"""Crystal Key planner: slot analysis against the official rank-30 slot pools (mock save data)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run_modules

# Rank 30 "Warden" slot-1 pool from the BIG Games API Ranks collection
# (joekiller/node-ps99-api ranks.json, dateModified 2025-07-05):
# 21 x3 (current-area breakables), 14 collect potions, 15 collect enchants, 9 diamond breakables.
SETUP = r'''
local frozenGoals = {
  {{Type = 21, Amount = 2750}, {Type = 21, Amount = 2750}, {Type = 21, Amount = 2750},
   {Type = 14, Amount = 70}, {Type = 15, Amount = 70}, {Type = 9, Amount = 45}},
  {{Type = 21, Amount = 3500}, {Type = 14, Amount = 90}, {Type = 15, Amount = 90}, {Type = 34, Amount = 50}},
}
local rankDef = setmetatable({Goals = frozenGoals}, {__index = function(_, k) error("frozen: " .. tostring(k)) end})
rankDefinition = function(rank) if rank == 30 then return "Rank30", rankDef end return nil, nil end
'''
run_modules(r'''
local crystal = Modules.byId.crystal
local pool = crystal.slotPool(30, 1)
assert(pool[21] and pool[14] and pool[15] and pool[9] and not pool[34], "slot-1 pool read from Directory.Ranks")
assert(crystal.slotPool(31, 1) == nil, "unknown rank: no pool, never guess")

local function slots(list)
  local s = {}
  for _, q in ipairs(list) do s[q[1]] = {slot = q[1], type = q[2], amount = q[3], progress = q[4]} end
  return s
end
-- Nothing held yet: tells the player which quests to keep in slots 2-4.
local ready, status, missing = crystal.analyze(pool, slots({{1, 14, 70, 0}, {2, 34, 50, 0}, {3, 7, 10000, 0}, {4, 42, 50, 0}}))
assert(not ready and #missing == 2 and missing[1] == 9 and missing[2] == 21, status)
-- Breakables held in slot 2 only: diamonds still missing.
ready, status, missing = crystal.analyze(pool, slots({{1, 14, 70, 0}, {2, 21, 3500, 100}, {3, 7, 10000, 0}}))
assert(not ready and #missing == 1 and missing[1] == 9, status)
-- Slot 1 itself is a breakable quest: must finish it first.
ready, status = crystal.analyze(pool, slots({{1, 21, 2750, 0}, {2, 34, 50, 0}, {3, 9, 900, 0}}))
assert(not ready and status:find("finish slot 1", 1, true), status)
-- A held quest that is already complete does not count as held.
ready, status, missing = crystal.analyze(pool, slots({{1, 15, 70, 0}, {2, 21, 3500, 3500}, {3, 9, 900, 10}}))
assert(not ready and #missing == 1 and missing[1] == 21, status)
-- The method's setup: slot 1 collect, 21 and 9 held in slots 2-4.
ready, status = crystal.analyze(pool, slots({{1, 15, 70, 12}, {2, 21, 3500, 100}, {3, 9, 900, 5}, {4, 42, 50, 0}}))
assert(ready and status:find("collect enchants", 1, true), status)
-- Unreadable pools never claim readiness.
ready, status = crystal.analyze(nil, slots({{1, 15, 70, 12}}))
assert(not ready and status:find("unreadable", 1, true))

-- tick(): reads Save.Goals by slot key and counts keys; read-only (no requests).
fake.save = {Rank = 30, Goals = {[1] = {Type = 14, Amount = 70, Progress = 3, UID = "a"},
    [2] = {Type = 21, Amount = 3500, Progress = 9, UID = "b"}, [4] = {Type = 9, Amount = 1200, Progress = 0, UID = "c"}},
    Inventory = {Misc = {k = {id = "Crystal Key", _am = 7}}}}
tickModule("crystal")
assert(crystal.plan.ready == true and crystal.plan.keys == 7, crystal.plan.status)
assert(#requests == 0, "planner never sends requests")
print("PASS crystal planner: live slot pools, blockers, slot-1 rule, completion awareness, read-only")
''', names=["15_crystal.lua"], setup=SETUP, name="crystal")
print("PASS test_crystal")

# ---------------------------------------------------------------- runner
run_modules(r'''
local crystal, recorder = Modules.byId.crystal, Modules.byId.recorder
assert(Config.CrystalKeyMode == false, "spending mode is OFF by default")
assert(Config.CrystalKeyReserve == 100, "100-key reserve by default (VY AutoRank's protected setting)")
Config.CrystalKeyReserve = 0
-- World 1 map with the Castle chest pad (path from idonthaveoneatm 2025-09).
local pad = {Name = "Pad", Parent = true, Position = Vector3.new(100, 0, 0), CFrame = CFrame.new(100, 0, 0),
  IsA = function(_, c) return c == "BasePart" end, FindFirstChild = function() return nil end}
local chest = {FindFirstChild = function(_, n) return n == "Pad" and pad or nil end}
local interact = {FindFirstChild = function(_, n) return n == "CrystalChest" and chest or nil end}
local castle = {FindFirstChild = function(_, n) return n == "INTERACT" and interact or nil end}
local map = {Name = "Map", FindFirstChild = function(_, n) return n == "3 | Castle" and castle or nil end}
mapRoots = function() return {map} end
Vector3.new = function(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3) end
V3 = {__sub = function(a, b) return setmetatable({X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z}, V3) end,
  __index = function(t, k) if k == "Magnitude" then return math.sqrt(t.X^2 + t.Y^2 + t.Z^2) end end}
pad.Position = Vector3.new(100, 0, 0)
local root = currentRoot()
root.Position = Vector3.new(0, 0, 0)
local plusMeta = {__add = function(a, b) return {X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z} end}
pad.CFrame = setmetatable({X = 100, Y = 0, Z = 0}, plusMeta)
-- Save keyed by strings; Stars decides the slot.
fake.save = {Rank = 30, RankStars = 5, Goals = {["1"] = {Type = 14, Amount = 70, Progress = 3, Stars = 1, UID = "s1"},
    ["2"] = {Type = 21, Amount = 3500, Progress = 9, Stars = 2, UID = "s2"},
    ["3"] = {Type = 9, Amount = 900, Progress = 0, Stars = 3, UID = "s3"}},
    Inventory = {Misc = {k = {id = "Crystal Key", _am = 3}}}}
state.world = {number = 1}
state.running = true
Config.CrystalKeyMode = true
-- Wrong world: released, no request.
state.world = {number = 2}
tickModule("crystal")
assert(crystal.runState.reason:find("World 1", 1, true) and sent("CrystalKey_Unlock") == 0 and not state.farmHold)
state.world = {number = 1}
-- No teaching needed: first tick moves onto the pad and holds farming.
advance(1) tickModule("crystal")
assert(state.farmHold == true and crystal.runState.phase == "moving to chest", crystal.runState.phase)
root.Position = Vector3.new(100, 0, 0)
fake.responses.CrystalKey_Unlock = true
advance(2) tickModule("crystal")
local r = lastRequest("CrystalKey_Unlock")
assert(r and #r.args == 0 and r.invoke == true, "live-confirmed request: Invoke with no arguments")
-- Replication arrives late: nothing changes for a few seconds -> still pending, no second request.
advance(3) tickModule("crystal")
assert(sent("CrystalKey_Unlock") == 1 and crystal.runState.pending ~= nil, "waits for replicated credit")
-- Keys Mastery kept the key: only quest progress moves -> still confirmed.
fake.save.Goals["1"].Progress = 5
advance(1) tickModule("crystal")
assert(crystal.runState.opened == 1 and Modules.stat("crystal", "open").confirmed == 1, "credit without key use counts")
advance(2) tickModule("crystal")
assert(sent("CrystalKey_Unlock") == 2)
-- Key consumed, no progress yet -> confirmed by the key count.
fake.save.Inventory.Misc.k._am = 2
advance(1) tickModule("crystal")
assert(crystal.runState.opened == 2)
-- Three opens that change nothing switch the mode off and release the hold.
for _ = 1, 3 do advance(2) tickModule("crystal") advance(11) tickModule("crystal") end
assert(Config.CrystalKeyMode == false and state.farmHold == false, crystal.runState.reason)
-- A taught request overrides the evidenced one.
Config.CrystalKeyMode = true
crystal.runState.misses = 0
local net = {Invoke = function(name, ...) return true end}
fake.clients.Network = net
state.clients = fake.clients
assert(recorder.start(20))
net.Invoke("ChestThing_Open", "k")
recorder.stop()
assert(recorder.learn("crystalChest", recorder.find({"chest"})))
assert(crystal.opener().name == "ChestThing_Open")
fake.responses.ChestThing_Open = true
advance(2) tickModule("crystal")
local t = lastRequest("ChestThing_Open")
assert(t and t.args[1] == "k", "taught request replayed with the current key UID")
-- Setup lost (e.g. rank up rerolled quests): release immediately.
fake.save.Goals = {["1"] = {Type = 21, Amount = 2750, Progress = 0, Stars = 1}}
advance(11) tickModule("crystal")
advance(1) tickModule("crystal")
assert(state.farmHold == false and crystal.runState.reason:find("setup", 1, true), crystal.runState.reason)
crystal.onPause()
assert(crystal.runState.phase == "off")
print("PASS crystal runner: live-confirmed no-arg open, Stars slots, credit by key OR progress, fail-safe off, taught override")
''', names=["05_recorder.lua", "15_crystal.lua"], setup=SETUP, name="crystal-runner")
print("PASS test_crystal runner")
