--!nocheck
-- Whole-file scenario for the Tap Simulator REBORN helper (Lune, mocked runtime):
-- quiet start, auto tap pacing and sequence re-sync, auto hatch walking to the egg,
-- auto rebirth limits, upgrades/skills/claims, same-VM re-execution and Stop.
-- Usage: lune run TapSim/tests/lune/smoke.luau TapSim/TapSim_Reborn.luau
local process = require("@lune/process")
local serde = require("@lune/serde")
local W = require("./tapsim_world")

W.loadSource(process.args[1] or "TapSim/TapSim_Reborn.luau")
-- The game's own client already tapped this session: our first taps are stale until re-sync.
W.build({ serverSeq = 400, tapPower = 60 })
local S = W.server

-- 1. Quiet start: everything defaults to OFF.
local genv = W.runIn({}, "first run")
local handle = genv.TapSimReborn
W.check(handle ~= nil and type(handle.Stop) == "function", "global handle with Stop")
W.check(W.guis() == 1, "one window after the first run")
W.wait(6)
W.check(#W.calls == 0, "no requests while every feature is off (" .. #W.calls .. ")")

-- 2. Auto tap: paced to the 0.1s interval, re-syncs past the game's own sequence.
W.click("Toggle_AutoTap")
W.wait(20)
local taps = W.count("TapService.TapRequested")
W.check(S.accepted > 100, "taps accepted by the server after re-sync (" .. S.accepted .. " of " .. taps .. ")")
W.check(S.tooFast == 0, "no tap sent faster than the server interval (" .. S.tooFast .. ")")
W.check(taps <= 20 * 10 + 5, "tap rate stays at or under 10/s (" .. taps .. " in 20s)")
local lastSeq, rising = -1, true
for _, c in ipairs(W.callsOf("TapService.TapRequested")) do
    local p = c.args[1]
    if p.ClientSequence <= lastSeq or p.Source ~= "button" or p.Auto ~= false then rising = false end
    lastSeq = p.ClientSequence
end
W.check(rising, "tap payloads carry a rising ClientSequence and Source=button")
W.check(W.save.Currencies.Coins > 5000, "coins earned by tapping (" .. W.save.Currencies.Coins .. ")")

-- 3. Auto hatch: picks the best affordable egg on an unlocked island and stands next to it.
W.click("Toggle_AutoHatch")
W.wait(25)
local hatchCalls = W.callsOf("EggService.EggHatchRequested")
W.check(S.hatches > 0, "eggs hatched (" .. S.hatches .. ")")
local skyAsked, badCount = false, false
for _, c in ipairs(hatchCalls) do
    local p = c.args[1]
    if p.Egg == "Sky" then skyAsked = true end
    if p.Count ~= 1 and p.Count ~= 3 then badCount = true end
    if p.Auto ~= true or type(p.Seq) ~= "number" then badCount = true end
end
W.check(not skyAsked, "never asks for an egg on a locked island")
W.check(not badCount, "hatch payloads use Count 1 or 3 (no x8 pass) with Auto and Seq")
W.check(S.tooFar <= 1, "teleports next to the egg before hatching (TooFar " .. S.tooFar .. ")")
local inFlight, maxInFlight, lastT = 0, 0, -math.huge
for _, c in ipairs(hatchCalls) do
    if c.t - lastT < 0.55 then inFlight += 1 else inFlight = 1 end
    maxInFlight = math.max(maxInFlight, inFlight)
    lastT = c.t
end
W.check(maxInFlight <= 1, "one hatch request in flight at a time")
W.click("Toggle_AutoHatch")

-- 4. Auto rebirth: only unlocked buttons (2), never more often than every 1.5s.
W.save.Currencies.Coins = 1e6
W.click("Toggle_AutoRebirth")
W.wait(12)
W.check(#S.rebirthTimes >= 3, "rebirth requests sent (" .. #S.rebirthTimes .. ")")
W.check(S.badIndex == 0, "never presses a locked rebirth button (" .. S.badIndex .. ")")
local minGap = math.huge
for i = 2, #S.rebirthTimes do minGap = math.min(minGap, S.rebirthTimes[i] - S.rebirthTimes[i - 1]) end
W.check(minGap >= 1.45, string.format("rebirths at least 1.5s apart (min %.2f)", minGap))
local firstPack = W.callsOf("RebirthService.RebirthRequested")[1]
W.check(firstPack and firstPack.args[1].Index == 2, "picks the biggest unlocked pack it can afford")
W.check(W.save.Statistics.Rebirths > 0, "rebirths counted (" .. W.save.Statistics.Rebirths .. ")")
W.click("Toggle_AutoRebirth")

-- 5. Upgrades, skill tree, equip, quests, chests.
for _, key in ipairs({ "AutoUpgrades", "AutoSkillTree", "AutoEquip", "AutoQuests", "AutoChests" }) do
    W.click("Toggle_" .. key)
end
W.wait(20)
W.check(W.count("UpgradeService.Purchase") >= 2, "upgrades bought")
W.check(W.save.SkillTree.Unlocked.ClickPower1 and W.save.SkillTree.Unlocked.Critical1,
    "skill tree unlocked including the subtree that opened later")
W.check(W.count("PetService.PetActionRequested") >= 2, "equip best fired repeatedly")
W.check(W.save.Quests.q1.Claimed == true and W.count("QuestService.ClaimQuest") == 1,
    "finished quest claimed once; unfinished quest left alone")
W.check(W.save.TapChests.chestA == nil, "tap chest claimed")

-- 6. Settings persist, and same-VM re-execution replaces the running copy.
local saved = W.files["TapSimReborn_settings.json"] and serde.decode("json", W.files["TapSimReborn_settings.json"])
W.check(saved and saved.AutoTap == true and saved.AutoUpgrades == true, "settings saved to the workspace file")
local seqBefore = S.lastSeq
local oldState = handle.State
W.runIn(genv, "second run")
W.wait(8)
W.check(oldState.alive == false, "previous copy stopped by re-execution")
W.check(genv.TapSimReborn ~= handle and genv.TapSimReborn.State.alive, "new copy owns the handle")
W.check(W.guis() == 1, "exactly one window after re-execution (" .. W.guis() .. ")")
W.check(S.lastSeq > seqBefore, "taps keep being accepted after re-execution (sequence carried over)")

-- 7. X stops everything.
W.click("Close")
W.wait(2)
W.check(genv.TapSimReborn == nil, "Stop removes the global handle")
W.check(W.guis() == 0, "Stop destroys the window")
local mark = #W.calls
W.wait(15)
W.check(#W.calls == mark, "no requests after Stop (" .. (#W.calls - mark) .. ")")
W.scanErrors("whole run")
process.exit(W.finish() and 0 or 1)
