"""Offline-only targeted behavioral test of diamond warm-up, travel throttling and cleanup."""
import ctypes
from pathlib import Path
src=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
lib=ctypes.CDLL('liblua5.4.so.0');lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p];lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
def run(code):
 L=lib.luaL_newstate();lib.luaL_openlibs(L)
 try:
  result=lib.luaL_loadstring(L,code.encode());assert result==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  result=lib.lua_pcallk(L,0,0,0,0,None);assert result==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
start=src.index('local function farm(goal)');end=src.index('-- Public-source egg lifecycle',start)
farmcode=src[start:end]
mock=r'''
math.clamp=function(a,b,c)return math.min(math.max(a,b),c)end
local clock=1000
local function now()return clock end
local logCount=0
local function log(...)logCount=logCount+1 end
local state={world={number=2,zone='Tech Spawn'},failures={},farmLastInterface='none',
 farmStats={empty=0},attempts={farm=0},lastFarm=0,diamondLastQuest=nil,diamondZone=nil,
 diamondZoneSince=0,diamondLastCredit=0,diamondLastCreditedAt=0,diamondLastTravelAt=-math.huge,
 diamondWarmupActions=0,diamondWarmupDiamonds=0,diamondMoveCount=0,diamondScoutCount=0,
 diamondArrivalAttempts=0,diamondArrivalFailures=0,
 diamondVisits={},diamondTravelGraceUntil=0,diamondPendingLoadUntil=0,
 farmReturnCount=0,farmReturnLast=0,lastSuccessfulAction=0}
local Config={AutoFarm=true,FarmTapRate=8,FastFarm=true,DiamondWarmupSeconds=5,
 DiamondWarmupMinActions=3,DiamondTravelCooldown=8,DiamondZoneDwell=10,
 DiamondStallSeconds=12,DiamondZoneRotation=true,DiamondVisitCooldown=22,
 FarmRadius=220,MaxCandidatesPerPass=80}
local function healthy(...)return true end
local function currentRoot()return {} end
local function movementAvailable(...)return true end
local function leaseMovement(...)return true end
local function clearMovement(...)end
local function cooldownReady(...)return false end
local function currentFarmZone()return state.farmZoneOverride or state.diamondZone or 'Tech Spawn' end
local function diamondAreas(...)return {} end
local moves,normalAttacks,diamondAttacks=0,0,0
local function nextDiamondArea()return {name='Zone '..tostring(moves+1),world=2}end
local startPositions=0
local function placeInZone(zone)
 if zone.name=='Tech Spawn' then startPositions=startPositions+1
 else moves=moves+1 end
 return true
end
local function farmingFieldPart(zone)return nil end
local function visibleTargetCandidates(kind)
 if kind=='diamond' then return {} end
 return {{uid='A1',model='fakeBreakable',distance=2}}
end
local function aimPetsAt(...)return true end
local function damageBreakable(target)normalAttacks=normalAttacks+1;return true end
local function getZoneInfo()return {name='Last',world=2}end
local function inHatchMovementWindow()return false end
local goal={kind='diamond',title='Break 450 diamond breakables',identity='DiamondGoal',progress=200}
'''
run(mock+farmcode+r'''
for t=1,5 do
 clock=1000+t
 assert(farm(goal)==true,'must attack ordinary breakables in a diamond-free zone')
end
assert(moves==0,'must stay to farm before first zone hop')
assert(normalAttacks>=5,'must farm normal breakables while seeking diamonds')
clock=1009;farm(goal)
assert(moves==1,'first visit should occur after actual breakable farming and warm-up')
clock=1011;farm(goal)
assert(moves==1,'must throttle repeat movement during new zone load')
assert(state.diamondZone=='Zone 1','current target zone should persist across ticks')
assert(state.diamondWarmupActions>0,'should farm ordinary objects in the new zone')
assert(state.farmReturnCount==0,'empty-scan return cannot override an active diamond route')
print('PASS diamond warm-up: ordinary farming, bounded visits, no repeated reposition')
''')
assert 'state.lootbagSourceCount=#sources' in src
assert 'findChild(Workspace,"__RENDERED")' in src
assert 'state.farmZoneOverride=wanted.name' not in src
assert 'state.diamondLastNormalFarm=' in src
print('PASS lootbag render discovery diagnostics and source-level farm-routing protections')
# A second isolated Lua mock covers bag graphics in __RENDERED rather than
# __THINGS.Lootbags. Previous builds only located __THINGS and hid zero objects.
start=src.index('local function setLootbagVisual(node,hide)')
end=src.index('local function restoreLootbagVisuals()',start)
run(r'''
local function typeof(x)return type(x)=='table' and x.__type or type(x)end
local clock=100
local function now()return clock end
local Config={HideLootbagVisuals=true,VisualRefreshSeconds=7}
local state={lootbagVisuals=setmetatable({},{__mode='k'}),lootbagHidden=0,
 lootbagVisualScannedAt=0,connections={},shutdown=false}
local function findChild(r,n)return r and r[n]end
local part={class='BasePart',LocalTransparencyModifier=0,Name='baggeom'}
function part:IsA(n)return n==self.class end
local bag={Name='Loot Bag Drop',children={part}}
function bag:GetChildren()return {} end
function bag:GetDescendants()return self.children end
bag.DescendantAdded={Connect=function(_,cb)return {Disconnect=function()end}end}
local render={Name='__RENDERED'}
function render:GetChildren()return {bag} end
local Workspace={__RENDERED=render}
local ReplicatedStorage={}
function Workspace:GetChildren()return {render}end
'''+src[start:end]+r'''
refreshLootbagVisuals(true)
assert(part.LocalTransparencyModifier==1,'render-root visual hidden')
assert(state.lootbagHidden==1 and state.lootbagSourceCount>=1,'bag renderer source detected')
assert(bag.children[1]==part,'bag object preserved for claim')
print('PASS lootbag discovery in separate render folder without deleting object')
''')
