-- Drops & Rewards page. The claim workers themselves are the v5.1 engine's
-- (rank rewards, free gifts, login streak, timed rewards, orbs, lootbags,
-- balloons); this module gathers their controls in one place and adds
-- Save-based confirmation counters so "requested" and "received" differ.
(function()
    local M = {id = "rewards", title = "Drops & Rewards", page = "drops", interval = 15}
    local seen = {gifts = nil, redeemed = nil}
    M.seen = seen

    local function size(t)
        local n = 0
        if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
        return n
    end

    -- Confirmation only: counts grow in Save when the server granted a reward.
    function M.tick()
        local data = saveData()
        if type(data) ~= "table" then return end
        local gifts = type(data.FreeGiftsRedeemed) == "table" and size(data.FreeGiftsRedeemed) or nil
        if gifts and seen.gifts and gifts > seen.gifts then
            for _ = 1, gifts - seen.gifts do
                Modules.note("rewards", "freegifts", "confirmed", "free gift redeemed (Save.FreeGiftsRedeemed)")
            end
        elseif gifts and seen.gifts and gifts < seen.gifts then
            Modules.state("rewards").last = "free gift cycle reset"
        end
        seen.gifts = gifts or seen.gifts
        Modules.state("rewards").last = string.format("orb claims sent %d, lootbag claims sent %d, free gifts confirmed %d",
            tonumber(state.orbClaims) or 0, tonumber(state.lootClaims) or 0, Modules.stat("rewards", "freegifts").confirmed)
    end
    M.active = function() return Config.AutoFreeGifts == true or Config.AutoCollectLootbags == true or Config.AutoCollectOrbs == true end

    function M.report()
        return string.format("lootbag claim attempts=%s errors=%s last=%s | orb claims sent=%s",
            tostring(state.lootbagClaimAttempts), tostring(state.lootbagClaimErrors),
            tostring(state.lootbagLastClaimStatus), tostring(state.orbClaims))
    end

    function M.buildUI(h, ui)
        local p = h.page("drops")
        h.section(p, "DROPS", "Orbs and lootbags are claimed with the game's own claim requests")
        h.toggle(p, "AutoCollectOrbs", "Collect orbs", "Orbs: Collect for loaded orb IDs; bounded batches")
        h.toggle(p, "AutoCollectLootbags", "Collect lootbags", "Lootbags_Claim for loaded bag IDs; never deletes bag objects")
        h.toggle(p, "SuperMagnet", "Super magnet", "Larger client pickup distance while running; restored on pause")
        h.toggle(p, "HideLootbagVisuals", "Hide lootbag models", "Local and reversible")
        h.toggle(p, "HidePickupPopups", "Hide floating pickup numbers", "Local and reversible")
        h.section(p, "REWARDS", "Each claim is checked against Save data before it counts as received")
        h.toggle(p, "AutoClaimRankRewards", "Claim rank rewards", "Ranks_ClaimReward for rewards your stars already unlocked")
        h.toggle(p, "AutoFreeGifts", "Claim free playtime gifts", "Redeem Free Gift when Save.FreeGiftsTime passes the wait time")
        h.toggle(p, "AutoLoginStreak", "Claim daily login streak", "Only when LoginStreakCmds.CanClaim() says it is ready")
        h.toggle(p, "AutoTimedRewards", "Claim timed rewards", "DailyRewards_Redeem near a loaded reward machine; cooldown from Save")
        h.toggle(p, "AutoPopBalloons", "Pop gift balloons", "Slingshot balloon gifts (needs 3 rebirths)")
        ui.rewardsStatus = h.rowLabel(p, "Rewards: not checked")
        ui.dropsStatus = h.rowLabel(p, "Drops: not checked")
        h.note(p, "Mailbox claiming is on the Trading & Mailbox page. Gift bags, lootboxes, keys and spin wheels are listed on Items & Boosts with their research status.", 52)
    end

    function M.render(ui)
        if ui.activePage ~= "drops" or not ui.rewardsStatus then return end
        local ex = state.extras or {}
        ui.rewardsStatus.Text = string.format("Login: %s  |  Timed: %s  |  Free gifts confirmed: %d",
            tostring(ex.loginLast), tostring(ex.timedLast), Modules.stat("rewards", "freegifts").confirmed)
        ui.dropsStatus.Text = string.format("Orb claims sent %s  |  Lootbag claims sent %s  |  %s",
            tostring(state.orbClaims or 0), tostring(state.lootClaims or 0), tostring(state.lootbagLastClaimStatus or "no lootbag claim yet"))
    end
    Modules.define(M)
end)()
