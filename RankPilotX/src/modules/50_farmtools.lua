-- Farm tools: ultimates, toys and TNT. Sources (research 2026-10-11):
--   Network["Ultimates: Activate"] Invoke(ultimateId); id from
--     UltimateCmds.GetEquippedItem():GetId(), gated by UltimateCmds.IsCharged(id)
--     [Fishka AutoUseUltimate.lua 2026-03-31; juhjuh ps99-hub main.lua 2026-08; qvirthh 2026-10-03]
--   SqueakyToy_Consume / ToyBall_Consume / ToyBone_Consume Invoke() no args
--     [Fishka AutoEatFruitsAndToys.lua 2026-03-30; single source] buff 600/300/300 s (BIG Games API Buffs)
--   TNT_Consume / TNT_Crate_Consume Invoke() no args [CHICHazHUB PSXfarm, 2024-02 only]
-- Ultimates are free and fire only when the game says they are charged.
-- Toys and TNT spend items: OFF by default, confirmed by the Misc stack
-- shrinking, and an item that is not consumed twice in a row is disabled.
(function()
    local M = {id = "farmtools", title = "Farm tools", page = "farm", interval = 3}
    M.defaults = {AutoUltimate = true, AutoUseToys = false, AutoUseTNT = false}
    M.features = {
        {key = "AutoUltimate", name = "Use ultimate when charged", status = "UNVERIFIED",
            evidence = "Ultimates: Activate(id) + UltimateCmds.IsCharged - 3 sources 2026"},
        {key = "AutoUseToys", name = "Use toys", status = "EXPERIMENTAL",
            evidence = "<Toy>_Consume() no-arg Invoke - one 2026 source"},
        {key = "AutoUseTNT", name = "Use TNT / TNT crates", status = "EXPERIMENTAL",
            evidence = "TNT_Consume / TNT_Crate_Consume no-arg Invoke - 2024 source only"},
    }
    M.ITEMS = {
        {id = "Squeaky Toy", remote = "SqueakyToy_Consume", key = "toys", seconds = 600},
        {id = "Toy Ball", remote = "ToyBall_Consume", key = "toys", seconds = 300},
        {id = "Toy Bone", remote = "ToyBone_Consume", key = "toys", seconds = 300},
        {id = "TNT", remote = "TNT_Consume", key = "tnt", seconds = 12},
        {id = "TNT Crate", remote = "TNT_Crate_Consume", key = "tnt", seconds = 20},
    }
    local itemState = {}  -- id -> {next, pending={before,sent}, misses, disabled}
    local ult = {last = "not checked", pendingId = nil, pendingAt = 0}
    M.itemState, M.ult = itemState, ult

    function M.ultimateTick()
        local cmds = Modules.client("UltimateCmds")
        if not cmds then ult.last = "UltimateCmds unavailable" return false end
        local okItem, item = callMethod(cmds, "GetEquippedItem")
        if not okItem or item == nil then ult.last = "no ultimate equipped" return false end
        local okId, id = pcall(function() return item:GetId() end)
        if not okId or type(id) ~= "string" then ult.last = "equipped ultimate id unreadable" return false end
        local okCharged, charged = callMethod(cmds, "IsCharged", id)
        if not okCharged then ult.last = "IsCharged unavailable: not firing blindly" return false end
        if ult.pendingId == id and now() - ult.pendingAt < 6 then
            if charged == false then
                Modules.note("farmtools", "ultimate", "confirmed", id .. " used (charge consumed)")
                ult.pendingId = nil
            end
            return false
        end
        ult.pendingId = nil
        if charged ~= true then ult.last = id .. " charging" return false end
        local accepted = Modules.call("farmtools", "ultimate", "Ultimates: Activate", {id}, true, 4)
        if accepted then
            ult.pendingId, ult.pendingAt = id, now()
            ult.last = id .. " activated; waiting for charge to reset"
        end
        return accepted
    end

    -- Shared pending/confirm logic for no-argument Misc item remotes.
    function M.itemTick(spec)
        local s = itemState[spec.id] or {next = 0, misses = 0}
        itemState[spec.id] = s
        if s.disabled then return false end
        local count = Modules.countItem("Misc", spec.id, s.pending ~= nil)
        if s.pending then
            if count < s.pending.before then
                Modules.note("farmtools", spec.key, "confirmed", spec.id .. " used")
                s.pending, s.misses = nil, 0
            elseif now() - s.pending.sent > 6 then
                s.pending, s.misses = nil, s.misses + 1
                Modules.note("farmtools", spec.key, "failed", spec.id .. " not consumed according to Save")
                if s.misses >= 2 then
                    s.disabled = true
                    log(spec.remote .. " did not consume " .. spec.id .. " twice; disabled until RECHECK", "SAFEGUARD")
                end
            end
            return false
        end
        if count < 1 or now() < s.next then return false end
        s.next = now() + spec.seconds
        local accepted = Modules.call("farmtools", spec.key, spec.remote, {}, true, 2)
        if accepted then s.pending = {before = count, sent = now()} end
        return accepted
    end

    function M.tick()
        if Config.AutoUltimate and state.running and Config.AutoFarm and not inHatchMovementWindow() then
            M.ultimateTick()
        end
        if (Config.AutoUseToys or Config.AutoUseTNT) and state.running and Config.AutoFarm then
            for _, spec in ipairs(M.ITEMS) do
                if (spec.key == "toys" and Config.AutoUseToys) or (spec.key == "tnt" and Config.AutoUseTNT) then
                    M.itemTick(spec)
                end
            end
        end
    end
    M.active = function() return Config.AutoUltimate == true or Config.AutoUseToys == true or Config.AutoUseTNT == true end
    function M.recheck()
        for _, s in pairs(itemState) do s.disabled, s.misses = false, 0 end
    end

    function M.report()
        local disabled = {}
        for id, s in pairs(itemState) do if s.disabled then table.insert(disabled, id) end end
        return "ultimate=" .. tostring(ult.last) .. (#disabled > 0 and (" | disabled: " .. table.concat(disabled, ", ")) or "")
    end

    function M.buildUI(h, ui)
        local p = h.page("farm")
        h.section(p, "FARM TOOLS", "Ultimates are free; toys and TNT spend items and are confirmed by inventory")
        h.toggle(p, "AutoUltimate", "Use ultimate when charged", "Ultimates: Activate for the equipped ultimate, only when IsCharged says so")
        h.toggle(p, "AutoUseToys", "Use toys", "Squeaky Toy / Toy Ball / Toy Bone once per buff duration (experimental)")
        h.toggle(p, "AutoUseTNT", "Use TNT and TNT crates", "Experimental 2024 remotes; disabled automatically if items are not consumed")
        ui.farmToolsStatus = h.rowLabel(p, "Ultimate: not checked")
        h.note(p, "Breakable sprinklers are not automated: no readable source shows how the game places them.", 40)
    end
    function M.render(ui)
        if ui.activePage ~= "farm" or not ui.farmToolsStatus then return end
        local u = Modules.stat("farmtools", "ultimate")
        ui.farmToolsStatus.Text = string.format("Ultimate: %s  |  used %d/%d confirmed  |  toys %d  tnt %d",
            tostring(ult.last), u.confirmed, u.attempted, Modules.stat("farmtools", "toys").confirmed,
            Modules.stat("farmtools", "tnt").confirmed)
    end
    Modules.define(M)
end)()
