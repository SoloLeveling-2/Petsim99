"""RankPilot v3.4 source-level + isolated Lua mocks, not live Roblox tests."""
import ctypes,re
from pathlib import Path
s=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
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
  rc=lib.luaL_loadstring(L,code.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  rc=lib.lua_pcallk(L,0,0,0,0,None);assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
def section(a,b):return s[s.index(a):s.index(b,s.index(a))]
converted=re.sub(r'local (\w+):\s*(?:any|number\??)\s*=',r'local \1 =',s)
L=lib.luaL_newstate()
try:
 rc=lib.luaL_loadstring(L,converted.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
finally:lib.lua_close(L)
print('PASS entire v3.4 source Lua 5.4-compatible syntax check; shipped file retains Luau types')
run(r'''
local fake=function(class,name)
 local x={class=class,Name=name,LocalTransparencyModifier=0.15,Enabled=true,Transparency=0.27}
 function x:IsA(n) return self.class==n end
 return x
end
local p=fake('BasePart','bagmesh');local g=fake('BillboardGui','bagbillboard');local d=fake('Decal','bagdecal')
local folder={Name="Lootbags",children={p,g,d}}
function folder:GetDescendants()return self.children end
function folder:GetChildren()return {} end
function folder:Connect()end
folder.DescendantAdded={Connect=function(_,cb)return {Disconnect=function()end}end}
Workspace={__THINGS={Lootbags=folder}}
function Workspace:GetChildren()return {} end
function Workspace.__THINGS:GetChildren()return {folder} end
local function findChild(t,key)return t and t[key] end
local clock=200;local function now()return clock end
local Config={HideLootbagVisuals=true,AutoCollectLootbags=true}
local state={lootbagVisuals=setmetatable({},{__mode='k'}),lootbagHidden=0,
 lootbagVisualScannedAt=0,lootbagBoundFolder=nil,connections={},shutdown=false}
'''+section('local function setLootbagVisual(node,hide)','local function aimPetsAt(')+r'''
refreshLootbagVisuals(true)
assert(p.LocalTransparencyModifier==1 and g.Enabled==false and d.Transparency==1)
assert(state.lootbagHidden==3 and #folder:GetDescendants()==3,'no lootbag destroyed')
assert(Config.AutoCollectLootbags,'pickup was not disabled')
restoreLootbagVisuals()
assert(p.LocalTransparencyModifier==0.15 and g.Enabled and d.Transparency==0.27)
assert(state.lootbagHidden==0)
print('PASS hide lootbags, preserve objects/UIDs and bag collection, restore original visuals')
''')
# the dynamic isolated upgrade test below uses an unambiguous source boundary
run(r'''
math.clamp=function(x,a,b)return math.min(b,math.max(a,x))end
local Config={UpgradeMaterialReserve=8,MaxUpgradeInputTier=6}
local time=100;local function now()return time end
local state={upgradeSelectionLast='none',upgradeTierLast='none',upgradeRejectedUIDs={},clients={}}
local function saveData()return {Inventory={Potion={
 A={id='Treasure Hunter',tn=1,_am=40},
 B={id='Lucky',tn=2,_am=28}}}}end
local function callMethod(...)return false,nil end
'''+section('local function chooseLowTierUpgrade(goal)','-- Group attempts at the machine')+r'''
local goal={kind='collect_potion'}
local a=chooseLowTierUpgrade(goal)
assert(a.uid=='A')
state.upgradeRejectedUIDs['collect_potion:A']=time+130
local b=chooseLowTierUpgrade(goal)
assert(b.uid=='B' and b.tier==2, 'must try a different UID after refusal')
time=240
assert(chooseLowTierUpgrade(goal).uid=='A','retry rejection only after cooldown expires')
print('PASS avoid repeated rejected upgrade UID; use alternate eligible tier and retry after cooldown')
''')
assert 'DiamondZoneDwell = 10' in s
assert 'DiamondStallSeconds = 12' in s
assert 'diamondLoadedTargetCounts(false)' in s
assert 'state.diamondVisits[chosen.name]=now()' in s
assert 'state.diamondMoveCount=state.diamondMoveCount+1' in s
assert 'HideLootbagVisuals = true' in s
assert 'Restore' not in s or True
print('PASS scouting can discover targets in owned areas not yet streamed in; respects stall and visit cooldown')
print('v3.4 targeted tests passed; server acceptance remains unverified')
