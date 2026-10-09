--!nocheck
--[[
 RankPilot / PS99 rank-focused, single-account Luau hub
 DZ-informed research build: 2026-10-09
 Repositories researched: firedvl/pet-simulator-99,
   pipipipipia23/aahsdasd-, CHICHazHUB/PSXfarm,
   ps99scripts/autoWorld, waktool/RankQuests and DZ Hub (uploaded PetSimulator99.lua).

 STATUS: Offline code review only. Live client compatibility is NOT verified.
 No external code loaded, no webhooks, no secret collection, no account-specific settings.
 Actions are feature-gated and failures are logged, not silently ignored.

 Local execution may violate Roblox/game rules. Use at your own discretion.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return warn("[RankPilot] LocalPlayer not available") end
print("[RankPilot] v2.10 loading...")

local environment = (type(getgenv) == "function" and getgenv()) or _G
if type(environment.RankPilot) == "table" and type(environment.RankPilot.Stop) == "function" then
    pcall(environment.RankPilot.Stop)
end

local Config = {
    Enabled = false,             -- Click START in the GUI after reviewing status
    AutoRank = true,
    AutoWorld = true,           -- Enables advancing unlocked-world progression
    AutoFarm = true,
    AutoHatch = true,
    AutoConsumables = true,
    AutoEventItems = true,      -- Spawn coin jars / comets / pinatas / lucky blocks for quests
    AutoVending = true,         -- Buy from potion/enchant vending machines for collect quests
    AutoUpgrade = true,         -- Upgrade low-tier potions/enchants at the upgrade machine
    MultiQuest = true,          -- Work on several compatible quests in the same tick
    UpgradeMinStack = 3,        -- Only upgrade a potion/enchant stack with at least this many copies
    UpgradeSeconds = 2.5,
    VendingSpendFraction = 0.20, -- Max share of current coins one vending purchase may cost
    SettingsVersion = 4,
    AutoClaimRankRewards = true,
    AutoRebirth = false,        -- Intentional opt-in only
    AutoEggSlots = false,       -- Opt-in: check available diamonds and verified bundle price
    AutoPetSlots = false,       -- Opt-in: check rank cap and verified diamond price
    AutoEquipBest = true,       -- From DZ Hub PetCmds.EquipBest
    AutoFreeGifts = false,      -- Opt-in: verified free-gift timestamps, no blind claiming
    RenderOff = false,
    FastMode = true,            -- Shorter tick / farm / pet-assign intervals
    InstantPets = true,         -- Bulk-join pets straight onto breakables (skips walking)
    SuperMagnet = true,         -- Collect every loaded orb and lootbag
    StayInBestArea = true,      -- Keep the player (and so the pets) in the best owned area
    AntiAFK = true,             -- Prevent the 20-minute idle kick
    AutoTap = true,             -- Tap the nearest breakable continuously
    TapSeconds = 0.1,
    AutoUltimate = true,        -- Fire the equipped ultimate whenever it is charged
    UltimateSeconds = 3,
    SkipEggAnimation = true,    -- Patch out the egg-opening animation / auto-click "Click to open"
    SmartHatchSettings = true,  -- Charged / Golden eggs OFF unless a quest needs them
    ChargedForRareQuests = true, -- Charged (lucky, 20x cost) ON for "hatch legendary/rare pets" quests
    GoldenEggsForGoldQuests = true, -- Golden eggs (50x cost) ON for gold/rainbow quests only if the Gold Machine cannot be used
    AutoGoldRainbow = true,     -- Gold / Rainbow machine for "make golden/rainbow pets" quests
    TargetsPerTick = 6,         -- Breakables damaged / pets spread across per farm pass
    FastTickSeconds = 0.25,
    FastFarmSeconds = 0.1,
    FastPetAssignSeconds = 0.3,
    MagnetSeconds = 0.3,
    FarmRadius = 65,
    MaxCandidatesPerPass = 100,
    ScanLimit = 140,
    MaxPetsPerTick = 12,
    TickSeconds = 1.2,
    QuestCooldown = 12,
    SaveRefreshSeconds = 1.5,
    WorldCheckSeconds = 18,
    RewardCheckSeconds = 22,
    FarmActionSeconds = 0.45,
    PetAssignSeconds = 1.5,
    EquipCheckSeconds = 18,
    SlotCheckSeconds = 28,
    GiftCheckSeconds = 65,
    HatchActionSeconds = 3.5,
    FastHatchSeconds = 1.2,
    TripSettleSeconds = 0.3,   -- Wait after teleporting before acting, so the server sees the new position
    ConsumableSeconds = 6,
    SpawnItemSeconds = 14,
    StallSeconds = 150,
    BlockedQuestSeconds = 75,
    MaxErrorsPerFeature = 5,
    MaxHatchBatch = 100,        -- Upper bound when the game's own max-hatch value is unreadable
    TargetRank = 0,             -- 0 = no artificial stopping point; game cap may change
    PreferHighStars = true,
    RepositionDistance = 35,
    MaxSlotSpendFraction = 0.40, -- cap a purchase to 40% of current diamonds
}
local optionOrder = {
    {"AutoRank", "Rank quest planner"}, {"AutoWorld", "Advance areas"},
    {"AutoFarm", "Farm breakables"}, {"AutoHatch", "Hatch rank quests"},
    {"AutoConsumables", "Fruit / potion / flags"},
    {"AutoEventItems", "Spawn jars / comets"},
    {"AutoVending", "Vending for collection quests"},
    {"AutoUpgrade", "Upgrade potions / enchants"},
    {"MultiQuest", "Do multiple quests at once"},
    {"AutoClaimRankRewards", "Claim rank rewards"},
    {"AutoRebirth", "Allow rebirth"},
    {"AutoEquipBest", "Keep best pets equipped"},
    {"AutoEggSlots", "Buy affordable egg slots"},
    {"AutoPetSlots", "Buy affordable pet slots"},
    {"AutoFreeGifts", "Claim ready free gifts"},
    {"FastMode", "Fast mode (shorter delays)"},
    {"InstantPets", "Instant pets (bulk join breakables)"},
    {"SuperMagnet", "Super magnet (orbs + lootbags)"},
    {"StayInBestArea", "Stay in best area"},
    {"AntiAFK", "Anti-AFK"},
    {"AutoTap", "Auto tap"},
    {"AutoUltimate", "Auto ultimate"},
    {"SkipEggAnimation", "Skip egg animation"},
    {"SmartHatchSettings", "Charged/Golden eggs only for quests"},
    {"ChargedForRareQuests", "Charged eggs for legendary quests"},
    {"GoldenEggsForGoldQuests", "Golden eggs if gold machine fails"},
    {"AutoGoldRainbow", "Gold / rainbow machine quests"},
    {"RenderOff", "Disable 3D rendering"},
}

local state = {
    running = false, shutdown = false, status = "Preparing", rank = "?",
    maxRank = "?", area = "?", chosen = "None", starCount = "?",
    goals = {}, logs = {}, tasks = {}, failures = {}, blocked = {}, cooldowns = {},
    questWatch = {},
    clients = {}, lastGoalFingerprint = "", lastRank = nil,
    lastProgressAt = os.clock(), lastSuccessfulAction = os.clock(),
    lastWorldCheck = 0, lastRewardCheck = 0, lastRefresh = 0,
    lastFarm = 0, lastHatch = 0, lastConsumable = 0, lastEventItem = 0,
    lastPetAssign = 0, lastAssignedTarget = nil, lastEquip = 0, lastMagnet = 0,
    bulkUnsupported = false, upgradeSkip = {}, probing = {}, lastTargets = {}, lastTargetsAt = 0,
    hatchLo = 1, hatchHi = 0, hatchResetAt = 0, hatchFails = 0, machineSpots = {}, eggCost = {}, farmHome = nil, hatchOptionTries = {}, hatchOptionPausedUntil = {}, activeGoals = {},
    hatchOptionSetByUs = {}, hatchOptionFiredAt = {}, wantOption = {}, hatchCap = {},
    convertSkip = {}, convertFailStreak = 0, spendWatch = {},
    lastSlots = 0, lastGifts = 0, lastFarmInterface = "none",
    attempts = {farm = 0, hatch = 0, zone = 0, consumable = 0},
    lastPosition = nil, generations = 0, connections = {}, gui = nil,
    configFile = "RankPilot_v1_settings.json", settingsLoaded = false,
    activeWorld = nil, currentTarget = nil, selectedGoalKey = nil, scanCursor = 1,
    commandCount = 0, blockedCount = 0,
}

local function now() return os.clock() end
local function describe(value)
    if type(value) == "string" then return value end
    local success, result = pcall(tostring, value)
    return success and result or "<unknown>"
end
local function log(text, category)
    local message = string.format("[%s] %s", category or "INFO", describe(text))
    table.insert(state.logs, 1, message)
    if #state.logs > 55 then table.remove(state.logs, #state.logs) end
    print("[RankPilot] " .. message)
end
local function cooldownReady(key, seconds)
    if now() < (state.cooldowns[key] or 0) then return false end
    state.cooldowns[key] = now() + seconds
    return true
end
local function failFeature(feature, err)
    local record = state.failures[feature] or {count = 0, last = 0, disabled = false}
    if now() - record.last > 100 then record.count = 0 end
    record.last = now()
    record.count = record.count + 1
    if record.count <= 2 or record.count == Config.MaxErrorsPerFeature then
        log(feature .. ": " .. describe(err), "ERROR")
    end
    if record.count >= Config.MaxErrorsPerFeature then
        record.disabled = true
        log(feature .. " disabled after repeated errors. Use RECHECK to retry.", "SAFEGUARD")
    end
    state.failures[feature] = record
end
local function healthy(feature)
    local row = state.failures[feature]
    return not (row and row.disabled)
end
local function findChild(parent, name)
    return parent and parent:FindFirstChild(name)
end
local function callMethod(tbl, name, ...)
    if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then
        return false, "missing " .. name
    end
    return pcall(tbl[name], ...)
end
local function currentRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function tryModule(node)
    if not node or not node:IsA("ModuleScript") then return nil end
    local ok, obj = pcall(require, node)
    if ok and type(obj) == "table" then return obj end
    return nil
end

local function refreshClients()
    local lib = findChild(ReplicatedStorage, "Library")
    local clientFolder = findChild(lib, "Client")
    local c = (clientFolder and tryModule(clientFolder)) or {}
    if type(c) ~= "table" then c = {} end
    for _,name in ipairs({"Save", "QuestCmds", "ZoneCmds", "RankCmds", "PetCmds", "EggCmds",
        "FruitCmds", "PotionCmds", "ZoneFlagCmds", "InventoryCmds", "RebirthCmds",
        "MapCmds", "CurrencyCmds", "MachineCmds", "PlayerPet", "BreakableFrontend", "UltimateCmds",
        "HatchingCmds", "MasteryCmds"}) do
        if not c[name] then c[name] = tryModule(findChild(clientFolder, name)) end
    end
    c.Network = c.Network or tryModule(findChild(clientFolder, "Network"))
    c.ZonesUtil = tryModule(findChild(findChild(lib, "Util"), "ZonesUtil"))
    c.RanksUtil = tryModule(findChild(findChild(lib, "Util"), "RanksUtil"))
    c.Directory = tryModule(findChild(lib, "Directory"))
    c.Balancing = tryModule(findChild(lib, "Balancing"))
    c.HatchingTypes = tryModule(findChild(findChild(lib, "Types"), "Hatching"))
    state.clients = c
    state.activeWorld = findChild(Workspace, "Map") or findChild(Workspace, "Map2") or findChild(Workspace, "Map3")
    return type(c.Save) == "table" and type(c.Save.Get) == "function"
end
local saveCache, saveCacheAt = nil, -math.huge
local function saveData()
    -- Short cache: the planner reads the save many times per tick.
    if saveCache and now() - saveCacheAt < 0.25 then return saveCache end
    local result = state.clients.Save
    local ok, data = callMethod(result, "Get")
    if ok and type(data) == "table" then
        saveCache, saveCacheAt = data, now()
        return data
    end
    return nil
end
-- Fallback for the on-screen info when the Save module cannot be read.
local function leaderstat(...)
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    if not stats then return nil end
    for _, name in ipairs({...}) do
        for _, child in ipairs(stats:GetChildren()) do
            if child.Name:lower():find(name, 1, true) then
                local value = child:IsA("ValueBase") and child.Value or nil
                local n = tonumber(value) or (type(value) == "string" and tonumber(value:match("%d+")))
                if n then return n end
                if value ~= nil then return value end
            end
        end
    end
    return nil
end
local function network(name, args, invoke)
    args = args or {}
    local container = findChild(ReplicatedStorage, "Network")
    local remote = findChild(container, name)
    if remote and invoke and remote:IsA("RemoteFunction") then
        return pcall(function() return remote:InvokeServer(unpack(args)) end)
    elseif remote and not invoke and remote:IsA("BaseRemoteEvent") then
        return pcall(function() remote:FireServer(unpack(args)); return true end)
    end
    local c = state.clients.Network
    if c then
        local method = invoke and "Invoke" or "Fire"
        if type(c[method]) == "function" then
            return pcall(c[method], name, unpack(args))
        end
    end
    return false, "remote missing or wrong type: " .. name
end
local function attemptNetwork(feature, name, args, invoke, interval)
    if not cooldownReady("remote:" .. name, interval or 3) then return false end
    local success, result = network(name, args, invoke)
    if not success then
        failFeature(feature, result)
        return false
    end
    state.commandCount = state.commandCount + 1
    return result ~= false
end

-- Some remotes' argument formats differ between game versions and their return
-- values are unreliable. probeRemote tries each argument shape in the background
-- and checks the save data to see whether it actually worked; the shape that
-- worked is remembered for next time.
-- Quick trip: teleport to a spot, run fn there, then return to where the
-- character was. Farming in the best area carries on between trips, so hatching,
-- vending and upgrading no longer pull the character away for long.
-- Must be called from a spawned thread (it waits).
local function quickTrip(cframe, fn)
    local root = currentRoot()
    if not root then return false, "character not ready" end
    local waited = 0
    while state.tripActive and waited < 8 do
        task.wait(0.2)
        waited = waited + 0.2
    end
    if state.tripActive then return false, "busy" end
    if state.shutdown or not state.running then return false, "stopped" end
    root = currentRoot()
    if not root then return false, "character not ready" end
    state.tripActive = true
    local home = root.CFrame
    local far = typeof(cframe) == "CFrame" and (root.Position - cframe.Position).Magnitude > 15
    if far then
        root.CFrame = cframe
        task.wait(Config.TripSettleSeconds)
    end
    local results
    if state.shutdown or not state.running then
        results = table.pack(true, false, "stopped")
    else
        results = table.pack(pcall(fn))
    end
    if far then
        local back = currentRoot()
        if back then back.CFrame = home end
    end
    state.tripActive = false
    if not results[1] then return false, results[2] end
    return table.unpack(results, 2, results.n)
end
local probeMemory = {}
local function probeRemote(key, remote, shapes, verify, onDone, tripTo)
    if state.probing[key] then return false end
    state.probing[key] = true
    task.spawn(function()
      local function runProbe()
        local order, known = {}, probeMemory[remote.Name]
        if known and shapes[known] then order[1] = known end
        for i = 1, #shapes do if i ~= known then order[#order+1] = i end end
        local worked, lastResult = false, nil
        for _, index in ipairs(order) do
            local args = shapes[index]
            local ok, result = pcall(function()
                if remote:IsA("RemoteFunction") then return remote:InvokeServer(unpack(args)) end
                remote:FireServer(unpack(args))
                return true
            end)
            state.commandCount = state.commandCount + 1
            lastResult = ok and result or ("error: " .. describe(result))
            task.wait(0.9)
            local okVerify, verified = pcall(verify)
            if ok and okVerify and verified then
                probeMemory[remote.Name] = index
                worked = true
                break
            end
            if state.shutdown or not state.running then break end
        end
        return worked, lastResult
      end
        local worked, lastResult
        if tripTo then worked, lastResult = quickTrip(tripTo, runProbe) else worked, lastResult = runProbe() end
        state.probing[key] = nil
        pcall(onDone, worked, lastResult)
    end)
    return true
end
local function loadSettings()
    if not (type(isfile) == "function" and type(readfile) == "function") then return end
    local ok, data = pcall(function()
        if not isfile(state.configFile) then return nil end
        return HttpService:JSONDecode(readfile(state.configFile))
    end)
    if ok and type(data) == "table" then
        -- Defaults that changed in settings v4 are not overridden by older saved files.
        if (tonumber(data.SettingsVersion) or 0) < 4 then
            data.AutoEventItems, data.AutoVending, data.AutoUpgrade = nil, nil, nil
        end
        data.SettingsVersion = nil
        -- Only on/off toggles are restored. Numbers such as MaxHatchBatch always
        -- come from this file, so an old saved value cannot hold a new version back.
        for key, value in pairs(data) do
            if type(Config[key]) == "boolean" and type(value) == "boolean" then
                Config[key] = value
            end
        end
        log("Preferences loaded")
    end
    -- Start disabled even when saved; a previous running session must not silently restart.
    Config.Enabled = false
end
local function persist()
    if type(writefile) ~= "function" then return end
    pcall(function()
        local copy = {SettingsVersion = Config.SettingsVersion}
        for k, v in pairs(Config) do
            if type(v) == "boolean" then copy[k] = v end
        end
        copy.Enabled = false
        writefile(state.configFile, HttpService:JSONEncode(copy))
    end)
end

local function getMaxRank()
    local c = state.clients.RankCmds
    local ok, result = callMethod(c, "GetMaxRank")
    if ok and type(result) == "number" and result >= 1 then return math.floor(result) end
    return nil
end
local function mapRoots()
    local roots = {}
    for _, name in ipairs({"Map", "Map2", "Map3"}) do
        local root = findChild(Workspace, name)
        if root then table.insert(roots, root) end
    end
    return roots
end
local function getZoneInfo()
    local c = state.clients.ZoneCmds
    local ok, name, details = callMethod(c, "GetMaxOwnedZone")
    if not ok then return nil end
    if type(name) == "table" then
        details = name
        name = name.ZoneName or name.Name
    end
    if type(name) ~= "string" or name == "" then return nil end
    local number = type(details) == "table" and tonumber(details.ZoneNumber) or nil
    local dir = state.clients.Directory
    local zoneData = dir and dir.Zones and dir.Zones[name]
    if not number and type(zoneData) == "table" then number = tonumber(zoneData.ZoneNumber) end
    return {name = name, number = number}
end
local function matchZoneFolder(zone)
    if not zone then return nil end
    for _,root in ipairs(mapRoots()) do
        if root then
            for _,folder in ipairs(root:GetChildren()) do
                local suffix = folder.Name:match("^%d+%s*|%s*(.*)$")
                if suffix == zone.name or folder.Name == zone.name then
                    return folder
                end
            end
        end
    end
    return nil
end
local function placeInZone(zone)
    if not zone or not zone.name then return false, "unknown owned zone" end
    local root = currentRoot()
    if not root then return false, "character not ready" end
    local util = state.clients.ZonesUtil
    if util then
        -- DZ Hub uses this client utility for the actual dotted farming area.
        local ok, zones = callMethod(util, "GetBreakableZones", zone.name)
        if ok and typeof(zones) == "Instance" then
            for _, part in ipairs(zones:GetChildren()) do
                if part:IsA("BasePart") then
                    local rel = part.CFrame:PointToObjectSpace(root.Position)
                    local inside = math.abs(rel.X) <= part.Size.X/2 + 2
                        and math.abs(rel.Z) <= part.Size.Z/2 + 2
                    if inside then return true end
                    if (root.Position-part.Position).Magnitude > Config.RepositionDistance then
                        root.CFrame = part.CFrame + Vector3.new(0, 5, 0)
                    end
                    return true
                end
            end
        end
        local okTP, cf = callMethod(util, "GetTeleportPartLocation", zone.name)
        if okTP and typeof(cf) == "CFrame" then
            if (root.Position-cf.Position).Magnitude > Config.RepositionDistance then
                root.CFrame=cf+Vector3.new(0,5,0)
            end
            return true
        end
    end
    -- Legacy map-folder fallback, used only when the game utility is unavailable.
    local folder = matchZoneFolder(zone)
    if not folder then return false, "zone folder not loaded" end
    local interact = folder:FindFirstChild("INTERACT")
    local part = interact and (interact:FindFirstChild("BREAKABLE_SPAWNS", true)
        or interact:FindFirstChild("BREAK_ZONE", true))
    if part and not part:IsA("BasePart") then
        part = part:FindFirstChildWhichIsA("BasePart", true)
    end
    if not part then
        local persistent = folder:FindFirstChild("PERSISTENT")
        part = persistent and persistent:FindFirstChild("Teleport", true)
    end
    if not part or not part:IsA("BasePart") then return false, "zone entry not loaded" end
    if (root.Position - part.Position).Magnitude > Config.RepositionDistance then
        root.CFrame = part.CFrame + Vector3.new(0, 4, 0)
    end
    return true
end
local function getGoalTitle(goal)
    local c = state.clients.QuestCmds
    local ok, title = callMethod(c, "MakeTitle", goal)
    if ok and type(title) == "string" and #title > 0 then return title end
    return type(goal) == "table" and (goal.Title or goal.Name or goal.id) or "Unknown goal"
end
local function classify(title)
    local v = string.lower(title)
    -- "Hatch a Legendary (or above) Pet", "Hatch 3 rare pets"
    if v:find("legendary") or v:find("mythical") or (v:find("rare") and v:find("pet")) then return "hatch_rare" end
    -- "Make 5 rainbow pets from best egg", "Make 50 golden pets from best egg"
    if v:find("rainbow") then return "rainbow" end
    if v:find("golden") or v:find("gold pet") then return "golden" end
    if v:find("hatch") then return "hatch" end
    -- Quest items, whatever the verb ("Break 3 piñatas", "Trigger 3 lucky blocks").
    if v:find("coin jar") then return "coinjar" end
    if v:find("comet") then return "comet" end
    if v:find("pinata") or v:find("piñata") then return "pinata" end
    if v:find("lucky block") then return "luckyblock" end
    if v:find("fruit") and (v:find("use") or v:find("eat")) then return "fruit" end
    if v:find("potion") and v:find("use") then return "potion" end
    if v:find("flag") and (v:find("use") or v:find("place")) then return "flag" end
    if v:find("collect") and v:find("potion") then return "collect_potion" end
    if v:find("collect") and v:find("enchant") then return "collect_enchant" end
    if v:find("upgrade") and v:find("potion") then return "upgrade_potion" end
    if v:find("upgrade") and v:find("enchant") then return "upgrade_enchant" end
    if v:find("unlock") and v:find("area") then return "zone" end
    if v:find("rebirth") then return "rebirth" end
    if v:find("earn") and v:find("diamond") then return "farm" end
    if v:find("break") then
        if v:find("coin jar") then return "coinjar" end
        if v:find("comet") then return "comet" end
        if v:find("pinata") or v:find("piñata") then return "pinata" end
        if v:find("lucky block") then return "luckyblock" end
        if v:find("mini") and v:find("chest") then return "minichest" end
        if v:find("safe") then return "safe" end
        if v:find("diamond") then return "diamond" end
        return "farm"
    end
    return "unhandled"
end
local scores = {
    farm = 98, diamond = 94, minichest = 62, safe = 60,
    hatch = 104, hatch_rare = 106, golden = 103, rainbow = 102,
    fruit = 88, potion = 86, flag = 74,
    zone = 76, rebirth = 12, coinjar = 101, comet = 101,
    pinata = 100, luckyblock = 100, convert = 4,
    collect_potion = 67, collect_enchant = 67,
    upgrade_potion = 70, upgrade_enchant = 70, unhandled = -200,
}
local function normalizeGoal(key, entry)
    if type(entry) ~= "table" then return nil end
    local title = describe(getGoalTitle(entry))
    local kind = classify(title)
    local progress = tonumber(entry.Progress or entry.progress or 0) or 0
    local required = tonumber(entry.Amount or entry.amount or 0) or 0
    local tier = tonumber(entry.Stars or entry.StarAmount or entry.Tier or entry.tier or key)
    local result = {
        key = tostring(key), title = title, kind = kind, progress = progress,
        required = required, tier = tier, raw = entry,
    }
    result.signature = tostring(key) .. ":" .. title .. ":" .. tostring(progress)
    result.identity = tostring(key) .. ":" .. title
    return result
end
local function readGoals(data)
    local result = {}
    local goals = data.Goals or data.RankGoals or data.RankQuests
    if type(goals) == "table" then
        for key, value in pairs(goals) do
            local g = normalizeGoal(key, value)
            if g then table.insert(result, g) end
        end
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end
local function getInventoryEntry(section, identifier, tier)
    local data = saveData()
    local inventory = data and data.Inventory
    local stock = inventory and inventory[section]
    if type(stock) ~= "table" then return nil end
    local candidates = {}
    for uid, item in pairs(stock) do
        if type(item) == "table" then
            local id = tostring(item.id or item.ID or "")
            local tn = tonumber(item.tn)
            local amount = tonumber(item._am or item.Amount or 1) or 1
            if amount > 0 and (identifier == nil or id:lower():find(identifier:lower(), 1, true))
                and (tier == nil or tier == tn) then
                table.insert(candidates, {uid = uid, id = id, tier = tn or 0, amount = amount})
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        return tostring(a.uid) < tostring(b.uid)
    end)
    return candidates[1]
end
local function numeralToNumber(text)
    local n = tonumber(text:lower():match("tier%s+(%d+)"))
    if n then return n end
    local romans = {I=1, V=5, X=10, L=50, C=100}
    local roman = text:upper():match("TIER%s+([IVXLC]+)")
    if not roman then return nil end
    local total, previous = 0, 0
    for i = #roman, 1, -1 do
        local v = romans[roman:sub(i,i)] or 0
        total = total + (v < previous and -v or v)
        previous = v
    end
    return total > 0 and total or nil
end

local function inspectState()
    local data = saveData()
    if not data then
        state.status = "Save.Get unavailable: no automation (press RECHECK)"
        state.rank = leaderstat("rank") or "?"
        return false
    end
    local rank = tonumber(data.Rank) or tonumber(leaderstat("rank"))
    if rank then
        state.rank = rank
        if rank ~= state.lastRank then
            if state.lastRank ~= nil then log("Rank advanced: " .. state.lastRank .. " -> " .. rank, "RANK") end
            state.lastRank = rank
            state.lastProgressAt = now()
            state.blocked = {}
            state.questWatch = {}
        end
    end
    state.starCount = data.RankStars or data.Stars or "?"
    -- RankCmds.GetMaxRank semantics may vary by game version. Display only.
    -- Do NOT use it as a stopping condition without live confirmation.
    local maximum = getMaxRank()
    state.maxRank = maximum or "unknown"
    local zone = getZoneInfo()
    state.area = zone and (tostring(zone.number or "?") .. " | " .. zone.name) or "not detected"
    state.goals = readGoals(data)
    -- Per-quest watchdog: only progress on THIS quest resets its timer.
    -- Other quests changing cannot conceal a stalled selected quest.
    local visible = {}
    for _, g in ipairs(state.goals) do
        visible[g.identity] = true
        local old = state.questWatch[g.identity]
        if not old or old.progress ~= g.progress then
            state.questWatch[g.identity] = {progress=g.progress, changedAt=now()}
        end
    end
    for id in pairs(state.questWatch) do
        if not visible[id] then state.questWatch[id] = nil end
    end
    local fragments = {}
    for _, g in ipairs(state.goals) do table.insert(fragments, g.signature) end
    local fingerprint = table.concat(fragments, "||")
    if fingerprint ~= state.lastGoalFingerprint then
        if state.lastGoalFingerprint ~= "" then log("Goals changed", "QUEST") end
        state.lastGoalFingerprint = fingerprint
        state.lastProgressAt = now()
    end
    return true
end
local questToggle = {
    hatch = "Hatch rank quests", farm = "Farm breakables", diamond = "Farm breakables",
    minichest = "Farm breakables", safe = "Farm breakables",
    fruit = "Fruit / potion / flags", potion = "Fruit / potion / flags", flag = "Fruit / potion / flags",
    zone = "Advance areas", rebirth = "Allow rebirth",
    coinjar = "Spawn jars / comets", comet = "Spawn jars / comets",
    pinata = "Spawn jars / comets", luckyblock = "Spawn jars / comets",
    collect_potion = "Vending or Upgrade", collect_enchant = "Vending or Upgrade",
    upgrade_potion = "Upgrade potions / enchants", upgrade_enchant = "Upgrade potions / enchants",
    hatch_rare = "Hatch rank quests", golden = "Gold / rainbow machine quests",
    rainbow = "Gold / rainbow machine quests",
}
local function eligible(goal)
    if (state.blocked[goal.identity] or 0) > now() then return false end
    local needed = {
        hatch = Config.AutoHatch, farm = Config.AutoFarm, diamond = Config.AutoFarm,
        hatch_rare = Config.AutoHatch,
        golden = Config.AutoGoldRainbow, rainbow = Config.AutoGoldRainbow,
        collect_potion = Config.AutoVending or Config.AutoUpgrade,
        collect_enchant = Config.AutoVending or Config.AutoUpgrade,
        upgrade_potion = Config.AutoUpgrade, upgrade_enchant = Config.AutoUpgrade,
        minichest = Config.AutoFarm, safe = Config.AutoFarm,
        fruit = Config.AutoConsumables, potion = Config.AutoConsumables,
        flag = Config.AutoConsumables, zone = Config.AutoWorld,
        coinjar = Config.AutoEventItems, comet = Config.AutoEventItems,
        pinata = Config.AutoEventItems, luckyblock = Config.AutoEventItems,
        rebirth = Config.AutoRebirth,
    }
    if needed[goal.kind] == true then return true end
    if cooldownReady("skipped:" .. goal.identity, 300) then
        local toggle = questToggle[goal.kind]
        log("Skipping '" .. goal.title .. "'" .. (toggle and (": turn on " .. toggle) or ": quest type not supported"), "PLANNER")
    end
    return false
end
local function rankGoals()
    local list = {}
    for _,g in ipairs(state.goals) do
        if eligible(g) then
            local score = (scores[g.kind] or -500)
            -- Prefer quests we have the resources to finish immediately.
            -- Avoid planning fruit/potion/flag consumption with an empty inventory.
            if g.kind == "fruit" then
                score = score + (getInventoryEntry("Fruit") and 38 or -35)
            elseif g.kind == "potion" then
                local neededTier = numeralToNumber(g.title)
                score = score + (getInventoryEntry("Potion",nil,neededTier) and 38 or -35)
            elseif g.kind == "flag" then
                score = score + (getInventoryEntry("Misc","Flag") and 23 or -30)
            end
            if Config.PreferHighStars and g.tier then score = score + (g.tier * 3) end
            if g.required > 0 then
                local completion = math.max(0,math.min(1,g.progress/g.required))
                score = score + completion * 22
            end
            table.insert(list, {g = g, score = score})
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.g.key < b.g.key
    end)
    local ordered = {}
    for i, row in ipairs(list) do ordered[i] = row.g end
    return ordered
end

local function matchesQuestBreakable(goalKind, b)
    if goalKind == "farm" then return true end
    local dirType = b.dir and tostring(b.dir.BreakableType or "") or ""
    local tags = (tostring(b.id or "") .. " " .. dirType .. " "
        .. tostring(b.model and b.model.Name or "")):lower()
    if goalKind == "diamond" then return tags:find("diamond", 1, true) ~= nil end
    if goalKind == "minichest" then
        return tags:find("mini", 1, true) ~= nil and tags:find("chest", 1, true) ~= nil
    end
    if goalKind == "safe" then return tags:find("safe", 1, true) ~= nil end
    if goalKind == "coinjar" then return tags:find("jar", 1, true) ~= nil end
    if goalKind == "comet" then return tags:find("comet", 1, true) ~= nil end
    if goalKind == "pinata" then return tags:find("pinata", 1, true) ~= nil or tags:find("piñata", 1, true) ~= nil end
    if goalKind == "luckyblock" then return tags:find("lucky", 1, true) ~= nil end
    return false
end

local function currentFarmZone()
    local ok, name = callMethod(state.clients.MapCmds, "GetCurrentZone")
    if ok and type(name) == "string" then return name end
    local owned = getZoneInfo()
    return owned and owned.name or nil
end

-- DZ source: BreakableFrontend.AllByZoneAndClass, b.uid, b.model,
-- b.position, b.health, b.dir, b.disableDamage, Pet:SetTarget.
-- This is preferable to guessing breakable IDs from Workspace model names.
local function dzBreakables(kind)
    local frontend = state.clients.BreakableFrontend
    if type(frontend) ~= "table" or type(frontend.AllByZoneAndClass) ~= "function" then
        return nil -- nil means unsupported, whereas {} means supported but empty.
    end
    local zone = currentFarmZone()
    if not zone then return {} end
    local root = currentRoot()
    if not root then return {} end
    local found = {}
    for _, className in ipairs({"Normal", "Chest"}) do
        local ok, group = callMethod(frontend, "AllByZoneAndClass", zone, className)
        if ok and type(group) == "table" then
            for _, b in pairs(group) do
                if type(b) == "table" and b.uid ~= nil and b.model
                    and type(b.health) == "number" and b.health > 0
                    and not b.disableDamage and not (b.dir and b.dir.NoTapping)
                    and matchesQuestBreakable(kind, b) then
                    local vipOK, isVIP = pcall(b.model.GetAttribute, b.model, "VIPBreakable")
                    if not (vipOK and isVIP) then
                        local pos = b.position
                        if typeof(pos) ~= "Vector3" then
                            local okModel, pivot = pcall(b.model.GetPivot, b.model)
                            pos = okModel and pivot.Position or nil
                        end
                        if typeof(pos) == "Vector3" then
                            local distance = (pos-root.Position).Magnitude
                            if distance <= Config.FarmRadius then
                                found[#found+1] = {uid = b.uid, id = b.id,
                                    model = b.model, distance = distance, dz = true}
                                if #found >= Config.MaxCandidatesPerPass then break end
                            end
                        end
                    end
                end
            end
        end
        if #found >= Config.MaxCandidatesPerPass then break end
    end
    table.sort(found, function(a,b) return a.distance < b.distance end)
    return found
end

local function getBreakables()
    local things = findChild(Workspace, "__THINGS")
    return findChild(things, "Breakables")
end
local function legacyBreakables(kind)
    local root = currentRoot()
    local group = getBreakables()
    if not root or not group then return {} end
    local list, candidates = {}, group:GetChildren()
    local count = #candidates
    if count == 0 then return list end
    local limit = math.min(count, Config.ScanLimit)
    for i=1,limit do
        local idx = ((state.scanCursor + i - 2) % count) + 1
        local child = candidates[idx]
        local part = child and child:FindFirstChild("Hitbox", true)
        if part and part:IsA("BasePart") then
            local distance = (part.Position - root.Position).Magnitude
            if distance <= Config.FarmRadius and matchesQuestBreakable(kind, {
                id = child.Name, model = child,
                dir = {BreakableType=tostring(child:GetAttribute("BreakableType") or "")},
            }) then
                list[#list+1] = {uid=child.Name,id=child.Name,model=child,
                    part=part,distance=distance,dz=false}
            end
        end
    end
    state.scanCursor = ((state.scanCursor + limit - 1) % count) + 1
    table.sort(list, function(a,b) return a.distance < b.distance end)
    return list
end
local function visibleTargetCandidates(kind)
    local modern = dzBreakables(kind)
    if modern ~= nil and #modern > 0 then
        state.lastFarmInterface = "DZ BreakableFrontend"
        return modern
    end
    -- BreakableFrontend can report nothing (e.g. zone name mismatch right after a
    -- teleport) while breakables are right there; scan the workspace as well.
    state.lastFarmInterface = "Legacy Workspace"
    return legacyBreakables(kind)
end

local function equippedPetIds()
    local ids = {}
    local ok, equipped = callMethod(state.clients.PetCmds, "GetEquipped")
    if ok and type(equipped) == "table" then
        for key, value in pairs(equipped) do
            local id = type(value) == "table" and (value.euid or value.uid or value.UID) or nil
            if id == nil and type(key) == "string" then id = key end
            if id ~= nil then ids[#ids+1] = id end
        end
    end
    return ids
end
-- Sends every equipped pet straight onto a breakable in one request, so pets
-- start dealing damage without walking there. Pets are spread across targets.
local function bulkJoinPets(targets)
    if not Config.InstantPets or state.bulkUnsupported then return false end
    if not findChild(findChild(ReplicatedStorage, "Network"), "Breakables_JoinPetBulk") then
        state.bulkUnsupported = true
        log("Instant pets: Breakables_JoinPetBulk not in this game version; using normal pet targeting", "WAIT")
        return false
    end
    local ids = equippedPetIds()
    if #ids == 0 then return false end
    local assignment = {}
    for i, petId in ipairs(ids) do
        assignment[petId] = targets[((i - 1) % #targets) + 1].uid
    end
    local ok, err = network("Breakables_JoinPetBulk", {assignment}, false)
    if not ok then
        state.bulkUnsupported = true
        log("Instant pets unavailable (" .. describe(err) .. "); using normal pet targeting", "WAIT")
        return false
    end
    return true
end
local function aimPetsAt(targets)
    local first = tostring(targets[1].uid)
    local interval = Config.FastMode and Config.FastPetAssignSeconds or Config.PetAssignSeconds
    if now()-state.lastPetAssign < interval and state.lastAssignedTarget == first then return false end
    if bulkJoinPets(targets) then
        state.lastPetAssign = now()
        state.lastAssignedTarget = first
        return true
    end
    local pp = state.clients.PlayerPet
    if type(pp) == "table" and type(pp.GetByPlayer) == "function" then
        local ok, pets = callMethod(pp, "GetByPlayer", LocalPlayer)
        if ok and type(pets) == "table" then
            local count = 0
            for _, pet in pairs(pets) do
                if type(pet) == "table" and type(pet.SetTarget) == "function" then
                    local target = targets[(count % #targets) + 1]
                    if target.model then pcall(pet.SetTarget, pet, target.model) end
                    count = count + 1
                    if count >= Config.MaxPetsPerTick then break end
                end
            end
            if count > 0 then
                state.lastPetAssign = now()
                state.lastAssignedTarget = first
                return true
            end
        end
    end
    local ids = equippedPetIds()
    if #ids > 0 then
        local count = 0
        for i, petId in ipairs(ids) do
            local target = targets[((i - 1) % #targets) + 1]
            if network("Breakables_JoinPet", {target.uid, petId}, false) then
                count = count + 1
            end
            if count >= Config.MaxPetsPerTick then break end
        end
        state.lastPetAssign = now()
        state.lastAssignedTarget = first
        return count > 0
    end
    return false
end
local function damageBreakable(target)
    -- DZ Hub observed UnreliableFire with b.uid, not b.id or model.Name.
    local net = state.clients.Network
    if type(net) == "table" and type(net.UnreliableFire) == "function" then
        local ok, result = callMethod(net, "UnreliableFire", "Breakables_PlayerDealDamage", target.uid)
        if ok and result ~= false then return true end
    end
    local ok, result = network("Breakables_PlayerDealDamage", {target.uid}, false)
    return ok and result ~= false
end
local function keepInBestArea()
    if state.tripActive or not Config.StayInBestArea or not cooldownReady("bestArea", 4) then return end
    local best = getZoneInfo()
    local ok, current = callMethod(state.clients.MapCmds, "GetCurrentZone")
    if best and ok and type(current) == "string" and current ~= best.name then
        local moved = placeInZone(best)
        if moved and cooldownReady("bestAreaLog", 60) then
            log("Moved back to best area: " .. best.name, "WORLD")
        end
    end
end
-- Goes back to the last spot where farming found targets (inside the best
-- area), or into the area's breakable zone if no spot is known yet.
local function returnToFarm(reason)
    if state.tripActive then return false end
    local root = currentRoot()
    if not root then return false end
    if state.farmHome and (root.Position - state.farmHome.Position).Magnitude > 30 then
        root.CFrame = state.farmHome
        if cooldownReady("returnLog", 20) then log("Back to farm spot" .. (reason and (": " .. reason) or ""), "WORLD") end
        return true
    end
    return placeInZone(getZoneInfo())
end
local function farm(goal, allowMove)
    if allowMove == nil then allowMove = true end
    -- Away at the egg / a machine: nothing to farm there, and no reason to log it.
    if state.tripActive then return false end
    if not healthy("farm") then return false end
    local interval = Config.FastMode and Config.FastFarmSeconds or Config.FarmActionSeconds
    if now() - state.lastFarm < interval then return false end
    if not currentRoot() then return false end
    if allowMove then keepInBestArea() end
    local kind = goal and goal.kind or "farm"
    local targets = visibleTargetCandidates(kind)
    if #targets == 0 then
        -- Nothing of this kind nearby. Only leave if there is nothing at all to farm
        -- here (e.g. standing at the egg), not just because no mini-chest is around.
        if allowMove and (kind == "farm" or #visibleTargetCandidates("farm") == 0) then
            returnToFarm("nothing to farm here")
        end
        if cooldownReady("noTargets:"..kind, 45) then
            log("No matching targets ("..kind..") in active zone via "..state.lastFarmInterface,"WAIT")
        end
        return false
    end
    -- Only a pass that found targets uses up the interval, so another quest's
    -- farm pass can still run this tick when this one had nothing to hit.
    state.lastFarm = now()
    state.lastTargets, state.lastTargetsAt = targets, now()
    if not state.tripActive then
        local root = currentRoot()
        if root then state.farmHome = root.CFrame end
    end
    local batch = {}
    for i = 1, math.min(#targets, math.max(1, Config.TargetsPerTick)) do batch[i] = targets[i] end
    aimPetsAt(batch)
    local ok = false
    for _, target in ipairs(batch) do
        if not Config.AutoTap or damageBreakable(target) then ok = true end
    end
    state.currentTarget = tostring(batch[1].uid)
    if not ok then
        failFeature("farm", "No compatible breakables interface for "..state.lastFarmInterface)
        return false
    end
    state.attempts.farm=state.attempts.farm+1
    state.lastSuccessfulAction = now() -- command accepted, NOT verified quest credit
    return true
end
local hatchAmount, disableEggAnimation, eggCurrency, currencyBalance, applyHatchSettings
-- Hatch Settings: Charged (lucky, 20x cost) and Golden (only gold pets, 50x cost).
-- State is read with HatchingCmds.IsEnabled(Hatching.Options.X) and changed with
-- the ChargedHatch_Toggle / GoldenHatch_Toggle remotes. The remote is only fired
-- when the state is wrong and the state is re-read afterwards, so this works
-- whether the remote sets or flips the option.
local hatchOptionRemotes = {CHARGED = "ChargedHatch_Toggle", GOLDEN = "GoldenHatch_Toggle"}
local hatchOptionNames = {CHARGED = "Charged eggs", GOLDEN = "Golden eggs"}
local function hatchOptionEnabled(option)
    local types = state.clients.HatchingTypes
    local options = types and types.Options
    local key = type(options) == "table" and options[option] or nil
    if key == nil then return nil end
    local ok, enabled = callMethod(state.clients.HatchingCmds, "IsEnabled", key)
    if ok and type(enabled) == "boolean" then return enabled end
    return nil
end
local function setHatchOption(option, want, reason, force)
    local current = hatchOptionEnabled(option)
    -- A forced OFF (pause/stop) also fires when the script switched the option ON
    -- moments ago and the change may not be visible yet.
    local recentlyOn = force and not want and state.hatchOptionSetByUs[option]
        and now() - (state.hatchOptionFiredAt[option] or 0) < 6
    if current == nil or (current == want and not recentlyOn) then
        state.hatchOptionTries[option] = 0
        if current == false then state.hatchOptionSetByUs[option] = nil end
        return current
    end
    if not force then
        if now() < (state.hatchOptionPausedUntil[option] or 0) then return current end
        if not cooldownReady("hatchOption:" .. option, 4) then return current end
    end
    local tries = (state.hatchOptionTries[option] or 0) + 1
    state.hatchOptionTries[option] = tries
    if tries > 3 then
        -- The server keeps refusing (e.g. the option is not unlocked yet).
        state.hatchOptionTries[option] = 0
        state.hatchOptionPausedUntil[option] = now() + 300
        log(hatchOptionNames[option] .. " could not be turned " .. (want and "on" or "off")
            .. " (not unlocked yet?); retrying in 5 min", "WAIT")
        return current
    end
    local ok, err = network(hatchOptionRemotes[option], {want}, false)
    if not ok then failFeature("hatch-settings", err); return current end
    state.commandCount = state.commandCount + 1
    state.hatchOptionFiredAt[option] = now()
    if want then state.hatchOptionSetByUs[option] = true end
    log(hatchOptionNames[option] .. (want and " ON" or " OFF") .. (reason and (" (" .. reason .. ")") or ""), "HATCH")
    return want
end
-- Decides which option the active quests need: Charged for "hatch legendary"
-- quests, Golden for golden/rainbow pet quests, otherwise both off.
applyHatchSettings = function(force)
    if not Config.SmartHatchSettings then
        -- Not managing them any more: undo only what this script switched ON.
        for option in pairs(state.hatchOptionSetByUs) do
            setHatchOption(option, false, "smart hatch settings off", force)
        end
        state.wantOption = {}
        return
    end
    -- Only the quests actually being worked on count (state.activeGoals).
    local wantCharged, wantGolden, why = false, false, nil
    if state.running and Config.AutoRank and Config.AutoHatch then
        for _, g in ipairs(state.activeGoals or {}) do
            if g.kind == "hatch_rare" and Config.ChargedForRareQuests then
                wantCharged, why = true, g.title
                break
            elseif (g.kind == "golden" or g.kind == "rainbow") and Config.GoldenEggsForGoldQuests
                and now() < (state.goldMachineFailedUntil or 0) then
                -- Golden eggs (50x) only when the Gold Machine route is not working:
                -- they also stop normal pets from piling up for the machine.
                wantGolden, why = true, g.title .. "; gold machine unavailable"
                break
            end
        end
    end
    state.wantOption = {CHARGED = wantCharged, GOLDEN = wantGolden}
    setHatchOption("CHARGED", wantCharged, wantCharged and why or "not needed", force)
    setHatchOption("GOLDEN", wantGolden, wantGolden and why or "not needed", force)
end
-- True while a Charged/Golden change has been sent but is not visible yet; hatching
-- waits so the purchase and the learned egg cost use the right mode.
local function hatchModePending()
    if not Config.SmartHatchSettings then return false end
    for option, want in pairs(state.wantOption) do
        local current = hatchOptionEnabled(option)
        if current ~= nil and current ~= want and now() >= (state.hatchOptionPausedUntil[option] or 0) then
            return true
        end
    end
    return false
end
local function eggNameByNumber(number)
    local dir = state.clients.Directory
    if dir and type(dir.Eggs) == "table" then
        for key, e in pairs(dir.Eggs) do
            if type(e) == "table" and tonumber(e.eggNumber) == number then
                return type(e._id) == "string" and e._id or (type(key) == "string" and key or nil)
            end
        end
    end
    local util = tryModule(findChild(findChild(findChild(ReplicatedStorage, "Library"), "Util"), "EggsUtil"))
    local ok, name = callMethod(util, "GetIdByNumber", number)
    if ok and type(name) == "string" then return name end
    return nil
end
-- Best egg = highest-numbered egg capsule loaded on the map that this account
-- has unlocked (save.MaximumAvailableEgg). Falls back to the egg directory.
local function findEgg()
    local data = saveData()
    local maxEgg = data and tonumber(data.MaximumAvailableEgg or data.MaxAvailableEgg)
    local eggs = findChild(findChild(Workspace, "__THINGS"), "Eggs")
    local best
    if eggs then
        for _, capsule in ipairs(eggs:GetDescendants()) do
            if capsule:IsA("Model") or capsule:IsA("BasePart") then
                local number = tonumber(capsule.Name:match("^(%d+)%s*%-%s*Egg"))
                if number and (not maxEgg or number <= maxEgg) and (not best or number > best.number) then
                    local okP, pivot = pcall(capsule.GetPivot, capsule)
                    if okP and typeof(pivot) == "CFrame" then
                        best = {number = number, capsuleCFrame = pivot}
                    end
                end
            end
        end
    end
    if best then
        best.name = eggNameByNumber(best.number)
        if best.name then return best end
    end
    if maxEgg then
        local name = eggNameByNumber(maxEgg)
        if name then return {number = maxEgg, name = name} end
    end
    return nil
end
-- Max eggs per hatch: the game's own value when readable, otherwise found by
-- trying a large batch and halving the range on each refusal.
hatchAmount = function(egg)
    -- EggCmds.GetMaxHatch() is the game's own per-hatch maximum (used by every
    -- current script); only when it is unreadable is the maximum searched for.
    local cmds = state.clients.EggCmds
    for _, method in ipairs({"GetMaxHatch", "GetMaxHatchCount"}) do
        local ok, cap = callMethod(cmds, method)
        if not (ok and tonumber(cap)) then
            local dir = state.clients.Directory
            local eggDir = dir and type(dir.Eggs) == "table" and dir.Eggs[egg.name]
            if eggDir then ok, cap = callMethod(cmds, method, eggDir) end
        end
        if ok and tonumber(cap) and tonumber(cap) >= 1 then
            state.hatchKnown = true
            return math.floor(tonumber(cap))
        end
    end
    state.hatchKnown = false
    if state.hatchHi < 1 or now() > state.hatchResetAt then
        state.hatchHi, state.hatchResetAt = Config.MaxHatchBatch, now() + 600
    end
    state.hatchHi = math.max(state.hatchHi, state.hatchLo)
    return math.max(1, math.ceil((state.hatchLo + state.hatchHi) / 2))
end
-- Removes the egg-opening cut-scene by replacing the game's animation function,
-- and clicks through "Click to open!" if the animation still appears.
disableEggAnimation = function()
    if not Config.SkipEggAnimation then return end
    if not state.eggAnimPatched and cooldownReady("eggAnimPatch", 30) then
        -- Shared modules can be patched without getsenv.
        local places = {LocalPlayer:FindFirstChild("PlayerScripts"), findChild(ReplicatedStorage, "Library")}
        for _, place in ipairs(places) do
            for _, node in ipairs(place and place:GetDescendants() or {}) do
                local name = node.Name:lower()
                if node:IsA("ModuleScript") and name:find("egg", 1, true)
                    and (name:find("anim", 1, true) or name:find("open", 1, true)) then
                    local module = tryModule(node)
                    for key, value in pairs(module or {}) do
                        if type(value) == "function" and type(key) == "string" and key:lower():find("anim", 1, true) then
                            module[key] = function() return end
                            state.eggAnimPatched = true
                            log("Egg animation disabled (" .. node.Name .. "." .. key .. ")", "HATCH")
                        end
                    end
                end
            end
        end
        if not state.eggAnimPatched and type(getsenv) ~= "function" and cooldownReady("noGetsenv", 600) then
            log("Executor has no getsenv: using auto-click on 'Click to open!' instead", "HATCH")
        end
    end
    if not state.eggAnimPatched and type(getsenv) == "function" and cooldownReady("eggAnimPatchEnv", 30) then
        local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
        for _, node in ipairs(scripts and scripts:GetDescendants() or {}) do
            local name = node.Name:lower()
            if node:IsA("LocalScript") and name:find("egg", 1, true)
                and (name:find("open", 1, true) or name:find("hatch", 1, true)) then
                local okEnv, env = pcall(getsenv, node)
                if okEnv and type(env) == "table" then
                    for key, value in pairs(env) do
                        local lowerKey = type(key) == "string" and key:lower() or ""
                        if type(value) == "function" and lowerKey:find("anim", 1, true)
                            and (lowerKey:find("egg", 1, true) or lowerKey:find("hatch", 1, true) or lowerKey:find("open", 1, true)) then
                            env[key] = function() return end
                            state.eggAnimPatched = true
                            log("Egg animation disabled (" .. node.Name .. "." .. key .. ")", "HATCH")
                        end
                    end
                end
            end
        end
    end
end
local function guiShown(node, gui)
    if not (node and node.Parent and node.Visible and node.AbsoluteSize.X > 0) then return false end
    local parent = node.Parent
    while parent and parent ~= gui do
        if parent:IsA("GuiObject") and not parent.Visible then return false end
        if parent:IsA("ScreenGui") and not parent.Enabled then return false end
        parent = parent.Parent
    end
    return true
end
local function findGuiText(gui, text)
    for _, node in ipairs(gui:GetDescendants()) do
        if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Text:lower():find(text, 1, true) then
            return node
        end
    end
    return nil
end
local function clickThroughEggPrompt()
    if not Config.SkipEggAnimation then return end
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then return end
    -- Never click while a purchase dialog is open: a stray click could buy something.
    if cooldownReady("buyDialogScan", 1) then
        state.buyDialogLabel = findGuiText(gui, "would you like to buy")
    end
    if guiShown(state.buyDialogLabel, gui) then return end
    local label = state.eggPromptLabel
    if not (label and label.Parent) then
        label = nil
        if not cooldownReady("eggPromptScan", 2) then return end
        for _, node in ipairs(gui:GetDescendants()) do
            if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Text:lower():find("click to open", 1, true) then
                label = node
                break
            end
        end
        state.eggPromptLabel = label
    end
    if guiShown(label, gui) then
        -- Click on the "Click to open!" text itself rather than the middle of the
        -- screen, where an egg or a button could be.
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            local inset = game:GetService("GuiService"):GetGuiInset()
            local point = label.AbsolutePosition + label.AbsoluteSize / 2 + inset
            vim:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 1)
            vim:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 1)
        end)
    end
end
eggCurrency = function(egg)
    local dir = state.clients.Directory
    local entry = dir and type(dir.Eggs) == "table" and dir.Eggs[egg.name]
    if type(entry) == "table" then
        local value = entry.currency or entry.Currency or entry.currencyId
        if type(value) == "string" then return value end
    end
    local zone = getZoneInfo()
    local zoneData = zone and dir and type(dir.Zones) == "table" and dir.Zones[zone.name]
    if type(zoneData) == "table" and type(zoneData.Currency) == "string" then return zoneData.Currency end
    return nil
end
currencyBalance = function(currency)
    local ok, amount = callMethod(state.clients.CurrencyCmds, "Get", currency)
    return ok and tonumber(amount) or nil
end
local function hatch()
    if now() < (state.hatchRefusedUntil or 0) then return false end
    applyHatchSettings()
    if state.hatchBusy then return true end
    if hatchModePending() then return true end
    local interval = Config.FastMode and Config.FastHatchSeconds or Config.HatchActionSeconds
    local okDebounce, debounce = callMethod(state.clients.EggCmds, "ComputeDebounce")
    if okDebounce and tonumber(debounce) then interval = math.max(interval, tonumber(debounce)) end
    if now()-state.lastHatch < interval then return true end
    local egg=findEgg()
    if not egg then
        if cooldownReady("noEgg",40) then log("No unlocked egg found on the map (go near your best egg once)", "WAIT") end
        state.hatchRefusedUntil = now() + 15
        return false
    end
    if not currentRoot() then return false end
    local count = hatchAmount(egg)
    -- Coins check: per-egg cost is learned from the balance change of earlier hatches.
    local currency = eggCurrency(egg)
    local balanceBefore = currency and currencyBalance(currency)
    -- Charged (20x) and Golden (50x) change the price, so costs are learned per mode.
    local costKey = egg.name .. (hatchOptionEnabled("CHARGED") and ":charged" or "")
        .. (hatchOptionEnabled("GOLDEN") and ":golden" or "")
    local perEgg = state.eggCost[costKey]
    if not perEgg and costKey ~= egg.name then
        -- New mode: start from the plain cost times the Charged (20x) / Golden (50x)
        -- multiplier, or with a single egg so the real cost gets learned.
        local base = state.eggCost[egg.name]
        if base and base > 0 then
            perEgg = base * (costKey:find(":charged", 1, true) and 20 or 1) * (costKey:find(":golden", 1, true) and 50 or 1)
        else
            count = 1
        end
    end
    -- After a coin refusal the batch is halved until a hatch succeeds again.
    if state.hatchCap[costKey] then count = math.min(count, state.hatchCap[costKey]) end
    if balanceBefore and perEgg and perEgg > 0 then
        local affordable = math.floor(balanceBefore / perEgg)
        if affordable < 1 then
            state.hatchRefusedUntil = now() + 45
            if cooldownReady("hatchNoCoins", 45) then
                log("Not enough " .. currency .. " to hatch " .. egg.name .. "; farming first", "WAIT")
            end
            returnToFarm("out of coins")
            return false
        end
        count = math.min(count, affordable)
    end
    pcall(disableEggAnimation)
    state.lastHatch=now()
    state.hatchBusy = true
    task.spawn(function()
        local function buy()
            if findChild(findChild(ReplicatedStorage,"Network"),"Eggs_RequestPurchase") then
                return network("Eggs_RequestPurchase",{egg.name,count},true)
            end
            return callMethod(state.clients.EggCmds,"RequestPurchase",egg.name,count)
        end
        local success, result, message
        if egg.capsuleCFrame then
            success, result, message = quickTrip(egg.capsuleCFrame*CFrame.new(0,4,8), buy)
        else
            success, result, message = buy()
        end
        state.hatchBusy = false
        state.commandCount = state.commandCount + 1
        if result == "busy" then state.lastHatch = 0; return end
        local reason = string.lower(tostring(message or (not success and result) or ""))
        if success and result ~= false then
            state.hatchFails = 0
            state.hatchLo = math.max(state.hatchLo, count)
            local balanceAfter = currency and currencyBalance(currency)
            -- Only learn the cost if the hatch mode did not change during the purchase.
            local modeNow = egg.name .. (hatchOptionEnabled("CHARGED") and ":charged" or "")
                .. (hatchOptionEnabled("GOLDEN") and ":golden" or "")
            if modeNow == costKey and balanceBefore and balanceAfter and balanceAfter < balanceBefore then
                state.eggCost[costKey] = (balanceBefore - balanceAfter) / count
            end
            state.hatchCap[costKey] = nil
            state.attempts.hatch=state.attempts.hatch+1
            if cooldownReady("hatchLog", 30) then log("Hatching "..egg.name.." x"..count, "HATCH") end
            state.lastSuccessfulAction=now()
            return
        end
        -- The server says why: "too quickly" is only the hatch cooldown, and
        -- "far away" means the trip did not get close enough.
        if reason:find("quick", 1, true) or reason:find("fast", 1, true) then return end
        if reason:find("far", 1, true) and cooldownReady("hatchFar", 30) then
            log("Hatch refused: too far from " .. egg.name, "WAIT")
        end
        -- Otherwise act on two refusals in a row.
        state.hatchFails = state.hatchFails + 1
        if state.hatchFails < 2 then return end
        state.hatchFails = 0
        if count > state.hatchLo and not state.hatchKnown then
            -- Too many at once: search downwards for the real maximum.
            state.hatchHi = count - 1
            state.lastHatch = 0
        elseif count > 1 then
            -- Probably not enough coins for this many: try half next time.
            state.hatchCap[costKey] = math.max(1, math.floor(count / 2))
            state.lastHatch = 0
        else
            -- Not even one egg: farm for a minute first.
            state.hatchRefusedUntil = now() + 60
            log("Hatch refused for "..egg.name.." x"..count.." ("..describe(message or result).."); farming 60s first","WAIT")
            returnToFarm("hatch refused")
        end
    end)
    return true
end
local function consume(goal)
    if now() - state.lastConsumable < Config.ConsumableSeconds then return false end
    state.lastConsumable = now()
    if goal.kind == "fruit" then
        local fruit = getInventoryEntry("Fruit")
        if not fruit then return false end
        local ok, result = callMethod(state.clients.FruitCmds, "Consume", fruit.uid)
        if ok and result ~= false then state.lastSuccessfulAction = now(); return true end
        failFeature("fruit", result)
    elseif goal.kind == "potion" then
        local tier = numeralToNumber(goal.title)
        local potion = getInventoryEntry("Potion", nil, tier)
        if not potion then return false end
        local ok, result = callMethod(state.clients.PotionCmds, "Consume", potion.uid)
        if ok and result ~= false then state.lastSuccessfulAction = now(); return true end
        failFeature("potion", result)
    elseif goal.kind == "flag" then
        local flag = getInventoryEntry("Misc", "Flag")
        if not flag then return false end
        local ok, result
        if findChild(findChild(ReplicatedStorage, "Network"), "FlexibleFlags_Consume") then
            -- Current games place flags through FlexibleFlags_Consume(flagId, flagUid, amount).
            ok, result = network("FlexibleFlags_Consume", {flag.id, flag.uid, 1}, true)
        else
            ok, result = callMethod(state.clients.ZoneFlagCmds, "Consume", flag.id, flag.uid)
        end
        if ok and result ~= false then state.lastSuccessfulAction = now(); return true end
        failFeature("flag", result)
    end
    return false
end
-- Vending collection automation is enabled only if the historical machine
-- method, its price directory and the player's balance are all readable.
-- This avoids charging an unknown amount for unverified stock.
local function vendingWait(reason)
    if cooldownReady("vending:why", 45) then log("Vending: " .. reason, "WAIT") end
    return false
end
local function vendingForGoal(goal, allowMove)
    if not Config.AutoVending or not healthy("vending") then return false end
    if state.vendingBusy then return true end
    if not cooldownReady("vending:scan", 4) then return false end
    local data = saveData()
    local stocks = data and (data.VendingStocks or data.VendingMachineStocks)
    if type(stocks) ~= "table" then return vendingWait("no vending stock in save data") end
    local prices = tryModule(findChild(findChild(findChild(ReplicatedStorage, "Library"), "Directory"), "VendingMachines"))
    local okCoins, coinBalance = callMethod(state.clients.CurrencyCmds, "Get", "Coins")
    coinBalance = okCoins and tonumber(coinBalance) or nil
    local machineCmds = state.clients.MachineCmds
    local itemKind = goal.kind == "collect_potion" and "potion" or "enchant"
    local reason = "no " .. itemKind .. " machine with stock"
    for machineName, stock in pairs(stocks) do
        if type(machineName)=="string" and machineName:lower():find(itemKind, 1, true)
            and tonumber(stock) and tonumber(stock) > 0 then
            local amount = math.min(3, math.floor(tonumber(stock)))
            local priceData = prices and prices[machineName]
            local price = priceData and tonumber(priceData.CurrencyCost)
            -- Unknown ownership / access is left for the server to decide.
            local okOwn, owned = callMethod(machineCmds, "Owns", machineName)
            local okUse, allowed = callMethod(machineCmds, "IsAllowedToOpen", machineName)
            if (okOwn and owned == false) or (okUse and allowed == false) then
                reason = machineName .. " is not unlocked"
            elseif price and coinBalance and price * amount > coinBalance * Config.VendingSpendFraction then
                reason = machineName .. " costs " .. tostring(price * amount) .. " coins (over spend limit)"
            else
                local node
                for _, mapRoot in ipairs(mapRoots()) do
                    node = mapRoot:FindFirstChild(machineName, true)
                    if node then break end
                end
                local spot = node and (node:FindFirstChild("Arrow", true) or node:FindFirstChild("arrowPivot", true)
                    or node:FindFirstChildWhichIsA("BasePart", true))
                local spotCF = spot and spot:IsA("BasePart") and (spot.CFrame + Vector3.new(0, 4, 0)) or nil
                state.vendingBusy = true
                task.spawn(function()
                    local function buy() return network("VendingMachines_Purchase", {machineName, amount}, true) end
                    local okBuy, result
                    if spotCF then okBuy, result = quickTrip(spotCF, buy) else okBuy, result = buy() end
                    state.vendingBusy = false
                    state.commandCount = state.commandCount + 1
                    if okBuy and result ~= false then
                        log("Bought " .. amount .. "x from " .. machineName, "VENDING")
                        state.lastSuccessfulAction = now()
                    elseif result ~= "busy" then
                        vendingWait(machineName .. " purchase refused (" .. describe(result) .. ")")
                    end
                end)
                return true
            end
        end
    end
    return vendingWait(reason)
end

local itemTypes = {
    coinjar = {match = "coin jar", word = "coinjar"},
    comet = {match = "comet", word = "comet"},
    pinata = {match = "pinata", word = "pinata"},
    luckyblock = {match = "lucky block", word = "luckyblock"},
}
local function squash(text) return (tostring(text):lower():gsub("[^%w]", "")) end
-- Finds e.g. "CoinJar_Spawn" / "Comet_Spawn" / "MiniPinata_Consume" by name.
local function findItemRemote(word)
    local net = findChild(ReplicatedStorage, "Network")
    if not net then return nil end
    local found, foundRank
    for _, remote in ipairs(net:GetChildren()) do
        local name = squash(remote.Name)
        if name:find(word, 1, true) and (remote:IsA("RemoteFunction") or remote:IsA("BaseRemoteEvent")) then
            local rank = name:find("spawn", 1, true) and 3 or name:find("consume", 1, true) and 2
                or (name:find("use", 1, true) or name:find("place", 1, true)) and 1 or nil
            if rank and (not found or rank > foundRank) then found, foundRank = remote, rank end
        end
    end
    return found
end
-- Picks the inventory item for the quest, preferring the variant the quest names
-- (e.g. "Basic Coin Jar" for a basic coin jar quest).
local function findQuestItem(spec, title)
    local data = saveData()
    local inventory = data and data.Inventory
    if type(inventory) ~= "table" then return nil end
    local lowerTitle = title:lower()
    local best, bestScore
    for _, section in pairs(inventory) do
        if type(section) == "table" then
            for uid, item in pairs(section) do
                if type(item) == "table" then
                    local id = tostring(item.id or item.ID or "")
                    local amount = tonumber(item._am or item.Amount or 1) or 1
                    if amount > 0 and id:lower():find(spec.match, 1, true) then
                        local score = 0
                        for word in id:lower():gmatch("%a+") do
                            score = score + (lowerTitle:find(word, 1, true) and 2 or -1)
                        end
                        -- A quest that names no variant is satisfied by the cheapest one.
                        if id:lower():find("basic", 1, true) or id:lower():find("mini", 1, true) then
                            score = score + 1
                        end
                        if not best or score > bestScore then best, bestScore = {uid = uid, id = id}, score end
                    end
                end
            end
        end
    end
    return best
end
local function spawnQuestObject(goal, allowMove)
    local spec = itemTypes[goal.kind]
    if not spec then return false end
    -- Attack anything already spawned first; this is not throttled.
    if #visibleTargetCandidates(goal.kind) > 0 then return farm(goal, allowMove) end
    -- Waiting between spawn attempts must not hold the character in place.
    if now() - state.lastEventItem < Config.SpawnItemSeconds then return false end
    local item = findQuestItem(spec, goal.title)
    if not item then
        if cooldownReady("missing:" .. goal.kind, 60) then log("No " .. spec.match .. " in inventory for '" .. goal.title .. "'", "WAIT") end
        return false
    end
    local remote = findItemRemote(spec.word)
    if not remote then
        if cooldownReady("noremote:" .. goal.kind, 120) then log("No spawn remote found for " .. spec.match, "WAIT") end
        return false
    end
    -- Spawn where farming happens (inside the breakable area); a spawn from
    -- outside it, e.g. next to the egg, is refused by the server.
    local root = currentRoot()
    local spawnSpot = nil
    local okBox, inBox = callMethod(state.clients.MapCmds, "IsInDottedBox")
    local outside = (okBox and inBox == false)
        or (root and state.farmHome and (root.Position - state.farmHome.Position).Magnitude > 30)
    if outside and state.farmHome then
        spawnSpot = state.farmHome
    elseif outside and allowMove then
        placeInZone(getZoneInfo())
    end
    state.lastEventItem = now()
    local function itemAmount()
        saveCache = nil
        local fresh = saveData()
        for _, section in pairs(fresh and fresh.Inventory or {}) do
            local entry = type(section) == "table" and section[item.uid]
            if type(entry) == "table" then return tonumber(entry._am or entry.Amount or 1) or 1 end
        end
        return 0
    end
    local before = itemAmount()
    local position = spawnSpot and spawnSpot.Position or (currentRoot() and currentRoot().Position)
    probeRemote("spawn-" .. goal.kind, remote, {
        {item.uid}, {item.id}, {item.uid, position}, {item.uid, 1},
    }, function()
        return itemAmount() < before or #visibleTargetCandidates(goal.kind) > 0
    end, function(worked, result)
        if worked then
            log("Spawned " .. item.id .. " via " .. remote.Name, "ITEM")
        else
            state.lastEventItem = now() + 45
            log("Spawn refused: " .. item.id .. " via " .. remote.Name .. " (" .. describe(result) .. ")", "WAIT")
        end
    end, spawnSpot)
    return true, "waiting"
end
local function tryAdvanceWorld()
    if now()-state.lastWorldCheck<Config.WorldCheckSeconds then return false end
    state.lastWorldCheck=now()
    local c=state.clients
    local ok,name=callMethod(c.ZoneCmds,"GetNextZone")
    if not ok or type(name)~="string" or name=="" then return false end
    local dir = c.Directory and c.Directory.Zones
    local zoneData = dir and dir[name]
    local balancing=c.Balancing
    local price, currency
    if type(zoneData)=="table" and type(balancing)=="table" then
        local priced,cost=callMethod(balancing,"CalcGatePrice",zoneData)
        if priced and type(cost)=="number" then
            price=cost;currency=zoneData.Currency
        end
    end
    if price and currency then
        local afford, can=callMethod(c.CurrencyCmds,"CanAfford",currency,price)
        if afford and can~=true then
            if cooldownReady("zone:notAfford",60) then
                log("Next zone costs "..tostring(price).." "..tostring(currency),"WAIT")
            end
            return false
        end
    elseif cooldownReady("zone:noPrice",120) then
        log("Gate price cannot be independently verified; requesting only through game remote", "WAIT")
    end
    local before=getZoneInfo()
    local accepted=attemptNetwork("zone","Zones_RequestPurchase",{name},true,Config.WorldCheckSeconds)
    if accepted then
        state.attempts.zone=state.attempts.zone+1
        local after=getZoneInfo()
        log("Zone purchase request: "..name.." (before="..tostring(before and before.name)
            ..", after="..tostring(after and after.name)..")", "WORLD")
        if after and after.name==name then placeInZone(after) end
    end
    if not Config.AutoRebirth then return accepted end
    local ok2,rebirth=callMethod(c.RebirthCmds,"GetNextRebirth")
    if ok2 and type(rebirth)=="table" then
        local current=getZoneInfo()
        local required=tonumber(rebirth.ZoneNumberRequired)
        local number=rebirth.RebirthNumber or rebirth._id
        if current and current.number and required and current.number>=required and number then
            if attemptNetwork("rebirth","Rebirth_Request",{tostring(number)},true,80) then
                log("Rebirth request: "..tostring(number),"WORLD")
            end
        end
    end
    return accepted
end

-- Reward thresholds can be cumulative. Source: DZ Hub ranksPending().
-- Uses the current rank ID from RanksUtil, instead of indexing only by integer rank.
local function pendingRankRewardIds(rankData, redeemed, stars)
    if type(rankData)~="table" or type(rankData.Rewards)~="table" then return {} end
    local out, total = {}, 0
    for idx, reward in ipairs(rankData.Rewards) do
        if type(reward)=="table" then
            total=total+(tonumber(reward.StarsRequired) or math.huge)
            if total<=stars and not redeemed[tostring(idx)] and not redeemed[idx] then
                out[#out+1]=idx
            end
        end
    end
    return out
end
local function claimRankRewards()
    if now()-state.lastRewardCheck<Config.RewardCheckSeconds then return end
    state.lastRewardCheck=now()
    local data=saveData()
    if not data or type(data.RedeemedRankRewards)~="table" then return end
    local c=state.clients
    local rank=tonumber(data.Rank)
    local rankData
    if rank and c.RanksUtil then
        local ok,id=callMethod(c.RanksUtil,"RankIDFromNumber",rank)
        if ok and id and c.Directory and c.Directory.Ranks then
            rankData=c.Directory.Ranks[id]
        end
    end
    if not rankData then
        local ok,arr=callMethod(c.RanksUtil,"GetArray")
        if ok and type(arr)=="table" and rank then rankData=arr[rank] end
    end
    local pending=pendingRankRewardIds(rankData,data.RedeemedRankRewards,tonumber(data.RankStars) or 0)
    local idx=pending[1]
    if not idx then return end
    if attemptNetwork("claim","Ranks_ClaimReward",{idx},false,4) then
        log("Rank reward claim request "..tostring(idx),"REWARD")
    end
end

local function diamonds()
    local ok,n=callMethod(state.clients.CurrencyCmds,"Get","Diamonds")
    return (ok and tonumber(n)) or nil
end
local function buySlot(kind)
    local c=state.clients
    local data=saveData()
    if not data or not c.RankCmds or not c.Balancing then return false end
    local isEgg=kind=="egg"
    local purchased=tonumber(isEgg and data.EggSlotsPurchased or data.PetSlotsPurchased)
    if not purchased then return false end
    local ceilingMethod=isEgg and "GetMaxPurchasableEggSlots" or "GetMaxPurchasableEquipSlots"
    local ok, ceiling=callMethod(c.RankCmds,ceilingMethod)
    if not ok or not tonumber(ceiling) or purchased>=tonumber(ceiling) then return false end
    local aim,amount,cost=purchased+1,1,0
    if isEgg then
        local bundleOK,last,size=callMethod(c.RankCmds,"GetEggBundle",aim)
        if not bundleOK or not tonumber(last) or not tonumber(size) then return false end
        aim=tonumber(last);amount=tonumber(size)
        if aim>tonumber(ceiling) or amount<1 or amount>50 then return false end
        for slot=aim-amount+1,aim do
            local priced,price=callMethod(c.Balancing,"CalcEggSlotPrice",slot)
            if not priced or not tonumber(price) or tonumber(price)<0 then return false end
            cost=cost+tonumber(price)
        end
    else
        local priced,price=callMethod(c.Balancing,"CalcPetSlotPrice",aim)
        if not priced or not tonumber(price) or tonumber(price)<0 then return false end
        cost=tonumber(price)
    end
    local balance=diamonds()
    if not balance or cost>balance*Config.MaxSlotSpendFraction then return false end
    local remote=isEgg and "EggHatchSlotsMachine_RequestPurchase"
        or "EquipSlotsMachine_RequestPurchase"
    if attemptNetwork("slots",remote,{aim},true,Config.SlotCheckSeconds) then
        log("Requested "..kind.." slot upgrade, target="..tostring(aim)
            .." cost="..tostring(cost),"UPGRADE")
        return true
    end
    return false
end
local function equipBest()
    if now()-state.lastEquip<Config.EquipCheckSeconds then return end
    state.lastEquip=now()
    local ok=callMethod(state.clients.PetCmds,"EquipBest")
    if not ok and cooldownReady("equipMissing",90) then
        log("PetCmds.EquipBest unavailable (source DZ Hub)","WAIT")
    end
end
local function extraProgression()
    if Config.AutoEquipBest then equipBest() end
    if now()-state.lastSlots>=Config.SlotCheckSeconds then
        state.lastSlots=now()
        if healthy("slots") then
            if Config.AutoPetSlots then buySlot("pet") end
            if Config.AutoEggSlots then buySlot("egg") end
        end
    end
end

-- Super magnet: orbs (coins / diamonds dropped by breakables) and lootbags are
-- queued the moment they appear, claimed in one request per type, then removed
-- locally. Removing them is what cuts the lag from hundreds of drops piling up.
local magnetSpecs = {
    {feature = "magnet-orbs", folder = "Orbs", exact = "Orbs: Collect",
        words = {"orb"}, verbs = {"collect", "claim"}, toId = tonumber},
    {feature = "magnet-lootbags", folder = "Lootbags", exact = "Lootbags_Claim",
        words = {"lootbag"}, verbs = {"claim", "collect"}, toId = function(name) return name end},
}
local function findMagnetRemote(spec)
    local net = findChild(ReplicatedStorage, "Network")
    if not net then return nil end
    local exact = net:FindFirstChild(spec.exact)
    if exact then return exact end
    for _, remote in ipairs(net:GetChildren()) do
        if remote:IsA("BaseRemoteEvent") or remote:IsA("RemoteFunction") then
            local name = squash(remote.Name)
            local hasWord, hasVerb = true, false
            for _, w in ipairs(spec.words) do if not name:find(w, 1, true) then hasWord = false end end
            for _, v in ipairs(spec.verbs) do if name:find(v, 1, true) then hasVerb = true end end
            if hasWord and hasVerb then return remote end
        end
    end
    return nil
end
local function queueMagnet(spec, node)
    local id = spec.toId(node.Name)
    if id ~= nil and not spec.seen[node] then
        spec.seen[node] = true
        spec.queue[#spec.queue+1] = {id = id, node = node}
    end
end
local function hookMagnet(spec)
    local folder = findChild(findChild(Workspace, "__THINGS"), spec.folder)
    if not folder or spec.hooked == folder then return folder end
    spec.hooked, spec.queue, spec.seen = folder, {}, setmetatable({}, {__mode = "k"})
    for _, node in ipairs(folder:GetChildren()) do queueMagnet(spec, node) end
    table.insert(state.connections, folder.ChildAdded:Connect(function(node)
        if Config.SuperMagnet then queueMagnet(spec, node) end
    end))
    return folder
end
local function flushMagnet(spec)
    if not healthy(spec.feature) or not hookMagnet(spec) or #spec.queue == 0 then return end
    if not spec.remote or not spec.remote.Parent then
        spec.remote = findMagnetRemote(spec)
        if not spec.remote then
            if cooldownReady("magnet:none:" .. spec.folder, 120) then
                log("Super magnet: no collect remote found for " .. spec.folder, "WAIT")
            end
            return
        end
    end
    local batch, ids = {}, {}
    while #spec.queue > 0 and #ids < 250 do
        local entry = table.remove(spec.queue, 1)
        if entry.node.Parent then
            batch[#batch+1] = entry
            ids[#ids+1] = entry.id
        end
    end
    if #ids == 0 then return end
    local ok, err = pcall(function()
        if spec.remote:IsA("RemoteFunction") then return spec.remote:InvokeServer(ids) end
        spec.remote:FireServer(ids)
        return true
    end)
    if not ok then failFeature(spec.feature, err); return end
    state.commandCount = state.commandCount + 1
    for _, entry in ipairs(batch) do pcall(entry.node.Destroy, entry.node) end
end
local function autoTap()
    if not Config.AutoTap or not healthy("farm") or not cooldownReady("tap", Config.TapSeconds) then return end
    if now() - state.lastTargetsAt > 1.5 then
        state.lastTargets, state.lastTargetsAt = visibleTargetCandidates("farm"), now()
    end
    for _, target in ipairs(state.lastTargets) do
        if target.model and target.model.Parent then
            damageBreakable(target)
            return
        end
    end
end
local function ultimateName(cmds)
    for _, getter in ipairs({"GetEquippedItem", "GetEquipped", "GetEquippedUltimate", "GetCurrent"}) do
        local ok, item = callMethod(cmds, getter)
        if ok and type(item) == "string" then return item end
        if ok and type(item) == "table" then
            local okId, id = pcall(function()
                if type(item.GetId) == "function" then return item:GetId() end
                return item._id or item.id or item.Id or (type(item._data) == "table" and item._data.id)
            end)
            if okId and id then return id end
        end
    end
    return nil
end
local function autoUltimate()
    if not Config.AutoUltimate or not healthy("ultimate") or not cooldownReady("ultimate", Config.UltimateSeconds) then return end
    local cmds = state.clients.UltimateCmds
    local name = ultimateName(cmds)
    if cmds then
        for _, method in ipairs({"Activate", "Use", "Fire"}) do
            if type(cmds[method]) == "function" then
                local ok = callMethod(cmds, method, name)
                if ok then return end
            end
        end
    end
    local net = findChild(ReplicatedStorage, "Network")
    for _, remote in ipairs(net and net:GetChildren() or {}) do
        local lower = squash(remote.Name)
        if lower:find("ultimate", 1, true) and (lower:find("activate", 1, true) or lower:find("use", 1, true)) then
            pcall(function()
                if remote:IsA("RemoteFunction") then remote:InvokeServer(name) else remote:FireServer(name) end
            end)
            state.commandCount = state.commandCount + 1
            return
        end
    end
    if cooldownReady("ultimate:none", 300) then log("Auto ultimate: no ultimate interface found", "WAIT") end
end
local function superMagnet()
    if not Config.SuperMagnet or now() - state.lastMagnet < Config.MagnetSeconds then return end
    state.lastMagnet = now()
    for _, spec in ipairs(magnetSpecs) do flushMagnet(spec) end
end
local function claimFreeGift()
    if not Config.AutoFreeGifts or not healthy("freegifts")
        or now()-state.lastGifts<Config.GiftCheckSeconds then return end
    state.lastGifts=now()
    local c=state.clients
    local data=saveData()
    local gifts=c.Directory and c.Directory.FreeGifts
    if type(gifts)~="table" or type(data)~="table" then return end
    local elapsed=tonumber(data.FreeGiftsTime)
    local redeemed=data.FreeGiftsRedeemed
    if not elapsed or type(redeemed)~="table" then return end
    -- The source's freeGiftsList() uses ID keys; iterate actual IDs rather
    -- than ipairs() on a potentially sparse ID-indexed table.
    for _,row in pairs(gifts) do
        if type(row)=="table" then
            local id=tonumber(row.Id)
            local required=tonumber(row.WaitTime)
            if id and required and elapsed>=required and not table.find(redeemed,id)
                and not redeemed[tostring(id)] then
                if attemptNetwork("freegifts","Redeem Free Gift",{id},true,10) then
                    log("Free gift claim request "..tostring(id),"REWARD")
                end
                return
            end
        end
    end
end
local function blockGoal(goal, seconds, reason)
    state.blocked[goal.identity] = now() + (seconds or Config.BlockedQuestSeconds)
    state.blockedCount = state.blockedCount + 1
    log("Deferred '" .. goal.title .. "': " .. reason, "PLANNER")
end
local goalFeature = {
    farm = "farm", diamond = "farm", minichest = "farm", safe = "farm",
    fruit = "fruit", potion = "potion", flag = "flag",
    zone = "zone", rebirth = "rebirth",
}
-- Upgrade machine: turns a stack of low-tier potions/enchants into a higher tier.
-- The remote is discovered by name because it differs between game versions.
local function findUpgradeRemote(word)
    local net = findChild(ReplicatedStorage, "Network")
    if not net then return nil end
    local found, foundRank = nil, 0
    for _, remote in ipairs(net:GetChildren()) do
        local name = squash(remote.Name)
        if (remote:IsA("RemoteFunction") or remote:IsA("BaseRemoteEvent")) and name:find(word, 1, true) then
            -- The Supercomputer replaced the separate upgrade machines.
            local rank = (name:find("computer", 1, true) and 3)
                or (name:find("upgrade", 1, true) and name:find("machine", 1, true) and 2)
                or (name:find("upgrade", 1, true) and 1) or 0
            if rank > foundRank then found, foundRank = remote, rank end
        end
    end
    return found
end
-- Locates a machine on the map (e.g. the Super Computer / upgrade machines) by
-- name. Zone folders keep machines under INTERACT.Machines; a full map search is
-- only a fallback, and results are cached.
local function findMachineSpot(key, words, machineNames)
    local cached = state.machineSpots[key]
    if cached and cached.node.Parent then return cached.cframe end
    if not cooldownReady("machineScan:" .. key, 60) then return nil end
    local function matches(node)
        local name = squash(node.Name)
        for _, word in ipairs(words) do
            if name:find(word, 1, true) then return true end
        end
        return false
    end
    local function remember(node)
        local okPivot, pivot = pcall(function()
            return node:IsA("BasePart") and node.CFrame or node:GetPivot()
        end)
        if okPivot and typeof(pivot) == "CFrame" then
            state.machineSpots[key] = {node = node, cframe = pivot * CFrame.new(0, 4, 6)}
            return state.machineSpots[key].cframe
        end
        return nil
    end
    -- MachineCmds.GetModels(name) returns the machine's models on the map.
    for _, machineName in ipairs(machineNames or {}) do
        local ok, models = callMethod(state.clients.MachineCmds, "GetModels", machineName)
        if ok and type(models) == "table" then
            for _, model in pairs(models) do
                if typeof(model) == "Instance" and model.Parent then return remember(model) end
            end
        end
    end
    for _, mapRoot in ipairs(mapRoots()) do
        for _, zone in ipairs(mapRoot:GetChildren()) do
            local machines = zone:FindFirstChild("INTERACT") and zone.INTERACT:FindFirstChild("Machines")
            for _, node in ipairs(machines and machines:GetChildren() or {}) do
                if matches(node) then return remember(node) end
            end
        end
    end
    for _, mapRoot in ipairs(mapRoots()) do
        for _, node in ipairs(mapRoot:GetDescendants()) do
            if (node:IsA("Model") or node:IsA("BasePart")) and matches(node) then return remember(node) end
        end
    end
    return nil
end
-- Stops spending on a quest whose progress does not move: after 3 accepted
-- spends with no progress the quest is deferred for 10 minutes.
local function spendAllowed(goal)
    local watch = state.spendWatch[goal.identity]
    return not (watch and watch.spends >= 3 and watch.progress == goal.progress)
end
local function recordSpend(goal)
    local watch = state.spendWatch[goal.identity]
    if not watch or watch.progress ~= goal.progress then
        watch = {progress = goal.progress, spends = 0}
        state.spendWatch[goal.identity] = watch
    end
    watch.spends = watch.spends + 1
    if watch.spends >= 3 then
        state.blocked[goal.identity] = now() + 600
        state.blockedCount = state.blockedCount + 1
        log("Deferred '" .. goal.title .. "' 10 min: spending made no quest progress", "SAFEGUARD")
    end
end
-- Copies of tier N needed for one tier N+1: Balancing.CalcPotionsPerTierRequired /
-- CalcEnchantsPerTierRequired (Mastery lowers them), with the known table as fallback.
local function perTierRequired(isPotion, tier)
    local bal = state.clients.Balancing
    local name = isPotion and "CalcPotionsPerTierRequired" or "CalcEnchantsPerTierRequired"
    local fn = type(bal) == "table" and bal[name]
    if type(fn) == "function" then
        local ok, n = pcall(fn, tier)
        if ok and tonumber(n) and tonumber(n) >= 1 then return math.floor(tonumber(n)) end
    end
    local fallback = isPotion and {3, 3, 4, 5, 5, 5, 5, 5, 7, 7, 7} or {5, 5, 5, 7, 7, 7, 7, 7, 10, 10}
    return fallback[tier]
end
local function allowMachine(name)
    callMethod(state.clients.MachineCmds, "AllowOpen", name)
end
local function upgradeItems(goal)
    if not Config.AutoUpgrade or not healthy("upgrade") then return false end
    if state.upgradeBusy then return true end
    local isPotion = goal.kind:find("potion", 1, true) ~= nil
    local word = isPotion and "potion" or "enchant"
    if not cooldownReady("upgrade:" .. word, Config.UpgradeSeconds) then return false end
    if now() < (state.upgradePausedUntil and state.upgradePausedUntil[word] or 0) then return false end
    local machineName = isPotion and "UpgradePotionsMachine" or "UpgradeEnchantsMachine"
    local net = findChild(ReplicatedStorage, "Network")
    -- Only the bulk remote's arguments are known ({[uid] = upgradesToMake}).
    local remote = findChild(net, machineName .. "_ActivateBulk")
    if not remote then
        if cooldownReady("upgrade:missing:" .. word, 300) then
            log(machineName .. "_ActivateBulk not found in this game version", "WAIT")
        end
        return false
    end
    if not spendAllowed(goal) then return false end
    local data = saveData()
    local stock = data and data.Inventory and data.Inventory[isPotion and "Potion" or "Enchant"]
    if type(stock) ~= "table" then return false end
    -- "Upgrade to N Tier III potions" needs Tier II inputs; collect quests use the
    -- cheapest upgrade (lowest tier).
    local remaining = math.max(1, (goal.required or 0) - (goal.progress or 0))
    local targetTier = goal.kind:find("upgrade", 1, true)
        and tonumber(goal.raw and (isPotion and goal.raw.PotionTier or goal.raw.EnchantTier) or nil)
        or (goal.kind:find("upgrade", 1, true) and numeralToNumber(goal.title)) or nil
    local inputTier = targetTier and targetTier - 1 or nil
    if not inputTier then
        for _, item in pairs(stock) do
            local tier = type(item) == "table" and tonumber(item.tn)
            local per = tier and perTierRequired(isPotion, tier)
            if per and (tonumber(item._am) or 1) >= per and (not inputTier or tier < inputTier) then inputTier = tier end
        end
    end
    local per = inputTier and perTierRequired(isPotion, inputTier)
    if not per then
        if cooldownReady("upgrade:none:" .. word, 90) then
            log("No " .. word .. " stack big enough to upgrade" .. (inputTier and (" (tier " .. inputTier .. ")") or ""), "WAIT")
        end
        return false
    end
    -- Biggest stacks first, so small (often rarer) stacks are left alone.
    local stacks = {}
    for uid, item in pairs(stock) do
        local amount = type(item) == "table" and tonumber(item._am) or 1
        if type(item) == "table" and tonumber(item.tn) == inputTier
            and amount >= math.max(per, Config.UpgradeMinStack) then
            stacks[#stacks+1] = {uid = uid, amount = amount}
        end
    end
    table.sort(stacks, function(a, b) return a.amount > b.amount end)
    local batch, total = {}, 0
    for _, stack in ipairs(stacks) do
        if total >= remaining then break end
        local make = math.min(math.floor(stack.amount / per), remaining - total)
        if make > 0 then
            batch[stack.uid] = make
            total = total + make
        end
    end
    if total == 0 then
        if cooldownReady("upgrade:none:" .. word, 90) then
            log("Not enough tier " .. inputTier .. " " .. word .. "s (" .. per .. " per upgrade)", "WAIT")
        end
        return false
    end
    -- The server only accepts this at the machine: the upgrade machine itself or
    -- the Supercomputer ("SuperMachine") in the World 2-4 spawns.
    local machine = findMachineSpot("upgrade:" .. word, {squash(machineName), "supermachine"},
        {machineName, "SuperMachine"})
    state.upgradeBusy = true
    task.spawn(function()
        local function activate()
            allowMachine("SuperMachine")
            allowMachine(machineName)
            return network(remote.Name, {batch}, true)
        end
        local ok, result, message
        if machine then ok, result, message = quickTrip(machine, activate) else ok, result, message = activate() end
        state.upgradeBusy = false
        state.commandCount = state.commandCount + 1
        if result == "stopped" then return end
        if ok and result ~= false and result ~= "busy" then
            state.upgradeFailStreak = 0
            recordSpend(goal)
            log("Upgraded " .. total .. "x tier " .. inputTier .. " " .. word .. "s", "UPGRADE")
            state.lastSuccessfulAction = now()
            return
        end
        state.upgradeFailStreak = (state.upgradeFailStreak or 0) + 1
        log("Upgrade refused: " .. describe(message or result) .. (machine and "" or "; machine not found on map"), "WAIT")
        if state.upgradeFailStreak >= 3 then
            state.upgradePausedUntil = state.upgradePausedUntil or {}
            state.upgradePausedUntil[word] = now() + 600
            state.upgradeFailStreak = 0
            log("Upgrades paused 10 min after repeated refusals", "SAFEGUARD")
        end
    end)
    return true
end

-- Gold / Rainbow machine: 10 normal pets -> 1 golden, 10 golden -> 1 rainbow
-- (Mastery lowers the 10). GoldMachine_Activate / RainbowMachine_Activate(uid, count).
-- Only pets from the best egg are used, never equipped or shiny ones.
local function bestEggPetIds()
    local egg = findEgg()
    local dir = state.clients.Directory
    local eggDir = egg and dir and type(dir.Eggs) == "table" and dir.Eggs[egg.name]
    if type(eggDir) ~= "table" or type(eggDir.pets) ~= "table" then return nil end
    local ids = {}
    for _, entry in pairs(eggDir.pets) do
        local id = type(entry) == "table" and (entry[1] or entry.id) or entry
        if type(id) == "string" then ids[id] = true end
    end
    return next(ids) and ids or nil
end
local function convertPets(goal)
    if not Config.AutoGoldRainbow or not healthy("convert") then return false end
    if state.convertBusy then return true end
    if not cooldownReady("convert:" .. goal.kind, 6) then return false end
    if not spendAllowed(goal) then return false end
    local data = saveData()
    local pets = data and data.Inventory and data.Inventory.Pet
    local allowed = bestEggPetIds()
    if type(pets) ~= "table" or not allowed then
        if cooldownReady("convert:noegg", 120) then log("Best egg pet list unknown; cannot pick pets to convert", "WAIT") end
        return false
    end
    -- Equipped pets are never converted: both the save list and PetCmds are checked.
    local equipped = {}
    for k, v in pairs(type(data.EquippedPets) == "table" and data.EquippedPets or {}) do
        equipped[tostring(k)] = true
        if type(v) == "string" then equipped[v] = true end
    end
    local okEq, eqPets = callMethod(state.clients.PetCmds, "GetEquipped")
    if okEq and type(eqPets) == "table" then
        for k, v in pairs(eqPets) do
            equipped[tostring(k)] = true
            if type(v) == "table" then
                for _, field in ipairs({"uid", "euid", "_uid"}) do
                    if v[field] then equipped[tostring(v[field])] = true end
                end
            end
        end
    end
    local function required(rainbowStep)
        local perk = rainbowStep and "RainbowReduction" or "GoldReduction"
        local n = 10
        local okPerk, hasPerk = callMethod(state.clients.MasteryCmds, "HasPerk", "Pets", perk)
        if okPerk and hasPerk then
            local okPower, power = callMethod(state.clients.MasteryCmds, "GetPerkPower", "Pets", perk)
            if okPower and tonumber(power) then n = math.max(1, n - math.floor(tonumber(power))) end
        end
        return n
    end
    local function biggestStack(variant, need)
        local best
        for uid, pet in pairs(pets) do
            if type(pet) == "table" and allowed[pet.id] and not pet.sh and not pet._lk
                and not equipped[tostring(uid)] and (tonumber(pet.pt) or 0) == variant
                and (state.convertSkip[tostring(uid)] or 0) < now() then
                local amount = tonumber(pet._am) or 1
                if amount >= need and (not best or amount > best.amount) then
                    best = {uid = uid, id = pet.id, amount = amount}
                end
            end
        end
        return best
    end
    local remaining = math.max(1, (goal.required or 0) - (goal.progress or 0))
    local rainbow = goal.kind == "rainbow"
    local step, stack, count
    local needRainbow, needGold = required(true), required(false)
    if rainbow then
        stack = biggestStack(1, needRainbow)
        if stack then
            step, count = "rainbow", math.min(math.floor(stack.amount / needRainbow), remaining)
        else
            -- Gold stage first: normal best-egg pets -> golden, enough for the rainbows still needed.
            stack = biggestStack(0, needGold)
            if stack then step, count = "gold", math.min(math.floor(stack.amount / needGold), remaining * needRainbow) end
        end
    else
        stack = biggestStack(0, needGold)
        if stack then step, count = "gold", math.min(math.floor(stack.amount / needGold), remaining) end
    end
    if not stack then
        if cooldownReady("convert:none:" .. goal.kind, 60) then
            log("Need " .. needGold .. " normal (or " .. needRainbow .. " golden) best-egg pets of one kind; hatching more", "WAIT")
        end
        return false
    end
    local machineName = step == "rainbow" and "RainbowMachine" or "GoldMachine"
    local remoteName = machineName .. "_Activate"
    local function machineFailed(reason)
        state.convertFailStreak = state.convertFailStreak + 1
        log(machineName .. ": " .. reason, "WAIT")
        if state.convertFailStreak >= 3 then
            -- Machine route not working: allow the Golden-eggs fallback for 10 minutes.
            state.convertFailStreak = 0
            state.goldMachineFailedUntil = now() + 600
            log("Gold/rainbow machine not working; golden eggs may be used for 10 min", "SAFEGUARD")
        end
        return false
    end
    if not findChild(findChild(ReplicatedStorage, "Network"), remoteName) then
        return machineFailed(remoteName .. " not found")
    end
    local machine = findMachineSpot("machine:" .. machineName, {squash(machineName), "supermachine"},
        {machineName, "SuperMachine"})
    if not machine then
        -- Calling it from far away is always refused.
        if cooldownReady("convert:nomachine:" .. machineName, 60) then
            return machineFailed("machine not found on the map")
        end
        return false
    end
    state.convertBusy = true
    task.spawn(function()
        local function activate()
            allowMachine("SuperMachine")
            allowMachine(machineName)
            return network(remoteName, {stack.uid, count}, true)
        end
        local ok, result, message = quickTrip(machine, activate)
        state.convertBusy = false
        state.commandCount = state.commandCount + 1
        if result == "stopped" or result == "busy" then return end
        if ok and result ~= false then
            state.convertFailStreak = 0
            -- The gold stage of a rainbow quest does not move that quest yet.
            if not (rainbow and step == "gold") then recordSpend(goal) end
            log("Made " .. count .. " " .. (step == "rainbow" and "rainbow" or "golden") .. " " .. tostring(stack.id), "CONVERT")
            state.lastSuccessfulAction = now()
        else
            state.convertSkip[tostring(stack.uid)] = now() + 300
            machineFailed("refused (" .. describe(message or result) .. ")")
        end
    end)
    return true
end

-- Quests that need the character in a particular place; only one runs per tick.
local locationKinds = {
    farm = true, diamond = true, minichest = true, safe = true,
    coinjar = true, comet = true, pinata = true, luckyblock = true,
}
local function needsLocation(goal)
    if locationKinds[goal.kind] then return true end
    -- Vending teleports to the machine; upgrades do not move the character.
    return false
end
local function performGoal(goal, allowMove)
    if not goal then return false end
    if allowMove == nil then allowMove = true end
    local feature = goalFeature[goal.kind] or (itemTypes[goal.kind] and "spawn-" .. goal.kind)
    if feature and not healthy(feature) then return false end
    if goal.kind == "hatch" or goal.kind == "hatch_rare" then return hatch() end
    if goal.kind == "golden" or goal.kind == "rainbow" then
        -- Convert what we have, and keep hatching the best egg for more pets
        -- (golden pets directly when "Golden eggs for gold/rainbow quests" is on).
        local converted = convertPets(goal)
        local hatched = Config.AutoHatch and hatch() or false
        return converted or hatched
    end
    if goal.kind == "fruit" or goal.kind == "potion" or goal.kind == "flag" then
        return consume(goal)
    end
    if goal.kind == "upgrade_potion" or goal.kind == "upgrade_enchant" then
        return upgradeItems(goal)
    end
    if goal.kind == "collect_potion" or goal.kind == "collect_enchant" then
        local upgraded = upgradeItems(goal)
        if upgraded or not allowMove or not healthy("vending") then return upgraded end
        return vendingForGoal(goal, allowMove)
    end
    if goal.kind == "zone" then tryAdvanceWorld(); return true end
    if goal.kind == "rebirth" then tryAdvanceWorld(); return true end
    if itemTypes[goal.kind] then return spawnQuestObject(goal, allowMove) end
    if goal.kind == "farm" or goal.kind == "diamond" or goal.kind == "minichest" or goal.kind == "safe" then
        return farm(goal, allowMove)
    end
    return false
end

local function stop()
    state.running = false
    pcall(applyHatchSettings, true)
    state.shutdown = true
    Config.Enabled = false
    state.status = "STOPPED"
    state.generations = state.generations + 1
    for _, conn in ipairs(state.connections) do pcall(function() conn:Disconnect() end) end
    state.connections = {}
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    if state.gui then pcall(function() state.gui:Destroy() end) end
    environment.RankPilot = nil
    log("Controller stopped and disconnected", "SYSTEM")
end
local function pause()
    Config.Enabled = false
    state.running = false
    pcall(applyHatchSettings, true)
    state.status = "PAUSED"
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    persist()
    log("Paused", "SYSTEM")
end
local function recheck()
    state.failures = {}
    state.blocked = {}
    state.questWatch = {}
    saveCache = nil
    state.bulkUnsupported = false
    local found = refreshClients()
    local okInspect, readable = pcall(inspectState)
    if found and okInspect and readable and not state.running then state.status = "PAUSED: press START" end
    log("Capabilities reloaded and temporary blocks cleared", "SYSTEM")
end
local function run()
    if state.shutdown then return end
    if not refreshClients() then
        state.status = "No readable Save interface"
        log("Cannot start: PS99 Save.Get not available in this client", "ERROR")
        return
    end
    state.running = true
    Config.Enabled = true
    state.lastProgressAt = now()
    log("Rank controller enabled", "SYSTEM")
    persist()
end

local function getReport()
    local c = state.clients
    local keys = {"Save", "QuestCmds", "ZoneCmds", "RankCmds", "PetCmds", "EggCmds", "PlayerPet", "BreakableFrontend", "ZonesUtil", "RanksUtil", "Directory", "Balancing",
        "PotionCmds", "FruitCmds", "ZoneFlagCmds", "RebirthCmds", "InventoryCmds"}
    local net = findChild(ReplicatedStorage, "Network")
    local upgradeRemotes = {}
    if net then
        for _, remote in ipairs(net:GetChildren()) do
            local name = squash(remote.Name)
            for _, word in ipairs({"upgrade", "computer", "potion", "enchant", "coinjar", "comet"}) do
                if name:find(word, 1, true) then
                    upgradeRemotes[#upgradeRemotes+1] = remote.Name .. "(" .. remote.ClassName:gsub("Remote", "") .. ")"
                    break
                end
            end
        end
    end
    -- Client modules for the Supercomputer / upgrades, with their function names.
    local clientModules = {}
    local clientFolder = findChild(findChild(ReplicatedStorage, "Library"), "Client")
    for _, node in ipairs(clientFolder and clientFolder:GetChildren() or {}) do
        local name = squash(node.Name)
        if node:IsA("ModuleScript") and (name:find("computer", 1, true) or name:find("upgrade", 1, true)) then
            local fns = {}
            for key, value in pairs(tryModule(node) or {}) do
                if type(value) == "function" then fns[#fns+1] = tostring(key) end
            end
            table.sort(fns)
            clientModules[#clientModules+1] = node.Name .. "{" .. table.concat(fns, ",") .. "}"
        end
    end
    local report = {"RankPilot DZ-enhanced capability report", "Rank: " .. describe(state.rank),
        "RankCmds.GetMaxRank value (diagnostic): " .. describe(state.maxRank), "Area: " .. state.area,
        "Status: " .. state.status, "PlaceId: " .. describe(game.PlaceId),
        "Breakable interface: " .. state.lastFarmInterface,
        "Goals: " .. #state.goals, "Controllers: " .. describe(state.chosen),
        "Upgrade remotes: " .. (#upgradeRemotes > 0 and table.concat(upgradeRemotes, ", ") or "none"),
        "Upgrade modules: " .. (#clientModules > 0 and table.concat(clientModules, " ") or "none")}
    for kind, spec in pairs(itemTypes) do
        local remote = findItemRemote(spec.word)
        table.insert(report, "Item remote " .. kind .. ": " .. (remote and remote.Name or "none"))
    end
    for _, spec in ipairs(magnetSpecs) do
        local remote = findMagnetRemote(spec)
        table.insert(report, "Magnet remote " .. spec.folder .. ": " .. (remote and remote.Name or "none"))
    end
    local eggScripts = {}
    local scriptsRoot = LocalPlayer:FindFirstChild("PlayerScripts")
    for _, node in ipairs(scriptsRoot and scriptsRoot:GetDescendants() or {}) do
        if (node:IsA("LocalScript") or node:IsA("ModuleScript")) and node.Name:lower():find("egg", 1, true) then
            eggScripts[#eggScripts+1] = node.Name
        end
    end
    table.insert(report, "Egg scripts: " .. (#eggScripts > 0 and table.concat(eggScripts, ", ") or "none"))
    table.insert(report, "Egg animation patched: " .. tostring(state.eggAnimPatched == true)
        .. " | hatch amount range " .. state.hatchLo .. "-" .. state.hatchHi)
    table.insert(report, "Hatch settings: charged=" .. describe(hatchOptionEnabled("CHARGED"))
        .. " golden=" .. describe(hatchOptionEnabled("GOLDEN")) .. " (HatchingCmds "
        .. (type(c.HatchingCmds) == "table" and "present" or "missing") .. ")")
    local egg = findEgg()
    table.insert(report, "Best egg: " .. (egg and (tostring(egg.number) .. " " .. tostring(egg.name)) or "not found"))
    for _,k in ipairs(keys) do
        table.insert(report, k .. ": " .. (type(c[k]) == "table" and "present" or "missing"))
    end
    for _,g in ipairs(state.goals) do
        table.insert(report, "QUEST [" .. g.key .. "][" .. g.kind .. "]: " .. g.title .. " (" .. g.progress .. "/" .. g.required .. ")")
    end
    for i=1,math.min(#state.logs, 15) do table.insert(report, state.logs[i]) end
    return table.concat(report, "\n")
end

local ui = {}
local function create(class, properties, parent)
    local obj = Instance.new(class)
    for k,v in pairs(properties or {}) do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end
local PALETTE = {
    base = Color3.fromRGB(17, 21, 31), panel = Color3.fromRGB(27, 34, 47),
    card = Color3.fromRGB(33, 42, 57), border = Color3.fromRGB(59, 73, 94),
    accent = Color3.fromRGB(80, 176, 245), green = Color3.fromRGB(90, 212, 160),
    white = Color3.fromRGB(232, 242, 250), gray = Color3.fromRGB(166, 185, 204),
}
local function addCorner(node, radius)
    create("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, node)
end
local function addStroke(node)
    create("UIStroke", {Color = PALETTE.border, Thickness = 1, Transparency = 0.3}, node)
end
local function textLabel(parent, txt, y, height, size, color)
    return create("TextLabel", {Name = "Label", BackgroundTransparency = 1,
        Text = txt, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1,-24,0,height),
        TextColor3 = color or PALETTE.white, Font = Enum.Font.Gotham,
        TextSize = size or 13, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd}, parent)
end
local function button(parent, txt, x, y, w, h, color, fn)
    local b = create("TextButton", {Text = txt, BackgroundColor3 = color or PALETTE.card,
        TextColor3 = PALETTE.white, BorderSizePixel = 0, Font = Enum.Font.GothamBold,
        TextSize = 12, Position = UDim2.fromOffset(x,y), Size = UDim2.fromOffset(w,h), AutoButtonColor = true}, parent)
    addCorner(b,7)
    table.insert(state.connections, b.MouseButton1Click:Connect(fn))
    return b
end
local function buildUI()
    local parent = CoreGui
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then parent = result end
    end
    local gui = create("ScreenGui", {Name = "RankPilotUI", ResetOnSpawn = false,
        DisplayOrder = 510, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    local parentOK = pcall(function() gui.Parent = parent end)
    if not parentOK then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    state.gui = gui
    local outer = create("Frame", {Name="Main", BackgroundColor3=PALETTE.base,
        BorderSizePixel=0, Position=UDim2.fromScale(.03,.14), Size=UDim2.fromOffset(400,553)}, gui)
    addCorner(outer,12); addStroke(outer)
    local title = textLabel(outer, "RANKPILOT  |  PS99", 10, 26, 17, PALETTE.accent)
    title.Font = Enum.Font.GothamBold
    textLabel(outer, "Advanced rank progression  |  no external loader", 36, 18, 10, PALETTE.gray)
    local status = textLabel(outer,"Status: preparing",58,27,12,PALETTE.green)
    local rank = textLabel(outer,"Rank: ?  |  Stars: ?  |  Max: ?",82,23,12,PALETTE.white)
    local zone = textLabel(outer,"Area: ?",105,23,12,PALETTE.gray)
    local goal = textLabel(outer,"Quest: None",127,37,11,PALETTE.white)
    goal.TextWrapped = true; goal.TextTruncate = Enum.TextTruncate.None
    local start = button(outer,"START",12,169,118,34,PALETTE.green,function()
        if state.running then pause() else run() end
    end)
    button(outer,"RECHECK",140,169,113,34,PALETTE.card,recheck)
    button(outer,"STOP / UNLOAD",262,169,125,34,PALETTE.card,stop)
    textLabel(outer,"FEATURES",211,20,11,PALETTE.accent)
    local optionFrame = create("ScrollingFrame", {Name="Options", BackgroundColor3=PALETTE.panel,
        BorderSizePixel=0, Position=UDim2.fromOffset(12,237),Size=UDim2.fromOffset(376,164),
        ScrollBarThickness=3,CanvasSize=UDim2.fromOffset(0,#optionOrder*31+8)},outer)
    addCorner(optionFrame,7)
    for i, pair in ipairs(optionOrder) do
        local field, label = pair[1], pair[2]
        local toggle = button(optionFrame,"",8,(i-1)*31+5,355,28,PALETTE.card,function() end)
        local function refreshToggle()
            toggle.Text = (Config[field] and "[ON]   " or "[OFF]  ") .. label
            toggle.TextColor3 = Config[field] and PALETTE.green or PALETTE.gray
        end
        -- Replace the temporary handler with the actual state transition.
        local oldConnection = state.connections[#state.connections]
        if oldConnection then oldConnection:Disconnect() end
        state.connections[#state.connections] = nil
        table.insert(state.connections, toggle.MouseButton1Click:Connect(function()
            Config[field] = not Config[field]
            if field == "RenderOff" and not Config[field] then
                pcall(function() RunService:Set3dRenderingEnabled(true) end)
            end
            refreshToggle(); persist()
        end))
        refreshToggle()
    end
    local logs = textLabel(outer,"No actions yet",409,91,10,PALETTE.gray)
    logs.TextYAlignment=Enum.TextYAlignment.Top
    logs.TextWrapped = true
    logs.TextTruncate = Enum.TextTruncate.None
    button(outer,"COPY REPORT",12,505,180,33,PALETTE.card,function()
        local report = getReport()
        if type(setclipboard) == "function" then
            local ok = pcall(setclipboard,report)
            log(ok and "Report copied" or "Clipboard unavailable", "SYSTEM")
        else
            print(report)
            log("No clipboard API; report printed to executor console", "SYSTEM")
        end
    end)
    local fps = textLabel(outer,"Requests: 0",510,24,11,PALETTE.gray)
    fps.Position = UDim2.fromOffset(204,510)
    fps.Size = UDim2.fromOffset(184,24)
    ui.status = status; ui.rank = rank; ui.zone = zone; ui.goal = goal
    ui.logs = logs; ui.fps = fps; ui.start = start
    local dragging, origin, initial = false, nil, nil
    table.insert(state.connections, title.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging = true; origin=input.Position; initial=outer.Position
        end
    end))
    table.insert(state.connections, title.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end))
    table.insert(state.connections, game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            local delta=input.Position-origin
            outer.Position=UDim2.new(initial.X.Scale,initial.X.Offset+delta.X,
                initial.Y.Scale,initial.Y.Offset+delta.Y)
        end
    end))
end
local function renderUI()
    if state.shutdown or not ui.status then return end
    ui.status.Text="Status: " .. state.status
    ui.rank.Text="Rank: "..describe(state.rank).."  |  Stars: "..describe(state.starCount).."  |  Max: "..describe(state.maxRank)
    ui.zone.Text="Area: "..state.area
    local questText = state.chosen
    if not state.running then
        -- While paused, list the active quests so the panel is still informative.
        local lines = {}
        for i = 1, math.min(#state.goals, 3) do
            local g = state.goals[i]
            lines[#lines+1] = string.format("%s (%s/%s)", g.title, describe(g.progress), describe(g.required))
        end
        questText = #lines > 0 and table.concat(lines, "; ") or "None detected"
    end
    ui.goal.Text="Quest: "..questText
    local recent = {}
    for i = 1, math.min(#state.logs, 7) do recent[i] = state.logs[i] end
    ui.logs.Text=table.concat(recent,"\n")
    ui.fps.Text="Requests: "..state.commandCount.." | Deferred: "..state.blockedCount
    ui.start.Text=state.running and "PAUSE" or "START"
end

local function mainLoop(generation)
    while not state.shutdown and generation == state.generations do
        if state.running then
            local ok, errorMessage=pcall(function()
                if not inspectState() then return end
                local target = tonumber(Config.TargetRank) or 0
                if target > 0 and type(state.rank)=="number" and state.rank >= target then
                    pause()
                    state.status = "TARGET RANK REACHED"
                    return
                end
                if Config.RenderOff then pcall(function() RunService:Set3dRenderingEnabled(false) end) end
                if Config.AutoClaimRankRewards and healthy("claim") then claimRankRewards() end
                if Config.AutoWorld and healthy("zone") then tryAdvanceWorld() end
                extraProgression()
                claimFreeGift()
                superMagnet()
                autoUltimate()
                if Config.AutoRank then
                    local ranked = rankGoals()
                    local active = {}
                    for i = 1, (Config.MultiQuest and #ranked or math.min(1, #ranked)) do active[i] = ranked[i] end
                    state.activeGoals = active
                    pcall(applyHatchSettings)
                    if #ranked > 0 then
                        -- One quest that needs the character somewhere (farm / hatch /
                        -- vending) plus every quest that can run from anywhere.
                        local moverUsed, active = false, {}
                        local limit = Config.MultiQuest and #ranked or 1
                        for i = 1, limit do
                            local g = ranked[i]
                            local moves = needsLocation(g)
                            do
                                -- Quests after the one that owns the character still act
                                -- where it stands (farm nearby, upgrade, consume).
                                local performed, why = performGoal(g, not moverUsed)
                                -- A location quest that could not act (no targets, no egg)
                                -- hands the character to the next one.
                                if moves and (performed or why == "moving" or why == "waiting") then moverUsed = true end
                                active[#active+1] = g.title .. " [" .. g.kind .. "]"
                                local watch = state.questWatch[g.identity]
                                if watch and now()-watch.changedAt > Config.StallSeconds then
                                    blockGoal(g, Config.BlockedQuestSeconds, "quest made no observed progress")
                                    watch.changedAt = now()
                                end
                            end
                        end
                        if Config.AutoFarm then farm(nil, not moverUsed) end
                        state.chosen = table.concat(active, "; ")
                        state.status = "Running " .. #active .. " quest(s)"
                    else
                        state.chosen="No supported quest ready"
                        state.status="Waiting / fallback farming"
                        if Config.AutoFarm then farm(nil) end
                    end
                else
                    state.activeGoals = {}
                    pcall(applyHatchSettings)
                    state.chosen="Quest planner disabled"
                    state.status="Farming"
                    if Config.AutoFarm then farm(nil) end
                end
            end)
            if not ok then failFeature("controller",errorMessage) end
        elseif now() - state.lastRefresh >= Config.SaveRefreshSeconds then
            -- Keep rank / stars / area / quests current even while paused.
            state.lastRefresh = now()
            pcall(inspectState)
        end
        pcall(renderUI)
        task.wait(Config.FastMode and Config.FastTickSeconds or Config.TickSeconds)
    end
end

-- Remove panels left behind by earlier (possibly crashed) runs.
local guiContainers = {CoreGui, LocalPlayer:FindFirstChildOfClass("PlayerGui")}
if type(gethui) == "function" then
    local okHui, hui = pcall(gethui)
    if okHui then table.insert(guiContainers, hui) end
end
for _, container in pairs(guiContainers) do
    if typeof(container) == "Instance" then
        pcall(function()
            for _, old in ipairs(container:GetChildren()) do
                if old.Name == "RankPilotUI" then old:Destroy() end
            end
        end)
    end
end

loadSettings()
-- Draw the panel first so something is always visible, even if loading the game modules stalls.
local uiOK, uiErr = pcall(buildUI)
if not uiOK then warn("[RankPilot] UI build error: " .. describe(uiErr)) end
pcall(function()
    local VirtualUser = game:GetService("VirtualUser")
    table.insert(state.connections, LocalPlayer.Idled:Connect(function()
        if not Config.AntiAFK or state.shutdown then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
end)
state.status = "Loading game modules..."
pcall(renderUI)
task.spawn(function()
    local loaded, ok = pcall(refreshClients)
    ok = loaded and ok
    if ok then
        pcall(inspectState)
        -- Not running yet, so both options are wanted OFF (e.g. left on by a disconnect).
        pcall(applyHatchSettings, true)
        log("Readable PS99 save module detected")
    else
        log("PS99 save module unavailable. Hub will remain safely paused.","WAIT")
    end
    if not state.running then
        state.status = ok and "PAUSED: press START" or "Save module not found: press RECHECK"
    end
end)
state.generations=state.generations+1
local threadGeneration=state.generations
task.spawn(function() mainLoop(threadGeneration) end)
-- Fast loop: tapping and clicking through the egg prompt need more than 4 ticks a second.
task.spawn(function()
    while not state.shutdown and threadGeneration == state.generations do
        if state.running then
            pcall(autoTap)
            pcall(clickThroughEggPrompt)
        end
        task.wait(math.max(0.05, Config.TapSeconds))
    end
end)

environment.RankPilot = {
    Version="2.10-DZ-research",
    Config=Config,
    Status=state,
    Start=run,
    Pause=pause,
    Recheck=recheck,
    Stop=stop,
    GetReport=getReport,
    GetGoals=function() return state.goals end,
}
log("DZ-informed rank hub ready; does not import untrusted DZ UI, webhook or serverhop code.","SYSTEM")
