"""RankPilot v4.1 targeted offline behavior checks; Roblox live behavior unverified."""
from pathlib import Path
import ctypes,re
s=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
lib=ctypes.CDLL('liblua5.4.so.0');lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
def run(code):
 L=lib.luaL_newstate();lib.luaL_openlibs(L)
 try:
  a=lib.luaL_loadstring(L,code.encode());assert a==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  b=lib.lua_pcallk(L,0,0,0,0,None);assert b==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
def section(a,b):return s[s.index(a):s.index(b,s.index(a))]
# Hatching is permitted to produce gold-quest inputs; when enough exist stop.
run(r'''
local Config={AutoHatchAlways=false,AutoHatchForGold=true,AutoGoldConversion=true,
 AutoHatchForRainbow=true,AutoRainbowConversion=true,AutoGoldForRainbow=true,
 ConversionPetReserve=10}
local state={goals={}}
local function readGoals(data)return data.Goals end
local function saveData()return nil end
local function bestEggPetSpecies()return {TechPet=true},{}end
local function activeBestEggRainbowQuest()return nil end
local function rainbowHasCraftMaterials()return false end
'''+section('local function hatchIntended(data)','-- DZ Hub\'s no-animation')+r'''
local goal={kind='convert',title='Make golden pets from best egg',progress=0,required=20}
local data={Goals={goal},Inventory={Pet={}}}
local yes,why=hatchIntended(data)
assert(yes and why=='gold best-egg materials','should hatch when no best-egg regular pets')
data.Inventory.Pet.A={id='TechPet',_am=30,pt=0}
yes,why=hatchIntended(data)
assert(not yes,'should stop hatching when conversion input is available')
print('PASS GOLD best-egg material hatch auto starts/stops without AlwaysHatch')
''')
# When the scout goes dry for multiple zones, defer high-star diamond goal and do alternate goal.
run(r'''
math.clamp=function(x,a,b)return math.min(math.max(x,a),b)end
local clock=1000
local function now()return clock end
local function log(...)end
local goal={kind='diamond',title='Break 450 diamond breakables',identity='diamond-quest',progress=200}
local secondary={kind='farm',title='Break 1350 breakables in best area',identity='normal-quest',progress=100}
local state={world={number=2,zone='Tech Spawn'},blocked={},goals={goal,secondary},
 attempts={farm=0},farmStats={empty=0},lastFarm=0,lastAssignedTarget='',lastPetAssign=0,
 diamondLastQuest=nil,diamondZone=nil,diamondZoneSince=0,diamondLastCredit=0,
 diamondLastCreditedAt=0,diamondLastTravelAt=-math.huge,diamondWarmupActions=0,
 diamondWarmupDiamonds=0,diamondMoveCount=0,diamondScoutCount=0,
 diamondArrivalAttempts=0,diamondArrivalFailures=0,diamondVisits={},
 diamondTravelGraceUntil=0,diamondPendingLoadUntil=0,diamondDryZoneVisits=0,
 farmReturnCount=0,farmReturnLast=0,lastSuccessfulAction=0}
local Config={AutoFarm=true,FarmTapRate=8,FastFarm=true,DiamondWarmupSeconds=5,
 DiamondWarmupMinActions=3,DiamondTravelCooldown=8,DiamondZoneDwell=10,
 DiamondStallSeconds=12,DiamondZoneRotation=true,DiamondVisitCooldown=22,
 FarmRadius=220,MaxCandidatesPerPass=80}
local function eligible(q)return true end
local function healthy(...)return true end
local function currentRoot()return {} end
local function movementAvailable(...)return true end
local function leaseMovement(...)return true end
local function clearMovement(...)end
local function cooldownReady(...)return false end
local function currentFarmZone()return state.farmZoneOverride or state.diamondZone or 'Tech Spawn' end
local function diamondAreas(...)return {} end
local moves,attacks=0,0
local function nextDiamondArea()return {name='Scout Zone '..tostring(moves+1),world=2}end
local function placeInZone(zone)if zone.name~='Tech Spawn' then moves=moves+1 end return true end
local function farmingFieldPart(zone)return nil end
local function visibleTargetCandidates(kind)
 if kind=='diamond' then return {} end
 return {{uid='A1',model='fakeBreakable',distance=2}}
end
local function aimPetsAt(...)return true end
local function damageBreakable(t)attacks=attacks+1;return true end
local function getZoneInfo()return {name='Last',world=2}end
local function inHatchMovementWindow()return false end
'''+section('local function farm(goal)','-- Public-source egg lifecycle')+r'''
for t=1,65 do
 clock=1000+t
 farm(goal)
 if (state.diamondDryDeferrals or 0)>=1 then break end
end
assert(attacks>=15,'scouting must farm ordinary objects while dry')
assert(moves>=3,'dry scouting must switch zones more than twice')
assert(state.diamondDryDeferrals>=1,'repeated dry visits must defer the diamond quest')
assert(state.diamondLastCreditedAt==1001,'scouting moves must never reset actual credit timestamp')
print('PASS diamond warm-up, fast zoned scouting, 3 dry visit deferral, no false credit resets')
''')
# Local yellow FX visual (non-destructive), reversible and avoids a whole workspace traversal.
visual=section('local function setLootbagVisual(node,hide)','-- Purely cosmetic. Roblox pet controller records')
run(r'''
local clock=200
local function now()return clock end
local Config={HideLootbagVisuals=true,HideYellowBagFX=true,VisualRefreshSeconds=5}
local state={lootbagVisuals=setmetatable({},{__mode='k'}),lootbagHidden=0,
 lootbagYellowHidden=0,lootbagVisualScannedAt=0,connections={},shutdown=false}
local function findChild(root,n)return root and root[n]end
local object={Name='FXGenerated',Transparency=0,LocalTransparencyModifier=0,
 Color={R=1,G=0.8,B=0.05}, Size={X=2,Y=2,Z=2}}
function object:IsA(kind)return kind=='MeshPart' or kind=='BasePart'end
local debris={Name='__DEBRIS'}
function debris:GetChildren()return {object}end
local Workspace={__DEBRIS=debris}
function Workspace:GetChildren()return {debris}end
local ReplicatedStorage={}
'''+visual+r'''
refreshLootbagVisuals(true)
assert(object.Transparency==1 and object.LocalTransparencyModifier==1,'client yellow bag hidden')
assert(state.lootbagYellowHidden==1,'bag found in generic FX root')
restoreLootbagVisuals()
assert(object.Transparency==0 and object.LocalTransparencyModifier==0,'bag visual fully restored')
print('PASS bounded yellow bag hiding and transparency restoration, model preserved')
''')
print('OFFLINE ONLY: no claims of Roblox/Potassium API compatibility')
