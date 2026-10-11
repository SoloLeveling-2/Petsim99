"""RankPilot v4.6: isolated Lua mocks of adapted VY code. No Roblox executor."""
from pathlib import Path
import ctypes, re
S=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
def execute(code):
 l=lib.luaL_newstate();lib.luaL_openlibs(l)
 try:
  r=lib.luaL_loadstring(l,code.encode());assert r==0,(lib.lua_tolstring(l,-1,None)or b'').decode()
  r=lib.lua_pcallk(l,0,0,0,0,None);assert r==0,(lib.lua_tolstring(l,-1,None)or b'').decode()
 finally:lib.lua_close(l)
def section(a,b): return S[S.index(a):S.index(b,S.index(a))]
compatible=re.sub(r'(?m)(\blocal\s+\w+)\s*:\s*(?:any|number\??|string\??|boolean\??)',r'\1',S)
execute('assert(load(' + repr(compatible) + ') ~= nil)') if False else None
l=lib.luaL_newstate()
try:
 assert lib.luaL_loadstring(l,compatible.encode())==0,(lib.lua_tolstring(l,-1,None)or b'').decode()
finally:lib.lua_close(l)
print('PASS full source Lua 5.4-compatible syntax parse')

speed=section('local function petTurbo(enable)','local function updateSuperMagnet(enable)')
execute(r'''
local captured
local function hookfunction(original,closure) captured=closure;return original end
local function now()return 50 end
local state={running=true,shutdown=false,clients={PlayerPet={CalculateSpeedMultiplier=function()return 2 end}}}
local Config={PetTurbo=true,InfinitePetSpeed=true,PetSpeedMultiplier=8}
'''+speed+r'''
assert(petTurbo(true))
assert(state.clients.PlayerPet.CalculateSpeedMultiplier()==math.huge)
assert(captured() == math.huge)
state.running=false
assert(captured()==2)
assert(petTurbo(false))
assert(state.clients.PlayerPet.CalculateSpeedMultiplier()==2)
print('VY exact infinity preserved, paused hook uses original, module restored')
''')
print('PASS exact math.huge hook + reversible pause/stop path')

bulk=section('local function vyOwnedPetIDs()','local function aimPetsAt(target, targets, kind)')
execute(r'''
local stamp=100
local function now()return stamp end
local function typeof(v) return type(v) end
local LocalPlayer={}
local records={{euid='a'},{euid='b'},{euid='c'},{euid='d'}}
local state={running=true,shutdown=false,clients={PlayerPet={GetByPlayer=function(_)return records end}},
 vyPetBulkSkipped=0,vyLastPetBulk=0,vyPetAssignment={},vyLastPetZone=nil,
 vyPetBulkSent=0,vyPetBulkFailed=0,vyPetBulkLast='none'}
local Config={VYPersistentPetBulk=true,VYBulkSeconds=1,MaxPetsPerTick=4}
local function callMethod(t,m,...)return true,t[m](...) end
local function currentFarmZone() return 'Glitch Skyscrapers' end
local received={}
local function network(name,args,invoke)
 assert(name=='Breakables_JoinPetBulk' and invoke==false)
 received[#received+1]=args[1]
 return true,true
end
'''+bulk+r'''
local t1={uid='u1',model={}}
local t2={uid='u2',model={}}
assert(vyBulkAssign({t1,t2},'farm',false)==true)
assert(#received==1)
local first=received[1]
assert(first.a=='u1' and first.b=='u2' and first.c=='u1')
stamp=100.2
assert(vyBulkAssign({t1,t2},'farm',false)=='cooldown')
assert(#received==1)
stamp=102
assert(vyBulkAssign({t2},'farm',false)==true)
assert(received[2].a=='u2' and received[2].b=='u2')
assert(state.vyPetBulkSent==2 and state.vyPetBulkSkipped==1)
print('Stable pet assignments, cooldown and stale target replacement')
''')
print('PASS VY persistent pet map + cooldown')

listener=section('local function vyInstallEventListener()','local function farm(goal)')
execute(r'''
local callback
local task={defer=function(f)f()end}
local folder={ChildAdded={Connect=function(_,fn)callback=fn;return {Disconnect=function()end}end}}
local function getBreakables()return folder end
local state={running=true,shutdown=false,hatchExclusive=false,vyBreakableListenerBound=false,
 vyBreakableListenerStatus='init',connections={},goals={{kind='coinjar',title='Break 3 coin jars'}},
 vyEventBreakables=0,vyEventBulkActions=0,scannedKey='old',lastTargetScan=1}
local Config={VYInstantEvents=true,VYPersistentPetBulk=true}
local function currentFarmZone()return 'Glitch Skyscrapers' end
local function eligible(g)return true end
local function matchesQuestBreakable(kind,meta,title) return kind=='coinjar' and meta.id:find('jar')~=nil end
local function vyBulkAssign(t,k,instant) assert(instant and k=='event');return true end
local function cooldownReady()return true end
local function log()end
'''+listener+r'''
assert(vyInstallEventListener()==nil)
assert(type(callback)=='function')
local obj={Parent={},Name='item',IsA=function(self,name)return name=='Model' end,
 GetAttribute=function(self,name)
 if name=='ParentID' then return 'Glitch Skyscrapers' end
 if name=='BreakableID' then return 'Basic Coin Jar' end
 if name=='BreakableUID' then return 123 end
 return nil end}
callback(obj)
assert(state.vyEventBreakables==1 and state.vyEventBulkActions==1)
assert(state.scannedKey=='')
state.hatchExclusive=true
callback(obj)
assert(state.vyEventBreakables==1)
print('Event listener triggers once; does not interrupt hatching')
''')
print('PASS VY event ChildAdded fast path + hatch priority')

travel=section('local function vyQueueLocalReexecution()','local function tryAdvanceWorld()')
execute(r'''
local stamp=100
local function now()return stamp end
local queued=nil
local function queue_on_teleport(payload) queued=payload end
local function isfile(name)return name=='RankPilot_PS99_VY_v4_6.lua' end
local function readfile()return 'return true' end
local function loadstring(src) return function()end end
local state={vyWorldQueued=false,vyWorldTravelAt=-math.huge,world={number=2},vyWorldTravelLast='none'}
local Config={VYWorldTravel=true,VYLocalWorkspaceFile='RankPilot_PS99_VY_v4_6.lua',VYWorldTravelCooldown=90}
local function network(name,args,invoke) assert(name=='World3Teleport' and invoke==true);return true,true end
'''+travel+r'''
assert(vyTravelWorld(3))
assert(queued and queued:find('readfile',1,true))
assert(state.vyWorldQueued)
assert(not vyTravelWorld(3),'throttled cross-world call')
print('World travel queues only local source, with bounded cooldown')
''')
print('PASS local-workspace world re-execution path')

for sig in ['VY persistent bulk pet assignments','VY distribute pets across targets','VY immediate special-breakable targeting','VY infinite pet speed (math.huge)','VY cross-world teleport + local reload']:
 assert sig in S,sig
print('PASS new settings exposed in organized UI')
