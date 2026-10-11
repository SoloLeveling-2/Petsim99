-- Optimization & player utilities (Roblox engine APIs only, no game remotes).
-- Patterns from DZ Hub (WalkSpeed, Noclip, Rejoin) and VY AutoRank (anti-AFK).
-- Everything is reversible: originals are saved and restored on toggle-off,
-- pause (walk speed / noclip) and Stop.
(function()
    local M = {id = "player", title = "Player & performance", page = "performance", interval = 2, runWhilePaused = true}
    M.defaults = {PerformanceMode = false, AntiAFK = true, FPSCap = 0, WalkSpeedOverride = 0, NoClip = false}
    M.features = {
        {key = "PerformanceMode", name = "Performance mode", status = "UNVERIFIED", evidence = "Local: doubles module intervals"},
        {key = "AntiAFK", name = "Anti-AFK", status = "UNVERIFIED", evidence = "LocalPlayer.Idled + VirtualUser (DZ Hub, VY AutoRank)"},
        {key = "NoClip", name = "Noclip", status = "UNVERIFIED", evidence = "Character BasePart CanCollide (DZ Hub)"},
    }
    local saved = {walkSpeed = nil, humanoid = nil, collide = {}, fps = nil, confirmAt = {}}
    local conns = {}
    M.saved = saved

    local function humanoid()
        local character = LocalPlayer and LocalPlayer.Character
        if not character then return nil end
        local okFind, hum = pcall(function() return character:FindFirstChildOfClass("Humanoid") end)
        return okFind and hum or nil
    end

    function M.applyWalkSpeed()
        local target = tonumber(Config.WalkSpeedOverride) or 0
        local hum = humanoid()
        if target <= 0 then
            if saved.humanoid and saved.walkSpeed and saved.humanoid.Parent then
                pcall(function() saved.humanoid.WalkSpeed = saved.walkSpeed end)
            end
            saved.humanoid, saved.walkSpeed = nil, nil
            return false
        end
        if not hum then return false end
        if saved.humanoid ~= hum then saved.humanoid, saved.walkSpeed = hum, hum.WalkSpeed end
        if hum.WalkSpeed ~= target then pcall(function() hum.WalkSpeed = target end) end
        return true
    end

    -- Parts are cached per character; only parts that collided are touched
    -- and exactly those are restored.
    function M.setNoClip(enabled)
        if enabled then
            if conns.noclip then return true end
            local okSignal, stepped = pcall(function() return RunService.Stepped end)
            if not okSignal or not stepped then return false end
            conns.noclip = stepped:Connect(function()
                local character = LocalPlayer and LocalPlayer.Character
                if not character or state.shutdown then return end
                if saved.noclipCharacter ~= character then
                    saved.noclipCharacter, saved.noclipParts = character, {}
                    for _, part in ipairs(character:GetDescendants()) do
                        if part:IsA("BasePart") then table.insert(saved.noclipParts, part) end
                    end
                end
                for _, part in ipairs(saved.noclipParts) do
                    if part.CanCollide then
                        saved.collide[part] = true
                        part.CanCollide = false
                    end
                end
            end)
            table.insert(state.connections, conns.noclip)
            return true
        end
        if conns.noclip then pcall(function() conns.noclip:Disconnect() end) conns.noclip = nil end
        for part in pairs(saved.collide) do
            if part.Parent then pcall(function() part.CanCollide = true end) end
        end
        saved.collide, saved.noclipCharacter, saved.noclipParts = {}, nil, nil
        return true
    end

    function M.setAntiAFK(enabled)
        if enabled and not conns.idle then
            local okService, virtualUser = pcall(function() return game:GetService("VirtualUser") end)
            if not okService or not virtualUser or not LocalPlayer or not LocalPlayer.Idled then return false end
            conns.idle = LocalPlayer.Idled:Connect(function()
                if state.shutdown or not Config.AntiAFK then return end
                pcall(function()
                    virtualUser:CaptureController()
                    virtualUser:ClickButton2(Vector2.new())
                end)
                Modules.note("player", "antiafk", "confirmed", "idle kick prevented " .. os.date("%H:%M:%S"))
            end)
            table.insert(state.connections, conns.idle)
        elseif not enabled and conns.idle then
            pcall(function() conns.idle:Disconnect() end)
            conns.idle = nil
        end
        return true
    end

    function M.applyFPS()
        if type(setfpscap) ~= "function" then return false, "setfpscap unavailable in this executor" end
        local cap = tonumber(Config.FPSCap) or 0
        if cap > 0 then
            if saved.fps == nil and type(getfpscap) == "function" then
                local okGet, current = pcall(getfpscap)
                saved.fps = okGet and tonumber(current) or false
            end
            return pcall(setfpscap, cap)
        end
        if saved.fps then pcall(setfpscap, saved.fps) end
        saved.fps = nil
        return true
    end

    function M.tick()
        if Config.AntiAFK and not conns.idle then M.setAntiAFK(true) end
        if state.running then
            M.applyWalkSpeed()
            if Config.NoClip and not conns.noclip then M.setNoClip(true) end
        end
    end
    M.active = function()
        return Config.AntiAFK == true or (tonumber(Config.WalkSpeedOverride) or 0) > 0 or Config.NoClip == true
    end

    function M.onSetting(field, value)
        if field == "AntiAFK" then M.setAntiAFK(value == true)
        elseif field == "NoClip" then M.setNoClip(value == true and state.running)
        elseif field == "WalkSpeedOverride" then M.applyWalkSpeed() end
    end
    function M.onStart()
        if Config.NoClip then M.setNoClip(true) end
        M.applyWalkSpeed()
    end
    function M.onPause()
        M.setNoClip(false)
        local keep = Config.WalkSpeedOverride
        Config.WalkSpeedOverride = 0
        M.applyWalkSpeed()
        Config.WalkSpeedOverride = keep
    end
    function M.cleanup()
        M.onPause()
        M.setAntiAFK(false)
        local keep = Config.FPSCap
        Config.FPSCap = 0
        M.applyFPS()
        Config.FPSCap = keep
    end

    -- Two clicks within 4 s are required so a stray click never leaves the server.
    function M.confirmed(action)
        local t = now()
        if t - (saved.confirmAt[action] or -100) <= 4 then
            saved.confirmAt[action] = nil
            return true
        end
        saved.confirmAt[action] = t
        log("Press " .. action .. " again within 4 seconds to confirm", "SYSTEM")
        return false
    end
    function M.rejoin(newServer)
        local okService, teleport = pcall(function() return game:GetService("TeleportService") end)
        if not okService or not teleport then return false end
        if newServer then
            return pcall(function() teleport:Teleport(game.PlaceId, LocalPlayer) end)
        end
        return pcall(function() teleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
    end

    function M.memoryText()
        local okLua, kb = pcall(collectgarbage, "count")
        local okStats, mb = pcall(function() return game:GetService("Stats"):GetTotalMemoryUsageMb() end)
        return string.format("Script heap %s MB  |  client memory %s MB",
            okLua and string.format("%.1f", (tonumber(kb) or 0) / 1024) or "?",
            okStats and string.format("%.0f", tonumber(mb) or 0) or "?")
    end

    function M.report()
        return string.format("antiAFK=%s noclip=%s walk=%s fps=%s | %s", tostring(conns.idle ~= nil),
            tostring(conns.noclip ~= nil), tostring(Config.WalkSpeedOverride), tostring(Config.FPSCap), M.memoryText())
    end

    function M.buildUI(h, ui)
        local p = h.page("performance")
        h.section(p, "MULTI-ACCOUNT PERFORMANCE", "Lower CPU per Roblox window")
        h.toggle(p, "PerformanceMode", "Performance mode", "Doubles v5.2 module intervals; combine with Low-lag mode and 3D rendering off")
        h.choice(p, "FPS cap", "setfpscap when the executor supports it; restored on Stop",
            function() return ((tonumber(Config.FPSCap) or 0) > 0 and (tostring(Config.FPSCap) .. " FPS") or "Off") .. "  >" end,
            function()
                local opts, idx = {0, 15, 30, 60, 120}, 1
                for i, v in ipairs(opts) do if v == Config.FPSCap then idx = i break end end
                Config.FPSCap = opts[idx % #opts + 1]
                local ok, why = M.applyFPS()
                if not ok then log("FPS cap: " .. tostring(why), "WAIT") end
            end)
        ui.playerMemory = h.rowLabel(p, "Memory: not measured")
        h.section(p, "PLAYER", "Client-side character settings; restored on pause and Stop")
        h.toggle(p, "AntiAFK", "Anti-AFK", "Prevents the 20-minute idle kick while the hub is loaded")
        h.choice(p, "Walk speed", "0 keeps the game's own speed",
            function() return tostring(Config.WalkSpeedOverride) .. "  >" end,
            function()
                local opts, idx = {0, 24, 32, 50, 75}, 1
                for i, v in ipairs(opts) do if v == Config.WalkSpeedOverride then idx = i break end end
                Config.WalkSpeedOverride = opts[idx % #opts + 1]
                M.applyWalkSpeed()
            end)
        h.toggle(p, "NoClip", "Noclip while running", "Walk through walls; gates stay locked server-side")
        h.section(p, "SERVER", "Manual only: press twice to confirm")
        h.toolbar(p, {
            {"REJOIN SERVER", function() if M.confirmed("REJOIN SERVER") then M.rejoin(false) end end},
            {"NEW SERVER", function() if M.confirmed("NEW SERVER") then M.rejoin(true) end end},
        })
        h.note(p, "Rejoin/new server reloads Roblox: run the script again or use your executor's auto-execute folder. No server-list web requests are made.", 46)
    end
    function M.render(ui)
        if ui.activePage ~= "performance" or not ui.playerMemory then return end
        ui.playerMemory.Text = M.memoryText()
    end
    Modules.define(M)
end)()
