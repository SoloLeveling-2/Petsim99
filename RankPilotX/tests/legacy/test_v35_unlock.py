"""Mocked source-extracted World 2 egg eligibility + unlock + hatch flow. Not live PS99."""
from pathlib import Path
import re,ctypes
s=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_close.argtypes=[ctypes.c_void_p]
def run(code):
    L=lib.luaL_newstate();lib.luaL_openlibs(L)
    try:
        rc=lib.luaL_loadstring(L,code.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
        rc=lib.lua_pcallk(L,0,0,0,0,None);assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
    finally:lib.lua_close(L)
def section(start,end):
    return s[s.index(start):s.index(end,s.index(start))]
converted=re.sub(r'local (\w+):\s*(?:any|number\??)\s*=',r'local \1 =',s)
L=lib.luaL_newstate()
try:
    rc=lib.luaL_loadstring(L,converted.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
finally:lib.lua_close(L)
print('PASS Lua 5.4 compatible entire-source parse; shipped Luau annotations preserved')
mock=r'''
local clock=100
local function now()return clock end
local function describe(v)return tostring(v)end
local function log()end
local function cooldownReady()return true end
local save={RecentWorld=2,MaximumAvailableEgg=204,PurchasedEggs={},UnlockedEggs={},EggsHatched=835928}
local function saveData()return save end
local calls={}
local function network(name,args,invoke)
  calls[#calls+1]={name=name,args=args}
  if name=='Eggs_RequestUnlock' then return true,true end
  if name=='Eggs_RequestPurchase' then return true,true end
  return false,'unknown'
end
local function callMethod(tbl,name,...)
 if type(tbl)~='table' or type(tbl[name])~='function' then return false,nil end
 return pcall(tbl[name],...)
end
local state={clients={EggCmds={IsUnlocked=function()return false end}},world={number=2},
 eggUnlockNext=0, eggUnlockRequests=0,eggUnlockLast='none',eggUnlockStatus='none',
 eggUnlockSource='none',eggUnlockSuccess=0,eggWorldModuleCount=0,eggWorldUnlockedCount=0,
 attempts={hatch=0},lastHatch=0,hatchRetryAt=0,hatchNoProgress=0,hatchRefusals=0,
 hatchLastConfirmedAt=0,hatchLastResult='none'}
local Config={AutoHatch=true,HatchActionSeconds=.85,MaxHatchBatch=100}
local function healthy()return true end
local function observeHatchProgress()end
local function currentRoot()return{Position={}}end
math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
local function mkModule(data)
 local o={data=data}
 function o:IsA(cl)return cl=='ModuleScript'end
 return o
end
require=function(o)return o.data end
local function folder(items)
 local obj={items=items}
 function obj:GetDescendants()return self.items end
 return obj
end
local ReplicatedStorage={__DIRECTORY={Eggs={['Zone Eggs']={['World 2']=folder({
  mkModule({eggNumber=204,name='Best Tech Egg',zoneNumber=191}),
  mkModule({eggNumber=202,name='Earlier Tech Egg',zoneNumber=189}),
  mkModule({eggNumber=206,name='Future Egg',zoneNumber=193})
 })}}}}
local function findChild(parent,name)return parent and parent[name] end
'''
# Integration: findEgg must return the eligible world-specific candidate even if
# the purchase list and IsUnlocked check are both empty/false.
run(mock+section('local function eggUnlockEvidence','-- DZ Hub approach: select the best unlocked zone egg')+r'''
state.clients.Directory={Eggs={},Zones={}}
state.cachedEgg=nil;state.cachedEggAt=0
state.world.number=2
local Workspace={}
local function zoneWorld()return 2 end
local function tryModule()return nil end
'''+section('local function findEgg()','-- Do not count a successful pcall')+r'''
local egg=findEgg()
assert(egg and egg.name=='Best Tech Egg', 'findEgg must not exclude locked eligible egg')
assert(egg.number==204 and state.eggSource:find('World 2',1,true))
print('PASS actual findEgg sees best eligible Tech egg despite zero purchased')
''')
run(mock+section('local function eggUnlockEvidence','-- DZ Hub approach: select the best unlocked zone egg')+r'''
local chosen=worldEggRecords(2,save)
assert(#chosen==2 and chosen[1].name=='Best Tech Egg','must select best ELIGIBLE egg even with zero purchased')
assert(state.eggWorldUnlockedCount==0 and state.eggWorldEligibleCount==2)
assert(eggUnlockEvidence(chosen[1],save)==false)
'''+section('local function ensureEggUnlocked(egg)','-- Dedicated hatching action')+r'''
assert(not ensureEggUnlocked(chosen[1]),'first call must unlock, not hatch')
assert(#calls==1 and calls[1].name=='Eggs_RequestUnlock' and calls[1].args[1]=='Best Tech Egg')
clock=101
assert(not ensureEggUnlocked(chosen[1]),'wait for unlock acknowledgement window')
clock=103
assert(ensureEggUnlocked(chosen[1]),'allow a hatch probe after positive unlock response')
assert(#calls==1, 'do not spam unlock')
save.PurchasedEggs['204']=true
assert(ensureEggUnlocked(chosen[1]) and state.eggUnlockSource=='Save.PurchasedEggs')
print('PASS eligible World 2 egg -> unlock first -> confirmation/probe -> purchased map')
''')
run(mock.replace('if name==\'Eggs_RequestUnlock\' then return true,true end','if name==\'Eggs_RequestUnlock\' then return true,false end')+section('local function eggUnlockEvidence','-- DZ Hub approach: select the best unlocked zone egg')+section('local function ensureEggUnlocked(egg)','-- Dedicated hatching action')+r'''
local chosen=worldEggRecords(2,save)[1]
assert(not ensureEggUnlocked(chosen))
assert(#calls==1)
clock=105
assert(not ensureEggUnlocked(chosen) and #calls==1,'reject must back off')
clock=122
assert(not ensureEggUnlocked(chosen) and #calls==2,'retry at bound only')
print('PASS rejected unlock backs off, does not hatch or spam remotes')
''')
# Test actual hatch function sends purchase only on accepted unlock. Here alternate stub injected (isolated code).
run(mock+section('local function eggUnlockEvidence','-- DZ Hub approach: select the best unlocked zone egg')+section('local function ensureEggUnlocked(egg)','-- Dedicated hatching action')+r'''
local function findEgg()return {name='Best Tech Egg',number=204,world=2}end
local function readGoals()return {{kind='hatch',required=100,progress=0}}end
local function hatchIntended()return true,'hatch quest' end
'''+re.sub(r'local (\w+):\s*(?:any|number\??)\s*=',r'local \1 =',section('local function hatch(allowTeleport)','local function consume(goal)'))+r'''
assert(not hatch(false))
assert(#calls==1 and calls[1].name=='Eggs_RequestUnlock')
clock=103
assert(hatch(false),'purchase should be attempted following unlock ack')
assert(#calls==2 and calls[2].name=='Eggs_RequestPurchase')
assert(calls[2].args[1]=='Best Tech Egg' and calls[2].args[2]==1)
assert(state.attempts.hatch==1)
print('PASS actual hatch worker orders Unlock BEFORE Purchase; falls back to 1 egg')
''')
print('All v3.5 egg unlock tests passed OFFLINE. No live server verification.')
