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

    function M.tick()
        local data = saveData()
        if type(data) ~= "table" then plan.status = "Save unavailable" return end
        local slots = M.readSlots(data)
        local rank = tonumber(data.Rank)
        local pool = rank and M.slotPool(rank, 1)
        local ready, status, blockers = M.analyze(pool, slots)
        plan.ready, plan.status, plan.blockers, plan.slots = ready, status, blockers, slots
        plan.keys = Modules.countItem("Misc", "Crystal Key")
        Modules.state("crystal").last = status .. " | crystal keys " .. plan.keys
    end
    M.active = function() return true end
    M.runWhilePaused = true

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
        h.section(p, "CRYSTAL KEY METHOD", "Checks the quest-slot setup from the game's own rank data")
        ui.crystalStatus = h.rowLabel(p, "Crystal setup: not checked")
        ui.crystalSlots = h.rowLabel(p, "Slots: not read")
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
    end
    Modules.define(M)
end)()
