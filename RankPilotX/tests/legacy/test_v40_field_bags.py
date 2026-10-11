"""Offline PS99 v4.0 placement and lootbag-particle tests; not live Roblox."""
from pathlib import Path
import ctypes
src=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
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
  r=lib.luaL_loadstring(L,code.encode());assert r==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  r=lib.lua_pcallk(L,0,0,0,0,None);assert r==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
placement=src[src.index('local function horizontalInside(part,point,margin)'):src.index('local function getGoalTitle(goal)')]
run(r'''
local function typeof(x) return type(x)=='table' and (x.__type or 'table') or type(x) end
local vmeta={}
vmeta.__index=function(t,k)if k=='Magnitude' then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z,__type='Vector3'},vmeta)end
vmeta.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
vmeta.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
Vector3={new=vec}
CFrame={new=function(v)return {Position=v,__type='CFrame'}end}
local teleports=0
local root=setmetatable({Position=vec(0,3,0)}, {__newindex=function(t,k,v)
 if k=='CFrame' then rawset(t,'Position',v.Position);teleports=teleports+1 end
 rawset(t,k,v)
end})
local function currentRoot()return root end
local field={__type='Instance',Position=vec(200,4,200),Size=vec(80,2,80)}
function field:IsA(x)return x=='BasePart'end
field.CFrame={Position=field.Position}
function field.CFrame:PointToObjectSpace(q)return vec(q.X-self.Position.X,q.Y-self.Position.Y,q.Z-self.Position.Z)end
local spawn={Main=field}
function spawn:FindFirstChild(name)return self[name]end
function spawn:IsA(name)return false end
function spawn:FindFirstChildWhichIsA()return nil end
local interact={BREAKABLE_SPAWNS=spawn}
function interact:FindFirstChild(name)return self[name]end
local folder={INTERACT=interact}
function folder:FindFirstChild(name)return self[name]end
local function matchZoneFolder(z)return folder end
local function zoneWorld(name)return 2 end
local function callMethod(...)return false,nil end
local function findChild(...)return nil end
local Workspace={}
local Config={AutoLoadBestArea=false,AutoZoneTeleports=false}
local state={world={number=2},clients={ZonesUtil={}},farmFieldRetries=0}
'''+placement+r'''
local zone={name='Dark Tech Forest',world=2}
local ok,reason=placeInZone(zone)
assert(ok,reason)
assert(horizontalInside(field,root.Position,0),'must land inside dotted breakable field')
assert(teleports==1 and state.farmFieldMethod=='BREAKABLE_SPAWNS.Main','must use actual spawn Main not road')
assert(state.farmFieldValidated==true)
local ok2=placeInZone(zone)
assert(ok2 and teleports==1,'repeat placement must not teleport if already inside field')
-- If Main cannot be found, do NOT return success from a gate/road teleport.
spawn.Main=nil
local old= root.Position
local ok3,why=placeInZone(zone)
assert(not ok3 and teleports==1,'do not pretend a missing farm field is a valid teleport')
print('PASS farm-field Main entry, bounded reposition, no road fallback')
''')
visual=src[src.index('local function setLootbagVisual(node,hide)'):src.index('-- Purely cosmetic. Roblox pet controller records')]
run(r'''
local function typeof(x)return type(x)=='table' and (x.__type or 'table') or type(x)end
local function now()return 150 end
local Config={HideLootbagVisuals=true,VisualRefreshSeconds=5}
local state={lootbagVisuals=setmetatable({},{__mode='k'}),lootbagHidden=0,
 lootbagVisualScannedAt=0,connections={},shutdown=false}
local function findChild(parent,name)return parent and parent[name]end
local effect={__type='Instance',Enabled=true}
function effect:IsA(name)return name=='ParticleEmitter'end
local template={__type='Instance',Name='Lootbags'}
function template:GetDescendants()return {effect}end
function template:GetChildren()return {effect}end
template.DescendantAdded={Connect=function(_,cb)return {Disconnect=function()end}end}
local Workspace={}
function Workspace:GetChildren()return {} end
local ReplicatedStorage={Assets={Particles={Lootbags=template}}}
'''+visual+r'''
refreshLootbagVisuals(true)
assert(effect.Enabled==false,'lootbag emitter prototype hidden')
assert(state.lootbagParticleSourceCount==1,'named PS99 lootbag prototype found')
assert(state.lootbagHidden>=1,'suppressed at least one visual element')
restoreLootbagVisuals()
assert(effect.Enabled==true,'original particle emitter restored')
print('PASS source-backed Lootbags particle suppression is reversible')
''')
assert 'DiamondWarmupSeconds = 5' in src
assert 'DiamondTravelCooldown = 8' in src
assert 'field-entry failures=' in src
print('PASS v4.0 scoped settings and diagnostics')
