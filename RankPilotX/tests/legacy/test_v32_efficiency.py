"""Targeted v3.2 isolated Lua 5.4 regression tests. Not a live Roblox test."""
import ctypes,re
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
 vm=lib.luaL_newstate();lib.luaL_openlibs(vm)
 try:
  rc=lib.luaL_loadstring(vm,code.encode())
  assert rc==0,(lib.lua_tolstring(vm,-1,None)or b'').decode()
  rc=lib.lua_pcallk(vm,0,0,0,0,None)
  assert rc==0,(lib.lua_tolstring(vm,-1,None)or b'').decode()
 finally:lib.lua_close(vm)
def extract(start,until):
 i=src.index(start)
 return src[i:src.index(until,i)]
# Full parser; Luau type annotations are preserved in shipped source.
converted=re.sub(r'local (\w+):\s*(?:any|number\?)\s*=',r'local \1 =',src)
converted=converted.replace('local liveCap: number =','local liveCap =')
converted=converted.replace('local numericCap: number? =','local numericCap =')
vm=lib.luaL_newstate()
try:
 rc=lib.luaL_loadstring(vm,converted.encode())
 assert rc==0,(lib.lua_tolstring(vm,-1,None)or b'').decode()
finally:lib.lua_close(vm)
print('PASS full v3.2 Lua syntax compatible parse, Luau typing preserved in shipped source')

# Popup regex catches in-game number-only currency gains, leaves normal HUDs.
run(r'''
local function dummy()end
'''+extract('local function popupIsAmount(txt)','local function popupLooksLikePickup(node)')+r'''
assert(popupIsAmount('703k') and popupIsAmount('1.29k'))
assert(popupIsAmount('257k') and popupIsAmount('6.48k'))
assert(popupIsAmount('+850') and popupIsAmount('103,500'))
assert(not popupIsAmount('32/1400'))
assert(not popupIsAmount('Rank 14'))
assert(not popupIsAmount('Collect potions'))
print('PASS numeric pickup regex with/without +, comma, suffix and decimal')
''')
run(r'''
Workspace={}
LocalPlayer={FindFirstChild=function()return nil end}
Config={HidePickupPopups=true}
state={popupRecords=setmetatable({},{__mode='k'}),popupHidden=0}
local function object(class,name,children,where)
 local o={Name=name,Parent={Name='Part'},Enabled=true,children=children or {},where=where or Workspace,class=class}
 function o:IsA(k)return self.class==k end
 function o:IsDescendantOf(where)return self.where==where end
 function o:GetDescendants()return self.children end
 return o
end
local label=object('TextLabel','Amount',nil,Workspace)
label.Text='703k'
local icon=object('ImageLabel','CoinIcon',nil,Workspace)
local pickup=object('BillboardGui','Billboard', {label,icon})
local poor=object('BillboardGui','Health',{label})
local hud=object('ScreenGui','Main', {label,icon})
'''+extract('local function popupIsAmount(txt)','local function checkPopupAfterCreation(node)')+r'''
assert(popupLooksLikePickup(pickup))
assert(not popupLooksLikePickup(poor))
assert(not popupLooksLikePickup(hud))
suppressPopup(pickup)
assert(pickup.Enabled==false and state.popupHidden==1)
assert(hud.Enabled)
print('PASS anchored number and icon hidden, non-gain HUD still visible')
''')

# Rotation sees only locally loaded owned zones of World 3, and respects current world.
run(r'''
local ticks=120
local function now()return ticks end
local function callMethod(module,name,...)return true,module[name](...)end
local Config={DiamondZonesPerPass=30,DiamondTargetRefresh=18}
local state={clients={ZoneCmds={Owns=function(n)return n~='Forbidden' end}},
 world={number=3,zone='Void Spawn'}, diamondScannedAt=0,diamondCandidateZones={},diamondCandidateCount=0,diamondRotateIndex=0,diamondTargetsByZone={},diamondLastTargetAudit=0}
local function zoneDirectoryInfo(n)return {ZoneNumber= n=='Void Spawn' and 200 or n=='Fracture' and 219 or n=='Forbidden' and 201 or 245}end
local function zoneWorld(n,info)
 return info.ZoneNumber<240 and 3 or 4
end
local roots={{Name='Map3',children={{Name='200 | Void Spawn'}, {Name='219 | Fracture'}, {Name='201 | Forbidden'}, {Name='245 | Fantasy Spawn'}}},
 {Name='Map4',children={{Name='240 | Fantasy Spawn'}}}}
for _,r in ipairs(roots) do function r:GetChildren()return self.children end end
local function mapRoots()return roots end
local function findChild(root,key)return root and root[key] end
local diamondModel={parent='Fracture'}
function diamondModel:IsA(n)return n=='Model'end
function diamondModel:GetAttribute(n)
 if n=='ParentID' then return 'Fracture' end
 if n=='BreakableID' then return 'Diamond Breakable' end
end
Workspace={__THINGS={Breakables={GetChildren=function()return {diamondModel} end}}}
local function currentFarmZone()return 'Void Spawn'end
'''+extract('local function diamondAreas(force)','-- BOTH APIs have been observed in public source:')+r'''
local zones=diamondAreas(true)
assert(#zones==2)
assert(zones[1].name=='Void Spawn' and zones[2].name=='Fracture')
assert(state.diamondCandidateCount==2)
local nextOne=nextDiamondArea()
assert(nextOne and nextOne.name=='Fracture')
state.diamondZone='Fracture'
assert(nextDiamondArea().name=='Void Spawn', 'Now scout alternate OWNED zone even before targets stream in')
print('PASS World 3 owned-area discovery and safe rotation, excluding locked and other-world areas')
''')

# Upgrades select real surplus in Tier II/III when Tier I is exhausted.
run(r'''
math.clamp=function(v,low,high)return math.max(low,math.min(high,v))end
local function now() return 200 end
local Config={UpgradeMaterialReserve=8,MaxUpgradeInputTier=3}
local state={upgradeSelectionLast='none',upgradeTierLast='none', clients={}}
local function saveData()
 return {Inventory={
  Potion={first={id='Coins',tn=1,_am=6},second={id='Damage',tn=2,_am=20},third={id='Luck',tn=4,_am=500}},
  Enchant={first={id='Coins',tn=1,_am=11},second={id='Criticals',tn=3,_am=24}}
 }}
end
local function callMethod(...)return false,nil end
'''+extract('local function chooseLowTierUpgrade(goal)','local function tryCollectionUpgrade()')+r'''
local potion=chooseLowTierUpgrade({kind='collect_potion'})
assert(potion and potion.id=='Damage' and potion.tier==2 and potion.ingredients==3)
local enchant=chooseLowTierUpgrade({kind='collect_enchant'})
assert(enchant and enchant.id=='Criticals' and enchant.tier==3 and enchant.ingredients==5)
assert(state.upgradeTierLast=='Tier 3 Enchant')
print('PASS Tier II potion, Tier III enchant, protected reserve and ignored Tier IV')
''')

assert 'interactiveToggle(page("farm"), "DiamondZoneRotation"' in src
assert 'choice(page("machines"), "Minimum ingredient reserve"' in src
assert 'Workspace.DescendantAdded' not in src # uses the signal from Workspace safely, not global mutable objects
assert 'state.diamondMoveCount=state.diamondMoveCount+1' in src
assert 'clearMovement("upgrade")' in src
print('PASS UI options, rotation diagnostics, safe upgrade movement')
print('v3.2 isolated efficiency tests passed; server behavior still unverified')
