"""Farm tools (ultimates, toys, TNT) and fruit-queue / boost logic (mock data, not live PS99)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run_modules

run_modules(r'''
local tools = Modules.byId.farmtools
assert(Config.AutoUltimate == true and Config.AutoUseToys == false and Config.AutoUseTNT == false)
state.running, Config.AutoFarm = true, true
-- No UltimateCmds: nothing is fired.
tickModule("farmtools")
assert(sent("Ultimates: Activate") == 0 and tools.ult.last == "UltimateCmds unavailable")
-- Equipped but IsCharged missing: never fire blindly.
local charged = false
local item = {GetId = function() return "Ground Pound" end}
advance(61)
fake.clients.UltimateCmds = {GetEquippedItem = function() return item end}
tickModule("farmtools")
assert(sent("Ultimates: Activate") == 0 and tools.ult.last:find("not firing blindly", 1, true))
-- Charging: wait. Charged: fire once with the equipped id, confirm when the charge resets.
fake.clients.UltimateCmds.IsCharged = function(id) assert(id == "Ground Pound") return charged end
tickModule("farmtools")
assert(sent("Ultimates: Activate") == 0)
charged = true
fake.responses["Ultimates: Activate"] = true
tickModule("farmtools")
local r = lastRequest("Ultimates: Activate")
assert(r and r.args[1] == "Ground Pound" and r.invoke == true)
tickModule("farmtools")
assert(sent("Ultimates: Activate") == 1, "pending: no double fire while still charged")
charged = false
advance(1) tickModule("farmtools")
assert(Modules.stat("farmtools", "ultimate").confirmed == 1)
-- Hatch-first window owns the character: no ultimate.
charged = true
setHatchWindow(true)
advance(10) tickModule("farmtools")
assert(sent("Ultimates: Activate") == 1)
setHatchWindow(false)

-- Toys: consumed -> confirmed; not consumed twice -> disabled.
Config.AutoUseToys = true
fake.save = {Inventory = {Misc = {t1 = {id = "Toy Ball", _am = 3}, t2 = {id = "Squeaky Toy", _am = 1}}}}
fake.responses.ToyBall_Consume = true
fake.responses.SqueakyToy_Consume = true
charged = false
advance(10) tickModule("farmtools")
assert(sent("SqueakyToy_Consume") == 1 and sent("ToyBall_Consume") == 1)
assert(#lastRequest("ToyBall_Consume").args == 0, "no-argument remote")
fake.save.Inventory.Misc.t1._am = 2
advance(2) tickModule("farmtools")
assert(Modules.stat("farmtools", "toys").confirmed == 1, "Toy Ball confirmed")
advance(7) tickModule("farmtools")
assert(Modules.stat("farmtools", "toys").failed == 1, "Squeaky Toy not consumed")
advance(700) tickModule("farmtools")
advance(7) tickModule("farmtools")
assert(tools.itemState["Squeaky Toy"].disabled == true, "disabled after two misses")
local before = sent("SqueakyToy_Consume")
advance(700) tickModule("farmtools")
assert(sent("SqueakyToy_Consume") == before, "disabled items are never sent again")
tools.recheck()
assert(tools.itemState["Squeaky Toy"].disabled == false)
-- No items, nothing sent.
Config.AutoUseTNT = true
local tntBefore = sent("TNT_Consume")
advance(30) tickModule("farmtools")
assert(sent("TNT_Consume") == tntBefore, "no TNT owned")
print("PASS farmtools: ultimate gating/confirmation, hatch priority, toys confirm/disable, TNT ownership")

-- Fruit queue: eat only the gap to the queue limit, never below the reserve.
local items = Modules.byId.items
Config.AutoEatFruits = true
Config.FruitReserve = 10
fake.save = {Inventory = {Fruit = {a = {id = "Apple", _am = 40}, b = {id = "Banana", _am = 12}}}}
fake.responses["Fruits: Consume"] = true
fake.clients.FruitCmds = {GetActiveFruits = function() return {Apple = {{1, 2, 3}, {4, 5}}, Banana = {}} end,
    ComputeFruitQueueLimit = function() return 20 end}
advance(100)
tickModule("items")
r = lastRequest("Fruits: Consume")
assert(r.args[1] == "a" and r.args[2] == 15, "Apple: 20 limit - 5 queued = 15; got " .. tostring(r.args[2]))
fake.save.Inventory.Fruit.a._am = 25
advance(3) tickModule("items")
advance(1) tickModule("items")
r = lastRequest("Fruits: Consume")
assert(r.args[1] == "b" and r.args[2] == 2, "Banana: limited by reserve 12-10 = 2")
Config.AutoEatFruits = false

-- Boosts: skip active boosts, keep one of each.
Config.AutoUseBoosts = true
fake.save = {Inventory = {Consumable = {c1 = {id = "Damage Booster", _am = 3}, c2 = {id = "XP Booster", _am = 1}}},
    Consumables = {["Damage Booster"] = {{t = 1}}}}
fake.responses.Consumables_Consume = true
advance(100) tickModule("items")
assert(sent("Consumables_Consume") == 0, "active boost skipped, single XP booster kept as reserve")
fake.save.Consumables = {}
advance(100) tickModule("items")
r = lastRequest("Consumables_Consume")
assert(r and r.args[1] == "c1" and r.args[2] == 1 and r.invoke == true)
print("PASS items v2: fruit queue gap, reserve cap, boost active/reserve gating")
''', names=["30_items.lua", "50_farmtools.lua"], name="farmtools")
print("PASS test_farmtools")
