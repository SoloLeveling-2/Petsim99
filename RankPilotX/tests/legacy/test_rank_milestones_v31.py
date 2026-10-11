"""RankPilot v3.1 game-source-derived rank milestones, star weighting and conversion tests.
These are offline Lua tests with game-service stubs, NOT server compatibility verification.
"""
import ctypes
from pathlib import Path
source=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]

def run(script):
    vm=lib.luaL_newstate();lib.luaL_openlibs(vm)
    try:
        rc=lib.luaL_loadstring(vm,script.encode())
        assert rc==0,(lib.lua_tolstring(vm,-1,None)or b'').decode()
        rc=lib.lua_pcallk(vm,0,0,0,0,None)
        assert rc==0,(lib.lua_tolstring(vm,-1,None)or b'').decode()
    finally:lib.lua_close(vm)

def segment(name,after):
    return source[source.index('local function '+name+'('):source.index(after,source.index('local function '+name+'('))]

prefix=r'''
math.clamp=function(n,lo,hi)return math.max(lo,math.min(hi,n))end
local function callMethod(obj,name,...)
 if type(obj)~='table' or type(obj[name])~='function' then return false,'missing' end
 return pcall(obj[name],...)
end
local function now()return 100 end
local function describe(value)return tostring(value)end
local function log()end
local Config={PreferHighStars=true,StarPriorityWeight=12,AutoFarm=true,AutoRank=true,AutoParallelQuests=true}
local state={clients={},rankStage={ready=false},maxRankSource='none',goals={},failures={},blocked={},cooldowns={}}
'''

run(prefix+segment('getMaxRank','-- The current official main progression index')+r'''
state.clients.RankCmds={GetMaxRank=function()return 14 end,
 AllRewardsReady=function()return false end,
 AllRewardsRedeemed=function()return true end,
 IsRankBlockedByZone=function()return false,false end}
state.clients.RanksUtil={
 GetMaximumRank=function()return {RankNumber=40}end,
 RankIDFromNumber=function(n)return 'r'..n end}
state.clients.Directory={Ranks={r14={Rewards={{StarsRequired=4},{StarsRequired=5},{StarsRequired=6}}}}}
assert(getMaxRank()==40, 'GetMaxRank in RankCmds returns CURRENT rank and cannot be used as cap')
local data={Rank=14,RankStars=8,RedeemedRankRewards={}}
local s=readRankStage(data)
assert(s.starsNeeded==15 and s.starsLeft==7 and not s.ready)
assert(#s.pending==1 and s.pending[1]==1, 'only first reward should be claimable at 8 stars')
data.RankStars=15;s=readRankStage(data)
assert(s.ready and not s.blocked and #s.pending==3)
assert(s.status:find('claim 3 rank reward'))
state.clients.RankCmds.IsRankBlockedByZone=function()return true,true,200,1 end
s=readRankStage(data)
assert(s.blocked and s.requiredZone==200 and s.rebirthsMissing==1)
assert(s.status:find('Area 200',1,true) and s.status:find('rebirth',1,true))
state.clients.RankCmds.IsRankBlockedByZone=function()return false,false end
data.RedeemedRankRewards={['1']=true,['2']=true,['3']=true}
s=readRankStage(data)
assert(s.ready and not s.blocked and #s.pending==0)
assert(s.status:find('game%-controlled rank advancement'))
data.Rank=40;s=readRankStage(data)
assert(s.max and s.status:find('MAX RANK',1,true))
assert(starValue({raw={Stars=4}})==4 and starValue({raw={Stars=2}})==2)
assert(starValue({raw={}})==1 and starValue({raw={Stars=100}})==4)
print('PASS max-rank source, cumulative stars, claim thresholds, blockers, MAX, star values')
''')

run(prefix+r'''
local scores={farm=98,minichest=62}
local farmKinds={farm=true,minichest=true}
local function healthy()return true end
local function eligible()return true end
local function cooldownReady()return false end
local function starValue(g)return g.raw and g.raw.Stars or 1 end
'''+segment('farmPriority','local function activeCollectGoal()')+r'''
local q1={kind='farm',title='Break 500 best-area objects',required=500,progress=0,raw={Stars=1},key='1',identity='q1'}
local q2={kind='farm',title='Break 500 best-area objects',required=500,progress=0,raw={Stars=4},key='2',identity='q2'}
state.goals={q1,q2}
assert(chooseFarmGoal()==q2,'must prioritize equal effort with more star rewards')
print('PASS high-star priority for equally actionable farm quests')
''')

run(prefix+r'''
Config.AutoRainbowConversion=true
local tick=100
local function now()return tick end
state.running=true
state.rainbowNext=0;state.rainbowRetryAt=0;state.rainbowAttempts=0;state.rainbowCredited=0
state.goals={{kind='convert',identity='rainbow',title='Make 40 rainbow pets from best egg',progress=0}}
local saved={Inventory={Pet={Regular={id='Bunny',_am=400},Gold={id='Bunny',_am=20,pt=1}}}}
local function saveData()return saved end
local function readGoals(data)return {{kind='convert',identity='rainbow',progress=data.progress or 0}}end
local function findEgg()return {name='best-egg',pets={{'Bunny',1},{'Fox',1}}}end
local function activeBestEggRainbowQuest()return true end
local posmt={__sub=function(a,b)return {Magnitude=math.abs(a.x-b.x)}end}
local marker={Position=setmetatable({x=0},posmt),CFrame={}}
local root={Position=setmetatable({x=0},posmt),CFrame={}}
local function loadedTechMachine()return marker end
local function movementAvailable()return true end
local function leaseMovement()return true end
local function clearMovement()end
local function currentRoot()return root end
local sendCount=0
local function network(name,args,invoke)
 assert(name=='RainbowMachine_Activate' and args[1]=='Gold' and args[2]==1 and invoke)
 sendCount=sendCount+1;return true,true
end
local function cooldownReady()return true end
'''+segment('tryRainbowConversion','-- Reversible client-only gain text suppression.')+r'''
assert(tryRainbowConversion() and sendCount==1 and state.rainbowAttempts==1)
-- Move clock forward for queued server-credit verification.
'''+r'''
tick=108;saved.progress=1
assert(not tryRainbowConversion() and state.rainbowCredited==1)
print('PASS rainbow conversion only spends best-egg gold stack and verifies quest credit')
''')

assert 'network("Potions: Consume",{potion.uid,1},false)' in source
assert 'AutoRainbowConversion = true' in source
assert 'AutoGoldConversion = true' in source
assert 'Network.Fire("Ranks_RankUp"' not in source
print('PASS potion qty=1, requested rainbow workflow ON, no invented rank-up request')
print('ALL v3.1 rank integration tests PASSED OFFLINE')
