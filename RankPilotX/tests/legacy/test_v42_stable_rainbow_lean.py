"""Offline integration-like mocks for RankPilot v4.2; not live Roblox testing."""
from pathlib import Path
import ctypes,re
SRC=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_close.argtypes=[ctypes.c_void_p]
def lua(code):
 L=lib.luaL_newstate();lib.luaL_openlibs(L)
 try:
  assert lib.luaL_loadstring(L,code.encode())==0, (lib.lua_tolstring(L,-1,None) or b'').decode()
  assert lib.lua_pcallk(L,0,0,0,0,None)==0, (lib.lua_tolstring(L,-1,None) or b'').decode()
 finally:lib.lua_close(L)
def section(a,b):return SRC[SRC.index(a):SRC.index(b,SRC.index(a))]
# source-backtest actual normalization and rainbow worker using a changing title.
mock=r'''
local clock=100
math.clamp=function(n,lo,hi)return math.min(math.max(n,lo),hi)end
local function now()return clock end
local function describe(x)return tostring(x)end
local function getGoalTitle(g)
 return 'Make '..tostring(g.Amount-g.Progress)..' rainbow pets from best egg'
end
local function classify(t)return 'convert' end
local saved={Goals={[2]={UID='rank-rainbow-UID-19',Type='BEST_RAINBOW',Stars=2,
  Amount=30,Progress=16}},RankStars=272,GoalsCompleted=44,
 Inventory={Pet={G={id='Alien',pt=1,_am=80}}}}
local function saveData()return saved end
local function log(...)end
local state={goals={},running=true,rankStage={},rainbowNext=0,rainbowRetryAt=0,
 rainbowPending=nil,rainbowAttempts=0,rainbowCredited=0,rainbowValidated=false,
 rainbowLastGoalProgress=nil,rainbowPrepPending=nil,rainbowPrepNext=0,
 rainbowPrepRetryAt=0,rainbowStableIdentityFixes=0}
local Config={AutoRainbowConversion=true,AutoRank=true,AutoParallelQuests=true,
 RainbowMaxOutputBatch=10,AutoGoldForRainbow=true,ConversionPetReserve=10}
local function findEgg()return {name='Best Egg',pets={{'Alien',1}}}end
local function movementAvailable()return true end
local function loadedTechMachine()
  return {Position=setmetatable({}, {__sub=function()return {Magnitude=0}end})}
end
local rp=setmetatable({}, {__sub=function()return {Magnitude=0}end})
local root={Position=rp,CFrame='FarmZone'}
local function currentRoot()return root end
local function leaseMovement()return true end
local function clearMovement()end
local calls={}
local function network(name,params,invoke)
 calls[#calls+1]={name=name,outputs=params[2]}
 return true,true
end
'''
normalizer=section('local function normalizeGoal(key, entry)','local function getInventoryEntry(')
# Code expects egg goal lookup helper, implement using fresh readGoals
helper='''
local function activeBestEggRainbowQuest(data)
 for _,g in ipairs(readGoals(data or saved)) do
   if g.kind=='convert' and g.title:lower():find('rainbow',1,true) then return g end
 end
 return nil
end
local function tryPrepareRainbowGold()return false end
'''
rainbow=section('local function tryRainbowConversion()','-- Reversible client-only gain text suppression')
lua(mock+normalizer+helper+rainbow+r'''
state.goals=readGoals(saved)
local original=state.goals[1].identity
assert(original=='2:rank-rainbow-UID-19','use UID, not the remaining pets in title')
assert(tryRainbowConversion()==true and calls[1].outputs==1,
 'first rainbow is one output as an expenditure safety test')
clock=107
saved.Goals[2].Progress=17
state.goals=readGoals(saved)
assert(state.goals[1].identity==original and state.goals[1].title~='Make 14 rainbow pets from best egg',
 'changing the remaining quantity must NOT change quest identity')
assert(tryRainbowConversion()==false and state.rainbowCredited==1
 and state.rainbowValidated,'the title change should be recognized as real quest credit')
clock=109
assert(tryRainbowConversion()==true and calls[2].outputs==8,
 'after confirmation, batch 8 outputs with 80 available golden pets')
print('PASS stable quest UID, credited rainbow confirmation, one-test-then-eight batch')
''')
# migration and hot-loop defaults
for token in ['LowLagMode = true','VisualRefreshSeconds = 90','MaxPetsPerTick = 55',
              'PetAssignSeconds = 2.6','CollectionSeconds = 1.8',
              'LeanProfileVersion = 2', 'math.clamp(tonumber(Config.PetSpeedMultiplier) or 8,1,20)',
              'task.wait(Config.FastFarm and (Config.LowLagMode and 0.20 or 0.14) or 0.6)',
              'if data.HideYellowBagFX==true then Config.HideYellowBagFX=false end']:
 assert token in SRC,token
print('PASS low-lag worker defaults, bounded pet speed, old settings migration')
