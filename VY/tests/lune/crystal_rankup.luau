--!nocheck
-- Crystal mode across a rank-up (Lune). Best area in World 2; the method runs in
-- World 1. Long after arriving (past the 90 s travel throttle) the server ranks
-- the account up while the held quests keep their UIDs. A valid setup must keep
-- its World 1 hold: no trip back to World 2 and back again.
-- Usage: lune run VY/tests/lune/crystal_rankup.luau <path to VY_AutoRank .luau>
local process = require("@lune/process")
local luneTask = require("@lune/task")
local R = require("./roblox_mock")
local W = require("./vy_world")
local H = require("./harness")

H.loadSource(process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau")
W.build({
    rank = 12, keys = 3000, world = 2, crystalReplicationDelay = 0.6,
    bestZone = {id = "Tech Zone", number = 110, world = 2},
    goals = {
        [1] = {UID = "g1", Type = 14, Amount = 32, Progress = 0, Stars = 1},
        [2] = {UID = "g2", Type = 21, Amount = 2200, Progress = 10, Stars = 2},
        [3] = {UID = "g3", Type = 9, Amount = 900, Progress = 0, Stars = 3},
        [4] = {UID = "g4", Type = 42, Amount = 3, Progress = 0, Stars = 4},
    },
})
local vm = H.newVM("vm1 (World 2)")
local vms = 1
for n = 1, 2 do W.handlers["World" .. n .. "Teleport"] = function() W.pendingWorld = n H.wait(0.2) return true end end
local alive = true
luneTask.spawn(function()
    while alive do
        if W.pendingWorld then
            local target = W.pendingWorld
            W.pendingWorld = nil
            H.wait(1.5)
            H.killVM(vm)
            W.world = target
            W.root.CFrame = R.CFrame.new(0, 5, 0)
            vms += 1
            vm = H.newVM("vm" .. vms .. " (World " .. target .. ")")
        end
        H.wait(0.2)
    end
end)

H.wait(5)
H.findButton("CrystalMode").Activated:Fire()
H.check(H.waitFor(function() return W.world == 1 end, 60), "travelled to World 1")
H.check(H.waitFor(function() return W.count("CrystalKey_Unlock") > 0 end, 60), "opening in World 1")
H.wait(120) -- well past the 90 s world-travel throttle
local teleportsBefore = W.count("World2Teleport")
-- Server-side rank-up: new rank, stars reset, slot 1 re-rolled, holders keep their UIDs.
W.save.Rank += 1
W.save.RankStars = 0
W.save.RedeemedRankRewards = {}
local first = W.goalsBySlot()[1]
first.UID, first.Type, first.Progress = "rank13-slot1", 15, 0
W.event("rank-up", W.save.Rank)
local opensAtRankUp = W.count("CrystalKey_Unlock")
H.wait(30)
H.check(W.count("World2Teleport") == teleportsBefore, "rank-up with a still-valid setup does not leave World 1 ("
    .. (W.count("World2Teleport") - teleportsBefore) .. " World2Teleport)")
H.check(W.count("CrystalKey_Unlock") > opensAtRankUp, "opening continues on the new rank")
local h = H.handle(vm)
H.check(h ~= nil and h.State.crystal.hold == true and h.State.crystal.halted == nil, "Crystal still owns the hold after the rank-up")
H.scanErrors("crystal rank-up")
alive = false
if h then h.Stop() end
process.exit(H.finish() and 0 or 1)
