"""Focused Lua 5.4 mocks for v3.8, never a claim of live PS99 behavior."""
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
def run(x):
  L=lib.luaL_newstate();lib.luaL_openlibs(L)
  try:
    code=lib.luaL_loadstring(L,x.encode())
    assert code==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
    code=lib.lua_pcallk(L,0,0,0,0,None)
    assert code==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
  finally:lib.lua_close(L)
def segment(a,b):
  return s[s.index(a):s.index(b,s.index(a))]
compatible=re.sub(r'local (\w+):\s*(?:any|number\??)\s*=',r'local \1 =',s)
L=lib.luaL_newstate();lib.luaL_openlibs(L)
try:
  assert lib.luaL_loadstring(L,compatible.encode())==0,(lib.lua_tolstring(L,-1,None)or b'').decode()
finally:lib.lua_close(L)
print('PASS entire hub Lua 5.4 compatible parse (Luau annotations retained in deliverable)')
mock='''
local clock=1000
local function now()return clock end
local state={diamondVisits={},diamondZone=nil,world={zone='Tech Spawn'},diamondLastStatus='',diamondScoutLast='',diamondChosenTargetCount=0}
local Config={DiamondVisitCooldown=65}
local areas={{name='Tech Spawn',number=100},{name='Neo Forest',number=101},{name='Cyber Castle',number=102}}
local counts={['Tech Spawn']=0,['Neo Forest']=0,['Cyber Castle']=0}
local function diamondAreas()return areas end
local function diamondLoadedTargetCounts()return counts end
local function zoneDirectoryInfo(n)
 for _,v in ipairs(areas)do if v.name==n then return {ZoneNumber=v.number} end end
 return nil
end
'''
run(mock+segment('local function nextDiamondArea()','-- BOTH APIs have been observed')+'''
local first=nextDiamondArea()
assert(first~=nil and first.name=='Neo Forest','Explore nearest owned unloaded target area')
state.diamondVisits[first.name]=clock
state.diamondZone=first.name
counts['Cyber Castle']=3
local second=nextDiamondArea()
assert(second.name=='Cyber Castle' and state.diamondChosenTargetCount==3,'Prefer observed diamond-rich area')
clock=1006
state.diamondVisits['Cyber Castle']=clock
state.diamondZone='Cyber Castle'
local third=nextDiamondArea()
assert(third.name=='Tech Spawn','Do not retry recently visited zones when another owned zone exists')
print('PASS bounded owned-area scouting and target-prioritized routing')
''')
petMock='''
local function typeof(v)return type(v)=='table' and v.__type or type(v)end
local state={petVisuals=setmetatable({}, {__mode='k'}), petVisualBoundFolders=setmetatable({}, {__mode='k'}),petHidden=0,petVisualScannedAt=0,clients={}}
local Config={HidePetVisuals=true,VisualRefreshSeconds=5}
local LocalPlayer={}
local Workspace={FindFirstChild=function()return nil end}
local function findChild(parent,name)return parent and parent:FindFirstChild(name)end
local function callMethod(tbl,name,...)
 if type(tbl)~='table' or type(tbl[name])~='function' then return false,nil end
 return pcall(tbl[name],...)
end
local function now()return 100 end
local part={__type='Instance',class='BasePart',LocalTransparencyModifier=0.3}
function part:IsA(name)return name==self.class end
local petModel={__type='Instance',class='Model'}
function petModel:IsA(name)return name=='Model'end
function petModel:GetDescendants()return {part}end
local pet={owner=LocalPlayer,model=petModel}
state.clients.PlayerPet={GetByPlayer=function()return {pet}end}
'''
run(petMock+segment('local function setPetVisual(node,hide)','local function aimPetsAt(')+'''
refreshPetVisuals(true)
assert(state.petHidden==1 and part.LocalTransparencyModifier==1,'pet part hides without deleting')
assert(petModel.__type=='Instance' and pet.owner==LocalPlayer,'pet record untouched')
restorePetVisuals()
assert(part.LocalTransparencyModifier==0.3 and state.petHidden==0,'pet appearance restored exactly')
print('PASS non-destructive pet suppression and unload restoration')
''')
lootMock='''
local function typeof(v)return type(v)=='table' and v.__type or type(v)end
local state={lootbagVisuals=setmetatable({}, {__mode='k'}),lootbagHidden=0}
local part={__type='Instance',class='BasePart',LocalTransparencyModifier=0.15}
function part:IsA(n)return n==self.class end
'''
run(lootMock+segment('local function setLootbagVisual(node,hide)','local function refreshLootbagVisuals(force)')+'''
setLootbagVisual(part,true)
assert(part.LocalTransparencyModifier==1 and state.lootbagHidden==1)
setLootbagVisual(part,false)
assert(part.LocalTransparencyModifier==0.15,'never delete claimable lootbags')
print('PASS lootbag cosmetic-only suppression and restoration')
''')
assert 'blockGoal(oldFarm,Config.FarmQuestRetrySeconds' in s
assert 'local farmGoal=chooseFarmGoal()' in s
assert 'state.farmSwitchCount=state.farmSwitchCount+1' in s
assert 'DiamondScoutVersion = 1' in s
assert 'AutoRainbowConversion = true' in s
assert 'HidePetVisuals = true' in s
print('PASS quest deferral, retry, rainbow pipeline and setting migration invariants')
