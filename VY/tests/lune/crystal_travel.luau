--!nocheck
-- Crystal mode across worlds (Lune). The best area is in World 2, the chest is
-- in World 1. A WorldNTeleport request is answered by replacing the client VM:
-- the old VM dies without Stop and the same source re-runs (Potassium
-- autoexec), hydrating only what VY persisted in its per-account JSON.
-- Usage: lune run VY/tests/lune/crystal_travel.luau <path to VY_AutoRank .luau>
local process = require("@lune/process")
local luneTask = require("@lune/task")
local R = require("./roblox_mock")
local W = require("./vy_world")
local H = require("./harness")

H.loadSource(process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau")
W.build({
    rank = 12, keys = 130, world = 2,
    bestZone = {id = "Tech Zone", number = 110, world = 2},
    goals = {
        [1] = {UID = "g1", Type = 15, Amount = 32, Progress = 0, Stars = 1},
        [2] = {UID = "g2", Type = 21, Amount = 2200, Progress = 10, Stars = 2},
        [3] = {UID = "g3", Type = 9, Amount = 900, Progress = 0, Stars = 3},
        [4] = {UID = "g4", Type = 42, Amount = 3, Progress = 0, Stars = 4},
    },
})

local vm = H.newVM("vm1 (World 2)")
local vms, arrivals = 1, {}
-- Teleport service: after a short load, the old VM dies and autoexec re-runs.
W.handlers["World1Teleport"] = function() W.pendingWorld = 1 H.wait(0.2) return true end
W.handlers["World2Teleport"] = function() W.pendingWorld = 2 H.wait(0.2) return true end
local alive = true
luneTask.spawn(function()
    while alive do
        if W.pendingWorld then
            local target = W.pendingWorld
            W.pendingWorld = nil
            H.wait(1.5)
            H.killVM(vm)
            W.world = target
            W.root.CFrame = R.CFrame.new(0, 5, 0) -- new server: spawn point
            vms += 1
            table.insert(arrivals, target)
            vm = H.newVM("vm" .. vms .. " (World " .. target .. ")")
        end
        H.wait(0.2)
    end
end)

H.wait(5)
local button = H.findButton("CrystalMode")
H.check(button ~= nil, "Crystal toggle exists in World 2")
button.Activated:Fire()
local travelled = H.waitFor(function() return W.world == 1 end, 60)
H.check(travelled, "travelled to World 1 for the chest")
H.check(W.equipped == 0, "pets stayed paused across the teleport")
local restoredOn = H.waitFor(function()
    local h = H.handle(vm)
    return h ~= nil and h.Config.AutoCrystalRank == true
end, 20)
H.check(restoredOn, "Crystal mode restored ON from the account file after travel")
local opened = H.waitFor(function() return W.count("CrystalKey_Unlock") > 0 end, 60)
H.check(opened, "chest opening resumed in World 1")
local done = H.waitFor(function()
    local h = H.handle(vm)
    return h and h.State.crystal.halted ~= nil
end, 400, 0.5)
H.check(done, "mode stopped at the key reserve")
H.check(W.keyStack()._am >= 100, "reserve kept (" .. W.keyStack()._am .. ")")
local back = H.waitFor(function() return W.world == 2 end, 240, 0.5)
H.check(back, "returned to the best area's world (World 2) afterwards")
local restored = H.waitFor(function() return W.equipped > 0 end, 60)
H.check(restored, "pets restored after the round trip")
local farmMark = #W.calls
local resumed = H.waitFor(function() return W.count("Breakables_JoinPetBulk", farmMark) > 0 end, 60)
H.check(resumed, "farming resumed in World 2")
local teleports = W.count("World1Teleport") + W.count("World2Teleport")
H.check(teleports == 2, "exactly two world requests for the round trip (" .. teleports .. ")")
H.check(#arrivals == 2, "two VM replacements (" .. #arrivals .. ")")
print(string.format("   requests=%d keys left=%d vms=%d teleports=%d", W.count("CrystalKey_Unlock"), W.keyStack()._am, vms, teleports))
H.scanErrors("crystal travel")
alive = false
local h = H.handle(vm)
if h then h.Stop() end
process.exit(H.finish() and 0 or 1)
