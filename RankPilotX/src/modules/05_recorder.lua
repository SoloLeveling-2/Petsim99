-- Action recorder ("teach an action"). For game actions with no readable
-- source (e.g. opening the Crystal Chest), the user performs the action once
-- by hand while the recorder briefly wraps the game's own Library.Client.Network
-- Invoke/Fire functions and notes which request the game itself sent. A feature
-- may then repeat exactly that request; nothing is guessed. Wrappers are
-- installed only during a short window and always restored (also on Stop).
-- Arguments are stored as a template: a string equal to an inventory item
-- UID becomes {item = <item id>} and is re-resolved to the current UID on replay.
(function()
    local M = {id = "recorder", title = "Action recorder", page = "diagnostics"}
    M.defaults = {LearnedActions = {}}
    local rec = {active = false, untilAt = 0, originals = nil, owner = nil, captures = {}}
    M.rec = rec
    local METHODS = {"Invoke", "Fire", "UnreliableFire"}
    -- Constant background traffic that is never the action being taught.
    local NOISE = {"Breakables_", "Orbs", "Lootbags", "Pets", "Idle", "Is Real Player", "Mark Approached",
        "Ping", "Tutorial", "EventLog", "Slingshot", "Hoverboard", "Emote", "Settings"}

    local function noisy(name)
        for _, word in ipairs(NOISE) do if string.find(name, word, 1, true) then return true end end
        return false
    end

    -- Map inventory UIDs to item ids so templates survive stack changes.
    local function uidIndex()
        local data = saveData(true)
        local index = {}
        local inv = type(data) == "table" and data.Inventory or {}
        for class, rows in pairs(type(inv) == "table" and inv or {}) do
            if type(rows) == "table" then
                for uid, row in pairs(rows) do
                    if type(row) == "table" and type(row.id) == "string" then index[uid] = {class = class, id = row.id} end
                end
            end
        end
        return index
    end

    function M.template(args, index)
        local out = {}
        for i, v in ipairs(args) do
            local t = type(v)
            if t == "string" and index[v] then
                out[i] = {item = index[v].id, class = index[v].class}
            elseif t == "string" or t == "number" or t == "boolean" then
                out[i] = v
            else
                return nil, "argument " .. i .. " is a " .. t .. " (cannot be replayed safely)"
            end
        end
        return out
    end

    function M.resolve(template)
        local args = {}
        for i, v in ipairs(template or {}) do
            if type(v) == "table" and v.item then
                local rows = Modules.inventory(v.class or "Misc", true)
                local uid = nil
                for candidate, row in pairs(rows or {}) do
                    if type(row) == "table" and row.id == v.item and (tonumber(row._am) or 1) > 0 then uid = candidate break end
                end
                if not uid then return nil, "no " .. tostring(v.item) .. " left" end
                args[i] = uid
            else
                args[i] = v
            end
        end
        return args
    end

    function M.stop()
        if rec.originals and rec.owner then
            for method, fn in pairs(rec.originals) do pcall(function() rec.owner[method] = fn end) end
        end
        rec.originals, rec.owner, rec.active = nil, nil, false
    end

    function M.start(seconds)
        M.stop()
        local net = state.clients and state.clients.Network
        if type(net) ~= "table" then return false, "game Network module unavailable" end
        local index = uidIndex()
        rec.captures, rec.originals, rec.owner = {}, {}, net
        for _, method in ipairs(METHODS) do
            local original = net[method]
            if type(original) == "function" then
                rec.originals[method] = original
                local ok = pcall(function()
                    net[method] = function(name, ...)
                        if rec.active and type(name) == "string" and not noisy(name) and #rec.captures < 40 then
                            local template, why = M.template({...}, index)
                            table.insert(rec.captures, {method = method, name = name, template = template,
                                problem = why, at = now()})
                        end
                        return original(name, ...)
                    end
                end)
                if not ok then rec.originals[method] = nil end
            end
        end
        if next(rec.originals) == nil then rec.owner = nil return false, "Network functions are read-only here" end
        rec.active, rec.untilAt = true, now() + math.clamp(tonumber(seconds) or 15, 5, 60)
        log("Recorder ON: perform the action in-game now (" .. math.floor(rec.untilAt - now()) .. " s)", "SYSTEM")
        return true
    end

    -- Most recent capture whose name matches one of the patterns (plain, lower-case).
    function M.find(patterns)
        for i = #rec.captures, 1, -1 do
            local c = rec.captures[i]
            local lower = string.lower(c.name)
            for _, p in ipairs(patterns) do
                if string.find(lower, p, 1, true) and c.template then return c end
            end
        end
        return nil
    end

    function M.learn(key, capture)
        if not capture or not capture.template then return false end
        local learned = type(Config.LearnedActions) == "table" and Config.LearnedActions or {}
        learned[key] = {name = capture.name, method = capture.method, args = capture.template}
        Config.LearnedActions = learned
        persist()
        return true
    end
    function M.learned(key)
        local learned = type(Config.LearnedActions) == "table" and Config.LearnedActions or {}
        local action = learned[key]
        if type(action) == "table" and type(action.name) == "string" and type(action.args) == "table" then return action end
        return nil
    end

    function M.tick()
        if rec.active and now() >= rec.untilAt then
            M.stop()
            log("Recorder OFF: " .. #rec.captures .. " game request(s) captured", "SYSTEM")
        end
    end
    M.active = function() return rec.active end
    M.runWhilePaused = true
    M.interval = 1
    function M.cleanup() M.stop() end

    function M.report()
        local names = {}
        for _, c in ipairs(rec.captures) do table.insert(names, c.method .. " " .. c.name) end
        return "captures: " .. (#names > 0 and table.concat(names, "; ") or "none")
    end

    function M.buildUI(h, ui)
        local p = h.page("diagnostics")
        h.section(p, "TEACH AN ACTION", "Records which request the game sends when YOU perform an action")
        h.toolbar(p, {{"RECORD 15 SECONDS", function() local ok, why = M.start(15) if not ok then log("Recorder: " .. tostring(why), "WAIT") end end},
            {"STOP RECORDING", M.stop}})
        ui.recorderRows = {}
        for i = 1, 4 do ui.recorderRows[i] = h.rowLabel(p, i == 1 and "No recording yet" or "") end
    end
    function M.render(ui)
        if ui.activePage ~= "diagnostics" or not ui.recorderRows then return end
        for i = 1, 4 do
            local c = rec.captures[#rec.captures - i + 1]
            ui.recorderRows[i].Text = c and string.format("%s %s (%s)", c.method, c.name, c.template and "replayable" or tostring(c.problem))
                or (i == 1 and (rec.active and "Recording... perform the action now" or "No recording yet") or "")
        end
    end
    Modules.define(M)
end)()
