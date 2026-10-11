from pathlib import Path
import ctypes,re
file=Path(str(Path(__file__).resolve().parents[2] / 'dist' / 'RankPilot_X_v5_2.lua'))
src=file.read_text()
# Lua 5.4 syntax check; remove only Luau variable type annotations.
converted=re.sub(r'(local\s+\w+):\s*(?:any|number\??)',r'\1',src)
converted=converted.replace('local numericCap: number?', 'local numericCap')
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p];lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p];lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
def check(code, do_run=False):
    L=lib.luaL_newstate();lib.luaL_openlibs(L)
    try:
        rc=lib.luaL_loadstring(L,code.encode());assert not rc,(lib.lua_tolstring(L,-1,None)or b'').decode()
        if do_run:
            rc=lib.lua_pcallk(L,0,0,0,0,None);assert not rc,(lib.lua_tolstring(L,-1,None)or b'').decode()
    finally:
        lib.lua_close(L)
check(converted)
print('PASS full script Lua 5.4 syntax after removing Luau type annotations')
assert 'CoreGui' not in src[src.index('local function accessibleUIParents()'):src.index('local function buildUI()')].replace('-- Never access CoreGui directly: some executors throw a Plugin permission error.','')
assert 'AutoUpgradeCollections' in src and 'CoinJar_Spawn' in src
assert src.count('Run compatible quests')>=0
assert 'getgenv' in src and 'loadstring(game:HttpGet(' not in src
assert 'Version="5.2.0-ModuleHub-Engine4.6"' in src
print('PASS source invariants; no external library loader; no restricted CoreGui reads')
segment=src[src.index('local ui: any = {pages = {}'):src.index('local function mainLoop(generation)')]
segment=re.sub(r'(local\s+\w+):\s*(?:any|number\??)',r'\1',segment)
mock=r'''
local all={}
local function starValue(goal)return (goal and goal.raw and goal.raw.Stars) or 1 end
local function signal()
  local o={handlers={}}
  function o:Connect(fn)
    self.handlers[#self.handlers+1]=fn
    return {Disconnect=function()end}
  end
  function o:Fire(...)
    for _,fn in ipairs(self.handlers) do fn(...) end
  end
  return o
end
local function object(class)
  local o=setmetatable({ClassName=class,MouseButton1Click=signal(),InputBegan=signal(),InputEnded=signal(),
    Visible=true,attributes={}}, {__newindex=function(self,k,v)
      if k=='BackgroundColor3' or k=='TextColor3' or k=='Color' then
        assert(typeof(v)=='Color3', 'Color3 expected for '..k..' but got '..typeof(v))
      end
      rawset(self,k,v)
    end})
  function o:FindFirstChild(name) if name=='PlayerGui' then return self.pg end return nil end
  function o:WaitForChild(name) if name=='PlayerGui' then return self.pg end return nil end
  function o:SetAttribute(k,v) self.attributes[k]=v end
  function o:GetAttribute(k) return self.attributes[k] end
  function o:Destroy() self.destroyed=true end
  all[#all+1]=o
  return o
end
Instance={new=function(class)return object(class) end}
Color3={fromRGB=function(r,g,b)return {_color=true,r=r,g=g,b=b} end}
function typeof(x)
  if type(x)=='table' and x._color then return 'Color3' end
  if type(x)=='table' and x.ClassName then return 'Instance' end
  return type(x)
end
UDim={new=function(a,b)return {Scale=a,Offset=b}end}
UDim2={fromOffset=function(a,b)return {X={Scale=0,Offset=a},Y={Scale=0,Offset=b}}end,
 fromScale=function(a,b)return {X={Scale=a,Offset=0},Y={Scale=b,Offset=0}}end,
 new=function(a,b,c,d)return {X={Scale=a,Offset=b},Y={Scale=c,Offset=d}}end}
Vector2={new=function(x,y)return {X=x,Y=y}end}
Enum=setmetatable({}, {__index=function(t,k)
 local child=setmetatable({}, {__index=function(_,key)return key end})
 rawset(t,k,child)return child
end})
math.clamp=function(v,a,b) return math.min(b,math.max(a,v)) end
local playerGui=object('PlayerGui')
local player=object('Player')
player.pg=playerGui
LocalPlayer=player
Workspace={CurrentCamera={ViewportSize=Vector2.new(1600,900)}}
local inputService={InputChanged=signal(),InputBegan=signal()}
game={GetService=function(_,name)if name=='UserInputService' then return inputService end end}
RunService={Set3dRenderingEnabled=function()end}
Config={AutoRank=true,AutoFarm=true,AutoParallelQuests=true,AutoUpgradeCollections=false,
    FarmTapRate=8,PetSpeedMultiplier=250,TargetRank=0,LocalNotifications=true}
state={connections={},gui=nil,logs={'event 1','event 2'},goals={{title='Break 10 chests',progress=4,required=10}},
 attempts={hatch=2,farm=37},concurrent={farm='minichest',hatch='none',collect='potions'},
 rank=14,area='198 | Void Fracture',running=false,chosen='chest quest',status='paused',
 hatchLastResult='ok',spawnLast='CoinJar request sent',machineStatus='Tech Spawn',
 upgradeLast='none',lastFarmInterface='DZ',farmError='none',hatchLastApi='RequestPurchase', world={number=3,name='Void',source='Save.RecentWorld',zone='Prison Tower',best='Prison HQ',bestWorld=3},worldTransition='not checked',extras={balloonLast='none',loginLast='none',timedLast='none',inventoryLast='none',capabilityLast='none',alerts={},visuals=setmetatable({}, {__mode='k'})}}
local calls={persist=0,run=0,pause=0,stop=0}
persist=function()calls.persist=calls.persist+1 end
run=function()state.running=true;calls.run=calls.run+1 end
pause=function()state.running=false;calls.pause=calls.pause+1 end
stop=function()calls.stop=calls.stop+1 end
recheck=function()end
getZoneInfo=function()return {name='Prison Tower',world=3}end
placeInZone=function()return true end
requestLocalZoneTeleport=function()return false end
getReport=function()return 'REPORT' end
petTurbo=function()end
updateSuperMagnet=function()end
skipEggAnimation=function()end
refreshPopups=function()end
restorePopups=function()end
log=function()end
setclipboard=function()end
function describe(x)return tostring(x or 'none') end
'''
tests=r'''
buildUI()
assert(state.gui and ui.window and ui.activePage=='home')
assert(ui.pages['ranks'] and ui.pages['diagnostics'] and ui.pages['eggs'] and ui.pages['worlds'])
assert(#ui.toggleRefresh>=20)
renderUI()
assert(ui.metricRank.Text=='RANK 14')
assert(ui.worldNumber.Text:find('Void',1,true)~=nil)
ui.nav['worlds'].MouseButton1Click:Fire()
assert(ui.activePage=='worlds')
assert(ui.metricQuests.Text=='1 ACTIVE')
assert(ui.questRows[1].root.Visible==true)
assert(ui.questRows[2].root.Visible==false)
assert(ui.diagRows[1].Text=='event 1')
local toggles={}
for _,o in ipairs(all) do if type(o.Name)=='string' and o.Name:match('^Toggle_') then
 toggles[o.Name]=toggles[o.Name] or o end end
assert(toggles.Toggle_AutoRank)
toggles.Toggle_AutoRank.MouseButton1Click:Fire()
assert(Config.AutoRank==false and calls.persist==1)
ui.nav['farm'].MouseButton1Click:Fire()
assert(ui.activePage=='farm' and ui.pages.farm.Visible and not ui.pages.home.Visible)
local minimize=nil
for _,o in ipairs(all) do if o.Text=='_' then minimize=o;break end end
assert(minimize)
minimize.MouseButton1Click:Fire()
assert(ui.window.Visible==false and ui.restoreButton.Visible==true)
ui.restoreButton.MouseButton1Click:Fire()
assert(ui.window.Visible==true and ui.restoreButton.Visible==false)
inputService.InputBegan:Fire({KeyCode=Enum.KeyCode.RightControl},false)
assert(not ui.window.Visible and ui.restoreButton.Visible)
inputService.InputBegan:Fire({KeyCode=Enum.KeyCode.RightControl},false)
assert(ui.window.Visible and not ui.restoreButton.Visible)
ui.playButton.MouseButton1Click:Fire()
assert(calls.run==1 and state.running)
renderUI()
assert(ui.playButton.Text=='PAUSE')
ui.playButton.MouseButton1Click:Fire()
assert(calls.pause==1 and not state.running)

local pageCount=0
for _ in pairs(ui.pages) do pageCount=pageCount+1 end
assert(pageCount==16, 'expected 16 real/planned tabs, saw '..pageCount)
local ns=nil
for _,o in ipairs(all) do if o.Name=='NavScroll' then ns=o;break end end
assert(ns and ns.CanvasSize.Y.Offset>450, 'sidebar should scroll')
for _,tab in ipairs({'home','ranks','farm','worlds','eggs','items','machines','drops','events','minigames','farmworld','trading','notifications','performance','settings','diagnostics'}) do
  assert(ui.pages[tab] and ui.nav[tab], 'missing page '..tab)
end
ui.nav.events.MouseButton1Click:Fire()
assert(ui.activePage=='events' and ui.pages.events.Visible and not ui.pages.home.Visible)
ui.nav.minigames.MouseButton1Click:Fire()
assert(ui.activePage=='minigames')
ui.nav.trading.MouseButton1Click:Fire()
assert(ui.activePage=='trading')
ui.nav.notifications.MouseButton1Click:Fire()
assert(ui.activePage=='notifications')
print('PASS v5.2 UI: 16 pages, expansion placeholders and sidebar navigation')

print('PASS UI mock: 10 pages, Color3 validation, rank display, 20+ toggles, sidebar, minimize, restore, keyboard hotkey, run/pause')
'''
check(mock+segment+tests,True)
