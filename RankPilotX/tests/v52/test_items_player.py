"""Items & Boosts, Drops & Rewards and player utilities (mock data, not live PS99)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run_modules

run_modules(r'''
local items = Modules.byId.items
assert(Config.AutoEatFruits == false and Config.AutoUsePotions == false and Config.AutoUseFlags == false,
    "spending toggles default OFF")
fake.save = {Inventory = {
    Fruit = {f1 = {id = "Apple", _am = 30}, f2 = {id = "Banana", _am = 8}, f3 = {id = "Apple", sh = true, _am = 50}},
    Potion = {p1 = {id = "Coins", tn = 2, _am = 9}, p2 = {id = "Coins", tn = 4, _am = 6}, p3 = {id = "Damage", tn = 1, _am = 5}},
    Misc = {m1 = {id = "Diamonds Flag", _am = 5}, m2 = {id = "Comet", _am = 9}}}}
-- Inactive: nothing is sent.
assert(tickModule("items") == false and #requests == 0)
-- Fruits: reserve 10 excludes Banana (8); shiny Apple excluded by default.
Config.AutoEatFruits = true
fake.responses["Fruits: Consume"] = true
tickModule("items")
local r = lastRequest("Fruits: Consume")
assert(r and r.args[1] == "f1" and r.args[2] == 1 and r.invoke == false, "eats the non-shiny Apple stack")
-- No confirmation yet -> no second fruit request while pending.
advance(1) tickModule("items")
assert(sent("Fruits: Consume") == 1)
-- Save shows the stack shrank: confirmed.
fake.save.Inventory.Fruit.f1._am = 29
advance(2) tickModule("items")
assert(Modules.stat("items", "fruit").confirmed == 1)
-- Per-fruit cooldown blocks an immediate second Apple.
advance(5) tickModule("items")
assert(sent("Fruits: Consume") == 1)
-- An unconsumed request is marked failed after 12 s and that fruit backs off.
advance(300)
tickModule("items")
assert(sent("Fruits: Consume") == 2)
advance(13) tickModule("items")
assert(Modules.stat("items", "fruit").failed == 1)
-- An active "use fruit" rank quest owns the fruit stacks.
state.goals = {{kind = "fruit", required = 5, progress = 1}}
advance(2000) tickModule("items")
assert(sent("Fruits: Consume") == 2, "quest lane has priority")
state.goals = {}
Config.AutoEatFruits = false

-- Potions: highest tier per type above reserve 5 (Damage 5 is at the reserve, excluded).
Config.AutoUsePotions = true
fake.responses["Potions: Consume"] = true
tickModule("items")
r = lastRequest("Potions: Consume")
assert(r and r.args[1] == "p2", "tier 4 Coins potion, not tier 2")
Config.AutoUsePotions = false

-- Flags: only "* Flag" Misc items; never inside an instance; FlexibleFlagCmds result respected.
Config.AutoUseFlags = true
local consumed = {}
fake.clients.FlexibleFlagCmds = {Consume = function(id, uid, n) table.insert(consumed, {id, uid, n}) return false, "different flag already placed" end}
tickModule("items")
assert(#consumed == 1 and consumed[1][1] == "Diamonds Flag" and consumed[1][2] == "m1" and consumed[1][3] == 1)
assert(Modules.stat("items", "flag").accepted == 0, "refusal is not success")
fake.clients.InstancingCmds = {IsInInstance = function() return true end}
advance(1000) tickModule("items")
assert(#consumed == 1, "no flags inside instances")
print("PASS items: defaults off, reserves, shiny skip, pending/confirm/fail, quest priority, tiers, flags")

-- Rewards: Save-confirmed free gifts.
local rewards = Modules.byId.rewards
Config.AutoFreeGifts = true
local before = #requests
fake.save = {FreeGiftsRedeemed = {1, 2}}
tickModule("rewards")
fake.save.FreeGiftsRedeemed = {1, 2, 3}
tickModule("rewards")
assert(Modules.stat("rewards", "freegifts").confirmed == 1)
assert(#requests == before, "rewards module sends nothing itself")
print("PASS rewards: free gift confirmation from Save")

-- Player: anti-AFK connects once, walk speed saved/restored, rejoin requires a second click.
local player = Modules.byId.player
local idleFn
local hum = {WalkSpeed = 16, Parent = true}
LocalPlayer.Idled = {Connect = function(_, fn) idleFn = fn return {Disconnect = function() idleFn = nil end} end}
LocalPlayer.Character = {FindFirstChildOfClass = function() return hum end}
local clicks = 0
fake.services = {VirtualUser = {CaptureController = function() end, ClickButton2 = function() clicks = clicks + 1 end}}
Vector2 = {new = function() return {} end}
tickModule("player")
assert(type(idleFn) == "function")
idleFn()
assert(clicks == 1 and Modules.stat("player", "antiafk").confirmed == 1)
Config.WalkSpeedOverride = 32
state.running = true
tickModule("player")
assert(hum.WalkSpeed == 32 and player.saved.walkSpeed == 16)
player.onPause()
assert(hum.WalkSpeed == 16 and Config.WalkSpeedOverride == 32, "pause restores, setting kept")
local teleports = 0
fake.services.TeleportService = {TeleportToPlaceInstance = function() teleports = teleports + 1 end, Teleport = function() teleports = teleports + 1 end}
assert(player.confirmed("REJOIN") == false and player.confirmed("REJOIN") == true)
advance(10)
assert(player.confirmed("REJOIN") == false, "confirmation window expires")
player.cleanup()
assert(idleFn == nil, "cleanup disconnects anti-AFK")
print("PASS player: anti-AFK, reversible walk speed, double-click server actions, cleanup")
''', names=["20_rewards.lua", "30_items.lua", "60_player.lua"], name="items-player")
print("PASS test_items_player")
