--!nocheck
-- Fake Tap Simulator REBORN client + server for running the WHOLE helper file in Lune.
-- Every value here is an invented fixture shaped after what the helper reads (it is not
-- game data). The fake server applies the rules the helper is built around: one tap per
-- 0.1s with a rising ClientSequence, hatching only within 10 studs of the egg with the
-- answer echoing Seq, and rebirth packs priced 1000 coins per rebirth. A green run proves
-- the helper keeps its own invariants against these fakes, NOT live game acceptance.
local R = require("./roblox_mock")
local luneTask = require("@lune/task")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local node = R.node
local Vector3, CFrame = R.Vector3, R.CFrame

local W = { calls = {}, files = {}, printed = {}, failures = {} }

local function vdelay(seconds, fn) luneTask.delay((seconds or 0) / R.SPEED, fn) end
function W.wait(virtualSeconds) luneTask.wait(virtualSeconds / R.SPEED) end

local function moduleScript(name, parent, value)
    local m = node("ModuleScript", name, parent)
    rawset(m, "__module", value)
    return m
end

function W.build(opts)
    opts = opts or {}
    local game = R.Instance.new("DataModel")
    game.Name = "Game"
    rawget(game, "__props").PlaceId = 72858262610964
    R.services = {}
    local function service(name)
        if R.services[name] then return R.services[name] end
        if name == "CoreGui" then R.recordError("CoreGui was accessed") end
        local s = node(name, name, game)
        R.services[name] = s
        return s
    end
    R.service = service
    local players = service("Players")
    local rs = service("ReplicatedStorage")
    local ws = service("Workspace")
    for _, n in ipairs({ "RunService", "HttpService", "UserInputService", "VirtualUser", "StarterGui", "CoreGui" }) do
        service(n)
    end
    R.errors = {}
    W.game = game

    local player = node("Player", "Tester", players, { UserId = 4242 })
    rawget(players, "__props").LocalPlayer = player
    local character = node("Model", "Tester", ws)
    local hrp = node("Part", "HumanoidRootPart", character)
    hrp.CFrame = CFrame.new(0, 5, 0)
    node("Humanoid", "Humanoid", character, { Health = 100 })
    rawget(player, "__props").Character = character
    W.hui = node("Folder", "HiddenUI", game)
    W.player, W.root = player, hrp

    -- Eggs: two on spawn, one on a locked island.
    local eggsFolder = node("Folder", "Eggs", ws)
    W.eggAt = {
        Basic = Vector3.new(6, -511, -1833),
        Spotted = Vector3.new(-5, -511, -1822),
        Sky = Vector3.new(-88, -48, -1904),
    }
    for name, at in pairs(W.eggAt) do
        local model = node("Model", name, eggsFolder)
        local part = node("Part", "Egg", model)
        part.CFrame = CFrame.new(at)
    end

    local save = {
        Currencies = { Coins = opts.coins or 0, Gems = opts.gems or 500 },
        Statistics = { Rebirths = 0 },
        Upgrades = { RebirthButtons = 1 }, -- 2 rebirth buttons unlocked
        Progression = { World = "Main", UnlockedIslands = {} },
        Eggs = { Unlocked = { Basic = true, Spotted = true, Sky = true } },
        Pets = { Owned = {}, Equipped = {}, StorageLimit = 50 },
        SkillTree = { Unlocked = {} },
        Quests = { q1 = { Completed = true, Claimed = false }, q2 = { Completed = false, Claimed = false } },
        TapChests = { chestA = true },
    }
    W.save = save
    local replica = { Data = save }

    -- Client modules the helper requires.
    local controllers = node("Folder", "Controllers", rs)
    local core = node("Folder", "Core", controllers)
    moduleScript("DataController", core, { GetReplica = function() return replica end })
    local sharedFolder = node("Folder", "Shared", rs)
    local function sharedModule(group, name, value)
        local folder = sharedFolder:FindFirstChild(group) or node("Folder", group, sharedFolder)
        moduleScript(name, folder, value)
    end
    sharedModule("Core", "GameConfig", { ManualTapInterval = 0.1 })
    sharedModule("Progression", "RebirthConfig", {
        GetAmountFromIndex = function(index) return 5 ^ (index - 1) end,
        GetPrice = function(amount) return amount * 1000 end,
    })
    sharedModule("Progression", "RebirthButtonConfig", {
        GetUnlockedCount = function(upgrades) return 1 + upgrades end,
        GetOptionCount = function(unlocked) return unlocked end,
        GetMaximumOptions = function() return 14 end,
    })
    sharedModule("Progression", "SkillTreeFormula", { HasAutoRebirth = function() return false end })
    sharedModule("Progression", "UpgradeConfig", { Order = { "ClickMultiplier", "CriticalChance" } })
    sharedModule("Progression", "SkillTreeConfig", {
        Clicking = { { Name = "ClickPower1", Children = { { Name = "Critical1" } } } },
    })
    sharedModule("Pets", "LaunchEggConfig", {
        Basic = { Price = 100, Island = "Spawn" },
        Spotted = { Price = 2500, Island = "Spawn" },
        Sky = { Price = 50, Island = "Sky" }, -- cheap but its island is locked
        Test = { Price = 1 },
    })

    -- Remotes (sleitnick Comm layout).
    local services = node("Folder", "RemoteServices", rs)
    local remotes = {}
    local function remote(svc, kind, name)
        local s = services:FindFirstChild(svc) or node("Folder", svc, services)
        local folder = s:FindFirstChild(kind) or node("Folder", kind, s)
        local r = node(kind == "RE" and "RemoteEvent" or "RemoteFunction", name, folder)
        remotes[svc .. "." .. name] = r
        return r
    end
    for _, spec in ipairs({
        { "TapService", "RE", "TapRequested" }, { "TapService", "RE", "TapResult" },
        { "AutoClickService", "RE", "AutoClickRequested" }, { "RebirthService", "RE", "RebirthRequested" },
        { "EggService", "RE", "EggHatchRequested" }, { "EggService", "RE", "EggHatchResult" },
        { "PetService", "RE", "PetActionRequested" }, { "UpgradeService", "RF", "Purchase" },
        { "SkillTreeService", "RF", "Unlock" }, { "QuestService", "RF", "ClaimQuest" },
        { "TapChestService", "RF", "Claim" }, { "OfflineRewardsService", "RF", "Claim" },
    }) do
        remote(spec[1], spec[2], spec[3])
    end
    W.remotes = remotes

    -- Fake server.
    W.server = { lastSeq = opts.serverSeq or 0, lastTap = -math.huge, accepted = 0, tooFast = 0, stale = 0,
        hatches = 0, tooFar = 0, badIndex = 0, rebirthTimes = {}, tapPower = opts.tapPower or 60 }
    local S = W.server
    local handlers = {}
    handlers["TapService.TapRequested"] = function(p)
        local now = R.vclock()
        if type(p) ~= "table" or type(p.ClientSequence) ~= "number" or p.ClientSequence <= S.lastSeq then
            S.stale += 1
            return
        end
        if now - S.lastTap < 0.1 then
            S.tooFast += 1
            return
        end
        S.lastSeq, S.lastTap = p.ClientSequence, now
        S.accepted += 1
        save.Currencies.Coins += S.tapPower
        vdelay(0.05, function() remotes["TapService.TapResult"].OnClientEvent:Fire({ ClientSequence = p.ClientSequence }) end)
    end
    handlers["RebirthService.RebirthRequested"] = function(p)
        table.insert(S.rebirthTimes, R.vclock())
        local unlocked = 1 + save.Upgrades.RebirthButtons
        if type(p) ~= "table" or type(p.Index) ~= "number" or p.Index < 1 or p.Index > unlocked then
            S.badIndex += 1
            return
        end
        local amount = 5 ^ (p.Index - 1)
        if save.Currencies.Coins >= amount * 1000 then
            save.Currencies.Coins -= amount * 1000
            save.Statistics.Rebirths += amount
        end
    end
    handlers["EggService.EggHatchRequested"] = function(p)
        local result = { Seq = p.Seq, Egg = p.Egg }
        local at = W.eggAt[p.Egg]
        local price = ({ Basic = 100, Spotted = 2500, Sky = 50 })[p.Egg]
        if not at or not price then
            result.Error = "UnknownEgg"
        elseif p.Egg == "Sky" and not save.Progression.UnlockedIslands.Sky then
            result.Error = "IslandLocked"
        elseif (W.root.Position - at).Magnitude > 10 then
            S.tooFar += 1
            result.Error = "TooFar"
        elseif save.Currencies.Coins < price * p.Count then
            result.Error = "NotEnoughCoins"
        else
            save.Currencies.Coins -= price * p.Count
            S.hatches += p.Count
            result.Success, result.Rolls = true, p.Count
        end
        vdelay(0.6, function() remotes["EggService.EggHatchResult"].OnClientEvent:Fire(result) end)
    end
    local levels = {}
    handlers["UpgradeService.Purchase"] = function(p)
        if save.Currencies.Gems < 10 then return { Success = false, Reason = "NotEnoughGems" } end
        save.Currencies.Gems -= 10
        levels[p.Name] = (levels[p.Name] or 0) + 1
        return { Success = true, Current = levels[p.Name] }
    end
    handlers["SkillTreeService.Unlock"] = function(p)
        if p.Name == "Critical1" and not save.SkillTree.Unlocked.ClickPower1 then
            return { Success = false, Reason = "SubtreeLocked" }
        end
        save.SkillTree.Unlocked[p.Name] = true
        return { Success = true }
    end
    handlers["QuestService.ClaimQuest"] = function(p)
        local q = save.Quests[p.Quest]
        if q and q.Completed then q.Claimed = true return { Success = true } end
        return { Success = false }
    end
    handlers["TapChestService.Claim"] = function(id)
        save.TapChests[id] = nil
        return true
    end

    local function record(kind, name, ...)
        local args = table.pack(...)
        table.insert(W.calls, { kind = kind, name = name, args = args, t = R.vclock() })
        local h = handlers[name]
        if h then return h(...) end
        return nil
    end
    R.invokeRemote = function(name, ...) return record("Invoke", name, ...) end
    R.fireRemote = function(name, ...) record("Fire", name, ...) end
    return W
end

function W.count(name)
    local n = 0
    for _, c in ipairs(W.calls) do if c.name == name then n += 1 end end
    return n
end

function W.callsOf(name)
    local list = {}
    for _, c in ipairs(W.calls) do if c.name == name then list[#list + 1] = c end end
    return list
end

-- Harness ---------------------------------------------------------------------------------

function W.check(cond, msg)
    if cond then print("ok   " .. msg) else table.insert(W.failures, msg) print("FAIL " .. msg) end
    return cond
end

function W.loadSource(path) W.source = fs.readFile(path) end

local function makeEnv(genv)
    local SPEED = R.SPEED
    local fakeTask = {
        spawn = function(f, ...) return luneTask.spawn(f, ...) end,
        defer = function(f, ...) return luneTask.defer(f, ...) end,
        delay = function(t, f, ...) return luneTask.delay((t or 0) / SPEED, f, ...) end,
        wait = function(t) t = t or 0.03 luneTask.wait(t / SPEED) return t end,
        cancel = function(th) return luneTask.cancel(th) end,
    }
    local fakeOs = table.clone(os)
    fakeOs.clock = R.vclock
    local printed = W.printed
    local env = {
        Vector3 = R.Vector3, Vector2 = R.Vector2, CFrame = R.CFrame, Color3 = R.Color3,
        UDim = R.UDim, UDim2 = R.UDim2, Enum = R.Enum, Instance = R.Instance,
        typeof = R.typeof, task = fakeTask, os = fakeOs,
        warn = function(...) table.insert(printed, "WARN " .. table.concat({ ... }, " ")) end,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
            table.insert(printed, table.concat(parts, " "))
        end,
        getgenv = function() return genv end,
        setthreadidentity = function() end,
        gethui = function() return W.hui end,
        isfile = function(p) return W.files[p] ~= nil end,
        readfile = function(p)
            if W.files[p] == nil then error("file not found: " .. tostring(p)) end
            return W.files[p]
        end,
        writefile = function(p, c) W.files[p] = c end,
        require = function(mod)
            if R.isInstance(mod) and rawget(mod, "__module") ~= nil then return rawget(mod, "__module") end
            error("require on a non-module: " .. tostring(mod), 2)
        end,
    }
    env.game = W.game
    env.workspace = R.services.Workspace
    return env
end

function W.runIn(genv, label)
    local ok, fn = pcall(luau.load, W.source, { debugName = "TapSim_Reborn", environment = makeEnv(genv) })
    W.check(ok, label .. ": source compiles in Luau (" .. tostring(ok or fn) .. ")")
    if not ok then return genv end
    local ran, err = pcall(fn)
    W.check(ran, label .. ": source runs to the end (" .. tostring(err) .. ")")
    return genv
end

function W.findButton(name)
    for _, d in ipairs(W.hui:GetDescendants()) do
        if d.Name == name then return d end
    end
    return nil
end

function W.click(name)
    local b = W.findButton(name)
    W.check(b ~= nil, "button " .. name .. " exists")
    if b then b.MouseButton1Click:Fire() end
end

function W.guis()
    local n = 0
    for _, d in ipairs(W.hui:GetChildren()) do if d.Name == "TapSimRebornGui" then n += 1 end end
    return n
end

local ERROR_PATTERNS = { "attempt to", "invalid argument", "stack overflow", "Color3 expected",
    "require on a non-module", "loop error", "is missing" }
function W.scanErrors(label)
    local bad = {}
    for _, line in ipairs(W.printed) do
        for _, p in ipairs(ERROR_PATTERNS) do
            if string.find(line, p, 1, true) then table.insert(bad, line) break end
        end
    end
    for _, e in ipairs(R.errors) do table.insert(bad, "signal: " .. tostring(e)) end
    for i = 1, math.min(#bad, 8) do print("   " .. bad[i]) end
    W.check(#bad == 0, label .. ": no Lua runtime errors in console (" .. #bad .. ")")
end

function W.finish()
    print(string.format("\n%d checks failed; %d console lines", #W.failures, #W.printed))
    if #W.failures > 0 then
        for i = math.max(1, #W.printed - 25), #W.printed do print("   console: " .. tostring(W.printed[i])) end
    end
    return #W.failures == 0
end

return W
