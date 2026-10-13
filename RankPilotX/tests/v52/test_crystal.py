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
