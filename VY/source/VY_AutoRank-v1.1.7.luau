-- =====================================================================================
--  VY AutoRank v1.1.7
--  Pet Simulator 99 rank automation for the Potassium executor (Roblox Luau).
--
--  Farms the best zone, hatches the best egg, crafts gold/rainbow pets, uses potions /
--  fruits / flags / event items, claims rank rewards and teleports to the best zone's
--  world (re-executing through Potassium autoexec, or optionally queue_on_teleport).
--
--  Re-running the script stops the previous instance (getgenv().VyAutoRank.Stop()).
--  Every game-module call goes through gcall() (thread identity 2); GUI / VirtualUser
--  stay at identity 8. Every loop iteration is pcall-wrapped and restarts on error.
-- =====================================================================================

-- =====================================================================================
--  1. CONFIG
-- =====================================================================================
local CONFIG = {
    -- behaviour
    AutoClaimRewards = true,
    AutoMinigames = true,        -- live rank goals 25/26/45/46; preserves normal configuration
    MinigameTick = 0.2,
    MinigameStateMaxAge = 900,
    MinigameTransactionTimeout = 1200,
    MinigamePhaseTimeout = 45,
    MinigameTravelTimeout = 180,
    MinigameTeleportTimeout = 45,
    MinigameTeleportRetries = 3,
    MinigameTeleportRetryDelay = 10,
    MinigameRecoveryTimeout = 180,
    MinigameNoProgressTimeout = 75,
    MinigameRetryCooldown = 600,  -- back off all minigames after a failed visit
    MinigameNormalWorkSeconds = 300, -- give other rank quests time before/between visits
    MinigameVisitSeconds = 90,   -- return after this visit budget when other quests remain
    MinigameActionTimeout = 30,
    MinigameBiteTimeout = 35,
    MinigameActionInterval = 0.35,
    MinigameFishingClickInterval = 0.2, -- one catch tap at a time, paced from its send time
    MinigameTargetTimeout = 20,
    MinigameMaxTargetDistance = 80,
    MinigameCastDistance = 160,
    AutoFarm = true,             -- pets attack breakables in the best zone (needed by almost every goal)
    AutoHatch = true,            -- hatch best egg when an egg/pet goal (or crafting fodder) needs it
    AlwaysHatch = false,         -- hatch best egg continuously even without an egg goal
    AutoCraftGoldRainbow = true, -- GoldMachine_Activate / RainbowMachine_Activate for goals 40/41 (and 4/5)
    AutoUsePotions = true,       -- USE_POTION goals
    AutoUpgradePotions = true,   -- UPGRADE_POTION goals
    AutoUpgradeEnchants = true,  -- UPGRADE_ENCHANT goals
    AutoUseFruits = true,        -- USE_FRUIT goals
    AutoUseFlags = true,         -- USE_FLAG goals
    AutoDiamondFlags = true,     -- maintain a Diamonds Flag while a diamond-breakable goal is active
    AutoSpawnEvents = true,      -- comets / pinatas / lucky blocks / coin jars from inventory
    AutoBuyZones = true,         -- progress to area 219, then stop all automatic area purchases
    AreaTarget = 219,            -- hard upper limit: 219, including rank-driven purchases
    AutoRebirth = true,          -- required rebirths, including Rebirth 9 for the Supercomputer Radio
    RebirthTarget = 9,           -- hard upper limit: 9
    AreaBuyInterval = 3,
    AreaRetryDelay = 15,
    AreaConfirmTimeout = 30,
    AutoWorldTeleport = true,    -- teleport to the world of the best zone when not already there (needs re-execution)
    InfinitePetSpeed = true,
    SuperMagnet = true,
    DisableHatchAnimation = true,
    AutoEquipBestPets = true,    -- PetCmds.EquipBest() if no pets are equipped
    AutoCrystalRank = false,     -- optional key-based rank mode; toggle in the hub
    CrystalKeyLimit = 5000,      -- maximum key-opening requests per enabled session
    CrystalKeyReserve = 100,     -- preserve at least this many owned full keys
    CrystalBurst = 10,          -- paced one-key requests before checking collection credit
    CrystalOpenDelay = 0.15,    -- minimum delay after each completed request
    CrystalCreditWait = 10,     -- stop when a burst produces no replicated collection credit
    TryRankUpRemote = false,     -- fire Ranks_RankUp manually when track complete (server normally does it itself)
    -- tuning
    FarmTick = 0.25,             -- seconds between pet re-assignment
    HatchDelay = 0.75,           -- seconds between hatch requests
    HatchMaxDistance = 85,       -- studs; purchases work from afar, so the script only hops to the egg for a RETRY
                                 -- when a hatch request failed while the egg was farther than this, then returns
    ControllerTick = 1.0,
    CraftTick = 4.0,
    EventTick = 3.0,
    ZonePositionTolerance = 25,  -- re-teleport into the break zone if farther than this from its center
    MaxInventoryPotionTier = 10,
    -- item preferences
    PotionUsePriority = { "Lucky", "Coins", "Diamonds", "Treasure Hunter", "Damage" }, -- never "Huge", "The Cocktail", "Walkspeed" unless nothing else
    PotionUpgradePriority = { "Coins", "Diamonds", "Lucky", "Treasure Hunter", "Damage" },
    EnchantUpgradePriority = { "Coins", "Diamonds", "Tap Power", "Criticals", "Lucky Eggs", "Strong Pets", "Treasure Hunter" }, -- only ids with MaxTier >= target tier
    FruitUsePriority = { "Apple", "Orange", "Pineapple", "Banana", "Watermelon", "Rainbow" },
    AllowShinyFruit = false,
    FlagPriority = { "Coins Flag", "Diamonds Flag", "Hasty Flag", "Strength Flag", "Magnet Flag", "Fortune Flag", "Shiny Flag" },
    CoinJarPriority = { "Basic Coin Jar", "Giant Coin Jar", "Magic Coin Jar" },
    ProtectedPetIds = {},        -- never used as gold/rainbow fodder
    UseShinyPetsAsFodder = false,
    -- Keep this file enabled in Potassium autoexec to resume after changing worlds.
    ReexecuteViaAutoexec = true, -- false only when using the queue_on_teleport options below
    -- Optional queue mode: explicit source, otherwise the executor workspace file.
    ReexecSource = nil,          -- explicit Luau source string to queue; or
    WorkspaceFile = "VY_AutoRank (16).luau", -- file in the executor workspace folder; queued as loadstring(readfile(name))()
    -- GUI
    ShowGui = true,
    GuiToggleKey = Enum.KeyCode.RightControl,
    DiscordInvite = "https://discord.gg/gfD29rTmV", -- hub button; copies only when clicked
}

-- =====================================================================================
--  2. Services, constants, goal enums
-- =====================================================================================
local VERSION = "1.1.7"
local TAG = "[AutoRank] "
local STATE_FILE = "VY_AutoRank_State.json"
local STATE_FILE_MAX_AGE = 900      -- seconds; counters older than this are not restored
local MAX_CRAFT_PER_CALL = 50       -- outputs per GoldMachine/RainbowMachine invoke
local MAX_UPGRADE_PER_CALL = 25     -- outputs per UpgradePotions/UpgradeEnchants invoke
local MAX_CLAIM_ATTEMPTS = 6        -- Ranks_ClaimReward fires per reward index before slowing the retry to CLAIM_SLOW_RETRY (per rank)
local CLAIM_SLOW_RETRY = 60         -- seconds between claim retries once MAX_CLAIM_ATTEMPTS is reached (never give up: the rank cannot complete without it)
local GUI_WIDTH = 320
local LINE_H = 18

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

-- captured early for the helpers below; re-captured in bootstrap() once the game is loaded
local LocalPlayer = Players.LocalPlayer

-- Verified place ids (FINDINGS.md) used as a last-resort world detection.
local WORLD_PLACE_IDS = {
    [8737899170] = 1,
    [16498369169] = 2,
    [17503543197] = 3,
    [140403681187145] = 4,
}

-- Types.Quests.Goals (name = id)
local GOAL_TYPE_NAMES = {
    [1] = "BREAKABLE", [2] = "PET", [3] = "EGG", [4] = "GOLD_PET", [5] = "RAINBOW_PET", [6] = "ZONE",
    [7] = "CURRENCY", [8] = "MINI_CHEST", [9] = "DIAMOND_BREAKABLE", [10] = "BUY_POTION", [11] = "BUY_ENCHANT",
    [12] = "UPGRADE_POTION", [13] = "UPGRADE_ENCHANT", [14] = "COLLECT_POTION", [15] = "COLLECT_ENCHANT",
    [18] = "FREE_GIFT", [19] = "FUSE_PETS", [20] = "BEST_EGG", [21] = "CURRENT_BREAKABLE", [22] = "SPAWN_OBBY",
    [23] = "MINEFIELD", [24] = "ATLANTIS", [25] = "DIGSITE", [26] = "FISHING", [27] = "ICE_OBBY",
    [28] = "PYRAMID_OBBY", [29] = "JUNGLE_OBBY", [30] = "CHEST_RUSH", [31] = "COIN_JAR", [32] = "COMET",
    [33] = "USE_FLAG", [34] = "USE_POTION", [35] = "USE_FRUIT", [36] = "SLED_RACE", [37] = "BEST_COIN_JAR",
    [38] = "BEST_COMET", [39] = "BEST_MINI_CHEST", [40] = "BEST_GOLD_PET", [41] = "BEST_RAINBOW_PET",
    [42] = "HATCH_RARE_PET", [43] = "BEST_PINATA", [44] = "BEST_LUCKYBLOCK", [45] = "ADVANCED_DIGSITE",
    [46] = "ADVANCED_FISHING", [47] = "INDEX_PET", [66] = "PINATA", [67] = "LUCKYBLOCK", [68] = "RANDOM_COIN_JAR",
    [69] = "RANDOM_COMET", [70] = "RANDOM_PINATA", [71] = "RANDOM_LUCKYBLOCK", [72] = "RANDOM_MINI_CHEST",
    [75] = "SUPERIOR_MINI_CHEST", [76] = "BEST_SUPERIOR_MINI_CHEST", [77] = "RANDOM_SUPERIOR_MINI_CHEST",
    [80] = "EQUIP_PET", [81] = "SPECIFIC_ZONE",
}

local function makeSet(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local FARM_GOALS = makeSet({ 1, 21, 9, 7, 14, 15, 8, 39, 75, 76 })   -- progressed by farming alone
local CHEST_GOALS = makeSet({ 8, 39, 75, 76 })                       -- wait for server spawns
local HATCH_GOALS = makeSet({ 20, 42, 3, 2 })
local EGG_COUNT_GOALS = makeSet({ 20, 3 })                           -- remaining counts eggs
local GOLD_GOALS = makeSet({ 40, 4 })
local RAINBOW_GOALS = makeSet({ 41, 5 })
local BEST_EGG_ONLY_CRAFT = makeSet({ 40, 41 })                      -- fodder must come from the best egg

local T_ZONE, T_DIAMOND, T_UPGRADE_POTION, T_UPGRADE_ENCHANT = 6, 9, 12, 13
local T_USE_FLAG, T_USE_POTION, T_USE_FRUIT = 33, 34, 35

-- event-item goals -> kind
local EVENT_GOAL_KIND = {
    [38] = "Comet", [32] = "Comet",
    [43] = "Pinata", [66] = "Pinata",
    [44] = "LuckyBlock", [67] = "LuckyBlock",
    [37] = "CoinJar", [31] = "CoinJar",
}
local EVENT_DEFS = {
    Comet = { items = { "Comet" }, remote = "Comet_Spawn", label = "comet", match = { "comet" } },
    Pinata = { items = { "Mini Pinata" }, remote = "MiniPinata_Consume", label = "pinata", match = { "pinata" } },
    LuckyBlock = { items = { "Mini Lucky Block" }, remote = "MiniLuckyBlock_Consume", label = "lucky block", match = { "luckyblock" } },
    CoinJar = { items = CONFIG.CoinJarPriority, remote = "CoinJar_Spawn", label = "coin jar", match = { "coinjar" } },
}
-- id substrings that mark an event/chest breakable regardless of BreakableClass (SPEC 4.2 OR rule)
local EVENT_BREAKABLE_WORDS = { "comet", "pinata", "jar", "lucky", "chest" }

-- BEGIN MINIGAME PURE
local MINIGAME_DEFS = {
    [25] = { world = 1, zoneNumber = 30, instance = "Digsite", kind = "Digsite" },
    [26] = { world = 1, zoneNumber = 27, instance = "Fishing", kind = "Fishing" },
    [45] = { world = 1, zoneNumber = 79, instance = "AdvancedDigsite", kind = "AdvancedDigsite" },
    [46] = { world = 1, zoneNumber = 92, instance = "AdvancedFishing", kind = "AdvancedFishing" },
}
-- Methods are installed in the pure, runtime, and adapter blocks before main starts.
-- Declare the complete interface up front for editors using Luau's older type solver.
type MinigameMethod = (...any) -> ...any
type MinigameControllerApi = {
    destination: MinigameMethod, classify: MinigameMethod, validate: MinigameMethod,
    holdsWork: MinigameMethod, hasNormalGoals: MinigameMethod, valid: MinigameMethod, part: MinigameMethod,
    setEnabled: MinigameMethod, setPriority: MinigameMethod,
    move: MinigameMethod, call: MinigameMethod, discardOperation: MinigameMethod,
    phase: MinigameMethod, fail: MinigameMethod, activeModel: MinigameMethod,
    remote: MinigameMethod, resolveZone: MinigameMethod, peerSnapshot: MinigameMethod,
    start: MinigameMethod, restore: MinigameMethod, finish: MinigameMethod,
    stop: (() -> ())?, observe: MinigameMethod, status: MinigameMethod,
    entry: MinigameMethod, exit: MinigameMethod, restoreLocation: MinigameMethod,
    tick: MinigameMethod, executeFishing: MinigameMethod, executeAdvancedFishing: MinigameMethod,
    executeDigsite: MinigameMethod, executeAdvancedDigsite: MinigameMethod,
}
local MinigameController = {} :: MinigameControllerApi
do
    local M = MinigameController
    local returning = { EXIT = true, RETURN = true, RESTORE = true, RESUME = true, RECOVERY = true, ABORTED = true }
    local phases = { PREPARE = true, SAVE_CONTEXT = true, PAUSE = true, WORLD_TRAVEL = true,
        INSTANCE_ENTRY = true, EXECUTE = true, VERIFY = true, EXIT = true, RETURN = true,
        RESTORE = true, RESUME = true, RECOVERY = true, ABORTED = true }
    local function finite(n)
        return type(n) == "number" and n == n and n > -math.huge and n < math.huge
    end
    local function identity(v)
        return (type(v) == "string" and #v > 0 and #v <= 160) or (finite(v) and v >= 0)
    end
    function M.destination(tx, crystalHold, world, zone)
        if tx then
            if returning[tx.phase] then
                return "MINIGAME_RETURN", world or tx.originalWorld, zone or tx.originalZone
            end
            return "MINIGAME_TRAVEL", tx.targetWorld, tx.targetZone
        end
        if crystalHold then return "CRYSTAL", 1, "Castle" end
        return "NORMAL_FARMING", world, zone
    end
    function M.classify(save, tx)
        if type(tx) ~= "table" or type(save) ~= "table" or not tonumber(save.Rank)
            or type(save.Goals) ~= "table" then return "UNKNOWN" end
        if tonumber(save.Rank) ~= tx.originalRank then return "RANK_CHANGED" end
        local replacement
        for tier, g in pairs(save.Goals) do
            if type(g) == "table" then
                if g.UID ~= nil and tx.goalUID ~= nil and tostring(g.UID) == tostring(tx.goalUID) then
                    if tonumber(g.Type) ~= tx.goalType then return "REPLACED" end
                    local amount, progress = tonumber(g.Amount), tonumber(g.Progress)
                    if not finite(amount) or amount <= 0 or not finite(progress) then return "UNKNOWN" end
                    return progress >= amount and "COMPLETED" or "ACTIVE", g
                end
                if tostring(tier) == tostring(tx.goalTier) and g.UID ~= nil then replacement = g end
            end
        end
        if tx.completionObserved == true or (tonumber(tx.lastProgress) or 0) >= tx.goalAmount then return "COMPLETED" end
        -- A star delta is attributable only after observed progress, an exact reward,
        -- and a complete, unchanged snapshot of every other quest slot.
        local peers = tx.peerGoals
        if replacement and type(peers) == "table" and tx.goalStars > 0
            and (tonumber(save.RankStars) or -1) - tx.baselineStars == tx.goalStars
            and tx.lastProgress > tx.progressBaseline then
            local stable, seen = true, {}
            for tier, g in pairs(save.Goals) do
                local key = tostring(tier)
                if key ~= tostring(tx.goalTier) then
                    local before = peers[key]
                    if type(g) ~= "table" or type(before) ~= "table" or g.UID == nil
                        or tostring(g.UID) ~= tostring(before.uid) or tonumber(g.Progress) ~= before.progress then stable = false; break end
                    seen[key] = true
                end
            end
            for key in pairs(peers) do if not seen[tostring(key)] then stable = false end end
            if stable then return "COMPLETED" end
        end
        return replacement and "REPLACED" or "UNKNOWN"
    end
    function M.validate(raw, userId, now)
        if type(raw) ~= "table" then return nil, "transaction is not a table" end
        if raw.schemaVersion ~= 1 or raw.userId ~= userId then return nil, "transaction schema/account mismatch" end
        local def = MINIGAME_DEFS[raw.goalType]
        if not def or not phases[raw.phase] then return nil, "unsupported goal or phase" end
        if not identity(raw.id) or type(raw.id) ~= "string" or not identity(raw.goalUID) or not identity(raw.goalTier) then
            return nil, "missing transaction/quest identity"
        end
        if raw.targetWorld ~= def.world or raw.instanceName ~= def.instance
            or type(raw.targetZone) ~= "string" or #raw.targetZone == 0 or #raw.targetZone > 160
            or type(raw.originalZone) ~= "string" or #raw.originalZone == 0 or #raw.originalZone > 160 then
            return nil, "transaction destination mismatch"
        end
        local clean = { schemaVersion = 1, userId = userId, id = raw.id, phase = raw.phase,
            goalUID = raw.goalUID, goalType = raw.goalType, goalTier = tostring(raw.goalTier),
            originalZone = raw.originalZone, targetZone = raw.targetZone,
            targetWorld = def.world, instanceName = def.instance }
        for _, key in ipairs({ "originalWorld", "originalRank", "goalAmount", "goalStars", "progressBaseline",
            "lastProgress", "baselineStars", "timestamp", "updatedAt", "phaseAt", "lastProgressAt" }) do
            local n = raw[key]
            if not finite(n) or n < 0 then return nil, "invalid number: " .. key end
            clean[key] = n
        end
        if clean.originalWorld < 1 or clean.originalWorld > 4 or clean.originalWorld % 1 ~= 0
            or clean.originalRank < 1 or clean.originalRank % 1 ~= 0 or clean.goalAmount <= 0 then
            return nil, "invalid world/rank/amount"
        end
        for _, key in ipairs({ "timestamp", "updatedAt", "phaseAt", "lastProgressAt" }) do
            if clean[key] > now + 30 or clean[key] < clean.timestamp then return nil, "invalid transaction clock" end
        end
        if now - clean.updatedAt > CONFIG.MinigameStateMaxAge or now - clean.timestamp > CONFIG.MinigameTransactionTimeout then
            return nil, "expired transaction"
        end
        if type(raw.teleportAttempts) ~= "table" then return nil, "missing teleport budget" end
        clean.teleportAttempts = {}
        for _, key in ipairs({ "outbound", "returning" }) do
            local n = raw.teleportAttempts[key]
            if not finite(n) or n < 0 or n % 1 ~= 0 or n > CONFIG.MinigameTeleportRetries then return nil, "invalid teleport budget" end
            clean.teleportAttempts[key] = n
        end
        clean.peerGoals = {}
        if type(raw.peerGoals) ~= "table" then return nil, "missing peer quest snapshot" end
        local count = 0
        for tier, peer in pairs(raw.peerGoals) do
            count += 1
            if count > 16 or not identity(tier) or type(peer) ~= "table" or not identity(peer.uid)
                or not finite(peer.progress) or peer.progress < 0 then return nil, "invalid peer quest snapshot" end
            clean.peerGoals[tostring(tier)] = { uid = peer.uid, progress = peer.progress }
        end
        for _, key in ipairs({ "completionObserved", "pausedPets", "cancelled", "aborted" }) do clean[key] = raw[key] == true end
        for _, key in ipairs({ "lastTeleportAt", "returnWorld", "recoveryAt", "cooldownUntil" }) do
            if raw[key] ~= nil then
                if not finite(raw[key]) or raw[key] < 0 then return nil, "invalid optional number: " .. key end
                if key == "returnWorld" and (raw[key] < 1 or raw[key] > 4 or raw[key] % 1 ~= 0) then
                    return nil, "invalid return world"
                elseif key == "cooldownUntil" and raw[key] > now + (CONFIG.MinigameRetryCooldown or 120) + 30 then
                    return nil, "invalid cooldown clock"
                elseif (key == "lastTeleportAt" or key == "recoveryAt") and raw[key] > now + 30 then
                    return nil, "invalid optional clock: " .. key
                end
                clean[key] = raw[key]
            end
        end
        for _, key in ipairs({ "returnZone", "recoveryReason", "outcome", "lastTeleportLeg" }) do
            if raw[key] ~= nil then
                if type(raw[key]) ~= "string" or #raw[key] > 500 then return nil, "invalid optional string: " .. key end
                clean[key] = raw[key]
            end
        end
        return clean
    end
end
-- END MINIGAME PURE

-- Fallback tier requirements (identity-2 Balancing functions are preferred)
local POTION_TIER_REQ_FALLBACK = { 3, 3, 4, 5, 5, 5, 5, 5, 7, 7, 7 }
local ENCHANT_TIER_REQ_FALLBACK = { 3, 3, 3, 5, 5, 5, 5, 5, 8, 8 }

-- =====================================================================================
--  3. Logging
-- =====================================================================================
local function int(x)
    x = tonumber(x) or 0
    return tostring(math.floor(x + 0.5))
end

local function fmt(f, ...)
    if select("#", ...) == 0 then return tostring(f) end
    local ok, s = pcall(string.format, tostring(f), ...)
    if ok then return s end
    local parts = { tostring(f) }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

local function log(f, ...)
    print(TAG .. fmt(f, ...))
end

local warnAt = {}
local function warnlog(key, f, ...)
    -- same key at most once per 30 s
    local now = os.clock()
    local last = warnAt[tostring(key)]
    if last and now - last < 30 then return end
    warnAt[tostring(key)] = now
    warn(TAG .. fmt(f, ...))
end

local logAt = {}
local function logEvery(key, seconds, f, ...)
    local now = os.clock()
    local last = logAt[tostring(key)]
    if last and now - last < seconds then return end
    logAt[tostring(key)] = now
    log(f, ...)
end

local onceDone = {}
local function logOnce(key, f, ...)
    key = tostring(key)
    if onceDone[key] then return end
    onceDone[key] = true
    log(f, ...)
end

local function warnOnce(key, f, ...)
    key = tostring(key)
    if onceDone[key] then return end
    onceDone[key] = true
    warn(TAG .. fmt(f, ...))
end

-- clears once-keys with the given prefix (e.g. "rank:" on rank-up)
local function resetOnce(prefix)
    for k in pairs(onceDone) do
        if string.sub(k, 1, #prefix) == prefix then onceDone[k] = nil end
    end
end

-- =====================================================================================
--  4. Previous instance, identity wrapper
-- =====================================================================================
local genv = (type(getgenv) == "function" and getgenv()) or _G
if type(genv.VyAutoRank) == "table" and type(genv.VyAutoRank.Stop) == "function" then
    pcall(genv.VyAutoRank.Stop)
    task.wait(0.25)
end

local state -- captured by gcall for cooperative cancellation after yielding work
local IDENTITY_GAME, IDENTITY_EXEC = 2, 8
local canSetIdentity = type(setthreadidentity) == "function"

-- Runs fn(...) at identity 2 (game modules) and restores identity 8 (executor / CoreGui).
-- Returns pcall-style results: ok, ...
local function gcall(fn, ...)
    if state and state.normalThreads[coroutine.running()] and (not state.alive or state.minigame.transaction
        or (state.areaProgression and state.areaProgression.hold)) then
        return false, "normal work paused for minigame or area transition"
    end
    if type(fn) ~= "function" then
        return false, "gcall: not a function"
    end
    if canSetIdentity then pcall(setthreadidentity, IDENTITY_GAME) end
    local r = table.pack(pcall(fn, ...))
    if canSetIdentity then pcall(setthreadidentity, IDENTITY_EXEC) end
    return table.unpack(r, 1, r.n)
end

-- First result of a successful gcall, else nil.
local function gval(fn, ...)
    local ok, a, b, c, d = gcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

local function isfn(mod, name)
    return type(mod) == "table" and type(mod[name]) == "function"
end

-- =====================================================================================
--  5. State, connections, Stop(), genv handle
-- =====================================================================================
state = {
    alive = true,
    startedAt = os.clock(),
    rank = nil,                 -- rankInfo() snapshot
    goals = {},                 -- activeGoals() snapshot (sorted by stars desc)
    goalsByType = {},
    plan = { hatch = false, hatchReasons = {}, hatchEggOnly = false, hatchRemaining = nil },
    action = "starting",
    counters = { hatched = 0, claimed = 0, crafted = 0, itemsUsed = 0, farmTicks = 0, eventTargets = 0 },
    persist = { lastWorldSwitch = 0, worldHistory = {} },
    normalWorkers = {},
    normalThreads = {},
    navigation = { owner = "NORMAL_FARMING" },
    areaProgression = { status = "Areas: starting (target 219 / Rebirth 9)", nextAt = 0 },
    minigame = { transaction = nil, generation = 0, session = {}, cooldowns = {} },
    worldSwitching = false,
    worldSwitchAt = 0,
    worldMismatch = false,      -- best zone is in another world (set by the controller)
    hopping = false,
    returnAfterHatch = nil,
    lastRank = nil,
    claimedAt = {},             -- reward index -> clock of last fire (debounce)
    claimAttempts = {},         -- reward index -> number of fires this rank
    pendingClaims = {},         -- reward index -> clock (counted when redeemed)
    trackCompleteLoggedRank = nil,
    trackCompleteAt = nil,
    rankUpFiredRank = nil,
    lastZoneBuyAt = 0,
    craftHatchReason = nil,     -- set by the crafting thread when fodder is missing
    lastEventSpawn = {},        -- kind -> clock
    eventBackoffUntil = {},     -- kind -> clock
    flagRetryAt = 0,
    flagBusy = false,
    diamondFlagUntil = {},      -- zone id -> next upkeep attempt (no repeated consumption every tick)
    farmPets = 0,
    farmTargets = 0,
    crystal = { hold = false, used = 0, reserved = 0, pausedPets = false, status = "OFF" },
    queued = false,
}

local function normalWorkAllowed()
    return state.alive and state.minigame.transaction == nil and not state.minigame.restorePets
        and not state.areaProgression.hold
end

local connections = {}
local function track(conn)
    if conn then connections[#connections + 1] = conn end
    return conn
end

local restoreFns = {}       -- run at Stop() to undo patches that can be undone
local persistHook = nil     -- set later (writes the state file)
local gui = nil             -- ScreenGui
local stopped = false
local handle

local function Stop()
    if stopped then return end
    stopped = true
    if MinigameController.stop then MinigameController.stop() end
    state.persist.queueActive = false
    state.alive = false
    state.action = "stopped"
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
    for _, fn in ipairs(restoreFns) do
        pcall(fn)
    end
    restoreFns = {}
    if gui then
        pcall(function() gui:Destroy() end)
        gui = nil
    end
    if persistHook then pcall(persistHook) end
    if genv.VyAutoRank == handle then
        genv.VyAutoRank = nil
    end
    print(TAG .. "stopped")
end

-- published right after stopping the old instance, before anything else can fail
handle = { Stop = Stop, Config = CONFIG, State = state, Version = VERSION }
genv.VyAutoRank = handle

-- =====================================================================================
--  6. Module loading
-- =====================================================================================
local G = {}

local MODULE_PATHS = {
    Save = { "Library", "Client", "Save" },
    Network = { "Library", "Client", "Network" },
    Directory = { "Library", "Directory" },
    RanksUtil = { "Library", "Util", "RanksUtil" },
    RankCmds = { "Library", "Client", "RankCmds" },
    ZoneCmds = { "Library", "Client", "ZoneCmds" },
    ZonesUtil = { "Library", "Util", "ZonesUtil" },
    EggsUtil = { "Library", "Util", "EggsUtil" },
    EggCmds = { "Library", "Client", "EggCmds" },
    MapCmds = { "Library", "Client", "MapCmds" },
    QuestCmds = { "Library", "Client", "QuestCmds" },
    PotionCmds = { "Library", "Client", "PotionCmds" },
    FruitCmds = { "Library", "Client", "FruitCmds" },
    FlexibleFlagCmds = { "Library", "Client", "FlexibleFlagCmds" },
    RandomEventCmds = { "Library", "Client", "RandomEventCmds" },
    InstancingCmds = { "Library", "Client", "InstancingCmds" },
    PlayerPet = { "Library", "Client", "PlayerPet" },
    PetCmds = { "Library", "Client", "PetCmds" },
    CurrencyCmds = { "Library", "Client", "CurrencyCmds" },
    PlaceFile = { "Library", "Modules", "PlaceFile" },
    CalcPotionsPerTierRequired = { "Library", "Balancing", "CalcPotionsPerTierRequired" },
    CalcEnchantsPerTierRequired = { "Library", "Balancing", "CalcEnchantsPerTierRequired" },
}
local OPTIONAL_MODULE_PATHS = {
    RebirthCmds = { "Library", "Client", "RebirthCmds" },
    CalcGatePrice = { "Library", "Balancing", "CalcGatePrice" },
    WorldsUtil = { "Library", "Util", "WorldsUtil" },
    EnchantCmds = { "Library", "Client", "EnchantCmds" },
    UpgradeCmds = { "Library", "Client", "UpgradeCmds" },
}

local function findPath(root, path, timeout)
    local inst = root
    for _, name in ipairs(path) do
        if not inst then return nil end
        local child = inst:FindFirstChild(name)
        if not child then
            local ok, res = pcall(function() return inst:WaitForChild(name, timeout or 5) end)
            child = ok and res or nil
        end
        inst = child
    end
    return inst
end

local function loadModule(key, path, optional)
    if G[key] ~= nil then return G[key] end
    local inst = findPath(RS, path, optional and 1 or 5)
    if not inst then
        if not optional then
            warnlog("mod-" .. key, "module %s not found (ReplicatedStorage.%s) - features needing it are disabled", key, table.concat(path, "."))
        end
        return nil
    end
    local ok, mod = gcall(require, inst)
    if not ok then
        warnlog("mod-" .. key, "require(%s) failed: %s", key, tostring(mod))
        return nil
    end
    G[key] = mod
    return mod
end

local function directoryTable(name)
    if type(G.Directory) == "table" then
        local ok, t = gcall(function() return G.Directory[name] end)
        if ok and type(t) == "table" then return t end
    end
    return loadModule(name, { "Library", "Directory", name }, true)
end

local function loadModules()
    for key, path in pairs(MODULE_PATHS) do
        if not state.alive then return end
        loadModule(key, path, false)
    end
    for key, path in pairs(OPTIONAL_MODULE_PATHS) do
        if not state.alive then return end
        loadModule(key, path, true)
    end
    G.Ranks = directoryTable("Ranks")
    G.Zones = directoryTable("Zones")
    G.Eggs = directoryTable("Eggs")
    G.Potions = directoryTable("Potions")
    G.Enchants = directoryTable("Enchants")
    G.RandomEvents = directoryTable("RandomEvents")
    local missing = {}
    for key in pairs(MODULE_PATHS) do
        if G[key] == nil then missing[#missing + 1] = key end
    end
    if #missing > 0 then
        table.sort(missing)
        warnlog("mod-missing", "missing modules: %s", table.concat(missing, ", "))
    end
end

-- =====================================================================================
--  7. Network / save wrappers
-- =====================================================================================
local function netFire(name, ...)
    if not isfn(G.Network, "Fire") then return false, "Network.Fire unavailable" end
    return gcall(G.Network.Fire, name, ...)
end

local function netInvoke(name, ...)
    if not isfn(G.Network, "Invoke") then return false, "Network.Invoke unavailable" end
    return gcall(G.Network.Invoke, name, ...)
end

local function netUnreliable(name, ...)
    if isfn(G.Network, "UnreliableFire") then
        return gcall(G.Network.UnreliableFire, name, ...)
    end
    return false, "Network.UnreliableFire unavailable"
end

local function getSave()
    if not isfn(G.Save, "Get") then return nil end
    local ok, s = gcall(G.Save.Get)
    if ok and type(s) == "table" then return s end
    return nil
end

-- =====================================================================================
--  8. Persistence & re-execution queue
-- =====================================================================================
local function stateFilePath()
    local id = LocalPlayer and tonumber(LocalPlayer.UserId)
    return id and id > 0 and ("VY_AutoRank_State_" .. tostring(math.floor(id)) .. ".json") or STATE_FILE
end

local function readStateFile()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    local ok, data = pcall(function()
        local path = stateFilePath()
        if not isfile(path) then path = STATE_FILE end -- migrate the earlier shared state once
        if not isfile(path) then return nil end
        local raw = readfile(path)
        if type(raw) ~= "string" or raw == "" then return nil end
        return HttpService:JSONDecode(raw)
    end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function writeStateFile()
    if type(writefile) ~= "function" then return false end
    local ok = pcall(function()
        local payload = {
            version = VERSION,
            userId = LocalPlayer and LocalPlayer.UserId,
            savedAt = os.time(),
            minigame = state.minigame.transaction,
            minigameEnabled = CONFIG.AutoMinigames,
            minigamePriorityFirst = state.minigame.priorityFirst == true,
            minigameNextStartAt = state.minigame.nextStartAt,
            minigameNormalWorkUntil = state.minigame.normalWorkUntil,
            queueToken = state.persist.queueToken,
            queueActive = state.persist.queueActive == true,
            minigameRestorePets = state.minigame.restorePets == true or (state.minigame.transaction and state.minigame.transaction.pausedPets == true) or false,
            worldHistory = state.persist.worldHistory,
            lastWorldSwitch = state.persist.lastWorldSwitch or 0,
            counters = state.counters,
            crystal = {
                userId = LocalPlayer and LocalPlayer.UserId,
                enabled = CONFIG.AutoCrystalRank,
                used = state.crystal.used + state.crystal.reserved,
                halted = state.crystal.halted,
                pausedPets = state.crystal.pausedPets,
            },
        }
        if writefile(stateFilePath(), HttpService:JSONEncode(payload)) == false then error("state write refused") end
    end)
    return ok
end
persistHook = writeStateFile

local function restoreStateFile()
    local data = readStateFile()
    if not data then return end
    local savedAt = tonumber(data.savedAt) or 0
    local ownerId = data.userId or (type(data.crystal) == "table" and data.crystal.userId)
    if not LocalPlayer or ownerId ~= LocalPlayer.UserId or savedAt > os.time() + 30
        or os.time() - savedAt > STATE_FILE_MAX_AGE then return end
    state.persist.lastWorldSwitch = math.min(os.time(), tonumber(data.lastWorldSwitch) or 0)
    state.persist.worldHistory = {}
    if type(data.worldHistory) == "table" then
        for _, timestamp in ipairs(data.worldHistory) do
            if type(timestamp) == "number" and timestamp <= os.time() + 30 and os.time() - timestamp < 180 then
                table.insert(state.persist.worldHistory, timestamp)
                if #state.persist.worldHistory >= 6 then break end
            end
        end
    end
    state.minigame.restorePets = data.minigameRestorePets == true
    if type(data.minigameEnabled) == "boolean" then CONFIG.AutoMinigames = data.minigameEnabled end
    if type(data.minigamePriorityFirst) == "boolean" then state.minigame.priorityFirst = data.minigamePriorityFirst end
    for field, stored in pairs({ nextStartAt = "minigameNextStartAt", normalWorkUntil = "minigameNormalWorkUntil" }) do
        local deadline = tonumber(data[stored])
        local maximum = field == "nextStartAt" and (CONFIG.MinigameRetryCooldown or 600) or (CONFIG.MinigameNormalWorkSeconds or 300)
        if deadline and deadline == deadline and deadline >= 0 and deadline <= os.time() + maximum + 30 then
            state.minigame[field] = deadline
        end
    end
    MinigameController.restore(data.minigame)
    local crystal = data.crystal
    if type(crystal) == "table" and os.time() - savedAt < STATE_FILE_MAX_AGE
        and LocalPlayer and crystal.userId == LocalPlayer.UserId then
        CONFIG.AutoCrystalRank = crystal.enabled == true
        state.crystal.used = math.max(0, tonumber(crystal.used) or 0)
        state.crystal.halted = type(crystal.halted) == "string" and crystal.halted or nil
        state.crystal.pausedPets = crystal.pausedPets == true
        state.crystal.pauseAt = os.clock()
    end
    if type(data.counters) == "table" and os.time() - savedAt < STATE_FILE_MAX_AGE then
        for k, v in pairs(data.counters) do
            if type(v) == "number" and state.counters[k] ~= nil then
                state.counters[k] = v
            end
        end
        log("Restored counters from %s", STATE_FILE)
    end
end

-- Queue this script to run again after the next place teleport.
local function queueSelf(verbose)
    -- Autoexec loads this installed file in the destination client. World travel still
    -- requires a successful state write; registering a second copy would race autoexec.
    if CONFIG.ReexecuteViaAutoexec == true then return true end
    local function unavailable(key, reason)
        if verbose then warnlog(key, "%s", reason) end
        return false, reason
    end
    local marker = 'local VERSION = "' .. VERSION .. '"'
    local explicitSource: any = CONFIG.ReexecSource
    if type(explicitSource) == "string" and #explicitSource > 0
        and (not string.find(explicitSource, marker, 1, true) or not string.find(explicitSource, "MINIGAME_DEFS", 1, true)) then
        return unavailable("queue-source", "ReexecSource must contain AutoRank v" .. VERSION .. " source")
    end
    if state.queued then return true end
    if type(queue_on_teleport) ~= "function" then
        return unavailable("queue-missing", "queue_on_teleport unavailable; enable Potassium autoexec and ReexecuteViaAutoexec")
    end
    local src = explicitSource
    if type(src) ~= "string" or #src == 0 then
        local name = CONFIG.WorkspaceFile
        if type(name) ~= "string" or not string.match(name, "^[%w%._%(%) %-]+%.luau$") then
            return unavailable("queue-name", "WorkspaceFile must be a .luau filename in the executor workspace")
        end
        if type(readfile) ~= "function" then return unavailable("queue-read", "readfile unavailable for WorkspaceFile") end
        local ok, source = pcall(readfile, name)
        if not ok or type(source) ~= "string" or not string.find(source, marker, 1, true)
            or not string.find(source, "MINIGAME_DEFS", 1, true) then
            return unavailable("queue-nofile", "Missing/stale workspace source: " .. name .. " (requires v" .. VERSION .. "); use autoexec or save the updated file there")
        end
        src = string.format('local ok,e=pcall(function() local s=readfile(%q); assert(string.find(s,%q,1,true),"AutoRank source version changed"); local f,err=loadstring(s); assert(f,err); f() end); if not ok then warn("[AutoRank reexec] "..tostring(e)) end', name, marker)
    end
    local token = HttpService:GenerateGUID(false)
    state.persist.queueToken, state.persist.queueActive = token, true
    if not writeStateFile() then
        state.persist.queueActive = false
        return unavailable("queue-state", "Could not save re-execution state in the executor workspace")
    end
    -- Only the latest queued copy for this account may run; Stop disarms it.
    src = string.format([[
local ok,err=pcall(function()
    local players=game:GetService("Players")
    local untilAt=os.clock()+90
    repeat task.wait(0.25) until (game:IsLoaded() and players.LocalPlayer) or os.clock()>=untilAt
    if not players.LocalPlayer or players.LocalPlayer.UserId~=%d then return end
    local http=game:GetService("HttpService")
    local d=http:JSONDecode(readfile(%q))
    if d.userId~=%d or d.queueToken~=%q or d.queueActive~=true then return end
    d.queueActive=false
    writefile(%q,http:JSONEncode(d))
    %s
end)
if not ok then warn("[AutoRank reexec] "..tostring(err)) end
    ]], LocalPlayer.UserId, stateFilePath(), LocalPlayer.UserId, token, stateFilePath(), src)
    local ok, result = pcall(queue_on_teleport, src)
    if ok and result ~= false then state.queued = true; return true end
    state.persist.queueActive = false
    writeStateFile()
    return unavailable("queue-fail", "queue_on_teleport failed: " .. tostring(result))
end

-- =====================================================================================
--  9. Game-state helpers (all game calls through gcall)
-- =====================================================================================
local cache = { zoneId = nil, zoneAt = 0, zone = nil, egg = nil, eggAt = 0, maxHatch = nil, maxHatchAt = 0, breakPart = nil, breakPartZone = nil }

local function invalidateCaches()
    cache.zoneAt = 0
    cache.eggAt = 0
    cache.maxHatchAt = 0
    cache.breakPart = nil
end

local function getHRP()
    local ch = LocalPlayer and LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

-- InstancingCmds.IsInInstance(), cached for 1 s (the farm tick and the fast path ask often)
local instanceCache = { at = -1e9, value = false }
local function inInstance()
    local now = os.clock()
    if now - instanceCache.at < 1 then return instanceCache.value end
    local v = false
    if isfn(G.InstancingCmds, "IsInInstance") then
        v = gval(G.InstancingCmds.IsInInstance) == true
    end
    instanceCache.at = now
    instanceCache.value = v
    return v
end

local function currentWorld()
    local pf = G.PlaceFile
    if type(pf) == "table" then
        for n = 1, 4 do
            local v = pf["IsWorld" .. n]
            if type(v) == "function" then
                local ok, r = gcall(v)
                v = ok and r or nil
            end
            if v == true then return n end
        end
    end
    if isfn(G.WorldsUtil, "GetWorldNumber") then
        local n = gval(G.WorldsUtil.GetWorldNumber)
        if type(n) == "number" then return n end
    end
    return WORLD_PLACE_IDS[game.PlaceId]
end

local function bestZoneId()
    local now = os.clock()
    if cache.zoneId and now - cache.zoneAt < 10 then return cache.zoneId end
    if isfn(G.ZoneCmds, "GetMaxOwnedZone") then
        local id = gval(G.ZoneCmds.GetMaxOwnedZone)
        if type(id) == "table" then id = id._id end
        if type(id) == "string" then
            cache.zoneId = id
            cache.zoneAt = now
            cache.zone = type(G.Zones) == "table" and G.Zones[id] or nil
        end
    end
    return cache.zoneId
end

local function bestZone()
    bestZoneId()
    return cache.zone
end

local function bestZoneName()
    local z = bestZone()
    return (z and (z.ZoneName or z._id)) or bestZoneId() or "?"
end

local function bestEgg()
    local now = os.clock()
    if cache.egg and now - cache.eggAt < 10 then
        if cache.egg.part and cache.egg.part.Parent == nil then
            cache.eggAt = 0 -- capsule part vanished (streaming) - re-resolve below
        else
            return cache.egg
        end
    end
    if not (isfn(G.EggCmds, "GetHighestEggNumberAvailable") and isfn(G.EggsUtil, "GetIdByNumber")) then
        return cache.egg
    end
    local n = gval(G.EggCmds.GetHighestEggNumberAvailable)
    if type(n) ~= "number" then return cache.egg end
    local id = gval(G.EggsUtil.GetIdByNumber, n)
    if type(id) == "table" then id = id._id end
    if type(id) ~= "string" then return cache.egg end
    local dir = type(G.Eggs) == "table" and G.Eggs[id] or nil
    local petIds = {}
    if dir and type(dir.pets) == "table" then
        for _, e in pairs(dir.pets) do
            if type(e) == "table" and type(e[1]) == "string" then
                petIds[e[1]] = true
            elseif type(e) == "string" then
                petIds[e] = true
            end
        end
    end
    local part = nil
    if isfn(G.EggsUtil, "GetEggPart") then
        local p = gval(G.EggsUtil.GetEggPart, n) -- egg NUMBER
        if typeof(p) == "Instance" then
            if p:IsA("BasePart") then
                part = p
            elseif p:IsA("Model") then
                part = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart", true)
            end
        end
    end
    cache.egg = { number = n, id = id, dir = dir, petIds = petIds, part = part, name = (dir and dir.name) or id }
    cache.eggAt = now
    return cache.egg
end

local function maxHatch()
    local now = os.clock()
    if cache.maxHatch and now - cache.maxHatchAt < 30 then return cache.maxHatch end
    local n = nil
    if isfn(G.EggCmds, "GetMaxHatch") then
        n = gval(G.EggCmds.GetMaxHatch) -- identity 2 required (gcall)
    end
    if type(n) ~= "number" or n < 1 then
        n = cache.maxHatch or 1 -- keep the last good value on a transient failure
    end
    cache.maxHatch = math.max(1, math.floor(n))
    cache.maxHatchAt = now
    return cache.maxHatch
end

local function inventory(category)
    local save = getSave()
    local inv = save and save.Inventory
    local cat = type(inv) == "table" and inv[category] or nil
    if type(cat) ~= "table" then return {} end
    return cat
end

-- sorted list of {uid, item, amount} (largest first); amount nil -> 1
local function stacks(category, predicate)
    local out = {}
    for uid, item in pairs(inventory(category)) do
        if type(item) == "table" then
            local amount = tonumber(item._am) or 1
            if amount >= 1 and (predicate == nil or predicate(item, amount)) then
                out[#out + 1] = { uid = uid, item = item, amount = amount }
            end
        end
    end
    table.sort(out, function(a, b) return a.amount > b.amount end)
    return out
end

-- first stack whose id is in the priority list (list order), else nil
local function pickByPriority(list, priority)
    for _, id in ipairs(priority or {}) do
        for _, s in ipairs(list) do
            if s.item.id == id then return s end
        end
    end
    return nil
end

-- stable order: priority ids first (in list order), then the rest by amount
local function orderByPriority(list, priority)
    local rank = {}
    for i, id in ipairs(priority or {}) do rank[id] = i end
    local out = {}
    for _, s in ipairs(list) do out[#out + 1] = s end
    table.sort(out, function(a, b)
        local ra, rb = rank[a.item.id] or 1e9, rank[b.item.id] or 1e9
        if ra ~= rb then return ra < rb end
        return a.amount > b.amount
    end)
    return out
end

-- ---- rank / goals ----------------------------------------------------------------
local function rankInfo()
    local save = getSave()
    if not save then return nil end
    local info = {}
    info.rankNumber = tonumber(save.Rank) or 1
    info.stars = tonumber(save.RankStars) or 0
    info.rebirths = tonumber(save.Rebirths) or 0
    info.rankId = isfn(G.RanksUtil, "RankIDFromNumber") and gval(G.RanksUtil.RankIDFromNumber, info.rankNumber) or nil
    info.rankDir = (info.rankId ~= nil and type(G.Ranks) == "table") and G.Ranks[info.rankId] or nil
    info.title = (info.rankDir and info.rankDir.Title) or tostring(info.rankId or ("Rank " .. info.rankNumber))
    info.rewards = (info.rankDir and type(info.rankDir.Rewards) == "table") and info.rankDir.Rewards or {}
    local total = nil
    if info.rankId ~= nil and isfn(G.RanksUtil, "GetTotalStarsRequired") then
        total = gval(G.RanksUtil.GetTotalStarsRequired, info.rankId)
    end
    if type(total) ~= "number" then
        total = 0
        for _, rw in ipairs(info.rewards) do
            total += tonumber(type(rw) == "table" and rw.StarsRequired) or 0
        end
    end
    info.totalStars = total
    info.redeemed = type(save.RedeemedRankRewards) == "table" and save.RedeemedRankRewards or {}
    local cnt = 0
    for _, v in pairs(info.redeemed) do
        if v then cnt += 1 end
    end
    info.redeemedCount = cnt
    info.allRedeemed = #info.rewards > 0 and cnt >= #info.rewards
    info.isMax = isfn(G.RankCmds, "IsMaxRank") and gval(G.RankCmds.IsMaxRank) == true
    info.blockedByZone, info.blockedByRebirth = false, false
    if isfn(G.RankCmds, "IsRankBlockedByZone") then
        local ok, bz, br, zn, rn = gcall(G.RankCmds.IsRankBlockedByZone)
        if ok then
            info.blockedByZone = bz == true
            info.blockedByRebirth = br == true
            info.zoneNumberNeeded = zn
            info.rebirthsNeeded = rn
        end
    end
    return info
end

-- Mirrors the game's "Redeem Rank Reward" loop: cumulative StarsRequired <= stars, key tostring(i)
local function earnedUnclaimedRewards(info)
    local out = {}
    if not info then return out end
    local cum = 0
    for i, rw in ipairs(info.rewards) do
        cum += tonumber(type(rw) == "table" and rw.StarsRequired) or 0
        if cum <= info.stars and info.redeemed[tostring(i)] == nil then
            out[#out + 1] = i
        end
    end
    return out
end

local function nextRewardIn(info)
    if not info then return nil end
    local cum = 0
    for _, rw in ipairs(info.rewards) do
        cum += tonumber(type(rw) == "table" and rw.StarsRequired) or 0
        if cum > info.stars then return cum - info.stars end
    end
    return nil
end

local function isSupported(t)
    if MINIGAME_DEFS[t] then return CONFIG.AutoMinigames end
    if t == 14 then return CONFIG.AutoFarm or CONFIG.AutoUpgradePotions end
    if t == 15 then return CONFIG.AutoFarm or CONFIG.AutoUpgradeEnchants end
    if FARM_GOALS[t] then return CONFIG.AutoFarm end
    if HATCH_GOALS[t] then return CONFIG.AutoHatch end
    if GOLD_GOALS[t] or RAINBOW_GOALS[t] then return CONFIG.AutoCraftGoldRainbow end
    if EVENT_GOAL_KIND[t] then return CONFIG.AutoSpawnEvents end
    if t == T_USE_POTION then return CONFIG.AutoUsePotions end
    if t == T_UPGRADE_POTION then return CONFIG.AutoUpgradePotions end
    if t == T_UPGRADE_ENCHANT then return CONFIG.AutoUpgradeEnchants end
    if t == T_USE_FRUIT then return CONFIG.AutoUseFruits end
    if t == T_USE_FLAG then return CONFIG.AutoUseFlags end
    if t == T_ZONE then return CONFIG.AutoBuyZones end
    return false
end

local titleCache, titleCacheCount = {}, 0
local function goalTitle(raw, copy)
    local key = tostring(copy.UID) .. ":" .. tostring(copy.Progress)
    local cached = titleCache[key]
    if cached then return cached end
    local title = nil
    if isfn(G.QuestCmds, "MakeTitle") then
        local ok, t = gcall(G.QuestCmds.MakeTitle, raw)
        if ok and type(t) == "string" and #t > 0 then title = t end
    end
    if not title then
        title = (GOAL_TYPE_NAMES[copy.Type] or ("Type " .. tostring(copy.Type))) .. " x" .. int(copy.Amount)
    end
    title = (string.gsub(title, "<[^>]->", "")) -- strip rich-text tags
    if titleCacheCount > 200 then
        titleCache, titleCacheCount = {}, 0
    end
    titleCache[key] = title
    titleCacheCount += 1
    return title
end

local function activeGoals()
    local save = getSave()
    local list, byType = {}, {}
    if not save or type(save.Goals) ~= "table" then return list, byType end
    for tier, g in pairs(save.Goals) do
        if type(g) == "table" and g.Type ~= nil then
            local amount = tonumber(g.Amount) or 0
            local progress = tonumber(g.Progress) or 0
            local copy = {
                tier = tier,
                Stars = tonumber(g.Stars) or 0,
                Type = g.Type,
                Amount = amount,
                Progress = progress,
                UID = g.UID,
                rankNumber = tonumber(save.Rank),
                rankStars = tonumber(save.RankStars) or 0,
                remaining = math.max(0, amount - progress),
                PotionTier = g.PotionTier,
                EnchantTier = g.EnchantTier,
                BreakableType = g.BreakableType,
                CurrencyID = g.CurrencyID,
                raw = g,
            }
            copy.title = goalTitle(g, copy)
            copy.supported = isSupported(copy.Type)
            list[#list + 1] = copy
            byType[copy.Type] = byType[copy.Type] or {}
            table.insert(byType[copy.Type], copy)
        end
    end
    table.sort(list, function(a, b)
        if a.Stars ~= b.Stars then return a.Stars > b.Stars end
        return tostring(a.tier) < tostring(b.tier)
    end)
    return list, byType
end

-- goal field (PotionTier / EnchantTier ...) with a fallback to the rank's goal pool
local function goalParam(goal, field)
    local v = goal[field]
    if v == nil and type(goal.raw) == "table" then v = goal.raw[field] end
    if v ~= nil then return v end
    local info = state.rank
    local pools = info and info.rankDir and info.rankDir.Goals
    if type(pools) ~= "table" then return nil end
    local pool = pools[goal.tier]
    if type(pool) ~= "table" then pool = pools[tonumber(goal.tier)] end
    if type(pool) ~= "table" then pool = pools[tostring(goal.tier)] end
    if type(pool) ~= "table" then return nil end
    local fallback = nil
    for _, entry in pairs(pool) do
        if type(entry) == "table" and entry.Type == goal.Type and entry[field] ~= nil then
            if entry.Amount == goal.Amount then return entry[field] end
            if fallback == nil then fallback = entry[field] end
        end
    end
    return fallback
end

-- live save goal with the same UID -> (goalTable or nil, saveAvailable)
local function findSaveGoal(goal)
    local save = getSave()
    if not (save and type(save.Goals) == "table") or goal.UID == nil then return nil, false end
    for _, g in pairs(save.Goals) do
        if type(g) == "table" and g.UID ~= nil and tostring(g.UID) == tostring(goal.UID)
            and tonumber(g.Type) == tonumber(goal.Type) then return g, true end
    end
    return nil, true
end

-- The second result distinguishes completion from retirement of a stale work item.
local function currentRemaining(goal)
    local tx = { goalUID = goal.UID, goalType = goal.Type, goalTier = goal.tier,
        goalAmount = goal.Amount, goalStars = goal.Stars or 0, originalRank = goal.rankNumber or (state.rank and state.rank.rankNumber),
        lastProgress = goal.Progress or 0, progressBaseline = goal.Progress or 0,
        baselineStars = goal.rankStars or 0 }
    local outcome, live = MinigameController.classify(getSave(), tx)
    if outcome == "ACTIVE" and live then
        return math.max(0, (tonumber(live.Amount) or 0) - (tonumber(live.Progress) or 0)), outcome
    end
    if outcome == "UNKNOWN" then return 0, outcome end -- wait for reliable save data before consuming items
    return 0, outcome -- zero cancels stale actions; it is not a success signal
end

-- Crystal rank helpers. Off by default; use only owned keys and live slot IDs.
local Crystal = {}
function Crystal.keyCount(save)
    local n = 0
    for _, item in pairs((save and save.Inventory and save.Inventory.Misc) or {}) do
        if type(item) == "table" and item.id == "Crystal Key" then n += math.max(0, tonumber(item._am) or 1) end
    end
    return n
end
function Crystal.inspect(save, info)
    if not save or not info or tonumber(save.Rank) ~= info.rankNumber then return nil, "waiting for rank data" end
    if type(save.Goals) ~= "table" then return nil, "waiting for rank data" end
    if info.isMax or info.blockedByZone or info.blockedByRebirth then return nil, "rank is complete or gated" end
    local pools = info.rankDir and info.rankDir.Goals
    local pool = type(pools) == "table" and (pools[1] or pools["1"])
    if type(pool) ~= "table" or next(pool) == nil then return nil, "rank quest pool unavailable" end
    local kinds = {}
    for _, goal in pairs(pool) do
        local t = type(goal) == "table" and tonumber(goal.Type)
        if t ~= 9 and t ~= 14 and t ~= 15 and t ~= 21 then return nil, "rank has other first-slot quests" end
        kinds[t] = true
    end
    if not (kinds[9] and kinds[21] and (kinds[14] or kinds[15])) then return nil, "rank pool does not match" end
    local first, diamond, area
    for tier, goal in pairs(save.Goals or {}) do
        if type(goal) == "table" and goal.UID ~= nil then
            local slot, t = tonumber(tier), tonumber(goal.Type)
            local rem = math.max(0, (tonumber(goal.Amount) or 0) - (tonumber(goal.Progress) or 0))
            if slot == 1 then first = goal
            elseif slot and slot > 1 and rem > 0 then
                if t == 9 then diamond = goal.UID elseif t == 21 then area = goal.UID end
            end
        end
    end
    if not (diamond and area) then return nil, "rerolling higher slots for both breakable quests" end
    if not first then return nil, "waiting for rank data" end
    if tonumber(first.Type) ~= 14 and tonumber(first.Type) ~= 15 then
        return nil, "clearing slot 1 for a collection quest"
    end
    return { rank = tonumber(save.Rank), diamond = diamond, area = area, first = first, keys = Crystal.keyCount(save) }
end
function Crystal.eligible()
    local c = state.crystal
    if not CONFIG.AutoCrystalRank or c.halted then return nil end
    if c.used + c.reserved >= math.max(0, tonumber(CONFIG.CrystalKeyLimit) or 5000) and not c.batch then return nil end
    local setup = Crystal.inspect(getSave(), state.rank)
    if not setup or setup.keys <= math.max(0, tonumber(CONFIG.CrystalKeyReserve) or 100) then return nil end
    return setup
end
function Crystal.holdsWork()
    if state.crystal and state.crystal.hold then return true end
    -- Eligibility cannot preempt a request/transition already owned by areas.
    local areas = state.areaProgression
    if areas and (areas.hold or areas.operation) then return false end
    return state.crystal and Crystal.eligible() ~= nil or false
end
function Crystal.equippedCount()
    if not isfn(G.PetCmds, "GetEquipped") then return nil end
    local value = gval(G.PetCmds.GetEquipped)
    if type(value) == "number" then return value end
    if type(value) == "table" then
        local n = 0
        for _ in pairs(value) do n += 1 end
        return n
    end
end
function Crystal.release()
    local c = state.crystal
    c.travelReady = false
    if c.pausedPets then
        c.pausedPets = false
        local ok, result = gcall(G.PetCmds.Restore)
        if not ok or result == false then warnlog("crystal-restore", "Pet restore failed; normal auto-equip will retry") end
    end
end
function Crystal.finish(reason, halt)
    local c = state.crystal
    c.hold, c.pins, c.batch, c.reserved = false, nil, nil, 0
    if halt then c.halted = reason end
    c.status = reason
    c.dataAt, c.rotationAt, c.chestWaitAt = nil, nil, nil
    Crystal.release()
    log("Crystal mode: %s", tostring(reason))
    writeStateFile()
end
function Crystal.waitForData()
    local c = state.crystal
    c.dataAt = c.dataAt or os.clock()
    c.status = "Crystal: waiting for replicated quest data"
    if os.clock() - c.dataAt > 15 then Crystal.finish("quest data did not arrive", true) end
end
function Crystal.pause()
    local c = state.crystal
    local count = Crystal.equippedCount()
    if count == nil or not isfn(G.PetCmds, "Restore") then
        Crystal.finish("Crystal paused: pet pause/restore interface unavailable", true)
        return false
    end
    if count == 0 then c.travelReady = true; return true end
    c.travelReady = false
    if not c.pausedPets then
        local remotes = RS:FindFirstChild("Network")
        local remote = remotes and remotes:FindFirstChild("Pets_UnequipAll")
        if not remote or not remote:IsA("RemoteEvent") then
            Crystal.finish("Crystal paused: pet unequip interface unavailable", true)
            return false
        end
        c.pausedPets, c.pauseAt = true, os.clock()
        local ok = netFire("Pets_UnequipAll")
        if not ok then Crystal.finish("Crystal paused: could not pause pets", true); return false end
        if Crystal.equippedCount() == 0 then c.travelReady = true; return true end
    elseif os.clock() - (c.pauseAt or os.clock()) > 15 then
        Crystal.finish("Crystal paused: pets did not stop within 15 seconds", true)
        return false
    end
    c.status = "Crystal: waiting for pets to pause"
    return false
end

-- ---- zone geometry -----------------------------------------------------------------
local function breakZonePart(zoneId)
    if cache.breakPart and cache.breakPartZone == zoneId and cache.breakPart.Parent then
        return cache.breakPart
    end
    local found = nil
    if isfn(G.ZonesUtil, "GetInteractFolder") then
        local folder = gval(G.ZonesUtil.GetInteractFolder, zoneId)
        if typeof(folder) == "Instance" then
            local bz = folder:FindFirstChild("BREAK_ZONES")
            if bz then
                for _, d in ipairs(bz:GetDescendants()) do
                    if d:IsA("BasePart") then
                        found = d
                        break
                    end
                end
            end
        end
    end
    if not found and isfn(G.MapCmds, "GetCurrentBreakZonePart") and isfn(G.MapCmds, "GetCurrentZone") then
        if gval(G.MapCmds.GetCurrentZone) == zoneId then
            local p = gval(G.MapCmds.GetCurrentBreakZonePart)
            if typeof(p) == "Instance" and p:IsA("BasePart") then found = p end
        end
    end
    cache.breakPart = found
    cache.breakPartZone = zoneId
    return found
end

local function standPosition(zoneId)
    local part = breakZonePart(zoneId)
    if part then return part.Position + Vector3.new(0, 4, 0) end
    if isfn(G.ZonesUtil, "GetTeleportPartLocation") then
        local cf = gval(G.ZonesUtil.GetTeleportPartLocation, zoneId) -- zone id STRING
        if typeof(cf) == "CFrame" then return cf.Position + Vector3.new(0, 3, 0) end
        if typeof(cf) == "Vector3" then return cf + Vector3.new(0, 3, 0) end
    end
    return nil
end

-- current zone id and whether we stand in its dotted box
local function currentZoneInfo()
    local cz = isfn(G.MapCmds, "GetCurrentZone") and gval(G.MapCmds.GetCurrentZone) or nil
    local inBox = isfn(G.MapCmds, "IsInDottedBox") and gval(G.MapCmds.IsInDottedBox) or nil
    return cz, inBox
end

local lastEnsureAt = 0
-- Teleports the character into the best zone's break zone when away. Rate limited (3 s).
local function ensureInBestZone()
    if not normalWorkAllowed() then return end
    if Crystal.holdsWork() then return false end
    if state.hopping or state.worldSwitching or state.worldMismatch then return false end
    local now = os.clock()
    local force = state.returnAfterHatch ~= nil and now >= state.returnAfterHatch
    if not force and now - lastEnsureAt < 3 then return false end
    lastEnsureAt = now
    if inInstance() then
        logEvery("ensure-instance", 30, "In an instance - not teleporting to the break zone")
        return false
    end
    local zoneId = bestZoneId()
    if not zoneId then return false end
    local pos = standPosition(zoneId)
    if not pos then
        logEvery("ensure-nopos", 60, "Cannot resolve the break zone position of %s yet", tostring(zoneId))
        return false
    end
    local hrp = getHRP()
    if not hrp then return false end
    local cz = isfn(G.MapCmds, "GetCurrentZone") and gval(G.MapCmds.GetCurrentZone) or nil
    local dist = (hrp.Position - pos).Magnitude
    if not normalWorkAllowed() then return false end
    if dist > CONFIG.ZonePositionTolerance or (cz ~= nil and cz ~= zoneId) then
        pcall(function()
            hrp.CFrame = CFrame.new(pos)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        state.returnAfterHatch = nil
        logEvery("ensure-tp", 10, "Teleported into the break zone of %s (was %s studs away)", tostring(zoneId), int(dist))
        return true
    end
    state.returnAfterHatch = nil
    return false
end

-- =====================================================================================
-- 10. Patches (speed hook, super magnet, hatch animation)
-- =====================================================================================
local function installSpeedHook()
    if type(hookfunction) ~= "function" then
        logOnce("nohook", "hookfunction unavailable - InfinitePetSpeed disabled")
        return
    end
    if not isfn(G.PlayerPet, "CalculateSpeedMultiplier") then
        logOnce("nospeedfn", "PlayerPet.CalculateSpeedMultiplier missing - InfinitePetSpeed disabled")
        return
    end
    local orig = nil
    local ok, err = pcall(function()
        orig = hookfunction(G.PlayerPet.CalculateSpeedMultiplier, function(...)
            if CONFIG.InfinitePetSpeed and state.alive then return math.huge end
            if type(orig) == "function" then return orig(...) end
            return 1
        end)
    end)
    if ok and type(orig) == "function" then
        log("Infinite pet speed hook installed")
    else
        warnlog("speedhook", "pet speed hook failed: %s", tostring(err or "no original returned"))
    end
end

local magnetBackup = setmetatable({}, { __mode = "k" })
local function applyMagnetConfig(r)
    if type(r) ~= "table" then return end
    if CONFIG.SuperMagnet and state.alive then
        if type(r.config) ~= "table" then r.config = {} end
        if magnetBackup[r.config] == nil then
            magnetBackup[r.config] = { orig = r.config.SuperMagnet }
        end
        r.config.SuperMagnet = true
    elseif type(r.config) == "table" and magnetBackup[r.config] then
        r.config.SuperMagnet = magnetBackup[r.config].orig
        magnetBackup[r.config] = nil
    end
end

local function installMagnet()
    local applied = 0
    local function patch(key, fn)
        local mod = G[key] or loadModule(key, OPTIONAL_MODULE_PATHS[key] or MODULE_PATHS[key], true)
        if type(mod) ~= "table" then return end
        pcall(function()
            if type(setreadonly) == "function" then setreadonly(mod, false) end
        end)
        local ok, err = pcall(fn, mod)
        if ok then
            applied += 1
        else
            warnlog("magnet-" .. key, "super magnet patch %s failed: %s", key, tostring(err))
        end
    end
    patch("EnchantCmds", function(e)
        local o = e.GetPower
        if type(o) ~= "function" then error("no GetPower") end
        e.GetPower = function(...)
            local p = ...
            if CONFIG.SuperMagnet and state.alive and (p == "Super Magnet" or p == "Magnet") then return 999 end
            return o(...)
        end
        restoreFns[#restoreFns + 1] = function() e.GetPower = o end
    end)
    patch("UpgradeCmds", function(u)
        local o = u.GetPower
        if type(o) ~= "function" then error("no GetPower") end
        u.GetPower = function(...)
            if CONFIG.SuperMagnet and state.alive and (...) == "Magnet" then return 999 end
            return o(...)
        end
        restoreFns[#restoreFns + 1] = function() u.GetPower = o end
    end)
    patch("InstancingCmds", function(i)
        local g = i.Get
        if type(g) ~= "function" then error("no Get") end
        i.Get = function(...)
            local r = g(...)
            if type(r) == "table" then pcall(applyMagnetConfig, r) end
            return r
        end
        restoreFns[#restoreFns + 1] = function() i.Get = g end
    end)
    if applied > 0 then
        log("Super magnet patches applied (%d/3)", applied)
    else
        warnlog("magnet-none", "no super magnet patch could be applied")
    end
end

-- Waits (up to 10 s per segment) for the Egg Opening Frontend script, then stubs PlayEggAnimation.
local function installNoHatchAnimation()
    if type(getsenv) ~= "function" then
        logOnce("nogetsenv", "getsenv unavailable - hatch animation stays on")
        return
    end
    task.spawn(function()
        local ok, err = pcall(function()
            local function segment(parent, name)
                if not parent then return nil end
                local child = parent:FindFirstChild(name)
                if child then return child end
                return parent:WaitForChild(name, 10)
            end
            local ps = segment(LocalPlayer, "PlayerScripts")
            local scripts = segment(ps, "Scripts")
            local gameFolder = segment(scripts, "Game")
            local eggScript = segment(gameFolder, "Egg Opening Frontend")
            if not eggScript then error("Egg Opening Frontend script not found (waited up to 10 s per segment)") end
            if not state.alive then return end
            local env = getsenv(eggScript)
            if type(env) ~= "table" then error("getsenv returned " .. typeof(env)) end
            local orig = env.PlayEggAnimation
            env.PlayEggAnimation = function() end
            restoreFns[#restoreFns + 1] = function()
                if orig ~= nil then env.PlayEggAnimation = orig end
            end
        end)
        if not state.alive then return end
        if ok then
            log("Hatch animation disabled")
        else
            warnlog("noanim", "could not disable hatch animation: %s", tostring(err))
        end
    end)
end

local function installPatches()
    if CONFIG.InfinitePetSpeed then pcall(installSpeedHook) end
    if CONFIG.SuperMagnet then pcall(installMagnet) end
    if CONFIG.DisableHatchAnimation then pcall(installNoHatchAnimation) end
end

-- =====================================================================================
-- 11. Anti-AFK (identity 8)
-- =====================================================================================
local function installAntiAfk()
    pcall(function()
        if type(getconnections) == "function" then
            for _, c in ipairs(getconnections(LocalPlayer.Idled)) do
                if c.Disable then
                    c:Disable()
                elseif c.Disconnect then
                    c:Disconnect()
                end
            end
        end
    end)
    track(LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
    log("Anti-AFK installed")
end

-- =====================================================================================
-- 12. Farm thread
-- =====================================================================================
local breakAssign = {}          -- pet euid -> breakable uid (sticky)
local farmTapCursor = 0
local breakablesFolderCache = nil
local lastEquipBestAt = 0

local function breakablesFolder()
    if breakablesFolderCache and breakablesFolderCache.Parent then return breakablesFolderCache end
    local things = workspace:FindFirstChild("__THINGS")
    local f = things and things:FindFirstChild("Breakables") or nil
    breakablesFolderCache = f
    return f
end

-- 1 = events/chests, 2 = diamond, 3 = everything else.
-- Recognize diamond piles before the broad non-Normal event-class rule.
-- Keep event word matching for chest classes whose names vary between updates.
local function classifyBreakable(m)
    local id = string.lower(tostring(m:GetAttribute("BreakableID") or ""))
    local class = m:GetAttribute("BreakableClass")
    for _, w in ipairs(EVENT_BREAKABLE_WORDS) do
        if string.find(id, w, 1, true) then return 1 end
    end
    if string.find(id, "diamond", 1, true) then return 2 end
    if class ~= nil and class ~= "Normal" then return 1 end
    return 3
end

local function collectBreakables(zoneId)
    local p1, p2, p3 = {}, {}, {}
    local folder = breakablesFolder()
    if not folder or not zoneId then return p1, p2, p3 end
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("ParentID") == zoneId then
            local uid = m:GetAttribute("BreakableUID")
            if uid ~= nil then
                local pr = classifyBreakable(m)
                if pr == 1 then
                    p1[#p1 + 1] = uid
                elseif pr == 2 then
                    p2[#p2 + 1] = uid
                else
                    p3[#p3 + 1] = uid
                end
            end
        end
    end
    return p1, p2, p3
end

local function petEuids()
    if not isfn(G.PlayerPet, "GetAll") then return {} end
    local ok, out = gcall(function()
        local res = {}
        local all = G.PlayerPet.GetAll()
        if type(all) ~= "table" then return res end
        local belongs = type(G.PlayerPet.BelongsToLocalPlayer) == "function" and G.PlayerPet.BelongsToLocalPlayer or nil
        local unfiltered = {}
        for _, p in pairs(all) do
            if type(p) == "table" and p.euid ~= nil then
                unfiltered[#unfiltered + 1] = p.euid
                local keep = true
                if belongs then
                    local okB, r = pcall(belongs, p)
                    if okB and r == false then keep = false end
                end
                if keep then res[#res + 1] = p.euid end
            end
        end
        -- safety net: if the ownership filter rejected every pet (unexpected API shape), farm with all of them
        if #res == 0 and #unfiltered > 0 then
            logEvery("pets-unfiltered", 60, "BelongsToLocalPlayer rejected all %d pets - using the unfiltered list", #unfiltered)
            return unfiltered
        end
        return res
    end)
    if ok and type(out) == "table" then return out end
    return {}
end

local lastEquipCheckAt = 0
-- Calls PetCmds.EquipBest() only when GetEquipped() POSITIVELY reports zero pets (fail closed: EquipBest
-- re-equips the whole team, so an unknown return shape or a failed call must never trigger it).
local function maybeEquipBest()
    if not normalWorkAllowed() then return end
    if not CONFIG.AutoEquipBestPets then return end
    local now = os.clock()
    if now - lastEquipBestAt < 30 or now - lastEquipCheckAt < 5 then return end
    lastEquipCheckAt = now
    if not (isfn(G.PetCmds, "GetEquipped") and isfn(G.PetCmds, "EquipBest")) then return end
    local okEq, eq = gcall(G.PetCmds.GetEquipped)
    if not okEq then
        warnlog("getequipped", "PetCmds.GetEquipped failed (%s) - EquipBest skipped", tostring(eq))
        return
    end
    -- known shapes: table (list/dict of equipped pets) or number (count)
    if type(eq) == "table" then
        if next(eq) ~= nil then return end            -- pets equipped
    elseif type(eq) == "number" then
        if eq > 0 then return end                     -- pets equipped
    else
        -- nil / boolean / userdata / string: shape unknown, do not act blindly
        warnlog("getequipped", "PetCmds.GetEquipped returned %s - EquipBest skipped", typeof(eq))
        return
    end
    lastEquipBestAt = now
    local ok, err = gcall(G.PetCmds.EquipBest)
    if ok then
        log("No pets equipped - PetCmds.EquipBest() called")
    else
        warnlog("equipbest", "EquipBest failed: %s", tostring(err))
    end
end

-- true when a DIAMOND_BREAKABLE goal still has remaining amount
local function wantsDiamonds()
    for _, g in ipairs(state.goalsByType[T_DIAMOND] or {}) do
        if g.remaining > 0 then return true end
    end
    return false
end

-- Share the team across every nonempty group. With enough pets each group
-- receives at least one pet; a diamond quest increases its share, never monopolizes it.
local function assignFarmPets(pets, groups, previous, rotation)
    local map, counts, quota, groupOf = {}, {}, {}, {}
    local n, count = #pets, #groups
    if n == 0 or count == 0 then return map, counts end
    local weightSum = 0
    for i, group in ipairs(groups) do
        quota[i] = 0
        counts[i] = 0
        group.used = {}
        group.nextTarget = 1
        for _, uid in ipairs(group.targets) do groupOf[uid] = i end
        weightSum = weightSum + group.weight
    end
    if n < count then
        -- Tiny teams rotate groups every three seconds so no quest waits forever.
        for i = 1, n do quota[((rotation + i - 1) % count) + 1] = 1 end
    else
        local remaining, assigned, fractions = n - count, count, {}
        for i, group in ipairs(groups) do
            local share = remaining * group.weight / weightSum
            local extra = math.floor(share)
            quota[i] = 1 + extra
            assigned = assigned + extra
            fractions[i] = share - extra
        end
        while assigned < n do
            local best = 1
            for i = 2, count do
                if fractions[i] > fractions[best] then best = i end
            end
            quota[best] = quota[best] + 1
            fractions[best] = -1
            assigned = assigned + 1
        end
    end
    -- Preserve one existing pet per target first; duplicates can move to new targets.
    for _, pet in ipairs(pets) do
        local uid = previous[pet]
        local i = uid ~= nil and groupOf[uid] or nil
        if i and counts[i] < quota[i] and not groups[i].used[uid] then
            map[pet] = uid
            counts[i] = counts[i] + 1
            groups[i].used[uid] = true
        end
    end
    for _, group in ipairs(groups) do
        group.free = {}
        for _, uid in ipairs(group.targets) do
            if not group.used[uid] then group.free[#group.free + 1] = uid end
        end
        group.nextFree = 1
    end
    for _, pet in ipairs(pets) do
        if map[pet] == nil then
            local old = previous[pet]
            local i = old ~= nil and groupOf[old] or nil
            if not i or counts[i] >= quota[i] then
                i = nil
                for candidate = 1, count do
                    if counts[candidate] < quota[candidate] then i = candidate; break end
                end
            end
            if i then
                local group = groups[i]
                local uid = group.free[group.nextFree]
                if uid ~= nil then
                    group.nextFree = group.nextFree + 1
                elseif old ~= nil and groupOf[old] == i then
                    uid = old
                else
                    uid = group.targets[group.nextTarget]
                    group.nextTarget = (group.nextTarget % #group.targets) + 1
                end
                map[pet] = uid
                counts[i] = counts[i] + 1
            end
        end
    end
    return map, counts
end

local function farmTick()
    if not normalWorkAllowed() then return end
    if Crystal.holdsWork() then Crystal.pause(); return end
    if not CONFIG.AutoFarm then return end
    if state.worldSwitching or state.worldMismatch then return end
    if inInstance() then return end
    ensureInBestZone()
    local zoneId = bestZoneId()
    if not zoneId then return end
    local pets = petEuids()
    state.farmPets = #pets
    if #pets == 0 then
        -- only consult GetEquipped/EquipBest when the farm loop's own verified pet view
        -- (PlayerPet.GetAll + BelongsToLocalPlayer) shows no local pets
        maybeEquipBest()
        return
    end
    local p1, p2, p3 = collectBreakables(zoneId)
    local groups, targets = {}, {}
    local function addGroup(name, list, weight)
        if #list == 0 then return end
        groups[#groups + 1] = { name = name, targets = list, weight = weight }
        for _, uid in ipairs(list) do targets[#targets + 1] = uid end
    end
    addGroup("events", p1, 2)
    addGroup("diamonds", p2, wantsDiamonds() and 2 or 1)
    addGroup("farming", p3, 1)
    state.farmTargets = #targets
    state.farmAllocation = {}
    if #targets == 0 then breakAssign = {}; return end
    local map, counts = assignFarmPets(pets, groups, breakAssign, math.floor(os.clock() / 3))
    breakAssign = map
    for i, group in ipairs(groups) do state.farmAllocation[group.name] = counts[i] end
    if next(map) == nil then return end
    farmTapCursor = (farmTapCursor % #targets) + 1
    netUnreliable("Breakables_PlayerDealDamage", targets[farmTapCursor])
    local ok, err = netFire("Breakables_JoinPetBulk", map)
    if ok then
        state.counters.farmTicks += 1
    else
        warnlog("farm-fire", "Breakables_JoinPetBulk failed: %s", tostring(err))
    end
end

-- Fast path: a new event requests the same shared scheduler as the regular farm loop.
-- Cheap checks run inline; only a breakable whose attributes have not replicated yet is deferred one frame.
local function onBreakableAdded(m)
    if not normalWorkAllowed() then return end
    if Crystal.holdsWork() then return end
    if not (state.alive and CONFIG.AutoFarm) or state.worldSwitching or state.worldMismatch then return end
    if typeof(m) ~= "Instance" or not m:IsA("Model") then return end
    local zoneId = cache.zoneId or bestZoneId()
    if not zoneId then return end
    local function handle()
        if not normalWorkAllowed() then return end
        state.normalWorkers.fastFarm = (state.normalWorkers.fastFarm or 0) + 1
        state.normalThreads[coroutine.running()] = true
        local ok, err = pcall(function()
            if not normalWorkAllowed() or m.Parent == nil then return end
            if m:GetAttribute("ParentID") ~= zoneId then return end
            if classifyBreakable(m) ~= 1 then return end
            local uid = m:GetAttribute("BreakableUID")
            if uid == nil then return end
            if inInstance() then return end -- cached (1 s)
            farmTick()
            state.counters.eventTargets += 1
            log("Event breakable '%s' appeared - sharing pets across farm targets (%s caught so far)",
                tostring(m:GetAttribute("BreakableID") or m.Name), int(state.counters.eventTargets))
        end)
        state.normalWorkers.fastFarm -= 1
        state.normalThreads[coroutine.running()] = nil
        if not ok then warnlog("fastpath", "breakable fast-path error: %s", tostring(err)) end
    end
    if m:GetAttribute("ParentID") == nil then
        task.defer(handle) -- attributes may replicate a frame after the instance
    else
        handle()
    end
end

local function installBreakableListener()
    task.spawn(function()
        local folder = nil
        local t0 = os.clock()
        while state.alive and not folder and os.clock() - t0 < 180 do
            folder = breakablesFolder()
            if not folder then task.wait(1) end
        end
        if not folder or not state.alive then
            if state.alive then warnlog("nobreakables", "workspace.__THINGS.Breakables not found - fast path disabled") end
            return
        end
        track(folder.ChildAdded:Connect(onBreakableAdded))
        log("Breakable fast-path listener installed")
    end)
end

-- =====================================================================================
-- 13. Hatch thread
-- =====================================================================================
local hatchFailures = 0
local hatchBackoffUntil = 0
local hatchNeedsHop = false     -- the last request failed from afar: retry next to the egg
local hopFailedEggId = nil      -- egg whose retry next to the egg also failed: distance is not the cause, stop hopping for it

local function hatchAmount()
    local amount = maxHatch()
    local plan = state.plan
    if plan.hatchEggOnly and type(plan.hatchRemaining) == "number" and plan.hatchRemaining > 0 then
        amount = math.min(amount, plan.hatchRemaining)
    end
    return math.max(1, math.floor(amount))
end

local function hatchPlanned()
    return CONFIG.AutoHatch and (CONFIG.AlwaysHatch or state.plan.hatch == true)
end

local function hatchTick()
    if not normalWorkAllowed() then return end
    if Crystal.holdsWork() then return end
    if not hatchPlanned() then return end
    if state.worldSwitching or state.worldMismatch then return end
    if os.clock() < hatchBackoffUntil then return end
    if inInstance() then return end
    local egg = bestEgg()
    if not (egg and egg.id) then
        warnlog("no-egg", "cannot resolve the best egg")
        return
    end
    local amount = hatchAmount()
    local hrp = getHRP()
    local part = egg.part
    local far = hrp ~= nil and part ~= nil and part.Parent ~= nil
        and (hrp.Position - part.Position).Magnitude > CONFIG.HatchMaxDistance
    local hopped = false
    if not normalWorkAllowed() then return end
    if far and hatchNeedsHop and hopFailedEggId ~= egg.id then
        state.hopping = true
        hopped = true
        pcall(function()
            hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 6))
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        task.wait(0.2)
    end
    if not normalWorkAllowed() then state.hopping = false; return end
    local ok, res, msg = netInvoke("Eggs_RequestPurchase", egg.id, amount) -- egg ID string
    if not normalWorkAllowed() then state.hopping = false; return end
    if hopped then
        state.hopping = false
        state.returnAfterHatch = os.clock() + 1
    end
    if ok and res == true then
        hatchFailures = 0
        hatchNeedsHop = false
        hopFailedEggId = nil
        state.counters.hatched += amount
        -- Keep the live plan honest until the controller rebuilds it (<= ControllerTick later):
        -- the hatch loop (HatchDelay 0.75 s + invoke RTT) can fire twice inside one controller period.
        -- Read state.plan AFTER the invoke on purpose: if the controller rebuilt it from a not-yet-replicated
        -- save during the yield, this still suppresses the duplicate batch.
        local plan = state.plan
        if plan.hatchEggOnly and type(plan.hatchRemaining) == "number" then
            plan.hatchRemaining -= amount
            if plan.hatchRemaining <= 0 then plan.hatch = false end
        end
        logEvery("hatch-ok", 30, "Hatching %s x%d (total %d)", tostring(egg.name or egg.id), amount, state.counters.hatched)
    else
        hatchFailures += 1
        local delays = { 1, 2, 5 }
        local d = delays[math.min(hatchFailures, 3)]
        hatchBackoffUntil = os.clock() + d
        -- a failure from afar -> retry ONCE next to the egg; a failure next to the egg -> distance was not the cause,
        -- so never hop again for this egg until a hatch succeeds (or the best egg changes)
        if hopped then hopFailedEggId = egg.id end
        hatchNeedsHop = far and not hopped and hopFailedEggId ~= egg.id
        local reason = ok and tostring(msg or res) or tostring(res)
        -- fixed throttle key: the server reply text is unbounded and must not defeat the 30 s throttle
        warnlog("hatch-fail", "hatch %s x%d failed (%s) - backing off %d s%s", tostring(egg.id), amount, reason, d,
            hatchNeedsHop and ", retrying next to the egg" or "")
    end
end

-- =====================================================================================
-- 14. Crafting / consumables thread (goal handlers)
-- =====================================================================================
local function protectedSet()
    local s = {}
    for _, id in ipairs(CONFIG.ProtectedPetIds or {}) do s[id] = true end
    return s
end

-- pet stacks of one type (0 normal, 1 golden, 2 rainbow) usable as fodder
local function fodderStacks(ptWanted, allowedIds)
    local prot = protectedSet()
    return stacks("Pet", function(item, _)
        if type(item.id) ~= "string" then return false end
        local pt = tonumber(item.pt) or 0
        if pt ~= ptWanted then return false end
        if allowedIds and not allowedIds[item.id] then return false end
        if item.sh == true and not CONFIG.UseShinyPetsAsFodder then return false end
        if prot[item.id] then return false end
        return true
    end)
end

-- returns ok, allowedIds (set, or nil = any pet), label for log messages
local function craftAllowedIds(goal)
    if BEST_EGG_ONLY_CRAFT[goal.Type] then
        local egg = bestEgg()
        if not (egg and egg.petIds and next(egg.petIds) ~= nil) then
            warnlog("craft-noegg", "cannot resolve best-egg pets for goal %s", tostring(goal.title))
            return false, nil, nil
        end
        return true, egg.petIds, tostring(egg.name or egg.id)
    end
    return true, nil, "best-egg" -- any pet qualifies, but a shortage is still covered by hatching the best egg
end

-- Smallest live remaining of the active gold goals (nil when none is active).
-- Golden pets crafted as an intermediate step for a rainbow goal also progress a gold goal.
local function goldGoalCap()
    local cap = nil
    for t in pairs(GOLD_GOALS) do
        for _, g in ipairs(state.goalsByType[t] or {}) do
            local live = findSaveGoal(g)
            if live then
                local r = math.max(0, (tonumber(live.Amount) or 0) - (tonumber(live.Progress) or 0))
                cap = cap and math.min(cap, r) or r
            end
        end
    end
    return cap
end

-- Crafts up to 'rem' golden outputs from normal stacks. capFn() (optional) returns a fresh cap that is
-- re-applied after every successful invoke (re-reads the save).
-- Returns (crafted, remainingNeeded, largestNormalStack) - largestNormalStack is nil after a remote failure.
local function craftGoldenFrom(normalStacks, rem, logSuffix, capFn)
    local crafted = 0
    for _, s in ipairs(normalStacks) do
        if rem <= 0 then break end
        while rem > 0 and s.amount >= 10 and normalWorkAllowed() do
            local k = math.min(math.floor(s.amount / 10), rem, MAX_CRAFT_PER_CALL)
            local ok, res, msg = netInvoke("GoldMachine_Activate", s.uid, k) -- amount = OUTPUT pets
            if ok and res == true then
                crafted += k
                rem -= k
                s.amount -= k * 10
                state.counters.crafted += k
                log("Crafted %d golden %s%s", k, tostring(s.item.id), logSuffix or "")
                task.wait(0.5)
                if capFn then
                    local c = capFn()
                    if type(c) == "number" then rem = math.min(rem, c) end
                end
            else
                warnlog("gold-fail", "GoldMachine_Activate failed: %s", tostring(ok and (msg or res) or res))
                return crafted, rem, nil
            end
        end
    end
    -- per-stack: GoldMachine_Activate consumes 10 pets of ONE stack, so partial stacks of different ids never add up
    local best = 0
    for _, s in ipairs(normalStacks) do best = math.max(best, s.amount) end
    return crafted, rem, best
end

local function fodderReason(left, leftover, label, goal)
    if left > 0 and leftover ~= nil then
        -- after an exhausted craft loop every stack is < 10, so outputs still owed always need a hatch
        local need = math.max(1, left * 10 - leftover)
        return string.format("need %d more normal %s pets for %s", need, tostring(label), GOAL_TYPE_NAMES[goal.Type] or "crafting")
    end
    return nil
end

-- returns a hatch reason string when fodder is missing, else nil
local function handleGoldCraft(goal)
    local ok, allowed, label = craftAllowedIds(goal)
    if not ok then return nil end
    local rem = currentRemaining(goal)
    if rem <= 0 then return nil end
    local normal = fodderStacks(0, allowed)
    local _, left, leftover = craftGoldenFrom(normal, rem, "", function() return currentRemaining(goal) end)
    return fodderReason(left, leftover, label, goal)
end

-- Crafts up to 'rem' rainbow outputs from golden stacks. Returns (remainingNeeded, ok).
local function craftRainbowFrom(goldenStacks, rem, goal)
    for _, s in ipairs(goldenStacks) do
        if rem <= 0 then break end
        while rem > 0 and s.amount >= 10 and normalWorkAllowed() do
            local k = math.min(math.floor(s.amount / 10), rem, MAX_CRAFT_PER_CALL)
            local ok, res, msg = netInvoke("RainbowMachine_Activate", s.uid, k) -- amount = OUTPUT pets
            if ok and res == true then
                rem -= k
                s.amount -= k * 10
                state.counters.crafted += k
                log("Crafted %d rainbow %s", k, tostring(s.item.id))
                task.wait(0.5)
                rem = math.min(rem, currentRemaining(goal))
            else
                warnlog("rainbow-fail", "RainbowMachine_Activate failed: %s", tostring(ok and (msg or res) or res))
                return rem, false
            end
        end
    end
    return rem, true
end

local function handleRainbowCraft(goal)
    local okIds, allowed, label = craftAllowedIds(goal)
    if not okIds or not normalWorkAllowed() then return nil end
    local rem = currentRemaining(goal)
    if rem <= 0 then return nil end
    -- step 1: rainbows from golden stacks (10 golden -> 1 rainbow)
    local golden = fodderStacks(1, allowed)
    local okStep
    rem, okStep = craftRainbowFrom(golden, rem, goal)
    if rem <= 0 or not okStep then return nil end
    -- step 2: golden pets of ONE pet id are needed (10 golden of the SAME id -> 1 rainbow), so the
    -- intermediate golden crafts are concentrated on a single id instead of being spread across ids
    local goldenById = {}
    for _, s in ipairs(golden) do
        goldenById[s.item.id] = (goldenById[s.item.id] or 0) + s.amount
    end
    local normal = fodderStacks(0, allowed)
    -- prefer the id that already holds the most golden pets, then the biggest normal stack
    table.sort(normal, function(a, b)
        local ga, gb = goldenById[a.item.id] or 0, goldenById[b.item.id] or 0
        if ga ~= gb then return ga > gb end
        return a.amount > b.amount
    end)
    local src = normal[1]
    if not src then
        return fodderReason(rem * 10, 0, label, goal)
    end
    local goldenNeeded = rem * 10 - (goldenById[src.item.id] or 0)
    if goldenNeeded <= 0 then return nil end -- the next pass crafts the rainbows
    -- a concurrent gold goal also counts these golden crafts: never overshoot it
    local goldCap = goldGoalCap()
    if goldCap ~= nil then
        if goldCap <= 0 then
            logEvery("rainbow-goldcap", 30, "Waiting for the gold goal to refresh before crafting golden pets for %s", tostring(goal.title))
            return nil
        end
        goldenNeeded = math.min(goldenNeeded, goldCap)
    end
    local made, left, leftover = craftGoldenFrom({ src }, goldenNeeded, " (for rainbow goal)", goldCap ~= nil and goldGoalCap or nil)
    if made > 0 then
        -- fresh golden pets: run the rainbow step again right away instead of waiting for the next tick
        task.wait(0.75)
        rem = currentRemaining(goal)
        if rem > 0 then
            craftRainbowFrom(fodderStacks(1, allowed), rem, goal)
        end
    end
    return fodderReason(left, leftover, label, goal)
end

local function tierRequirement(kind, srcTier)
    local fn, fb
    if kind == "potion" then
        fn = G.CalcPotionsPerTierRequired
        fb = POTION_TIER_REQ_FALLBACK
    else
        fn = G.CalcEnchantsPerTierRequired
        fb = ENCHANT_TIER_REQ_FALLBACK
    end
    if type(fn) == "function" then
        local n = gval(fn, srcTier) -- identity 2
        if type(n) == "number" and n >= 1 then return math.floor(n) end
    end
    return fb[srcTier] or fb[#fb] or 3
end

local function handleUsePotions(goal)
    local T = tonumber(goalParam(goal, "PotionTier"))
    if not T then
        warnOnce("notier:" .. tostring(goal.UID), "USE_POTION goal '%s' has no PotionTier - skipping", tostring(goal.title))
        return
    end
    local rem = currentRemaining(goal)
    if rem <= 0 then return end
    local n = math.min(rem, 10)
    local used = 0
    while used < n and normalWorkAllowed() do
        local list = stacks("Potion", function(item, _) return tonumber(item.tn) == T end)
        local s = pickByPriority(list, CONFIG.PotionUsePriority) or list[1]
        if not s then
            warnOnce("noitem:" .. tostring(goal.UID), "No tier %d potions left in inventory (%s)", T, tostring(goal.title))
            break
        end
        local ok, err = netFire("Potions: Consume", s.uid, 1)
        if not ok then
            warnlog("potion-fail", "Potions: Consume failed: %s", tostring(err))
            break
        end
        used += 1
        state.counters.itemsUsed += 1
        task.wait(0.4)
    end
    if used > 0 then log("Used %d tier %d potion(s) (%s)", used, T, tostring(goal.title)) end
end

local function upgradeStacks(category, srcTier, priority, dirTable, targetTier)
    local list = stacks(category, function(item, _)
        if tonumber(item.tn) ~= srcTier then return false end
        local dirEntry = type(dirTable) == "table" and item.id ~= nil and dirTable[item.id] or nil
        local maxTier = dirEntry and tonumber(dirEntry.MaxTier) or nil
        if maxTier and maxTier < targetTier then return false end
        return true
    end)
    return orderByPriority(list, priority)
end

local function handleUpgrade(goal, kind)
    local isPotion = kind == "potion"
    local field = isPotion and "PotionTier" or "EnchantTier"
    local T = tonumber(goalParam(goal, field))
    -- Tier V is the highest OUTPUT. Never consume tier V to create tier VI.
    if not T or T < 2 or T > 5 or T ~= math.floor(T) then
        warnOnce("notier:" .. tostring(goal.UID), "%s upgrade target must be tier II-V; got %s", kind, tostring(T))
        return
    end
    local rem = currentRemaining(goal)
    if rem <= 0 then return end
    local dirTable
    if isPotion then dirTable = G.Potions else dirTable = G.Enchants end
    local category = isPotion and "Potion" or "Enchant"
    local priority = isPotion and CONFIG.PotionUpgradePriority or CONFIG.EnchantUpgradePriority
    local remote = isPotion and "UpgradePotionsMachine_Activate" or "UpgradeEnchantsMachine_Activate"
    local usable = 0
    -- Always start at I. Re-read inventory at each tier so newly made items
    -- can feed the next step. Intermediate outputs do NOT count as quest outputs.
    for srcTier = 1, T - 1 do
        rem = math.min(rem, currentRemaining(goal))
        if rem <= 0 or not normalWorkAllowed() then return end
        local need = tierRequirement(kind, srcTier)
        local budget = rem
        for intermediate = srcTier + 1, T - 1 do
            budget = budget * tierRequirement(kind, intermediate)
        end
        -- Limit work per tier per tick; continue the chain on the next tick.
        budget = math.min(budget, MAX_UPGRADE_PER_CALL)
        local list = upgradeStacks(category, srcTier, priority, dirTable, T)
        for _, s in ipairs(list) do
            if budget <= 0 or not normalWorkAllowed() then break end
            rem = math.min(rem, currentRemaining(goal))
            if rem <= 0 then return end
            if srcTier == T - 1 then budget = math.min(budget, rem) end
            if s.amount >= need then
                usable = usable + 1
                local k = math.min(math.floor(s.amount / need), budget)
                local ok, res, msg = netInvoke(remote, s.uid, k)
                if ok and res == true then
                    budget = budget - k
                    if srcTier == T - 1 then rem = rem - k end
                    state.counters.crafted = state.counters.crafted + k
                    log("Upgraded %d x %s %s T%d -> T%d", k, tostring(s.item.id), kind, srcTier, srcTier + 1)
                    task.wait(0.5)
                else
                    -- A rejected candidate must not block every other stack.
                    warnlog("upg-fail-" .. kind, "%s T%d %s failed: %s", remote, srcTier,
                        tostring(s.item.id), tostring(ok and (msg or res) or res))
                end
            end
        end
    end
    if usable == 0 and rem > 0 then
        warnOnce("noitem:" .. tostring(goal.UID), "No usable %s stacks in tiers I through %d for %s", kind, T - 1, tostring(goal.title))
    end
end

local collectionRetryAt = {}
local function handleCollectByUpgrade(goal, kind)
    local key = tostring(goal.UID)
    if os.clock() < (collectionRetryAt[key] or 0) then return end
    local isPotion = kind == "potion"
    local category = isPotion and "Potion" or "Enchant"
    local dirTable
    if isPotion then dirTable = G.Potions else dirTable = G.Enchants end
    local priority = isPotion and CONFIG.PotionUpgradePriority or CONFIG.EnchantUpgradePriority
    local remote = isPotion and "UpgradePotionsMachine_Activate" or "UpgradeEnchantsMachine_Activate"
    -- Lowest source tier first. Never turn V into VI.
    for srcTier = 1, 4 do
        local need = tierRequirement(kind, srcTier)
        for _, stack in ipairs(upgradeStacks(category, srcTier, priority, dirTable, srcTier + 1)) do
            if not normalWorkAllowed() then return end
            local rem = currentRemaining(goal)
            if rem <= 0 then return end
            local amount = math.min(math.floor(stack.amount / need), rem, MAX_UPGRADE_PER_CALL)
            if amount >= 1 and normalWorkAllowed() then
                local ok, res, msg = netInvoke(remote, stack.uid, amount)
                if ok and res == true then
                    state.counters.crafted = state.counters.crafted + amount
                    local after = rem
                    local deadline = os.clock() + 3
                    repeat
                        task.wait(0.2)
                        after = currentRemaining(goal)
                    until after < rem or os.clock() >= deadline or not normalWorkAllowed()
                    local _, outcome = currentRemaining(goal)
                    if after < rem and (outcome == "ACTIVE" or outcome == "COMPLETED") then
                        log("Collection %s advanced by %d after %s T%d -> T%d", key, rem - after, kind, srcTier, srcTier + 1)
                    else
                        collectionRetryAt[key] = os.clock() + 30
                        warnlog("collect-no-credit-" .. kind, "Upgraded %s T%d -> T%d but collection did not advance; pausing 30s", kind, srcTier, srcTier + 1)
                    end
                    return
                else
                    warnlog("collect-upgrade-" .. kind, "%s failed for %s T%d: %s", remote, tostring(stack.item.id), srcTier, tostring(ok and (msg or res) or res))
                end
            end
        end
    end
    logEvery("collect-no-stock-" .. kind, 30, "No upgradeable tier I-IV %s stacks; continuing farming", kind)
end

local function handleUseFruits(goal)
    local rem = currentRemaining(goal)
    if rem <= 0 then return end
    local n = math.min(rem, 10)
    local used = 0
    while used < n and normalWorkAllowed() do
        local list = stacks("Fruit", function(item, _)
            if item.sh == true and not CONFIG.AllowShinyFruit then return false end
            return true
        end)
        local s = pickByPriority(list, CONFIG.FruitUsePriority) or list[1]
        if not s then
            warnOnce("noitem:" .. tostring(goal.UID), "No fruits left in inventory (%s)", tostring(goal.title))
            break
        end
        local ok, err = netFire("Fruits: Consume", s.uid, 1)
        if not ok then
            warnlog("fruit-fail", "Fruits: Consume failed: %s", tostring(err))
            break
        end
        used += 1
        state.counters.itemsUsed += 1
        task.wait(0.4)
    end
    if used > 0 then log("Used %d fruit(s) (%s)", used, tostring(goal.title)) end
end

local function tryPlaceFlag(goal, diamondOnly)
    if not normalWorkAllowed() then return end
    if state.flagBusy or os.clock() < state.flagRetryAt then return end
    if state.worldMismatch or state.worldSwitching or state.hopping then return end
    if not isfn(G.FlexibleFlagCmds, "Consume") then
        logOnce("noflagcmds", "FlexibleFlagCmds.Consume unavailable - flag goals are manual")
        return
    end
    if goal and currentRemaining(goal) <= 0 then return end
    if inInstance() then return end
    local zoneId = bestZoneId()
    local cz, inBox = currentZoneInfo()
    if cz ~= zoneId or inBox ~= true then
        ensureInBestZone()
        return
    end
    local reason = goal and tostring(goal.title) or "diamond breakable quest"
    local list = stacks("Misc", function(item, _)
        if diamondOnly then return item.id == "Diamonds Flag" end
        return type(item.id) == "string" and string.sub(item.id, -5) == " Flag"
    end)
    local s = nil
    if diamondOnly or (CONFIG.AutoDiamondFlags and wantsDiamonds()) then
        s = pickByPriority(list, { "Diamonds Flag" })
    end
    s = s or pickByPriority(list, CONFIG.FlagPriority) or list[1]
    if not s then
        if diamondOnly then
            logEvery("no-diamond-flags", 60, "No Diamonds Flags available - farming continues")
        else
            warnOnce("noitem:" .. tostring(goal.UID), "No flags left in inventory (%s)", reason)
            state.flagRetryAt = os.clock() + 60
        end
        return
    end
    if not normalWorkAllowed() then return end
    state.flagBusy = true -- the upkeep and flag-quest threads share this lock and cooldown
    local ok, res, msg = gcall(G.FlexibleFlagCmds.Consume, s.item.id, s.uid, 1) -- (flagId, uid, amount)
    state.flagBusy = false
    if ok and res == true then
        state.counters.itemsUsed += 1
        state.flagRetryAt = os.clock() + 5
        if s.item.id == "Diamonds Flag" then
            state.diamondFlagUntil[zoneId] = os.clock() + 300
        end
        log("Placed %s (%s left) for %s", tostring(s.item.id), int(s.amount - 1), reason)
    elseif ok and res == false then
        local m = tostring(msg or "")
        local ml = string.lower(m)
        if string.find(ml, "different flag", 1, true) or string.find(ml, "already", 1, true) then
            state.flagRetryAt = os.clock() + 60
            logEvery("flag-exists", 60, "A flag is already placed in this area (%s) - retrying in 60 s", m)
        else
            state.flagRetryAt = os.clock() + 20
            warnlog("flag-fail", "Flag placement refused: %s", m)
        end
    else
        state.flagRetryAt = os.clock() + 20
        warnlog("flag-err", "FlexibleFlagCmds.Consume error: %s", tostring(res))
    end
end

local function handleUseFlags(goal)
    tryPlaceFlag(goal, false)
end

local function maintainDiamondFlag()
    if not normalWorkAllowed() then return end
    if Crystal.holdsWork() then return end
    if not (CONFIG.AutoFarm and CONFIG.AutoUseFlags and CONFIG.AutoDiamondFlags and wantsDiamonds()) then return end
    local zoneId = bestZoneId()
    if not zoneId or os.clock() < (state.diamondFlagUntil[zoneId] or 0) then return end
    tryPlaceFlag(nil, true)
end

-- gold goals first (their golden crafts also feed rainbow goals), then rainbow, then the rest; star order within
local function craftOrder(t)
    if GOLD_GOALS[t] then return 1 end
    if RAINBOW_GOALS[t] then return 2 end
    return 3
end

local function craftTick()
    if not normalWorkAllowed() then return end
    if Crystal.holdsWork() then return end
    if state.worldSwitching then return end
    local goals = {}
    for _, g in ipairs(state.goals) do
        if g.remaining > 0 then goals[#goals + 1] = g end
    end
    if #goals == 0 then
        state.craftHatchReason = nil
        return
    end
    table.sort(goals, function(a, b)
        local oa, ob = craftOrder(a.Type), craftOrder(b.Type)
        if oa ~= ob then return oa < ob end
        if a.Stars ~= b.Stars then return a.Stars > b.Stars end
        return tostring(a.tier) < tostring(b.tier)
    end)
    local needHatch = nil
    for _, goal in ipairs(goals) do
        if not normalWorkAllowed() then return end
        local t = goal.Type
        local handler, arg = nil, nil
        if GOLD_GOALS[t] and CONFIG.AutoCraftGoldRainbow then
            handler = handleGoldCraft
        elseif RAINBOW_GOALS[t] and CONFIG.AutoCraftGoldRainbow then
            handler = handleRainbowCraft
        elseif t == T_USE_POTION and CONFIG.AutoUsePotions then
            handler = handleUsePotions
        elseif t == 14 and CONFIG.AutoUpgradePotions then
            handler, arg = handleCollectByUpgrade, "potion"
        elseif t == 15 and CONFIG.AutoUpgradeEnchants then
            handler, arg = handleCollectByUpgrade, "enchant"
        elseif t == T_UPGRADE_POTION and CONFIG.AutoUpgradePotions then
            handler, arg = handleUpgrade, "potion"
        elseif t == T_UPGRADE_ENCHANT and CONFIG.AutoUpgradeEnchants then
            handler, arg = handleUpgrade, "enchant"
        elseif t == T_USE_FRUIT and CONFIG.AutoUseFruits then
            handler = handleUseFruits
        elseif t == T_USE_FLAG and CONFIG.AutoUseFlags then
            handler = handleUseFlags
        end
        if handler then
            -- every handler runs in its own pcall so one failure cannot starve the others
            local ok, result = pcall(handler, goal, arg)
            if not ok then
                warnlog("handler-" .. tostring(t), "handler for goal type %s failed: %s", tostring(t), tostring(result))
            elseif (GOLD_GOALS[t] or RAINBOW_GOALS[t]) and type(result) == "string" and needHatch == nil then
                needHatch = result
            end
        end
    end
    if needHatch ~= nil then
        logEvery("craft-fodder", 30, "Crafting needs more fodder: %s - hatching the best egg", needHatch)
    end
    state.craftHatchReason = needHatch
end

-- =====================================================================================
-- 15. Event-item thread (comets / pinatas / lucky blocks / coin jars)
-- =====================================================================================
local function eventKindOf(ev)
    if type(ev) ~= "table" then return nil end
    local names = {}
    if type(ev.dir) == "table" then
        names[#names + 1] = ev.dir._id
        names[#names + 1] = ev.dir.Name
        names[#names + 1] = ev.dir.name
    end
    names[#names + 1] = ev.id
    names[#names + 1] = ev.name
    for _, n in ipairs(names) do
        if type(n) == "string" then
            local norm = string.lower((string.gsub(n, "%s", "")))
            for kind, def in pairs(EVENT_DEFS) do
                for _, m in ipairs(def.match) do
                    if string.find(norm, m, 1, true) then return kind end
                end
            end
        end
    end
    return nil
end

local function activeEventKinds(zoneId)
    local kinds = {}
    if not isfn(G.RandomEventCmds, "GetActive") then return kinds end
    local ok, active = gcall(G.RandomEventCmds.GetActive)
    if not ok or type(active) ~= "table" then return kinds end
    for _, ev in pairs(active) do
        local kind = eventKindOf(ev)
        if kind and (ev.parentID == nil or ev.parentID == zoneId) then
            kinds[kind] = true
        end
    end
    return kinds
end

-- best Misc stack for the given item ids (priority order, largest stack) -> {uid, item, amount} or nil
local function pickMiscStack(ids)
    local set = makeSet(ids or {})
    local list = stacks("Misc", function(item, _) return set[item.id] == true end)
    return pickByPriority(list, ids) or list[1]
end

local function eventTick()
    if not normalWorkAllowed() then return end
    if Crystal.holdsWork() then return end
    if not CONFIG.AutoSpawnEvents then return end
    if state.worldSwitching or state.worldMismatch or state.hopping then return end
    local wanted = {} -- kind -> goal with the most stars
    for _, goal in ipairs(state.goals) do
        local kind = EVENT_GOAL_KIND[goal.Type]
        if kind and goal.remaining > 0 and wanted[kind] == nil then
            wanted[kind] = goal
        end
    end
    if next(wanted) == nil then return end
    if inInstance() then return end
    local zoneId = bestZoneId()
    if not zoneId then return end
    local cz, inBox = currentZoneInfo()
    if cz ~= zoneId or inBox ~= true then
        logEvery("event-notinbox", 30, "Not inside the dotted box of %s - moving before spawning event items", tostring(zoneId))
        ensureInBestZone()
        return
    end
    local active = activeEventKinds(zoneId)
    local now = os.clock()
    for kind, goal in pairs(wanted) do
        if not normalWorkAllowed() then return end
        local def = EVENT_DEFS[kind]
        if def and not active[kind]
            and now - (state.lastEventSpawn[kind] or -1e9) >= 12
            and now >= (state.eventBackoffUntil[kind] or 0) then
            local rem = currentRemaining(goal)
            if rem > 0 then
                local s = pickMiscStack(def.items)
                if not s then
                    warnOnce("noitem:" .. tostring(goal.UID), "No %s left in inventory (%s)", table.concat(def.items, "/"), tostring(goal.title))
                else
                    local ok, res, msg = netInvoke(def.remote, s.uid)
                    if ok and res == true then
                        state.lastEventSpawn[kind] = now
                        state.counters.itemsUsed += 1
                        log("Spawned %s (%s left) - %s %s/%s", tostring(s.item.id), int(s.amount - 1), def.label,
                            int(goal.Amount - rem + 1), int(goal.Amount))
                    else
                        state.eventBackoffUntil[kind] = now + 10
                        warnlog("event-fail-" .. kind, "%s failed: %s", def.remote, tostring(ok and (msg or res) or res))
                    end
                    task.wait(0.3)
                end
            end
        end
    end
end

-- =====================================================================================
-- 16. World teleport
-- =====================================================================================
-- BEGIN AREA PROGRESSION
-- IDs/signatures: https://github.com/vuhoanghai208/script/blob/91a4ad9893f263b3d6a329aa13aebbcaf4677533/map1#L841
-- Price lookup: https://github.com/idonthaveoneatm/lua/blob/13aaad3b13646d055b7966d35971611d1b0787ba/games/PetSimulator99/autoRanker.lua#L1405
-- Rebirth 9 awards the Supercomputer Radio at area 219 (BIG Games update 26).
local AreaProgression = {}
do
    local A = AreaProgression
    local function integer(n)
        return type(n) == "number" and n == n and n >= 0 and n < math.huge and n % 1 == 0
    end
    local function limits()
        local area, rebirth = CONFIG.AreaTarget, CONFIG.RebirthTarget
        return integer(area) and math.clamp(area, 1, 219) or 219,
            integer(rebirth) and math.clamp(rebirth, 0, 9) or 9
    end
    local function zoneResult(fn)
        if type(fn) ~= "function" then return nil end
        local id, data = gval(fn)
        if type(id) == "table" then data, id = id, id._id end
        if type(id) ~= "string" or id == "" then return nil end
        local directory = type(G.Zones) == "table" and G.Zones[id]
        if type(directory) == "table" then
            if type(data) == "table" and data.ZoneNumber ~= directory.ZoneNumber then return nil end
            data = directory
        end
        if type(data) ~= "table" or not integer(data.ZoneNumber) or data.ZoneNumber < 1
            or not integer(data.WorldNumber) or data.WorldNumber < 1 or data.WorldNumber > 4
            or (data._id ~= nil and data._id ~= id) then return nil end
        return id, data
    end
    local function snapshot()
        local save = getSave()
        local rebirths = save and tonumber(save.Rebirths)
        if not integer(rebirths) then return nil end
        local id, zone = zoneResult(G.ZoneCmds and G.ZoneCmds.GetMaxOwnedZone)
        if not id then return nil end
        if cache.zoneId ~= id then invalidateCaches() end
        cache.zoneId, cache.zone, cache.zoneAt = id, zone, os.clock()
        return { id = id, zone = zone, number = zone.ZoneNumber, rebirths = rebirths }
    end
    local function permitted()
        return state.alive and CONFIG.AutoBuyZones and not state.minigame.transaction
            and not state.minigame.restorePets and not Crystal.holdsWork()
            and not state.worldSwitching and not inInstance()
    end
    local function eligibleRebirth(s, target, maximum)
        if not CONFIG.AutoRebirth or not isfn(G.RebirthCmds, "GetNextRebirth") then return nil end
        local data = gval(G.RebirthCmds.GetNextRebirth)
        if type(data) ~= "table" or not integer(data.RebirthNumber) or not integer(data.ZoneNumberRequired) then return nil end
        if data.RebirthNumber ~= s.rebirths + 1 or data.RebirthNumber > maximum
            or data.ZoneNumberRequired < 1 or data.ZoneNumberRequired > target
            or s.number < data.ZoneNumberRequired then return nil end
        return data
    end
    local function startRequest(p, kind, id, number, beforeRebirths)
        local op = { pending = true, kind = kind, id = id, number = number,
            beforeRebirths = beforeRebirths, userId = LocalPlayer.UserId, owner = handle, at = os.clock() }
        p.operation, genv.VyAreaOperation = op, op
        p.status = kind == "rebirth" and ("Rebirth " .. number .. ": requesting") or ("Area " .. number .. ": purchasing")
        task.spawn(function()
            local valid = permitted() and p.operation == op
            local s = valid and snapshot()
            local target, maximum = limits()
            if s then
                if kind == "zone" then
                    local nextId, nextZone = zoneResult(G.ZoneCmds and G.ZoneCmds.GetNextZone)
                    valid = s.number < target and nextId == id and nextZone.ZoneNumber == number
                        and number == s.number + 1 and number <= target and currentWorld() == nextZone.WorldNumber
                else
                    local rb = eligibleRebirth(s, target, maximum)
                    valid = rb ~= nil and rb.RebirthNumber == number and s.rebirths == beforeRebirths
                end
            else valid = false end
            if not valid then op.ok, op.result, op.message = true, false, "state changed before request"
            else
                op.ok, op.result, op.message = netInvoke(kind == "zone" and "Zones_RequestPurchase" or "Rebirth_Request", id)
            end
            -- Finish the lease even if Stop/reinjection happened while Invoke yielded.
            op.pending, op.done = false, true
        end)
    end
    function A.tick()
        local p = state.areaProgression
        if not CONFIG.AutoBuyZones then p.status, p.hold, p.travelWorld = "Area progression: OFF", false, nil; return end
        if not permitted() then return end
        local s, now = snapshot(), os.clock()
        if not s then p.status = "Areas: waiting for current area/rebirth data"; return end
        local target, maximum = limits()
        p.current, p.rebirths = s.number, s.rebirths
        -- Reconstruct frontier travel from live ownership on every injection. This
        -- also works if GetNextZone is nil until the destination world has loaded.
        local frontier = s.number >= 199 and s.rebirths >= 8 and target >= 200 and 3
            or s.number >= 99 and s.rebirths >= 4 and target >= 100 and 2 or nil
        p.travelWorld = frontier and frontier > s.zone.WorldNumber and frontier or nil
        p.hold = p.travelWorld ~= nil
        local lease = genv.VyAreaOperation
        if not p.operation and type(lease) == "table" and lease.userId == LocalPlayer.UserId then p.operation = lease end
        local op = p.operation
        if op then
            if op.kind == "rebirth" then p.hold = true end
            if op.pending then p.status = "Areas: waiting for " .. op.kind .. " request"; return end
            local confirmed = op.kind == "zone" and s.number >= op.number
                or op.kind == "rebirth" and s.rebirths >= op.number
            if confirmed or not op.ok or op.result ~= true or now - op.at >= (CONFIG.AreaConfirmTimeout or 30) then
                p.operation = nil
                if genv.VyAreaOperation == op then genv.VyAreaOperation = nil end
                p.hold = p.travelWorld ~= nil
                p.nextAt = now + (confirmed and (CONFIG.AreaBuyInterval or 3) or (CONFIG.AreaRetryDelay or 15))
                if confirmed then
                    invalidateCaches()
                    p.status = (op.kind == "zone" and "Area " or "Rebirth ") .. op.number .. " confirmed"
                    log("%s", p.status)
                else
                    local detail = not op.ok and op.result or op.message or (op.result ~= true and op.result) or "unlock not replicated"
                    p.status = "Areas: " .. tostring(detail) .. " (retrying)"
                    logEvery("area-request", 15, "%s", p.status)
                end
                return
            end
            p.status = "Areas: waiting for " .. op.kind .. " " .. op.number .. " confirmation"
            return
        end
        if s.number >= target and (s.rebirths >= maximum or not CONFIG.AutoRebirth) then
            p.hold, p.travelWorld = false, nil
            p.status = s.rebirths >= maximum and "Area 219 / Rebirth 9 reached; auto-buy stopped"
                or "Area " .. target .. " reached; rebirth automation is OFF"
            return
        end
        if now < (p.nextAt or 0) then return end
        local rb = eligibleRebirth(s, target, maximum)
        if rb then
            p.hold, p.travelWorld = true, nil
            p.status = "Rebirth " .. rb.RebirthNumber .. ": waiting for farming/hatching to finish"
            for _, count in pairs(state.normalWorkers) do if count > 0 then return end end
            if state.hopping or state.flagBusy then return end
            startRequest(p, "rebirth", tostring(rb.RebirthNumber), rb.RebirthNumber, s.rebirths)
            return
        end
        if s.number >= target then
            p.status = "Area " .. target .. " reached; waiting for eligible Rebirth " .. maximum
            return
        end
        local world = p.travelWorld or s.zone.WorldNumber
        if currentWorld() ~= world then
            p.status = "Areas: travelling to World " .. world
            return
        end
        local id, nextZone = zoneResult(G.ZoneCmds and G.ZoneCmds.GetNextZone)
        if not id then p.status = "Areas: next area unavailable (check world/rebirth requirements)"; return end
        if nextZone.ZoneNumber > target then p.status = "Area cap " .. target .. ": purchase blocked"; return end
        if nextZone.ZoneNumber ~= s.number + 1 then p.status = "Areas: waiting for consistent next-area data"; return end
        if nextZone.WorldNumber ~= currentWorld() then p.status = "Areas: waiting for world/rebirth unlock"; return end
        if type(G.CalcGatePrice) == "function" and isfn(G.CurrencyCmds, "Get") and type(nextZone.Currency) == "string" then
            local cost = gval(G.CalcGatePrice, nextZone)
            local balance = gval(G.CurrencyCmds.Get, nextZone.Currency)
            if type(cost) == "number" and cost == cost and cost >= 0 and cost < math.huge
                and type(balance) == "number" and balance == balance and balance < cost then
                p.status = string.format("Area %d: farming %s (%.0f / %.0f)", nextZone.ZoneNumber, nextZone.Currency, balance, cost)
                p.nextAt = now + (CONFIG.AreaBuyInterval or 3)
                return
            end
        end
        -- The server remains authoritative for prices, rebirths and zone quests.
        startRequest(p, "zone", id, nextZone.ZoneNumber, s.rebirths)
    end
end
-- END AREA PROGRESSION

local lastWorldAttempt = -1e9

local function areaRebirthHoldsTravel()
    local areas = state.areaProgression
    return areas and ((areas.hold and not areas.travelWorld)
        or (areas.operation and areas.operation.kind == "rebirth"))
end

local function navigationDestination()
    local zone = bestZone()
    local tx, crystalHold = state.minigame.transaction, state.crystal.hold
    local frontier = state.areaProgression and state.areaProgression.travelWorld
    if not tx and not crystalHold and CONFIG.AutoBuyZones and frontier then
        return "NORMAL_FARMING", frontier, bestZoneId()
    end
    return MinigameController.destination(tx, crystalHold, zone and zone.WorldNumber, bestZoneId())
end

local function worldTeleport(n, zoneId, owner)
    n = tonumber(n)
    if not n or n < 1 or n > 4 or n % 1 ~= 0 then return false, "invalid destination world" end
    local tx, nav, now = state.minigame.transaction, state.navigation, os.time()
    owner = owner or "NORMAL_FARMING"
    local expectedOwner, expectedWorld = navigationDestination()
    if owner ~= expectedOwner or n ~= expectedWorld then return false, "world navigation belongs to " .. expectedOwner end
    if owner == "NORMAL_FARMING" and areaRebirthHoldsTravel() then return nil, "waiting for rebirth confirmation" end
    nav.owner, nav.world, nav.zone = owner, n, zoneId
    if currentWorld() == n then state.worldMismatch = false; return true end
    if not CONFIG.AutoWorldTeleport then return false, "AutoWorldTeleport is disabled" end
    if state.worldSwitching then return nil, "waiting for destination" end
    local pending = genv.VyWorldTravel
    if pending and pending.pending then return nil, "world request has not returned; no duplicate retry" end
    local leg = owner == "MINIGAME_RETURN" and "returning" or "outbound"
    if tx then
        if tx.teleportAttempts[leg] >= CONFIG.MinigameTeleportRetries then return false, "world teleport retry budget exhausted" end
        if tx.lastTeleportLeg == leg and now - (tx.lastTeleportAt or 0) < CONFIG.MinigameTeleportRetryDelay then return nil end
    else
        if os.clock() - lastWorldAttempt < 30 or now - (state.persist.lastWorldSwitch or 0) < 90 then return nil end
    end
    -- Rolling guard survives reinjection but permits a short outbound/return trip.
    local history = {}
    for _, timestamp in ipairs(state.persist.worldHistory or {}) do
        if timestamp <= now + 30 and now - timestamp < 180 then history[#history + 1] = timestamp end
    end
    if #history >= 6 then return false, "world travel rate limit reached (six attempts in 180s)" end
    local ready, reason = queueSelf(true)
    if not ready then return false, reason or "teleport re-execution unavailable" end
    local previous = state.persist.lastWorldSwitch
    if tx then
        tx.teleportAttempts[leg] += 1
        tx.lastTeleportAt, tx.lastTeleportLeg, tx.updatedAt = now, leg, now
    end
    history[#history + 1] = now
    state.persist.worldHistory, state.persist.lastWorldSwitch = history, now
    if not writeStateFile() then
        state.persist.lastWorldSwitch = previous
        return false, "could not persist world travel before request"
    end
    lastWorldAttempt = os.clock()
    state.worldSwitching, state.worldSwitchAt = true, os.clock()
    state.action = string.format("Teleporting to World %d (%s)", n, owner)
    local lease = { pending = true, owner = handle, at = os.clock(), world = n }
    genv.VyWorldTravel, nav.pending = lease, lease
    log("World travel %s -> %d (%s)", owner, n, tostring(zoneId))
    task.spawn(function()
        local actualOwner, actualWorld = navigationDestination()
        if not state.alive or nav.pending ~= lease or actualOwner ~= owner or actualWorld ~= n
            or (owner == "NORMAL_FARMING" and areaRebirthHoldsTravel()) then
            lease.pending = false
            state.worldSwitching = false
            return
        end
        -- Preserve the game's verified server-side world travel abstraction.
        local ok, result, message = netInvoke(string.format("World%dTeleport", n))
        lease.pending = false
        if not state.alive or nav.pending ~= lease then return end
        if not ok or result == false then
            state.worldSwitching = false
            nav.failure = tostring(ok and (message or result) or result)
            if not tx then state.persist.lastWorldSwitch = previous end
            writeStateFile()
            warnlog("world-fail", "World%dTeleport failed: %s", n, nav.failure)
        end
    end)
    return nil, "world request sent; awaiting destination verification"
end

local function checkWorld()
    local tx, nav = state.minigame.transaction, state.navigation
    local zone = bestZone()
    local owner, destination, zoneId = navigationDestination()
    nav.owner, nav.world, nav.zone = owner, destination, zoneId
    local cw = currentWorld()
    state.worldMismatch = destination ~= nil and cw ~= destination
    if state.worldSwitching then
        -- A control change may request a return while an outbound request is
        -- already accepted. Observe the destination actually sent to the server.
        local sentDestination = nav.pending and nav.pending.world or destination
        if cw and cw == sentDestination then
            state.worldSwitching = false
            invalidateCaches()
        elseif os.clock() - state.worldSwitchAt > CONFIG.MinigameTeleportTimeout then
            state.worldSwitching = false
            nav.failure = "destination was not reached within teleport timeout"
            warnlog("world-timeout", "%s", nav.failure)
        end
        return
    end
    if tx then return end -- The FSM alone initiates either leg of temporary travel.
    if not destination or not cw or not state.worldMismatch then return end
    if owner == "CRYSTAL" and not state.crystal.travelReady then return end
    if CONFIG.AutoWorldTeleport then worldTeleport(destination, zoneId, owner)
    else logEvery("world:wrong", 60, "World %s required; AutoWorldTeleport is disabled", tostring(destination)) end
end


-- BEGIN MINIGAME RUNTIME
-- Transaction runtime; driven exclusively by controllerTick, with one outstanding call.
do
    local M = MinigameController
    function M.holdsWork()
        return state.minigame.transaction ~= nil
    end
    function M.setEnabled(enabled)
        if not state.alive then return end
        local mg, tx = state.minigame, state.minigame.transaction
        CONFIG.AutoMinigames = enabled == true
        if CONFIG.AutoMinigames then
            -- Explicit user retry only; persisted settings never run this setter.
            mg.nextStartAt, mg.normalWorkUntil, mg.cooldowns = 0, 0, {}
            mg.lastFailure = nil
        elseif tx and M.destination(tx, false) ~= "MINIGAME_RETURN" then
            -- Retain ownership through exit/return. discardOperation keeps any
            -- already-sent request's global lease until its result settles.
            M.fail(tx, "Minigames turned off; returning to farming")
        end
        writeStateFile()
    end
    function M.setPriority(first)
        if not state.alive then return end
        state.minigame.priorityFirst = first == true
        if state.minigame.priorityFirst then
            M.setEnabled(true)
        else
            state.minigame.normalWorkUntil = os.time() + (CONFIG.MinigameNormalWorkSeconds or 300)
            writeStateFile()
        end
    end
    function M.hasNormalGoals()
        for _, goal in ipairs(state.goals) do
            if not MINIGAME_DEFS[goal.Type] and goal.supported and (tonumber(goal.remaining) or 0) > 0 then return true end
        end
        return false
    end
    function M.valid(tx, generation)
        return state.alive and state.minigame.transaction == tx
            and (generation == nil or generation == state.minigame.generation)
    end
    function M.part(object)
        if typeof(object) ~= "Instance" then return nil end
        if object:IsA("BasePart") then return object end
        if object:IsA("Model") and object.PrimaryPart then return object.PrimaryPart end
        return object:FindFirstChildWhichIsA("BasePart", true)
    end
    function M.move(tx, cf)
        if not M.valid(tx) or typeof(cf) ~= "CFrame" then return false, "movement owner cancelled" end
        local p = cf.Position
        if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or math.abs(p.X) > 1e7
            or math.abs(p.Y) > 1e7 or math.abs(p.Z) > 1e7 then return false, "invalid movement position" end
        local hrp = getHRP()
        if not hrp or not hrp:IsA("BasePart") then return false, "character root not ready" end
        return pcall(function() hrp.CFrame = cf; hrp.AssemblyLinearVelocity = Vector3.zero end)
    end
    function M.call(tx, key, fn, ...)
        local mg, now = state.minigame, os.clock()
        if not M.valid(tx) then return "ERROR", "transaction cancelled" end
        local op = mg.operation
        if op then
            if op.key ~= key then return "ERROR", "another operation still owns the transaction" end
            if not op.done then
                if now - op.at > CONFIG.MinigameActionTimeout then return "ERROR", "operation timed out: " .. key end
                return "WAIT"
            end
            mg.operation = nil
            local r = op.result
            if not r[1] then return "ERROR", tostring(r[2]) end
            if r[2] ~= true then return "ERROR", tostring(r[3] or "module/network call failed") end
            if r[3] == false then return "ERROR", tostring(r[4] or "server refused " .. key) end
            return "DONE", r[3], r[4]
        end
        local old = genv.VyMinigameOperation
        if old and old.pending then return "WAIT", "waiting for earlier operation to settle" end
        local args, generation = table.pack(...), mg.generation
        op = { key = key, at = now, pending = true, owner = handle, transactionId = tx.id }
        mg.operation, genv.VyMinigameOperation = op, op
        task.spawn(function()
            if not M.valid(tx, generation) or mg.operation ~= op then op.pending = false; return end
            local result = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
            op.pending = false
            if M.valid(tx, generation) and mg.operation == op then
                op.result, op.done = result, true
            end
        end)
        return "WAIT"
    end
    function M.discardOperation()
        -- A sent request cannot be unsent. Keep its lease until it returns; never retry it in parallel.
        state.minigame.generation += 1
        state.minigame.operation = nil
    end
    function M.phase(tx, phase)
        if not M.valid(tx) then return end
        tx.phase, tx.phaseAt, tx.updatedAt = phase, os.time(), os.time()
        state.minigame.session = {}
        invalidateCaches()
        instanceCache.at = -1e9
        log("Minigame %s [%s] -> %s", tx.instanceName, tx.id, phase)
        if not writeStateFile() then
            state.minigame.lastFailure = "could not persist transaction phase"
            if phase ~= "RECOVERY" and phase ~= "ABORTED" then
                tx.recoveryReason, tx.phase, tx.phaseAt = state.minigame.lastFailure, "RECOVERY", os.time()
                tx.recoveryAt = tx.phaseAt
            end
        end
    end
    function M.fail(tx, reason)
        if not M.valid(tx) then return end
        reason = string.sub(tostring(reason), 1, 450)
        tx.recoveryReason, tx.recoveryAt = reason, tx.recoveryAt or os.time()
        state.minigame.lastFailure = reason
        warnlog("minigame-failure", "%s: %s", tx.instanceName, reason)
        M.discardOperation()
        M.phase(tx, "RECOVERY")
    end
    function M.activeModel(tx)
        if isfn(G.InstancingCmds, "GetInstanceID") then
            local id = gval(G.InstancingCmds.GetInstanceID)
            if id ~= nil and id ~= tx.instanceName then return nil, "a different instance is active" end
        end
        local things = workspace:FindFirstChild("__THINGS")
        local container = things and things:FindFirstChild("__INSTANCE_CONTAINER")
        local active = container and container:FindFirstChild("Active")
        local model = active and active:FindFirstChild(tx.instanceName)
        if typeof(model) == "Instance" then return model end
        return nil, "waiting for " .. tx.instanceName .. " instance replication"
    end
    function M.remote(name, class)
        local folder = RS:FindFirstChild("Network")
        local remote = folder and folder:FindFirstChild(name)
        return typeof(remote) == "Instance" and remote:IsA(class)
    end
    function M.resolveZone(def)
        for id, zone in pairs(G.Zones or {}) do
            if type(zone) == "table" and zone.WorldNumber == def.world and zone.ZoneNumber == def.zoneNumber then
                return type(zone._id) == "string" and zone._id or tostring(id), zone
            end
        end
        return nil
    end
    function M.peerSnapshot(save, goalTier)
        local peers = {}
        for tier, goal in pairs(save.Goals or {}) do
            if tostring(tier) ~= tostring(goalTier) and type(goal) == "table" and goal.UID ~= nil then
                peers[tostring(tier)] = { uid = goal.UID, progress = tonumber(goal.Progress) or 0 }
            end
        end
        return peers
    end
    function M.start(goal)
        local mg, save, def = state.minigame, getSave(), MINIGAME_DEFS[goal.Type]
        if M.holdsWork() or mg.restorePets or not save or not def or not goal.UID or goal.Amount <= 0 or goal.remaining <= 0 then return false end
        if Crystal.holdsWork() or state.crystal.pausedPets or state.worldSwitching or inInstance() then return false end
        local pending = genv.VyCrystalOpening
        if pending and pending.pending then return false end
        pending = genv.VyMinigameOperation
        if pending and pending.pending then return false end
        if os.time() < (mg.cooldowns[tostring(goal.UID)] or 0) or os.time() < (mg.nextStartAt or 0) then return false end
        local targetZone = M.resolveZone(def)
        local zone, originId, world = bestZone(), bestZoneId(), currentWorld()
        if not targetZone or not zone or not originId or not world then return false end
        if zone.WorldNumber == 1 and (tonumber(zone.ZoneNumber) or 0) < def.zoneNumber then
            mg.cooldowns[tostring(goal.UID)] = os.time() + CONFIG.MinigameRetryCooldown
            mg.lastFailure = def.instance .. " area is not owned yet"
            return false
        end
        local now = os.time()
        local tx = { schemaVersion = 1, userId = LocalPlayer.UserId, id = HttpService:GenerateGUID(false),
            phase = "PREPARE", goalUID = goal.UID, goalType = goal.Type, goalTier = tostring(goal.tier),
            goalAmount = goal.Amount, goalStars = goal.Stars, originalWorld = world, originalZone = originId,
            targetWorld = def.world, targetZone = targetZone, instanceName = def.instance,
            originalRank = tonumber(save.Rank), progressBaseline = goal.Progress, lastProgress = goal.Progress,
            baselineStars = tonumber(save.RankStars) or 0, peerGoals = M.peerSnapshot(save, goal.tier),
            teleportAttempts = { outbound = 0, returning = 0 }, timestamp = now, updatedAt = now,
            phaseAt = now, lastProgressAt = now, pausedPets = false }
        mg.transaction, mg.session = tx, {}
        mg.generation += 1
        mg.lastFailure = nil
        state.returnAfterHatch = nil
        state.plan = { hatch = false, hatchReasons = {}, hatchEggOnly = false }
        if not writeStateFile() then M.fail(tx, "state file is not writable"); return false end
        return true
    end
    function M.restore(raw)
        if raw == nil then return end
        local tx, reason = M.validate(raw, LocalPlayer.UserId, os.time())
        if not tx then state.minigame.lastFailure = reason; warnlog("minigame-restore", "Ignoring saved minigame: %s", reason); return end
        state.minigame.transaction = tx
        state.minigame.generation += 1
        state.minigame.session = {}
        -- Never replay an in-flight cast/click/dig after a script restart. Re-enter and observe.
        if tx.cancelled or tx.phase == "ABORTED" then
            tx.recoveryReason, tx.recoveryAt = tx.recoveryReason or "previous script stopped", os.time()
            M.phase(tx, "RECOVERY")
        elseif tx.phase == "EXECUTE" or tx.phase == "VERIFY" then
            M.phase(tx, "INSTANCE_ENTRY")
        end
        invalidateCaches()
        instanceCache.at = -1e9
        log("Resumed minigame %s [%s], phase %s, current World %s", tx.instanceName, tx.id, tx.phase, tostring(currentWorld()))
    end
    function M.finish(tx, aborted)
        local mg = state.minigame
        if not M.valid(tx) then return end
        M.discardOperation()
        local now = os.time()
        mg.normalWorkUntil = now + (CONFIG.MinigameNormalWorkSeconds or 300)
        mg.nextStartAt = now + (aborted and CONFIG.MinigameRetryCooldown or 10)
        mg.cooldowns[tostring(tx.goalUID)] = mg.nextStartAt
        mg.lastOutcome = aborted and "ABORTED" or (tx.outcome or "UNKNOWN")
        mg.lastFailure = tx.recoveryReason or mg.lastFailure
        -- If recovery could not restore pets, retry through the bounded normal restore path below.
        mg.restorePets = tx.pausedPets == true
        mg.restorePetsAt = os.clock()
        mg.transaction, mg.session = nil, {}
        state.navigation.owner = "NORMAL_FARMING"
        state.hopping, state.returnAfterHatch = false, nil
        breakAssign = {}
        invalidateCaches()
        instanceCache.at = -1e9
        writeStateFile()
        log("Minigame %s ended: %s%s", tx.instanceName, mg.lastOutcome,
            mg.lastFailure and (" (" .. mg.lastFailure .. ")") or "")
    end
    function M.stop()
        local tx = state.minigame.transaction
        state.minigame.generation += 1
        state.minigame.operation = nil
        if tx then
            tx.cancelled, tx.aborted, tx.phase, tx.updatedAt = true, true, "ABORTED", os.time()
            tx.recoveryReason = "script stopped; recovery required on next run"
        end
    end
    function M.observe(tx)
        local outcome, live = M.classify(getSave(), tx)
        if live then
            local progress = tonumber(live.Progress) or 0
            if progress > tx.lastProgress then
                tx.lastProgress, tx.lastProgressAt, tx.updatedAt = progress, os.time(), os.time()
                writeStateFile()
            end
        end
        if outcome == "COMPLETED" then tx.completionObserved, tx.outcome = true, outcome end
        return outcome
    end
    function M.status()
        local mg, tx = state.minigame, state.minigame.transaction
        if not tx then
            if not CONFIG.AutoMinigames then return "Minigames: OFF | normal quests active" end
            local untilAt = math.max(mg.nextStartAt or 0, not mg.priorityFirst and M.hasNormalGoals() and (mg.normalWorkUntil or 0) or 0)
            if untilAt > os.time() then
                return string.format("Normal quests active | minigames in %ds%s",
                    untilAt - os.time(), mg.lastFailure and ("\nLast minigame: " .. mg.lastFailure) or "")
            end
            return mg.lastFailure and ("Minigame: " .. mg.lastFailure)
                or (mg.priorityFirst and "Minigames first: ready" or "Minigames: ready")
        end
        local _, world = M.destination(tx, false, (bestZone() or {}).WorldNumber, bestZoneId())
        return string.format("%s | type %d slot %s | %s/%s\n%s | W%s -> W%s | retries %d/%d | idle %ds\n%s",
            tx.instanceName, tx.goalType, tx.goalTier, int(tx.lastProgress), int(tx.goalAmount), tx.phase,
            tostring(currentWorld() or "?"), tostring(world or "?"), tx.teleportAttempts.outbound,
            tx.teleportAttempts.returning, math.max(0, os.time() - tx.lastProgressAt),
            (tx.phase == "ABORTED" and mg.lastFailure) or mg.session.status or tx.recoveryReason or mg.lastFailure or "waiting for replicated quest progress")
    end
    function M.entry(tx)
        local mg, now = state.minigame, os.clock()
        if currentWorld() ~= tx.targetWorld then return "ERROR", "instance entry in wrong world" end
        local model = M.activeModel(tx)
        if model and (not isfn(G.InstancingCmds, "IsInInstance") or gval(G.InstancingCmds.IsInInstance) == true) then
            local op = mg.operation
            if op and not op.done then return "WAIT" end
            mg.operation = nil
            return "DONE"
        end
        if inInstance() then return "ERROR", "another instance is already active" end
        local session = mg.session
        if session.entered then return "WAIT" end
        if session.enterRequested then
            local status, reason = M.call(tx, "enter", gcall, G.InstancingCmds.Enter, tx.instanceName)
            if status == "DONE" then session.entered = true; instanceCache.at = -1e9 end
            return status == "DONE" and "WAIT" or status, reason
        end
        local things = workspace:FindFirstChild("__THINGS")
        local instances = things and things:FindFirstChild("Instances")
        local portal = instances and instances:FindFirstChild(tx.instanceName)
        local teleports = portal and portal:FindFirstChild("Teleports")
        local entrance = teleports and M.part(teleports:FindFirstChild("Enter"))
        if not entrance then
            if now - (session.lastMoveAt or -1e9) > 3 then
                session.lastMoveAt = now
                local pos = standPosition(tx.targetZone)
                if pos then M.move(tx, CFrame.new(pos)) end
            end
            return "WAIT", "loading instance entrance"
        end
        local hrp = getHRP()
        if not hrp then return "WAIT", "waiting for character" end
        if (hrp.Position - entrance.Position).Magnitude > 10 then
            local ok, reason = M.move(tx, entrance.CFrame + Vector3.new(0, 3, 0))
            if not ok then return "ERROR", reason end
            session.movedAt = now
            return "WAIT"
        end
        if now - (session.movedAt or -1e9) < 0.5 then return "WAIT" end
        session.enterRequested = true
        return M.call(tx, "enter", gcall, G.InstancingCmds.Enter, tx.instanceName)
    end
    function M.exit(tx)
        local mg = state.minigame
        local travel = genv.VyWorldTravel
        if state.worldSwitching or (travel and travel.pending) then
            return "WAIT", "waiting for world travel to settle before returning"
        end
        local op = genv.VyMinigameOperation
        if op and op.pending and mg.operation ~= op then return "WAIT" end
        local model = M.activeModel(tx)
        instanceCache.at = -1e9
        if not inInstance() and not model then
            if mg.operation and not mg.operation.done then return "WAIT" end
            mg.operation = nil
            return "DONE"
        end
        if not isfn(G.InstancingCmds, "Leave") then return "ERROR", "InstancingCmds.Leave unavailable" end
        if mg.session.left then return "WAIT" end
        local status, reason = M.call(tx, "leave", gcall, G.InstancingCmds.Leave)
        if status == "DONE" then mg.session.left = true; return "WAIT" end
        return status, reason
    end
    function M.restoreLocation(tx)
        invalidateCaches()
        local zone, id, hrp = bestZone(), bestZoneId(), getHRP()
        if not zone or not id then return "WAIT", "Restore: waiting for best zone data" end
        if not hrp then return "WAIT", "Restore: waiting for character" end
        if currentWorld() ~= zone.WorldNumber then M.phase(tx, "RETURN"); return "WAIT" end
        instanceCache.at = -1e9
        if inInstance() then return "ERROR", "instance exit not confirmed" end
        local part, pos = breakZonePart(id), standPosition(id)
        if not pos then return "WAIT", "Restore: waiting for best zone teleport position" end
        local loaded = part and part:IsA("BasePart")
        local arrived = false
        if loaded then
            -- The zone's actual geometry is independent of optional/stale MapCmds
            -- markers. Allow root clearance above the thin dotted-box plane.
            local p, size = part.CFrame:PointToObjectSpace(hrp.Position), part.Size
            arrived = math.abs(p.X) <= size.X / 2 and math.abs(p.Z) <= size.Z / 2
                and math.abs(p.Y) <= size.Y / 2 + 8
                and (hrp.Position - pos).Magnitude <= CONFIG.ZonePositionTolerance
        end
        if not arrived then
            if os.clock() - (state.minigame.session.lastMoveAt or -1e9) > 3 then
                state.minigame.session.lastMoveAt = os.clock()
                -- Approach the teleport fallback first so distant geometry can stream.
                local ok, reason = M.move(tx, CFrame.new(pos))
                if not ok then return "ERROR", reason end
            end
            return "WAIT", loaded and "Restore: moving into best zone break area" or "Restore: loading best zone break area"
        end
        if tx.pausedPets then
            local status, reason = M.call(tx, "restore-pets", gcall, G.PetCmds.Restore)
            if status ~= "DONE" then return status, reason or "Restore: restoring equipped pets" end
            tx.pausedPets = false
            writeStateFile()
        end
        return "DONE"
    end
    function M.tick()
        local mg, now = state.minigame, os.time()
        local tx = mg.transaction
        if not tx then
            if mg.restorePets then
                if genv.VyMinigameOperation and genv.VyMinigameOperation.pending then
                    local pending = genv.VyMinigameOperation
                    if pending == mg.petRestoreOperation and os.clock() - pending.at > CONFIG.MinigameActionTimeout then
                        mg.restorePets = false
                        mg.lastFailure = "pet restoration timed out; no duplicate request will be sent"
                        mg.nextStartAt = now + CONFIG.MinigameRetryCooldown
                        writeStateFile()
                    end
                    return
                end
                local restore = mg.petRestoreOperation
                if restore then
                    if not restore.done then return end
                    mg.petRestoreOperation = nil
                    if restore.ok then
                        mg.restorePets = false
                        writeStateFile()
                    else
                        mg.lastFailure = "pet restoration failed; retrying before minigames"
                        mg.petRestoreRetryAt = os.clock() + 5
                    end
                    return
                end
                if os.clock() < (mg.petRestoreRetryAt or 0) then return end
                if (mg.petRestoreAttempts or 0) >= 3 or not isfn(G.PetCmds, "Restore") then
                    mg.restorePets = false
                    mg.lastFailure = "pet restoration failed; normal auto-equip will retry"
                    mg.nextStartAt = now + CONFIG.MinigameRetryCooldown
                    writeStateFile()
                    return
                end
                mg.petRestoreAttempts = (mg.petRestoreAttempts or 0) + 1
                restore = { pending = true, owner = handle, at = os.clock() }
                mg.petRestoreOperation, genv.VyMinigameOperation = restore, restore
                task.spawn(function()
                    if not state.alive or mg.petRestoreOperation ~= restore then restore.pending = false; return end
                    local ok, result = gcall(G.PetCmds.Restore)
                    restore.pending = false
                    if state.alive and mg.petRestoreOperation == restore then
                        restore.ok, restore.done = ok and result ~= false, true
                    end
                end)
                return
            end
            if state.areaProgression and (state.areaProgression.hold or state.areaProgression.operation) then return end
            if genv.VyAreaOperation and genv.VyAreaOperation.pending and genv.VyAreaOperation.userId == LocalPlayer.UserId then return end
            if not CONFIG.AutoMinigames then return end
            if mg.normalWorkUntil == nil then
                mg.normalWorkUntil = now + (CONFIG.MinigameNormalWorkSeconds or 300)
                writeStateFile()
            end
            if now < (mg.nextStartAt or 0) or (not mg.priorityFirst and M.hasNormalGoals() and now < mg.normalWorkUntil) then return end
            for _, goal in ipairs(state.goals) do
                if MINIGAME_DEFS[goal.Type] and M.start(goal) then break end
            end
            return
        end
        local phase = tx.phase
        if phase ~= "RECOVERY" and phase ~= "ABORTED" and not tx.recoveryAt then
            if not CONFIG.AutoMinigames and M.destination(tx, false) ~= "MINIGAME_RETURN" then
                M.fail(tx, "AutoMinigames disabled"); return
            end
            if now - tx.timestamp > CONFIG.MinigameTransactionTimeout then M.fail(tx, "transaction time limit reached"); return end
        end
        if phase ~= "ABORTED" and tx.recoveryAt and now - tx.recoveryAt > CONFIG.MinigameRecoveryTimeout then
            tx.aborted = true
            tx.recoveryReason = (tx.recoveryReason or "recovery failed") .. "; automatic recovery time limit reached"
            M.discardOperation()
            M.phase(tx, "ABORTED")
            return
        end
        local phaseLimit = (phase == "EXECUTE" or phase == "VERIFY") and CONFIG.MinigameNoProgressTimeout
            or (phase == "WORLD_TRAVEL" or phase == "RETURN") and CONFIG.MinigameTravelTimeout
            or CONFIG.MinigamePhaseTimeout
        local since = (phase == "EXECUTE" or phase == "VERIFY") and tx.lastProgressAt or tx.phaseAt
        if phase ~= "RECOVERY" and phase ~= "ABORTED" and now - since > phaseLimit then
            local detail = phase == "RESTORE" and mg.session.status
            M.fail(tx, phase .. " timed out" .. (detail and (": " .. detail) or "")); return
        end
        if phase == "PREPARE" or phase == "SAVE_CONTEXT" or phase == "PAUSE"
            or phase == "WORLD_TRAVEL" or phase == "INSTANCE_ENTRY" then
            local outcome = M.observe(tx)
            if outcome == "UNKNOWN" then return end
            if outcome ~= "ACTIVE" then
                tx.outcome = outcome
                if outcome ~= "COMPLETED" then tx.recoveryReason = "quest outcome: " .. outcome end
                M.discardOperation()
                M.phase(tx, "EXIT")
                return
            end
        end
        if phase == "PREPARE" then
            if not (isfn(G.InstancingCmds, "Enter") and isfn(G.InstancingCmds, "Leave")
                and isfn(G.InstancingCmds, "IsInInstance")) then M.fail(tx, "instance entry/exit interface unavailable"); return end
            if not M.remote("Instancing_FireCustomFromClient", "RemoteEvent") then M.fail(tx, "custom instance event unavailable"); return end
            if string.find(tx.instanceName, "Fishing", 1, true) and not M.remote("Instancing_InvokeCustomFromClient", "RemoteFunction") then
                M.fail(tx, "fishing interaction interface unavailable"); return
            end
            if not (isfn(G.PetCmds, "GetEquipped") and isfn(G.PetCmds, "Restore")
                and M.remote("Pets_UnequipAll", "RemoteEvent")) then M.fail(tx, "pet pause/restore interface unavailable"); return end
            local returnWorld = tonumber((bestZone() or {}).WorldNumber) or tx.originalWorld
            if currentWorld() ~= tx.targetWorld or returnWorld ~= tx.targetWorld then
                local ready, reason = queueSelf(true)
                if not ready then M.fail(tx, reason or "teleport re-execution unavailable"); return end
            end
            M.phase(tx, "SAVE_CONTEXT")
        elseif phase == "SAVE_CONTEXT" then
            if M.observe(tx) ~= "ACTIVE" then M.fail(tx, "quest changed during preparation"); return end
            M.phase(tx, "PAUSE")
        elseif phase == "PAUSE" then
            for _, count in pairs(state.normalWorkers) do if count > 0 then return end end
            if state.flagBusy or state.hopping then return end
            local count = Crystal.equippedCount()
            if count == nil then return end
            if count > 0 then
                if mg.session.pauseSent then return end
                tx.pausedPets = true
                if not writeStateFile() then M.fail(tx, "cannot save pet restoration context"); return end
                local status, reason = M.call(tx, "pause-pets", netFire, "Pets_UnequipAll")
                if status == "ERROR" then M.fail(tx, reason)
                elseif status == "DONE" then mg.session.pauseSent = true end
                return
            end
            if mg.operation and not mg.operation.done then return end
            mg.operation = nil
            breakAssign = {}
            M.phase(tx, "WORLD_TRAVEL")
        elseif phase == "WORLD_TRAVEL" or phase == "RETURN" then
            if phase == "RETURN" then invalidateCaches() end
            local owner, world, zone = M.destination(tx, false, (bestZone() or {}).WorldNumber, bestZoneId())
            state.navigation.owner, state.navigation.world, state.navigation.zone = owner, world, zone
            if world and currentWorld() == world then
                state.worldSwitching, state.worldMismatch = false, false
                M.phase(tx, phase == "WORLD_TRAVEL" and "INSTANCE_ENTRY" or "RESTORE")
            elseif world then
                local ok, reason = worldTeleport(world, zone, owner)
                if ok == false then M.fail(tx, reason) end
            end
        elseif phase == "INSTANCE_ENTRY" then
            local outcome = M.observe(tx)
            if outcome ~= "ACTIVE" and outcome ~= "UNKNOWN" then tx.outcome = outcome; M.phase(tx, "EXIT"); return end
            if outcome == "UNKNOWN" then return end
            local status, reason = M.entry(tx)
            if status == "ERROR" then M.fail(tx, reason)
            elseif status == "DONE" then tx.lastProgressAt = now; M.phase(tx, "EXECUTE") end
        elseif phase == "EXECUTE" or phase == "VERIFY" then
            local outcome = M.observe(tx)
            if outcome ~= "ACTIVE" then
                if outcome ~= "UNKNOWN" then
                    tx.outcome = outcome
                    if outcome ~= "COMPLETED" then tx.recoveryReason = "quest outcome: " .. outcome end
                    M.discardOperation()
                    M.phase(tx, "EXIT")
                end
                return
            end
            if phase == "VERIFY" then
                -- Session carries fishing/digging state across quest verification ticks.
                tx.phase, tx.phaseAt = "EXECUTE", now
                return
            end
            local def = MINIGAME_DEFS[tx.goalType]
            if not mg.priorityFirst and M.hasNormalGoals() and now - tx.timestamp >= (CONFIG.MinigameVisitSeconds or 90) and not mg.operation then
                tx.outcome = "DEFERRED" -- Preserve partial server progress; let other quests run.
                M.phase(tx, "EXIT")
                return
            end
            local executor = M["execute" .. def.kind]
            if type(executor) ~= "function" then M.fail(tx, "minigame handler unavailable"); return end
            local status, reason = executor(tx)
            mg.session.status = reason or (status == "CYCLE" and "checking quest progress" or "waiting for minigame interaction")
            if status == "ERROR" then M.fail(tx, reason)
            elseif status == "CYCLE" then tx.phase, tx.phaseAt = "VERIFY", now end
        elseif phase == "EXIT" then
            local status, reason = M.exit(tx)
            if status == "ERROR" then M.fail(tx, reason)
            elseif status == "DONE" then M.phase(tx, "RETURN") end
        elseif phase == "RESTORE" then
            local status, reason = M.restoreLocation(tx)
            mg.session.status = reason or "Restore: checking farming location"
            if status == "ERROR" then M.fail(tx, reason)
            elseif status == "DONE" then M.phase(tx, "RESUME") end
        elseif phase == "RESUME" then
            M.finish(tx, tx.aborted == true or tx.recoveryReason ~= nil)
        elseif phase == "RECOVERY" then
            tx.aborted = true
            if os.clock() < (mg.session.exitRetryAt or 0) then return end
            local status, reason = M.exit(tx)
            if status == "DONE" then M.phase(tx, "RETURN")
            elseif status == "ERROR" then
                tx.recoveryReason = string.sub(tostring(reason), 1, 450)
                M.discardOperation()
                mg.session.exitFailures = (mg.session.exitFailures or 0) + 1
                mg.session.exitRetryAt = os.clock() + 3
                mg.session.left = nil
                if mg.session.exitFailures >= 3 then M.phase(tx, "ABORTED") end
            end
        elseif phase == "ABORTED" then
            instanceCache.at = -1e9
            local operation, travel = genv.VyMinigameOperation, genv.VyWorldTravel
            if state.worldSwitching or (operation and operation.pending) or (travel and travel.pending) or inInstance() or M.activeModel(tx) then
                mg.lastFailure = "Automatic recovery stopped: exit the instance manually or restart after the pending request settles"
                return
            end
            M.finish(tx, true) -- Normal navigation can recover only once instance exit is observed.
        end
    end
end
-- END MINIGAME RUNTIME


-- BEGIN MINIGAME ADAPTERS
-- Protocol evidence (historical third-party code; runtime checks still required):
-- https://github.com/Hoith95/Pet-99/blob/e406a3df7cd050e26975465d86f5ff57f86c4cac/Fishing-Only
-- https://github.com/Humbleble/Datasetsss/blob/112dadb8d7f9286e3b718733e623d0f76188d3d7/AutoFishPS99.txt
-- https://github.com/NTDCONCUBETI/Duongcutobeti/blob/4bcc06b46c3e80b45d03303e858d4f8404c072fe/Digsite2CTE
-- Water.Layer1: https://github.com/benomat/scripts/blob/6b6e19661167c1a330ad6f5465b7a8461e1f5b29/paste/Map.lua#L812
-- Line endpoints: https://github.com/TranMyNhi/TranMyNhi/blob/74967c9b00d87a96f17b1d3bc742b094a771d0fd/PS99#L31
-- Catch tapping while FishingGame.Enabled: same source, lines 48-53.
do
    local M = MinigameController
    local function waitReady(session, key, reason, seconds)
        local now = os.clock()
        session[key] = session[key] or now
        if now - session[key] > seconds then return "ERROR", reason end
        return "WAIT", reason
    end
    local function visibleInPlayerGui(node, pg)
        while node and node ~= pg do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("LayerCollector") and not node.Enabled then return false end
            node = node.Parent
        end
        return node == pg
    end
    local function isReelPrompt(node, pg)
        if not node or not (node:IsA("TextLabel") or node:IsA("TextButton")) then return false end
        if node.TextTransparency == 1 and node.TextStrokeTransparency == 1 then return false end
        -- The recorded tapping screen differs from the older FishingGame layout.
        -- Match its specific instruction, including a combined rich-text label.
        local text = string.lower(node.Text):gsub("<[^>]*>", ""):gsub("%p", " "):gsub("%s+", " ")
        text = text:match("^%s*(.-)%s*$") or ""
        return (text == "keep tapping to reel" or text == "tap keep tapping to reel")
            and visibleInPlayerGui(node, pg)
    end
    local function visibleFishingGame(session)
        local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then session.catchPrompt = nil; return false end
        local instances = pg and pg:FindFirstChild("_INSTANCES")
        local gameGui = instances and instances:FindFirstChild("FishingGame")
        if gameGui then
            local bar = gameGui:FindFirstChild("GameBar", true)
            local node = bar and bar:IsA("GuiObject") and bar or gameGui
            -- Old layout is a positive fast path; hidden legacy UI must not
            -- suppress a visible reel prompt in the current layout.
            if (node ~= gameGui or gameGui:IsA("ScreenGui")) and visibleInPlayerGui(node, pg) then return true end
        end
        if isReelPrompt(session.catchPrompt, pg) then return true end
        session.catchPrompt = nil
        for _, node in ipairs(pg:GetDescendants()) do
            if isReelPrompt(node, pg) then
                session.catchPrompt = node
                return true
            end
        end
        return false
    end
    local function equippedRod()
        local character = LocalPlayer and LocalPlayer.Character
        return character and character:FindFirstChild("Rod", true)
    end
    local function rodLine()
        local rod = equippedRod()
        local line = rod and rod:FindFirstChild("FishingLine", true)
        if not rod or not line then return nil end
        if not (line:IsA("Beam") or line:IsA("RopeConstraint")) then return nil end
        return line
    end
    local function fishingTarget(model, hrp)
        local best, distance
        local function consider(part, preferCenter)
            local point = part.Position
            if not preferCenter or (point - hrp.Position).Magnitude > CONFIG.MinigameCastDistance then
                -- Large water parts can have a distant center while their shore
                -- is nearby. Project into their local bounds before rejecting.
                local localPoint, size = part.CFrame:PointToObjectSpace(hrp.Position), part.Size
                local xLimit = math.max(0, size.X / 2 - math.min(6, size.X / 4))
                local zLimit = math.max(0, size.Z / 2 - math.min(6, size.Z / 4))
                point = part.CFrame:PointToWorldSpace(Vector3.new(
                    math.clamp(localPoint.X, -xLimit, xLimit), size.Y / 2,
                    math.clamp(localPoint.Z, -zLimit, zLimit)))
            end
            local d = (point - hrp.Position).Magnitude
            if not distance or d < distance then best, distance = point, d end
            return point, d
        end
        local water = model:FindFirstChild("Water")
        local layer = water and water:FindFirstChild("Layer1")
        if layer and layer:IsA("BasePart") then
            local point, d = consider(layer, true)
            if d <= CONFIG.MinigameCastDistance then return point end
        end
        local interact = model:FindFirstChild("Interactable")
        local pool = interact and interact:FindFirstChild("DeepPool")
        if pool and pool:IsA("BasePart") then
            local point, d = consider(pool, true)
            if d <= CONFIG.MinigameCastDistance then return point end
        end
        -- Normal Fishing also has Water geometry outside Interactable. Resolve a
        -- nearby point on its surface instead of casting at a large part's center.
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                local water = part.Material == Enum.Material.Water
                local parent = part
                while not water and parent and parent ~= model do
                    water = string.lower(parent.Name) == "water"
                    parent = parent.Parent
                end
                if water then
                    consider(part, false)
                end
            end
        end
        return best
    end
    local function beneath(object, ancestor)
        if not ancestor then return false end
        while object do
            if object == ancestor then return true end
            object = object.Parent
        end
        return false
    end
    local function ownBobber(model, line)
        if not line then return nil end
        local folder = model:FindFirstChild("Bobbers")
        if not folder then return nil end
        local anchors = {}
        for _, key in ipairs({ "Attachment0", "Attachment1" }) do
            local anchor = line[key]
            -- Normal and advanced fishing can use opposite line endpoints.
            -- Ignore the rod end so a nearby player's bobber cannot own our bite.
            if anchor and anchor:IsA("Attachment") and not beneath(anchor, LocalPlayer.Character) then
                anchors[#anchors + 1] = anchor
            end
        end
        local best, distance = nil, 5
        for _, candidate in ipairs(folder:GetChildren()) do
            local part = candidate:IsA("BasePart") and candidate.Name == "Bobber" and candidate
                or candidate:FindFirstChild("Bobber", true)
            if part and part:IsA("BasePart") then
                for _, anchor in ipairs(anchors) do
                    if beneath(anchor, candidate) then return part end
                    local d = (part.Position - anchor.WorldPosition).Magnitude
                    if d < distance then best, distance = part, d end
                end
            end
        end
        return best
    end
    local function bubblesAt(bobber)
        if not bobber then return false end
        local debris = workspace:FindFirstChild("__DEBRIS")
        if not debris then return false end
        local inspected = 0
        for _, host in ipairs(debris:GetChildren()) do
            inspected += 1
            if inspected > 256 then break end
            if host.Name == "host" and host:IsA("BasePart") and (host.Position - bobber.Position).Magnitude <= 2 then
                local attachment = host:FindFirstChild("Attachment")
                if attachment then
                    for _, name in ipairs({ "Bubbles", "Rare Bubbles" }) do
                        local emitter = attachment:FindFirstChild(name)
                        if emitter then return true end -- Emit() bursts need not have Enabled=true.
                    end
                end
            end
        end
        return false
    end
    local function fishing(tx)
        local session, now = state.minigame.session, os.clock()
        local model, reason = M.activeModel(tx)
        if not model then return waitReady(session, "missingAt", reason, CONFIG.MinigameTargetTimeout) end
        session.missingAt = nil
        local stage: string = session.fishStage or "READY"
        local catching = visibleFishingGame(session)
        -- Consume the outstanding request before inspecting transient geometry.
        -- A cast creates FishingLine; reeling removes bubbles; a catch removes the line.
        local op = state.minigame.operation
        if op then
            if op.key ~= "cast" and op.key ~= "reel" and op.key ~= "fish-click" then
                return "ERROR", "unexpected pending fishing operation: " .. tostring(op.key)
            end
            local status, why = M.call(tx, op.key, op.key == "fish-click" and netInvoke or netFire)
            if status == "ERROR" then return status, why end
            if status == "DONE" then
                if op.key == "cast" then session.fishStage, session.stageAt = "BITE", now
                elseif op.key == "reel" then session.fishStage, session.stageAt = "REEL", now
                else
                    session.fishTaps = (session.fishTaps or 0) + 1
                    session.nextAt = op.at + (CONFIG.MinigameFishingClickInterval or 0.2)
                end
            end
            if status ~= "DONE" or op.key ~= "fish-click" then
                return "WAIT", why or ("Fishing: " .. op.key .. (status == "DONE" and " sent" or " pending"))
            end
            -- A completed tap releases the single-operation lease. Continue to
            -- check the live UI and send the next due tap in this same tick.
        end
        if catching then
            if stage ~= "CATCH" then
                session.fishStage, session.stageAt, session.fishTaps = "CATCH", now, 0
                return "WAIT", "Fishing: catch interaction ready"
            end
        end
        if stage == "READY" then
            local hrp = getHRP()
            if not equippedRod() or not hrp then return waitReady(session, "rodAt", "Fishing: waiting for equipped rod/character", CONFIG.MinigameTargetTimeout) end
            session.rodAt = nil
            if now < (session.nextAt or 0) then return "WAIT", "Fishing: preparing next cast" end
            if now >= (session.targetScanAt or 0) then
                session.targetScanAt, session.castTarget = now + 2, fishingTarget(model, hrp)
            end
            local target = session.castTarget
            if not target then return waitReady(session, "targetAt", "Fishing: no replicated DeepPool/Water surface found", CONFIG.MinigameTargetTimeout) end
            local castDistance = (hrp.Position - target).Magnitude
            if castDistance > CONFIG.MinigameCastDistance then
                return "ERROR", string.format("nearest fishing water is %.0f studs away (cast limit %.0f)",
                    castDistance, CONFIG.MinigameCastDistance)
            end
            session.targetAt = nil
            local status, why = M.call(tx, "cast", netFire, "Instancing_FireCustomFromClient", tx.instanceName, "RequestCast", target)
            if status == "DONE" then session.fishStage, session.stageAt = "BITE", now end
            return status == "ERROR" and "ERROR" or "WAIT", why or "Fishing: casting"
        elseif stage == "BITE" then
            if now - session.stageAt > CONFIG.MinigameBiteTimeout then return "ERROR", "no observed bite after cast" end
            local line = rodLine()
            if not line then return "WAIT", "Fishing: waiting for line after cast" end
            if now >= (session.biteScanAt or 0) then
                session.biteScanAt = now + 0.5
                session.bobber = ownBobber(model, line)
                session.bite = bubblesAt(session.bobber)
            end
            if not session.bobber then return "WAIT", "Fishing: waiting for bobber connected to rod line" end
            if not session.bite then return "WAIT", "Fishing: waiting for bite" end
            local status, why = M.call(tx, "reel", netFire, "Instancing_FireCustomFromClient", tx.instanceName, "RequestReel")
            if status == "DONE" then session.fishStage, session.stageAt = "REEL", now end
            return status == "ERROR" and "ERROR" or "WAIT", why or "Fishing: reeling"
        elseif stage == "REEL" then
            if now - session.stageAt > CONFIG.MinigameActionTimeout then return "ERROR", "catch UI did not activate after reel" end
            return "WAIT", "Fishing: waiting for catch interaction"
        elseif stage == "CATCH" then
            if not catching then
                session.fishStage, session.nextAt, session.bite = "READY", now + 1, false
                return "CYCLE", "Fishing: checking quest progress" -- Only live rank data can certify completion.
            end
            if now - session.stageAt > CONFIG.MinigameActionTimeout then return "ERROR", "catch interaction exceeded time limit" end
            local tapping = "Fishing: tapping catch bar | " .. tostring(session.fishTaps or 0) .. " taps"
            if now < (session.nextAt or 0) then return "WAIT", tapping end
            local status, why = M.call(tx, "fish-click", netInvoke, "Instancing_InvokeCustomFromClient", tx.instanceName, "Clicked")
            return status == "ERROR" and "ERROR" or "WAIT", why or tapping
        end
        return "ERROR", "unknown fishing stage"
    end
    local function accessible(target, blocks, hrp)
        local part = M.part(target)
        if not part or not part.Parent then return false end
        if (hrp.Position - part.Position).Magnitude > CONFIG.MinigameMaxTargetDistance then return false end
        if blocks then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = { blocks }
            local hit = workspace:Raycast(hrp.Position, part.Position - hrp.Position, params)
            if hit and hit.Instance ~= part and not hit.Instance:IsDescendantOf(target) then return false end
        end
        return true, part
    end
    local function chooseDigTarget(folder, blocks, hrp)
        local best, nearest
        if not folder then return nil end
        for _, object in ipairs(folder:GetChildren()) do
            local coord = object:GetAttribute("Coord")
            if typeof(coord) == "Vector3" then
                local ok, part = accessible(object, blocks, hrp)
                if ok then
                    local distance = (hrp.Position - part.Position).Magnitude
                    if not nearest or distance < nearest then best, nearest = object, distance end
                end
            end
        end
        return best
    end
    local function digging(tx)
        local session, now = state.minigame.session, os.clock()
        local model, reason = M.activeModel(tx)
        if not model then return waitReady(session, "missingAt", reason, CONFIG.MinigameTargetTimeout) end
        session.missingAt = nil
        local hrp = getHRP()
        if not hrp then return waitReady(session, "rootAt", "character not ready", CONFIG.MinigameTargetTimeout) end
        local important = model:FindFirstChild("Important")
        local blocks = important and important:FindFirstChild("ActiveBlocks")
        local chests = important and important:FindFirstChild("ActiveChests")
        if not blocks or not chests then return waitReady(session, "foldersAt", "digsite blocks/chests did not replicate", CONFIG.MinigameTargetTimeout) end
        if state.minigame.operation then
            local status, why = M.call(tx, "dig", netFire, "Instancing_FireCustomFromClient", tx.instanceName, session.command, session.coord)
            if status == "DONE" then session.nextAt = now + CONFIG.MinigameActionInterval; return "CYCLE" end
            return status, why
        end
        if now < (session.nextAt or 0) then return "WAIT" end
        if not session.target or not session.target.Parent or now >= (session.scanAt or 0) then
            session.scanAt = now + 1
            local target = chooseDigTarget(chests, blocks, hrp)
            local command = "DigChest"
            if not target then target, command = chooseDigTarget(blocks, blocks, hrp), "DigBlock" end
            if target ~= session.target then session.targetAt = now end
            session.target, session.command = target, command
        end
        local target = session.target
        if not target then return waitReady(session, "emptyAt", "no reachable dig targets with Coord attributes", CONFIG.MinigameTargetTimeout) end
        session.emptyAt = nil
        if now - (session.targetAt or now) > CONFIG.MinigameTargetTimeout then return "ERROR", "dig target did not change within time limit" end
        local coord, part = target:GetAttribute("Coord"), M.part(target)
        if typeof(coord) ~= "Vector3" or not part or not part.Parent then session.target = nil; return "WAIT" end
        local above = part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0)
        if (hrp.Position - above).Magnitude > 8 then
            local ok, why = M.move(tx, CFrame.new(above))
            if not ok then return "ERROR", why end
            session.nextAt = now + 0.4
            return "WAIT"
        end
        session.coord = coord
        local status, why = M.call(tx, "dig", netFire, "Instancing_FireCustomFromClient", tx.instanceName, session.command, coord)
        return status == "ERROR" and "ERROR" or "WAIT", why
    end
    function M.executeFishing(tx) return fishing(tx) end
    function M.executeAdvancedFishing(tx) return fishing(tx) end
    function M.executeDigsite(tx) return digging(tx) end
    function M.executeAdvancedDigsite(tx) return digging(tx) end
end
-- END MINIGAME ADAPTERS

-- =====================================================================================
-- Crystal rank controller. The no-argument call below was confirmed in a live one-key test.
function Crystal.controller()
    if MinigameController.holdsWork() or state.minigame.restorePets then return end
    if state.areaProgression.hold or state.areaProgression.operation then return end
    local c = state.crystal
    if not CONFIG.AutoCrystalRank then
        if c.hold or c.pausedPets then Crystal.finish("OFF", false) end
        c.status = "OFF"
        return
    end
    if c.halted then c.status = "Crystal paused: " .. tostring(c.halted); return end
    local setup, reason = Crystal.inspect(getSave(), state.rank)
    if not setup and (reason == "waiting for rank data" or reason == "rank quest pool unavailable")
        and (c.hold or c.pausedPets) then Crystal.waitForData(); return end
    c.dataAt = nil
    local limit = math.max(0, tonumber(CONFIG.CrystalKeyLimit) or 5000)
    local reserve = math.max(0, tonumber(CONFIG.CrystalKeyReserve) or 100)
    if c.used >= limit and not c.batch then Crystal.finish("key limit reached", true); return end
    if not setup or setup.keys <= reserve then
        if c.hold or c.pausedPets then Crystal.finish(reason or "key reserve reached", false) end
        c.status = "Crystal: " .. tostring(reason or "key reserve reached")
        return
    end
    if c.pins and (c.pins.rank ~= setup.rank or c.pins.diamond ~= setup.diamond or c.pins.area ~= setup.area) then
        Crystal.finish("Crystal: quest setup changed; rerolling", false)
        return
    end
    c.hold = true
    c.pins = c.pins or { rank = setup.rank, diamond = setup.diamond, area = setup.area }
    if not Crystal.pause() then return end
    if currentWorld() ~= 1 then
        c.status = "Crystal: travelling to World 1"
    else
        c.status = string.format("Crystal: opening | requests %d/%d | reserve %d", c.used, limit, reserve)
    end
    local pending = genv.VyCrystalOpening
    if pending and pending.pending and os.clock() - (pending.at or os.clock()) > 15 then
        Crystal.finish("chest request still pending; no retry", true)
    end
end
function Crystal.atChest()
    if MinigameController.holdsWork() or state.minigame.restorePets then return end
    local c, now = state.crystal, os.clock()
    local map = workspace:FindFirstChild("Map")
    local castle = map and map:FindFirstChild("3 | Castle")
    local interact = castle and castle:FindFirstChild("INTERACT")
    local chest = interact and interact:FindFirstChild("CrystalChest")
    local pad = chest and chest:FindFirstChild("Pad")
    local hrp = getHRP()
    if not hrp then return false end
    if not pad or not pad:IsA("BasePart") then
        c.chestWaitAt = c.chestWaitAt or now
        if now - c.chestWaitAt > 30 then Crystal.finish("Crystal Chest did not load", true); return false end
        if now - (c.lastMoveAt or -1e9) >= 3 then
            c.lastMoveAt = now
            for id, zone in pairs(G.Zones or {}) do
                if type(zone) == "table" and zone.WorldNumber == 1 and zone.ZoneNumber == 3
                    and isfn(G.ZonesUtil, "GetTeleportPartLocation") then
                    local cf = gval(G.ZonesUtil.GetTeleportPartLocation, id)
                    if typeof(cf) == "CFrame" then
                        pcall(function() hrp.CFrame = cf + Vector3.new(0, 3, 0); hrp.AssemblyLinearVelocity = Vector3.zero end)
                    end
                    break
                end
            end
        end
        c.status = "Crystal: loading Castle chest"
        return false
    end
    c.chestWaitAt = nil
    if (hrp.Position - pad.Position).Magnitude > 12 then
        c.lastMoveAt = now
        pcall(function() hrp.CFrame = CFrame.new(pad.Position + Vector3.new(0, 3, 0)); hrp.AssemblyLinearVelocity = Vector3.zero end)
        c.status = "Crystal: moving beside chest"
        return false
    end
    return now - (c.lastMoveAt or -1e9) >= 0.5
end
function Crystal.openTick()
    if MinigameController.holdsWork() or state.minigame.restorePets then return end
    local c, now = state.crystal, os.clock()
    if not state.alive or not CONFIG.AutoCrystalRank or c.halted or not c.hold or not c.travelReady
        or state.worldSwitching or state.hopping or currentWorld() ~= 1 or inInstance() then return end
    local pending = genv.VyCrystalOpening
    if pending and pending.pending then return end
    if Crystal.equippedCount() ~= 0 then Crystal.pause(); return end
    local liveSave = getSave()
    local setup, reason = Crystal.inspect(liveSave, state.rank)
    if not setup and (reason == "waiting for rank data" or reason == "rank quest pool unavailable") then
        Crystal.waitForData()
        return
    end
    c.dataAt = nil
    if not setup or not c.pins or setup.rank ~= c.pins.rank or setup.diamond ~= c.pins.diamond or setup.area ~= c.pins.area then
        Crystal.finish("Crystal: quest setup changed; rerolling", false)
        return
    end
    if setup.keys <= math.max(0, tonumber(CONFIG.CrystalKeyReserve) or 100)
        or c.used >= math.max(0, tonumber(CONFIG.CrystalKeyLimit) or 5000) then
        Crystal.finish("key limit or reserve reached", true)
        return
    end
    if not Crystal.atChest() then return end
    if now < (c.nextAt or 0) then return end
    local batch = c.batch
    if batch and batch.left == 0 then
        local first, before = setup.first, batch.before
        local credited = first.UID ~= before.uid or (tonumber(first.Progress) or 0) > before.progress
            or (tonumber(liveSave.RankStars) or 0) > before.stars
        if credited then
            c.batch, c.reserved = nil, 0
            writeStateFile()
        elseif now - batch.lastAt > math.max(1, tonumber(CONFIG.CrystalCreditWait) or 10) then
            Crystal.finish("no collection credit after opening; no retry", true)
        else c.status = "Crystal: waiting for collection credit" end
        return
    end
    local remaining = math.max(0, (tonumber(setup.first.Amount) or 0) - (tonumber(setup.first.Progress) or 0))
    if remaining == 0 then
        c.rotationAt = c.rotationAt or now
        if now - c.rotationAt > 15 then Crystal.finish("slot 1 did not rotate", true) end
        return
    end
    c.rotationAt = nil
    if not batch then
        local remotes = RS:FindFirstChild("Network")
        local remote = remotes and remotes:FindFirstChild("CrystalKey_Unlock")
        if not remote or not remote:IsA("RemoteFunction") then Crystal.finish("confirmed chest interface unavailable", true); return end
        c.keyEstimate = math.min(c.keyEstimate or setup.keys, setup.keys)
        local reserve = math.max(0, tonumber(CONFIG.CrystalKeyReserve) or 100)
        local limit = math.max(0, tonumber(CONFIG.CrystalKeyLimit) or 5000)
        local n = math.floor(math.min(math.max(1, tonumber(CONFIG.CrystalBurst) or 10), remaining,
            c.keyEstimate - reserve, limit - c.used))
        if n < 1 then Crystal.finish("key limit or reserve reached", true); return end
        batch = { left = n, before = { uid = setup.first.UID, progress = tonumber(setup.first.Progress) or 0,
            stars = tonumber(liveSave.RankStars) or 0 }, lastAt = now }
        c.batch, c.reserved = batch, n
        -- Persist the whole reservation first. A crash can over-count the budget, never under-count it.
        if not writeStateFile() then
            Crystal.finish("could not save the key budget; no opening sent", true)
            return
        end
    end
    batch.left -= 1
    c.reserved -= 1
    c.used += 1
    c.keyEstimate -= 1
    local lease = { pending = true, at = now, owner = handle }
    genv.VyCrystalOpening = lease
    local ok, res, msg = netInvoke("CrystalKey_Unlock") -- verified signature: no arguments, one owned key
    lease.pending = false
    if not state.alive then return end
    if not ok or res == false then
        Crystal.finish("chest opening failed: " .. tostring(ok and (msg or res) or res), true)
        return
    end
    batch.lastAt = os.clock()
    c.nextAt = batch.lastAt + math.max(0.05, tonumber(CONFIG.CrystalOpenDelay) or 0.15)
end
function Crystal.setEnabled(value)
    local c = state.crystal
    CONFIG.AutoCrystalRank = value == true
    if CONFIG.AutoCrystalRank then
        c.used, c.reserved, c.keyEstimate, c.halted = 0, 0, nil, nil
        c.batch, c.pins, c.rotationAt, c.chestWaitAt = nil, nil, nil, nil
        c.status = "Crystal: preparing quests"
        if not MinigameController.holdsWork() then Crystal.controller() end
    else Crystal.finish("OFF", false) end
    writeStateFile()
end
restoreFns[#restoreFns + 1] = Crystal.release

-- 17. Controller thread
-- =====================================================================================
local function onRankUp(info)
    log("RANK UP! now rank %d - %s", info.rankNumber, tostring(info.title))
    -- pending claims of the previous rank must have been redeemed for the rank-up to happen
    for i in pairs(state.pendingClaims) do
        state.counters.claimed += 1
        state.pendingClaims[i] = nil
    end
    state.claimedAt = {}
    state.claimAttempts = {}
    state.trackCompleteLoggedRank = nil
    state.trackCompleteAt = nil
    state.rankUpFiredRank = nil
    state.lastZoneBuyAt = 0
    resetOnce("rank:")
    hatchFailures = 0
    hatchBackoffUntil = 0
    hatchNeedsHop = false
    hopFailedEggId = nil
    invalidateCaches()
    writeStateFile()
end

local function claimRewards(info)
    if not CONFIG.AutoClaimRewards or not info then return end
    for i in pairs(state.pendingClaims) do
        if info.redeemed[tostring(i)] ~= nil then
            state.counters.claimed += 1
            state.pendingClaims[i] = nil
        end
    end
    local now = os.clock()
    for _, i in ipairs(earnedUnclaimedRewards(info)) do
        if not state.alive then return end
        local attempts = state.claimAttempts[i] or 0
        -- never give up: the rank cannot complete without every reward redeemed, so after MAX_CLAIM_ATTEMPTS
        -- the retry only slows down to CLAIM_SLOW_RETRY (a dropped claim / transient FFlag flip clears later)
        local stuck = attempts >= MAX_CLAIM_ATTEMPTS
        if stuck then
            warnOnce("rank:claimstuck-" .. tostring(i), "Reward #%d was requested %d times but never redeemed - retrying every %d s (RankRewards disabled server-side?)", i, attempts, CLAIM_SLOW_RETRY)
        end
        local last = state.claimedAt[i]
        if last == nil or now - last > (stuck and CLAIM_SLOW_RETRY or 5) then
            local ok, err = netFire("Ranks_ClaimReward", i)
            if ok then
                state.claimedAt[i] = now
                state.claimAttempts[i] = attempts + 1
                state.pendingClaims[i] = now
                if stuck then
                    logEvery("claim-retry-" .. tostring(i), 300, "Retrying reward #%d claim (%s/%s stars)", i, int(info.stars), int(info.totalStars))
                else
                    log("Claimed reward #%d (%s/%s stars)", i, int(info.stars), int(info.totalStars))
                end
                task.wait(0.3)
            else
                warnlog("claim-fail", "Ranks_ClaimReward %d failed: %s", i, tostring(err))
            end
        end
    end
end

local function checkTrackComplete(info)
    if not info or info.isMax then return end
    if not (info.allRedeemed and info.stars >= info.totalStars) then return end
    if info.blockedByZone or info.blockedByRebirth then return end
    if state.trackCompleteLoggedRank ~= info.rankNumber then
        state.trackCompleteLoggedRank = info.rankNumber
        state.trackCompleteAt = os.clock()
        log("Rank %d track complete - waiting for the server rank-up", info.rankNumber)
    end
    if CONFIG.TryRankUpRemote and state.rankUpFiredRank ~= info.rankNumber
        and os.clock() - (state.trackCompleteAt or 0) > 15 then
        state.rankUpFiredRank = info.rankNumber
        local ok, err = netFire("Ranks_RankUp")
        if ok then
            log("Fired Ranks_RankUp (TryRankUpRemote)")
        else
            warnlog("rankup-fail", "Ranks_RankUp failed: %s", tostring(err))
        end
    end
end

local function handleBlockedAndZones(info)
    local ok, err = pcall(AreaProgression.tick)
    if not ok then
        state.areaProgression.status = "Areas: " .. tostring(err)
        warnlog("area-progression", "%s", tostring(err))
    end
end

local function buildPlan()
    local info = state.rank
    local plan = { hatch = false, hatchReasons = {}, hatchEggOnly = true, hatchRemaining = nil, crafting = false, waitingChest = false }
    local parts = {}
    if MinigameController.holdsWork() then
        state.plan = plan
        state.action = MinigameController.status()
        return
    end
    if state.crystal.hold then
        state.plan = plan
        state.action = state.crystal.status
        return
    end
    local zone = bestZone()
    if state.worldSwitching then
        state.plan = plan
        state.action = string.format("teleporting to World %s", tostring(zone and zone.WorldNumber or "?"))
        return
    end
    if state.worldMismatch then
        parts[#parts + 1] = string.format("wrong world (best zone is in World %s)", tostring(zone and zone.WorldNumber or "?"))
    elseif info and info.isMax then
        parts[#parts + 1] = "max rank reached"
    elseif CONFIG.AutoFarm then
        local s = string.format("Farming %s (%s pets / %s targets)", tostring(bestZoneName()), int(state.farmPets), int(state.farmTargets))
        if state.counters.eventTargets > 0 then
            s = s .. string.format(", %s events caught", int(state.counters.eventTargets))
        end
        parts[#parts + 1] = s
    end
    for _, goal in ipairs(state.goals) do
        local t = goal.Type
        if goal.remaining > 0 then
            if HATCH_GOALS[t] and CONFIG.AutoHatch then
                plan.hatch = true
                table.insert(plan.hatchReasons, GOAL_TYPE_NAMES[t] or tostring(t))
                if EGG_COUNT_GOALS[t] then
                    plan.hatchRemaining = math.max(plan.hatchRemaining or 0, goal.remaining)
                else
                    plan.hatchEggOnly = false
                end
            elseif (GOLD_GOALS[t] or RAINBOW_GOALS[t]) and CONFIG.AutoCraftGoldRainbow then
                plan.crafting = true
                parts[#parts + 1] = string.format("%s %s/%s", GOLD_GOALS[t] and "gold crafting" or "rainbow crafting", int(goal.Progress), int(goal.Amount))
            elseif EVENT_GOAL_KIND[t] and CONFIG.AutoSpawnEvents then
                local def = EVENT_DEFS[EVENT_GOAL_KIND[t]]
                parts[#parts + 1] = string.format("%s %s/%s", def.label, int(goal.Progress), int(goal.Amount))
            elseif CHEST_GOALS[t] then
                plan.waitingChest = true
            elseif t == T_USE_POTION and CONFIG.AutoUsePotions then
                parts[#parts + 1] = string.format("potions T%s %s/%s", tostring(goalParam(goal, "PotionTier") or "?"), int(goal.Progress), int(goal.Amount))
            elseif t == T_UPGRADE_POTION and CONFIG.AutoUpgradePotions then
                parts[#parts + 1] = string.format("potion upgrades %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_UPGRADE_ENCHANT and CONFIG.AutoUpgradeEnchants then
                parts[#parts + 1] = string.format("enchant upgrades %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_USE_FRUIT and CONFIG.AutoUseFruits then
                parts[#parts + 1] = string.format("fruits %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_USE_FLAG and CONFIG.AutoUseFlags then
                parts[#parts + 1] = string.format("flags %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_ZONE and CONFIG.AutoBuyZones then
                parts[#parts + 1] = "buying zones"
            end
        end
    end
    local fodderOnly = false
    if state.craftHatchReason ~= nil and CONFIG.AutoHatch then
        fodderOnly = not plan.hatch
        plan.hatch = true
        plan.hatchEggOnly = false
        table.insert(plan.hatchReasons, state.craftHatchReason)
    end
    if CONFIG.AlwaysHatch and CONFIG.AutoHatch then
        plan.hatch = true
        plan.hatchEggOnly = false
        fodderOnly = false
    end
    if not plan.hatch then plan.hatchEggOnly = false end
    state.plan = plan
    if plan.hatch and not state.worldMismatch then
        local egg = cache.egg or bestEgg()
        parts[#parts + 1] = string.format("hatching %s x%s%s", tostring(egg and (egg.name or egg.id) or "best egg"), int(hatchAmount()),
            fodderOnly and " (fodder)" or "")
    end
    if plan.waitingChest then parts[#parts + 1] = "waiting for mini chest spawns" end
    if info and info.blockedByZone then
        parts[#parts + 1] = string.format("rank needs zone %s", tostring(info.zoneNumberNeeded or "?"))
    elseif info and info.blockedByRebirth then
        parts[#parts + 1] = string.format("rank needs %s rebirths (have %s)", tostring(info.rebirthsNeeded or "?"), int(info.rebirths))
    end
    if state.hopping then parts[#parts + 1] = "hopping to egg" end
    state.action = #parts > 0 and table.concat(parts, " | ") or "idle"
end

local function controllerTick()
    local info = rankInfo()
    if info then
        state.rank = info
        if state.lastRank ~= nil and info.rankNumber ~= state.lastRank then
            onRankUp(info)
        end
        state.lastRank = info.rankNumber
    end
    local goals, byType = activeGoals()
    state.goals = goals
    state.goalsByType = byType
    for _, goal in ipairs(goals) do
        if not goal.supported then
            logOnce("unsupported-" .. tostring(goal.UID), "Goal '%s' (type %s %s) is not automatable; farming continues",
                tostring(goal.title), tostring(goal.Type), GOAL_TYPE_NAMES[goal.Type] or "")
        end
    end
    local minigameOk, minigameError = pcall(MinigameController.tick)
    if not minigameOk then
        local tx = state.minigame.transaction
        if tx then MinigameController.fail(tx, minigameError)
        else warnlog("minigame-tick", "%s", tostring(minigameError)) end
    end
    if MinigameController.holdsWork() then
        checkWorld()
        buildPlan()
        return
    end
    if state.worldSwitching then
        buildPlan()
        checkWorld()
        return
    end
    pcall(claimRewards, info)
    pcall(checkTrackComplete, info)
    Crystal.controller()
    if not Crystal.holdsWork() then pcall(handleBlockedAndZones, info) end
    pcall(checkWorld)
    buildPlan()
end

-- =====================================================================================
-- 18. GUI (identity 8)
-- =====================================================================================
local GUI = { goalLabels = {} }
local WHITE = Color3.fromRGB(255, 255, 255)
local GREY = Color3.fromRGB(200, 200, 200)
local GREEN = Color3.fromRGB(90, 220, 120)
local YELLOW = Color3.fromRGB(255, 215, 90)
local RED = Color3.fromRGB(255, 140, 140)

local function create(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        inst[k] = v
    end
    inst.Parent = parent
    return inst
end

local function formatTime(total)
    total = math.max(0, math.floor(total))
    return string.format("%02d:%02d:%02d", math.floor(total / 3600), math.floor(total / 60) % 60, total % 60)
end

local function guiParent()
    if type(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and typeof(h) == "Instance" then return h end
    end
    return CoreGui
end

-- Copy only after a hub click. Keep the visible URL selectable when the
-- executor does not provide clipboard access. No browser or desktop requests.
local function copyDiscordInvite()
    local invite = CONFIG.DiscordInvite
    local code = type(invite) == "string" and string.match(invite, "^https://discord%.gg/([%w_-]+)$") or nil
    if not code then return "Invalid Discord invite" end
    if type(setclipboard) == "function" then
        local ok, result = pcall(setclipboard, invite)
        if ok and result ~= false then return "Discord link copied!" end
    end
    return "Select link below to copy"
end

local function buildGui()
    if not CONFIG.ShowGui then return end
    local ok, err = pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "VyAutoRankGui"
        sg.ResetOnSpawn = false
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.DisplayOrder = 999
        pcall(function()
            if syn and syn.protect_gui then syn.protect_gui(sg) end
        end)
        sg.Parent = guiParent()
        gui = sg

        local main = create("Frame", {
            Name = "Main",
            BackgroundColor3 = Color3.fromRGB(30, 30, 30),
            BorderSizePixel = 0,
            Position = UDim2.new(0.085, 0, 0.13, 0),
            Size = UDim2.new(0, GUI_WIDTH, 0, 250),
            Active = true,
        }, sg)
        create("UICorner", { CornerRadius = UDim.new(0, 8) }, main)
        GUI.main = main

        local function makeLabel(props)
            props.BackgroundTransparency = 1
            props.Font = props.Font or Enum.Font.SourceSans
            props.TextColor3 = props.TextColor3 or WHITE
            props.TextSize = props.TextSize or 14
            props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
            props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
            return create("TextLabel", props, main)
        end

        makeLabel({
            Name = "Title",
            Text = "VY AutoRank v" .. VERSION,
            Font = Enum.Font.SourceSansBold,
            TextSize = 16,
            Position = UDim2.new(0, 10, 0, 3),
            Size = UDim2.new(1, -50, 0, 20),
        })
        local closeBtn = create("TextButton", {
            Name = "Close",
            BackgroundTransparency = 1,
            Font = Enum.Font.SourceSansBold,
            Text = "X",
            TextColor3 = WHITE,
            TextSize = 16,
            Position = UDim2.new(1, -30, 0, 3),
            Size = UDim2.new(0, 26, 0, 20),
        }, main)
        local divider = create("Frame", {
            Name = "Divider",
            BackgroundColor3 = WHITE,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 6, 0, 25),
            Size = UDim2.new(1, -12, 0, 2),
        }, main)
        create("UICorner", { CornerRadius = UDim.new(0, 50) }, divider)

        GUI.rank = makeLabel({
            Name = "Rank",
            Text = "Rank: loading...",
            Font = Enum.Font.SourceSansSemibold,
            Position = UDim2.new(0, 10, 0, 30),
            Size = UDim2.new(1, -20, 0, LINE_H),
        })
        GUI.rewards = makeLabel({
            Name = "Rewards",
            Text = "",
            Position = UDim2.new(0, 10, 0, 30 + LINE_H),
            Size = UDim2.new(1, -20, 0, LINE_H),
        })
        for i = 1, 4 do
            GUI.goalLabels[i] = makeLabel({
                Name = "Goal" .. i,
                Text = "",
                TextColor3 = GREY,
                Position = UDim2.new(0, 10, 0, 30 + LINE_H * (1 + i)),
                Size = UDim2.new(1, -20, 0, LINE_H),
                Visible = false,
            })
        end
        GUI.status = makeLabel({
            Name = "Status",
            Text = "starting...",
            TextColor3 = GREEN,
            Position = UDim2.new(0, 10, 0, 30 + LINE_H * 6),
            Size = UDim2.new(1, -20, 0, 34),
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextTruncate = Enum.TextTruncate.None,
        })
        GUI.areas = makeLabel({
            Name = "AreaProgress", Text = "", TextColor3 = YELLOW,
            Position = UDim2.new(0, 10, 0, 180), Size = UDim2.new(1, -20, 0, 54),
            TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
            TextTruncate = Enum.TextTruncate.None,
        })
        GUI.minigame = makeLabel({
            Name = "Minigame", Text = "", TextColor3 = GREY,
            Position = UDim2.new(0, 10, 0, 180), Size = UDim2.new(1, -20, 0, 72),
            TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
            TextTruncate = Enum.TextTruncate.None, Visible = false,
        })
        GUI.counters = makeLabel({
            Name = "Counters",
            Text = "",
            TextColor3 = YELLOW,
            Position = UDim2.new(0, 10, 0, 30 + LINE_H * 6 + 36),
            Size = UDim2.new(1, -20, 0, LINE_H),
        })

        GUI.minigameToggle = create("TextButton", {
            Name = "MinigameToggle", Text = "Minigames: ON",
            BackgroundColor3 = Color3.fromRGB(45, 135, 85), BorderSizePixel = 0,
            Font = Enum.Font.SourceSansSemibold, TextSize = 15, TextColor3 = WHITE,
            Position = UDim2.new(0, 10, 0, 195), Size = UDim2.new(1, -20, 0, 26),
        }, main)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, GUI.minigameToggle)
        GUI.minigamePriority = create("TextButton", {
            Name = "MinigamePriority", Text = "Do minigames first: OFF",
            BackgroundColor3 = Color3.fromRGB(70, 70, 80), BorderSizePixel = 0,
            Font = Enum.Font.SourceSansSemibold, TextSize = 15, TextColor3 = WHITE,
            Position = UDim2.new(0, 10, 0, 224), Size = UDim2.new(1, -20, 0, 26),
        }, main)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, GUI.minigamePriority)
        track(GUI.minigameToggle.Activated:Connect(function()
            MinigameController.setEnabled(not CONFIG.AutoMinigames)
        end))
        track(GUI.minigamePriority.Activated:Connect(function()
            MinigameController.setPriority(not (CONFIG.AutoMinigames and state.minigame.priorityFirst))
        end))

        GUI.crystal = create("TextButton", {
            Name = "CrystalMode", Text = "Crystal mode: OFF (uses keys)",
            BackgroundColor3 = Color3.fromRGB(55, 115, 160), BorderSizePixel = 0,
            Font = Enum.Font.SourceSansSemibold, TextSize = 15, TextColor3 = WHITE,
            Position = UDim2.new(0, 10, 0, 195), Size = UDim2.new(1, -20, 0, 26),
        }, main)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, GUI.crystal)
        GUI.crystalKeys = makeLabel({
            Name = "CrystalKeys", Text = "", Position = UDim2.new(0, 10, 0, 224),
            Size = UDim2.new(1, -20, 0, LINE_H), TextColor3 = GREY,
        })
        track(GUI.crystal.Activated:Connect(function()
            Crystal.setEnabled(not CONFIG.AutoCrystalRank)
        end))

        GUI.discord = create("TextButton", {
            Name = "Discord",
            Text = "Copy Discord Link",
            BackgroundColor3 = Color3.fromRGB(88, 101, 242),
            BorderSizePixel = 0,
            Font = Enum.Font.SourceSansSemibold,
            TextSize = 15,
            TextColor3 = WHITE,
            Position = UDim2.new(0, 10, 0, 195),
            Size = UDim2.new(1, -20, 0, 26),
        }, main)
        create("UICorner", { CornerRadius = UDim.new(0, 5) }, GUI.discord)
        GUI.invite = create("TextBox", {
            Name = "DiscordInvite",
            Text = CONFIG.DiscordInvite,
            ClearTextOnFocus = false,
            TextEditable = false,
            BackgroundTransparency = 1,
            Font = Enum.Font.SourceSans,
            TextSize = 14,
            TextColor3 = GREY,
            Position = UDim2.new(0, 10, 0, 224),
            Size = UDim2.new(1, -20, 0, 20),
        }, main)
        local function copyFromHub()
            if not state.alive or GUI.discordBusy then return end
            GUI.discordAttempt = (GUI.discordAttempt or 0) + 1
            local attempt = GUI.discordAttempt
            GUI.discordBusy = true
            local ok, message = pcall(copyDiscordInvite)
            GUI.discordBusy = false
            if not state.alive or not GUI.discord or not GUI.discord.Parent then return end
            GUI.discord.Text = ok and message or "Select link below to copy"
            task.delay(3, function()
                if state.alive and GUI.discord and GUI.discord.Parent and GUI.discordAttempt == attempt then
                    GUI.discord.Text = "Copy Discord Link"
                end
            end)
        end
        track(GUI.discord.Activated:Connect(copyFromHub))
        track(GUI.invite.Focused:Connect(copyFromHub))

        -- dragging
        local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
        track(main.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                -- Only the title bar starts a drag; Discord/link clicks stay clickable.
                if input.Position.Y > main.AbsolutePosition.Y + 27 then return end
                dragging = true
                dragStart = input.Position
                startPos = main.Position
                local c
                c = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if c then c:Disconnect() end
                    end
                end)
            end
        end))
        track(main.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end))
        track(UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging and dragStart and startPos then
                local delta = input.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        track(closeBtn.MouseButton1Click:Connect(function()
            Stop()
        end))
        track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == CONFIG.GuiToggleKey and gui then
                gui.Enabled = not gui.Enabled
            end
        end))
    end)
    if ok then
        log("GUI created (toggle: %s)", tostring(CONFIG.GuiToggleKey and CONFIG.GuiToggleKey.Name or "none"))
    else
        warnlog("gui", "GUI creation failed: %s", tostring(err))
    end
end

local function refreshGui()
    if not gui or not GUI.main or not gui.Parent then return end
    local info = state.rank
    if info then
        GUI.rank.Text = string.format("Rank %s - %s   %s / %s stars",
            int(info.rankNumber), tostring(info.title), int(info.stars), int(info.totalStars))
        local nextIn = nextRewardIn(info)
        local tail = ""
        if nextIn then
            tail = "   next in " .. int(nextIn) .. " stars"
        elseif info.allRedeemed then
            tail = "   all claimed"
        end
        GUI.rewards.Text = string.format("Rewards %s/%s%s", int(info.redeemedCount), int(#info.rewards), tail)
    else
        GUI.rank.Text = "Rank: loading..."
        GUI.rewards.Text = ""
    end
    local goals = state.goals
    local n = math.min(#goals, 4)
    local y = 30 + LINE_H * 2
    for i = 1, 4 do
        local lbl = GUI.goalLabels[i]
        local g = goals[i]
        if g and i <= n then
            lbl.Visible = true
            lbl.Position = UDim2.new(0, 10, 0, y)
            lbl.Text = string.format("[%s*] %s  %s/%s%s", int(g.Stars), tostring(g.title), int(g.Progress), int(g.Amount),
                g.supported and "" or " (manual)")
            lbl.TextColor3 = g.supported and GREY or RED
            y += LINE_H
        else
            lbl.Visible = false
        end
    end
    y += 2
    GUI.status.Position = UDim2.new(0, 10, 0, y)
    GUI.status.Text = MinigameController.holdsWork() and ("Minigame: " .. state.minigame.transaction.phase) or tostring(state.action)
    y += 36
    local showMinigame = MinigameController.holdsWork() or state.minigame.lastFailure ~= nil
    GUI.minigame.Visible = showMinigame
    if showMinigame then
        GUI.minigame.Position = UDim2.new(0, 10, 0, y)
        GUI.minigame.Text = MinigameController.status()
        y += 76
    end
    GUI.areas.Position = UDim2.new(0, 10, 0, y)
    local areas = state.areaProgression
    GUI.areas.Text = string.format("Area %s / 219 | Rebirth %s / 9\n%s",
        tostring(areas.current or "?"), tostring(areas.rebirths or "?"), tostring(areas.status))
    y += 58
    GUI.counters.Position = UDim2.new(0, 10, 0, y)
    local c = state.counters
    GUI.counters.Text = string.format("hatched %s | claimed %s | crafted %s | items %s | up %s",
        int(c.hatched), int(c.claimed), int(c.crafted), int(c.itemsUsed), formatTime(os.clock() - state.startedAt))
    y += LINE_H + 6
    if GUI.minigameToggle then
        GUI.minigameToggle.Position = UDim2.new(0, 10, 0, y)
        GUI.minigameToggle.Text = CONFIG.AutoMinigames and "Minigames: ON"
            or (MinigameController.holdsWork() and "Minigames: OFF (returning)" or "Minigames: OFF")
        GUI.minigameToggle.BackgroundColor3 = CONFIG.AutoMinigames and Color3.fromRGB(45, 135, 85)
            or Color3.fromRGB(100, 65, 65)
        y += 29
        GUI.minigamePriority.Position = UDim2.new(0, 10, 0, y)
        local first = CONFIG.AutoMinigames and state.minigame.priorityFirst == true
        GUI.minigamePriority.Text = first and "Do minigames first: ON" or "Do minigames first: OFF"
        GUI.minigamePriority.BackgroundColor3 = first and Color3.fromRGB(145, 100, 35)
            or Color3.fromRGB(70, 70, 80)
        y += 29
    end
    if GUI.crystal then
        GUI.crystal.Position = UDim2.new(0, 10, 0, y)
        local crystal = state.crystal or {}
        GUI.crystal.Text = CONFIG.AutoCrystalRank and (crystal.halted and "Crystal mode: PAUSED (toggle to reset)" or "Crystal mode: ON (uses keys)")
            or "Crystal mode: OFF (uses keys)"
        y += 29
        GUI.crystalKeys.Position = UDim2.new(0, 10, 0, y)
        GUI.crystalKeys.Text = string.format("Keys %s | requests %s/%s | reserve %s", int(Crystal.keyCount(getSave())),
            int(crystal.used or 0), int(CONFIG.CrystalKeyLimit or 5000), int(CONFIG.CrystalKeyReserve or 100))
        y += LINE_H + 6
    end
    GUI.discord.Position = UDim2.new(0, 10, 0, y)
    y += 29
    GUI.invite.Position = UDim2.new(0, 10, 0, y)
    y += 26
    GUI.main.Size = UDim2.new(0, GUI_WIDTH, 0, y)
end

-- =====================================================================================
-- 19. Threads, bootstrap, startup
-- =====================================================================================
-- Every loop iteration is pcall'ed; intervalFn() decides the wait (idle loops back off to 1 s).
local function spawnLoop(name, tickFn, intervalFn)
    task.spawn(function()
        while state.alive do
            local normal = name == "farm" or name == "hatch" or name == "craft" or name == "events" or name == "diamond flag" or name == "crystal"
            local ok, err = true, nil
            if not normal or normalWorkAllowed() then
                if normal then
                    state.normalWorkers[name] = (state.normalWorkers[name] or 0) + 1
                    state.normalThreads[coroutine.running()] = true
                end
                ok, err = pcall(tickFn)
                if normal then
                    state.normalWorkers[name] -= 1
                    state.normalThreads[coroutine.running()] = nil
                end
            end
            if not ok then
                warnlog("loop-" .. name, "%s loop error: %s", name, tostring(err))
                task.wait(1)
            end
            if not state.alive then break end
            local okI, iv = pcall(intervalFn)
            iv = okI and tonumber(iv) or 1
            task.wait(math.max(0.05, iv))
        end
    end)
end

local function farmInterval()
    if not normalWorkAllowed() then return 1 end
    if Crystal.holdsWork() then return 1 end
    if not CONFIG.AutoFarm or state.worldSwitching or state.worldMismatch then return 1 end
    return CONFIG.FarmTick
end

local function hatchInterval()
    if not normalWorkAllowed() then return 1 end
    if Crystal.holdsWork() then return 1 end
    local now = os.clock()
    if hatchBackoffUntil > now then return math.min(5, hatchBackoffUntil - now) end
    if not hatchPlanned() or state.worldSwitching or state.worldMismatch then return 1 end
    return CONFIG.HatchDelay
end

local function startThreads()
    spawnLoop("controller", controllerTick, function()
        local tx = state.minigame.transaction
        return tx and tx.phase ~= "ABORTED" and CONFIG.MinigameTick or CONFIG.ControllerTick
    end)
    spawnLoop("crystal", Crystal.openTick, function() return normalWorkAllowed() and 0.1 or 1 end)
    spawnLoop("farm", farmTick, farmInterval)
    spawnLoop("hatch", hatchTick, hatchInterval)
    spawnLoop("craft", craftTick, function() return CONFIG.CraftTick end)
    spawnLoop("events", eventTick, function() return CONFIG.EventTick end)
    spawnLoop("diamond flag", maintainDiamondFlag, function() return 3 end)
    spawnLoop("gui", refreshGui, function() return 0.5 end)
    spawnLoop("persist", writeStateFile, function() return 60 end)
    installBreakableListener()
end

local function bootstrap()
    local loadedAt = os.clock()
    repeat task.wait(0.25) until game:IsLoaded() or not state.alive or os.clock() - loadedAt > 90
    if not game:IsLoaded() then warn(TAG .. "client did not load within 90 seconds"); return false end
    if not state.alive then return false end
    local t0 = os.clock()
    while state.alive and not Players.LocalPlayer do
        if os.clock() - t0 > 60 then
            warn(TAG .. "LocalPlayer not available after 60 s - aborting")
            return false
        end
        task.wait(0.5)
    end
    if not state.alive then return false end
    LocalPlayer = Players.LocalPlayer
    t0 = os.clock()
    while state.alive do
        local lib = RS:FindFirstChild("Library")
        local client = lib and lib:FindFirstChild("Client")
        if client then break end
        if os.clock() - t0 > 60 then
            warn(TAG .. "ReplicatedStorage.Library.Client not found after 60 s - aborting")
            return false
        end
        logEvery("boot-lib", 5, "Waiting for ReplicatedStorage.Library.Client...")
        task.wait(0.5)
    end
    if not state.alive then return false end
    loadModules()
    if not (G.Save and G.Network) then
        warn(TAG .. "Save/Network module unavailable - cannot continue")
        return false
    end
    t0 = os.clock()
    while state.alive and getSave() == nil do
        if os.clock() - t0 > 60 then
            warn(TAG .. "Save.Get() stayed nil for 60 s - aborting")
            return false
        end
        logEvery("boot-save", 5, "Waiting for save data...")
        task.wait(0.5)
    end
    -- soft wait for the client's own loaded flag (hub approach), capped at 5 s
    t0 = os.clock()
    while state.alive and os.clock() - t0 < 5 do
        local ok, loaded = pcall(function() return LocalPlayer:GetAttribute("__LOADED") end)
        if ok and loaded then break end
        task.wait(0.25)
    end
    return state.alive
end

local function startupSummary()
    local info = state.rank
    if info then
        log("Rank %s - %s | %s/%s stars | rewards %s/%s | rebirths %s", int(info.rankNumber), tostring(info.title), int(info.stars),
            int(info.totalStars), int(info.redeemedCount), int(#info.rewards), int(info.rebirths))
    end
    for _, g in ipairs(state.goals) do
        log("  goal [%s*] %s  %s/%s (type %s)%s", int(g.Stars), tostring(g.title), int(g.Progress), int(g.Amount), tostring(g.Type),
            g.supported and "" or " (manual)")
    end
    local zone = bestZone()
    local egg = bestEgg()
    log("Best zone: %s (world %s) | best egg: %s (#%s, max hatch %s) | current world: %s",
        tostring(bestZoneName()), tostring(zone and zone.WorldNumber or "?"),
        tostring(egg and (egg.name or egg.id) or "?"), tostring(egg and egg.number or "?"), int(maxHatch()),
        tostring(currentWorld() or "?"))
    if state.action ~= "" then log("Action: %s", state.action) end
end

local function main()
    log("VY AutoRank v%s starting (identity %s)", VERSION, tostring(type(getthreadidentity) == "function" and getthreadidentity() or "?"))
    if not bootstrap() then
        Stop()
        return
    end
    restoreStateFile()
    installPatches()
    pcall(installAntiAfk)
    queueSelf(false)
    buildGui()
    local ok, err = pcall(controllerTick)
    if not ok then warnlog("first-tick", "first controller tick failed: %s", tostring(err)) end
    startThreads()
    pcall(startupSummary)
    log("All threads running. Stop with getgenv().VyAutoRank.Stop() or the GUI X button.")
end

task.spawn(function()
    local ok, err = pcall(main)
    if not ok then
        warn(TAG .. "fatal error during startup: " .. tostring(err))
        Stop()
    end
end)
