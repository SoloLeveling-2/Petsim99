"""Source-derived isolated functional mocks. Does NOT run Roblox client/server."""
from pathlib import Path
import ctypes,re
S=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
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
def section(a,b):return S[S.index(a):S.index(b,S.index(a))]
compatible=re.sub(r'(?m)(\blocal\s+\w+)\s*:\s*(?:any|number\??|string\??|boolean\??)',r'\1',S)
L=lib.luaL_newstate()
try:
 assert lib.luaL_loadstring(L,compatible.encode())==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
finally:lib.lua_close(L)
print('PASS v4.5 whole-script Lua 5.4 syntax compatible parse')
# Exercise targeted pet reassignment with actual extracted implementation.
petcode=section('local function aimPetsAt(target, targets, kind)','local function damageBreakable(target)')
run(r'''
local clock=100
local function now()return clock end
local calls=0
local function typeof(v)return type(v) end
local modelA={}
local modelB={}
local pets={}
for i=1,55 do
  local pet={SetTarget=function(self,target) calls=calls+1 end}
  pets[#pets+1]=pet
end
local state={lastPetAssign=0,lastAssignedTarget=nil,petTargetCommands=0,petTargetSkipped=0,
 clients={PlayerPet={GetByPlayer=function(_)return pets end}}}
local Config={PetAssignSeconds=2.6,PetTargetMaxAge=8,SpreadPets=false,MaxPetsPerTick=55}
local LocalPlayer={}
local function callMethod(tbl,method,...)
 return true,tbl[method](...)
end
local function network()return false end
'''+petcode+r'''
assert(aimPetsAt({uid='A',model=modelA},nil,'farm'))
assert(calls==55)
clock=100.2
assert(not aimPetsAt({uid='B',model=modelB},nil,'farm'),'do not redirect 55 pets on every 0.2s tick')
clock=103
assert(aimPetsAt({uid='B',model=modelB},nil,'farm'))
assert(calls==110,'two actual target allocations, not dozens')
clock=105
assert(not aimPetsAt({uid='B',model=modelB},nil,'farm'))
assert(state.petTargetCommands==110 and state.petTargetSkipped==2)
''')
print('PASS 55-pet reassignment throttled even when target changes every farm tick')
# Extract source collection worker. Claim payload must be an ARRAY of IDs, not dictionary.
collector=section('local function collectDrops()','-- Observe claimable lootbag IDs')
run(r'''
local stamp=100
local function now()return stamp end
local bag={Name='loot_uid_1'}
local orb={Name='12345'}
local function folder(contents)return {GetChildren=function()return contents end}end
local workspace={__THINGS={Lootbags=folder({bag}),Orbs=folder({orb})}}
local function findChild(root,key)return root and root[key]end
local state={lastCollector=0,claimSeen={},lootClaims=0,orbClaims=0,
 lootbagClaimAttempts=0,lootbagClaimErrors=0}
local Config={CollectionSeconds=1.8,CollectionBatch=35,
 AutoCollectLootbags=true,AutoCollectOrbs=true}
local requests={}
local function network(name,args,invoke)
 assert(type(args)=='table' and type(args[1])=='table')
 local ids=args[1]
 if name=='Lootbags_Claim' then
  assert(#ids==1 and ids[1]=='loot_uid_1','lootbag claim must contain LIST of actual bag UIDs')
 elseif name=='Orbs: Collect' then
  assert(#ids==1 and ids[1]==12345,'orb claim number preserved')
 else error('unexpected remote '..name) end
 requests[#requests+1]=name
 return true,true
end
local function cooldownReady()return false end
local function log()end
local function describe(s)return tostring(s)end
local Workspace=workspace
'''+collector+r'''
collectDrops()
assert(state.orbClaims==1 and state.lootClaims==1)
assert(state.lootbagClaimAttempts==1 and state.lootbagClaimErrors==0)
assert(#requests==2)
collectDrops() -- bounded by collector cooldown
assert(#requests==2)
''')
print('PASS source lootbag UID array, orb IDs, no repeat claim burst')
# Subject to live verification, but avoids the 250x client movement hot loop.
for token in ['PetSpeedMultiplier = 8,','FarmTargetHoldSeconds = 3.0',
              'VisualRefreshSeconds = 90','TargetStabilityVersion = 1',
              'Config.LowLagMode and 7 or 16','state.farmProgressObserved']:
 assert token in S,token
print('PASS migration, low-overhead defaults and real quest-credit diagnostics')
