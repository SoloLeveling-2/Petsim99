"""Offline Lua mocks for new v5.1 features. These DO NOT test the live PS99 server."""
from pathlib import Path
import ctypes,re
src=(Path(__file__).resolve().parents[2]/'dist'/'RankPilot_X_v5_2.lua').read_text()
assert 'AutoLoginStreak = false' in src and 'AutoTimedRewards = false' in src
assert 'AutoPopBalloons = false' in src
assert 'InfinitePetSpeed = true' in src
assert 'VYPersistentPetBulk = true' in src
assert 'local function extrasWorker(generation)' in src
assert 'task.spawn(function() extrasWorker(threadGeneration) end)' in src
assert 'AutoOpenMailbox' not in src
assert 'loadstring(game:HttpGet(' not in src
start=src.index('local function extraAlert(message)')
stop=src.index('local function getReport()',start)
features=src[start:stop]
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
def execute(lua):
    L=lib.luaL_newstate();lib.luaL_openlibs(L)
    try:
        rc=lib.luaL_loadstring(L,lua.encode());assert rc==0,(lib.lua_tolstring(L,-1,None) or b'').decode()
        rc=lib.lua_pcallk(L,0,0,0,0,None);assert rc==0,(lib.lua_tolstring(L,-1,None) or b'').decode()
    finally:lib.lua_close(L)

mock=r'''
local timestamp=1000
local function now()return timestamp end
local Config={LocalNotifications=true,AutoLoginStreak=true,AutoTimedRewards=true,AutoPopBalloons=true,
    AutoPlayerUpgrades=true,PlayerUpgradeSpendFraction=0.15,Fullbright=false,
    LoginCheckSeconds=75,TimedCheckSeconds=80,BalloonCheckSeconds=3,BalloonHitCooldown=1.5,
    BalloonSmall=true,BalloonMedium=true,BalloonHuge=true,LowLagMode=true}
local state={running=true,shutdown=false,rank=12,extras={loginLast='none',loginClaims=0,loginNext=0,
    timedLast='none',timedClaims=0,timedNext=0,balloonLast='none',balloonHits=0,balloonNext=0,
    balloonSeen={},slingshot=false,visuals=setmetatable({},{__mode='k'}),visualNext=0,
    visualHidden=0,lastRankAlert=nil,alerts={},playerUpgradeLast='none',playerUpgradeConfirmed=0,playerUpgradeNext=0}}
local requests={}
local modules={LoginStreakCmds={CanClaim=function()return true end}, RebirthCmds={Get=function()return 3 end}}
state.clients=modules
local beforeLogin=true
local canCount=0
modules.LoginStreakCmds.CanClaim=function()canCount=canCount+1;return beforeLogin end
local function callMethod(mod,func,...)
  if not mod or type(mod[func])~='function' then return false,'missing' end
  return pcall(mod[func],...)
end
local function cooldownReady()return true end
local function log()end
local function network(name,args,invoke)
 requests[#requests+1]={name=name,args=args,invoke=invoke}
 if name=='Login Streaks: Claim' then beforeLogin=false;return true,true end
 if name=='DailyRewards_Redeem' then inventory.TimedRewardTimestamps.DailyCoins=12000;return true,true end
 if name=='BalloonGifts_GetActiveBalloons' then return true,{
    {Id=77,Position=setmetatable({__type='Vector3',X=30,Y=0,Z=40},V3),BalloonTypeId='Huge Balloon',Popped=false}}
 end
 if name=='Slingshot_Equip' or name=='Slingshot_FireProjectile' or name=='Slingshot_Unequip' or name=='BalloonGifts_BalloonHit' then return true,true end
 return false,'missing'
end
inventory={Rank=12,Rebirths=3,Inventory={Pet={one={id='PetA',_am=4}},Potion={one={id='Lucky',_am=2}}},
   TimedRewardTimestamps={}}
local function saveData()return inventory end
local function movementAvailable()return true end
local function leaseMovement()return true end
local function clearMovement()end
local function typeof(v)return type(v)=='table' and v.__type or type(v) end
V3={}
V3.__index=function(self,k)
 if k=='Magnitude' then return math.sqrt(self.X*self.X+self.Y*self.Y+self.Z*self.Z) end
 return V3[k]
end
function V3.__sub(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},V3) end
Vector2={new=function(x,y) return {Magnitude=math.sqrt(x*x+y*y)} end}
local root={Position=setmetatable({__type='Vector3',X=0,Y=0,Z=0},V3),Parent=true,CFrame={}}
local function currentRoot()return root end
local function isfn()end
ReplicatedStorage={FindFirstChild=function()return nil end}
Workspace={FindFirstChild=function()return nil end,GetServerTimeNow=function()return 12000 end}
local light={Brightness=1,ClockTime=18,FogEnd=100,GlobalShadows=true,Ambient='old'}
game={GetService=function(_,service) if service=='Lighting' then return light end end}
Color3={fromRGB=function(r,g,b)return {r,g,b}end}
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local function obj(class)
  return {ClassName=class,Parent=true,FindFirstChild=function()return nil end,
    IsA=function(self,k)return k==class end,GetDescendants=function()return {} end}
end
local function assertRequest(name)
 for _,row in ipairs(requests) do if row.name==name then return true end end
 return false
end
task={wait=function()end}
'''
checks=r'''
assert(#state.extras.alerts==0)
assert(claimLoginStreak())
assert(state.extras.loginClaims==1)
assert(state.extras.loginLast=='confirmed claimed by CanClaim()')
assert(assertRequest('Login Streaks: Claim'))
assert(#state.extras.alerts==1)
timestamp=2000
assert(not claimLoginStreak())
assert(state.extras.loginClaims==1)
assert(inspectInventoryCounts():find('Pet 1 stacks / 4 items',1,true))
assert(inspectMinigameCapabilities()=='PS99 client folder missing')
local filtered=filteredBalloonList({
 {Id=1,Position={__type='Vector3'},BalloonTypeId='Huge Balloon'},
 {Id=2,Position={__type='Vector3'},BalloonTypeId='Small Balloon'},
 {Id=3,Position={__type='Vector3'},BalloonTypeId='Unrecognized'},
 {Id=4,Position={__type='Vector3'},BalloonTypeId='Huge Balloon',Popped=true},
})
assert(#filtered==2)
Config.BalloonSmall=false
assert(#filteredBalloonList({
 {Id=1,Position={__type='Vector3'},BalloonTypeId='Huge Balloon'},
 {Id=2,Position={__type='Vector3'},BalloonTypeId='Small Balloon'}
})==1)
assert(popBalloon())
assert(state.extras.balloonHits==1)
assert(assertRequest('Slingshot_Equip') and assertRequest('Slingshot_FireProjectile')
   and assertRequest('BalloonGifts_BalloonHit'))
-- Throttle repeat attempts on the same balloon.
assert(not popBalloon())
Config.AutoPopBalloons=false
assert(not popBalloon())
assert(assertRequest('Slingshot_Unequip'))
local vis={ClassName='BasePart',Parent=true,LocalTransparencyModifier=0,
  IsA=function(self,c)return c=='BasePart' end,GetDescendants=function()return {} end}
assert(visuallyHideTree(vis)==1)
assert(vis.LocalTransparencyModifier==1)
restoreAdditionalVisuals()
assert(vis.LocalTransparencyModifier==0)
-- Unready reward metadata must never fire any redemption remote.
local before=#requests
assert(not claimTimedReward())
assert(#requests==before)
-- A real locally loaded machine can be reached without changing position.
local pad={Position=setmetatable({__type='Vector3',X=2,Y=0,Z=0},V3),IsA=function(_,c)return c=='BasePart' end}
local model={__type='Instance',Parent=true,FindFirstChild=function(_,name)return name=='Pad' and pad or nil end}
state.clients.Directory={TimedRewards={DailyCoins={Cooldown=25,MachineName='DailyCoins'}}}
state.clients.MachineCmds={GetModels=function() return {model} end}
inventory.TimedRewardTimestamps.DailyCoins=10
timestamp=3000
assert(claimTimedReward())
assert(state.extras.timedClaims==1)
assert(state.extras.timedLast=='confirmed DailyCoins')
assert(assertRequest('DailyRewards_Redeem'))
Config.Fullbright=true
applyFullbright()
assert(light.Brightness==2 and light.ClockTime==12 and light.GlobalShadows==false)
Config.Fullbright=false
applyFullbright()
assert(light.Brightness==1 and light.ClockTime==18 and light.GlobalShadows==true)
-- Player upgrades must not spend more than the allowed fraction, nor try unknown costs.
state.clients.UpgradeCmds={All=function()return {{UpgradeID='Coins Power',ZoneID='Zone 1',UpgradeTier=1}} end,
  CanInteractWith=function()return true end,
  Purchase=function()error('must not be called without verified currency balance')end}
state.clients.Directory.Upgrades={['Coins Power']={TierCosts={[1]=50},TierCurrencies={[1]='Coins'}}}
state.clients.CurrencyCmds={Get=function()return 100 end} -- price 50 > 15% of balance
assert(not buyAffordablePlayerUpgrade())
assert(not assertRequest('Upgrade_Purchase'))
local purchased=false
state.clients.UpgradeCmds={
 All=function() return {{UpgradeID='Coins Power',ZoneID='Zone 1',UpgradeTier=purchased and 2 or 1}} end,
 CanInteractWith=function()return true end,
 Purchase=function()purchased=true;return true end
}
state.clients.CurrencyCmds.Get=function()return 1000 end -- cost 50 <= 15% of 1000
timestamp=4000
assert(buyAffordablePlayerUpgrade())
assert(state.extras.playerUpgradeConfirmed==1)
print('PASS v5.1: login, timed rewards, player upgrade budget + confirmation, balloons, visuals, inventory, fullbright')
'''
execute(mock+features+checks)
print('PASS full feature mock')
