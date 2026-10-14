--!nocheck
-- Whole-file lifecycle smoke test (Lune): start, ordinary work, same-VM
-- re-execution (previous instance stops, one GUI), GUI X button, quiet after Stop.
-- Usage: lune run VY/tests/lune/smoke.luau <path to VY_AutoRank .luau> [expected version]
local process = require("@lune/process")
local W = require("./vy_world")
local H = require("./harness")

H.loadSource(process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau")
local expected = process.args[2]
W.build({
    rank = 12, keys = 20,
    goals = {
        [1] = {UID = "g1", Type = 21, Amount = 1700, Progress = 0, Stars = 1},
        [2] = {UID = "g2", Type = 14, Amount = 40, Progress = 0, Stars = 2},
        [3] = {UID = "g3", Type = 9, Amount = 900, Progress = 0, Stars = 3},
        [4] = {UID = "g4", Type = 42, Amount = 3, Progress = 0, Stars = 4},
    },
})
local function guis()
    local n = 0
    for _, d in ipairs(W.hui:GetChildren()) do if d.Name == "VyAutoRankGui" then n += 1 end end
    return n
end

local genv = H.newVM("first run")
local handle = H.handle(genv)
H.check(handle ~= nil and type(handle.Stop) == "function", "global handle with Stop")
if expected then H.check(handle.Version == expected, "handle version " .. tostring(handle.Version) .. " == " .. expected) end
H.wait(15)
H.check(guis() == 1, "one GUI after the first run")
local title = H.findButton("Title")
H.check(title ~= nil and string.find(title.Text, handle.Version, 1, true) ~= nil, "GUI title shows the running version: " .. tostring(title and title.Text))
H.check(W.count("Breakables_JoinPetBulk") > 0, "farming requests sent")
H.check(W.count("Eggs_RequestPurchase") > 0, "hatching requests sent for the hatch goal")
H.check(W.count("Ranks_ClaimReward") > 0, "earned reward claimed")
H.check(W.count("CrystalKey_Unlock") == 0, "no Crystal Key spent while the mode is OFF")
H.scanErrors("first run")

-- Same-VM re-execution: VY stops the previous handle itself.
local oldState = handle.State
H.runIn(genv, "second run")
H.wait(10)
local handle2 = H.handle(genv)
H.check(oldState.alive == false, "previous instance stopped by re-execution")
H.check(handle2 ~= nil and handle2 ~= handle and handle2.State.alive == true, "new instance owns the handle")
H.check(guis() == 1, "exactly one GUI after re-execution (" .. guis() .. ")")

-- GUI X button stops everything.
local close = H.findButton("Close")
H.check(close ~= nil, "close button exists")
close.MouseButton1Click:Fire()
H.wait(3)
H.check(genv.VyAutoRank == nil, "Stop removes the global handle")
H.check(guis() == 0, "Stop destroys the GUI")
local mark = #W.calls
H.wait(20)
H.check(#W.calls == mark, "no requests after Stop (" .. (#W.calls - mark) .. ")")
H.scanErrors("lifecycle")
process.exit(H.finish() and 0 or 1)
