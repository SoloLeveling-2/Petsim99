"""Rank telemetry/stall recovery and live-event quest focus (mock data, not live PS99)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run_modules

run_modules(r'''
local rank = Modules.byId.rank
assert(rank and Config.RankStallRecovery == true and Config.RankStallMinutes == 8)
local rechecks = 0
recheck = nil
-- Save with two goals keyed by UID; titles change as counts change, UIDs do not.
fake.save = {Rank = 12, RankStars = 3, RedeemedRankRewards = {["1"] = true},
    Goals = {{UID = "g1", Amount = 100, Progress = 10, Type = 1}, {UID = "g2", Amount = 4, Progress = 0, Type = 2}}}
assert(rank.sample(fake.save) == 0, "first sample is a baseline")
advance(60)
fake.save.Goals[1].Progress = 40
assert(rank.sample(fake.save) == 30)
advance(60)
-- g2 disappears while stars rise: counted as one completed goal.
fake.save.Goals = {{UID = "g1", Amount = 100, Progress = 55}}
fake.save.RankStars = 5
fake.save.RedeemedRankRewards = {["1"] = true, ["2"] = true}
assert(rank.sample(fake.save) == 15)
assert(rank.tele.completed == 1 and rank.tele.rewardsConfirmed == 1)
local perMinute, questsPerMinute, starsPerHour = rank.rates()
assert(math.abs(perMinute - 22.5) < 0.01, perMinute)
assert(questsPerMinute > 0.6 and starsPerHour > 59, questsPerMinute .. " " .. starsPerHour)
-- A goal replaced WITHOUT stars rising is not counted as completed.
advance(30)
fake.save.Goals = {{UID = "g3", Amount = 10, Progress = 0}}
rank.sample(fake.save)
assert(rank.tele.completed == 1)

-- Stall watchdog: stage 1 after N minutes, stage 2 after 2N, once each.
state.running = true
Config.AutoRank = true
local calledRecheck = 0
local oldTele = rank.tele.lastCreditAt
advance(8 * 60 + 1)
tickModule("rank")
assert(rank.tele.stage == 1 and rank.tele.recoveries == 1, "stage 1")
tickModule("rank")
assert(rank.tele.recoveries == 1, "stage 1 runs once")
state.movementOwner, state.movementUntil, state.farmGoal = "farm", now() + 999, {kind = "farm"}
advance(8 * 60)
tickModule("rank")
assert(rank.tele.stage == 2 and state.movementOwner == nil and state.farmGoal == nil, "stage 2 resets targeting")
-- Progress resets the watchdog.
fake.save.Goals[1].Progress = 3
tickModule("rank")
assert(rank.tele.stage == 0)
-- Pausing is not stalling: START resets the idle clock.
advance(3600)
rank.onStart()
tickModule("rank")
assert(rank.tele.stage == 0, "no recovery right after START")
-- Missing save never crashes the module.
fake.save = nil
tickModule("rank")
assert(rank.tele.last == "Save.Get unavailable")
print("PASS rank telemetry, completion detection, stall recovery stages, pause safety")

-- Events: GetActive shape from VY AutoRank; focus only in the farm zone.
local events = Modules.byId.events
assert(events.kindOf("Basic Coin Jar") == "coinjar" and events.kindOf("Piñata Party") == "pinata")
assert(events.kindOf("Lucky Block") == "luckyblock" and events.kindOf("Fireworks") == nil)
fake.clients.RandomEventCmds = nil
tickModule("events")
assert(events.live.summary:find("unavailable", 1, true), events.live.summary)
advance(61)
fake.clients.RandomEventCmds = {GetActive = function() return {
    a = {dir = {Name = "Comet"}, uid = "e1", parentID = "Zone B"},
    b = {dir = {_id = "Lucky Block"}, uid = "e2", parentID = "Zone A"}} end}
state.goals = {{identity = "q-comet", kind = "comet", title = "Break 3 comets", required = 3, progress = 0},
    {identity = "q-lucky", kind = "luckyblock", title = "Break 2 lucky blocks", required = 2, progress = 0}}
Config.AutoFarm = true
state.running = true
state.eventFocus = nil
tickModule("events")
assert(state.eventFocus == "q-lucky", "focus the event that is in the farm zone: " .. tostring(state.eventFocus))
assert(events.live.summary:find("Comet @Zone B", 1, true))
state.eventFocus = nil
state.goals[2].progress = 2
tickModule("events")
assert(state.eventFocus == nil, "completed quests are not focused; other-zone events ignored")
Config.EventQuestFocus = false
state.goals[2].progress = 0
tickModule("events")
assert(state.eventFocus == nil, "toggle off: monitoring only")
assert(#requests == 0, "events module never sends network requests")
print("PASS events: GetActive parsing, zone-gated quest focus, read-only")
''', names=["10_rank.lua", "40_events.lua"], name="rank-events")
print("PASS test_rank_events")
