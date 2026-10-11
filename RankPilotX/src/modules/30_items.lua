-- Items & Boosts: optional boost upkeep outside rank quests. Rank-quest item
-- use (Use N fruits/potions/flags) stays in the v5.1 consumables lane.
-- Every action here spends inventory, so all toggles are OFF by default,
-- each stack keeps a reserve, and use is confirmed by the stack amount
-- dropping in Save data (a fired request alone is not counted as success).
--   Fruits: Consume (Fire) (uid, 1)             VY AutoRank
--   Potions: Consume (Fire) (uid, 1)            decompiled capture + VY AutoRank
--   FlexibleFlagCmds.Consume(flagId, uid, 1)    VY AutoRank (returns true / false,msg)
(function()
    local M = {id = "items", title = "Items & Boosts", page = "items", interval = 4}
    M.defaults = {AutoEatFruits = false, EatShinyFruits = false, FruitReserve = 10, FruitEatSeconds = 240,
        AutoUsePotions = false, PotionReserve = 5, PotionUseSeconds = 600,
        AutoUseFlags = false, FlagReserve = 2, FlagUseSeconds = 300}
    M.features = {
        {key = "AutoEatFruits", name = "Keep fruit boosts", status = "UNVERIFIED", evidence = "Fruits: Consume (uid,1) Fire - VY AutoRank"},
        {key = "AutoUsePotions", name = "Keep potion boosts", status = "UNVERIFIED", evidence = "Potions: Consume (uid,1) Fire - decompiled capture, VY"},
        {key = "AutoUseFlags", name = "Place flags in current area", status = "UNVERIFIED", evidence = "FlexibleFlagCmds.Consume(flagId,uid,1) - VY AutoRank"},
    }
    local pending = {}       -- uid -> {before, sent, kind, id}
    local lastUse = {}       -- kind..":"..id -> time of last confirmed/attempted use
    M.pending, M.lastUse = pending, lastUse

    -- Highest-tier stack per item id, skipping stacks at or below the reserve.
    function M.candidates(class, reserve, allowShiny)
        local rows = Modules.inventory(class)
        local best = {}
        for uid, row in pairs(rows or {}) do
            if type(row) == "table" and type(row.id) == "string" then
                local amount = tonumber(row._am) or 1
                local shinyOk = allowShiny or row.sh ~= true
                if shinyOk and amount > reserve then
                    local tier = tonumber(row.tn) or 0
                    local current = best[row.id]
                    if not current or tier > current.tier then
                        best[row.id] = {uid = uid, id = row.id, tier = tier, amount = amount}
                    end
                end
            end
        end
        local list = {}
        for _, entry in pairs(best) do table.insert(list, entry) end
        table.sort(list, function(a, b) return a.id < b.id end)
        return list
    end

    -- A stack that shrank since the request confirms the use.
    function M.verify(class)
        local rows = Modules.inventory(class, true)
        for uid, p in pairs(pending) do
            if p.class == class and now() - p.sent >= 2 then
                local row = rows and rows[uid]
                local amount = type(row) == "table" and (tonumber(row._am) or 1) or 0
                local settled = true
                if amount < p.before then
                    Modules.note("items", p.kind, "confirmed", p.id .. " used (stack " .. p.before .. " -> " .. amount .. ")")
                elseif now() - p.sent > 12 then
                    Modules.note("items", p.kind, "failed", p.id .. " not consumed according to Save")
                    lastUse[p.kind .. ":" .. p.id] = now() + 600 -- back off this item for 10 extra minutes
                else
                    settled = false -- Save may replicate a little later
                end
                if settled then pending[uid] = nil end
            end
        end
    end

    local function hasPending(class)
        for _, p in pairs(pending) do if p.class == class then return true end end
        return false
    end

    -- Use at most one stack per tick per class, round-robin by id.
    function M.useOne(kind, class, list, cooldown, send)
        if hasPending(class) then return false end
        for _, entry in ipairs(list) do
            local key = kind .. ":" .. entry.id
            if now() >= (lastUse[key] or 0) then
                lastUse[key] = now() + cooldown
                local ok, why = send(entry)
                if ok then
                    pending[entry.uid] = {before = entry.amount, sent = now(), kind = kind, class = class, id = entry.id}
                    return true
                end
                Modules.state("items").last = kind .. " " .. entry.id .. " refused: " .. describe(why)
                return false
            end
        end
        return false
    end

    -- Never spend boosts while the rank engine is working an item quest of
    -- the same class: the v5.1 consumables lane needs those exact stacks.
    function M.questNeeds(kind)
        for _, g in ipairs(state.goals or {}) do
            if g.kind == kind and (g.required or 0) > (g.progress or 0) then return true end
        end
        return false
    end

    function M.inInstance()
        local ok, inside = callMethod(Modules.client("InstancingCmds"), "IsInInstance")
        return ok and inside == true
    end

    function M.tick()
        M.verify("Fruit")
        M.verify("Potion")
        M.verify("Misc")
        if Config.AutoEatFruits and not M.questNeeds("fruit") then
            local list = M.candidates("Fruit", math.max(0, tonumber(Config.FruitReserve) or 10), Config.EatShinyFruits)
            M.useOne("fruit", "Fruit", list, math.max(30, tonumber(Config.FruitEatSeconds) or 240), function(entry)
                return Modules.call("items", "fruit", "Fruits: Consume", {entry.uid, 1}, false, 1)
            end)
        end
        if Config.AutoUsePotions and not M.questNeeds("potion") then
            local list = M.candidates("Potion", math.max(0, tonumber(Config.PotionReserve) or 5), true)
            M.useOne("potion", "Potion", list, math.max(60, tonumber(Config.PotionUseSeconds) or 600), function(entry)
                return Modules.call("items", "potion", "Potions: Consume", {entry.uid, 1}, false, 1)
            end)
        end
        if Config.AutoUseFlags and not M.questNeeds("flag") and not M.inInstance() then
            local flags = {}
            for _, entry in ipairs(M.candidates("Misc", math.max(0, tonumber(Config.FlagReserve) or 2), true)) do
                if entry.id:sub(-5) == " Flag" then table.insert(flags, entry) end
            end
            local flagCmds = Modules.client("FlexibleFlagCmds")
            if flagCmds then
                M.useOne("flag", "Misc", flags, math.max(60, tonumber(Config.FlagUseSeconds) or 300), function(entry)
                    Modules.note("items", "flag", "attempted")
                    local ok, result, message = callMethod(flagCmds, "Consume", entry.id, entry.uid, 1)
                    if ok and result ~= false then
                        Modules.note("items", "flag", "accepted")
                        return true
                    end
                    return false, message or result
                end)
            end
        end
    end
    M.active = function()
        return Config.AutoEatFruits == true or Config.AutoUsePotions == true or Config.AutoUseFlags == true
    end

    function M.report()
        local n = 0
        for _ in pairs(pending) do n = n + 1 end
        return "pending confirmations=" .. n
    end

    function M.buildUI(h, ui)
        local p = h.page("items")
        h.section(p, "BOOST UPKEEP", "Optional item use outside rank quests. Spends items: OFF by default, keeps a reserve")
        h.toggle(p, "AutoEatFruits", "Keep fruit boosts", "Eat one of each fruit type every few minutes above the reserve")
        h.toggle(p, "EatShinyFruits", "Include shiny fruits", "Shiny fruits are skipped unless this is ON")
        h.choice(p, "Fruit reserve", "Never eat a fruit stack below this amount",
            function() return tostring(Config.FruitReserve) .. "  >" end,
            function()
                local opts, idx = {0, 10, 25, 50, 100}, 1
                for i, v in ipairs(opts) do if v == Config.FruitReserve then idx = i break end end
                Config.FruitReserve = opts[idx % #opts + 1]
            end)
        h.toggle(p, "AutoUsePotions", "Keep potion boosts", "Use the highest tier of each potion every 10 minutes; paused while a use-potion quest is active")
        h.choice(p, "Potion reserve", "Never use a potion stack below this amount",
            function() return tostring(Config.PotionReserve) .. "  >" end,
            function()
                local opts, idx = {2, 5, 10, 25}, 1
                for i, v in ipairs(opts) do if v == Config.PotionReserve then idx = i break end end
                Config.PotionReserve = opts[idx % #opts + 1]
            end)
        h.toggle(p, "AutoUseFlags", "Place flags in current area", "FlexibleFlagCmds.Consume; never inside instances; keeps a reserve")
        ui.itemsStatus = h.rowLabel(p, "Items: not checked")
    end

    function M.render(ui)
        if ui.activePage ~= "items" or not ui.itemsStatus then return end
        local fruit, potion, flag = Modules.stat("items", "fruit"), Modules.stat("items", "potion"), Modules.stat("items", "flag")
        ui.itemsStatus.Text = string.format("Confirmed uses  fruit %d/%d  potion %d/%d  flag %d/%d (confirmed/attempted)",
            fruit.confirmed, fruit.attempted, potion.confirmed, potion.attempted, flag.confirmed, flag.attempted)
    end
    Modules.define(M)
end)()
