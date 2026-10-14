--!nocheck
-- One whole normal-Fishing transaction (Lune): priority ON -> PREPARE -> PAUSE
-- (pets) -> INSTANCE_ENTRY -> cast/bite/reel/tap cycles -> exact quest credit ->
-- EXIT -> RETURN -> RESTORE (best area, pets) -> RESUME -> ordinary farming.
-- Usage: lune run VY/tests/lune/fishing_flow.luau <source> [flags...]
-- flags: legacy  - old FishingGame/GameBar layout instead of the current prompt
--        travel  - best area in World 2: the transaction crosses worlds and every
--                  teleport replaces the client VM (autoexec re-run hydrates the JSON)
--        slow    - with travel: 40 s place load + 45 s until Save data arrives, and
--                  "Do minigames first" stays OFF (ordinary quests also remain)
--        debris  - 300 unrelated parts already sit in workspace.__DEBRIS
local process = require("@lune/process")
local luneTask = require("@lune/task")
local R = require("./roblox_mock")
local W = require("./vy_world")
local F = require("./vy_fishing")
local H = require("./harness")

local flags = {}
for i = 2, #process.args do flags[process.args[i]] = true end
local layout = flags.legacy and "legacy" or "current"
local travel, slow = flags.travel == true, flags.slow == true
H.loadSource(process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau")
W.build({
    rank = 12, keys = 0,
    bestZone = {id = "Best Zone", number = travel and 110 or 30, world = travel and 2 or 1},
    world = travel and 2 or 1,
    rollPools = {[2] = {34}},
    goals = {
        [1] = {UID = "g1", Type = 21, Amount = 5000, Progress = 0, Stars = 1},
        [2] = {UID = "g2", Type = 26, Amount = 3, Progress = 0, Stars = 2},
        [3] = {UID = "g3", Type = 9, Amount = 900, Progress = 0, Stars = 3},
    },
})
F.install({layout = layout})
if flags.debris then
    for i = 1, 300 do
        local p = R.node("Part", "Effect", F.debris)
        p.CFrame = R.CFrame.new(i, -50, 0)
    end
end
local genv = H.newVM("vm1")
local vms = 1
local function current() return H.handle(genv) end
if travel then
    for n = 1, 2 do W.handlers["World" .. n .. "Teleport"] = function() W.pendingWorld = n H.wait(0.2) return true end end
    luneTask.spawn(function()
        while true do
            if W.pendingWorld then
                local target = W.pendingWorld
                W.pendingWorld = nil
                H.wait(slow and 40 or 1.5)
                H.killVM(genv)
                W.world = target
                if slow then W.saveReadyAt = R.vclock() + 45 end -- the new server's data loads slowly
                W.root.CFrame = R.CFrame.new(0, 5, 0)
                vms += 1
                genv = H.newVM("vm" .. vms .. " (World " .. target .. ")")
            end
            H.wait(0.2)
        end
    end)
end
-- Invariant probe: no ordinary farming request while a minigame transaction owns work.
local violations = 0
local farm = W.handlers["Breakables_JoinPetBulk"]
W.handlers["Breakables_JoinPetBulk"] = function(...)
    local h = current()
    if h and h.State.minigame.transaction ~= nil then violations += 1 end
    return farm(...)
end

H.wait(5)
local priority = H.findButton("MinigamePriority")
H.check(priority ~= nil, "minigame priority button exists")
if not slow then priority.Activated:Fire() end
local function mg() local h = current() return h and h.State.minigame or {} end
local started = H.waitFor(function() return mg().transaction ~= nil end, slow and 400 or 30, 0.5)
H.check(started, "Fishing transaction started for the type-26 goal")
local entered = H.waitFor(function() return W.instance == "Fishing" end, slow and 300 or 120, 0.5)
H.check(entered, "entered the Fishing instance")
H.check(W.equipped == 0, "pets paused before travel/entry")
local completed = H.waitFor(function()
    local g = W.goalsBySlot()[2]
    return g == nil or g.Type ~= 26 or (mg().transaction == nil and mg().lastOutcome ~= nil)
end, 300, 0.5)
H.check(completed, string.format("fishing goal completed by automation (casts %d, reels %d, taps %d, catches %d)",
    F.casts, F.reels, F.taps, F.catches))
H.check(F.catches >= 3 and F.taps >= 3 * F.tapsPerCatch, "three credited catches with serialized taps")
local finished = H.waitFor(function()
    return current() ~= nil and mg().transaction == nil and mg().lastOutcome ~= nil and W.world == (travel and 2 or 1)
end, slow and 900 or 400, 0.5)
H.check(finished, "transaction finished: " .. tostring(mg().lastOutcome) .. " " .. tostring(mg().lastFailure))
H.check(mg().lastOutcome == "COMPLETED", "outcome COMPLETED (" .. tostring(mg().lastOutcome) .. ")")
H.check(W.instance == nil, "left the instance")
H.check(W.zoneAt(W.root.Position) == "Best Zone", "restored into the best area")
H.check(H.waitFor(function() return W.equipped > 0 end, 30), "pets restored")
local mark = #W.calls
H.check(H.waitFor(function() return W.count("Breakables_JoinPetBulk", mark) > 0 end, 30), "ordinary farming resumed")
H.check(violations == 0, "no farming request during the transaction (" .. violations .. ")")
if travel then
    H.check(W.count("World1Teleport") == 1 and W.count("World2Teleport") == 1,
        "one outbound and one return teleport (" .. W.count("World1Teleport") .. "/" .. W.count("World2Teleport") .. ")")
else
    H.check(W.count("World1Teleport") == 0, "already in World 1: no world teleport")
end
H.scanErrors("fishing " .. layout .. (travel and " travel" or "") .. (slow and " slow" or "") .. (flags.debris and " debris" or ""))
current().Stop()
process.exit(H.finish() and 0 or 1)
