"""Offline isolated Lua 5.4 mocks for v3.7: NOT a live Roblox integration test."""
import ctypes,re
from pathlib import Path
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
  q=lib.luaL_loadstring(L,code.encode());assert q==0,(lib.lua_tolstring(L,-1,None) or b'').decode()
  q=lib.lua_pcallk(L,0,0,0,0,None);assert q==0,(lib.lua_tolstring(L,-1,None) or b'').decode()
 finally:lib.lua_close(L)
def segment(a,b):
 return s[s.index(a):s.index(b,s.index(a))]
compatible=re.sub(r'local (\w+):\s*(?:any|number\??)\s*=',r'local \1 =',s)
L=lib.luaL_newstate()
try:
 q=lib.luaL_loadstring(L,compatible.encode());assert q==0,(lib.lua_tolstring(L,-1,None) or b'').decode()
finally:lib.lua_close(L)
print('PASS v3.7 whole-script Lua-compatible parse')
helper=segment('local function activeBestEggRainbowQuest(data)','-- DZ Hub\'s no-animation implementation')
mock='''
local clock=100
local function now()return clock end
local quest={identity='2:make 30 rainbows',title='Make 30 rainbow pets from best egg',kind='convert',progress=0,required=30,raw={Stars=2}}
local save={Goals={quest},RankStars=270,GoalsCompleted=35,Inventory={Pet={}}}
local state={goals={quest},clients={},world={number=2},running=true,
 rainbowNext=0,rainbowRetryAt=0,rainbowLast='none',rainbowAttempts=0,
 rainbowCredited=0,rainbowValidated=false,rainbowPending=nil,
 rainbowPrepPending=nil,rainbowPrepNext=0,rainbowPrepRetryAt=0,
 rainbowPrepAttempts=0,rainbowPrepCredited=0,rainbowPrepLast='none'}
local Config={AutoRank=true,AutoParallelQuests=true,AutoHatch=true,AutoHatchAlways=false,
 AutoHatchForRainbow=true,AutoRainbowConversion=true,AutoGoldForRainbow=true,
 ConversionPetReserve=10,RainbowGoldBatchMax=10,RainbowMaxOutputBatch=10}
local egg={name='Best Tech Egg',pets={{'Alien',1},{'Tiger',1}}}
local function findEgg()return egg end
local function saveData(...)return save end
local function readGoals(x)return (x and x.Goals) or state.goals end
'''
run(mock+helper+'''
local intended,reason=hatchIntended(save)
assert(intended and reason=='rainbow material hatching')
save.Inventory.Pet.Normal={id='Alien',pt=false,_am=120}
assert(hatchIntended(save)==false,'having 100+reserve regular pets suppresses unnecessary material hatch')
save.Inventory.Pet.Normal._am=20
save.Inventory.Pet.Gold={id='Alien',pt=1,_am=10}
assert(hatchIntended(save)==false,'golden pets for immediate rainbow craft stop background egg hatching')
save.Inventory.Pet.Gold=nil
save.Goals={}
assert(hatchIntended(save)==false,'no hatch and no rainbow quest stops hatching')
save.Goals={{kind='hatch',required=100,progress=15}}
assert(hatchIntended(save)==true,'ordinary active hatch quest still triggers hatching')
save.Goals={quest};egg.pets=nil
assert(hatchIntended(save)==false,'missing egg species prevents blind hatch spending')
print('PASS hatch-for-rainbow start/stop controls, stock checks, no blind spending')
''')
# A full mock of GoldMachine and RainbowMachine call-and-verify sequence, including
# quest completion via changed RankStars rather than only +progress.
network_mock=mock+'''
math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
local p=setmetatable({}, {__sub=function()return {Magnitude=0}end})
local root={Position=p,CFrame='previous'}
local marker={Position=p,CFrame='machine'}
local function currentRoot()return root end
local function loadedTechMachine()return marker end
local function movementAvailable()return true end
local function leaseMovement()return true end
local function clearMovement()end
local function log()end
local function describe(x)return tostring(x)end
local callLog={}
local function network(name,args,invoke)
  callLog[#callLog+1]={name=name,uid=args[1],outputs=args[2]}
  if name=='GoldMachine_Activate' then
    save.Inventory.Pet.Gold={id='Alien',pt=1,_am=(save.Inventory.Pet.Gold and save.Inventory.Pet.Gold._am or 0)+args[2]}
  end
  return true,true
end
'''
gold_code=segment('local function tryPrepareRainbowGold(goal, species, data)','-- Rainbow crafting is supported')
rainbow_code=segment('local function tryRainbowConversion()','-- Reversible client-only gain text suppression')
run(network_mock+helper+gold_code+rainbow_code+'''
save.Inventory.Pet.Normal={id='Alien',pt=false,_am=130}
assert(tryRainbowConversion()==true)
assert(#callLog==1 and callLog[1].name=='GoldMachine_Activate' and callLog[1].outputs==10,
 'make 10 gold species-matching pets in one bounded batch')
clock=103
assert(tryRainbowConversion()==false,'gold inventory must be verified before rainbow crafting')
clock=108
assert(tryRainbowConversion()==false and state.rainbowPrepCredited==10,'verify new gold count')
clock=110
assert(tryRainbowConversion()==true and callLog[2].name=='RainbowMachine_Activate'
 and callLog[2].outputs==1,'first rainbow conversion is 1 test output')
clock=117
quest.progress=1
assert(tryRainbowConversion()==false and state.rainbowValidated and state.rainbowCredited==1,
 'only credited quest progress enables rainbow batching')
clock=119
assert(tryRainbowConversion()==true and callLog[3].outputs==1,
 'inventory still reports only 10 gold; first verified batch can only afford 1')
-- The second request has no additional quest credit. It must back off rather
-- than spend further pets on unverified server behaviour.
clock=138
assert(tryRainbowConversion()==false and state.rainbowRetryAt>clock)
print('PASS normal->gold->rainbow, verify before batch, refuse uncredited repetition')
''')
# Verify a quest replaced by a new goal can still be counted if rank stars rose.
run(network_mock+helper+gold_code+rainbow_code+'''
save.Inventory.Pet.Gold={id='Alien',pt=1,_am=40}
assert(tryRainbowConversion())
assert(callLog[1].name=='RainbowMachine_Activate' and callLog[1].outputs==1)
clock=107
save.Goals={{kind='farm',identity='2:next quest',progress=0,required=100}}
save.RankStars=272;save.GoalsCompleted=36
assert(tryRainbowConversion()==false and state.rainbowValidated and state.rainbowCredited==1)
print('PASS rainbow quest replacement + star credit counts as completed')
''')
chooser=segment('local function chooseLowTierUpgrade(goal)','-- Group attempts at the machine')
run('''
local clock=100
math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
local function now()return clock end
local state={clients={},upgradeRejectedUIDs={}}
local Config={MaxUpgradeInputTier=6,UpgradeMaterialReserve=8}
local goal={kind='collect_enchant',required=32,progress=4}
local saved={Inventory={Enchant={Small={id='Lucky Eggs',tn=1,_am=20},
 Huge={id='Treasure Hunter',tn=3,_am=180}}}}
local function saveData()return saved end
local function callMethod()return false end
'''+chooser+'''
local row=chooseLowTierUpgrade(goal)
assert(row.uid=='Huge' and row.possible==34,
 'one Tier III enchant batch should finish a 28-output quest instead of a tiny Tier I stack')
print('PASS upgrade chooser prefers a stack capable of completing the quest in one batch')
''')
assert 'placeInZone,best' in s and 'farmReturnCount' in s
assert 'UpgradeVerifySeconds = 6' in s and 'state.upgradeValidated[pending.kind]' in s
assert 'Hatch suspended: no active hatch or rainbow material need' in s
print('PASS farm recovery and faster gated machine verification controls present')
print('ALL v3.7 NEW OFFLINE TESTS PASSED')
