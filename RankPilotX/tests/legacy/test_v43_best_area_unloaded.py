"""v4.3 Lua behavioral tests for unloaded best area + fast nearly-complete quest priority.
Uses an isolated Lua 5.4 mock, not live Roblox.
"""
import ctypes
from pathlib import Path
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
  x=lib.luaL_loadstring(L,code.encode());assert x==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  x=lib.lua_pcallk(L,0,0,0,0,None);assert x==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
part=src[src.index('local function horizontalInside(part,point,margin)'):src.index('local function getGoalTitle(goal)')]
mock=r'''
local t=100
local function now()return t end
local function typeof(v)return type(v)=='table' and (v.__type or 'table') or type(v)end
local vm={}
vm.__index=function(x,k) if k=='Magnitude' then return math.sqrt(x.X*x.X+x.Y*x.Y+x.Z*x.Z)end end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z,__type='Vector3'},vm)end
vm.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
vm.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
Vector3={new=vec}
local cfm={}
cfm.__index=cfm
cfm.__add=function(a,b)return setmetatable({Position=a.Position+b,__type='CFrame'},cfm)end
CFrame={new=function(p)return setmetatable({Position=p,__type='CFrame'},cfm)end}
function cfm:PointToObjectSpace(p)return p-self.Position end
local moves=0
local r={Position=vec(0,4,0)}
local root=setmetatable(r,{__newindex=function(tb,k,v)
 if k=='CFrame' then rawset(tb,'Position',v.Position);moves=moves+1;return end
 rawset(tb,k,v)
end})
local function currentRoot()return root end
local Config={AutoLoadBestArea=true,AutoZoneTeleports=false}
local state={world={number=2},clients={ZonesUtil={GetTeleportPartLocation=function()return CFrame.new(vec(500,4,60))end},ZoneCmds={Owns=function()return true end}},farmFieldRetries=0}
local function getZoneInfo()return {name='Glitch Skyscrapers',world=2}end
local function zoneWorld(name)return 2 end
local function callMethod(tb,name,...)
 if not tb or not tb[name] then return false,'missing' end
 return pcall(tb[name],...)
end
local function findChild(parent,name)return parent and parent[name] end
local Workspace={}
local loaded=false
local field={Position=vec(503,4,60),Size=vec(70,2,70),CFrame=CFrame.new(vec(503,4,60))}
function field:IsA(k)return k=='BasePart'end
local spawns={Main=field}
function spawns:FindFirstChild(k)return self[k]end
function spawns:IsA()return false end
local interact={BREAKABLE_SPAWNS=spawns}
function interact:FindFirstChild(k)return self[k] end
local folder={INTERACT=interact}
function folder:FindFirstChild(k)return self[k] end
local function matchZoneFolder(z)return loaded and folder or nil end
local native=0
local function network(name,args,invoke)
 assert(name=='Teleports_RequestTeleport' and args[1]=='Glitch Skyscrapers' and invoke)
 native=native+1;return true,true
end
'''
run(mock+part+r'''
local goal={name='Glitch Skyscrapers',world=2}
local first,reason=placeInZone(goal)
assert(not first and moves==1, 'must teleport toward unloaded BEST zone first')
assert(state.bestAreaAnchorMoves==1)
assert(root.Position.X==500)
-- Area loaded after arriving; now choose the actual spawn box.
loaded=true;t=t+1
local second,why=placeInZone(goal)
assert(second,why)
assert(state.farmFieldValidated and state.farmFieldLast:find('Inside Glitch Skyscrapers',1,true))
assert((state.bestAreaNativeRequests or 0)==0)
assert(moves<=2,'unnecessary travel loop')
print('PASS unloaded best-zone anchor -> actual field after streaming')
''')
run(mock+part+r'''
local goal={name='Glitch Skyscrapers',world=2}
local first=placeInZone(goal)
assert(not first)
t=t+4
local second=placeInZone(goal)
assert(not second and native==1, 'native teleport fallback must be attempted once after streaming grace')
t=t+3
local third=placeInZone(goal)
assert(not third and native==1,'native teleport calls must be rate limited')
print('PASS delayed game teleport request, no spam')
''')
priority=src[src.index('local function farmPriority(g)'):src.index('-- Mini-chests and superior mini-chests')]
run('''
local scores={farm=98,minichest=62,coinjar=56}
local Config={PreferHighStars=true,StarPriorityWeight=12}
local function starValue(g)return g.stars end
'''+priority+'''
local nearly={kind='farm',title='Break 27 breakables in best area',required=1350,progress=1323,stars=1}
local chest={kind='minichest',title='Break 5 mini-chests in best area',required=5,progress=0,stars=4}
assert(farmPriority(nearly)>farmPriority(chest),'finishing 27 breakables must outrank chest waiting')
print('PASS nearly-complete best-area farm prioritized before 4-star chest')
''')
print('All v4.3 targeted tests passed')
