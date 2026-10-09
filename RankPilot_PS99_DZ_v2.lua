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
    AutoEventItems = false,     -- Explicit opt-in for consumable comets/jars/etc.
    AutoVending = false,        -- Opt-in: up to 5% of available coins per purchase
    AutoClaimRankRewards = true,
    AutoRebirth = false,        -- Intentional opt-in only
    AutoEggSlots = false,       -- Opt-in: check available diamonds and verified bundle price
    AutoPetSlots = false,       -- Opt-in: check rank cap and verified diamond price
    AutoEquipBest = true,       -- From DZ Hub PetCmds.EquipBest
    AutoFreeGifts = false,      -- Opt-in: verified free-gift timestamps, no blind claiming
    RenderOff = false,
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
    ConsumableSeconds = 6,
    SpawnItemSeconds = 14,
    StallSeconds = 150,
    BlockedQuestSeconds = 75,
    MaxErrorsPerFeature = 5,
    MaxHatchBatch = 30,
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
    {"AutoClaimRankRewards", "Claim rank rewards"},
    {"AutoRebirth", "Allow rebirth"},
    {"AutoEquipBest", "Keep best pets equipped"},
    {"AutoEggSlots", "Buy affordable egg slots"},
    {"AutoPetSlots", "Buy affordable pet slots"},
    {"AutoFreeGifts", "Claim ready free gifts"},
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
    lastPetAssign = 0, lastAssignedTarget = nil, lastEquip = 0,
    lastSlots = 0, lastGifts = 0, lastFarmInterface = "none",
    attempts = {farm = 0, hatch = 0, zone = 0, consumable = 0},
    lastPosition = nil, generations = 0, connections = {}, gui = nil,
    configFile = "RankPilot_v1_settings.json", settingsLoaded = false,
    activeWorld = nil, currentTarget = nil, selectedGoalKey = nil, scanCursor = 1,
    commandCount = 0, blockedCount = 0,
}

local function now() return os.clock() end
local function safe(fn, ...)
    if type(fn) ~= "function" then return false, "function unavailable" end
    return pcall(fn, ...)
end
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
local function guarded(feature, fn)
    if not healthy(feature) then return false end
    local ok, value = pcall(fn)
    if not ok then failFeature(feature, value); return false end
    return true, value
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
        "MapCmds", "CurrencyCmds", "MachineCmds", "PlayerPet", "BreakableFrontend"}) do
        if not c[name] then c[name] = tryModule(findChild(clientFolder, name)) end
    end
    c.Network = c.Network or tryModule(findChild(clientFolder, "Network"))
    c.ZonesUtil = tryModule(findChild(findChild(lib, "Util"), "ZonesUtil"))
    c.RanksUtil = tryModule(findChild(findChild(lib, "Util"), "RanksUtil"))
    c.Directory = tryModule(findChild(lib, "Directory"))
    c.Balancing = tryModule(findChild(lib, "Balancing"))
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
    elseif remote and not invoke and remote:IsA("RemoteEvent") then
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

local function loadSettings()
    if not (type(isfile) == "function" and type(readfile) == "function") then return end
    local ok, data = pcall(function()
        if not isfile(state.configFile) then return nil end
        return HttpService:JSONDecode(readfile(state.configFile))
    end)
    if ok and type(data) == "table" then
        for key, value in pairs(data) do
            if Config[key] ~= nil and type(Config[key]) == type(value) then
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
        local copy = {}
        for k, v in pairs(Config) do copy[k] = v end
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
    if v:find("hatch") then return "hatch" end
    if v:find("golden") or v:find("rainbow") then return "convert" end
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
    hatch = 90, fruit = 88, potion = 86, flag = 74,
    zone = 76, rebirth = 12, coinjar = 56, comet = 56,
    pinata = 54, luckyblock = 54, convert = 4,
    collect_potion = 67, collect_enchant = 67,
    upgrade_potion = 2, upgrade_enchant = 2, unhandled = -200,
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
local function eligible(goal)
    if (state.blocked[goal.identity] or 0) > now() then return false end
    local needed = {
        hatch = Config.AutoHatch, farm = Config.AutoFarm, diamond = Config.AutoFarm,
        collect_potion = Config.AutoVending, collect_enchant = Config.AutoVending,
        minichest = Config.AutoFarm, safe = Config.AutoFarm,
        fruit = Config.AutoConsumables, potion = Config.AutoConsumables,
        flag = Config.AutoConsumables, zone = Config.AutoWorld,
        coinjar = Config.AutoEventItems, comet = Config.AutoEventItems,
        pinata = Config.AutoEventItems, luckyblock = Config.AutoEventItems,
        rebirth = Config.AutoRebirth,
    }
    return needed[goal.kind] == true
end
local function chooseGoal()
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
    return list[1] and list[1].g or nil
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
    if modern ~= nil then
        state.lastFarmInterface = "DZ BreakableFrontend"
        return modern
    end
    state.lastFarmInterface = "Legacy Workspace"
    return legacyBreakables(kind)
end

local function aimPetsAt(target)
    if now()-state.lastPetAssign < Config.PetAssignSeconds
        and state.lastAssignedTarget == tostring(target.uid) then return false end
    local pp = state.clients.PlayerPet
    if type(pp) == "table" and type(pp.GetByPlayer) == "function" and target.model then
        local ok, pets = callMethod(pp, "GetByPlayer", LocalPlayer)
        if ok and type(pets) == "table" then
            local count = 0
            for _, pet in pairs(pets) do
                if type(pet) == "table" and type(pet.SetTarget) == "function" then
                    pcall(pet.SetTarget, pet, target.model)
                    count = count + 1
                    if count >= Config.MaxPetsPerTick then break end
                end
            end
            if count > 0 then
                state.lastPetAssign = now()
                state.lastAssignedTarget = tostring(target.uid)
                return true
            end
        end
    end
    local ok, equipped = callMethod(state.clients.PetCmds, "GetEquipped")
    if ok and type(equipped) == "table" then
        local count = 0
        for petId in pairs(equipped) do
            if network("Breakables_JoinPet", {target.uid, petId}, false) then
                count = count + 1
            end
            if count >= Config.MaxPetsPerTick then break end
        end
        state.lastPetAssign = now()
        state.lastAssignedTarget = tostring(target.uid)
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
local function farm(goal)
    if not healthy("farm") then return false end
    if now() - state.lastFarm < Config.FarmActionSeconds then return false end
    state.lastFarm = now()
    if not currentRoot() then return false end
    local kind = goal and goal.kind or "farm"
    local targets = visibleTargetCandidates(kind)
    if #targets == 0 then
        local area = getZoneInfo()
        placeInZone(area)
        if cooldownReady("noTargets:"..kind, 45) then
            log("No matching targets ("..kind..") in active zone via "..state.lastFarmInterface,"WAIT")
        end
        return false
    end
    local target = targets[1]
    aimPetsAt(target)
    local ok = damageBreakable(target)
    state.currentTarget = tostring(target.uid)
    if not ok then
        failFeature("farm", "No compatible breakables interface for "..state.lastFarmInterface)
        return false
    end
    state.attempts.farm=state.attempts.farm+1
    state.lastSuccessfulAction = now() -- command accepted, NOT verified quest credit
    return true
end
local function findEgg()
    local dir = state.clients.Directory
    local data = saveData()
    local ownedEggs = dir and dir.Eggs
    -- DZ Hub derives the unlocked egg from this account's save, not a fixed egg number.
    if type(ownedEggs) == "table" and type(data) == "table" then
        local worldNo = tonumber(data.RecentWorld)
        local maxEgg = tonumber(data.MaximumAvailableEgg)
        if worldNo and maxEgg then
            local chosen
            for _, e in pairs(ownedEggs) do
                if type(e) == "table" and type(e._id) == "string"
                    and tonumber(e.worldNumber) == worldNo then
                    local num = tonumber(e.eggNumber)
                    if num and num <= maxEgg and (not chosen or num > chosen.number) then
                        chosen = {number=num, name=e._id, point=nil, fromDirectory=true}
                    end
                end
            end
            if chosen then
                -- A loaded capsule provides a real position when proximity is required.
                local things=findChild(Workspace,"__THINGS")
                local eggs=findChild(things,"Eggs")
                if eggs then
                    for _,capsule in ipairs(eggs:GetDescendants()) do
                        local number=tonumber(capsule.Name:match("^(%d+)%s*%-%s*Egg Capsule"))
                        if number==chosen.number and (capsule:IsA("Model") or capsule:IsA("BasePart")) then
                            local okP,pivot=pcall(capsule.GetPivot,capsule)
                            if okP and typeof(pivot)=="CFrame" then
                                chosen.capsuleCFrame=pivot
                                break
                            end
                        end
                    end
                end
                return chosen
            end
        end
    end
    -- Old capsule method remains as a fallback for client builds without the directory.
    local things = findChild(Workspace, "__THINGS")
    local eggs = findChild(things, "Eggs")
    local main = findChild(eggs, "Main")
    if not main then return nil end
    local available = {}
    for _, obj in ipairs(main:GetChildren()) do
        local number = tonumber(obj.Name:match("(%d+)"))
        local hud = obj:FindFirstChild("PriceHUD")
        local unlocked = hud and hud:FindFirstChild("PriceHUDAvailable")
        local point = hud and hud:IsA("BasePart") and hud or obj:FindFirstChildWhichIsA("BasePart", true)
        if number and unlocked and point then
            available[#available+1]={number=number,point=point}
        end
    end
    table.sort(available,function(a,b) return a.number>b.number end)
    local chosen = available[1]
    if not chosen then return nil end
    local util=tryModule(findChild(findChild(findChild(ReplicatedStorage,"Library"),"Util"),"EggsUtil"))
    local ok, name=callMethod(util,"GetIdByNumber",chosen.number)
    if not ok or type(name)~="string" then return nil end
    chosen.name=name
    return chosen
end
local function hatch()
    if now()-state.lastHatch < Config.HatchActionSeconds then return false end
    state.lastHatch=now()
    local egg=findEgg()
    if not egg then
        if cooldownReady("noEgg",40) then log("No egg confirmed as unlocked", "WAIT") end
        return false
    end
    local root=currentRoot()
    if not root then return false end
    if egg.point and (root.Position-egg.point.Position).Magnitude>17 then
        root.CFrame=egg.point.CFrame*CFrame.new(0,0,-5)
        return false
    end
    if egg.capsuleCFrame and (root.Position-egg.capsuleCFrame.Position).Magnitude>35 then
        root.CFrame=egg.capsuleCFrame+Vector3.new(0,4,0)
        return false
    end
    local ok, cap=callMethod(state.clients.EggCmds,"GetMaxHatch")
    if not ok or not tonumber(cap) then ok,cap=callMethod(state.clients.EggCmds,"GetMaxHatch",egg.name) end
    if not ok or not tonumber(cap) then
        if cooldownReady("hatch:noCap",55) then log("No verified egg hatch cap", "WAIT") end
        return false
    end
    local count=math.max(1,math.min(math.floor(tonumber(cap)),Config.MaxHatchBatch))
    local success,result
    if state.clients.EggCmds and type(state.clients.EggCmds.RequestPurchase)=="function" then
        success,result=callMethod(state.clients.EggCmds,"RequestPurchase",egg.name,count)
    else
        success,result=network("Eggs_RequestPurchase",{egg.name,count},true)
    end
    if not success or result==false then
        if cooldownReady("hatchRejected",25) then
            log("Hatching refused (currency, proximity or interface); egg="..egg.name,"WAIT")
        end
        return false
    end
    state.attempts.hatch=state.attempts.hatch+1
    state.lastSuccessfulAction=now()
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
        local ok, result = callMethod(state.clients.ZoneFlagCmds, "Consume", flag.id, flag.uid)
        if ok and result ~= false then state.lastSuccessfulAction = now(); return true end
        failFeature("flag", result)
    end
    return false
end
-- Vending collection automation is enabled only if the historical machine
-- method, its price directory and the player's balance are all readable.
-- This avoids charging an unknown amount for unverified stock.
local function vendingForGoal(goal)
    if not Config.AutoVending then return false end
    if not cooldownReady("vending:scan", 8) then return false end
    local data = saveData()
    if not data or type(data.VendingStocks) ~= "table" then return false end
    local machineCmds = state.clients.MachineCmds
    if not machineCmds then return false end
    local lib = findChild(ReplicatedStorage, "Library")
    local directory = findChild(lib, "Directory")
    local prices = tryModule(findChild(directory, "VendingMachines"))
    local ok, coinBalance = callMethod(state.clients.CurrencyCmds, "Get", "Coins")
    if not ok or type(coinBalance) ~= "number" or coinBalance <= 0 or not prices then
        if cooldownReady("vending:unknown", 60) then
            log("Vending deferred: price or coin balance unavailable", "WAIT")
        end
        return false
    end
    local itemKind = goal.kind == "collect_potion" and "potion" or "enchant"
    for machineName, stock in pairs(data.VendingStocks) do
        if type(machineName)=="string" and machineName:lower():find(itemKind, 1, true)
            and type(stock)=="number" and stock > 0 then
            local priceData = prices[machineName]
            local price = priceData and tonumber(priceData.CurrencyCost)
            local canOwn, owned = callMethod(machineCmds,"Owns",machineName)
            local canUse, allowed = callMethod(machineCmds,"IsAllowedToOpen",machineName)
            local amount = math.min(3,math.floor(stock))
            if price and price > 0 and price*amount <= coinBalance*.05
                and canOwn and owned and canUse and allowed then
                local node = nil
                for _,root in ipairs(mapRoots()) do
                    if root then node = root:FindFirstChild(machineName,true) end
                    if node then break end
                end
                local indicator = node and (node:FindFirstChild("Arrow",true) or node:FindFirstChild("arrowPivot",true))
                if indicator and indicator:IsA("BasePart") then
                    local root = currentRoot()
                    if not root then return false end
                    if (root.Position-indicator.Position).Magnitude > 12 then
                        root.CFrame=indicator.CFrame+Vector3.new(0,4,0)
                        return false
                    end
                    return attemptNetwork("vending", "VendingMachines_Purchase",
                        {machineName,amount},true,9)
                end
            end
        end
    end
    return false
end

local itemTypes = {
    coinjar = {match = "Coin Jar", remote = "CoinJar_Spawn"},
    comet = {match = "Comet", remote = "Comet_Spawn"},
    pinata = {match = "Pinata", remote = nil}, -- unverified: do not guess a remote
    luckyblock = {match = "Lucky Block", remote = nil}, -- unverified: do not guess a remote
}
local function spawnQuestObject(goal)
    if now() - state.lastEventItem < Config.SpawnItemSeconds then return false end
    state.lastEventItem = now()
    local spec = itemTypes[goal.kind]
    if not spec then return false end
    local objects = visibleTargetCandidates(goal.kind)
    if #objects > 0 then return farm(goal) end
    if not spec.remote then
        if cooldownReady("unverified:" .. goal.kind, 90) then
            log("No verified spawn interface for " .. goal.kind .. "; will attack existing objects only", "WAIT")
        end
        return false
    end
    if not placeInZone(getZoneInfo()) then return false end
    local item = getInventoryEntry("Misc", spec.match)
    if not item then
        if cooldownReady("missing:" .. goal.kind, 60) then log("Missing " .. spec.match .. " inventory item", "WAIT") end
        return false
    end
    return attemptNetwork("spawn-" .. goal.kind, spec.remote, {item.uid}, true, Config.SpawnItemSeconds)
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
    local ok,result=callMethod(state.clients.PetCmds,"EquipBest")
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
    collect_potion = "vending", collect_enchant = "vending",
    zone = "zone", rebirth = "rebirth",
}
local function performGoal(goal)
    if not goal then return false end
    local feature = goalFeature[goal.kind] or (itemTypes[goal.kind] and "spawn-" .. goal.kind)
    if feature and not healthy(feature) then return false end
    if goal.kind == "hatch" then return hatch() end
    if goal.kind == "fruit" or goal.kind == "potion" or goal.kind == "flag" then
        return consume(goal)
    end
    if goal.kind == "collect_potion" or goal.kind == "collect_enchant" then
        return vendingForGoal(goal)
    end
    if goal.kind == "zone" then tryAdvanceWorld(); return true end
    if goal.kind == "rebirth" then tryAdvanceWorld(); return true end
    if itemTypes[goal.kind] then return spawnQuestObject(goal) end
    if goal.kind == "farm" or goal.kind == "diamond" or goal.kind == "minichest" or goal.kind == "safe" then
        return farm(goal)
    end
    return false
end

local function stop()
    state.running = false
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
    local report = {"RankPilot DZ-enhanced capability report", "Rank: " .. describe(state.rank),
        "RankCmds.GetMaxRank value (diagnostic): " .. describe(state.maxRank), "Area: " .. state.area,
        "Status: " .. state.status, "PlaceId: " .. describe(game.PlaceId),
        "Breakable interface: " .. state.lastFarmInterface,
        "Goals: " .. #state.goals, "Controllers: " .. describe(state.chosen)}
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
    ui.logs.Text=table.concat({state.logs[1] or "",state.logs[2] or "",state.logs[3] or ""},"\n")
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
                if Config.AutoRank then
                    local selected=chooseGoal()
                    if selected then
                        state.chosen=selected.title.."  ["..selected.kind.."]"
                        state.status="Running "..selected.kind
                        local performed = performGoal(selected)
                        if not performed and selected.kind=="hatch" then
                            -- Hatch tasks often require coins or an unlocked egg.
                            -- Spend a bounded part of each cycle collecting coins.
                            if Config.AutoFarm then farm(nil) end
                        end
                        local watch = state.questWatch[selected.identity]
                        if watch and now()-watch.changedAt > Config.StallSeconds then
                            blockGoal(selected, Config.BlockedQuestSeconds,
                                "selected quest made no observed progress")
                            watch.changedAt=now()
                        end
                    else
                        state.chosen="No supported quest ready"
                        state.status="Waiting / fallback farming"
                        if Config.AutoFarm then farm(nil) end
                    end
                else
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
        task.wait(Config.TickSeconds)
    end
end

loadSettings()
local ok = refreshClients()
if ok then
    pcall(inspectState)
    log("Readable PS99 save module detected")
else
    log("PS99 save module unavailable. Hub will remain safely paused.","WAIT")
end
local uiOK, uiErr = pcall(buildUI)
if not uiOK then log("UI build error: " .. describe(uiErr), "ERROR") end
state.status = ok and "PAUSED: press START" or "Save module not found: press RECHECK"
state.generations=state.generations+1
local threadGeneration=state.generations
task.spawn(function() mainLoop(threadGeneration) end)

environment.RankPilot = {
    Version="2.0-DZ-research",
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
