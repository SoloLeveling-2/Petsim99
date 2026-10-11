"""Offline tests of RankPilot 3.6 manual-video batch semantics and guarded hatching."""
import ctypes, re, runpy
from pathlib import Path
z=runpy.run_path(str(Path(__file__).with_name('test_v35_unlock.py')))
s=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
run=z['run']; section=z['section']; mock=z['mock']
assert '111 tier-II potions' in s and '37 crafted potions' in s
assert 'HatchFarmRemoteProbe' in s
# Case 1: stale planner says hatch; current save has none. No egg unlock/purchase ever.
run(mock + r'''
local function readGoals()return {}end
local function hatchIntended()return false,'no quest' end
local function findEgg()error('must not look for an egg without a live quest')end
'''+re.sub(r'local (\w+):\s*(?:any|number\??)\s*=',r'local \1 =',section('local function hatch(allowTeleport)','local function consume(goal)'))+r'''
assert(hatch(true)==false)
assert(#calls==0 and state.hatchLastResult:find('no active hatch'))
print('PASS strict live-quest stop, no unwanted unlock/purchase')
''')
# Case 2: only one remote probe from an unreachable farming spot, must verify actual EggsHatched.
probe_mock=mock + r'''
local function readGoals()return {{kind='hatch',required=200,progress=0}} end
local function hatchIntended()return true,'hatch quest' end
local a=setmetatable({}, {__sub=function() return {Magnitude=250}end})
local b=setmetatable({}, {__sub=function() return {Magnitude=250}end})
local char={Position=a,CFrame='previous'}
currentRoot=function()return char end
local function typeof(x) if type(x)=='table' and x.Position then return 'CFrame' end return type(x)end
local function findEgg()return {name='Best Tech Egg',number=204,world=2,capsuleCFrame={Position=b}} end
local function ensureEggUnlocked()return true end
state.clients.EggCmds={GetMaxHatch=function()return 20 end,
 RequestPurchase=function(name,qty)
   calls[#calls+1]={name='Purchase',qty=qty}
   return true
 end}
state.hatchFarmRemoteBackoff=0
state.hatchRemoteLastProbe=0
state.hatchFarmRemoteLast='not tested'
state.hatchFarmRemoteSupported=false
state.hatchGoalActive=true
Config.HatchFarmRemoteProbe=true
Config.MaxHatchBatch=100
'''
hatch_code=re.sub(r'local (\w+):\s*(?:any|number\??)\s*=',r'local \1 =',section('local function hatch(allowTeleport)','local function consume(goal)'))
run(probe_mock+hatch_code+r'''
clock=100
assert(hatch(false)==true)
assert(#calls==1 and calls[1].qty==1,'only one remote trial permitted')
clock=102
assert(hatch(false)==false and #calls==1,'must wait for observed progress')
save.EggsHatched=save.EggsHatched+1
clock=103
assert(hatch(false)==true)
assert(state.hatchFarmRemoteSupported==true,'observed remote egg credit required')
assert(#calls==2 and calls[2].qty==20,'only verified remote travel-free hatching can batch')
print('PASS away-from-egg 1-egg trial, no spam, verified batch follow-up')
''')
run(probe_mock+hatch_code+r'''
clock=100
assert(hatch(false)==true and #calls==1)
clock=110
assert(hatch(false)==false and #calls==1)
assert(state.hatchFarmRemoteBackoff>110)
assert(state.hatchFarmRemoteSupported==false)
print('PASS no remote credit -> back off and use ordinary movement windows')
''')
# Case 3: bulk crafting is output quantity not inputs, and replacement + earned
# stars confirms quest completion even if the original goal slot is replaced.
upgrade_mock=r'''
local clock=100
math.clamp=function(n,lo,hi)return math.max(lo,math.min(hi,n))end
local function now()return clock end
local goal={identity='2:Collect 28 potions',kind='collect_potion',progress=9,
 required=37,title='Collect 28 potions',raw={UID='old',Stars=2}}
local replacement={identity='2:Break 3 coin jars',kind='coinjar',progress=0,
 required=3,title='Break 3 coin jars',raw={UID='new',Stars=2}}
local saved={Inventory={Potion={A={id='Coins',tn=2,_am=350}}},RankStars=264,
 GoalsCompleted=40}
local state={running=true,goals={goal},clients={},upgradePending=nil,upgradeNext=0,
 upgradeDisabled={},upgradeCount=0,collectionCredits=0,upgradeValidated={},
 upgradeLast='none',upgradeLastCreditMethod='none',upgradeRejectedUIDs={},
 upgradeRejectedCount=0,upgradeVisitStart=0,upgradeVisitCompleted=0,
 logs={},cooldowns={},movementOwner=nil,movementUntil=0,
 upgradeSelectionLast='none',upgradeTierLast='none'}
local Config={AutoUpgradeCollections=true,AutoRank=true,AutoParallelQuests=true,
 UpgradeMaterialReserve=8,MaxUpgradeInputTier=6,UpgradePauseSeconds=170,
 UpgradeInterval=3,UpgradeVisitSeconds=24,UpgradeRejectedUIDCooldown=130,
 UpgradeMaxOutputBatch=40,UpgradeVerifySeconds=13}
local function callMethod(...)return false,nil end
local function healthy()return true end
local function eligible()return true end
local function movementAvailable()return true end
local function leaseMovement()return true end
local function clearMovement()end
local function log()end
local function describe(v)return tostring(v)end
local function cooldownReady()return true end
local function saveData()return saved end
local function readGoals()return state.goals end
local v=setmetatable({}, {__sub=function()return {Magnitude=0}end})
local function currentRoot()return {Position=v,CFrame='original'}end
local function loadedTechMachine()return {Position=v,CFrame='machine'}end
local requests={}
local function network(name,args,invoke)
 requests[#requests+1]={name=name,uid=args[1],amount=args[2]}
 return true,true
end
'''
# Need include collectionGoals, chooser, upgrade visit, worker. Split to avoid unrelated code.
chunks=section('local function collectionGoals','local function loadedTechMachine')
chunks+=section('local function chooseLowTierUpgrade','-- Public Griffin autoRanker: GoldMachine_Activate')
run(upgrade_mock+chunks+r'''
local item=chooseLowTierUpgrade(goal)
assert(item and item.ingredients==3 and item.possible==114,
 'Tier II potion batch must use 3 ingredient items per new potion')
assert(tryCollectionUpgrade())
assert(#requests==1 and requests[1].amount==28,
 '28 outputs remaining must request 28, not 84 input items')
assert(state.upgradePending and state.upgradePending.outputs==28)
clock=115
state.goals={replacement}
saved.RankStars=266
saved.GoalsCompleted=41
assert(tryCollectionUpgrade()==false)
assert(state.collectionCredits==1 and state.upgradeLastCreditMethod:find('Quest replaced'),
 'rank-star gain plus quest replacement must be recognized')
print('PASS Tier II 28-output bulk craft and completed quest replacement credited')
''')
print('ALL v3.6 NEW OFFLINE TESTS PASSED')
