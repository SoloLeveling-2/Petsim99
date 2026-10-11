-- Events: live random-event monitor and quest focus.
--   RandomEventCmds.GetActive() -> {ev} with ev.dir (Directory.RandomEvents
--   entry), ev.uid/ev.id and ev.parentID (zone)   [VY AutoRank, decompiled RandomEventCmds]
-- Focus does not move the character or spend items: when a coin jar, comet,
-- pinata or lucky block event is active in the zone the farm lane already
-- uses, the matching rank quest is promoted through the engine's existing
-- eventFocus mechanism so pets attack it first. Retired seasonal events have
-- no code here, so no retired remote can ever be fired.
(function()
    local M = {id = "events", title = "Events", page = "events", interval = 5}
    M.defaults = {EventQuestFocus = true}
    M.features = {
        {key = "EventQuestFocus", name = "Focus quests on live random events", status = "UNVERIFIED",
            evidence = "RandomEventCmds.GetActive (VY AutoRank); engine eventFocus"},
    }
    local live = {list = {}, summary = "not checked"}
    M.live = live
    local KINDS = {
        {pattern = "coin jar", kind = "coinjar"}, {pattern = "comet", kind = "comet"},
        {pattern = "pinata", kind = "pinata"}, {pattern = "piñata", kind = "pinata"},
        {pattern = "lucky block", kind = "luckyblock"},
    }

    function M.kindOf(name)
        local lower = string.lower(tostring(name or ""))
        for _, entry in ipairs(KINDS) do
            if string.find(lower, entry.pattern, 1, true) then return entry.kind end
        end
        return nil
    end

    function M.readActive()
        local commands = Modules.client("RandomEventCmds")
        local ok, active = callMethod(commands, "GetActive")
        if not ok or type(active) ~= "table" then return nil, commands and "GetActive failed" or "RandomEventCmds unavailable" end
        local list = {}
        for key, ev in pairs(active) do
            if type(ev) == "table" then
                local dir = type(ev.dir) == "table" and ev.dir or {}
                local name = dir.Name or dir.name or dir._id or ev.name or ev.Name or tostring(key)
                table.insert(list, {name = tostring(name), uid = ev.uid or ev.id or key,
                    zone = ev.parentID or ev.ParentID, kind = M.kindOf(name)})
            end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        return list
    end

    function M.tick()
        local list, why = M.readActive()
        if not list then
            live.list, live.summary = {}, tostring(why)
            Modules.state("events").last = live.summary
            return
        end
        live.list = list
        local names = {}
        for _, ev in ipairs(list) do
            table.insert(names, ev.name .. (ev.zone and (" @" .. tostring(ev.zone)) or ""))
        end
        live.summary = #names > 0 and table.concat(names, ", ") or "no active random events"
        Modules.state("events").last = live.summary
        if not (Config.EventQuestFocus and state.running and Config.AutoFarm) then return end
        local okZone, farmZone = pcall(currentFarmZone)
        farmZone = okZone and farmZone or nil
        for _, ev in ipairs(list) do
            if ev.kind and (ev.zone == nil or (farmZone and tostring(ev.zone) == tostring(farmZone))) then
                for _, goal in ipairs(state.goals or {}) do
                    if goal.kind == ev.kind and (goal.required or 0) > (goal.progress or 0) and eligible(goal) then
                        if state.eventFocus ~= goal.identity then
                            Modules.note("events", "focus", "accepted", "focused " .. goal.title .. " on live " .. ev.name)
                        end
                        state.eventFocus, state.eventFocusUntil = goal.identity, now() + 12
                        return
                    end
                end
            end
        end
    end
    M.active = function() return true end

    function M.report() return "active events: " .. tostring(live.summary) end

    function M.buildUI(h, ui)
        local p = h.page("events")
        h.section(p, "LIVE RANDOM EVENTS", "Read from the game's RandomEventCmds while running")
        ui.eventsLive = h.rowLabel(p, "Active events: not checked")
        h.toggle(p, "EventQuestFocus", "Focus quests on live events",
            "Promote a matching coin jar/comet/pinata/lucky block quest when its event is in your farm zone")
        h.note(p, "Seasonal event tabs from other hubs (Christmas 2025, Lucky Raid 2026, Halloween 2025) are retired; they are intentionally not implemented and no retired remote is ever called.", 52)
    end
    function M.render(ui)
        if ui.activePage ~= "events" or not ui.eventsLive then return end
        ui.eventsLive.Text = "Active events: " .. tostring(live.summary)
    end
    Modules.define(M)
end)()
