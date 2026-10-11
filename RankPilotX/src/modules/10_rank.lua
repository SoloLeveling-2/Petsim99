-- Rank telemetry, stall recovery and rank-reward confirmation.
-- Speed is measured as CONFIRMED quest progress: deltas of Save.Goals[*].Progress
-- keyed by the stable goal UID, plus RankStars / Rank increases. Nothing here
-- sends a network request; recovery only reloads capabilities and resets the
-- planner's local state, so it is safe to leave on.
(function()
    local M = {id = "rank", title = "Rank telemetry", page = "ranks", interval = 6}
    M.defaults = {RankStallRecovery = true, RankStallMinutes = 8}
    M.features = {
        {key = "RankStallRecovery", name = "Automatic stall recovery", status = "UNVERIFIED",
            evidence = "Local only: RECHECK + planner reset when Save.Goals progress stops"},
    }
    local tele = {goals = {}, window = {}, stars = nil, rank = nil, redeemed = nil,
        lastCreditAt = nil, startedAt = nil, credited = 0, fraction = 0, completed = 0,
        rewardsConfirmed = 0, recoveries = 0, stage = 0, last = "waiting for Save data"}
    M.tele = tele

    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    -- One sample: credit = sum of positive Progress deltas for goals with the
    -- same UID. A goal that disappears while stars rise counts as completed.
    function M.sample(data)
        if type(data) ~= "table" or type(data.Goals) ~= "table" then return nil end
        local t = now()
        tele.startedAt = tele.startedAt or t
        tele.lastCreditAt = tele.lastCreditAt or t
        local seen, credit, fraction = {}, 0, 0
        for _, goal in pairs(data.Goals) do
            if type(goal) == "table" and goal.UID ~= nil then
                local uid = tostring(goal.UID)
                local progress = tonumber(goal.Progress) or 0
                local amount = math.max(1, tonumber(goal.Amount) or 1)
                local prev = tele.goals[uid]
                if prev and progress > prev.progress then
                    credit = credit + (progress - prev.progress)
                    fraction = fraction + (progress - prev.progress) / amount
                end
                tele.goals[uid] = {progress = progress, amount = amount}
                seen[uid] = true
            end
        end
        local stars, rank = tonumber(data.RankStars), tonumber(data.Rank)
        local starsUp = tele.stars and stars and stars > tele.stars
        local rankUp = tele.rank and rank and rank > tele.rank
        for uid, prev in pairs(tele.goals) do
            if not seen[uid] then
                tele.goals[uid] = nil
                if starsUp or rankUp then
                    tele.completed = tele.completed + 1
                    fraction = fraction + math.max(0, prev.amount - prev.progress) / prev.amount
                end
            end
        end
        if type(data.RedeemedRankRewards) == "table" then
            local redeemed = countKeys(data.RedeemedRankRewards)
            if tele.redeemed and redeemed > tele.redeemed and not rankUp then
                tele.rewardsConfirmed = tele.rewardsConfirmed + (redeemed - tele.redeemed)
                Modules.note("rank", "rewards", "confirmed", "rank reward redeemed (Save.RedeemedRankRewards)")
            end
            tele.redeemed = redeemed
        end
        if credit > 0 or starsUp or rankUp then
            tele.lastCreditAt = t
            tele.stage = 0
        end
        tele.credited = tele.credited + credit
        tele.fraction = tele.fraction + fraction
        table.insert(tele.window, {t = t, credit = credit, fraction = fraction, stars = stars or 0})
        while #tele.window > 0 and t - tele.window[1].t > 600 do table.remove(tele.window, 1) end
        tele.stars, tele.rank = stars or tele.stars, rank or tele.rank
        return credit
    end

    -- Rates over the last 10 minutes (or since start when shorter).
    function M.rates()
        local w = tele.window
        if #w < 2 then return 0, 0, 0 end
        local minutes = math.max(0.5, (w[#w].t - w[1].t) / 60)
        local credit, fraction = 0, 0
        for i = 2, #w do
            credit = credit + w[i].credit
            fraction = fraction + w[i].fraction
        end
        local starsPerHour = math.max(0, (w[#w].stars - w[1].stars)) / minutes * 60
        return credit / minutes, fraction / minutes, starsPerHour
    end

    -- Escalating, local-only recovery. Stage 1 reloads client modules and
    -- clears temporary quest blocks; stage 2 also resets planner targeting and
    -- releases a stuck movement lease. Each stage runs once per stall.
    function M.recover(idleMinutes)
        local limit = math.max(3, tonumber(Config.RankStallMinutes) or 8)
        if idleMinutes >= limit and tele.stage == 0 then
            tele.stage = 1
            tele.recoveries = tele.recoveries + 1
            pcall(recheck)
            tele.last = string.format("No credited progress for %.0f min: reloaded APIs and cleared quest blocks", idleMinutes)
            log(tele.last, "RECOVERY")
            extraAlert("Stall recovery 1: " .. tele.last)
            return 1
        elseif idleMinutes >= limit * 2 and tele.stage == 1 then
            tele.stage = 2
            tele.recoveries = tele.recoveries + 1
            state.farmGoal, state.diamondZone, state.diamondZoneSince = nil, nil, 0
            state.scannedKey, state.lastTargetScan = "", 0
            state.eventFocus, state.eventFocusUntil = nil, 0
            state.movementOwner, state.movementUntil = nil, 0
            state.hatchNeedsCoins = false
            tele.last = string.format("Still stalled after %.0f min: reset targeting and released movement lease", idleMinutes)
            log(tele.last, "RECOVERY")
            extraAlert("Stall recovery 2: " .. tele.last)
            return 2
        end
        return 0
    end

    function M.tick()
        local data = saveData()
        if not data then
            tele.last = "Save.Get unavailable"
            return
        end
        M.sample(data)
        local idle = (now() - (tele.lastCreditAt or now())) / 60
        local perMinute, questsPerMinute, starsPerHour = M.rates()
        Modules.state("rank").last = string.format("%.1f progress/min, %.2f quests/min, %.1f stars/h",
            perMinute, questsPerMinute, starsPerHour)
        if Config.RankStallRecovery and Config.AutoRank and state.running then M.recover(idle) end
    end
    M.active = function() return true end
    -- A pause is not a stall: restart the idle clock whenever START is pressed.
    function M.onStart()
        tele.lastCreditAt = now()
        tele.stage = 0
    end

    function M.report()
        local perMinute, questsPerMinute, starsPerHour = M.rates()
        return string.format("confirmed progress %.1f/min, quests %.2f/min, stars %.1f/h, total credited %d, "
            .. "goals completed %d, rank rewards confirmed %d, recoveries %d, last=%s",
            perMinute, questsPerMinute, starsPerHour, tele.credited, tele.completed,
            tele.rewardsConfirmed, tele.recoveries, tostring(tele.last))
    end

    function M.buildUI(h, ui)
        local p = h.page("ranks")
        h.section(p, "SPEED (CONFIRMED BY SAVE DATA)", "Quest progress counted only when Save.Goals actually changes")
        ui.rankSpeed = h.rowLabel(p, "Measuring: progress/min not available yet")
        ui.rankStall = h.rowLabel(p, "Stall watchdog: waiting")
        h.toggle(p, "RankStallRecovery", "Automatic stall recovery",
            "No credited progress for the set minutes: reload APIs, then reset targeting (no spending)")
        h.choice(p, "Stall recovery after", "Minutes without credited quest progress",
            function() return tostring(Config.RankStallMinutes) .. " min  >" end,
            function()
                local opts, idx = {5, 8, 12, 20}, 1
                for i, v in ipairs(opts) do if v == Config.RankStallMinutes then idx = i break end end
                Config.RankStallMinutes = opts[idx % #opts + 1]
            end)
    end

    function M.render(ui)
        if ui.activePage ~= "ranks" or not ui.rankSpeed then return end
        local perMinute, questsPerMinute, starsPerHour = M.rates()
        ui.rankSpeed.Text = string.format("Confirmed: %.1f progress/min  |  %.2f quests/min  |  %.1f stars/hour",
            perMinute, questsPerMinute, starsPerHour)
        local idle = tele.lastCreditAt and (now() - tele.lastCreditAt) / 60 or 0
        ui.rankStall.Text = string.format("Last credited progress %.1f min ago  |  recoveries %d  |  %s",
            idle, tele.recoveries, tostring(tele.last))
    end
    Modules.define(M)
end)()
