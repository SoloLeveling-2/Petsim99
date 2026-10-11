-- RankPilot X v5.2 module framework.
-- Runs inside the main chunk, after getReport(), so every engine helper above
-- (Config, state, network, saveData, callMethod, movement lease, log, ...) is
-- in scope. Everything lives in the Modules table: no new main-chunk locals.
--
-- Contract for a module (all fields optional except id):
--   id, title, page              identity and the UI page its controls go on
--   defaults = {Key = value}     merged into Config before saved settings load
--   features = {{key=, name=, status=, evidence=}}  status chips + matrix rows
--   interval = seconds           cadence of tick() inside the shared worker
--   active = function() -> bool  cheap gate; tick() is skipped when false
--   runWhilePaused = bool        tick even when the controller is paused
--   tick, buildUI(h, ui), render(ui), report(), onSetting(field, value),
--   onStart(), onPause(reason), cleanup(reason), recheck(), capability()
(function()
    local STATUS_COLORS = {
        VERIFIED = Color3.fromRGB(94, 219, 164),
        UNVERIFIED = Color3.fromRGB(240, 196, 92),
        EXPERIMENTAL = Color3.fromRGB(245, 146, 76),
        UNAVAILABLE = Color3.fromRGB(238, 110, 128),
        PLANNED = Color3.fromRGB(162, 166, 188),
    }
    Modules.STATUS_COLORS = STATUS_COLORS
    -- Live status of v5.1 engine toggles. VERIFIED means a live report from an
    -- earlier build (v4.4 or older) showed game-credited results; nothing after
    -- v4.4 has been live tested, so re-check these after updating.
    Modules.coreStatus = {
        AutoRank = "VERIFIED", AutoFarm = "VERIFIED", AutoHatch = "VERIFIED",
        AutoLoadBestArea = "VERIFIED", AutoUpgradeCollections = "VERIFIED",
        AutoRainbowConversion = "VERIFIED", AutoGoldForRainbow = "VERIFIED",
        AutoHatchForRainbow = "VERIFIED", AutoConsumables = "VERIFIED",
        HidePetVisuals = "VERIFIED", HidePickupPopups = "VERIFIED",
        AutoParallelQuests = "UNVERIFIED", FastFarm = "UNVERIFIED", HatchFirstMode = "UNVERIFIED",
        PreferHighStars = "UNVERIFIED", DeferMiniChestQuests = "UNVERIFIED",
        AutoClaimRankRewards = "UNVERIFIED", AutoWorld = "UNVERIFIED",
        AutoGoldConversion = "UNVERIFIED", AutoHatchForGold = "UNVERIFIED",
        SkipEggAnimations = "UNVERIFIED", AutoEquipBest = "UNVERIFIED",
        AutoCollectOrbs = "UNVERIFIED", AutoCollectLootbags = "UNVERIFIED",
        AutoEventItems = "UNVERIFIED", PotionBatchUse = "UNVERIFIED",
        DiamondZoneRotation = "UNVERIFIED", AdaptiveFarmPriority = "UNVERIFIED",
        VYPersistentPetBulk = "UNVERIFIED", VYMultiTargetSpread = "UNVERIFIED",
        VYInstantEvents = "UNVERIFIED", SuperMagnet = "UNVERIFIED", PetTurbo = "UNVERIFIED",
        AutoFreeGifts = "UNVERIFIED", AutoLoginStreak = "UNVERIFIED",
        AutoTimedRewards = "UNVERIFIED", AutoPlayerUpgrades = "UNVERIFIED",
        AutoPopBalloons = "UNVERIFIED", AutoEggSlots = "UNVERIFIED", AutoPetSlots = "UNVERIFIED",
        AutoVending = "UNVERIFIED", AutoRebirth = "UNVERIFIED", LocalNotifications = "UNVERIFIED",
        RenderOff = "UNVERIFIED", LowLagMode = "UNVERIFIED", Fullbright = "UNVERIFIED",
        HideBalloonVisuals = "UNVERIFIED", HideBreakableVisuals = "UNVERIFIED",
        SpreadPets = "UNVERIFIED", AutoHatchAlways = "UNVERIFIED",
        InfinitePetSpeed = "EXPERIMENTAL", HideLootbagVisuals = "EXPERIMENTAL",
        HideYellowBagFX = "EXPERIMENTAL", AutoZoneTeleports = "EXPERIMENTAL",
        VYWorldTravel = "EXPERIMENTAL", HatchFarmRemoteProbe = "EXPERIMENTAL",
    }
    Modules.featureIndex = {}

    local function moduleState(id)
        local bucket = state.modules[id]
        if not bucket then
            bucket = {last = "not checked", stats = {}, nextAt = 0, available = nil, reason = nil}
            state.modules[id] = bucket
        end
        return bucket
    end
    Modules.state = moduleState

    function Modules.define(spec)
        assert(type(spec) == "table" and type(spec.id) == "string", "module needs an id")
        if Modules.byId[spec.id] then return Modules.byId[spec.id] end
        for key, value in pairs(spec.defaults or {}) do
            if Config[key] == nil then Config[key] = value end
        end
        for _, feature in ipairs(spec.features or {}) do
            feature.module = spec.id
            if feature.key then Modules.featureIndex[feature.key] = feature end
        end
        spec.interval = tonumber(spec.interval) or 3
        moduleState(spec.id)
        table.insert(Modules.list, spec)
        Modules.byId[spec.id] = spec
        return spec
    end

    -- Attempted / accepted / confirmed counters. "accepted" means the game
    -- remote returned without error; only "confirmed" means game state changed.
    function Modules.stat(id, key)
        local bucket = moduleState(id)
        local row = bucket.stats[key]
        if not row then
            row = {attempted = 0, accepted = 0, confirmed = 0, failed = 0, last = "not attempted"}
            bucket.stats[key] = row
        end
        return row
    end
    function Modules.note(id, key, outcome, message)
        local row = Modules.stat(id, key)
        if outcome == "attempted" then row.attempted = row.attempted + 1
        elseif outcome == "accepted" then row.accepted = row.accepted + 1
        elseif outcome == "confirmed" then row.confirmed = row.confirmed + 1
        elseif outcome == "failed" then row.failed = row.failed + 1 end
        if message then
            row.last = tostring(message)
            moduleState(id).last = tostring(message)
        end
        row.lastAt = now()
        return row
    end

    -- Rate-limited remote call that keeps the raw result. Returns
    -- (accepted, result); accepted=false on cooldown, missing remote or a
    -- false/nil-error response. Callers must still verify game state.
    function Modules.call(id, key, remote, args, invoke, interval)
        if not cooldownReady("mod-remote:" .. remote, interval or 3) then return false, "cooldown" end
        Modules.note(id, key, "attempted")
        local ok, result = network(remote, args or {}, invoke)
        if not ok then
            Modules.note(id, key, "failed", remote .. " failed: " .. describe(result))
            failFeature("mod:" .. id, result)
            return false, result
        end
        state.commandCount = state.commandCount + 1
        if result == false then
            Modules.note(id, key, "failed", remote .. " refused")
            return false, result
        end
        Modules.note(id, key, "accepted")
        return true, result
    end

    -- Client module lookup by name. state.clients is the game's own
    -- Library.Client table, so lookups are cached in a private table instead
    -- of writing into it; refreshClients() (RECHECK) swaps state.clients and
    -- that invalidates the cache.
    local clientCache = {owner = nil, found = {}}
    function Modules.client(name)
        local c = state.clients
        if type(c) ~= "table" then return nil end
        if clientCache.owner ~= c then clientCache.owner, clientCache.found = c, {} end
        local cached = clientCache.found[name]
        if type(cached) == "table" then return cached end
        if type(cached) == "number" and now() < cached then return nil end
        local okIndex, direct = pcall(function() return c[name] end)
        local found = (okIndex and type(direct) == "table") and direct or nil
        if not found then
            local library = findChild(ReplicatedStorage, "Library")
            found = tryModule(findChild(findChild(library, "Client"), name))
        end
        -- Missing modules are retried after 60 s (some load late).
        clientCache.found[name] = found or (now() + 60)
        return found
    end
    function Modules.directory(name)
        local dir = state.clients and state.clients.Directory
        local section = type(dir) == "table" and dir[name] or nil
        return type(section) == "table" and section or nil
    end
    function Modules.inventory(class, force)
        local data = saveData(force)
        local inv = type(data) == "table" and data.Inventory or nil
        local rows = type(inv) == "table" and inv[class] or nil
        return type(rows) == "table" and rows or nil, data
    end
    -- Sum of _am for every stack of `class` whose id matches `id`.
    function Modules.countItem(class, id, force)
        local rows = Modules.inventory(class, force)
        local total = 0
        for _, row in pairs(rows or {}) do
            if type(row) == "table" and row.id == id then
                total = total + math.max(0, tonumber(row._am) or 1)
            end
        end
        return total
    end

    -- Valuable or user-protected pets are never consumed, mailed or listed.
    function Modules.isProtectedPet(uid, row)
        if type(row) ~= "table" then return true end
        local protectedList = Config.ProtectedPetUids
        if type(protectedList) == "table" then
            for _, protectedUid in ipairs(protectedList) do
                if protectedUid == uid then return true end
            end
        end
        if row._lk == true or row.lk == true then return true end
        if row.sh == true then return true end
        local pets = Modules.directory("Pets")
        local info = pets and row.id and pets[row.id]
        if type(info) ~= "table" then return true end
        if info.huge or info.titanic or info.exclusiveLevel or info.gargantuan then return true end
        return false
    end

    -- Movement for modules: one shared lease, never during a hatch window.
    -- fn(root) runs while the lease is held; the original CFrame is restored
    -- when restore=true.
    function Modules.withMovement(owner, seconds, restore, fn)
        if not movementAvailable(owner) or inHatchMovementWindow() then return false, "movement busy" end
        local root = currentRoot()
        if not root then return false, "character not loaded" end
        leaseMovement(owner, seconds)
        local original = root.CFrame
        local ok, result = pcall(fn, root)
        if restore and root.Parent then pcall(function() root.CFrame = original end) end
        clearMovement(owner)
        if not ok then return false, result end
        return result ~= false, result
    end

    function Modules.statusFor(key)
        local feature = Modules.featureIndex[key]
        local status = feature and feature.status or Modules.coreStatus[key]
        if not status then return nil end
        if feature and feature.module then
            local bucket = state.modules[feature.module]
            if bucket and bucket.available == false and status ~= "PLANNED" then status = "UNAVAILABLE" end
        end
        return status, STATUS_COLORS[status]
    end

    local function probe(m)
        local bucket = moduleState(m.id)
        if type(m.capability) ~= "function" then
            bucket.available, bucket.reason = true, nil
            return true
        end
        local ok, available, reason = pcall(m.capability)
        bucket.available = ok and available == true
        bucket.reason = (not ok and tostring(available)) or reason
        return bucket.available
    end

    local function each(method, ...)
        for _, m in ipairs(Modules.list) do
            if type(m[method]) == "function" then
                local ok, err = pcall(m[method], ...)
                if not ok and cooldownReady("module:" .. m.id .. ":" .. method, 30) then
                    log("Module " .. m.id .. "." .. method .. " failed: " .. describe(err), "ERROR")
                end
            end
        end
    end
    function Modules.startAll() each("onStart") end
    function Modules.pauseAll(reason)
        each("onPause", reason)
        for _, m in ipairs(Modules.list) do clearMovement("mod:" .. m.id) end
    end
    function Modules.cleanupAll(reason)
        if Modules.cleaned then return end
        Modules.cleaned = true
        each("cleanup", reason)
        for _, m in ipairs(Modules.list) do clearMovement("mod:" .. m.id) end
    end
    function Modules.recheckAll()
        for _, m in ipairs(Modules.list) do
            state.failures["mod:" .. m.id] = nil
            probe(m)
        end
        each("recheck")
    end
    function Modules.onSetting(field, value) each("onSetting", field, value) end
    function Modules.render(ui)
        if not ui or not ui.window or not ui.window.Visible then return end
        each("render", ui)
    end

    -- One shared worker for every module. Intervals stretch in performance
    -- mode, unhealthy modules back off through failFeature/healthy, and the
    -- loop sleeps for the shortest pending interval instead of spinning.
    function Modules.worker(generation)
        for _, m in ipairs(Modules.list) do probe(m) end
        while not state.shutdown and generation == state.generations do
            local stretch = Config.PerformanceMode and 2 or 1
            local soonest = now() + 5
            for _, m in ipairs(Modules.list) do
                if state.shutdown or generation ~= state.generations then break end
                local bucket = moduleState(m.id)
                local due = now() >= (bucket.nextAt or 0)
                if due and type(m.tick) == "function" and (state.running or m.runWhilePaused) then
                    bucket.nextAt = now() + m.interval * stretch
                    local wanted = true
                    if type(m.active) == "function" then
                        local okActive, isActive = pcall(m.active)
                        wanted = okActive and isActive == true
                    end
                    if wanted and bucket.available ~= false and healthy("mod:" .. m.id) then
                        local started = os.clock()
                        local ok, err = pcall(m.tick)
                        -- Exponential average of tick CPU time, shown in Diagnostics.
                        bucket.costMs = (bucket.costMs or 0) * 0.8 + (os.clock() - started) * 1000 * 0.2
                        if not ok then
                            clearMovement("mod:" .. m.id)
                            failFeature("mod:" .. m.id, err)
                            bucket.last = "error: " .. describe(err)
                        end
                    end
                end
                if (bucket.nextAt or 0) < soonest then soonest = bucket.nextAt end
            end
            task.wait(math.clamp(soonest - now(), Config.PerformanceMode and 1 or 0.5, 5))
        end
        Modules.cleanupAll("worker exit")
    end

    function Modules.reportLines()
        local lines = {}
        for _, m in ipairs(Modules.list) do
            local bucket = moduleState(m.id)
            local text = string.format("MODULE %s (%.1f ms/tick): %s", m.id, bucket.costMs or 0, tostring(bucket.last))
            if bucket.available == false then text = text .. " | UNAVAILABLE " .. tostring(bucket.reason) end
            if type(m.report) == "function" then
                local ok, res = pcall(m.report)
                text = text .. " | " .. (ok and tostring(res) or ("report error " .. tostring(res)))
            end
            table.insert(lines, text)
            for key, row in pairs(bucket.stats) do
                table.insert(lines, string.format("  %s.%s attempted=%d accepted=%d confirmed=%d failed=%d last=%s",
                    m.id, key, row.attempted, row.accepted, row.confirmed, row.failed, tostring(row.last)))
            end
        end
        return lines
    end

    -- UI: modules add their own controls, then the framework adds a module
    -- health table to Diagnostics so attempted/confirmed counts are visible.
    function Modules.buildUI(ui, h)
        for _, m in ipairs(Modules.list) do
            if type(m.buildUI) == "function" then
                local ok, err = pcall(m.buildUI, h, ui)
                if not ok then log("UI for module " .. m.id .. " failed: " .. describe(err), "ERROR") end
            end
        end
        local diag = h.page("diagnostics")
        h.section(diag, "MODULE HEALTH", "Attempted vs game-confirmed results per v5.2 module")
        ui.moduleRows = {}
        for _, m in ipairs(Modules.list) do
            if type(m.tick) == "function" or m.features then
                ui.moduleRows[m.id] = h.rowLabel(diag, m.id .. ": not checked")
            end
        end
    end
    Modules.define({
        id = "framework",
        render = function(ui)
            if ui.activePage ~= "diagnostics" or not ui.moduleRows then return end
            for id, row in pairs(ui.moduleRows) do
                local bucket = moduleState(id)
                local attempted, confirmed = 0, 0
                for _, stat in pairs(bucket.stats) do
                    attempted = attempted + stat.attempted
                    confirmed = confirmed + stat.confirmed
                end
                local status = bucket.available == false and ("UNAVAILABLE: " .. tostring(bucket.reason)) or tostring(bucket.last)
                row.Text = string.format("%s  |  attempted %d  confirmed %d  |  %.1f ms/tick  |  %s",
                    id, attempted, confirmed, bucket.costMs or 0, status)
            end
        end,
    })
end)()
