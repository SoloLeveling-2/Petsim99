-- Crystal Key rank-up planner (user-reported "crystal key method").
-- Evidence for the slot rule: the official rank directory (BIG Games API
-- "Ranks" collection, configData.Goals = one weighted quest pool per slot,
-- e.g. rank 30 slot 1 = {CURRENT_BREAKABLE(21) x3, COLLECT_POTION(14),
-- COLLECT_ENCHANT(15), DIAMOND_BREAKABLE(9)}) read live from
-- Directory.Ranks[RankIDFromNumber(rank)].Goals. Players report the game never
-- gives two active quests the same type, so when every non-collect type of
-- slot 1's pool is already held (unfinished) in slots 2-4, slot 1 can only roll
-- collect potions / collect enchants, which Crystal Chest drops complete.
-- This module is READ-ONLY planning: it reports whether the account is set
-- up and how many keys it holds. Opening the chest is a separate, opt-in step.
(function()
    local M = {id = "crystal", title = "Crystal Key planner", page = "ranks", interval = 5}
    M.COLLECT = {[14] = "collect potions", [15] = "collect enchants"}
    M.NAMES = {[1] = "breakables", [7] = "currency", [9] = "diamond breakables", [14] = "collect potions",
        [15] = "collect enchants", [21] = "breakables (current area)", [34] = "use potions"}
    local plan = {status = "not checked", ready = false, slots = {}, blockers = {}, keys = 0}
    M.plan = plan

    -- Active quests by slot. Save.Goals is keyed by slot (VY AutoRank iterates
    -- `for tier, g in pairs(save.Goals)`; RankPilot keeps the same key).
    function M.readSlots(data)
        local slots = {}
        if type(data) ~= "table" or type(data.Goals) ~= "table" then return slots end
        for key, g in pairs(data.Goals) do
            local slot = tonumber(key)
            if slot and type(g) == "table" and g.Type ~= nil then
                slots[slot] = {slot = slot, type = tonumber(g.Type) or g.Type, amount = tonumber(g.Amount) or 0,
                    progress = tonumber(g.Progress) or 0, uid = g.UID, stars = tonumber(g.Stars) or 1}
            end
        end
        return slots
    end

    -- Quest types slot 1 can roll at this rank, from the game's own directory.
    -- Directory tables are frozen (unknown keys throw), so read inside pcall.
    function M.slotPool(rank, slotIndex)
        local _, definition = rankDefinition(rank)
        if type(definition) ~= "table" then return nil end
        local ok, types = pcall(function()
            local pool = definition.Goals[slotIndex or 1]
            local found = {}
            for _, entry in pairs(pool) do
                local t = type(entry) == "table" and tonumber(rawget(entry, "Type") or entry.Type) or nil
                if t then found[t] = true end
            end
            return found
        end)
        if not ok or type(types) ~= "table" or next(types) == nil then return nil end
        return types
    end

    -- Pure analysis: given slot-1 pool types and active slots, is slot 1
    -- forced to a collect quest? Returns ready, status text, blocker list.
    function M.analyze(pool, slots)
        if not pool then return false, "rank quest pools unreadable (Directory.Ranks)", {} end
        local collectable = false
        for t in pairs(M.COLLECT) do if pool[t] then collectable = true end end
        if not collectable then return false, "slot 1 cannot roll collect quests at this rank", {} end
        local held = {}
        for slot, q in pairs(slots) do
            if slot >= 2 and q.progress < q.amount then held[q.type] = slot end
        end
        local missing = {}
        for t in pairs(pool) do
            if not M.COLLECT[t] and not held[t] then table.insert(missing, t) end
        end
        table.sort(missing)
        local first = slots[1]
        if #missing > 0 then
            local names = {}
            for _, t in ipairs(missing) do table.insert(names, M.NAMES[t] or ("type " .. tostring(t))) end
            local hint = "keep completing other quests until slots 2-4 hold: " .. table.concat(names, ", ")
            if first and not M.COLLECT[first.type] and pool[first.type] then
                hint = "finish slot 1 (" .. (M.NAMES[first.type] or tostring(first.type)) .. ") first; " .. hint
            end
            return false, hint, missing
        end
        if not first then return false, "slot 1 is empty (waiting for a new quest)", {} end
        if not M.COLLECT[first.type] then
            return false, "slot 1 holds " .. (M.NAMES[first.type] or tostring(first.type)) .. "; finish it to reroll", {}
        end
        return true, "READY: slot 1 = " .. M.COLLECT[first.type] .. " (" .. first.progress .. "/" .. first.amount
            .. "); breakable quests are held in other slots", {}
    end

    function M.refreshPlan(force)
        local data = saveData(force)
        if type(data) ~= "table" then plan.status, plan.ready = "Save unavailable", false return end
        local slots = M.readSlots(data)
        local rank = tonumber(data.Rank)
        local pool = rank and M.slotPool(rank, 1)
        local ready, status, blockers = M.analyze(pool, slots)
        plan.ready, plan.status, plan.blockers, plan.slots = ready, status, blockers, slots
        plan.keys = Modules.countItem("Misc", "Crystal Key", force)
        plan.checkedAt = now()
        Modules.state("crystal").last = status .. " | crystal keys " .. plan.keys
    end

    -- ------------------------------------------------------------ runner
    -- Opt-in, spends Crystal Keys. Opens the chest only with a request that is
    -- either evidenced in readable source (EVIDENCED_OPEN, nil until found) or
    -- was recorded from the user's own manual chest opening (recorder).
    M.EVIDENCED_OPEN = nil
    M.defaults = {CrystalKeyMode = false, CrystalKeyReserve = 0, CrystalOpenSeconds = 1.5}
    M.features = {
        {key = "CrystalKeyMode", name = "Crystal Key rank-up mode", status = "EXPERIMENTAL",
            evidence = "Slot pools: Directory.Ranks; chest pad: Map['3 | Castle'].INTERACT.CrystalChest.Pad (idonthaveoneatm 2025-09); open request: taught by recorder"},
    }
    local runState = {phase = "off", pending = nil, misses = 0, nextOpen = 0, opened = 0, pad = nil}
    M.runState = runState

    function M.opener()
        if M.EVIDENCED_OPEN then return M.EVIDENCED_OPEN end
        local recorder = Modules.byId.recorder
        return recorder and recorder.learned("crystalChest") or nil
    end

    function M.findPad()
        if runState.pad and runState.pad.Parent then return runState.pad end
        runState.pad = nil
        for _, root in ipairs(mapRoots()) do
            if root.Name == "Map" or root.Name == "Map1" then
                local castle = root:FindFirstChild("3 | Castle")
                local interact = castle and castle:FindFirstChild("INTERACT")
                local chest = (interact and interact:FindFirstChild("CrystalChest")) or root:FindFirstChild("CrystalChest", true)
                local pad = chest and (chest:FindFirstChild("Pad") or chest:FindFirstChild("Pad", true))
                if pad and pad:IsA("BasePart") then runState.pad = pad return pad end
            end
        end
        return nil
    end

    function M.release(reason)
        if state.farmHold or runState.phase ~= "off" then
            state.farmHold = false
            clearMovement("mod:crystal")
        end
        runState.phase, runState.pending = "off", nil
        runState.reason = reason
    end

    function M.runner()
        if not Config.CrystalKeyMode or not state.running then M.release("mode off") return end
        if now() - (plan.checkedAt or 0) >= 5 or runState.pending then M.refreshPlan(runState.pending ~= nil) end
        -- Settle the previous open first: the key stack must shrink.
        if runState.pending then
            if plan.keys < runState.pending.before then
                runState.opened, runState.misses, runState.pending = runState.opened + 1, 0, nil
                Modules.note("crystal", "open", "confirmed", "Crystal Chest opened (keys " .. plan.keys .. ")")
            elseif now() - runState.pending.sent > 6 then
                runState.pending, runState.misses = nil, runState.misses + 1
                Modules.note("crystal", "open", "failed", "no key consumed")
                if runState.misses >= 3 then
                    Config.CrystalKeyMode = false
                    M.release("3 opens consumed no key: mode switched off (re-teach the chest action)")
                    log("Crystal mode stopped: " .. runState.reason, "SAFEGUARD")
                    return
                end
            else
                return
            end
        end
        local opener = M.opener()
        local spare = plan.keys - math.max(0, tonumber(Config.CrystalKeyReserve) or 0)
        if not opener then M.release("teach the chest action first (Auto Rank page)") return end
        if spare < 1 then M.release("no spare Crystal Keys") return end
        if not plan.ready then M.release("setup: " .. tostring(plan.status)) return end
        if (state.world and state.world.number) ~= 1 then M.release("go to World 1 (Castle) to use the Crystal Chest") return end
        local pad = M.findPad()
        if not pad then M.release("Crystal Chest not loaded (stand in World 1 Castle area)") return end
        -- Hold the breakable quests: no farming while the method runs.
        state.farmHold = true
        if not movementAvailable("mod:crystal") then runState.phase = "waiting for movement" return end
        leaseMovement("mod:crystal", 8)
        local root = currentRoot()
        if root and (root.Position - pad.Position).Magnitude > 8 then
            pcall(function() root.CFrame = pad.CFrame + Vector3.new(0, 3, 0) end)
            runState.phase = "moving to chest"
            return
        end
        runState.phase = "opening"
        if now() < runState.nextOpen then return end
        local recorder = Modules.byId.recorder
        if not recorder then M.release("recorder unavailable") return end
        local args, why = recorder.resolve(opener.args)
        if not args then M.release(tostring(why)) return end
        runState.nextOpen = now() + math.max(0.5, tonumber(Config.CrystalOpenSeconds) or 1.5)
        local accepted = Modules.call("crystal", "open", opener.name, args, opener.method == "Invoke", 0.5)
        if accepted then runState.pending = {before = plan.keys, sent = now()} end
    end

    function M.tick()
        M.runner()
        if not Config.CrystalKeyMode and now() - (plan.checkedAt or 0) >= 5 then M.refreshPlan(false) end
    end
    M.active = function() return true end
    M.runWhilePaused = true
    M.interval = 1
    function M.onPause() M.release("paused") end
    function M.cleanup() M.release("stopped") end
    function M.onSetting(field, value)
        if field == "CrystalKeyMode" and not value then M.release("mode off") end
    end

    function M.report()
        local parts = {}
        for slot = 1, 4 do
            local q = plan.slots[slot]
            if q then table.insert(parts, string.format("s%d=%s %d/%d", slot, M.NAMES[q.type] or tostring(q.type), q.progress, q.amount)) end
        end
        return tostring(plan.status) .. " | keys=" .. tostring(plan.keys) .. " | " .. table.concat(parts, ", ")
    end

    function M.buildUI(h, ui)
        local p = h.page("ranks")
        h.section(p, "CRYSTAL KEY METHOD", "Hold breakable quests in slots 2-4, then open the World 1 Crystal Chest")
        ui.crystalStatus = h.rowLabel(p, "Crystal setup: not checked")
        ui.crystalSlots = h.rowLabel(p, "Slots: not read")
        h.toggle(p, "CrystalKeyMode", "Crystal Key rank-up mode",
            "Spends Crystal Keys. Pauses farming while the setup is held; stops if keys are not consumed")
        h.toolbar(p, {
            {"1) TEACH CHEST OPEN", function()
                local recorder = Modules.byId.recorder
                if not recorder then return end
                local ok, why = recorder.start(20)
                log(ok and "Open the Crystal Chest once by hand within 20 s" or ("Recorder: " .. tostring(why)), "SYSTEM")
            end},
            {"2) SAVE CHEST ACTION", function()
                local recorder = Modules.byId.recorder
                local capture = recorder and recorder.find({"chest", "crystal", "key"})
                if capture and recorder.learn("crystalChest", capture) then
                    log("Saved chest action: " .. capture.method .. " " .. capture.name, "SYSTEM")
                else
                    log("No chest/key request was recorded; record again while opening the chest", "WAIT")
                end
            end},
        })
        ui.crystalRun = h.rowLabel(p, "Crystal mode: off")
    end
    function M.render(ui)
        if ui.activePage ~= "ranks" or not ui.crystalStatus then return end
        ui.crystalStatus.Text = "Crystal setup: " .. tostring(plan.status) .. "  |  keys " .. tostring(plan.keys)
        local parts = {}
        for slot = 1, 4 do
            local q = plan.slots[slot]
            if q then table.insert(parts, string.format("%d: %s %d/%d", slot, M.NAMES[q.type] or ("type " .. tostring(q.type)), q.progress, q.amount)) end
        end
        ui.crystalSlots.Text = "Slots  " .. (#parts > 0 and table.concat(parts, "   ") or "none")
        local opener = M.opener()
        ui.crystalRun.Text = string.format("Mode: %s%s  |  opened %d  |  chest action: %s", runState.phase,
            runState.reason and runState.phase == "off" and (" (" .. runState.reason .. ")") or "", runState.opened,
            opener and opener.name or "not taught")
    end
    Modules.define(M)
end)()
