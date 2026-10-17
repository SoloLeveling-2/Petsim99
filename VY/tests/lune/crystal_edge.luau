--!nocheck
-- Crystal edge cases (Lune), one per process:
--   lune run VY/tests/lune/crystal_edge.luau <source> <scenario>
-- scenarios: slow-replication | no-credit | refused | not-ready | stars-keys |
--   zero-drop-tail | stars-complete | travel-refused | retain-strand | protect-setup
local process = require("@lune/process")
local W = require("./vy_world")
local H = require("./harness")

local scenario = process.args[2] or "slow-replication"
H.loadSource(process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau")
local goals = {
    [1] = {UID = "g1", Type = 14, Amount = 32, Progress = 0, Stars = 1},
    [2] = {UID = "g2", Type = 21, Amount = 2200, Progress = 10, Stars = 2},
    [3] = {UID = "g3", Type = 9, Amount = 900, Progress = 0, Stars = 3},
    [4] = {UID = "g4", Type = 42, Amount = 3, Progress = 0, Stars = 4},
}
local opts = {rank = 12, keys = 150, goals = goals}
if scenario == "slow-replication" then opts.crystalReplicationDelay = 6 end
if scenario == "not-ready" then goals[1] = {UID = "g1", Type = 21, Amount = 1700, Progress = 0, Stars = 1} goals[2].Type = 34 end
if scenario == "stars-keys" then
    -- Save keyed by strings whose order differs from Stars; slot identity must come from the data.
    opts.goals = {["1"] = goals[1], ["2"] = goals[2], ["3"] = goals[3], ["4"] = goals[4]}
end
if scenario == "zero-drop-tail" then
    -- One item left; the next keys happen to drop no potions (6.8% each per the wiki odds).
    goals[1].Progress = 31
    opts.crystalDrops = {0, 0, 2, 3, 2, 1}
elseif scenario == "stars-complete" then
    goals[1].Progress = 30
    opts.rankStars, opts.totalStars = 801, 802
elseif scenario == "travel-refused" then
    opts.world, opts.bestZone = 2, {id = "Tech Zone", number = 110, world = 2}
elseif scenario == "retain-strand" then
    opts.keys, opts.crystalRetainEvery = 300, 5 -- Keys Mastery keeps the key (20% here, to make it visible)
elseif scenario == "protect-setup" then
    -- Diamond holder present, best-area quest not yet: hatching finishes slot 2, which then rolls a 21.
    goals[2] = {UID = "g2", Type = 20, Amount = 6, Progress = 0, Stars = 2}
    opts.rollPools, opts.rollAmounts = {[1] = {14, 15}, [2] = {21}}, {[2] = 2200}
end
W.build(opts)
if scenario == "travel-refused" then
    W.handlers["World1Teleport"] = function() H.wait(0.2) return false, "Teleport failed" end
end
if scenario == "no-credit" then
    W.handlers["CrystalKey_Unlock"] = function() H.wait(0.1) return true end -- accepted, nothing changes
elseif scenario == "refused" then
    W.handlers["CrystalKey_Unlock"] = function() H.wait(0.1) return false, "Not allowed" end
end

local genv = H.newVM("vm")
local handle = H.handle(genv)
local holdProbe = {nine = nil}
if scenario == "protect-setup" then
    -- Record the holder's progress at the moment the hold first starts.
    local original = W.handlers["CrystalKey_Unlock"]
    W.handlers["CrystalKey_Unlock"] = function(...)
        if holdProbe.nine == nil then holdProbe.nine = W.goalsBySlot()[3].Progress end
        return original(...)
    end
end
H.wait(scenario == "protect-setup" and 0.5 or 4)
H.findButton("CrystalMode").Activated:Fire()
local c = handle.State.crystal

if scenario == "slow-replication" then
    -- Probe at the moment of each request (a fixed wait raced the 6 s replication when a
    -- loaded machine stretched the burst): request 11 may only follow replicated credit.
    local replicatedAtEleven = nil
    local original = W.handlers["CrystalKey_Unlock"]
    W.handlers["CrystalKey_Unlock"] = function(...)
        if W.count("CrystalKey_Unlock") == 11 and replicatedAtEleven == nil then
            replicatedAtEleven = 0
            for _, e in ipairs(W.events) do
                if e.kind == "crystal-replicated" then replicatedAtEleven += 1 end
            end
        end
        return original(...)
    end
    local more = H.waitFor(function() return W.count("CrystalKey_Unlock") > 10 end, 90)
    H.check(replicatedAtEleven ~= nil and replicatedAtEleven >= 1,
        "burst stops at 10 requests while credit is pending (credit replicated before request 11: "
            .. tostring(replicatedAtEleven) .. ")")
    H.check(more, "next burst starts after replicated credit")
    H.check(c.halted == nil, "slow replication does not halt the mode (" .. tostring(c.halted) .. ")")
elseif scenario == "no-credit" then
    local halted = H.waitFor(function() return c.halted ~= nil end, 120)
    H.check(halted and string.find(c.halted, "no collection credit", 1, true) ~= nil, "halts when opens give no credit: " .. tostring(c.halted))
    H.check(W.count("CrystalKey_Unlock") <= 10, "spent at most one burst without credit (" .. W.count("CrystalKey_Unlock") .. ")")
    H.check(H.waitFor(function() return W.equipped > 0 end, 20), "pets restored after the halt")
elseif scenario == "refused" then
    local halted = H.waitFor(function() return c.halted ~= nil end, 60)
    H.check(halted and string.find(c.halted, "Not allowed", 1, true) ~= nil, "halts on a refusal: " .. tostring(c.halted))
    H.check(W.count("CrystalKey_Unlock") == 1, "no retry after a refusal (" .. W.count("CrystalKey_Unlock") .. ")")
elseif scenario == "not-ready" then
    H.wait(20)
    H.check(W.count("CrystalKey_Unlock") == 0, "no chest request when slot 1 is not a collect quest")
    H.check(W.count("Pets_UnequipAll") == 0, "pets not paused when the setup is missing")
    H.check(W.count("Breakables_JoinPetBulk") > 0, "ordinary farming continues while waiting for the setup")
    H.check(string.find(tostring(c.status), "slot 1", 1, true) ~= nil or string.find(tostring(c.status), "reroll", 1, true) ~= nil,
        "status explains the missing setup: " .. tostring(c.status))
elseif scenario == "stars-keys" then
    local opened = H.waitFor(function() return W.count("CrystalKey_Unlock") > 0 end, 30)
    H.check(opened, "string-keyed Save.Goals still recognised (status " .. tostring(c.status) .. ")")
elseif scenario == "zero-drop-tail" then
    local rotated = H.waitFor(function() return W.goalsBySlot()[1].UID ~= "g1" or c.halted ~= nil end, 90)
    H.check(rotated and c.halted == nil, "zero-drop keys near the end do not halt the mode (halted: " .. tostring(c.halted) .. ")")
    H.check(W.goalsBySlot()[1].UID ~= "g1", "slot 1 completed and rotated")
elseif scenario == "stars-complete" then
    local done = H.waitFor(function() return W.save.RankStars >= W.totalStars end, 60)
    H.check(done, "rank stars completed by the method (" .. W.save.RankStars .. "/" .. W.totalStars .. ")")
    H.wait(2) -- in-flight burst replies settle
    local mark = W.count("CrystalKey_Unlock")
    H.wait(20)
    H.check(W.count("CrystalKey_Unlock") == mark, "no keys spent after the rank's stars are complete (" .. (W.count("CrystalKey_Unlock") - mark) .. " extra)")
    H.check(c.halted == nil, "no sticky halt at rank end (" .. tostring(c.halted) .. ")")
elseif scenario == "travel-refused" then
    local held = H.waitFor(function() return c.hold == true end, 30)
    H.check(held, "hold taken while travel is attempted")
    H.wait(400)
    H.check(c.halted ~= nil and not c.hold, "mode gives up when World 1 cannot be reached (" .. tostring(c.halted or c.status) .. ")")
    H.check(H.waitFor(function() return W.equipped > 0 end, 30), "pets restored after giving up")
elseif scenario == "retain-strand" then
    local done = H.waitFor(function() return c.halted ~= nil end, 900, 0.5)
    H.check(done, "mode reached its stop (" .. tostring(c.halted) .. ")")
    H.check(W.keyStack()._am == 100, "stops exactly at the 100-key reserve when keys are kept (keys left " .. W.keyStack()._am .. ")")
elseif scenario == "protect-setup" then
    local engaged = H.waitFor(function() return W.count("CrystalKey_Unlock") > 0 end, 240, 0.5)
    H.check(engaged, "mode engages once the best-area quest rolls (status " .. tostring(c.status) .. ")")
    H.check(holdProbe.nine == 0, "the diamond holder was kept unfinished while waiting (progress " .. tostring(holdProbe.nine) .. ")")
end
H.scanErrors(scenario)
handle.Stop()
process.exit(H.finish() and 0 or 1)
