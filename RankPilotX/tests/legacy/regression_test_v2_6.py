"""Offline-only functional tests. Never claims Roblox server compatibility."""
from pathlib import Path
import ctypes,re
p=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua'));s=p.read_text()
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
def run(code):
 L=lib.luaL_newstate();lib.luaL_openlibs(L)
 try:
  ret=lib.luaL_loadstring(L,code.encode());assert ret==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  ret=lib.lua_pcallk(L,0,0,0,0,None);assert ret==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
def snippet(a,b):return s[s.index('local function '+a+'('):s.index('local function '+b+'(')]
assert re.search(r'local state: any\s*=',s)
assert re.search(r'local Config: any\s*=',s)
assert 'state.hatchNeedsCoins and nil or goal' not in s
assert 'local chosenFarmGoal = goal' in s
assert 'local ok,_=callMethod(state.clients.PetCmds,"EquipBest")' in s
assert 'pcall(gethui)' in s and 'CoreGui:FindFirstChild' not in s
assert 'loadstring(game:HttpGet' not in s
print('PASS Luau lint repairs, scoped movement, and no remote UI loader')
run(r'''
local t=100
now=function()return t end
Config={AutoFarm=true,AutoCollectLootbags=true,AutoVending=false,AutoConsumables=true,
 AutoHatch=true,AutoEventItems=true,AutoWorld=true,AutoRebirth=false}
state={goals={},blocked={},failures={},eventFocus=nil,eventFocusUntil=0}
healthy=function()return true end
'''+snippet('eligible','farmPriority')+r'''
assert(eligible({kind='coinjar',identity='J'}) and eligible({kind='comet',identity='C'}))
assert(eligible({kind='collect_potion',identity='P'}))
''')
print('PASS item-spawn and collection quest eligibility')
run(r'''
local clock=100
math.clamp=function(n,lo,hi)return math.max(lo,math.min(hi,n))end
now=function()return clock end
local goal={identity='X',kind='collect_potion',progress=14,required=32,title='Collect potions'}
state={running=true,goals={goal},clients={},upgradePending=nil,upgradeNext=0,upgradeDisabled={},
 upgradeCount=0,collectionCredits=0,upgradeValidated={},upgradeLast='none',
 upgradeRejectedUIDs={},upgradeRejectedCount=0,upgradeVisitStart=0,upgradeVisitCompleted=0,
 logs={},cooldowns={},movementOwner=nil,movementUntil=0}
callMethod=function(...)return false,nil end
Config={AutoUpgradeCollections=true,AutoRank=true,AutoParallelQuests=true,
 UpgradeKeepReserve=10,UpgradeMaterialReserve=10,MaxUpgradeInputTier=3,UpgradePauseSeconds=170,UpgradeInterval=3,UpgradeVisitSeconds=24,UpgradeRejectedUIDCooldown=130}
math.clamp=function(x,a,b)return math.min(math.max(x,a),b)end
healthy=function()return true end
eligible=function()return true end
movementAvailable=function()return true end
leaseMovement=function()return true end
clearMovement=function()end
log=function()end
describe=tostring
cooldownReady=function()return true end
saveData=function()return {Inventory={Potion={A={id='Damage',tn=1,_am=50}},
 Enchant={B={id='Coins',tn=1,_am=70}}}} end
local v=setmetatable({},{__sub=function()return {Magnitude=0}end})
currentRoot=function()return {Position=v,CFrame='original'}end
loadedTechMachine=function()return {Position=v,CFrame='machine'}end
readGoals=function()return {goal}end
local requests={}
network=function(name,args,invoke)
 table.insert(requests,{name=name,args=args,invoke=invoke})
 return true,true
end
'''+snippet('collectionGoals','loadedTechMachine')+snippet('chooseLowTierUpgrade','popupIsAmount')+r'''
local i=chooseLowTierUpgrade(goal)
assert(i and i.id=='Damage' and i.ingredients==3,'item choice')
assert(tryCollectionUpgrade(),'upgrade request failed')
assert(#requests==1 and requests[1].name=='UpgradePotionsMachine_Activate')
assert(requests[1].args[2]==13 and requests[1].invoke==true) -- bulk outputs bounded by surplus
assert(state.upgradePending and state.upgradePending.before==14,'pending before')
clock=114
goal.progress=15
assert(not tryCollectionUpgrade())
assert(state.collectionCredits==1 and state.upgradeValidated.collect_potion,'credit unrecognized')
clock=118
assert(tryCollectionUpgrade(),'second upgrade returned false')
assert(requests[2].args[2]==13,'bulk request must respect input budget: '..tostring(requests[2].args[2]))
''')
print('PASS upgrade remote payload; server progress confirmation gates bigger batches')
run(r'''
local clock=100
math.clamp=function(n,lo,hi)return math.max(lo,math.min(hi,n))end
now=function()return clock end
local goal={identity='C',kind='collect_enchant',progress=3,required=18,title='Collect enchants'}
state={running=true,goals={goal},clients={},upgradePending=nil,upgradeNext=0,upgradeDisabled={},
 upgradeCount=0,collectionCredits=0,upgradeValidated={},upgradeLast='none',
 upgradeRejectedUIDs={},upgradeRejectedCount=0,upgradeVisitStart=0,upgradeVisitCompleted=0,
 logs={},cooldowns={},movementOwner=nil,movementUntil=0}
callMethod=function(...)return false,nil end
Config={AutoUpgradeCollections=true,AutoRank=true,AutoParallelQuests=true,
 UpgradeKeepReserve=10,UpgradeMaterialReserve=10,MaxUpgradeInputTier=3,UpgradePauseSeconds=170,UpgradeInterval=3,UpgradeVisitSeconds=24,UpgradeRejectedUIDCooldown=130}
healthy=function()return true end
eligible=function()return true end
movementAvailable=function()return true end
leaseMovement=function()return true end
clearMovement=function()end
log=function()end
describe=tostring
cooldownReady=function()return true end
saveData=function()return {Inventory={Enchant={B={id='Coins',tn=1,_am=70}}}}end
local v=setmetatable({},{__sub=function()return {Magnitude=0}end})
currentRoot=function()return {Position=v,CFrame='original'}end
loadedTechMachine=function()return {Position=v,CFrame='machine'}end
readGoals=function()return {goal}end -- simulates an uncredited quest
network=function(name,args,invoke)
 assert(name=='UpgradeEnchantsMachine_Activate' and args[2]==12)
 return true,true
end
'''+snippet('collectionGoals','loadedTechMachine')+snippet('chooseLowTierUpgrade','popupIsAmount')+r'''
assert(tryCollectionUpgrade())
clock=114
assert(not tryCollectionUpgrade())
assert(state.collectionCredits==0)
assert(state.upgradeDisabled.C>clock)
clock=140
assert(not tryCollectionUpgrade())
''')
print('PASS uncredited enchant upgrades enter cooldown instead of blindly spending again')
run(r'''
Config={HidePickupPopups=true}
Workspace={}
LocalPlayer={FindFirstChild=function()return nil end}
state={popupRecords=setmetatable({},{__mode='k'}),popupHidden=0}
local function gui(name,text)
 local g={Name=name,Enabled=true,Parent={Name='GainEffects'}}
 function g:IsDescendantOf(root) return root==Workspace end
 function g:GetChildren()return {}end
 function g:IsA(k)return k=='BillboardGui'end
 function g:GetDescendants()
  local label={Text=text}
  function label:IsA(k)return k=='TextLabel'end
  local icon={}
  function icon:IsA(k)return k=='ImageLabel'end
  return {label,icon}
 end
 return g
end
'''+snippet('popupIsAmount','refreshPopups')+r'''
local popup=gui('Floating','+123k')
local quest=gui('QuestBadge','Rank 14')
assert(popupLooksLikePickup(popup))
assert(not popupLooksLikePickup(quest))
suppressPopup(popup)
assert(popup.Enabled==false and state.popupHidden==1)
assert(quest.Enabled==true)
''')
print('PASS local popup detection does not remove normal quest GUI; visual-only toggling')
assert 'task.spawn(function() eventWorker(threadGeneration) end)' in s
assert 'task.spawn(function() upgradeWorker(threadGeneration) end)' in s
assert 'AutoEventItems = true' in s and 'AutoUpgradeCollections = true' in s
print('PASS concurrent event / upgrade workers; upgrade toggle enabled on fresh v2.7 settings, bounded by reserve')
run(r'''
local clock=100
now=function() return clock end
local goal={kind='coinjar',identity='CJ1',title='Break 4 coin jars in best area'}
state={lastEventItem=0,spawnPending={},spawnActions=0,commandCount=0,
 eventFocus=nil,eventFocusUntil=0,activeGoalTitle=nil}
Config={AutoEventItems=true,SpawnItemSeconds=14}
itemTypes={coinjar={match='Coin Jar',remote='CoinJar_Spawn'}}
healthy=function() return true end
movementAvailable=function()return true end
leaseMovement=function()return true end
clearMovement=function()end
visibleTargetCandidates=function()return {} end
getZoneInfo=function()return {name='Void Fracture'} end
placeInZone=function()return true end
getInventoryEntry=function(section,match)
 assert(section=='Misc' and match=='Coin Jar')
 return {uid='UID-123',id='Basic Coin Jar'}
end
local calls={}
network=function(remote,args,invoke)
 table.insert(calls,{remote=remote,uid=args[1],invoke=invoke})
 return true,true
end
currentRoot=function()return nil end
inHatchMovementWindow=function()return false end
describe=tostring
log=function()end
cooldownReady=function()return true end
'''+snippet('spawnQuestObject','collectionGoals')+r'''
assert(spawnQuestObject(goal)==true)
assert(#calls==1 and calls[1].remote=='CoinJar_Spawn')
assert(calls[1].uid=='UID-123' and calls[1].invoke==true)
assert(state.eventFocus=='CJ1' and state.spawnActions==1)
clock=103
assert(spawnQuestObject(goal)==false)
assert(#calls==1,'cannot spend another jar during pending window')
''')
print('PASS coin jar spawn uses real inventory UID, one source-backed request, and cooldown')
print('OFFLINE ONLY: live server responses and visual popup names still need verification')
