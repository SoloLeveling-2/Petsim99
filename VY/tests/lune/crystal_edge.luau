--!nocheck
-- Crystal edge cases (Lune), one per process:
--   lune run VY/tests/lune/crystal_edge.luau <source> slow-replication|no-credit|refused|not-ready|stars-keys
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
W.build(opts)
if scenario == "no-credit" then
    W.handlers["CrystalKey_Unlock"] = function() H.wait(0.1) return true end -- accepted, nothing changes
elseif scenario == "refused" then
    W.handlers["CrystalKey_Unlock"] = function() H.wait(0.1) return false, "Not allowed" end
end

local genv = H.newVM("vm")
local handle = H.handle(genv)
H.wait(4)
H.findButton("CrystalMode").Activated:Fire()
local c = handle.State.crystal

if scenario == "slow-replication" then
    H.waitFor(function() return W.count("CrystalKey_Unlock") >= 10 end, 60)
    H.wait(3) -- replication still pending (6 s)
    H.check(W.count("CrystalKey_Unlock") == 10, "burst stops at 10 requests while credit is pending (" .. W.count("CrystalKey_Unlock") .. ")")
    local more = H.waitFor(function() return W.count("CrystalKey_Unlock") > 10 end, 30)
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
end
H.scanErrors(scenario)
handle.Stop()
process.exit(H.finish() and 0 or 1)
