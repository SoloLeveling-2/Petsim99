"""RankPilot v3.3: source-backed Tier I-VI ingredients and reversible chest deferral.

These are isolated Lua 5.4 mocks, not live PS99 server tests.
"""
import ctypes,re
from pathlib import Path
s=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua')).read_text()
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
  rc=lib.luaL_loadstring(L,code.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  rc=lib.lua_pcallk(L,0,0,0,0,None);assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
 finally:lib.lua_close(L)
def section(start,end):return s[s.index(start):s.index(end,s.index(start))]
# Full syntax parse strips only Luau type declarations; source is unchanged.
converted=re.sub(r'local (\w+):\s*(?:any|number\?)\s*=',r'local \1 =',s)
converted=converted.replace('local liveCap: number =','local liveCap =').replace('local numericCap: number? =','local numericCap =')
L=lib.luaL_newstate()
try:
 rc=lib.luaL_loadstring(L,converted.encode());assert rc==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
finally:lib.lua_close(L)
print('PASS v3.3 complete Lua 5.4 compatible syntax parse')
run(r'''
math.clamp=function(n,l,h)return math.max(l,math.min(h,n))end
local function now() return 200 end
local Config={UpgradeMaterialReserve=8,MaxUpgradeInputTier=6}
local state={clients={MasteryCmds={GetPerkPower=function(typeName,name) return 0 end}},upgradeSelectionLast='',upgradeTierLast=''}
local potion={tier1={id='Damage',tn=1,_am=7},tier5={id='Coins',tn=5,_am=18},tier6={id='Lucky',tn=6,_am=19},tier7={id='Ultra',tn=7,_am=1000}}
local enchant={tier1={id='Coins',tn=1,_am=2},tier4={id='Strong Pets',tn=4,_am=16},tier6={id='Criticals',tn=6,_am=30}}
local function saveData()return {Inventory={Potion=potion,Enchant=enchant}} end
local function callMethod(module,name,...)
 if not module or type(module[name])~='function' then return false,nil end
 return pcall(module[name],...)
end
'''+section('local function chooseLowTierUpgrade(goal)','local function tryCollectionUpgrade()')+r'''
local p=chooseLowTierUpgrade({kind='collect_potion'})
assert(p and p.tier==5 and p.id=='Coins' and p.ingredients==5,'Tier V potion needs 5 of same type')
potion.tier5._am=4
p=chooseLowTierUpgrade({kind='collect_potion'})
assert(p and p.tier==6 and p.ingredients==5,'Tier VI potion usable as input')
assert(state.upgradeTierLast=='Tier 6 Potion')
local e=chooseLowTierUpgrade({kind='collect_enchant'})
assert(e and e.tier==4 and e.ingredients==7,'Tier IV enchant needs 7')
enchant.tier4._am=1
local e6=chooseLowTierUpgrade({kind='collect_enchant'})
assert(e6 and e6.tier==6 and e6.ingredients==7,'Tier VI enchant needs 7')
state.clients.MasteryCmds.GetPerkPower=function(category,perk)
 assert(perk=='BetterCrafting')
 return 2
end
local discounted=chooseLowTierUpgrade({kind='collect_enchant'})
assert(discounted and discounted.tier==6 and discounted.ingredients==5,'respects verified crafting mastery discount')
Config.MaxUpgradeInputTier=5
assert(chooseLowTierUpgrade({kind='collect_enchant'})==nil,'opted Tier V cap cannot consume Tier VI')
print('PASS potion Tier V/VI, enchant Tier IV/VI, mastery discount, per-tier cap, reserve')
''')
run(r'''
local Config={DeferMiniChestQuests=true,AutoFarm=true,AutoHatch=true,AutoParallelQuests=true,AutoUpgradeCollections=true,
 AutoCollectLootbags=true,AutoVending=false,AutoEventItems=true,AutoRank=true,PreferHighStars=true,StarPriorityWeight=12}
local state={rankStage={ready=false},goals={},clients={},blocked={},failures={},deferredChestCount=0}
local function now()return 100 end
local function healthy()return true end
local function starValue(g)return g.raw and g.raw.Stars or 1 end
local function getInventoryEntry()return nil end
local function numeralToNumber()return nil end
local scores={minichest=62,hatch=90,collect_enchant=67,farm=98}
'''+section('local function eligible(goal)','local function inHatchMovementWindow()')+section('local function chooseGoal()','local function matchesQuestBreakable(')+r'''
local normal={kind='minichest',identity='m',key='1',title='Break 2 mini-chests in best area',progress=3,required=5,raw={Stars=3}}
local superior={kind='minichest',identity='s',key='2',title='Break a superior mini-chest in best area',progress=0,required=1,raw={Stars=4}}
local hatch={kind='hatch',identity='h',key='3',title='Hatch 1400 best eggs',progress=0,required=1400,raw={Stars=2}}
local ench={kind='collect_enchant',identity='e',key='4',title='Collect 23 enchants',progress=9,required=32,raw={Stars=1}}
state.goals={normal,superior,hatch,ench}
assert(chooseFarmGoal()==nil,'farm lane should not target mini/superior chests while hatch and collect exist')
assert(chooseGoal().kind~='minichest','foreground must defer both chest classes')
assert(state.deferredChestCount==2 and state.chestDeferralActive)
state.goals={normal,superior}
assert(chooseFarmGoal() and chooseFarmGoal().kind=='minichest','chest quests automatically resume when other goals gone')
assert(chooseGoal().kind=='minichest')
assert(state.deferredChestCount==0)
state.goals={normal,hatch}
Config.AutoHatch=false
assert(chooseFarmGoal() and chooseFarmGoal().kind=='minichest','disabled hatch lane must not starve chest quest')
Config.AutoHatch=true
Config.DeferMiniChestQuests=false
assert(chooseFarmGoal().kind=='minichest','user can turn off chest deferral')
print('PASS both chest variants deferred; resumes when alternatives gone; disabled lanes do not starve')
''')
assert 'local _,def=rankDefinition(currentRank)' in s
assert 'UpgradeTierSelectionVersion = 1' in s and 'legacyTier' in s
assert 'interactiveToggle(page("ranks"), "DeferMiniChestQuests"' in s
assert 'choice(page("machines"), "Highest upgrade input tier"' in s
print('PASS unused-variable warning removed, UI controls present, old settings migration included')
print('v3.3 tests passed (offline only; no claim about live PS99 credits)')
