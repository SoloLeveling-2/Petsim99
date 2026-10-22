--!nocheck
-- Edge cases for the Tap Simulator REBORN helper (Lune, mocked runtime). One case per run:
--   late-load       client folders (Controllers, Shared, RemoteServices) appear 40s after start,
--                   as when the script runs from autoexec before the game has loaded
--   silent-taps     the server takes taps but TapResult never answers (e.g. after an update)
--   worker-restart  TapService.TapRequested only appears 25s after start
--   offline-later   "Claim offline earnings" is switched on after the script started
--   stand-spot      egg models are not streamed in, so the ring search runs without them
-- Usage: lune run TapSim/tests/lune/edge.luau TapSim/TapSim_Reborn.luau <case>
local process = require("@lune/process")
local W = require("./tapsim_world")

W.loadSource(process.args[1] or "TapSim/TapSim_Reborn.luau")
local case = process.args[2] or "late-load"

if case == "late-load" then
    W.build({ lateLoad = 40, coins = 1e6 })
    local genv = W.runIn({}, case)
    W.check(W.guis() == 1, "window shows while the game is still loading")
    for _, key in ipairs({ "AutoTap", "AutoHatch", "AutoRebirth" }) do W.click("Toggle_" .. key) end
    W.wait(120)
    W.check(W.server.accepted > 50, "taps flow once the remotes exist (" .. W.server.accepted .. ")")
    W.check(W.server.hatches > 0, "hatching starts once the egg config exists (" .. W.server.hatches .. ")")
    W.check(#W.server.rebirthTimes > 0, "rebirths start once the rebirth config exists (" .. #W.server.rebirthTimes .. ")")
    local status = W.findButton("Status")
    W.check(status and string.find(status.Text, "Coins", 1, true) ~= nil, "status shows the save data: " .. tostring(status and status.Text))
    genv.TapSimReborn.Stop()
elseif case == "silent-taps" then
    W.build({ silentTaps = true })
    local genv = W.runIn({}, case)
    W.click("Toggle_AutoTap")
    W.wait(400)
    local lastSeq, rising, finite = -1, true, true
    for _, c in ipairs(W.callsOf("TapService.TapRequested")) do
        local seq = c.args[1].ClientSequence
        if seq <= lastSeq then rising = false end
        if seq >= 2 ^ 53 then finite = false end
        lastSeq = seq
    end
    W.check(rising, "ClientSequence keeps rising while nothing answers")
    W.check(finite, "ClientSequence stays below 2^53, where +1 stops changing it (last " .. lastSeq .. ")")
    local before = W.server.accepted
    W.wait(20)
    W.check(W.server.accepted - before > 100, "the server still accepts taps after 400s (" .. (W.server.accepted - before) .. " in 20s)")
    genv.TapSimReborn.Stop()
elseif case == "worker-restart" then
    W.build({ lateTapRemote = 25 })
    local genv = W.runIn({}, case)
    W.click("Toggle_AutoTap")
    W.wait(60)
    W.check(W.server.accepted > 50, "auto tap recovers once the remote appears (" .. W.server.accepted .. ")")
    genv.TapSimReborn.Stop()
elseif case == "offline-later" then
    W.build({})
    local genv = W.runIn({}, case)
    W.wait(10)
    W.check(W.count("OfflineRewardsService.Claim") == 0, "no offline claim while the toggle is off")
    W.click("Toggle_ClaimOffline")
    W.wait(5)
    W.check(W.count("OfflineRewardsService.Claim") == 1, "switching the toggle on claims once (" .. W.count("OfflineRewardsService.Claim") .. ")")
    genv.TapSimReborn.Stop()
elseif case == "stand-spot" then
    W.build({ noEggModels = true, coins = 1e6 })
    local genv = W.runIn({}, case)
    W.click("Toggle_AutoHatch")
    W.wait(30)
    W.check(W.server.hatches > 0, "hatches without streamed egg models (" .. W.server.hatches .. ")")
    local egg = W.eggAt.Spotted
    local pos = W.root.Position
    W.check(math.abs(pos.Y - egg.Y) < 0.5, string.format("stands on the ground ring beside the egg, not the blind fallback (dy %.1f)", pos.Y - egg.Y))
    genv.TapSimReborn.Stop()
else
    error("unknown case " .. tostring(case))
end

W.scanErrors(case)
process.exit(W.finish() and 0 or 1)
