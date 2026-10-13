"""Action recorder: captures the game's own Network calls during a short window and restores them."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run_modules

run_modules(r'''
local recorder = Modules.byId.recorder
local sentToGame = {}
local net = {
  Invoke = function(name, ...) table.insert(sentToGame, name) return true end,
  Fire = function(name, ...) table.insert(sentToGame, name) end,
}
local originalInvoke = net.Invoke
fake.clients.Network = net
state.clients = fake.clients
fake.save = {Inventory = {Misc = {keyuid = {id = "Crystal Key", _am = 5}}}}
assert(recorder.start(15))
assert(net.Invoke ~= originalInvoke, "wrapper installed during the window")
-- The game opens the chest with the key UID; background noise is ignored.
net.Fire("Breakables_PlayerDealDamage", "123")
net.Invoke("Some_Open", "keyuid", 1, true)
net.Invoke("Weird_Call", {nested = true})
assert(#sentToGame == 3, "calls still reach the game unchanged")
assert(#recorder.rec.captures == 2, "noise filtered")
local c = recorder.find({"open"})
assert(c and c.name == "Some_Open" and c.method == "Invoke")
assert(type(c.template[1]) == "table" and c.template[1].item == "Crystal Key", "UID stored as item reference")
assert(c.template[2] == 1 and c.template[3] == true)
assert(recorder.rec.captures[2].template == nil and recorder.rec.captures[2].problem:find("table", 1, true),
  "non-primitive args are never replayed")
-- Window end restores the original functions.
advance(16)
tickModule("recorder")
assert(net.Invoke == originalInvoke and recorder.rec.active == false, "original restored")
-- Learn + resolve: the stored item reference becomes the CURRENT stack UID.
assert(recorder.learn("crystalChest", c))
local action = recorder.learned("crystalChest")
assert(action and action.name == "Some_Open")
fake.save.Inventory.Misc = {newuid = {id = "Crystal Key", _am = 2}}
local args = recorder.resolve(action.args)
assert(args[1] == "newuid" and args[2] == 1 and args[3] == true)
fake.save.Inventory.Misc = {}
local none, why = recorder.resolve(action.args)
assert(none == nil and why:find("Crystal Key", 1, true), "no key -> no replay")
-- Stop/cleanup restores even mid-window.
assert(recorder.start(30))
recorder.cleanup()
assert(net.Invoke == originalInvoke)
-- Read-only Network tables are handled without errors.
fake.clients.Network = setmetatable({}, {__index = net, __newindex = function() error("frozen") end})
state.clients = fake.clients
local ok, reason = recorder.start(10)
assert(ok == false and reason:find("read-only", 1, true), tostring(reason))
print("PASS recorder: capture window, noise filter, UID templates, restore on end/cleanup, frozen tables")
''', names=["05_recorder.lua"], name="recorder")
print("PASS test_recorder")
