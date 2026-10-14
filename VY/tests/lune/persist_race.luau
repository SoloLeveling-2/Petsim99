--!nocheck
-- Two copies start back to back in the same client VM (two autoexec files, or a
-- manual re-run while the first copy is still loading). The second copy stops
-- the first BEFORE the first restored the per-account file. The saved settings
-- (here: Minigames OFF) and any in-flight transaction must survive.
-- Usage: lune run VY/tests/lune/persist_race.luau <path to VY_AutoRank .luau>
local process = require("@lune/process")
local W = require("./vy_world")
local H = require("./harness")

H.loadSource(process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau")
W.build({rank = 12, keys = 0, goals = {
    [1] = {UID = "g1", Type = 21, Amount = 5000, Progress = 0, Stars = 1},
    [2] = {UID = "g2", Type = 26, Amount = 3, Progress = 0, Stars = 2},
}})

-- Session 1: the user turns Minigames OFF; the choice is saved.
local first = H.newVM("session 1")
H.wait(5)
H.findButton("MinigameToggle").Activated:Fire()
H.check(H.handle(first).Config.AutoMinigames == false, "Minigames switched OFF")
local path = nil
for name in pairs(W.files) do if string.find(name, "VY_AutoRank_State_", 1, true) then path = name end end
H.check(path ~= nil and string.find(W.files[path], '"minigameEnabled":false', 1, true) ~= nil, "OFF saved in the per-account file")
H.killVM(first) -- place teleport: the VM ends without Stop

-- Session 2: two copies start in the same new VM, the second right after the first.
local genv = {}
H.runIn(genv, "copy A")
H.runIn(genv, "copy B")
H.wait(10)
local h = H.handle(genv)
H.check(h ~= nil and h.Config.AutoMinigames == false, "saved Minigames OFF survives a duplicate start (now " .. tostring(h and h.Config.AutoMinigames) .. ")")
H.check(string.find(W.files[path], '"minigameEnabled":false', 1, true) ~= nil, "per-account file still says OFF")
local replaced = H.console("replacing running AutoRank v")
H.check(#replaced >= 1, "console names the copy being replaced (" .. #replaced .. ")")
H.scanErrors("persist race")
h.Stop()
process.exit(H.finish() and 0 or 1)
