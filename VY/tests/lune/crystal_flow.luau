--!nocheck
-- End-to-end Crystal Key mode in the fake world (Lune).
-- Usage: lune run VY/tests/lune/crystal_flow.luau <path to VY_AutoRank .luau>
-- Setup: rank 12, slot 1 = collect potions 0/32, slot 2 = best-area breakables,
-- slot 3 = diamond breakables, slot 4 = hatch rare pet; 150 full keys (reserve 100).
-- Checks the integrated flow: pets paused, no farming/hatching while held,
-- chest pad, no-argument CrystalKey_Unlock, bounded bursts, replicated credit,
-- slot-1 rotation, reserve kept, pets restored and farming resumed, Stop quiet.
local process = require("@lune/process")
local R = require("./roblox_mock")
local W = require("./vy_world")
local H = require("./harness")

H.loadSource(process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau")
W.build({
    rank = 12, keys = 150,
    goals = {
        [1] = {UID = "g1", Type = 14, Amount = 32, Progress = 0, Stars = 1},
        [2] = {UID = "g2", Type = 21, Amount = 2200, Progress = 10, Stars = 2},
        [3] = {UID = "g3", Type = 9, Amount = 900, Progress = 0, Stars = 3},
        [4] = {UID = "g4", Type = 42, Amount = 3, Progress = 0, Stars = 4},
    },
})
local genv = H.newVM("vm1")
local handle = H.handle(genv)
-- Invariant probes: any farm/hatch request while Crystal holds work is a violation.
local violations = {}
for _, name in ipairs({"Breakables_JoinPetBulk", "Eggs_RequestPurchase"}) do
    local original = W.handlers[name]
    W.handlers[name] = function(...)
        if handle.State.crystal.hold then table.insert(violations, name) end
        return original(...)
    end
end
H.check(handle and handle.Version ~= nil, "handle published with version " .. tostring(handle and handle.Version))
H.check(handle.Config.AutoCrystalRank == false, "Crystal mode is OFF by default")

-- Phase 1: Crystal OFF -> ordinary farming advances the held breakable quest.
local slots = W.goalsBySlot
local before21 = slots()[2].Progress
H.wait(12)
H.check(W.count("Breakables_JoinPetBulk") > 0, "farming runs while Crystal is OFF")
H.check(slots()[2].Progress > before21, "ordinary farming advances slot-2 best-area breakables (" .. before21 .. " -> " .. slots()[2].Progress .. ")")
H.check(W.count("CrystalKey_Unlock") == 0, "no chest request while OFF")

-- Phase 2: user turns Crystal ON from the hub.
local button = H.findButton("CrystalMode")
H.check(button ~= nil, "Crystal toggle button exists in the hub")
local callsAtToggle = #W.calls
button.Activated:Fire()
H.check(handle.Config.AutoCrystalRank == true, "toggle turns Crystal ON")
local paused = H.waitFor(function() return W.equipped == 0 end, 10)
H.check(paused and W.count("Pets_UnequipAll", callsAtToggle) >= 1, "pets paused with Pets_UnequipAll")
local opened = H.waitFor(function() return W.count("CrystalKey_Unlock") > 0 end, 20)
H.check(opened, "chest opening starts")
H.check((W.root.Position - W.pad.Position).Magnitude <= 12, "character stands at the Castle chest pad")

-- Holders must not advance while the method runs.
H.wait(1)
local held21, held9 = slots()[2] and slots()[2].Progress, slots()[3] and slots()[3].Progress
local farmBefore = W.count("Breakables_JoinPetBulk")

-- First burst is bounded before any replicated credit arrives.
local firstReplication = nil
for _, e in ipairs(W.events) do if e.kind == "crystal-replicated" then firstReplication = e.t break end end
local beforeCredit = 0
for _, c in ipairs(W.calls) do
    if c.name == "CrystalKey_Unlock" and (firstReplication == nil or c.t < firstReplication) then beforeCredit += 1 end
end
H.check(beforeCredit <= 10, "at most one 10-key burst before replicated credit (" .. beforeCredit .. ")")

-- Run until the mode halts at the reserve (or time out).
local c = handle.State.crystal
local finished = H.waitFor(function() return c.halted ~= nil or (not c.hold and W.count("CrystalKey_Unlock") > 40) end, 400, 0.5)
H.check(finished, "mode reached a terminal state: " .. tostring(c.halted or c.status))
local keys = W.keyStack()._am
H.check(keys >= 100, "100-key reserve kept (keys left " .. keys .. ")")
local bad = 0
for _, e in ipairs(W.events) do if e.kind == "crystal-bad-args" or e.kind == "crystal-too-far" then bad += 1 end end
H.check(bad == 0, "every chest request had no arguments and was sent from the pad (" .. bad .. " bad)")
local rotations = 0
for _, e in ipairs(W.events) do if e.kind == "goal-complete" and e.detail.slot == 1 then rotations += 1 end end
H.check(rotations >= 2, "slot 1 completed and rotated repeatedly (" .. rotations .. ")")
H.check(W.save.RankStars >= 3 + rotations, "stars paid for slot-1 completions (" .. W.save.RankStars .. ")")
H.check(slots()[2].UID == "g2" and slots()[3].UID == "g3", "held breakable quests survived")
H.check(#violations == 0, "no farming or hatching request while the method held work (" .. #violations .. ")")
local _ = held21, held9
print(string.format("   opens=%d (server) requests=%d keys %d->%d rotations=%d stars=%d status=%s",
    W.crystalOpens, W.count("CrystalKey_Unlock"), 150, keys, rotations, W.save.RankStars, tostring(c.status)))

-- Phase 3: after the halt, pets come back and ordinary work resumes.
local restored = H.waitFor(function() return W.equipped > 0 end, 20)
H.check(restored, "pets restored after the mode stopped")
local resumed = H.waitFor(function() return W.count("Breakables_JoinPetBulk") > farmBefore end, 30)
H.check(resumed, "farming resumed after the mode stopped")

-- Phase 4: Stop is quiet.
H.scanErrors("crystal flow")
handle.Stop()
H.wait(2)
local after = #W.calls
H.wait(20)
H.check(#W.calls == after, "no requests after Stop (" .. (#W.calls - after) .. ")")
local _ = R
process.exit(H.finish() and 0 or 1)
