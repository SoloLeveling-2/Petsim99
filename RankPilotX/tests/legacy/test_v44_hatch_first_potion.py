"""Offline behavior probes of shipped RankPilot 4.4 Lua logic, NOT live Roblox."""
import ctypes,re
from pathlib import Path
S=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
def lua(code):
 L=lib.luaL_newstate();lib.luaL_openlibs(L)
 try:
  rc=lib.luaL_loadstring(L,code.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  rc=lib.lua_pcallk(L,0,0,0,0,None);assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
def section(start,end):return S[S.index(start):S.index(end,S.index(start))]
compatible=re.sub(r'(?m)(\blocal\s+\w+)\s*:\s*(?:any|number\??|string\??|boolean\??)',r'\1',S)
lua('assert(type(1)=="number")\n')
L=lib.luaL_newstate()
try:
 rc=lib.luaL_loadstring(L,compatible.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
finally:lib.lua_close(L)
print('PASS full-script Lua 5.4-compatible syntax parse, Luau annotations retained in delivered file')
movement=section('local function inHatchMovementWindow()','local function chooseGoal()')
lua('''local Config={HatchFirstMode=true} local state={hatchExclusive=true,hatchNeedsCoins=false}
local function now()return 100 end
'''+movement+'''
assert(inHatchMovementWindow()==true,'active egg work must block farm movement')
state.hatchNeedsCoins=true
assert(inHatchMovementWindow()==false,'verified currency shortage yields farming opportunity')
state.hatchExclusive=false; state.hatchNeedsCoins=false
assert(inHatchMovementWindow()==false,'inactive hatch cannot starve farming')
''')
print('PASS hatch-first movement blocks diamond hopping but allows coin-farming fallback')
worker=section('local function hatchWorker(generation)','-- Passive quest worker')
mock=r'''
local requests={}
local Config={AutoHatch=true,HatchFirstMode=true,AutoParallelQuests=true,
 AutoFarm=true,FastFarm=true,SkipEggAnimations=false}
local state={running=true,shutdown=false,generations=1,hatchRetryAt=1000,
 hatchNeedsCoins=false,farmGoal={kind="diamond"},chestDeferralActive=false,
 hatchExclusive=false,hatchIntent="",hatchGoalActive=false}
local function now() return 100 end
local function healthy()return true end
local function activeHatchQuest()return {kind="hatch"}end
local function hatchIntended()return true,"hatch quest"end
local function saveData()return {}end
local function movementAvailable()return true end
local function inHatchMovementWindow()return state.hatchExclusive and not state.hatchNeedsCoins end
local function hatch(movable)table.insert(requests,movable)end
local function skipEggAnimation()end
local function failFeature()error("no errors expected")end
local task={wait=function()state.shutdown=true end}
'''
lua(mock+worker+'''
hatchWorker(1)
assert(#requests==1 and requests[1]==true,'hatch should be allowed to move to egg despite diamond quest')
assert(state.hatchExclusive)
''')
print('PASS live-shaped hatch worker chooses hatch destination despite active diamond farm lane')
consume=section('local function consume(goal)','-- Vending collection automation')
base=r'''
local t=100
math.clamp=function(n,a,b)return math.min(math.max(n,a),b)end
local function now()return t end
local saved={RankStars=20,GoalsCompleted=4,goal={kind="potion",identity="quest:1",uid="1",title="Use Damage Potion IV",progress=0,required=12}}
local function saveData()return saved end
local function readGoals(data)return data.goal and {data.goal} or {}end
local state={consumableTimes={},clients={PotionCmds={Consume=function(uid)return true end}},
 potionBatchVerified=nil,potionPending=nil,potionBatchedRequests=0,potionFallbackUses=0,
 failures={}}
local Config={ConsumableSeconds=0.7,PotionBatchUse=true,PotionMaxBatch=8}
local requests={}
local function healthy()return true end
local function numeralToNumber()return 4 end
local function potionForUseGoal()return {uid="PotionDamageIV",id="Damage",tier=4,amount=30},"Damage"end
local function getInventoryEntry()return nil end
local function network(name,args,invoke)
 assert(name=="Potions: Consume" and not invoke)
 table.insert(requests,args[2]); return true,true
end
local function callMethod(cmd,fun,uid)return true,true end
local function failFeature(...)error("Unexpected error")end
local function cooldownReady()return true end
local function log()end
'''
lua(base+consume+r'''
assert(consume(saved.goal))
assert(#requests==1 and requests[1]==2,'first request must probe 2, not blindly consume 8')
t=103;saved.goal.progress=2
assert(consume(saved.goal))
assert(state.potionBatchVerified==true and requests[2]==8,
 'after verified +2 quest credit, one bounded 8-potion use allowed')
assert(state.potionBatchedRequests==2)
''')
print('PASS potion batch requires successful two-credit trial before 8-count request')
lua(base+consume+r'''
assert(consume(saved.goal))
t=106
assert(consume(saved.goal))
assert(state.potionBatchVerified==false,'no credit means no more batched potion attempts')
assert(state.potionFallbackUses==1,'fallback must use safe single client call')
assert(#requests==1,'unsupported batches must not be retried')
''')
print('PASS uncredited potion batch stops and falls back to bounded singles')
# Config precedence and safety invariants
for x in ['HatchFirstMode = true','AutoEventItems = true','SpawnItemSeconds = 5',
          'PotionBatchUse = true', 'PotionMaxBatch = 8',
          'local previousProgress=state.spawnObserved[goal.identity]',
          'nextVisualWorkerAt=now()+5','Config.LowLagMode and 7 or 16',
          'Insufficient egg currency reported; temporarily farming coins']:
 assert x in S,x
print('PASS lean-loop, quest-event refresh, and currency-evidence source invariants')
