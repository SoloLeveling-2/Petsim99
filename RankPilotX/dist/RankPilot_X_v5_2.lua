--[[
 RankPilot X v5.2.0 / ZapHub-style module hub on the v5.1 engine (v4.6 VY engine + v3.10 reference)
 v5.2: module framework (src/modules), 16-page UI with search and status chips,
 22 v5.1 bug fixes, rank telemetry + stall recovery, items/events/player modules.
 VY source integration: persistent bulk pet targeting, instant event reactions,
 exact infinite pet speed, optional cross-world continuation: 2026-10-10
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
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return warn("[RankPilot] LocalPlayer not available") end

local environment = (type(getgenv) == "function" and getgenv()) or _G
if type(environment.RankPilot) == "table" and type(environment.RankPilot.Stop) == "function" then
    pcall(environment.RankPilot.Stop)
end

local Config: any = {
    Enabled = false,             -- Click START in the GUI after reviewing status
    AutoRank = true,
    AutoWorld = true,           -- Buy available gates only in the currently loaded world
    AutoZoneTeleports = false,  -- Optional manual game teleport for owned areas
    AutoLoadBestArea = true, -- Automatically request current-world BEST area when its farm field is not streamed in.
    AutoFarm = true,
    AutoHatch = true,          -- Separate hatch worker independent of primary quest planner
    AutoHatchAlways = false,   -- Opt in explicitly if hatching without a rank quest.
    AutoHatchForRainbow = true, -- Hatch best eggs only while rainbow-quest materials are missing.
    AutoHatchForGold = true, -- Hatch best eggs if a GOLD best-egg quest lacks convertible regular pets.
    HatchFarmRemoteProbe = false, -- Prior live report rejected remote hatch away from egg; avoid unnecessary probes.
    SkipEggAnimations = true,  -- DZ Hub technique: hide egg opening screen and click prompt
    HatchInterval = 0.65,      -- Verified egg requests, not every render frame.
    HatchFirstMode = true,     -- Active hatch/material quests own movement until done or short on currency.
    HatchFirstVersion = 1,

    AutoParallelQuests = true,  -- Concurrent lanes: farming, hatching, collecting, consumables
    HatchMovementShare = true, -- Share character position in bounded windows when egg is elsewhere
    HatchSharePeriod = 34,     -- Seconds per shared movement cycle
    HatchShareSeconds = 12,    -- Seconds reserved for hatching when both lanes need movement
    AutoConsumables = true,
    AutoEventItems = true,      -- Only when an active matching rank quest exists; consumes jar/comet items.
    AutoUpgradeCollections = true, -- Requested automation: spends surplus low-tier materials; validates quest credit.
    UpgradeKeepReserve = 10,    -- Keep at least ten of each input tier/type when possible.
    UpgradePauseSeconds = 125,  -- Back off when game did not credit an upgrade.
    UpgradeInterval = 1.5,        -- Bounded time between crafting attempts.
    UpgradeMaxOutputBatch = 40, -- Bulk-craft up to remaining collection quest need and surplus materials.
    UpgradeVerifySeconds = 6, -- Give bulk crafting and rank quest credit time to replicate.
    UpgradeRejectedUIDCooldown = 130, -- A rejected item stack is not retried immediately.
    UpgradeVisitSeconds = 42,   -- Group upgrade attempts at one machine before returning.
    HidePickupPopups = true,    -- Hide 3D gain billboards, NOT actual reward collection.
    HideLootbagVisuals = true, -- Visuals only; keep collectible IDs alive.
    HideYellowBagFX = false, -- No expensive guessed yellow-object scan; targeted lootbag render roots remain hidden.
    HidePetVisuals = true, -- Only cosmetic pet render objects, NOT pet controllers or inventory.
    VisualRefreshSeconds = 90, -- Visual folders use listeners; rare fallback sweep for new roots.
    DiamondZoneRotation = true, -- Search other OWNED and loaded zones for diamond breakables.
    DiamondZoneDwell = 10,     -- Give real diamond targets a short attack window.
    DiamondStallSeconds = 12, -- Rotate sooner when the quest counter is not growing.
    DiamondProbeSeconds = 3,  -- Delay before evaluating a new zone after streaming.
    DiamondWarmupSeconds = 5, -- Productive normal-breakable window before rotating without diamond progress.
    DiamondWarmupMinActions = 3, -- Issue farming actions before rotating; server may not credit every request.
    DiamondTravelCooldown = 8, -- Minimum between moves; reduces streaming lag without long empty waits.
    DiamondVisitCooldown = 22, -- Avoid revisiting recently scouted empty zones.
    DiamondTargetRefresh = 9, -- Avoid rescanning all loaded zones every few seconds.
    DiamondRoutingVersion = 1, -- Migrate old fast-hopping interval once.
    DiamondScoutVersion = 1, -- New bounded scouting; migrate older 65s dwell once.
    DiamondArrivalVersion = 1, -- Migrate old empty-area scout timings when upgrading to v4.
    DiamondFastVersion = 1, -- Apply a one-time shorter scout profile to inherited v4 defaults.
    LeanProfileVersion = 2, -- Carry forward low-lag improvements to old saved settings.
    TargetStabilityVersion = 1, -- One-time migration from rapid retargeting and extreme pet speed.
    FarmTargetHoldSeconds = 3.0, -- Do not abandon a live normal breakable every fast tick.
    PetTargetMaxAge = 8.0, -- Reissue set-target only when stale instead of commanding all pets every two seconds.
    LootbagFastClaim = true, -- Direct claimable-UID ChildAdded watcher, not a full 3D effects scan.
    LootbagDiagSeconds = 48, -- Diagnostic-only, bounded sampling of unknown visual objects.
    LowLagMode = true, -- Togglable worker pacing for smoother area travel.
    GoldWorkflowVersion = 1, -- Enable golden quest material preparation once, honor subsequent user toggles.
    UpgradeFlowVersion = 1, -- Migrate old slow upgrade interval once.
    DiamondZonesPerPass = 30,  -- Bounded scan, no cross-world teleports.
    MaxUpgradeInputTier = 6,   -- Source-backed upgrade ingredients from Tier I through VI.
    UpgradeTierSelectionVersion = 1, -- Migrate old Tier III default once; preserve future user choice.
    DeferMiniChestQuests = true, -- Prioritize all other actionable quests before mini/superior chests.
    UpgradeMaterialReserve = 8, -- Protect low-tier stacks; separate from original reserve setting.
    AutoVending = false,        -- Opt-in: up to 5% of available coins per purchase
    AutoClaimRankRewards = true,
    AutoRebirth = false,        -- Intentional opt-in only
    AutoEggSlots = false,       -- Opt-in: check available diamonds and verified bundle price
    AutoPetSlots = false,       -- Opt-in: check rank cap and verified diamond price
    AutoEquipBest = true,       -- From DZ Hub PetCmds.EquipBest
    AutoGoldConversion = true, -- A matching GOLD quest may consume regular pets/diamonds; credit-checked.
    AutoRainbowConversion = true, -- Requested: craft rainbow best-egg pets for an active matching quest.
    AutoGoldForRainbow = true, -- Make golden pets as intermediate materials ONLY for an active rainbow quest.
    RainbowGoldBatchMax = 10,
    RainbowMaxOutputBatch = 10, -- After first credited rainbow, allow up to ten outputs per request. -- At most 10 gold crafts per request before inventory verification.
    ConversionPetReserve = 10, -- Protect ten regular pets in each species stack.
    RainbowWorkflowVersion = 1, -- Migrate older config once; thereafter user settings are preserved.
    AutoRankMilestones = true, -- Read real star requirements and world/rebirth blocks; do not invent rank-up remotes.
    StarPriorityWeight = 12, -- Extra score for each extra star granted by a quest (1-4 verified from Goals.Stars).
    AutoFreeGifts = false,      -- Opt-in: verified free-gift timestamps, no blind claiming
    AutoLoginStreak = false,    -- DZ Hub source: LoginStreakCmds.CanClaim and Login Streaks: Claim
    AutoTimedRewards = false,   -- DZ Hub source: TimedRewards directory and DailyRewards_Redeem
    AutoPlayerUpgrades = false, -- DZ Hub source: UpgradeCmds.All/CanInteractWith/Purchase
    PlayerUpgradeSpendFraction = 0.15, -- Never spend >15% of one currency balance on a purchase
    Fullbright = false,        -- Reversible Lighting settings
    AutoPopBalloons = false,    -- DZ Hub source: 3-rebirth slingshot, active balloon registry
    BalloonSmall = true,
    BalloonMedium = true,
    BalloonHuge = true,
    HideBalloonVisuals = false, -- cosmetic only, never destroy server-linked models
    HideBreakableVisuals = false, -- cosmetic only, preserve model UIDs and descendants
    LocalNotifications = true, -- in-hub events only; no webhooks, outbound HTTP or uploads
    LoginCheckSeconds = 75,
    TimedCheckSeconds = 80,
    BalloonCheckSeconds = 3,
    BalloonHitCooldown = 1.5,
    RenderOff = false,
    FastFarm = true,              -- Separate fast farm tick independent from 1.2s quest planner.
    FarmTapRate = 7,              -- Fast but bounded; low-lag mode caps inherited 16 TPS settings.
    SpreadPets = false,          -- Keep pets on stable targets rather than scattering weak attacks.
    PetTurbo = true,             -- Client movement only; cannot multiply server damage.
    InfinitePetSpeed = true,    -- VY: CalculateSpeedMultiplier returns EXACTLY math.huge (unstable on some clients).
    VYPersistentPetBulk = true, -- VY: stable per-pet Breakables_JoinPetBulk assignments; fallback to DZ targeting.
    VYMultiTargetSpread = true, -- VY-style pet distribution across several normal breakables, optional.
    VYInstantEvents = true,     -- VY: react to qualifying breakable ChildAdded when a matching rank quest is active.
    VYBulkSeconds = 1.0,       -- Rate-limit bulk pet commands to avoid CPU/network flooding.
    VYWorldTravel = false,     -- Opt in: world switch only if a saved local source can re-execute.
    VYLocalWorkspaceFile = "RankPilot_X_v5_1_Feature_Expansion.lua", -- Save this file under this name in executor workspace.
    VYWorldTravelCooldown = 90,

    PetSpeedMultiplier = 8,      -- Modest CLIENT movement; extreme 250x causes excess physics/render churn.
    SuperMagnet = true,          -- DZ OrbCmds.Orb properties, when present.
    AutoCollectOrbs = true,      -- Claim loaded orb IDs through observed network action.
    AutoCollectLootbags = true,  -- Claim loaded bag IDs, do NOT destroy objects locally.
    CollectionBatch = 35,
    CollectionSeconds = 1.8, -- Batch drop IDs efficiently; monitor real bag UID folder.
    FarmRadius = 220,
    MaxCandidatesPerPass = 48,
    ScanLimit = 75,
    MaxPetsPerTick = 55,
    TickSeconds = 1.8,
    QuestCooldown = 12,
    SaveRefreshSeconds = 1.8,
    WorldCheckSeconds = 18,
    RewardCheckSeconds = 3, -- Prompt shows cumulative reward thresholds; request one reward per bounded cooldown.
    FarmActionSeconds = 0.45,
    PetAssignSeconds = 2.6,
    EquipCheckSeconds = 18,
    SlotCheckSeconds = 28,
    GiftCheckSeconds = 65,
    HatchActionSeconds = 0.75,
    ConsumableSeconds = 0.7, -- One safe potion fallback per interval if batching fails.
    PotionBatchUse = true,    -- Probe a quantity of 2, then use batches only after actual quest credit.
    PotionMaxBatch = 8,
    PotionBatchVersion = 1,
    SpawnItemSeconds = 5, -- Bounded queue: one jar/comet until its spawned target or quest result is checked.
    StallSeconds = 150,
    FarmQuestStallSeconds = 45, -- Detect slow farm quests independently of other quest progress.
    FarmQuestRetrySeconds = 55, -- Temporarily switch to an easier supported quest.
    AdaptiveFarmPriority = true,
    BlockedQuestSeconds = 75,
    MaxErrorsPerFeature = 5,
    MaxHatchBatch = 256, -- Uses the live EggCmds cap, never purchases more than allowed
    TargetRank = 0,             -- 0 = no artificial stopping point; game cap may change
    PreferHighStars = true,
    RepositionDistance = 35,
    MaxSlotSpendFraction = 0.40, -- cap a purchase to 40% of current diamonds
}
local state: any = {
    running = false, shutdown = false, status = "Preparing", rank = "?",
    extras = {
        loginLast="not checked", loginClaims=0, loginNext=0,
        timedLast="not checked", timedClaims=0, timedNext=0,
        playerUpgradeLast="not checked", playerUpgradeConfirmed=0, playerUpgradeNext=0,
        lightOriginal=nil,
        balloonLast="not checked", balloonHits=0, balloonNext=0,
        balloonSeen={}, slingshot=false, balloonCheckAt=0,
        visuals=setmetatable({}, {__mode="k"}), visualNext=0,
        visualHidden=0, lastRankAlert=nil, alerts={},
        inventoryLast="not checked", capabilityLast="not checked",
    },
    maxRank = "?", area = "?", chosen = "None", starCount = "?",
    goals = {}, logs = {}, tasks = {}, failures = {}, blocked = {}, cooldowns = {},
    questWatch = {},
    clients = {}, lastGoalFingerprint = "", lastRank = nil,
    movementOwner=nil, movementUntil=0, spawnPending={}, spawnActions=0,
    spawnLast="not attempted", spawnObserved={}, spawnNextLog=0,
    eventFocus=nil, eventFocusUntil=0,
    hatchExclusive=false, hatchExclusiveSince=0, hatchExclusiveLast="inactive",
    potionPending=nil, potionBatchVerified=nil, potionBatchLast="not attempted",
    potionBatchedRequests=0, potionFallbackUses=0,
    nextVisualWorkerAt=0,
    upgradePending=nil, upgradeNext=0, upgradeDisabled={}, upgradeCount=0,
    upgradeLast="not attempted", collectionCredits=0, upgradeValidated={},
    upgradeLastOutputBatch=0, upgradeLastCreditMethod="none",
    machineStatus="not checked", machineNextTravel=0, machineTravelCount=0,
    popupRecords=setmetatable({}, {__mode="k"}), popupHidden=0,
    popupLastScan=0, popupBound=false, popupPending=setmetatable({}, {__mode="k"}),
    popupLastStatus="not checked", popupInspected=0,
    lootbagVisuals=setmetatable({}, {__mode="k"}), lootbagHidden=0,
    lootbagYellowHidden=0, lootbagYellowScanned=0, lootbagYellowLast="not scanned",
    lootbagSourceCount=0, lootbagScannedObjects=0,
    lootbagParticleSourceCount=0, lootbagParticleHidden=0,
    lootbagBoundFolder=nil, lootbagVisualScannedAt=0, lootbagVisualLast="not scanned",
    petVisuals=setmetatable({}, {__mode="k"}), petHidden=0,
    petVisualBoundFolders=setmetatable({}, {__mode="k"}), petVisualScannedAt=0,
    petVisualLast="not scanned", petVisualCount=0,
    diamondZone=nil, diamondZoneSince=0, diamondScannedAt=0,
    diamondCandidateZones={}, diamondRotateIndex=0, diamondMoveCount=0,
    diamondLastStatus="not checked", diamondLastQuest=nil,
    diamondCandidateCount=0, diamondLastCredit=0, diamondLastCreditedAt=0,
    diamondTargetsByZone={}, diamondLastTargetAudit=0,
    diamondChosenTargetCount=0, diamondTravelGraceUntil=0,
    diamondDryZoneVisits=0, diamondDryDeferrals=0, diamondLastDefer="none",
    diamondVisits={}, diamondAreaAudit={}, diamondScoutCount=0,
    diamondScoutLast="not started", diamondScoutAt=0,
    diamondWarmupActions=0, diamondWarmupDiamonds=0,
    diamondLastTravelAt=-math.huge, diamondPendingLoadUntil=0,
    diamondLastNormalFarm="not attempted",
    farmFieldMethod="not checked", farmFieldLast="not checked",
    farmFieldValidated=false, farmFieldRetries=0,
    bestAreaTravelAt=-math.huge, bestAreaNativeAt=-math.huge,
    bestAreaTarget=nil, bestAreaTravelStatus="not requested",
    bestAreaAnchorMoves=0, bestAreaNativeRequests=0, bestAreaLoadPending=0,
    diamondArrivalAttempts=0, diamondArrivalFailures=0,
    farmSwitchCount=0, farmSwitchLast="none",
    upgradeTierLast="none", upgradeSelectionLast="not checked",
    upgradeRejectedUIDs={}, upgradeRejectedCount=0,
    upgradeReturnCFrame=nil, upgradeVisitStart=0, upgradeVisitCompleted=0,
    deferredChestCount=0, chestDeferralActive=false, chestDeferralReason="not evaluated",
    lastProgressAt = os.clock(), lastSuccessfulAction = os.clock(),
    lastWorldCheck = 0, lastRewardCheck = 0, lastRefresh = 0,
    world = {number=nil, source="not checked", name="Unknown", zone="?", best="?"},
    worldTransition="not checked", worldChangedAt=0, lastWorldTeleport=0,
    worldMapCount=0, lastSuperMachine=nil, lastSuperMachineScan=-math.huge,
    worldSaveConflict=false,
    lastFarm = 0, lastHatch = 0, lastConsumable = 0, lastEventItem = 0,
    consumableTimes = {}, concurrent = {farm="none",hatch="none",collect="none",passive="none"},
    farmError = "none", modernFarmRetryAt = 0, farmLastRecoveredAt = 0,
    hatchBatch = nil, hatchLastEgg = nil, hatchLastResult = "not attempted",
    hatchRefusals = 0, hatchNoProgress = 0, hatchNeedsCoins = false,
    hatchRetryAt = 0, hatchGoalActive = false, hatchConfirmed = 0,
    hatchObservedTotal = nil, hatchObservedAt = 0,
    hatchQuestIdentity = nil, hatchQuestProgress = nil,
    hatchFarmRemoteSupported=false, hatchFarmRemoteProbe=nil, hatchFarmRemoteBackoff=0,
    hatchFarmRemoteLast="not tested", hatchRemoteLastProbe=0,
    hatchLastConfirmedAt = 0, hatchLastBatchAdjustment = 0,
    hatchLastApi = "none", hatchLastQty = 0, hatchCapacitySource="not checked",
    lastAnimationScan=0, cachedEgg=nil, cachedEggAt=0,
    eggDiscovery="not checked", eggWorldModuleCount=0, eggWorldUnlockedCount=0,
    eggSource="none", eggFallbackStatus="not attempted",
    eggWorldEligibleCount=0, eggEligibleCandidates={},
    eggUnlockRequests=0, eggUnlockLast="not attempted",
    eggUnlockStatus="not checked", eggUnlockNext=0, eggUnlockPending=nil,
    eggUnlockSuccess=0, eggUnlockSource="none",
    eggVerifiedByHatchName=nil, eggVerifiedByHatchWorld=nil,
    goldenLast="not attempted", goldenAttempts=0, goldenCredited=0,
    goldenPending=nil, goldenRetryAt=0, goldenNext=0,
    cachedEggWorld=nil, cachedEggMax=nil,
    eggAnimation = {installed=false, frontend=nil, originalPlay=nil,
        settings=nil, originalGet=nil, workspaceSaved=false, oldInstant=nil},
    lastPetAssign = 0, lastAssignedTarget = nil, lastEquip = 0,
    lastSlots = 0, lastGifts = 0, lastFarmInterface = "none",
    attempts = {farm = 0, hatch = 0, zone = 0, consumable = 0},
    lastPosition = nil, generations = 0, connections = {}, gui = nil,
    configFile = "RankPilot_v2_7_settings.json", settingsLoaded = false,
    activeWorld = nil, currentTarget = nil, selectedGoalKey = nil, scanCursor = 1,
    commandCount = 0, blockedCount = 0,
    farmGoal = nil, lastFarmGoal = nil, farmStats = {dz = 0, cmd = 0, workspace = 0, empty = 0},
    lastCollector = 0, orbClaims = 0, lootClaims = 0, claimSeen = {},
    lootbagUidFolder=nil, lootbagUidBind=nil, lootbagKnownChildren=0,
    lootbagLastClaimStatus="not checked", lootbagRootSample="none", lootbagClaimErrors=0,
    lootbagClaimAttempts=0, lootbagLastVisualSample=0,
    focusTargetUID=nil, focusTargetKey=nil, focusTargetAt=0, focusTargetChanges=0,
    petTargetCommands=0, petTargetSkipped=0, targetDamageRequests=0,
    farmProgressLast={}, farmProgressObserved=0,
    orbModule = nil, originalOrbPickup = nil, originalOrbCollect = nil,
    petSpeedOriginal = nil, petSpeedApplied = false, lastSpeedCheck = 0,
    vySpeedHookOriginal=nil, vySpeedHookInstalled=false, vySpeedStatus="not installed",
    vyPetAssignment={}, vyLastPetBulk=0, vyPetBulkSent=0, vyPetBulkFailed=0,
    vyPetBulkSkipped=0, vyPetBulkLast="not started", vyLastPetZone=nil,
    vyBreakableListenerBound=false, vyBreakableListenerStatus="not bound",
    vyEventBreakables=0, vyEventBulkActions=0, vyEventLast="not started",
    vyWorldTravelLast="not requested", vyWorldTravelAt=-math.huge,
    vyWorldQueued=false, vyWorldAttempted=nil,

    lastTargetScan = 0, scannedTargets = {}, scannedKey = "", scanMode = "",

    cachedSave = nil, cachedSaveAt = -math.huge, hudRank = nil, hudRankAt = -math.huge,
    rankConflict = false, farmZoneOverride = nil, activeGoalTitle = nil,
    rankStage = {status="not checked", starsNeeded=nil, starsLeft=nil, pending={}, requiredZone=nil,
        rebirthsMissing=nil, ready=false, max=false, blocked=false, nextRank=nil, source="none"},
    rankStageLastStatus = "", lastRankCheck = 0, maxRankSource = "none",
    rainbowAttempts=0, rainbowCredited=0, rainbowPending=nil,
    rainbowNext=0, rainbowRetryAt=0, rainbowLast="not attempted",
    rainbowValidated=false, rainbowLastGoalProgress=nil,
    rainbowPrepPending=nil, rainbowPrepNext=0, rainbowPrepRetryAt=0,
    rainbowPrepAttempts=0, rainbowPrepCredited=0, rainbowPrepLast="not attempted",
    rainbowStableIdentityFixes=0, rebirthLast="not checked",
    farmReturnLast=0, farmReturnCount=0, farmReturnLastStatus="not attempted",
    modules = {},
}
-- v5.2 module registry. Feature modules (src/modules/*.lua) register here.
-- It is declared before every lifecycle, report, settings and UI function so
-- they can all reach it; every hook is pcall-guarded so a broken module can
-- never take down the rank engine or the GUI.
local Modules: any = {list = {}, byId = {}}

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
        if feature == "farm" then
            -- Avoid the permanently dead farm shown in the user's recording.
            -- Back off and switch to Workspace/BreakableCmds on the next try.
            record.recoveryCount = (record.recoveryCount or 0) + 1
            record.retryAt = now() + math.min(120, 12 * record.recoveryCount)
            state.modernFarmRetryAt = now() + 40
            state.farmError = describe(err)
            log("Farm cooldown before automatic retry: " .. math.floor(record.retryAt - now())
                .. "s. Original error: " .. state.farmError, "RECOVERY")
        else
            log(feature .. " disabled after repeated errors. Use RECHECK to retry.", "SAFEGUARD")
        end
    end
    state.failures[feature] = record
end
local function healthy(feature)
    local row = state.failures[feature]
    if feature == "farm" and row and row.disabled and now() >= (row.retryAt or math.huge) then
        row.disabled = false
        row.count = 0
        row.last = now()
        state.farmLastRecoveredAt = now()
        if cooldownReady("farm:resume", 12) then
            log("Retrying farm after cooldown; older BreakableCmds/Workspace preferred", "RECOVERY")
        end
    end
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
-- One character can physically be in only one location. Workers share a
-- bounded movement lease so Supercomputer travel does not fight zone farming.
local function movementAvailable(owner)
    return not state.movementOwner or now()>=state.movementUntil
        or state.movementOwner==owner
end
local function leaseMovement(owner, seconds)
    if not movementAvailable(owner) then return false end
    state.movementOwner=owner
    state.movementUntil=now()+seconds
    return true
end
local function clearMovement(owner)
    if state.movementOwner==owner then
        state.movementOwner=nil
        state.movementUntil=0
    end
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
    state.cachedSave = nil
    state.cachedSaveAt = -math.huge
    local lib = findChild(ReplicatedStorage, "Library")
    local clientFolder = findChild(lib, "Client")
    local c: any = (clientFolder and tryModule(clientFolder)) or {}
    if type(c) ~= "table" then c = {} end
    for _,name in ipairs({"Save", "QuestCmds", "ZoneCmds", "RankCmds", "PetCmds", "EggCmds",
        "FruitCmds", "PotionCmds", "ZoneFlagCmds", "InventoryCmds", "RebirthCmds", "LoginStreakCmds", "MachineCmds", "UpgradeCmds",
        "MapCmds", "CurrencyCmds", "MasteryCmds", "PlayerPet", "BreakableFrontend", "BreakableCmds", "OrbCmds", "SettingsCmds"}) do
        if not c[name] then c[name] = tryModule(findChild(clientFolder, name)) end
    end
    c.Network = c.Network or tryModule(findChild(clientFolder, "Network"))
    c.OrbModule = tryModule(findChild(findChild(clientFolder, "OrbCmds"), "Orb"))
    c.ZonesUtil = tryModule(findChild(findChild(lib, "Util"), "ZonesUtil"))
    c.RanksUtil = tryModule(findChild(findChild(lib, "Util"), "RanksUtil"))
    c.Directory = tryModule(findChild(lib, "Directory"))
    c.Balancing = tryModule(findChild(lib, "Balancing"))
    state.clients = c
    state.activeWorld = nil  -- World map is detected dynamically, not pinned to Map1.
    return type(c.Save) == "table" and type(c.Save.Get) == "function"
end
-- Share a single recent snapshot across planner, inventory and reward checks.
-- Each refresh obtains a new snapshot, so this is not a frozen copy of account state.
local function saveData(force)
    if not force and state.cachedSave and now() - state.cachedSaveAt < Config.SaveRefreshSeconds then
        return state.cachedSave
    end
    local ok, data = callMethod(state.clients.Save, "Get")
    if ok and type(data) == "table" then
        state.cachedSave, state.cachedSaveAt = data, now()
        return data
    end
    -- Never keep operating on a stale snapshot when Save.Get fails.
    state.cachedSave, state.cachedSaveAt = nil, -math.huge
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
                -- Old v3.2 configs saved the default Tier III cap. Since this is
                -- a new feature, migrate only legacy settings; subsequent user
                -- choices (including selecting III) remain persistent.
                local legacyTier = key == "MaxUpgradeInputTier"
                    and (tonumber(data.UpgradeTierSelectionVersion) or 0) < 1
                local oldRotation=key=="DiamondZoneDwell"
                    and (tonumber(data.DiamondRoutingVersion) or 0)<1
                    and tonumber(value)==23
                local oldScout=(tonumber(data.DiamondScoutVersion) or 0)<1
                    and ((key=="DiamondZoneDwell" and tonumber(value)==65)
                        or (key=="DiamondStallSeconds" and tonumber(value)==65)
                        or (key=="DiamondTargetRefresh" and tonumber(value)==18))
                local oldUpgrade=key=="UpgradeInterval"
                    and (tonumber(data.UpgradeFlowVersion) or 0)<1
                    and tonumber(value)==9
                if not legacyTier and not oldRotation and not oldScout and not oldUpgrade then Config[key] = value end
            end
        end
        if Config.VYLocalWorkspaceFile == "RankPilot_PS99_VY_v4_6.lua"
            or Config.VYLocalWorkspaceFile == "RankPilot_X_v5_1_Feature_Expansion.lua" then
            Config.VYLocalWorkspaceFile = "RankPilot_X_v5_2.lua"
        end
        -- This update was explicitly requested: older v3.6 preferences did
        -- not contain a rainbow material-preparation pipeline. Enable it ONCE
        -- for this migration, but preserve explicit v3.7+ OFF choices.
        if (tonumber(data.DiamondArrivalVersion) or 0)<1 then
            -- Existing v3.9 saved defaults are too slow and can leave the
            -- character in an empty street for 24 seconds per visit.
            if tonumber(data.DiamondWarmupSeconds)==24 then Config.DiamondWarmupSeconds=12 end
            if tonumber(data.DiamondWarmupMinActions)==12 then Config.DiamondWarmupMinActions=6 end
            if tonumber(data.DiamondTravelCooldown)==22 then Config.DiamondTravelCooldown=15 end
            if tonumber(data.DiamondVisitCooldown)==65 then Config.DiamondVisitCooldown=36 end
            if tonumber(data.DiamondZoneDwell)==24 then Config.DiamondZoneDwell=16 end
            if tonumber(data.DiamondStallSeconds)==30 then Config.DiamondStallSeconds=20 end
            Config.DiamondArrivalVersion=1
        end
        if (tonumber(data.RainbowWorkflowVersion) or 0)<1 then
            Config.AutoRainbowConversion=true
            Config.AutoGoldForRainbow=true
            Config.AutoHatchForRainbow=true
            Config.RainbowWorkflowVersion=1
        end
        if (tonumber(data.DiamondFastVersion) or 0)<1 then
            -- Apply only if values are the previous shipped defaults.
            -- Respect users who customized their timing explicitly.
            local migrated={DiamondZoneDwell={16,10},DiamondStallSeconds={20,12},
                DiamondProbeSeconds={9,3},DiamondWarmupSeconds={12,5},
                DiamondWarmupMinActions={6,3},DiamondTravelCooldown={15,8},
                DiamondVisitCooldown={36,22},DiamondTargetRefresh={16,9}}
            for field,oldNew in pairs(migrated) do
                if tonumber(data[field])==oldNew[1] then Config[field]=oldNew[2] end
            end
            Config.DiamondFastVersion=1
        end
        if (tonumber(data.LeanProfileVersion) or 0)<1 then
            -- Source v4.1 repeatedly traversed pet/loot FX objects, and
            -- some older profiles retained x10000 pet speed. Migrate known
            -- shipped defaults only; users may retune after this update.
            local leanMigrations={
                VisualRefreshSeconds={7,28}, FarmTapRate={8,5},
                CollectionSeconds={1.3,2.4}, CollectionBatch={35,25},
                PetAssignSeconds={0.8,2.0}, MaxPetsPerTick={150,55},
                ScanLimit={130,75}, MaxCandidatesPerPass={70,48},
                TickSeconds={1.2,1.8}, SaveRefreshSeconds={1.5,1.8},
            }
            for field,pair in pairs(leanMigrations) do
                if data[field]~=nil and tonumber(Config[field])==pair[1] then Config[field]=pair[2] end
            end
            if tonumber(Config.PetSpeedMultiplier)>500 then
                Config.PetSpeedMultiplier=250
            end
            -- Old broad yellow-object heuristic never recognized any of the
            -- user's remaining lootbags but scanned thousands of FX objects.
            -- Keep named lootbag suppression ON; disable only the broad pass.
            if data.HideYellowBagFX==true then Config.HideYellowBagFX=false end
            if data.HatchFarmRemoteProbe==true then Config.HatchFarmRemoteProbe=false end
            Config.LeanProfileVersion=1
        end
        if (tonumber(data.LeanProfileVersion) or 0)<2 then
            -- Migrate only previous shipped values; do not overwrite a
            -- user's genuinely customized timings or toggles.
            local v44defaults={
                VisualRefreshSeconds={28,42},
                CollectionSeconds={2.4,3.0},
                CollectionBatch={25,35},
                FarmTapRate={5,7},
                HatchActionSeconds={0.85,0.75},
                ConsumableSeconds={6,0.7},
                SpawnItemSeconds={14,5},
            }
            for field,values in pairs(v44defaults) do
                if data[field]~=nil and tonumber(Config[field])==values[1] then Config[field]=values[2] end
            end
            Config.LeanProfileVersion=2
        end
        if (tonumber(data.TargetStabilityVersion) or 0)<1 then
            -- Prior shipped defaults repeatedly redirected pets and could
            -- create severe client-side speed churn, without extra server DPS.
            if tonumber(Config.PetSpeedMultiplier)==250 or tonumber(Config.PetSpeedMultiplier)==500 then
                Config.PetSpeedMultiplier=8
            end
            -- Keep all 55 equipped pets eligible for assignments; the stable-target throttle cuts repetition.
            if data.PetAssignSeconds~=nil and tonumber(Config.PetAssignSeconds)==2 then Config.PetAssignSeconds=2.6 end
            if data.VisualRefreshSeconds~=nil and tonumber(Config.VisualRefreshSeconds)==42 then Config.VisualRefreshSeconds=90 end
            if data.CollectionSeconds~=nil and tonumber(Config.CollectionSeconds)==3 then Config.CollectionSeconds=1.8 end
            if data.SpreadPets==true then Config.SpreadPets=false end
            Config.TargetStabilityVersion=1
        end
        if (tonumber(data.GoldWorkflowVersion) or 0)<1 then
            Config.AutoGoldConversion=true
            Config.AutoHatchForGold=true
            Config.GoldWorkflowVersion=1
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

-- Source: uploaded RankCmds/GetMaxRank returns the CURRENT rank, not the cap.
-- Only RanksUtil.GetMaximumRank().RankNumber identifies the live maximum rank.
local function getMaxRank()
    local util=state.clients.RanksUtil
    local ok, definition=callMethod(util,"GetMaximumRank")
    if ok and type(definition)=="table" and tonumber(definition.RankNumber) then
        state.maxRankSource="RanksUtil.GetMaximumRank().RankNumber"
        return tonumber(definition.RankNumber)
    end
    local dir=state.clients.Directory
    if dir and type(dir.Ranks)=="table" then
        local maximum=nil
        for _,definition2 in pairs(dir.Ranks) do
            if type(definition2)=="table" then
                local n=tonumber(definition2.RankNumber)
                if n and (not maximum or n>maximum) then maximum=n end
            end
        end
        if maximum then
            state.maxRankSource="Directory.Ranks observed maximum"
            return maximum
        end
    end
    state.maxRankSource="unavailable"
    return nil
end

-- Read game-owned rank data. All Rewards[i].StarsRequired entries are incremental;
-- their CUMULATIVE sum is the milestone (verified in the uploaded Rank UI source).
local function rankDefinition(rank)
    local c=state.clients
    if not (rank and c.RanksUtil and c.Directory and type(c.Directory.Ranks)=="table") then return nil,nil end
    local ok,rankID=callMethod(c.RanksUtil,"RankIDFromNumber",rank)
    if not ok or not rankID then return nil,nil end
    local success,definition=pcall(function() return c.Directory.Ranks[rankID] end)
    if not success or type(definition)~="table" then return nil,nil end
    return rankID,definition
end
local function starValue(goal)
    -- Goal.Stars is the verified game field. Do not infer values from its array index.
    local raw=goal and goal.raw
    local n=raw and tonumber(raw.Stars)
    if not n then return 1 end
    return math.clamp(math.floor(n),1,4)
end
local function readRankStage(data)
    local currentRank=tonumber(data and data.Rank)
    local stars=tonumber(data and data.RankStars)
    local maxRank=getMaxRank()
    local stage={status="Rank data unavailable",starsNeeded=nil,starsLeft=nil,pending={},
        requiredZone=nil,rebirthsMissing=nil,ready=false,max=false,blocked=false,
        nextRank=currentRank and currentRank+1 or nil,source="none"}
    if not currentRank or not stars then return stage end
    if maxRank and currentRank>=maxRank then
        stage.status="MAX RANK ("..currentRank..")";stage.max=true;stage.source=state.maxRankSource
        return stage
    end
    local _,def=rankDefinition(currentRank)
    if not def or type(def.Rewards)~="table" then
        stage.status="No readable rank reward directory; waiting";return stage
    end
    local total=0
    local redeemed=type(data.RedeemedRankRewards)=="table" and data.RedeemedRankRewards or {}
    for i,reward in ipairs(def.Rewards) do
        local increment=type(reward)=="table" and tonumber(reward.StarsRequired)
        if not increment or increment<0 then
            stage.status="Invalid star requirement in rank directory";return stage
        end
        total=total+increment
        if stars>=total and not redeemed[tostring(i)] and not redeemed[i] then
            table.insert(stage.pending,i)
        end
    end
    stage.starsNeeded=total
    stage.starsLeft=math.max(0,total-stars)
    stage.source="RanksUtil.RankIDFromNumber + Directory.Ranks cumulative Rewards"
    -- Prefer direct game predicates when present; fall back to the above math.
    local okReady,serverReady=callMethod(state.clients.RankCmds,"AllRewardsReady")
    stage.ready=okReady and type(serverReady)=="boolean" and serverReady or stars>=total
    if not stage.ready then
        stage.status="Earn "..stage.starsLeft.." more stars to rank up"
        return stage
    end
    local okBlock,zoneBlocked,rebirthBlocked,areaNeeded,rebirthsMissing =
        callMethod(state.clients.RankCmds,"IsRankBlockedByZone")
    if okBlock then
        stage.requiredZone=zoneBlocked and tonumber(areaNeeded) or nil
        stage.rebirthsMissing=rebirthBlocked and tonumber(rebirthsMissing) or nil
        stage.blocked=zoneBlocked==true or rebirthBlocked==true
    end
    if stage.blocked then
        local parts={}
        if stage.requiredZone then table.insert(parts,"Area "..stage.requiredZone) end
        if stage.rebirthsMissing then table.insert(parts,"+"..stage.rebirthsMissing.." rebirth(s)") end
        stage.status="RANK BLOCKED: "..(#parts>0 and table.concat(parts," and ") or "area/rebirth requirement")
    elseif #stage.pending>0 then
        stage.status="STARS READY: claim "..#stage.pending.." rank reward(s)"
    else
        local okRedeemed,allRedeemed=callMethod(state.clients.RankCmds,"AllRewardsRedeemed")
        if okRedeemed and allRedeemed==false then
            stage.status="Stars ready; reward redemption incomplete"
        else
            stage.status="READY: waiting for game-controlled rank advancement"
        end
    end
    return stage
end

-- The current official main progression index has four worlds (1-99,
-- 100-199, 200-239, 240-279). Read live directory world metadata first;
-- these ranges are a diagnostic fallback, not a replacement for game data.
local WORLD_LABELS = {[1]="Coins",[2]="Tech",[3]="Void",[4]="Fantasy"}
local function worldFromArea(area)
    area=tonumber(area)
    if not area then return nil end
    if area>=1 and area<=99 then return 1 end
    if area>=100 and area<=199 then return 2 end
    if area>=200 and area<=239 then return 3 end
    if area>=240 and area<=279 then return 4 end
    return nil -- do not guess for zones added by future updates
end
local function zoneDirectoryInfo(name)
    local dir=state.clients.Directory
    return type(name)=="string" and dir and type(dir.Zones)=="table" and dir.Zones[name] or nil
end
local function zoneWorld(name, details)
    local directory=zoneDirectoryInfo(name)
    local n=type(details)=="table" and tonumber(details.WorldNumber or details.worldNumber)
    if not n and type(directory)=="table" then
        n=tonumber(directory.WorldNumber or directory.worldNumber)
    end
    if n then return n,"Directory/zone metadata" end
    local area=(type(details)=="table" and tonumber(details.ZoneNumber))
        or (type(directory)=="table" and tonumber(directory.ZoneNumber))
    n=worldFromArea(area)
    return n,n and "official area-range fallback" or "unknown zone world"
end
local function mapRoots()
    local roots={}
    for _,node in ipairs(Workspace:GetChildren()) do
        -- Map, Map2, Map3, Map4 and later numbered maps. Do not hardcode 3.
        if node.Name:match("^Map%d*$") then roots[#roots+1]=node end
    end
    table.sort(roots,function(a,b) return a.Name<b.Name end)
    return roots
end
local function getZoneInfo()
    local c=state.clients.ZoneCmds
    local ok,name,details=callMethod(c,"GetMaxOwnedZone")
    if not ok then return nil end
    if type(name)=="table" then
        details=name
        name=name.ZoneName or name.Name or name._id
    end
    if type(name)~="string" or name=="" then return nil end
    local directory=zoneDirectoryInfo(name)
    local number=type(details)=="table" and tonumber(details.ZoneNumber) or nil
    if not number and type(directory)=="table" then number=tonumber(directory.ZoneNumber) end
    local world,worldSource=zoneWorld(name,details)
    return {name=name,number=number,world=world,worldSource=worldSource}
end
local function readWorldContext(data)
    local lastWorld=data and tonumber(data.RecentWorld)
    local activeZone=nil
    local ok,current=callMethod(state.clients.MapCmds,"GetCurrentZone")
    if ok and type(current)=="string" then activeZone=current end
    local currentZoneWorld=activeZone and zoneWorld(activeZone)
    local best=getZoneInfo()
    local world=lastWorld or currentZoneWorld or (best and best.world)
    local source=lastWorld and "Save.RecentWorld" or
        (currentZoneWorld and "MapCmds.GetCurrentZone" or "max-owned zone")
    state.worldSaveConflict=lastWorld~=nil and currentZoneWorld~=nil
        and lastWorld~=currentZoneWorld
    if state.worldSaveConflict then
        -- In a place transition Save.RecentWorld may lag behind the physically
        -- loaded map. Trust the current area ONLY if its folder exists in this
        -- place, never just because its title appears in stale saved state.
        local folderLoaded=false
        for _,map in ipairs(mapRoots()) do
            for _,folder in ipairs(map:GetChildren()) do
                local suffix=folder.Name:match("^%d+%s*|%s*(.*)$")
                if folder.Name==activeZone or suffix==activeZone then
                    folderLoaded=true;break
                end
            end
            if folderLoaded then break end
        end
        if folderLoaded then
            world=currentZoneWorld
            source="loaded current zone (Save.RecentWorld disagrees)"
        end
    end
    local previous=state.world.number
    if previous==nil and world~=nil and state.worldTransition=="not checked" then
        state.worldTransition="Current game place reports World "..tostring(world)
    end
    if previous~=nil and world~=nil and previous~=world then
        state.cachedEgg=nil;state.cachedEggAt=0
        state.hatchFarmRemoteSupported=false;state.hatchFarmRemoteProbe=nil
        state.hatchFarmRemoteBackoff=0;state.hatchRemoteLastProbe=0
        state.hatchFarmRemoteLast="New world: travel-free hatch must be revalidated"
        state.scannedTargets={};state.scannedKey="";state.lastTargetScan=0
        state.farmZoneOverride=nil;state.activeGoalTitle=nil
        state.diamondZone=nil;state.diamondScannedAt=0
        state.diamondCandidateZones={};state.diamondRotateIndex=0
        state.diamondVisits={};state.diamondAreaAudit={};state.diamondScoutCount=0
        state.diamondDryZoneVisits=0;state.rainbowLastGoalProgress=nil
        state.diamondWarmupActions=0;state.diamondPendingLoadUntil=0
        state.machineNextTravel=0;state.lastSuperMachine=nil
        state.lastSuperMachineScan=-math.huge;state.worldChangedAt=now()
        state.worldTransition="World changed: "..tostring(previous).." -> "..tostring(world)
        log(state.worldTransition,"WORLD")
    end
    local roots=mapRoots()
    state.worldMapCount=#roots
    state.activeWorld=(function()
        if world then
            for _,m in ipairs(roots) do
                if m.Name=="Map"..tostring(world) or (world==1 and m.Name=="Map") then return m end
            end
        end
        return roots[1]
    end)()
    state.world={number=world,source=source,name=WORLD_LABELS[world] or "Unknown",
        zone=activeZone or "unknown",best=best and best.name or "unknown",
        bestWorld=best and best.world or nil}
    return state.world
end
local function matchZoneFolder(zone)
    if not zone then return nil end
    local roots=mapRoots()
    if state.activeWorld then
        for i,r in ipairs(roots) do
            if r==state.activeWorld then table.remove(roots,i);break end
        end
        table.insert(roots,1,state.activeWorld)
    end
    for _,root in ipairs(roots) do
        for _,folder in ipairs(root:GetChildren()) do
            local suffix=folder.Name:match("^%d+%s*|%s*(.*)$")
            if suffix==zone.name or folder.Name==zone.name then return folder end
        end
    end
    return nil
end
-- Farming coordinates must point INSIDE the dotted breakable area, not the
-- portal/road or the first arbitrary INTERACT descendant. PS99 auto-rank
-- sources use INTERACT.BREAKABLE_SPAWNS.Main as the actual farm-field anchor.
local function horizontalInside(part,point,margin)
    if not part or not part:IsA("BasePart") then return false end
    local p=part.CFrame:PointToObjectSpace(point)
    return math.abs(p.X) <= math.max(0,part.Size.X/2 + (margin or 0))
       and math.abs(p.Z) <= math.max(0,part.Size.Z/2 + (margin or 0))
end
local function farmingFieldPart(zone)
    local folder=matchZoneFolder(zone)
    local interact=folder and folder:FindFirstChild("INTERACT")
    local spawns=interact and interact:FindFirstChild("BREAKABLE_SPAWNS",true)
    local main=spawns and spawns:FindFirstChild("Main",true)
    if main and main:IsA("BasePart") then return main,"BREAKABLE_SPAWNS.Main" end
    local util=state.clients.ZonesUtil
    local ok,zones=callMethod(util,"GetBreakableZones",zone.name)
    if ok and typeof(zones)=="Instance" then
        if zones:IsA("BasePart") then return zones,"ZonesUtil field" end
        local best,score=nil,-math.huge
        for _,part in ipairs(zones:GetDescendants()) do
            if part:IsA("BasePart") then
                local area=part.Size.X*part.Size.Z
                local rank=area+(part.Name:lower()=="main" and 1e9 or 0)
                if area>=20 and rank>score then best,score=part,rank end
            end
        end
        if best then return best,"ZonesUtil field part" end
    end
    if spawns then
        local fallback=spawns:IsA("BasePart") and spawns
            or spawns:FindFirstChildWhichIsA("BasePart",true)
        if fallback then return fallback,"BREAKABLE_SPAWNS fallback" end
    end
    return nil,"farming field not loaded"
end
local function breakableCentroid(zoneName)
    -- If an old map doesn't expose Main, use REAL breakable positions from
    -- this zone rather than a gate teleport position on the public road.
    local folder=findChild(findChild(Workspace,"__THINGS"),"Breakables")
    if not folder then return nil end
    local sx,sy,sz,count=0,0,0,0
    for _,object in ipairs(folder:GetChildren()) do
        if (object:IsA("Model") or object:IsA("BasePart"))
            and object:GetAttribute("ParentID")==zoneName then
            local part=object:IsA("BasePart") and object
                or object:FindFirstChildWhichIsA("BasePart",true)
            if part then
                sx=sx+part.Position.X; sy=sy+part.Position.Y
                sz=sz+part.Position.Z; count=count+1
                if count>=24 then break end
            end
        end
    end
    if count<2 then return nil end
    return Vector3.new(sx/count,sy/count,sz/count)
end
local function placeInZone(zone)
    if not zone or not zone.name then return false,"unknown owned zone" end
    local active=state.world and state.world.number
    local requested=zone.world or zoneWorld(zone.name)
    if requested and active and requested~=active then
        state.worldTransition="Cannot CFrame from World "..tostring(active)
            .." to World "..tostring(requested).."; use an in-game world portal"
        return false,state.worldTransition
    end
    local root=currentRoot()
    if not root then return false,"character not ready" end
    local field,source=farmingFieldPart(zone)
    local goal,method
    if field then
        local candidate=breakableCentroid(zone.name)
        if candidate and horizontalInside(field,candidate,-2) then
            goal=Vector3.new(candidate.X,field.Position.Y+5,candidate.Z)
            method=source.." + breakable centroid"
        else
            goal=field.Position+Vector3.new(0,5,0)
            method=source
        end
    else
        goal=breakableCentroid(zone.name)
        method="visible breakable centroid"
        if goal then goal=goal+Vector3.new(0,4,0) end
    end
    if not goal then
        -- A remote best-owned area may not be streamed in yet. The old
        -- implementation returned here BEFORE travelling, so that area could
        -- never load and every rank quest requiring it stalled indefinitely.
        state.farmFieldValidated=false
        local best=Config.AutoLoadBestArea and getZoneInfo() or nil
        local isBest=best and best.name==zone.name
        if (Config.AutoLoadBestArea and isBest) or Config.AutoZoneTeleports then
            if state.bestAreaTarget~=zone.name then
                state.bestAreaTarget=zone.name
                state.bestAreaTravelAt=-math.huge
                state.bestAreaNativeAt=-math.huge
                state.bestAreaLoadPending=0
            end
            local t=now()
            -- DZ Hub uses this game-provided zone CFrame. Do not invent map
            -- coordinates or use a stale CFrame from a different world.
            local anchorOK,anchor=callMethod(state.clients.ZonesUtil,
                "GetTeleportPartLocation",zone.name)
            if anchorOK and typeof(anchor)=="CFrame" then
                local goalPoint=anchor.Position+Vector3.new(0,6,0)
                local distance=(root.Position-goalPoint).Magnitude
                if distance>15 and t-(state.bestAreaTravelAt or -math.huge)>=9 then
                    local moved,err=pcall(function() root.CFrame=anchor+Vector3.new(0,6,0) end)
                    if moved then
                        state.bestAreaTravelAt=t
                        state.bestAreaLoadPending=t+3.5
                        state.bestAreaAnchorMoves=(state.bestAreaAnchorMoves or 0)+1
                        state.bestAreaTravelStatus="Moved to game-provided anchor for "..zone.name.."; loading field"
                        state.farmFieldLast=state.bestAreaTravelStatus
                        return false,state.farmFieldLast
                    else
                        state.bestAreaTravelStatus="Zone anchor movement failed: "..tostring(err)
                    end
                end
            end
            -- If the zone still has no field after an anchor move, the game's
            -- normal current-world teleport is a second source-backed route.
            -- Rate-limit it and never call it across Roblox world places.
            if t>=(state.bestAreaLoadPending or 0)
                and t-(state.bestAreaNativeAt or -math.huge)>=24 then
                local ownsOK,owns=callMethod(state.clients.ZoneCmds,"Owns",zone.name)
                if (ownsOK and owns==true) or (isBest and best.world==active) then
                    -- GetMaxOwnedZone itself is authoritative ownership evidence.
                    state.bestAreaNativeAt=t
                    local sent,response=network("Teleports_RequestTeleport",{zone.name},true)
                    state.bestAreaNativeRequests=(state.bestAreaNativeRequests or 0)+1
                    if sent and response~=false then
                        state.bestAreaLoadPending=t+5
                        state.bestAreaTravelStatus="Game teleport accepted for "..zone.name.."; streaming field"
                    else
                        state.bestAreaTravelStatus="Game teleport not confirmed for "..zone.name
                            ..": "..tostring(response)
                    end
                else
                    state.bestAreaTravelStatus="Waiting for field and owned-zone verification: "..zone.name
                end
            end
            state.farmFieldLast=state.bestAreaTravelStatus
            return false,state.farmFieldLast
        end
        state.farmFieldLast="No breakable-spawn field/centroid for "..zone.name
        return false,state.farmFieldLast
    end
    local closeEnough=field and horizontalInside(field,root.Position,-3)
        or ((root.Position-goal).Magnitude<=16)
    if not closeEnough then
        -- One CFrame move per deliberate arrival, never every fast-farm tick.
        root.CFrame=CFrame.new(goal)
    end
    local arrived=field and horizontalInside(field,root.Position,1.5)
        or (root.Position-goal).Magnitude<=18
    state.farmFieldMethod=method
    state.farmFieldValidated=arrived==true
    state.farmFieldLast=(arrived and "Inside " or "Not inside ")..zone.name
        .." via "..method
    if arrived and state.bestAreaTarget==zone.name then
        state.bestAreaTravelStatus="Verified farming field after travel: "..zone.name
        state.bestAreaLoadPending=0
    end
    if not arrived then
        state.farmFieldRetries=(state.farmFieldRetries or 0)+1
        return false,state.farmFieldLast
    end
    return true,state.farmFieldLast
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
    -- The game's MakeTitle includes remaining counts (e.g. 14 rainbow pets -> 13).
    -- A title-based key changes on every credit and caused the pending rainbow
    -- craft to appear uncredited. Prefer the server's stable quest UID; when a
    -- client does not expose one, combine slot + raw quest type, never title.
    local stableType = entry.UID or entry.Type or entry.TypeAsString or entry.QuestType or kind
    result.uid = entry.UID
    result.signature = tostring(key) .. ":" .. title .. ":" .. tostring(progress)
    result.identity = tostring(key) .. ":" .. tostring(stableType)
    return result
end
local function readGoals(data)
    local result = {}
    if type(data.Goals) == "table" then
        for key, value in pairs(data.Goals) do
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
    local candidates = {}
    local function inspectStack(uid, row)
        if type(row) ~= "table" then return end
        -- Both layouts are evidenced in the researched PS99 sources:
        -- Save.Inventory[section][uid]={id,tn,_am} and
        -- InventoryCmds.State().container._store._byType[section]._byUID.
        local item=type(row._data)=="table" and row._data or row
        local itemId=item.id or item.ID
        if type(itemId)~="string" or itemId=="" then return end
        local level=tonumber(item.tn)
        local quantity=tonumber(item._am or row._am or item.Amount or row.Amount) or 1
        if quantity<=0 then return end
        if identifier and not itemId:lower():find(identifier:lower(),1,true) then return end
        if tier and level~=tier then return end
        candidates[#candidates+1]={uid=uid,id=itemId,tier=level or 0,amount=quantity}
    end
    if type(stock)=="table" then
        for uid,row in pairs(stock) do inspectStack(uid,row) end
    end
    if #candidates==0 then
        local ok,inventoryState=callMethod(state.clients.InventoryCmds,"State")
        if ok and type(inventoryState)=="table" then
            local container=inventoryState.container
            local store=container and container._store
            local byType=store and store._byType
            local byUID=byType and byType[section] and byType[section]._byUID
            if type(byUID)=="table" then
                for uid,row in pairs(byUID) do inspectStack(uid,row) end
            end
        end
    end
    table.sort(candidates, function(a,b)
        if a.tier~=b.tier then return a.tier<b.tier end
        return tostring(a.uid)<tostring(b.uid)
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

-- USE potion quests often specify a named potion (e.g. "Damage Potion IV").
-- Matching only the tier could accidentally consume unrelated potions and
-- never credit the rank quest. Resolve the named potion from actual inventory
-- IDs; do not invent a list of names or consume an unrelated exact-tier stack.
local function potionForUseGoal(goal,tier,snapshot)
    local inventory=snapshot and snapshot.Inventory and snapshot.Inventory.Potion
    local title=type(goal.title)=="string" and goal.title:lower() or ""
    local longest=nil
    if type(inventory)=="table" then
        for _,row in pairs(inventory) do
            local item=type(row)=="table" and (row._data or row) or nil
            local id=item and item.id
            if type(id)=="string" and id~="" and title:find(id:lower(),1,true)
                and (not longest or #id>#longest) then
                longest=id
            end
        end
    end
    -- The title might only say "Use Tier IV Potions", in which case
    -- any matching tier is valid and the fallback is appropriate.
    return getInventoryEntry("Potion",longest,tier),longest
end

-- HUD candidate is advisory. Only accept an unambiguous visible player's rank
-- label. Other GUI elements may have rank text, so never use this for remotes.
local function readHudRank()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local unique, number = {}, nil
    for _, label in ipairs(gui:GetDescendants()) do
        if (label:IsA("TextLabel") or label:IsA("TextButton")) and label.Visible then
            local text = label.Text
            if type(text) == "string" then
                local rank = tonumber(text:match("^%s*Rank%s+(%d+)%s*%-%s*"))
                if rank then unique[rank] = true; number = rank end
            end
        end
    end
    for rank in pairs(unique) do
        if rank ~= number then return nil end
    end
    return number
end

local function inspectState()
    local data = saveData()
    if not data then
        state.status = "Save.Get unavailable: no automation"
        return false
    end
    local rank = tonumber(data.Rank)
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
    state.starCount = data.RankStars or "?"
    if now() - state.hudRankAt > 12 then
        state.hudRankAt = now()
        state.hudRank = readHudRank()
    end
    local conflict = type(state.rank) == "number" and type(state.hudRank) == "number"
        and state.hudRank ~= state.rank
    if conflict and not state.rankConflict then
        log(("Rank mismatch: Save.Get().Rank=%d, visible HUD candidate=%d; stop to verify live data")
            :format(state.rank, state.hudRank), "DIAGNOSTIC")
    end
    state.rankConflict = conflict
    -- Verified uploaded source: RankCmds.GetMaxRank is the CURRENT rank.
    -- The real cap is RanksUtil.GetMaximumRank().RankNumber.
    local maximum = getMaxRank()
    state.maxRank = maximum or "unknown"
    if Config.AutoRankMilestones then
        local stage=readRankStage(data)
        state.rankStage=stage
        if stage.status~=state.rankStageLastStatus then
            if state.rankStageLastStatus~="" then log(stage.status,"RANK") end
            state.rankStageLastStatus=stage.status
        end
    else
        state.rankStage={status="Rank milestone tracking disabled",ready=false,pending={},blocked=false}
    end
    local context=readWorldContext(data)
    local zone=getZoneInfo()
    local areaZone=zone
    if zone and zone.world and context.number and zone.world~=context.number then
        -- A stale max-owned-zone API must never drive the player across places.
        local localZone=context.zone
        local localDir=zoneDirectoryInfo(localZone)
        if type(localDir)=="table" then
            areaZone={name=localZone,number=tonumber(localDir.ZoneNumber),world=context.number}
        else
            areaZone=nil
        end
        state.worldTransition="Max-owned zone belongs to World "..tostring(zone.world)
            .." while this place is World "..tostring(context.number)..". World transition needed."
    end
    state.area=areaZone and (tostring(areaZone.number or "?") .. " | " .. areaZone.name) or "world area unresolved"
    state.goals = readGoals(data)
    if not state.running and #state.goals > 0 and state.chosen == "None" then
        state.chosen = tostring(#state.goals) .. " rank quests detected; press START"
    end
    -- Per-quest watchdog: only progress on THIS quest resets its timer.
    -- Other quests changing cannot conceal a stalled selected quest.
    local visible = {}
    for _, g in ipairs(state.goals) do
        visible[g.identity] = true
        local old = state.questWatch[g.identity]
        if old and g.progress>old.progress
            and (g.kind=="farm" or g.kind=="diamond" or g.kind=="minichest"
                or g.kind=="safe" or g.kind=="coinjar" or g.kind=="comet") then
            state.farmProgressObserved=(state.farmProgressObserved or 0)+(g.progress-old.progress)
            state.farmProgressRecentAt=now()
        end
        if not old or old.progress ~= g.progress then
            state.questWatch[g.identity] = {progress=g.progress, changedAt=now()}
        end
    end
    for id in pairs(state.questWatch) do
        if not visible[id] then state.questWatch[id] = nil end
    end
    -- Progress changes are normal every second; only log a true goal
    -- replacement/arrival/departure. The prior signature included Progress.
    local fragments = {}
    for _, g in ipairs(state.goals) do table.insert(fragments, g.identity) end
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
    local feature = ({farm="farm", diamond="farm", minichest="farm", safe="farm",
        hatch="hatch", fruit="fruit", potion="potion", flag="flag",
        zone="zone", rebirth="zone",
        coinjar="spawn-coinjar", comet="spawn-comet",
        pinata="spawn-pinata", luckyblock="spawn-luckyblock"})[goal.kind]
    if Config.AutoFarm and (goal.kind=="coinjar" or goal.kind=="comet"
        or goal.kind=="pinata" or goal.kind=="luckyblock") then
        feature="farm" -- spawning still requires AutoEventItems separately
    end
    if feature and not healthy(feature) then return false end
    local needed = {
        hatch = Config.AutoHatch, farm = Config.AutoFarm, diamond = Config.AutoFarm,
        collect_potion = Config.AutoFarm or Config.AutoCollectLootbags or Config.AutoVending,
        collect_enchant = Config.AutoFarm or Config.AutoCollectLootbags or Config.AutoVending,
        minichest = Config.AutoFarm, safe = Config.AutoFarm,
        fruit = Config.AutoConsumables, potion = Config.AutoConsumables,
        flag = Config.AutoConsumables, zone = Config.AutoWorld,
        -- Farming an already spawned event object does not spend an item.
        -- AutoEventItems remains opt-in for actually spawning a coin jar/comet.
        coinjar = Config.AutoFarm or Config.AutoEventItems,
        comet = Config.AutoFarm or Config.AutoEventItems,
        pinata = Config.AutoFarm or Config.AutoEventItems,
        luckyblock = Config.AutoFarm or Config.AutoEventItems,
        rebirth = Config.AutoRebirth,
        upgrade_potion = Config.AutoUpgradeCollections,
        upgrade_enchant = Config.AutoUpgradeCollections,
    }
    return needed[goal.kind] == true
end
-- One physical farm lane, an independent hatch lane, a no-movement
-- consumables lane and a drop-collection lane. Compatible quests advance
-- together; only movement is time-sliced when both destinations differ.
local farmKinds = {farm=true,diamond=true,minichest=true,safe=true,
    coinjar=true,comet=true,pinata=true,luckyblock=true}
local function farmPriority(g)
    local score=scores[g.kind] or -100
    if Config.PreferHighStars then
        score=score+(starValue(g)-1)*(tonumber(Config.StarPriorityWeight) or 12)
    end
    local name=g.title:lower()
    if name:find("best area",1,true) then score=score+12 end
    if name:find("superior",1,true) then score=score-32 end
    if g.required>0 then
        local remain=math.max(1,g.required-g.progress)
        score=score+math.min(36,90/(1+math.log(remain)))
        -- Finishing a short, nearly completed quest beats sitting on a
        -- rare chest spawn for hours. Evaluate remaining amount, not title.
        if g.kind=="farm" and name:find("best area",1,true)
            and remain<=math.max(40,math.floor(g.required*0.07)) then
            score=score+125
        end
    end
    return score
end
-- Mini-chests and superior mini-chests often take longer to appear than
-- hatching, collection and ordinary-breakable goals. Defer BOTH chest
-- variants while another supported, enabled quest is available. General
-- farming still runs in the background for drops and currencies.
local function isMiniChestGoal(goal)
    if not goal then return false end
    if goal.kind == "minichest" then return true end
    local title = type(goal.title) == "string" and goal.title:lower() or ""
    return title:find("chest",1,true) ~= nil
        and (title:find("mini",1,true) ~= nil or title:find("superior",1,true) ~= nil)
end
local function hasAnotherSupportedQuest()
    if not Config.DeferMiniChestQuests then return false end
    local found = false
    for _,goal in ipairs(state.goals) do
        if not isMiniChestGoal(goal) then
            if eligible(goal) then found = true;break end
            -- A temporarily blocked ordinary best-area farm quest must not
            -- cause the planner to abandon it for a scarce 4-star mini-chest
            -- simply because its destination is still streaming in.
            if goal.kind=="farm" and Config.AutoFarm and healthy("farm")
                and goal.title:lower():find("best area",1,true) then
                found=true;break
            end
            -- Conversions have a separate optional worker, not eligible().
            if goal.kind == "convert" and type(goal.title) == "string" then
                local lower=goal.title:lower()
                if (Config.AutoGoldConversion and lower:find("gold",1,true))
                    or (Config.AutoRainbowConversion and lower:find("rainbow",1,true)
                        and now()>=(state.rainbowRetryAt or 0)) then
                    found=true;break
                end
            end
        end
    end
    return found
end
local function refreshChestDeferral()
    local defer = hasAnotherSupportedQuest()
    local count = 0
    for _,goal in ipairs(state.goals) do
        if isMiniChestGoal(goal) then count=count+1 end
    end
    state.deferredChestCount = defer and count or 0
    state.chestDeferralActive = defer and count>0
    state.chestDeferralReason = state.chestDeferralActive
        and (tostring(count).." mini/superior chest quest(s) waiting for other quests")
        or (count>0 and "Other actionable quests finished; chest quests allowed" or "No chest quests")
    return defer
end
local function chooseFarmGoal()
    if not Config.AutoFarm or not healthy("farm") then return nil end
    if state.rankStage and state.rankStage.ready then return nil end
    if state.eventFocus and now()<state.eventFocusUntil then
        for _,g in ipairs(state.goals) do
            if g.identity==state.eventFocus and eligible(g) then return g end
        end
    end
    local deferChests = refreshChestDeferral()
    local best,bestScore=nil,-math.huge
    for _,g in ipairs(state.goals) do
        if farmKinds[g.kind] and eligible(g)
            and not (deferChests and isMiniChestGoal(g)) then
            local score=farmPriority(g)
            if score>bestScore then best,bestScore=g,score end
        end
    end
    return best
end
local function activeCollectGoal()
    if state.rankStage and state.rankStage.ready then return nil end
    local best,bestScore=nil,-math.huge
    for _,g in ipairs(state.goals) do
        if (g.kind=="collect_potion" or g.kind=="collect_enchant") and eligible(g) then
            local progress=g.required>0 and g.progress/g.required or 0
            local score=(Config.PreferHighStars and (starValue(g)-1)*12 or 0)+progress*8
            if score>bestScore then best,bestScore=g,score end
        end
    end
    return best
end
local function inHatchMovementWindow()
    -- Hatch-first is a protected session, not a repeating 12/34s ping-pong.
    -- Allow farming if and ONLY if the active hatch cannot afford even one egg.
    if Config.HatchFirstMode then
        return state.hatchExclusive and not state.hatchNeedsCoins
    end
    -- Legacy bounded sharing remains available when hatch-first is disabled.
    -- Even if chest deferral leaves no specific farm goal, the background
    -- breakable farmer still moves. Reserve a hatch window in that case too.
    if not (Config.AutoParallelQuests and Config.HatchMovementShare
        and state.hatchGoalActive
        and (state.farmGoal or state.chestDeferralActive)) then return false end
    local period=math.max(20,tonumber(Config.HatchSharePeriod) or 42)
    local duration=math.clamp(tonumber(Config.HatchShareSeconds) or 12,3,period-5)
    -- Prefer farming most of the time. Reserve a small movement window for
    -- egg travel, without launching overlapping character teleports.
    return (now() % period) < duration
end
local function chooseGoal()
    if state.rankStage and state.rankStage.ready then return nil end
    local deferChests = refreshChestDeferral()
    local list = {}
    for _,g in ipairs(state.goals) do
        if eligible(g) and not (deferChests and isMiniChestGoal(g)) then
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
            if Config.PreferHighStars then
                score = score + (starValue(g)-1)*(tonumber(Config.StarPriorityWeight) or 12)
            end
            if g.required > 0 then
                local completion = math.max(0,math.min(1,g.progress/g.required))
                local remaining = math.max(1, g.required-g.progress)
                -- A nearly-finished 2/4 chest quest should beat 0/2400 generic
                -- breakables even though generic farming runs in the background.
                score = score + completion * 35 + 125 / (1 + math.log(remaining))
            end
            -- "Superior" variants need an exact identified target, not any mini-chest.
            -- Such a target may not be discoverable through readable metadata.
            if g.title:lower():find("superior", 1, true) then score = score - 60 end
            table.insert(list, {g = g, score = score})
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.g.key < b.g.key
    end)
    return list[1] and list[1].g or nil
end

local function matchesQuestBreakable(goalKind, b, title)
    if goalKind == "farm" then return true end
    local dirType = b.dir and tostring(b.dir.BreakableType or "") or ""
    local tags = (tostring(b.id or "") .. " " .. dirType .. " "
        .. tostring(b.model and b.model.Name or "") .. " " .. tostring(b.class or "")):lower()
    if b.model and typeof(b.model) == "Instance" then
        local ok, value = pcall(b.model.GetAttribute, b.model, "BreakableID")
        if ok and value ~= nil then tags = tags .. " " .. tostring(value):lower() end
    end
    -- Genuine superior quests must not be credited by ordinary mini chests.
    if type(title) == "string" and title:lower():find("superior", 1, true)
        and not tags:find("superior", 1, true) then return false end
    if goalKind == "diamond" then return tags:find("diamond", 1, true) ~= nil end
    if goalKind == "minichest" then
        -- Open-source PS99 autoRanker handles MINI_CHEST with BreakableID "Chest".
        -- Some versions expose only Class="Chest" and an opaque numeric UID.
        local candidate=(tostring(b.id or "").." "..tostring(b.model and b.model.Name or "").." "..dirType):lower()
        for _,other in ipairs({"coin jar","comet","pinata","piñata","lucky block","balloon"}) do
            if candidate:find(other,1,true) then return false end
        end
        -- A source can expose only an opaque UID and a Chest class.
        return candidate:find("chest",1,true)~=nil or b.class=="Chest"
    end
    if goalKind == "safe" then return tags:find("safe", 1, true) ~= nil end
    if goalKind == "coinjar" then return tags:find("jar", 1, true) ~= nil end
    if goalKind == "comet" then return tags:find("comet", 1, true) ~= nil end
    if goalKind == "pinata" then return tags:find("pinata", 1, true) ~= nil or tags:find("piñata", 1, true) ~= nil end
    if goalKind == "luckyblock" then return tags:find("lucky", 1, true) ~= nil end
    return false
end

local function currentFarmZone()
    if state.farmZoneOverride then
        local targetWorld=zoneWorld(state.farmZoneOverride)
        if not targetWorld or not state.world.number or targetWorld==state.world.number then
            return state.farmZoneOverride
        end
        state.farmZoneOverride=nil
    end
    local ok,name=callMethod(state.clients.MapCmds,"GetCurrentZone")
    if ok and type(name)=="string" then
        local world=zoneWorld(name)
        if not world or not state.world.number or world==state.world.number then return name end
    end
    local owned=getZoneInfo()
    if owned and (not owned.world or not state.world.number or owned.world==state.world.number) then
        return owned.name
    end
    return nil
end

-- DZ source: BreakableFrontend.AllByZoneAndClass, b.uid, b.model,
-- b.position, b.health, b.dir, b.disableDamage, Pet:SetTarget.
-- This is preferable to guessing breakable IDs from Workspace model names.
local function partPosition(model)
    if not model or typeof(model) ~= "Instance" then return nil end
    if model:IsA("BasePart") then return model.Position end
    -- Workspace.__THINGS.Breakables also contains Highlight and other
    -- non-geometry instances. Never invoke Model.GetPivot on those.
    if not model:IsA("Model") then return nil end
    local ok,pivot = pcall(function() return model:GetPivot() end)
    if ok and typeof(pivot) == "CFrame" then return pivot.Position end
    local part=model:FindFirstChildWhichIsA("BasePart",true)
    return part and part.Position or nil
end
local function getBreakables()
    local things = findChild(Workspace, "__THINGS")
    return findChild(things, "Breakables")
end
-- For a generic diamond-breakable quest the game can credit owned zones
-- outside the best area. Only inspect folders actually loaded in this place.
-- Never invent zone numbers/coordinates or cross-world CFrame destinations.
local function diamondAreas(force)
    if not force and now()-state.diamondScannedAt<35 then
        return state.diamondCandidateZones
    end
    state.diamondScannedAt=now()
    local list, seen={},{ }
    local world=state.world and state.world.number
    for _,map in ipairs(mapRoots()) do
        if not world or map.Name==(world==1 and "Map" or "Map"..tostring(world))
            or map==state.activeWorld then
            for _,folder in ipairs(map:GetChildren()) do
                local prefix,name=folder.Name:match("^(%d+)%s*|%s*(.+)$")
                if name and prefix and not seen[name] then
                    local info=zoneDirectoryInfo(name)
                    local areaWorld=zoneWorld(name,info)
                    if not areaWorld or not world or areaWorld==world then
                        local known,owns=callMethod(state.clients.ZoneCmds,"Owns",name)
                        if known and owns==true then
                            seen[name]=true
                            list[#list+1]={name=name,number=tonumber(prefix),world=world}
                        end
                    end
                end
            end
        end
    end
    table.sort(list,function(a,b) return (a.number or 0)<(b.number or 0) end)
    -- Limit candidate-size and keep a fallback pool in recently loaded areas.
    local cap=math.max(2,tonumber(Config.DiamondZonesPerPass) or 30)
    if #list>cap then
        local stride=math.max(1,math.floor(#list/cap))
        local sampled={}
        for i=1,#list,stride do
            sampled[#sampled+1]=list[i]
            if #sampled>=cap then break end
        end
        list=sampled
    end
    state.diamondCandidateZones=list
    state.diamondCandidateCount=#list
    return list
end
-- Inspect diamond targets BEFORE teleporting. Use only data the client has loaded:
-- Workspace BreakableID/ParentID, then DZ/BreakableCmds.AllByZoneAndClass.
-- A guessed area cannot be scored; it should not trigger blind fast hopping.
local function diamondLoadedTargetCounts(force)
    if not force and now()-(state.diamondLastTargetAudit or 0)<(Config.DiamondTargetRefresh or 18) then
        return state.diamondTargetsByZone
    end
    state.diamondLastTargetAudit=now()
    local zones=diamondAreas(false)
    local counts={}
    for _,z in ipairs(zones) do counts[z.name]=0 end
    local folder=findChild(findChild(Workspace,"__THINGS"),"Breakables")
    if folder then
        for _,model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") or model:IsA("BasePart") then
                local zone=model:GetAttribute("ParentID")
                local id=model:GetAttribute("BreakableID")
                if type(zone)=="string" and counts[zone]~=nil
                    and type(id)=="string" and id:lower():find("diamond",1,true) then
                    counts[zone]=counts[zone]+1
                end
            end
        end
    end
    -- Search the actual client breakable records when Workspace did not show
    -- any diamond target in that area. Bounded and memoized, not per frame.
    local module=state.clients.BreakableCmds or state.clients.BreakableFrontend
    if type(module)=="table" and type(module.AllByZoneAndClass)=="function" then
        for _,zone in ipairs(zones) do
            if counts[zone.name]==0 then
                for _,class in ipairs({"Normal","Chest"}) do
                    local ok,records=callMethod(module,"AllByZoneAndClass",zone.name,class)
                    if ok and type(records)=="table" then
                        for _,b in pairs(records) do
                            local id=""
                            if typeof(b)=="Instance" then
                                id=tostring(b:GetAttribute("BreakableID") or "")
                            elseif type(b)=="table" then
                                id=tostring(b.id or (b.dir and b.dir._id) or "")
                                if b.model and typeof(b.model)=="Instance" then
                                    id=id.." "..tostring(b.model:GetAttribute("BreakableID") or "")
                                end
                            end
                            if id:lower():find("diamond",1,true) then
                                counts[zone.name]=counts[zone.name]+1
                            end
                        end
                    end
                end
            end
        end
    end
    state.diamondTargetsByZone=counts
    return counts
end
local function nextDiamondArea()
    state.diamondVisits=state.diamondVisits or {}
    local areas=diamondAreas(false)
    if #areas<2 then
        state.diamondLastStatus="Need at least 2 owned, loaded zone folders"
        return nil
    end
    local counts=diamondLoadedTargetCounts(false)
    local previous=state.diamondZone or (state.world and state.world.zone)
    local previousNumber=tonumber((zoneDirectoryInfo(previous) or {}).ZoneNumber) or 0
    local timestamp=now()
    local revisit=math.max(12,tonumber(Config.DiamondVisitCooldown) or 65)
    local chosen,scoreBest=nil,-math.huge
    -- Explicit scouting is necessary: unvisited areas often have zero
    -- breakables streamed in until the character enters that area's box.
    -- Candidate locations are REAL owned and loaded zones, never guessed.
    for _,zone in ipairs(areas) do
        if zone.name~=previous then
            local last=state.diamondVisits[zone.name] or -math.huge
            local age=timestamp-last
            if age>=revisit then
                local count=counts[zone.name] or 0
                local travel=math.abs((zone.number or 0)-previousNumber)
                local signal=count>0 and (160+math.min(30,count)*8) or 0
                local score=signal-math.min(travel,90)*6.5
                    + math.min(30,age/15) + ((zone.number or 0)%5)*0.01
                if score>scoreBest then chosen,scoreBest=zone,score end
            end
        end
    end
    if not chosen then
        -- All zones on cooldown. An active quest should still revisit the
        -- least-recently-visited OWNED zone once it can make progress again.
        local oldest=math.huge
        for _,zone in ipairs(areas) do
            if zone.name~=previous then
                local visited=state.diamondVisits[zone.name] or -math.huge
                if visited<oldest then chosen,oldest=zone,visited end
            end
        end
    end
    if chosen then
        state.diamondChosenTargetCount=counts[chosen.name] or 0
        state.diamondScoutLast="Scouting owned area "..chosen.name
            .." ("..state.diamondChosenTargetCount.." preloaded diamond targets)"
        return chosen
    end
    state.diamondLastStatus="No alternate owned area available"
    return nil
end

-- BOTH APIs have been observed in public source:
-- DZ: BreakableFrontend returns Lua records with .uid/.model/.dir.
-- Griffin autoRanker: BreakableCmds returns model instances with BreakableID/ParentID.
local function dzBreakables(kind)
    local zone = currentFarmZone()
    if not zone or not currentRoot() then return {}, "zone not loaded" end
    local root = currentRoot()
    local accepted, seen = {}, {}
    local checked = false
    local source = nil
    for _, spec in ipairs({
        {module = state.clients.BreakableFrontend, name = "DZ BreakableFrontend"},
        {module = state.clients.BreakableCmds, name = "BreakableCmds"},
    }) do
        local module = spec.module
        if spec.name == "DZ BreakableFrontend" and now() < (state.modernFarmRetryAt or 0) then
            module = nil
        end
        if type(module)=="table" and type(module.AllByZoneAndClass)=="function" then
            for _,class in ipairs({"Chest", "Normal"}) do
                local ok, group = callMethod(module,"AllByZoneAndClass",zone,class)
                if ok and type(group)=="table" then
                    checked = true
                    for _,entry in pairs(group) do
                        local model,uid,id,meta,pos,skip
                        if typeof(entry)=="Instance" and (entry:IsA("Model") or entry:IsA("BasePart")) then
                            model=entry; uid=entry.Name
                            local gotID,pid=pcall(entry.GetAttribute,entry,"BreakableID")
                            id=gotID and pid or entry.Name
                            local gotZone,z=pcall(entry.GetAttribute,entry,"ParentID")
                            if gotZone and type(z)=="string" and z~="" and z~=zone then skip=true end
                            meta={id=id,model=model,class=class}
                            pos=partPosition(model)
                        elseif type(entry)=="table" then
                            model=entry.model
                            uid=entry.uid or (model and model.Name)
                            id=entry.id or (model and model.Name)
                            meta={id=id,model=model,dir=entry.dir,class=class}
                            pos=entry.position
                            if typeof(pos)~="Vector3" then pos=partPosition(model) end
                            if (type(entry.health)=="number" and entry.health <= 0)
                                or entry.disableDamage or (entry.dir and entry.dir.NoTapping) then skip=true end
                        end
                        if type(id)=="string" and id:lower():find("vip",1,true) then skip=true end
                        if not skip and uid~=nil and pos and not seen[tostring(uid)]
                            and matchesQuestBreakable(kind,meta,state.activeGoalTitle)
                            and (pos-root.Position).Magnitude<=Config.FarmRadius then
                            local vip=false
                            if model and typeof(model)=="Instance" then
                                local vok,value=pcall(model.GetAttribute,model,"VIPBreakable")
                                vip=vok and value==true
                            end
                            if not vip then
                                seen[tostring(uid)]=true
                                accepted[#accepted+1]={uid=uid,id=id,model=model,
                                    distance=(pos-root.Position).Magnitude,dz=true,class=class,
                                    from=spec.name}
                            end
                        end
                    end
                end
            end
            if #accepted>0 then source=spec.name;break end
        end
    end
    if #accepted>0 then
        table.sort(accepted,function(a,b) return a.distance<b.distance end)
        while #accepted>Config.MaxCandidatesPerPass do table.remove(accepted) end
        return accepted,source
    end
    -- Even when a modern API exists, it can return no matches for a newly loaded
    -- world; fall back to the Workspace attributes instead of standing idle.
    return nil,checked and "modern empty" or "modern unavailable"
end
local function legacyBreakables(kind)
    local root=currentRoot()
    local group=getBreakables()
    if not root or not group then return {} end
    local list,candidates={},group:GetChildren()
    local count=#candidates
    if count==0 then return list end
    local limit=math.min(count,Config.ScanLimit)
    local zone=currentFarmZone()
    for i=1,limit do
        local index=((state.scanCursor+i-2)%count)+1
        local obj=candidates[index]
        local geometry=obj and (obj:IsA("Model") or obj:IsA("BasePart"))
        local pos=geometry and partPosition(obj) or nil
        if geometry and pos then
            local okZone,actualZone=pcall(obj.GetAttribute,obj,"ParentID")
            local belongs=not okZone or actualZone==nil or actualZone==zone
            local okID,breakableID=pcall(obj.GetAttribute,obj,"BreakableID")
            local okType,t=pcall(obj.GetAttribute,obj,"BreakableType")
            local vipOK,vip=pcall(obj.GetAttribute,obj,"VIPBreakable")
            local b={id=okID and breakableID or obj.Name,model=obj,
                dir={BreakableType=okType and t or ""}}
            local distance=(pos-root.Position).Magnitude
            if belongs and not (vipOK and vip==true) and distance<=Config.FarmRadius
                and matchesQuestBreakable(kind,b,state.activeGoalTitle) then
                list[#list+1]={uid=obj.Name,id=b.id,model=obj,distance=distance,dz=false,
                    from="Workspace attributes"}
            end
        end
    end
    state.scanCursor=((state.scanCursor+limit-1)%count)+1
    table.sort(list,function(a,b) return a.distance<b.distance end)
    return list
end
local function visibleTargetCandidates(kind)
    local nowStamp=now()
    local key=tostring(kind).."/"..tostring(currentFarmZone()).."/"..tostring(state.activeGoalTitle)
    if state.scannedKey==key and nowStamp-state.lastTargetScan<1.3 then
        return state.scannedTargets
    end
    local worked,modern,reason=pcall(dzBreakables,kind)
    if not worked then
        state.farmError = tostring(modern)
        state.modernFarmRetryAt=now()+45
        if cooldownReady("farm:adapter-error",30) then
            log("DZ/BreakableCmds discovery error: " .. state.farmError
                .. "; trying Workspace targets", "RECOVERY")
        end
        modern,reason=nil,"modern adapter failed"
    end
    local targets,source
    if modern and #modern>0 then
        targets,source=modern,reason
        state.farmStats.dz=state.farmStats.dz+1
    else
        local oldOk, oldTargets=pcall(legacyBreakables,kind)
        targets=oldOk and oldTargets or {}
        if not oldOk then
            state.farmError=tostring(oldTargets)
            if cooldownReady("farm:workspace-error",30) then
                log("Workspace discovery error: " .. state.farmError, "RECOVERY")
            end
        end
        source=#targets>0 and "Workspace attributes" or tostring(reason or "empty")
        state.farmStats.workspace=state.farmStats.workspace+1
    end
    state.lastFarmInterface=source
    state.scannedTargets=targets
    state.scannedKey=key
    state.lastTargetScan=nowStamp
    return targets
end

-- Client-side movement speed. Restores the original when paused or unloaded.
-- InfinitePetSpeed returns EXACTLY math.huge (VY behaviour, user request);
-- PetSpeedMultiplier (1-20x) is the finite fallback used when it is OFF.
local function petTurbo(enable)
    local module=state.clients.PlayerPet
    if type(module)~="table" or type(module.CalculateSpeedMultiplier)~="function" then return false end
    if enable and Config.PetTurbo then
        if not state.petSpeedOriginal then
            state.petSpeedOriginal=module.CalculateSpeedMultiplier
        end
        local original=state.petSpeedOriginal
        -- VY's specific behavior: EXACT math.huge, not a 10,000x approximation.
        -- The hook covers clients holding a cached function reference. Its closure
        -- returns the original when paused/stopped, even if an executor cannot unhook.
        if Config.InfinitePetSpeed and not state.vySpeedHookInstalled
            and type(hookfunction)=="function" then
            local previous=nil
            local ok,ret=pcall(function()
                return hookfunction(original,function(...)
                    if not state.shutdown and state.running
                        and Config.PetTurbo and Config.InfinitePetSpeed then
                        return math.huge
                    end
                    if type(previous)=="function" then return previous(...) end
                    return 1
                end)
            end)
            if ok and type(ret)=="function" then
                previous=ret
                state.vySpeedHookOriginal=ret
                state.vySpeedHookInstalled=true
                state.vySpeedStatus="VY hookfunction installed; exact math.huge enabled"
            else
                state.vySpeedStatus="hook unavailable; module-level exact math.huge fallback"
            end
        end
        local ok=pcall(function()
            module.CalculateSpeedMultiplier=function(...)
                if not state.shutdown and state.running and Config.InfinitePetSpeed then
                    return math.huge
                end
                local value=1
                local good,normal=pcall(original,...)
                if good and type(normal)=="number" and normal==normal then value=normal end
                return math.max(value,math.clamp(tonumber(Config.PetSpeedMultiplier) or 8,1,20))
            end
        end)
        if Config.InfinitePetSpeed and not state.vySpeedHookInstalled then
            state.vySpeedStatus="VY module function replaced with exact math.huge"
        end
        state.petSpeedApplied=ok
        return ok
    end
    if state.petSpeedOriginal then
        pcall(function() module.CalculateSpeedMultiplier=state.petSpeedOriginal end)
        state.petSpeedOriginal=nil
    end
    state.petSpeedApplied=false
    return true
end
local function updateSuperMagnet(enable)
    local orb=state.clients.OrbModule
    if type(orb)~="table" then return false end
    if enable and Config.SuperMagnet then
        if state.originalOrbPickup==nil then state.originalOrbPickup=orb.DefaultPickupDistance end
        if state.originalOrbCollect==nil then state.originalOrbCollect=orb.CollectDistance end
        return pcall(function()
            orb.DefaultPickupDistance=1500
            orb.CollectDistance=1500
        end)
    end
    pcall(function()
        if state.originalOrbPickup~=nil then orb.DefaultPickupDistance=state.originalOrbPickup end
        if state.originalOrbCollect~=nil then orb.CollectDistance=state.originalOrbCollect end
    end)
    state.originalOrbPickup=nil;state.originalOrbCollect=nil
    return true
end
local function collectDrops()
    if now()-state.lastCollector<Config.CollectionSeconds then return end
    state.lastCollector=now()
    if now()>=(state.claimSeenPruneAt or 0) then
        state.claimSeenPruneAt=now()+60
        for token,untilAt in pairs(state.claimSeen) do
            if untilAt<now() then state.claimSeen[token]=nil end
        end
    end
    local folder=findChild(Workspace,"__THINGS")
    if not folder then return end
    local lists={
        {enabled=Config.AutoCollectOrbs,name="Orbs",remote="Orbs: Collect",type="number"},
        {enabled=Config.AutoCollectLootbags,name="Lootbags",remote="Lootbags_Claim",type="string"},
    }
    for _,entry in ipairs(lists) do
        if entry.enabled then
            local objects=findChild(folder,entry.name)
            if objects then
                local collected,names,ids=0,{},{}
                for _,obj in ipairs(objects:GetChildren()) do
                    local name=obj.Name
                    local token=entry.name.."/"..name
                    if now()>=(state.claimSeen[token] or 0) then
                        if entry.type=="number" then
                            local id=tonumber(name)
                            if id then ids[#ids+1]=id;names[#names+1]=token end
                        else
                            ids[#ids+1]=name;names[#names+1]=token
                        end
                        collected=collected+1
                        if collected>=Config.CollectionBatch then break end
                    end
                end
                if collected>0 then
                    local ok,result=network(entry.remote,{ids},false)
                    if entry.name=="Lootbags" then
                        state.lootbagClaimAttempts=state.lootbagClaimAttempts+1
                        state.lootbagLastClaimStatus=ok and result~=false
                            and ("Submitted "..collected.." lootbag IDs; credit not yet verified")
                            or ("Claim request failed: "..describe(result))
                        if not ok or result==false then
                            state.lootbagClaimErrors=state.lootbagClaimErrors+1
                        end
                    end
                    if ok and result~=false then
                        for _,token in ipairs(names) do state.claimSeen[token]=now()+4 end
                        if entry.name=="Orbs" then state.orbClaims=state.orbClaims+collected
                        else state.lootClaims=state.lootClaims+collected end
                        -- Never destroy the local objects. A sent claim is NOT
                        -- confirmation that the server awarded anything.
                    elseif cooldownReady("claim:"..entry.name,45) then
                        log(entry.remote.." not available: "..describe(result),"WAIT")
                    end
                end
            end
        end
    end
end

-- Observe claimable lootbag IDs through the game-owned folder. We deliberately
-- do NOT delete drops, clone graphics, or hide unrelated gold objects.
-- ChildAdded permits collection without repeated full Workspace scans.
local function watchClaimableLootbags()
    local things=findChild(Workspace,"__THINGS")
    local folder=findChild(things,"Lootbags")
    if folder~=state.lootbagUidFolder then
        state.lootbagUidFolder=folder
        if state.lootbagUidBind then
            pcall(function() state.lootbagUidBind:Disconnect() end)
            state.lootbagUidBind=nil
        end
        if folder then
            state.lootbagUidBind=folder.ChildAdded:Connect(function(obj)
                if state.shutdown or not Config.AutoCollectLootbags then return end
                -- Collection occurs at the next bounded collector pass.
                state.lastCollector=0
            end)
            table.insert(state.connections,state.lootbagUidBind)
        end
    end
    state.lootbagKnownChildren=folder and #folder:GetChildren() or 0
    if not folder then
        state.lootbagLastClaimStatus="Workspace.__THINGS.Lootbags not found"
    elseif state.lootbagKnownChildren==0 and state.lootClaims==0 then
        state.lootbagLastClaimStatus="Lootbag UID folder empty; yellow graphics may be a separate renderer"
    end
end

-- Cosmetic only: hide the locally rendered lootbag parts but keep the
-- server-side bag models/UIDs available for Lootbags_Claim.
local function setLootbagVisual(node,hide)
    local records=state.lootbagVisuals
    if hide then
        if records[node]~=nil then return end
        local property,value
        if node:IsA("BasePart") then
            property,value="LocalTransparencyModifier",1
        elseif node:IsA("BillboardGui") or node:IsA("SurfaceGui")
            or node:IsA("ParticleEmitter") or node:IsA("Trail") or node:IsA("Beam") then
            property,value="Enabled",false
        elseif node:IsA("Decal") or node:IsA("Texture") then
            property,value="Transparency",1
        end
        if property then
            local ok,original=pcall(function() return node[property] end)
            if ok then
                records[node]={property,original}
                if node:IsA("BasePart") then
                    local read,alpha=pcall(function() return node.Transparency end)
                    if read then records[node].alpha=alpha end
                end
                pcall(function() node[property]=value end)
                if node:IsA("BasePart") then
                    pcall(function() node.Transparency=1 end)
                end
                state.lootbagHidden=state.lootbagHidden+1
            end
        end
    else
        local original=records[node]
        if original then
            pcall(function() node[original[1]]=original[2] end)
            if original.alpha~=nil then
                pcall(function() node.Transparency=original.alpha end)
            end
            records[node]=nil
        end
    end
end
local function refreshLootbagVisuals(force)
    if not Config.HideLootbagVisuals then return end
    if not force and now()-state.lootbagVisualScannedAt<Config.VisualRefreshSeconds then return end
    state.lootbagVisualScannedAt=now()
    local things=findChild(Workspace,"__THINGS")
    local debris=findChild(Workspace,"__DEBRIS")
    local rendered=findChild(Workspace,"__RENDERED")
    local clientFX=findChild(Workspace,"__CLIENT")
    local sources,seen={},{}
    local function addSource(folder)
        if folder and not seen[folder] then
            seen[folder]=true
            sources[#sources+1]=folder
        end
    end
    -- Visuals may be under a render/FX container even when the claimable
    -- __THINGS.Lootbags folder is empty. Search identifiable bag roots only.
    local roots={}
    for _,root in pairs({things,rendered,clientFX,debris,Workspace}) do
        if root then roots[#roots+1]=root end
    end
    for _,root in ipairs(roots) do
        if root then
            for _,name in ipairs({"Lootbags","LootBags","LootBag","Loot Bags",
                "LootbagDrops","LootBagFX","Lootbag Effects","LootDrops"}) do
                addSource(findChild(root,name))
            end
            -- Direct names may vary in spacing/case; bounded shallow lookup.
            local children=root:GetChildren()
            for i=1,math.min(#children,180) do
                local item=children[i]
                local low=item.Name:lower()
                if low:find("lootbag",1,true) or low:find("loot bag",1,true) then
                    addSource(item)
                end
            end
        end
    end
    -- Inspect single-level FX children only when their names clearly refer
    -- to lootbags. Never disable a general lootbag collection script.
    local scanned=0
    for _,root in pairs({debris,rendered,clientFX}) do
        if root then
            local children=root:GetChildren()
            for i=1,math.min(#children,160) do
                local item=children[i]
                scanned=scanned+1
                local n=item.Name:lower()
                if n:find("lootbag",1,true) or n:find("loot bag",1,true) then
                    addSource(item)
                end
            end
        end
    end
    -- PS99 public optimization source identifies ReplicatedStorage.Assets.Particles
    -- entries Lootbags and LootbagsCurrency. Suppress emitter templates so
    -- newly spawned visual effects inherit disabled emitters, but DO NOT
    -- delete assets or touch claimable item IDs.
    local assets=findChild(ReplicatedStorage,"Assets")
    local particles=findChild(assets,"Particles")
    local fxSources=0
    if particles then
        for _,name in ipairs({"Lootbags","LootbagsCurrency"}) do
            local template=findChild(particles,name)
            if template then
                fxSources=fxSources+1
                addSource(template)
            end
        end
    end
    -- Some PS99 clients render yellow bags as unnamed MeshParts under
    -- transient client FX roots. Hide ONLY small yellow graphical parts from
    -- those roots, not general Workspace breakables or collectible UIDs.
    -- This is optional, local, bounded and fully reversible.
    local yellowScanned,yellowHidden=0,0
    if Config.HideYellowBagFX then
        local fxRoots={}
        if debris then fxRoots[#fxRoots+1]=debris end
        if rendered then fxRoots[#fxRoots+1]=rendered end
        if clientFX then fxRoots[#fxRoots+1]=clientFX end
        for _,fxRoot in ipairs(fxRoots) do
            -- Bounded shallow scan: GetDescendants() on huge debris folders
            -- caused avoidable lag when the user hopped between areas.
            local parents=fxRoot:GetChildren()
            for i=1,math.min(#parents,50) do
                local parent=parents[i]
                local objects={parent}
                if parent:IsA("Model") or parent:IsA("Folder") then
                    local children=parent:GetChildren()
                    for j=1,math.min(#children,6) do
                        objects[#objects+1]=children[j]
                    end
                end
                for _,obj in ipairs(objects) do
                    if obj:IsA("MeshPart") or obj:IsA("Part") then
                        yellowScanned=yellowScanned+1
                        local color,size=obj.Color,obj.Size
                        local name=obj.Name:lower()
                        local named=name:find("bag",1,true) or name:find("loot",1,true)
                        local compact=size.X<=7 and size.Y<=7 and size.Z<=7
                        local yellow=color.R>=0.75 and color.G>=0.55 and color.B<=0.39
                        if compact and (named or yellow) then
                            if not state.lootbagVisuals[obj] then yellowHidden=yellowHidden+1 end
                            pcall(setLootbagVisual,obj,true)
                        end
                    end
                end
            end
        end
    end
    state.lootbagYellowScanned=yellowScanned
    state.lootbagYellowHidden=(state.lootbagYellowHidden or 0)+yellowHidden
    state.lootbagYellowLast="Transient yellow meshes checked "..yellowScanned
        .."; newly concealed "..yellowHidden
    state.lootbagParticleSourceCount=fxSources
    state.lootbagSourceCount=#sources
    state.lootbagScannedObjects=scanned
    for _,folder in ipairs(sources) do
        if not state.lootbagBoundFolders then
            state.lootbagBoundFolders=setmetatable({}, {__mode="k"})
        end
        if not state.lootbagBoundFolders[folder] then
            state.lootbagBoundFolders[folder]=true
            table.insert(state.connections,folder.DescendantAdded:Connect(function(obj)
                if Config.HideLootbagVisuals and not state.shutdown then
                    pcall(setLootbagVisual,obj,true)
                end
            end))
        end
        pcall(setLootbagVisual,folder,true)
        for _,obj in ipairs(folder:GetDescendants()) do
            pcall(setLootbagVisual,obj,true)
        end
    end
    state.lootbagVisualLast=#sources>0
        and ("Scanned "..#sources.." named lootbag render roots; hiding visuals only")
        or "No identifiable lootbag render root detected; object names may differ"
end

local function restoreLootbagVisuals()
    for obj in pairs(state.lootbagVisuals) do
        pcall(setLootbagVisual,obj,false)
    end
    state.lootbagHidden=0
    state.lootbagVisualLast="Original lootbag visuals restored"
end

-- Purely cosmetic. Roblox pet controller records are left intact for
-- PlayerPet:SetTarget; never destroy/unequip pets or tamper with their IDs.
local function setPetVisual(node,hide)
    if not node or typeof(node)~="Instance" then return end
    local records=state.petVisuals
    if hide then
        if records[node]~=nil then return end
        local property,value
        if node:IsA("BasePart") then
            property,value="LocalTransparencyModifier",1
        elseif node:IsA("BillboardGui") or node:IsA("SurfaceGui")
            or node:IsA("ParticleEmitter") or node:IsA("Trail")
            or node:IsA("Beam") or node:IsA("Highlight") then
            property,value="Enabled",false
        elseif node:IsA("Decal") or node:IsA("Texture") then
            property,value="Transparency",1
        end
        if property then
            local ok,original=pcall(function() return node[property] end)
            if ok then
                records[node]={property,original}
                pcall(function() node[property]=value end)
                state.petHidden=state.petHidden+1
            end
        end
    else
        local original=records[node]
        if original then
            pcall(function() node[original[1]]=original[2] end)
            records[node]=nil
        end
    end
end
local function hidePetTree(root)
    if not root or typeof(root)~="Instance" then return end
    pcall(setPetVisual,root,true)
    for _,node in ipairs(root:GetDescendants()) do
        pcall(setPetVisual,node,true)
    end
end
local function refreshPetVisuals(force)
    if not Config.HidePetVisuals then return end
    if not force and now()-state.petVisualScannedAt<Config.VisualRefreshSeconds then return end
    state.petVisualScannedAt=now()
    local count=0
    local pp=state.clients.PlayerPet
    if type(pp)=="table" then
        local ok,pets=callMethod(pp,"GetByPlayer",LocalPlayer)
        if not ok or type(pets)~="table" then
            ok,pets=callMethod(pp,"GetAll")
        end
        if ok and type(pets)=="table" then
            for _,pet in pairs(pets) do
                if count>=120 then break end
                if type(pet)=="table" then
                    local permitted=true
                    if pet.owner~=nil then permitted=pet.owner==LocalPlayer end
                    if permitted then
                        for _,key in ipairs({"model","Model","instance","Instance",
                            "petModel","PetModel","renderModel","RenderModel"}) do
                            local asset=pet[key]
                            if typeof(asset)=="Instance" then
                                hidePetTree(asset);count=count+1;break
                            end
                        end
                    end
                end
            end
        end
    end
    -- The graphical representation may live separately from PlayerPet
    -- records; restrict folder fallback to EXPLICIT pet-render containers.
    local things=findChild(Workspace,"__THINGS")
    local rendered=findChild(Workspace,"__RENDERED")
    local petFolders={}
    local petParents={}
    for _,parent in pairs({things,rendered,Workspace}) do
        if parent then petParents[#petParents+1]=parent end
    end
    for _,parent in ipairs(petParents) do
        if parent then
            for _,name in ipairs({"Pets","ClientPets"}) do
                local folder=findChild(parent,name)
                if folder then petFolders[#petFolders+1]=folder end
            end
        end
    end
    for _,folder in ipairs(petFolders) do
        if folder and typeof(folder)=="Instance" then
            if not state.petVisualBoundFolders[folder] then
                state.petVisualBoundFolders[folder]=true
                table.insert(state.connections,folder.DescendantAdded:Connect(function(obj)
                    if Config.HidePetVisuals and not state.shutdown then
                        pcall(setPetVisual,obj,true)
                    end
                end))
            end
            hidePetTree(folder)
            count=count+1
        end
    end
    state.petVisualCount=count
    state.petVisualLast=count>0 and ("Pet visuals hidden from "..count.." source(s)")
        or "No identifiable pet render models yet; retrying"
end
local function restorePetVisuals()
    for node in pairs(state.petVisuals) do
        pcall(setPetVisual,node,false)
    end
    state.petHidden=0
    state.petVisualLast="Original local pet appearance restored"
end

-- VY v1.0.0 (lines 1191-1356) adapted: each locally owned equipped pet
-- retains a target BreakableUID while that target exists. ONE bulk command
-- replaces repetitive individual SetTarget calls on compatible clients.
-- RankPilot still determines the correct zone/quest and verifies real progress.
local function vyOwnedPetIDs()
    local result={}
    local pp=state.clients.PlayerPet
    if type(pp)~="table" then return result end
    local ok,personal=callMethod(pp,"GetByPlayer",LocalPlayer)
    if ok and type(personal)=="table" then
        for _,pet in pairs(personal) do
            if type(pet)=="table" and pet.euid~=nil then
                result[#result+1]=pet.euid
            end
        end
    end
    if #result==0 and type(pp.BelongsToLocalPlayer)=="function" then
        local got,all=callMethod(pp,"GetAll")
        if got and type(all)=="table" then
            for _,pet in pairs(all) do
                if type(pet)=="table" and pet.euid~=nil then
                    local own,belongs=pcall(pp.BelongsToLocalPlayer,pet)
                    if own and belongs==true then result[#result+1]=pet.euid end
                end
            end
        end
    end
    return result
end

local function vyBulkAssign(targets, kind, immediate)
    if not Config.VYPersistentPetBulk or not state.running or state.shutdown
        or type(targets)~="table" or #targets==0 then return false end
    local timestamp=now()
    local interval=math.max(0.35,tonumber(Config.VYBulkSeconds) or 1)
    if timestamp-(state.vyLastPetBulk or 0)<(immediate and 0.25 or interval) then
        state.vyPetBulkSkipped=state.vyPetBulkSkipped+1
        return "cooldown"
    end
    local petIDs=vyOwnedPetIDs()
    if #petIDs==0 then
        state.vyPetBulkLast="No verified locally owned pet EUIDs; DZ fallback"
        return false
    end
    local zone=currentFarmZone()
    if zone~=state.vyLastPetZone then
        state.vyPetAssignment={}
        state.vyLastPetZone=zone
    end
    local living,free,assigned={}, {}, {}
    for _,t in ipairs(targets) do
        if t.uid~=nil and t.model and (typeof(t.model)~="Instance" or t.model.Parent~=nil) then
            local key=tostring(t.uid)
            if not living[key] then
                living[key]=t.uid
                free[#free+1]=t.uid
            end
        end
    end
    if #free==0 then return false end
    local maxPets=math.max(1,tonumber(Config.MaxPetsPerTick) or 55)
    local livePet={}
    for _,id in ipairs(petIDs) do livePet[tostring(id)]=true end
    for key,old in pairs(state.vyPetAssignment) do
        if not livePet[tostring(key)] or living[tostring(old)]==nil then
            state.vyPetAssignment[key]=nil
        else
            assigned[tostring(old)]=true
        end
    end
    local queue={}
    for _,targetUID in ipairs(free) do
        if not assigned[tostring(targetUID)] then queue[#queue+1]=targetUID end
    end
    local map,n={},0
    local rr=1
    for _,id in ipairs(petIDs) do
        if n>=maxPets then break end
        local key=tostring(id)
        if state.vyPetAssignment[key]==nil then
            local choice
            if immediate then
                choice=free[1]
            elseif #queue>0 then
                choice=table.remove(queue,1)
            else
                choice=free[rr]
                rr=rr%#free+1
            end
            state.vyPetAssignment[key]=choice
        end
        map[id]=state.vyPetAssignment[key]
        n=n+1
    end
    if n==0 then return false end
    local ok,accepted=network("Breakables_JoinPetBulk",{map},false)
    state.vyLastPetBulk=timestamp
    if ok and accepted~=false then
        state.vyPetBulkSent=state.vyPetBulkSent+1
        state.vyPetBulkLast="VY bulk assigned "..tostring(n).." pets to "
            ..tostring(#free).." live target(s), zone="..tostring(zone)
        state.lastPetAssign=timestamp
        return true
    end
    state.vyPetBulkFailed=state.vyPetBulkFailed+1
    state.vyPetBulkLast="VY bulk refused/unavailable: "..tostring(accepted)
    return false
end

local function aimPetsAt(target, targets, kind)
    if not target or not target.model then return false end
    -- On a compatible client VY can assign all pets through one compact command.
    -- If absent/rejected retain the existing tested DZ SetTarget fallback.
    if Config.VYPersistentPetBulk then
        local group=((Config.VYMultiTargetSpread or Config.SpreadPets)
            and kind=="farm" and targets) or {target}
        local bulk=vyBulkAssign(group,kind,false)
        if bulk==true or bulk=="cooldown" then return bulk==true end
    end
    local targetUID=tostring(target.uid)
    local same=state.lastAssignedTarget==targetUID
    local since=now()-state.lastPetAssign
    -- Old code could redirect every equipped pet on consecutive 0.2s ticks
    -- because it only guarded the SAME target, while the farm target changed.
    if since<Config.PetAssignSeconds
        or (same and since<Config.PetTargetMaxAge) then
        state.petTargetSkipped=(state.petTargetSkipped or 0)+1
        return false
    end
    local pp=state.clients.PlayerPet
    local pets
    if type(pp)=="table" then
        local ok,list=callMethod(pp,"GetByPlayer",LocalPlayer)
        if ok and type(list)=="table" then pets=list end
        if not pets then
            local got,all=callMethod(pp,"GetAll")
            if got and type(all)=="table" then
                pets={}
                for _,pet in pairs(all) do
                    local gotOwner,owner=pcall(function() return pet.owner end)
                    if gotOwner and owner==LocalPlayer then pets[#pets+1]=pet end
                end
            end
        end
    end
    local count=0
    local spread=Config.SpreadPets and kind=="farm" and targets and #targets>1
    if type(pets)=="table" then
        for _,pet in pairs(pets) do
            if count>=Config.MaxPetsPerTick then break end
            local model=spread and targets[(count%math.min(#targets,12))+1].model or target.model
            if model then
                local ok=pcall(function()
                    -- DZ Hub uses pet:SetTarget(model) for GetByPlayer records.
                    -- A separate ranker uses SetTargetFromServer for GetAll records.
                    if type(pet.SetTarget)=="function" then
                        pet:SetTarget(model)
                    elseif type(pp.SetTargetFromServer)=="function" then
                        pp.SetTargetFromServer(pet,"Breakable",model)
                    else
                        error("Pet target API unavailable")
                    end
                end)
                if ok then count=count+1 end
            end
        end
    end
    -- Fallback for clients without readable PlayerPet tables.
    if count==0 then
        local ok,equipped=callMethod(state.clients.PetCmds,"GetEquipped")
        if ok and type(equipped)=="table" then
            for petId in pairs(equipped) do
                local a=network("Breakables_JoinPet",{target.uid,petId},false)
                if a then count=count+1 end
                if count>=Config.MaxPetsPerTick then break end
            end
        end
    end
    if count>0 then
        state.lastPetAssign=now()
        state.lastAssignedTarget=targetUID
        state.petTargetCommands=(state.petTargetCommands or 0)+count
        return true
    end
    return false
end

local function damageBreakable(target)
    -- DZ Hub observed UnreliableFire with b.uid; older sources use object.Name.
    local net = state.clients.Network
    if type(net) == "table" and type(net.UnreliableFire) == "function" then
        local ok, result = callMethod(net, "UnreliableFire", "Breakables_PlayerDealDamage", target.uid)
        if ok and result ~= false then return true end
    end
    local ok, result = network("Breakables_PlayerDealDamage", {target.uid}, false)
    return ok and result ~= false
end
-- VY event fast path: only ACTUAL special breakables for a matching live quest.
-- Avoid a full scan for every frame and never override hatch-first travel.
local function vyInstallEventListener()
    local boundFolder=state.vyBreakableFolder
    if state.vyBreakableListenerBound and (boundFolder==nil or boundFolder.Parent~=nil) then return end
    if state.vyBreakableConnection then
        pcall(function() state.vyBreakableConnection:Disconnect() end)
        state.vyBreakableConnection=nil
    end
    local folder=getBreakables()
    if not folder then
        state.vyBreakableListenerStatus="Breakables folder not loaded; deferred"
        return
    end
    local function onAdded(obj)
        if not Config.VYInstantEvents or not Config.VYPersistentPetBulk
            or not state.running or state.shutdown or state.hatchExclusive then return end
        if not obj:IsA("Model") then return end
        task.defer(function()
            if not obj.Parent or not state.running or state.hatchExclusive then return end
            local ok,err=pcall(function()
                local zone=currentFarmZone()
                if not zone then return end
                local parentId=obj:GetAttribute("ParentID")
                if parentId~=nil and tostring(parentId)~=tostring(zone) then
                    return
                end
                local id=tostring(obj:GetAttribute("BreakableID") or obj.Name):lower()
                local class=tostring(obj:GetAttribute("BreakableClass") or ""):lower()
                if class=="normal" then return end
                local relevant=false
                for _,g in ipairs(state.goals or {}) do
                    if eligible(g) and (g.kind=="minichest" or g.kind=="coinjar"
                        or g.kind=="comet" or g.kind=="pinata"
                        or g.kind=="luckyblock") then
                        local tags={id=id,model=obj,class=class,dir={BreakableType=class}}
                        if matchesQuestBreakable(g.kind,tags,g.title) then relevant=true;break end
                    end
                end
                if not relevant then return end
                local uid=obj:GetAttribute("BreakableUID") or obj.Name
                local target={uid=uid,id=id,model=obj}
                state.vyEventBreakables=state.vyEventBreakables+1
                if vyBulkAssign({target},"event",true)==true then
                    state.vyEventBulkActions=state.vyEventBulkActions+1
                    state.vyEventLast="Sent equipped pets to new "..id.." at "..zone
                    state.scannedKey="";state.lastTargetScan=0
                else
                    state.vyEventLast="Event detected; bulk unavailable, regular farm will target: "..id
                end
            end)
            if not ok and cooldownReady("vy:event-error",30) then
                log("VY event listener: "..tostring(err),"RECOVERY")
            end
        end)
    end
    state.vyBreakableConnection=folder.ChildAdded:Connect(onAdded)
    state.connections[#state.connections+1]=state.vyBreakableConnection
    state.vyBreakableFolder=folder
    state.vyBreakableListenerBound=true
    state.vyBreakableListenerStatus="VY ChildAdded event targeting listening"
end

local function farm(goal)
    if not healthy("farm") or not Config.AutoFarm then return false end
    local rate=math.clamp(tonumber(Config.FarmTapRate) or 7,1,
        Config.LowLagMode and 7 or 16)
    local seconds=Config.FastFarm and 1/rate or Config.FarmActionSeconds
    if now()-state.lastFarm<seconds then return false end
    state.lastFarm=now()
    if not currentRoot() or not movementAvailable("farm") then return false end
    if goal and state.blocked and (state.blocked[goal.identity] or 0)>now() then goal=nil end
    local kind=goal and goal.kind or "farm"
    state.activeGoalTitle=goal and goal.title or nil
    state.farmZoneOverride=nil
    local diamondAnywhere = goal and goal.kind=="diamond"
        and not goal.title:lower():find("best area",1,true)
    if not diamondAnywhere then
        state.diamondZone=nil
        state.diamondLastQuest=nil
    elseif state.diamondLastQuest~=goal.identity then
        state.diamondLastQuest=goal.identity
        state.diamondZone=nil
        state.diamondZoneSince=0
        state.diamondLastCreditedAt=now()
        state.diamondLastCredit=goal.progress
        state.diamondLastTargetAudit=0
        state.diamondWarmupActions=0
        state.diamondPendingLoadUntil=0
        diamondAreas(true)
    end
    if diamondAnywhere then
        -- A zone is established once per quest, then changes only when the
        -- routing branch explicitly moves. Calling placeInZone() on every
        -- fast tick caused repeated teleports and client rendering spikes.
        if not state.diamondZone then
            state.diamondZone=currentFarmZone() or (state.world and state.world.zone)
            state.diamondZoneSince=now()
            state.diamondWarmupActions=0
            if state.diamondZone then
                -- Initial scout must also get into the farming field, not
                -- inherit an old roadway position from MapCmds.
                local initial={name=state.diamondZone,world=state.world.number}
                state.diamondArrivalAttempts=state.diamondArrivalAttempts+1
                local good,message=placeInZone(initial)
                if not good then
                    state.diamondArrivalFailures=state.diamondArrivalFailures+1
                    state.diamondLastStatus="Initial field entry unavailable: "..tostring(message)
                else
                    state.diamondLastStatus="Inside initial farm field: "..initial.name
                end
                state.scannedKey="";state.lastTargetScan=0
            end
        end
        if state.diamondZone then
            state.farmZoneOverride=state.diamondZone
        end
    end
    if goal and goal.title:lower():find("best area",1,true) then
        local best=getZoneInfo()
        if not best or not placeInZone(best) then
            if cooldownReady("farm:bestZoneNotLoaded",30) then
                log("Best area still loading: "..goal.title,"WAIT")
            end
            return false
        end
        state.farmZoneOverride=best.name
    end
    -- Only occasionally re-check the player against the actual dotted field.
    -- A UI zone name does not prove that our character entered its spawn box.
    if diamondAnywhere and state.diamondZone
        and now()-(state.diamondLastFieldCheck or -math.huge)>9 then
        state.diamondLastFieldCheck=now()
        local probe={name=state.diamondZone,world=state.world.number}
        local field=farmingFieldPart(probe)
        local root=currentRoot()
        if field and root and not horizontalInside(field,root.Position,0) then
            if movementAvailable("farm") and leaseMovement("farm",2) then
                local ok,arrived=pcall(placeInZone,probe)
                clearMovement("farm")
                state.scannedKey="";state.lastTargetScan=0
                if not ok or not arrived then
                    state.diamondArrivalFailures=state.diamondArrivalFailures+1
                end
            end
        end
    end
    local targets=visibleTargetCandidates(kind)
    if diamondAnywhere then
        if goal.progress>(state.diamondLastCredit or 0) then
            state.diamondDryZoneVisits=0
            state.diamondWarmupDiamonds=state.diamondWarmupDiamonds
                + math.max(0,goal.progress-(state.diamondLastCredit or 0))
            state.diamondLastCredit=goal.progress
            state.diamondLastCreditedAt=now()
        end
        local elapsed=now()-(state.diamondZoneSince or now())
        local sinceCredit=now()-(state.diamondLastCreditedAt or now())
        local dry=#targets==0
        local warmup=math.max(4,tonumber(Config.DiamondWarmupSeconds) or 5)
        local farmedEnough=state.diamondWarmupActions>=(tonumber(Config.DiamondWarmupMinActions) or 12)
        -- Work ordinary breakables first. The server may roll diamond
        -- breakables as destroyed objects respawn; that is not guaranteed.
        local stalledDry=dry and elapsed>=warmup and
            (farmedEnough or elapsed>=warmup+2)
        local stalledDiamonds=not dry and elapsed>=math.max(warmup,Config.DiamondZoneDwell)
            and sinceCredit>=math.max(9,tonumber(Config.DiamondStallSeconds) or 12)
        local due=stalledDry or stalledDiamonds
        local cooled=now()-(state.diamondLastTravelAt or -math.huge)
            >=math.max(8,tonumber(Config.DiamondTravelCooldown) or 8)
        if Config.DiamondZoneRotation and due and cooled
            and now()>=(state.diamondTravelGraceUntil or 0)
            and now()>=(state.diamondPendingLoadUntil or 0) then
            local chosen=nextDiamondArea()
            if chosen and leaseMovement("farm",4) then
                state.diamondArrivalAttempts=state.diamondArrivalAttempts+1
                local ok,moved,reason=pcall(placeInZone,chosen)
                clearMovement("farm")
                if ok and moved then
                    if state.diamondZone and state.diamondZone~=chosen.name then
                        state.diamondVisits[state.diamondZone]=now()
                    end
                    state.diamondZone=chosen.name
                    state.farmZoneOverride=chosen.name
                    state.diamondVisits[chosen.name]=now()
                    state.diamondZoneSince=now()
                    state.diamondLastTravelAt=now()
                    state.diamondTravelGraceUntil=now()+1.5
                    state.diamondPendingLoadUntil=now()+1.8
                    -- A scout move is not quest progress. Preserve the last
                    -- REAL diamond credit timestamp so repeated dry visits
                    -- eventually yield to an easier quest.
                    state.diamondWarmupActions=0
                    state.diamondMoveCount=state.diamondMoveCount+1
                    state.diamondScoutCount=state.diamondScoutCount+1
                    if dry and sinceCredit>20 then
                        state.diamondDryZoneVisits=(state.diamondDryZoneVisits or 0)+1
                    end
                    if (state.diamondDryZoneVisits or 0)>=3 then
                        local alternatives=false
                        for _,taskGoal in ipairs(state.goals or {}) do
                            if taskGoal.identity~=goal.identity and taskGoal.kind=="farm"
                                and eligible(taskGoal) then alternatives=true;break end
                        end
                        if alternatives then
                            state.blocked[goal.identity]=now()+24
                            state.diamondDryDeferrals=(state.diamondDryDeferrals or 0)+1
                            state.diamondLastDefer="Dry diamond route after 3 scout visits; normal best-area quest for 24s"
                            state.diamondDryZoneVisits=0
                        end
                    end
                    state.diamondLastStatus="Arrived at "..chosen.name
                        .."; breaking ordinary objects before next scout"
                    state.scannedKey="";state.lastTargetScan=0
                    state.diamondLastTargetAudit=0
                    return false
                else
                    state.diamondArrivalFailures=state.diamondArrivalFailures+1
                    state.diamondVisits[chosen.name]=now()
                    state.diamondScoutLast="Farm-field arrival failed "..chosen.name..": "
                        ..tostring(reason or moved)
                    state.diamondTravelGraceUntil=now()+5
                end
            end
        elseif not dry then
            state.diamondLastStatus="Attacking diamonds in "..tostring(currentFarmZone())
                .." ("..tostring(#targets).." loaded, "
                ..tostring(math.floor(sinceCredit)).."s since credit)"
        else
            state.diamondLastStatus="Farming ordinary breakables in "..tostring(currentFarmZone())
                .." ("..tostring(state.diamondWarmupActions).." farm actions; "
                ..tostring(math.floor(elapsed)).."s visit)"
        end
    end
    if #targets==0 and kind~="farm" then
        -- Do not stall the whole controller waiting for rare chests.
        -- Continue collecting regular breakables while a rare target spawns.
        -- Does not pretend a normal breakable credits the chest quest.
        local prevTitle=state.activeGoalTitle
        state.activeGoalTitle=nil
        targets=visibleTargetCandidates("farm")
        state.activeGoalTitle=prevTitle
        if cooldownReady("noTargets:"..kind,40) then
            log("No "..kind.." targets in "..(diamondAnywhere and "current scouted area" or "best area").."; farming ordinary breakables while waiting", "WAIT")
        end
        if #targets>0 then kind="farm" end
    end
    if #targets==0 then
        -- Critical: after the last egg-hatch quest completes, the character
        -- may still be standing at an egg capsule. An empty scanner in that
        -- location must not prevent returning to the actual farming zone.
        if not diamondAnywhere and now()-(state.farmReturnLast or 0)>=22
            and movementAvailable("farm") and not inHatchMovementWindow() then
            local best=getZoneInfo()
            if best and (not best.world or best.world==state.world.number) then
                state.farmReturnLast=now()
                if leaseMovement("farm",3) then
                    local ok,moved,reason=pcall(placeInZone,best)
                    clearMovement("farm")
                    if ok and moved then
                        state.farmReturnCount=state.farmReturnCount+1
                        state.farmReturnLastStatus="Returned to "..best.name.." after empty farm scan"
                        state.scannedKey="";state.lastTargetScan=0
                        state.diamondLastTargetAudit=0
                        if cooldownReady("farm:returned",25) then
                            log(state.farmReturnLastStatus,"RECOVERY")
                        end
                    else
                        state.farmReturnLastStatus="Farm return deferred: "..tostring(reason or moved)
                    end
                end
            end
        end
        if cooldownReady("noBreakables",40) then
            log("No loaded targets; verify zone and BreakableID; interface="..state.lastFarmInterface,"WAIT")
        end
        state.farmStats.empty=state.farmStats.empty+1
        return false
    end
    local target=targets[1]
    if kind=="farm" and #targets>1 then
        -- Keep pets and player attacks on the SAME breakable until it dies
        -- or a short bounded timeout. Rotate only at those boundaries.
        local focusKey=tostring(currentFarmZone()).."/"..tostring(kind)
        local previousUID=state.focusTargetKey==focusKey and state.focusTargetUID or nil
        local age=now()-(state.focusTargetAt or 0)
        local hold=math.max(1.5,tonumber(Config.FarmTargetHoldSeconds) or 3)
        if previousUID and age<hold then
            for _,candidate in ipairs(targets) do
                if tostring(candidate.uid)==previousUID then
                    local model=candidate.model
                    if not model or typeof(model)~="Instance" or model.Parent~=nil then
                        target=candidate
                        break
                    end
                end
            end
        else
            -- Choose a different real breakable after the hold window.
            local rotate=((state.focusTargetChanges or 0)%math.min(#targets,8))+1
            target=targets[rotate]
        end
        if tostring(target.uid)~=previousUID or state.focusTargetKey~=focusKey then
            state.focusTargetChanges=(state.focusTargetChanges or 0)+1
            state.focusTargetAt=now()
        end
        state.focusTargetUID=tostring(target.uid)
        state.focusTargetKey=focusKey
    else
        state.focusTargetUID=tostring(target.uid)
        state.focusTargetKey=tostring(currentFarmZone()).."/"..tostring(kind)
        state.focusTargetAt=now()
    end
    aimPetsAt(target,targets,kind)
    local ok=damageBreakable(target)
    if ok then state.targetDamageRequests=(state.targetDamageRequests or 0)+1 end
    state.currentTarget=tostring(target.uid)
    if not ok then
        if cooldownReady("noDamageAPI",35) then
            failFeature("farm","No compatible damage interface for "..state.lastFarmInterface)
        end
        return false
    end
    state.attempts.farm=state.attempts.farm+1
    if diamondAnywhere and kind=="farm" then
        state.diamondWarmupActions=state.diamondWarmupActions+1
        state.diamondLastNormalFarm="Normal breakable attack issued in "
            ..tostring(state.diamondZone).."; requests do not guarantee kills"
    end
    state.lastSuccessfulAction=now()
    return true
end

-- Public-source egg lifecycle:
--   MaximumAvailableEgg = highest accessible egg number, NOT proof it was purchased.
--   PurchasedEggs is the current documented PS99 purchase/unlock map.
--   Eggs_RequestUnlock(egg.name) appears in independent open PS99 auto-rankers.
-- Treat a missing UnlockedEggs list as unknown, not a reason to discard all eggs.
local function eggUnlockEvidence(egg, data)
    if not egg or type(egg.name)~="string" then return false,"invalid egg" end
    if state.eggVerifiedByHatchName==egg.name
        and state.eggVerifiedByHatchWorld==((state.world and state.world.number) or egg.world) then
        return true,"verified by live hatch credit"
    end
    local number=tonumber(egg.number)
    local purchased=data and data.PurchasedEggs
    if type(purchased)=="table" then
        for _,key in ipairs({egg.name, tostring(number or ""), number or -1}) do
            local value=purchased[key]
            if value==true or (type(value)=="table" and (value.Purchased==true or value.Unlocked==true)) then
                return true,"Save.PurchasedEggs"
            end
        end
    end
    local unlocked=data and data.UnlockedEggs
    if type(unlocked)=="table" then
        if unlocked[number]==true or unlocked[tostring(number)]==true
            or unlocked[egg.name]==true then
            return true,"Save.UnlockedEggs map"
        end
        for _,value in pairs(unlocked) do
            if value==number or value==egg.name then
                return true,"Save.UnlockedEggs list"
            end
        end
    end
    local called,answer=callMethod(state.clients.EggCmds,"IsUnlocked",egg.name)
    if called and answer==true then return true,"EggCmds.IsUnlocked" end
    -- Missing/false ownership is not a reason to omit an eligible egg.
    return false, type(purchased)=="table" and "Save.PurchasedEggs not confirmed" or "unlock unknown"
end

-- A maximum egg number is an access ceiling. Build candidates independently
-- of purchases, then request the actual server unlock for the best candidate.
local function worldEggRecords(world, data)
    local list,count,ownedCount= {},0,0
    local folder=findChild(findChild(findChild(ReplicatedStorage,"__DIRECTORY"),"Eggs"),"Zone Eggs")
    folder=findChild(folder,"World "..tostring(world))
    if not folder then
        state.eggDiscovery="Zone Eggs / World "..tostring(world).." folder missing"
        state.eggWorldModuleCount,state.eggWorldUnlockedCount,state.eggWorldEligibleCount=0,0,0
        state.eggEligibleCandidates={}
        return list
    end
    local accessLimit=data and tonumber(data.MaximumAvailableEgg)
    for _,module in ipairs(folder:GetDescendants()) do
        if module:IsA("ModuleScript") then
            count=count+1
            local ok,record=pcall(require,module)
            if ok and type(record)=="table" then
                local number=tonumber(record.eggNumber or record.EggNumber)
                local name=record.name or record._id or record.id
                if number and type(name)=="string" and name~=""
                    and accessLimit and number<=accessLimit then
                    local egg={number=number,name=name,world=world,
                        pets=record.pets,zoneNumber=tonumber(record.zoneNumber),
                        source="__DIRECTORY Zone Eggs / World "..tostring(world)}
                    local owned=eggUnlockEvidence(egg,data)
                    egg.purchased=owned
                    if owned then ownedCount=ownedCount+1 end
                    list[#list+1]=egg
                end
            end
        end
    end
    table.sort(list,function(a,b)return a.number>b.number end)
    state.eggWorldModuleCount,state.eggWorldUnlockedCount,state.eggWorldEligibleCount=count,ownedCount,#list
    state.eggEligibleCandidates=list
    state.eggDiscovery="World "..tostring(world).." modules="..count
        ..", eligible="..#list..", purchased/unlocked="..ownedCount
    return list
end

-- DZ Hub approach: select the best unlocked zone egg from the account's
-- current-world egg directory. A reachable capsule is advisory, not required.
local function findEgg()
    local dir=state.clients.Directory
    local data=saveData()
    local best=nil
    local currentWorld=(state.world and state.world.number) or (data and tonumber(data.RecentWorld))
    local currentMax=data and tonumber(data.MaximumAvailableEgg)
    local directory=dir and dir.Eggs
    if state.cachedEgg and now()-state.cachedEggAt<10
        and state.cachedEggWorld==currentWorld and state.cachedEggMax==currentMax then
        return state.cachedEgg
    end
    local function remember(egg)
        state.cachedEgg=egg
        state.cachedEggWorld=currentWorld
        state.cachedEggMax=currentMax
        state.cachedEggAt=now()
        return egg
    end
    -- Prefer explicitly world-scoped modules over guessed global egg indices.
    if currentWorld then
        local sourceEggs=worldEggRecords(currentWorld,data)
        if #sourceEggs>0 then
            best=sourceEggs[1]
            state.eggSource=best.source
        end
    end
    if not best and type(directory)=="table" and currentWorld then
        for _,egg in pairs(directory) do
            if type(egg)=="table" and type(egg._id)=="string"
                and tonumber(egg.worldNumber or egg.WorldNumber)==currentWorld then
                local number=tonumber(egg.eggNumber or egg.EggNumber)
                if number then
                    local verified,unlocked=false,false
                    if type(state.clients.EggCmds)=="table"
                        and type(state.clients.EggCmds.IsUnlocked)=="function" then
                        local yesOk,yes=callMethod(state.clients.EggCmds,"IsUnlocked",egg._id)
                        if yesOk and type(yes)=="boolean" then
                            verified=true;unlocked=yes
                        end
                    end
                    if not verified and currentMax then
                        verified=true;unlocked=number<=currentMax
                    end
                    -- Do not infer an unlock if both APIs are unavailable.
                    -- The zone/MaximumAvailableEgg limit means ELIGIBLE, not purchased.
                    -- A false IsUnlocked response must still permit an unlock attempt.
                    if (unlocked or (currentMax and number<=currentMax))
                        and (not best or number>best.number) then
                        local zoneName=nil
                        local zoneNumber=tonumber(egg.zoneNumber)
                        if zoneNumber and type(dir.Zones)=="table" then
                            for label,z in pairs(dir.Zones) do
                                if type(z)=="table" and tonumber(z.ZoneNumber)==zoneNumber then
                                    local zw=tonumber(z.WorldNumber or z.worldNumber)
                                    if zw==nil or zw==currentWorld then
                                        zoneName=tostring(z.ZoneName or z._id or label)
                                        break
                                    end
                                end
                            end
                        end
                        best={number=number,name=egg._id,world=currentWorld,
                            zoneName=zoneName,source="Directory.Eggs",currency=egg.Currency}
                        state.eggSource="Directory.Eggs"
                    end
                end
            end
        end
    end

    -- Resolve target location using zone metadata; do not guess coordinates.
    -- Some egg modules omit zoneNumber, but zones carry MaximumAvailableEgg.
    if best and not best.zoneName and not best.zoneNumber and dir and type(dir.Zones)=="table" then
        local candidate,bestCeiling=nil,math.huge
        for label,z in pairs(dir.Zones) do
            if type(z)=="table" then
                local worldOfZone=zoneWorld(tostring(label),z)
                local ceiling=tonumber(z.MaximumAvailableEgg)
                if worldOfZone==currentWorld and ceiling and ceiling>=best.number
                    and ceiling<bestCeiling then
                    local zoneName=tostring(z.ZoneName or z._id or label)
                    local ownsOk,owns=callMethod(state.clients.ZoneCmds,"Owns",zoneName)
                    if not ownsOk or owns==true then
                        candidate=zoneName;bestCeiling=ceiling
                    end
                end
            end
        end
        if candidate then best.zoneName=candidate end
    end
    if best and not best.zoneName and best.zoneNumber and dir and type(dir.Zones)=="table" then
        for label, z in pairs(dir.Zones) do
            if type(z)=="table" and tonumber(z.ZoneNumber)==best.zoneNumber then
                local zw=zoneWorld(tostring(label),z)
                if not zw or zw==currentWorld then
                    best.zoneName=tostring(z.ZoneName or z._id or label)
                    break
                end
            end
        end
    end
    -- Read all loaded capsules. Modern DZ Hub uses this layout; old releases
    -- use PriceHUD.PriceHUDAvailable. Neither layout is guaranteed in every map.
    local things=findChild(Workspace,"__THINGS")
    local eggs=findChild(things,"Eggs")
    if eggs then
        local capsules={}
        for _,obj in ipairs(eggs:GetDescendants()) do
            local num=tonumber(obj.Name:match("^(%d+)%s*%-%s*Egg Capsule"))
            if num and (obj:IsA("Model") or obj:IsA("BasePart")) then
                local ok,pivot=pcall(obj.GetPivot,obj)
                if ok and typeof(pivot)=="CFrame" then
                    capsules[num]=pivot
                end
            end
        end
        if best then
            best.capsuleCFrame=capsules[best.number]
            return remember(best)
        end
        -- Fallback when directory data is absent or not mapped.
        local main=findChild(eggs,"Main")
        if main then
            local old={}
            for _,obj in ipairs(main:GetChildren()) do
                local number=tonumber(obj.Name:match("^(%d+)"))
                local hud=findChild(obj,"PriceHUD")
                local unlocked=hud and (findChild(hud,"PriceHUDAvailable") or findChild(hud,"PriceHUD"))
                if number and unlocked then
                    old[#old+1]={number=number,point=(hud:IsA("BasePart") and hud or obj:FindFirstChildWhichIsA("BasePart",true))}
                end
            end
            table.sort(old,function(a,b)return a.number>b.number end)
            if old[1] then
                local util=tryModule(findChild(findChild(findChild(ReplicatedStorage,"Library"),"Util"),"EggsUtil"))
                local ok,id=callMethod(util,"GetIdByNumber",old[1].number)
                if ok and type(id)=="string" then
                    return remember({number=old[1].number,name=id,point=old[1].point,source="EggsUtil"})
                end
            end
        end
    end
    if best then return remember(best) end
    -- Legacy PS99 evidence: EggsUtil.GetIdByNumber(saved max egg). This is
    -- attempted ONLY when no world-scoped egg could be identified. Never
    -- generate synthetic names or treat an unknown name as verified.
    if currentWorld and currentMax and currentMax>=1 then
        local eggsUtil=tryModule(findChild(findChild(findChild(ReplicatedStorage,"Library"),"Util"),"EggsUtil"))
        if type(eggsUtil)=="table" then
            for offset=0,math.min(4,currentMax-1) do
                local number=currentMax-offset
                local ok,id=callMethod(eggsUtil,"GetIdByNumber",number)
                if not ok or type(id)~="string" then
                    local ok2,entry=callMethod(eggsUtil,"GetByNumber",number)
                    if ok2 and type(entry)=="table" then
                        ok,id=true,entry.name or entry._id
                    end
                end
                if ok and type(id)=="string" and id~="" then
                    if number<=currentMax then
                        state.eggFallbackStatus="EggsUtil.GetIdByNumber("..number..") returned "..id
                        state.eggSource="EggsUtil fallback; pending purchase verification"
                        return remember({number=number,name=id,world=currentWorld,
                            source="EggsUtil.GetIdByNumber",zoneName=nil})
                    end
                end
            end
            state.eggFallbackStatus="EggsUtil returned no eligible egg around saved max "..currentMax
        else
            state.eggFallbackStatus="EggsUtil module unavailable"
        end
    end
    return nil
end

-- Do not count a successful pcall as a credited egg. Some PS99 interfaces
-- return nil even when called successfully; observed save changes are stronger.
local function observeHatchProgress()
    if now()-state.hatchObservedAt<2.5 then return end
    state.hatchObservedAt=now()
    local data=saveData(true)
    local total=data and tonumber(data.EggsHatched)
    local credited=0
    if total then
        if state.hatchObservedTotal and total>state.hatchObservedTotal then
            credited=total-state.hatchObservedTotal
        end
        state.hatchObservedTotal=total
    end
    -- Some game builds expose quest progress more reliably than EggsHatched.
    -- Only compare updates to the SAME quest, never across quest replacements.
    if type(data)=="table" then
        for _,quest in ipairs(readGoals(data)) do
            if quest.kind=="hatch" then
                if state.hatchQuestIdentity==quest.identity
                    and state.hatchQuestProgress
                    and quest.progress>state.hatchQuestProgress then
                    credited=math.max(credited,quest.progress-state.hatchQuestProgress)
                end
                state.hatchQuestIdentity=quest.identity
                state.hatchQuestProgress=quest.progress
                break
            end
        end
    end
    if credited>0 then
        state.hatchConfirmed=state.hatchConfirmed+credited
        state.hatchNoProgress=0
        state.hatchRefusals=0
        state.hatchNeedsCoins=false
        state.hatchBatch=nil
        state.hatchLastConfirmedAt=now()
        if state.eggUnlockPending and state.eggUnlockPending.name==state.hatchLastEgg then
            state.eggUnlockSuccess=state.eggUnlockSuccess+1
            state.eggUnlockStatus="Confirmed by actual hatch progress"
            state.eggUnlockSource="EggsHatched / rank quest increase"
            state.eggVerifiedByHatchName=state.hatchLastEgg
            state.eggVerifiedByHatchWorld=state.world and state.world.number
            state.eggUnlockPending=nil
        end
        state.hatchLastResult="confirmed +"..tostring(credited).." eggs"
        if cooldownReady("hatch:progress",10) then
            log("Hatch progress increased by "..credited.." eggs","HATCH")
        end
    end
end

-- Select a hatch rank quest independently of chooseGoal(). Farming/other
-- rank quests can progress simultaneously; a main farm quest no longer starves
-- hatching just because it scores higher.
local function activeHatchQuest()
    if state.rankStage and state.rankStage.ready then return nil end
    local best,bestScore=nil,-math.huge
    for _,quest in ipairs(state.goals) do
        if quest.kind=="hatch" then
            local progress=quest.required>0 and math.clamp(quest.progress/quest.required,0,1) or 0
            local score=(Config.PreferHighStars and (starValue(quest)-1)*12 or 0)+progress*18
            if score>bestScore then best,bestScore=quest,score end
        end
    end
    return best
end

-- The best-egg rainbow task can require hatching raw material even when
-- no separate Hatch Eggs rank quest is present. Never hatch indefinitely when
-- enough best-egg regular/gold pets already exist for the next craft.
local function activeBestEggRainbowQuest(data)
    local goals=data and readGoals(data) or state.goals
    for _,g in ipairs(goals or {}) do
        local title=type(g.title)=="string" and g.title:lower() or ""
        if g.kind=="convert" and title:find("rainbow",1,true)
            and title:find("best egg",1,true) and (g.required or 0)>(g.progress or 0) then
            return g
        end
    end
    return nil
end
local function bestEggPetSpecies()
    local egg=findEgg()
    if not egg or type(egg.pets)~="table" then return {},egg end
    local species={}
    for _,row in pairs(egg.pets) do
        if type(row)=="table" and type(row[1])=="string" then species[row[1]]=true end
    end
    return species,egg
end
local function rainbowHasCraftMaterials(data)
    local species=bestEggPetSpecies()
    if not next(species) then return false end
    local pets=data and data.Inventory and data.Inventory.Pet
    if type(pets)~="table" then return false end
    for _,row in pairs(pets) do
        local info=type(row)=="table" and (row._data or row) or nil
        if type(info)=="table" and species[info.id] and not info.sh then
            local amount=tonumber(info._am or row._am) or 1
            if (info.pt==1 or info.pt=="1") and amount>=10 then return true end
            if (info.pt==nil or info.pt==false or info.pt==0)
                and amount>=100+math.max(0,tonumber(Config.ConversionPetReserve) or 10)
                and Config.AutoGoldForRainbow then return true end
        end
    end
    return false
end
local function hatchIntended(data)
    if Config.AutoHatchAlways then return true,"always hatch enabled" end
    data=data or saveData(true)
    if not data then return false,"save unavailable" end
    for _,g in ipairs(readGoals(data)) do
        if g.kind=="hatch" and g.required>g.progress then return true,"hatch quest" end
    end
    if Config.AutoHatchForGold and Config.AutoGoldConversion then
        local src=data and readGoals(data) or state.goals
        for _,g in ipairs(src or {}) do
            local title=type(g.title)=="string" and g.title:lower() or ""
            if g.kind=="convert" and title:find("gold",1,true)
                and title:find("best egg",1,true) and (g.required or 0)>(g.progress or 0) then
                local species=bestEggPetSpecies()
                if not next(species) then return false,"gold quest egg species unknown" end
                local petInventory=data and data.Inventory and data.Inventory.Pet
                local convertible=false
                for _,row in pairs(type(petInventory)=="table" and petInventory or {}) do
                    local info=type(row)=="table" and (row._data or row) or nil
                    if type(info)=="table" and species[info.id] and (info.pt==nil or info.pt==false or info.pt==0)
                        and not info.sh then
                        if (tonumber(info._am or row._am) or 1)>=10+
                            math.max(0,tonumber(Config.ConversionPetReserve) or 10) then
                            convertible=true;break
                        end
                    end
                end
                if not convertible then return true,"gold best-egg materials" end
            end
        end
    end
    if Config.AutoHatchForRainbow and Config.AutoRainbowConversion
        and Config.AutoGoldForRainbow and activeBestEggRainbowQuest(data) then
        local species=bestEggPetSpecies()
        -- Do not spend coins blind if the current best egg's pet species
        -- metadata is missing. Conversion cannot be verified without it.
        if not next(species) then
            return false,"best-egg species metadata unavailable"
        end
        if not rainbowHasCraftMaterials(data) then
            return true,"rainbow material hatching"
        end
    end
    return false,"no active hatch/material requirement"
end

-- DZ Hub's no-animation implementation, but WITHOUT the restricted CoreGui
-- dependency. Revert every override when paused or unloaded.
local function skipEggAnimation(enabled)
    local anim=state.eggAnimation
    local active=enabled and Config.SkipEggAnimations
    local changed=false
    if active and state.eggAnimation.installed
        and now()-state.lastAnimationScan<3 then return true end
    if active then
        state.lastAnimationScan=now()
        local ps=LocalPlayer:FindFirstChild("PlayerScripts")
        local scripts=findChild(ps,"Scripts")
        local gameScripts=findChild(scripts,"Game")
        local frontend=findChild(gameScripts,"Egg Opening Frontend")
        if not anim.originalPlay and frontend and type(getsenv)=="function" then
            local ok,env=pcall(getsenv,frontend)
            if ok and type(env)=="table" and type(env.PlayEggAnimation)=="function" then
                anim.frontend=env
                anim.originalPlay=env.PlayEggAnimation
                local installed=pcall(function() env.PlayEggAnimation=function() end end)
                if not installed then anim.originalPlay=nil;anim.frontend=nil else changed=true end
            end
        end
        local settings=state.clients.SettingsCmds
        if not anim.originalGet and type(settings)=="table" and type(settings.Get)=="function" then
            local original=settings.Get
            local installed=pcall(function()
                settings.Get=function(key,...)
                    if key=="EggPotatoMode" then return "On" end
                    return original(key,...)
                end
            end)
            if installed then anim.settings=settings;anim.originalGet=original;changed=true end
        end
        if not anim.workspaceSaved then
            local ok,old=pcall(Workspace.GetAttribute,Workspace,"GlobalInstantHatch")
            if ok then
                local applied=pcall(Workspace.SetAttribute,Workspace,"GlobalInstantHatch",true)
                if applied then
                    anim.oldInstant=old
                    anim.workspaceSaved=true
                    changed=true
                end
            end
        end
        -- Clear only the PS99 hatch prompt, never destroy the Egg GUI itself.
        local gui=LocalPlayer:FindFirstChild("PlayerGui")
        if gui then
            for _,v in ipairs(gui:GetDescendants()) do
                if v.Name=="TapToOpen" then pcall(v.Destroy,v) end
            end
        end
    else
        if anim.originalPlay and anim.frontend then
            pcall(function() anim.frontend.PlayEggAnimation=anim.originalPlay end)
        end
        anim.originalPlay=nil;anim.frontend=nil
        if anim.originalGet and anim.settings then
            pcall(function() anim.settings.Get=anim.originalGet end)
        end
        anim.originalGet=nil;anim.settings=nil
        if anim.workspaceSaved then
            pcall(function() Workspace:SetAttribute("GlobalInstantHatch",anim.oldInstant) end)
            anim.workspaceSaved=false;anim.oldInstant=nil
        end
    end
    anim.installed=anim.workspaceSaved or anim.originalPlay~=nil or anim.originalGet~=nil
    return changed or anim.installed
end

-- Request an unlock before hatching. A successful RPC invocation is not proof of
-- ownership, so always recheck PurchasedEggs / the client before the hatch probe.
-- Public open-source call: Network.Invoke("Eggs_RequestUnlock", egg.name).
local function ensureEggUnlocked(egg)
    local data=saveData(true)
    local owned,evidence=eggUnlockEvidence(egg,data)
    if owned then
        state.eggUnlockStatus="Confirmed: "..evidence
        state.eggUnlockSource=evidence
        state.eggUnlockPending=nil
        return true
    end
    local pending=state.eggUnlockPending
    if pending and pending.name==egg.name and now()<pending.expires then
        if pending.acknowledged and now()>=pending.readyAt then
            -- No saved ownership yet, but the unlock call did not reject.
            -- Permit a bounded hatch attempt; only EggsHatched/quest progress
            -- can ultimately verify that the egg is actually usable.
            state.eggUnlockStatus="Unlock request acknowledged; hatch credit pending"
            return true
        end
        state.eggUnlockStatus="Waiting for egg unlock confirmation"
        return false
    end
    if now()<state.eggUnlockNext then return false end
    state.eggUnlockNext=now()+3
    local success,response=network("Eggs_RequestUnlock",{egg.name},true)
    state.eggUnlockRequests=state.eggUnlockRequests+1
    state.eggUnlockLast="Eggs_RequestUnlock("..egg.name..") -> "
        ..(success and describe(response) or "ERROR "..describe(response))
    if not success or response==false then
        state.eggUnlockStatus="Unlock refused; inspect requested egg and zone"
        state.eggUnlockNext=now()+20
        state.eggUnlockPending={name=egg.name,acknowledged=false,
            readyAt=now()+20,expires=now()+20}
        if cooldownReady("egg:unlockRefused",20) then
            log(state.eggUnlockLast,"WAIT")
        end
        return false
    end
    state.eggUnlockPending={name=egg.name,acknowledged=true,
        readyAt=now()+2,expires=now()+50}
    state.eggUnlockStatus="Unlock sent, rechecking purchase state"
    if cooldownReady("egg:unlockSent",12) then log(state.eggUnlockLast,"EGG") end
    return false
end

-- Dedicated hatching action, never called from the main quest planner. Attempt
-- smaller batches after an explicit refusal, and detect lack of save progress.
local function hatch(allowTeleport)
    if not Config.AutoHatch or not healthy("hatch") then return false end
    if now()<state.hatchRetryAt then return false end
    if now()-state.lastHatch<Config.HatchActionSeconds then return false end
    state.lastHatch=now()
    observeHatchProgress()
    -- Verify against FRESH save, not a planner snapshot from the previous tick.
    -- This also guards the exported HatchNow() command after a quest is replaced.
    local fresh=saveData(true)
    local intended,intent=hatchIntended(fresh)
    if not intended then
        state.hatchGoalActive=false
        state.hatchLastResult="Hatch suspended: no active hatch or rainbow material need"
        state.hatchFarmRemoteProbe=nil
        return false
    end
    state.hatchIntent=intent
    -- A remote-only hatch from the farming zone gets ONE probe. Do not
    -- repeat or promote to full batches until EggsHatched really increases.
    if state.hatchFarmRemoteProbe then
        local pending=state.hatchFarmRemoteProbe
        local latest=saveData(true)
        local total=latest and tonumber(latest.EggsHatched)
        if total and total>pending.before then
            state.hatchFarmRemoteSupported=true
            state.hatchFarmRemoteLast="Verified remote hatch while staying in the farming area"
            state.hatchFarmRemoteProbe=nil
        elseif now()-pending.sent>=9 then
            state.hatchFarmRemoteSupported=false
            state.hatchFarmRemoteBackoff=now()+120
            state.hatchFarmRemoteLast="Remote hatch gave no egg credit; using location-sharing windows"
            state.hatchFarmRemoteProbe=nil
        else
            return false
        end
    end
    local egg=findEgg()
    if not egg then
        -- v5.2: without an egg the hatch lane cannot act, so release
        -- hatch-first exclusivity briefly and let farming continue.
        state.hatchNoEggUntil=now()+30
        state.hatchLastResult="No unlocked egg identified"
        if cooldownReady("hatch:noEgg",18) then log(state.hatchLastResult,"WAIT") end
        return false
    end
    local root=currentRoot()
    if not root then return false end
    -- If another quest is the primary activity, do not ping-pong the player
    -- between the best farming area and an egg room far away.
    local eggLocation=egg.capsuleCFrame or (egg.point and egg.point.CFrame)
    if not eggLocation and egg.zoneName then
        local found,zoneCF=callMethod(state.clients.ZonesUtil,"GetTeleportPartLocation",egg.zoneName)
        if found and typeof(zoneCF)=="CFrame" then eggLocation=zoneCF end
    end
    local pos=eggLocation and eggLocation.Position
    local awayFromEgg=pos and (root.Position-pos).Magnitude>35
    local remoteFarmProbe=false
    if awayFromEgg then
        if Config.HatchFarmRemoteProbe and not allowTeleport then
            if state.hatchFarmRemoteSupported then
                remoteFarmProbe=true
            elseif now()>=state.hatchFarmRemoteBackoff
                and now()-state.hatchRemoteLastProbe>=20 then
                remoteFarmProbe=true
                state.hatchRemoteLastProbe=now()
            end
        end
        if not remoteFarmProbe then
            if allowTeleport then
                local cf=eggLocation
                if typeof(cf)=="CFrame" then
                    pcall(function() root.CFrame=cf+Vector3.new(0,4,0) end)
                    state.hatchLastResult="Moving to best unlocked egg"
                end
            else
                state.hatchLastResult="Waiting for hatch travel window or verified remote hatch"
            end
            return false
        end
    end
    if not ensureEggUnlocked(egg) then
        state.hatchLastResult="Unlocking egg first: "..tostring(egg.name)
        return false
    end
    local ok,cap=callMethod(state.clients.EggCmds,"GetMaxHatch")
    if not ok or not tonumber(cap) then
        ok,cap=callMethod(state.clients.EggCmds,"GetMaxHatch",egg.name)
    end
    -- A missing GetMaxHatch is not a reason to permanently stop auto-hatch.
    -- Public PS99 examples pass a quantity to Eggs_RequestPurchase; testing
    -- exactly one egg is the safest supported fallback. Never invent a cap.
    local liveCap: number = 1
    local numericCap: number? = tonumber(cap)
    if ok and numericCap ~= nil and numericCap >= 1 then
        liveCap = math.floor(numericCap)
        state.hatchCapacitySource="EggCmds.GetMaxHatch"
    else
        local saved=saveData()
        local count=saved and tonumber(saved.EggHatchCount)
        if count and count>=1 then
            liveCap=math.floor(count)
            state.hatchCapacitySource="Save.EggHatchCount (source-backed fallback)"
        else
            state.hatchCapacitySource="fallback: one egg; game cap unavailable"
        end
        if liveCap==1 and cooldownReady("hatch:capFallback",30) then
            log("GetMaxHatch unavailable. Attempting one egg and verifying actual game progress", "HATCH")
        end
    end
    local qty=math.clamp(math.floor(state.hatchBatch or liveCap),1,
        math.min(liveCap,Config.MaxHatchBatch))
    if remoteFarmProbe and not state.hatchFarmRemoteSupported then qty=1 end
    local probeBefore=nil
    if remoteFarmProbe and not state.hatchFarmRemoteSupported then
        local snapshot=saveData(true)
        probeBefore=snapshot and tonumber(snapshot.EggsHatched)
        if probeBefore==nil then
            state.hatchFarmRemoteLast="No egg counter for away-from-egg trial; falling back to travel"
            state.hatchFarmRemoteBackoff=now()+120
            return false
        end
    end
    state.hatchLastQty=qty
    state.hatchLastEgg=egg.name
    local success,result,reason
    if type(state.clients.EggCmds)=="table" and type(state.clients.EggCmds.RequestPurchase)=="function" then
        state.hatchLastApi="EggCmds.RequestPurchase"
        success,result,reason=callMethod(state.clients.EggCmds,"RequestPurchase",egg.name,qty)
        -- A thrown error is not evidence that the fallback remote will work,
        -- but the remote is documented by public PS99 scripts.
        if not success or result==false then
            state.hatchLastApi="Eggs_RequestPurchase (fallback after client refusal/error)"
            success,result=network("Eggs_RequestPurchase",{egg.name,qty},true)
        end
    else
        state.hatchLastApi="Eggs_RequestPurchase"
        success,result=network("Eggs_RequestPurchase",{egg.name,qty},true)
    end
    state.attempts.hatch=state.attempts.hatch+1
    if not success or result==false then
        if remoteFarmProbe then
            state.hatchFarmRemoteBackoff=now()+120
            state.hatchFarmRemoteSupported=false
            state.hatchFarmRemoteLast="Away-from-egg request rejected; will use normal travel"
        end
        local why=tostring(reason or result or "unspecified refusal")
        state.hatchRefusals=state.hatchRefusals+1
        state.hatchLastResult="Refused "..qty.."x "..egg.name..": "..why
        if qty>1 then
            state.hatchBatch=math.max(1,math.floor(qty/2))
            -- Unaffordable max batch? Retry fewer eggs next time.
        else
            -- A false/error return alone does NOT mean the account is broke.
            -- Only relinquish the hatch-first movement lease when the client
            -- explicitly identifies an affordability/currency problem.
            local reasonText=why:lower()
            local shortOnCurrency=reasonText:find("insufficient",1,true)
                or reasonText:find("not enough",1,true)
                or reasonText:find("cannot afford",1,true)
                or reasonText:find("currency",1,true)
                or reasonText:find("coins",1,true)
                or reasonText:find("funds",1,true)
            state.hatchNeedsCoins=not not shortOnCurrency
            state.hatchRetryAt=now()+14
            state.hatchBatch=1
            if cooldownReady("hatch:coin",20) then
                log(state.hatchNeedsCoins
                    and ("Insufficient egg currency reported; temporarily farming coins: "..why)
                    or ("One-egg refusal with no proven coin shortage; holding egg position and retrying: "..why),"HATCH")
            end
        end
        if cooldownReady("hatch:refusal",8) then log(state.hatchLastResult,"WAIT") end
        return false
    end
    state.hatchNeedsCoins=false
    state.lastSuccessfulAction=now()
    if probeBefore then
        state.hatchFarmRemoteProbe={before=probeBefore,sent=now()}
        state.hatchFarmRemoteLast="Sent one away-from-egg test hatch; awaiting actual egg counter"
    end
    state.hatchNoProgress=state.hatchNoProgress+1
    state.hatchLastResult="Request sent: "..qty.."x "..egg.name.." via "..state.hatchLastApi.." (credit unconfirmed)"
    if cooldownReady("hatch:request",20) then log(state.hatchLastResult,"HATCH") end
    -- A nil return can be a valid accepted request, OR a silent rejection.
    -- Only adapt when neither EggsHatched nor the same quest shows progress.
    if state.hatchNoProgress>=6 and (state.hatchLastConfirmedAt==0
        or now()-state.hatchLastConfirmedAt>8) then
        if qty>1 then
            state.hatchBatch=math.max(1,math.floor(qty/2))
            if cooldownReady("hatch:batch",10) then
                log("No observed egg progress; trying smaller hatch batch of "..state.hatchBatch,"DIAGNOSTIC")
            end
            state.hatchNoProgress=0
        else
            -- No credit is an API/position/currency UNKNOWN, not proof of a
            -- shortage. Preserve egg-first location instead of racing diamonds.
            state.hatchNeedsCoins=false
            state.hatchRetryAt=now()+15
            state.hatchNoProgress=0
            if cooldownReady("hatch:stalled",25) then
                log("One-egg requests did not increase progress. Keeping egg location; inspect API, currency and hatch requirements", "DIAGNOSTIC")
            end
        end
    end
    return true
end
local function consume(goal)
    if not healthy(goal.kind) then return false end
    -- Every consumable kind is an independent lane. A fruit use cannot block a
    -- potion use, and an unavailable exact-tier potion must not be substituted.
    local throttleKey = goal.kind .. ":" .. goal.identity
    if now() - (state.consumableTimes[throttleKey] or 0) < Config.ConsumableSeconds then return false end
    state.consumableTimes[throttleKey] = now()
    state.lastConsumable = now()
    if goal.kind == "fruit" then
        local fruit = getInventoryEntry("Fruit")
        if not fruit then return false end
        local ok, result = callMethod(state.clients.FruitCmds, "Consume", fruit.uid)
        if ok and result ~= false then state.lastSuccessfulAction = now(); return true end
        failFeature("fruit", result)
    elseif goal.kind == "potion" then
        -- Public and user-captured PS99 calls establish Potions: Consume(uid, 1).
        -- Whether quantity>1 is supported is UNVERIFIED. Probe only two,
        -- verify real quest credit, then grow to modest bounded batches.
        local pending=state.potionPending
        if pending then
            if now()-pending.sent<2.2 then return false end
            local latest=saveData(true)
            local current=nil
            if latest then
                for _,g in ipairs(readGoals(latest)) do
                    if g.identity==pending.identity or (pending.uid and g.uid==pending.uid) then
                        current=g;break
                    end
                end
            end
            local credit=current and math.max(0,current.progress-pending.progress) or 0
            local rewarded=latest and not current
                and ((tonumber(latest.GoalsCompleted) or 0)>pending.completed
                    or (tonumber(latest.RankStars) or 0)>pending.stars)
            if credit>=2 or (rewarded and pending.quantity>1) then
                state.potionBatchVerified=true
                state.potionBatchLast="Verified potion batch credit +"..tostring(credit>0 and credit or pending.quantity)
            elseif now()-pending.sent<4.5 then
                return false -- Server may replicate the goal a little later.
            else
                state.potionBatchVerified=false
                state.potionBatchLast="No 2+ credit from quantity probe; using safe single potion consumption"
            end
            state.potionPending=nil
            -- If the quest disappeared, never use more bottles against stale data.
            if not current then return false end
        end
        local snapshot=saveData(true)
        local fresh=nil
        if snapshot then
            for _,g in ipairs(readGoals(snapshot)) do
                if g.identity==goal.identity then fresh=g;break end
            end
        end
        if not fresh then return false end
        local tier = numeralToNumber(fresh.title)
        local potion,matchedName = potionForUseGoal(fresh,tier,snapshot)
        if not potion then
            if cooldownReady("potion:missing:"..goal.identity,45) then
                log("Use-potion quest needs " .. (tier and ("tier "..tier) or "any tier")
                    .. "; no matching potion in readable inventory", "WAIT")
            end
            return false
        end
        local remaining=math.max(0,fresh.required-fresh.progress)
        if remaining<1 then return false end
        local limit=math.clamp(math.floor(tonumber(Config.PotionMaxBatch) or 8),1,12)
        local quantity=1
        if Config.PotionBatchUse and remaining>=2 and potion.amount>=2
            and state.potionBatchVerified~=false then
            quantity=state.potionBatchVerified and math.min(limit,remaining,potion.amount) or 2
        end
        if quantity>1 then
            local ok,response=network("Potions: Consume",{potion.uid,quantity},false)
            if ok and response~=false then
                state.potionBatchedRequests=state.potionBatchedRequests+1
                state.potionPending={identity=fresh.identity,uid=fresh.uid,
                    progress=fresh.progress,quantity=quantity,sent=now(),
                    stars=tonumber(snapshot.RankStars) or 0,
                    completed=tonumber(snapshot.GoalsCompleted) or 0}
                state.potionBatchLast="Sent "..quantity.." potion use request(s) for "..potion.id.."; matched type="..tostring(matchedName or "generic tier").."; credit pending"
                state.lastSuccessfulAction=now()
                return true
            end
            state.potionBatchVerified=false
            state.potionBatchLast="Quantity>1 not accepted; switching to safe singles"
        end
        local ok,result=callMethod(state.clients.PotionCmds,"Consume",potion.uid)
        if not ok then
            ok,result=network("Potions: Consume",{potion.uid,1},false)
        end
        if ok and result~=false then
            state.potionFallbackUses=state.potionFallbackUses+1
            state.lastSuccessfulAction=now()
            if cooldownReady("potion:request:"..goal.identity,12) then
                log("Using "..potion.id.." tier="..tostring(potion.tier).." (single verified-format request)","POTION")
            end
            return true
        end
        failFeature("potion",result)
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
    if not Config.AutoVending or not healthy("vending") then return false end
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
                        if inHatchMovementWindow() or not leaseMovement("vending",6) then return false end
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
    -- Decompiled ActionMenu.Misc["Mini Pinata"]: Network.Invoke("MiniPinata_Consume", uid);
    -- MiniLuckyBlock_Consume(uid) from the captured remote list and VY AutoRank.
    pinata = {match = "Mini Pinata", remote = "MiniPinata_Consume"},
    luckyblock = {match = "Mini Lucky Block", remote = "MiniLuckyBlock_Consume"},
}
local function spawnQuestObject(goal)
    if not Config.AutoEventItems or not healthy("spawn-"..goal.kind) then return false end
    -- If the game's actual quest counter advanced, the previous jar/comet
    -- was completed; do not needlessly wait out its older pending timeout.
    state.spawnObserved=state.spawnObserved or {}
    local previousProgress=state.spawnObserved[goal.identity]
    if previousProgress~=nil and goal.progress>previousProgress then
        state.spawnPending[goal.identity]=0
    end
    state.spawnObserved[goal.identity]=goal.progress
    if now()-state.lastEventItem<Config.SpawnItemSeconds then return false end
    if now()<(state.spawnPending[goal.identity] or 0) then return false end
    local spec=itemTypes[goal.kind]
    if not spec or not spec.remote then return false end
    if not movementAvailable("event") or inHatchMovementWindow() then return false end

    local savedTitle=state.activeGoalTitle
    state.activeGoalTitle=goal.title
    local existing=visibleTargetCandidates(goal.kind)
    state.activeGoalTitle=savedTitle
    if #existing>0 then
        state.eventFocus=goal.identity
        state.eventFocusUntil=now()+10
        if cooldownReady("event:exists:"..goal.kind,30) then
            log("Existing "..goal.kind.." detected; pets will attack before spending another", "EVENT")
        end
        return false
    end

    local item=getInventoryEntry("Misc",spec.match)
    if not item then
        state.spawnLast="Missing "..spec.match.." item in Inventory.Misc or InventoryCmds.State"
        if cooldownReady("event:noitem:"..goal.kind,35) then log(state.spawnLast,"WAIT") end
        return false
    end
    local best=getZoneInfo()
    if not best then
        state.spawnLast="Cannot resolve best owned area for "..goal.kind
        if cooldownReady("event:nozone",35) then log(state.spawnLast,"WAIT") end
        return false
    end
    if not leaseMovement("event",5) then return false end
    local before=currentRoot() and currentRoot().Position
    local placed,placeWhy=placeInZone(best)
    if not placed then
        state.spawnLast="Zone travel failed: "..tostring(placeWhy)
        clearMovement("event")
        if cooldownReady("event:travel",30) then log(state.spawnLast,"WAIT") end
        return false
    end
    local moved=before and currentRoot() and (currentRoot().Position-before).Magnitude>15
    if moved then task.wait(0.55) end -- Allow zone replication to settle.
    local ok,result=network(spec.remote,{item.uid},true)
    state.commandCount=state.commandCount+(ok and 1 or 0)
    state.lastEventItem=now()
    state.spawnPending[goal.identity]=now()+(ok and result~=false and 13 or 18)
    clearMovement("event")
    state.spawnLast=spec.remote.." item="..item.id.." uid="..tostring(item.uid)
        .." zone="..best.name.." response="..describe(result)
    if ok and result~=false then
        state.spawnActions=state.spawnActions+1
        state.eventFocus=goal.identity
        state.eventFocusUntil=now()+15
        log("Spawn request sent: "..state.spawnLast.."; waiting for object or quest credit", "EVENT")
        return true
    end
    if cooldownReady("event:reject:"..goal.kind,15) then log("Spawn rejected: "..state.spawnLast,"WAIT") end
    return false
end
-- Low-tier upgrades are supported by PS99 public Lua implementations:
-- UpgradePotionsMachine_Activate(uid, count) and
-- UpgradeEnchantsMachine_Activate(uid, count). The batch argument counts
-- outputs, not ingredients. Check observed quest progress before any retry.
local function collectionGoals()
    local items={}
    for _,g in ipairs(state.goals) do
        if (g.kind=="collect_potion" or g.kind=="collect_enchant"
            or g.kind=="upgrade_potion" or g.kind=="upgrade_enchant") and eligible(g) then
            items[#items+1]=g
        end
    end
    table.sort(items,function(a,b)
        local ar=a.required>0 and (a.required-a.progress) or 9999
        local br=b.required>0 and (b.required-b.progress) or 9999
        return ar<br
    end)
    return items
end
-- Supercomputer availability differs by place. Void World contains a
-- Supercomputer in its hub; do not teleport a World 3 character to the World 2
-- Tech Spawn CFrame. Search the CURRENT loaded map, then read a local teleport.
local function loadedTechMachine()
    local world=state.world and state.world.number
    local marker=state.lastSuperMachine
    if marker and typeof(marker)=="Instance" and marker:IsDescendantOf(Workspace)
        and marker:IsA("BasePart") then
        return marker
    end
    local maps=mapRoots()
    if now()-(state.lastSuperMachineScan or 0)>=8 then
        state.lastSuperMachineScan=now()
        local candidates={}
        if state.activeWorld then candidates[#candidates+1]=state.activeWorld end
        for _,root in ipairs(maps) do
            if root~=state.activeWorld then candidates[#candidates+1]=root end
        end
        for _,root in ipairs(candidates) do
            -- Local machine folder discovery without a full Workspace scan.
            local machine=root:FindFirstChild("SuperMachine",true)
                or root:FindFirstChild("Supercomputer",true)
            local pad=machine and (machine:FindFirstChild("PadGlow",true)
                or machine:FindFirstChild("Pad",true)
                or machine:FindFirstChild("Arrow",true))
            if not pad and machine and machine:IsA("BasePart") then pad=machine end
            if pad and pad:IsA("BasePart") then
                state.lastSuperMachine=pad
                state.machineStatus="Found local Supercomputer at "..root.Name
                return pad
            end
        end
    end
    -- These hub names are documented in PS99 source/world references. Do not
    -- guess unknown World 4 machine locations or CFrame coordinates.
    local hub=(world==2 and "Tech Spawn") or (world==3 and "Void Spawn") or nil
    if not hub then
        return nil,"No loaded Supercomputer; no verified hub teleport for World "..tostring(world)
    end
    local found,cf=callMethod(state.clients.ZonesUtil,"GetTeleportPartLocation",hub)
    if found and typeof(cf)=="CFrame" then
        if now()>=(state.machineNextTravel or 0)
            and movementAvailable("upgrade") and leaseMovement("upgrade",9) then
            local root=currentRoot()
            local moved=root and pcall(function() root.CFrame=cf+Vector3.new(0,5,0) end)
            if moved then
                state.machineTravelCount=state.machineTravelCount+1
                state.machineNextTravel=now()+40
                state.machineStatus="Moved toward current World "..world.." hub; waiting for Supercomputer streaming"
                -- Hold movement lease so farming cannot immediately teleport away.
            else
                clearMovement("upgrade")
            end
        end
        return nil,"Supercomputer not loaded near "..hub.." yet"
    end
    return nil,"No loaded Supercomputer or supported local hub location in World "..tostring(world)
end
-- Collect quests should use the cheapest surplus stacks first. Public
-- auto-rank code records 3/4 potion inputs and 5/7 enchant inputs depending
-- on the input tier. Live inventory is checked before each purchase.
local function chooseLowTierUpgrade(goal)
    local name=(goal.kind=="collect_potion" or goal.kind=="upgrade_potion") and "Potion" or "Enchant"
    local items={}
    local data=saveData()
    local stock=data and data.Inventory and data.Inventory[name]
    local function addItem(uid,row)
        if type(row)~="table" then return end
        local item=type(row._data)=="table" and row._data or row
        local tier=tonumber(item.tn)
        local quantity=tonumber(item._am or row._am or item.Amount or row.Amount) or 1
        if type(item.id)=="string" and tier and quantity>0 then
            items[#items+1]={uid=uid,id=item.id,tier=tier,amount=quantity}
        end
    end
    if type(stock)=="table" then
        for uid,row in pairs(stock) do addItem(uid,row) end
    end
    if #items==0 then
        local ok,inv=callMethod(state.clients.InventoryCmds,"State")
        local container=ok and type(inv)=="table" and inv.container
        local store=container and container._store
        local section=store and store._byType and store._byType[name]
        if section and type(section._byUID)=="table" then
            for uid,row in pairs(section._byUID) do addItem(uid,row) end
        end
    end
    -- Source: idonthaveoneatm/lua / games/PetSimulator99/autoRanker.lua.
    -- The first six costs are indexed by INPUT tier, not output tier:
    -- potions 3,3,4,5,5,5; enchants 5,5,5,7,7,7.
    -- PS99's BetterCrafting mastery can reduce the required ingredients.
    -- If the live mastery module cannot report a discount, use the full
    -- published historical cost, which errs on the conservative side.
    local potionCosts = {3,3,4,5,5,5}
    local enchantCosts = {5,5,5,7,7,7}
    local discount = 0
    local discountOK,discountValue=callMethod(state.clients.MasteryCmds,
        "GetPerkPower", name=="Potion" and "Potions" or "Enchants", "BetterCrafting")
    if discountOK and type(discountValue)=="number" and discountValue>=0 then
        discount=math.floor(discountValue)
    end
    local candidates={}
    local reserve=math.max(0,tonumber(Config.UpgradeMaterialReserve) or 8)
    local tierLimit=math.clamp(tonumber(Config.MaxUpgradeInputTier) or 6,1,6)
    for _,row in ipairs(items) do
        local key=goal.kind..":"..tostring(row.uid)
        local rejectedUntil=(state.upgradeRejectedUIDs and state.upgradeRejectedUIDs[key]) or 0
        local baseCost=(name=="Potion" and potionCosts or enchantCosts)[row.tier]
        local ingredients=baseCost and math.max(1,baseCost-discount) or nil
        local available=ingredients and math.floor((row.amount-reserve)/ingredients) or 0
        if row.tier>=1 and row.tier<=tierLimit and available>=1
            and now()>=rejectedUntil then
            row.ingredients=ingredients
            row.possible=available
            candidates[#candidates+1]=row
        end
    end
    local remaining=math.max(1,(goal.required or 0)-(goal.progress or 0))
    table.sort(candidates,function(a,b)
        -- Completing the whole quest in one request is faster than jumping
        -- between several low-tier stacks. Compare craft OUTPUT quantities.
        local aComplete=a.possible>=remaining
        local bComplete=b.possible>=remaining
        if aComplete~=bComplete then return aComplete end
        if not aComplete and a.possible~=b.possible then return a.possible>b.possible end
        if a.tier~=b.tier then return a.tier<b.tier end
        if a.possible~=b.possible then return a.possible>b.possible end
        return tostring(a.uid)<tostring(b.uid)
    end)
    if #candidates==0 then
        state.upgradeSelectionLast="No affordable surplus Tier I-"..tostring(tierLimit).." "..name
            .." stacks; reserve="..tostring(reserve)
        return nil,state.upgradeSelectionLast
    end
    local chosen=candidates[1]
    state.upgradeTierLast="Tier "..tostring(chosen.tier).." "..name
    state.upgradeSelectionLast=chosen.id.." (tier "..chosen.tier
        ..", "..chosen.ingredients.." inputs each, "..chosen.possible.." possible upgrades)"
    return chosen
end
-- Group attempts at the machine instead of returning to the farm after
-- every single request. Movement lease and visit length are always bounded.
local function finishUpgradeVisit()
    local root=currentRoot()
    if root and state.upgradeReturnCFrame and state.movementOwner=="upgrade" then
        pcall(function() root.CFrame=state.upgradeReturnCFrame end)
    end
    clearMovement("upgrade")
    state.upgradeReturnCFrame=nil
    state.upgradeVisitStart=0
    state.upgradeVisitCompleted=state.upgradeVisitCompleted+1
end
local function tryCollectionUpgrade()
    if not (Config.AutoUpgradeCollections and Config.AutoRank and Config.AutoParallelQuests
        and state.running and healthy("upgrades-collect")) then
        if state.upgradeVisitStart>0 then finishUpgradeVisit() end
        return false
    end
    local goals=collectionGoals()
    if state.upgradePending then
        local pending=state.upgradePending
        local verifyDelay=math.max(3,tonumber(Config.UpgradeVerifySeconds) or 6)
        if state.upgradeValidated[pending.kind] then verifyDelay=3 end
        if now()-pending.sent<verifyDelay then
            leaseMovement("upgrade",math.max(2,verifyDelay-(now()-pending.sent)+2))
            return false
        end
        local snapshot=saveData(true)
        local rawCurrent=snapshot and readGoals(snapshot) or {}
        local current, originalStillPresent=nil,false
        for _,g in ipairs(rawCurrent) do
            if g.identity==pending.identity then
                current=g
                if not pending.goalUID or not g.raw or not g.raw.UID
                    or tostring(g.raw.UID)==tostring(pending.goalUID) then
                    originalStillPresent=true
                end
                break
            end
        end
        local gained=current and originalStillPresent and math.max(0,current.progress-pending.before) or 0
        local starsAfter=snapshot and tonumber(snapshot.RankStars)
        local completedAfter=snapshot and tonumber(snapshot.GoalsCompleted)
        local changedUID=current and pending.goalUID and current.raw and current.raw.UID
            and tostring(current.raw.UID)~=tostring(pending.goalUID)
        local noLongerPresent=not originalStillPresent or changedUID
        local starsAdvanced=starsAfter and pending.starsBefore and starsAfter>pending.starsBefore
        local completionsAdvanced=completedAfter and pending.completedBefore
            and completedAfter>pending.completedBefore
        local finished=noLongerPresent and (starsAdvanced or completionsAdvanced)
        if gained==0 and not finished and now()-pending.sent<12 then
            -- Short fast verification, with one bounded grace window so a
            -- slow server replication does not falsely blacklist the item.
            leaseMovement("upgrade",math.max(2,12-(now()-pending.sent)+2))
            return false
        end
        if gained>0 or finished then
            state.collectionCredits=state.collectionCredits+1
            state.upgradeValidated[pending.kind]=true
            state.upgradeLastCreditMethod=gained>0 and ("Quest progress +"..gained)
                or "Quest replaced and earned stars/completion recorded"
            state.upgradeLast=pending.kind.." credited: "..state.upgradeLastCreditMethod
            log(state.upgradeLast,"UPGRADE")
        else
            state.upgradeRejectedUIDs[pending.kind..":"..tostring(pending.uid)]=now()+Config.UpgradeRejectedUIDCooldown
            state.upgradeDisabled[pending.identity]=now()+Config.UpgradePauseSeconds
            state.upgradeLast="No confirmed quest credit after "..tostring(pending.outputs)
                .." crafted "..pending.kind.." output(s); paused spending"
            state.upgradeLastCreditMethod="Unconfirmed"
            log(state.upgradeLast,"DIAGNOSTIC")
            finishUpgradeVisit()
        end
        state.upgradePending=nil
        -- Immediately consider the next *active* collection quest after a
        -- confirmed craft rather than waiting through the old 13s hold.
        state.upgradeNext=now()+(state.upgradeLastCreditMethod~="Unconfirmed" and 0.4 or Config.UpgradeInterval)
        return false
    end
    if #goals==0 then
        if state.upgradeVisitStart>0 then finishUpgradeVisit() end
        return false
    end
    if now()<state.upgradeNext or not movementAvailable("upgrade") then return false end
    local goal
    for _,g in ipairs(goals) do
        if now()>=(state.upgradeDisabled[g.identity] or 0) then goal=g;break end
    end
    if not goal then
        if state.upgradeVisitStart>0 then finishUpgradeVisit() end
        return false
    end
    if state.upgradeVisitStart>0
        and now()-state.upgradeVisitStart>=Config.UpgradeVisitSeconds then
        finishUpgradeVisit()
        state.upgradeNext=now()+6 -- farm briefly before next machine visit
        return false
    end
    local item,why=chooseLowTierUpgrade(goal)
    if not item then
        if cooldownReady("upgrade:noitems:"..goal.kind,45) then log(why,"WAIT") end
        state.upgradeDisabled[goal.identity]=now()+28
        state.upgradeNext=now()+8
        if state.upgradeVisitStart>0 then finishUpgradeVisit() end
        return false
    end
    local marker,msg=loadedTechMachine()
    if not marker then
        state.machineStatus=msg
        if cooldownReady("upgrade:machine",30) then log("Upgrade deferred: "..msg,"WAIT") end
        state.upgradeNext=now()+8
        if state.upgradeVisitStart>0 then finishUpgradeVisit() end
        return false
    end
    if not leaseMovement("upgrade",10) then return false end
    local root=currentRoot()
    if not root then clearMovement("upgrade");return false end
    if state.upgradeVisitStart==0 then
        state.upgradeVisitStart=now()
        state.upgradeReturnCFrame=root.CFrame
    end
    if (root.Position-marker.Position).Magnitude>9 then
        local moved=pcall(function() root.CFrame=marker.CFrame+Vector3.new(0,3,0) end)
        if not moved then finishUpgradeVisit();return false end
        task.wait(0.6)
    end
    if (root.Position-marker.Position).Magnitude>13 then
        state.upgradeLast="Supercomputer is too far away after travel; no request sent"
        finishUpgradeVisit()
        state.upgradeNext=now()+12
        return false
    end
    local remote=(goal.kind=="collect_potion" or goal.kind=="upgrade_potion")
        and "UpgradePotionsMachine_Activate" or "UpgradeEnchantsMachine_Activate"
    -- In the supplied 2026-10-09 recording, selecting 111 tier-II potions
    -- produced 37 crafted potions and completed the collect-potions quest.
    -- The remote's count argument is the NUMBER OF OUTPUT CRAFTS in the
    -- publicly readable rank scripts, not the number of input ingredients.
    -- The older single-output test was not representative of that success.
    local available=math.floor((item.amount-Config.UpgradeMaterialReserve)/item.ingredients)
    local remaining=goal.required>0 and math.max(0,goal.required-goal.progress) or 0
    local outputLimit=math.clamp(math.floor(tonumber(Config.UpgradeMaxOutputBatch) or 40),1,100)
    local amount=math.floor(math.min(available,remaining,outputLimit))
    if amount<1 then
        state.upgradeLast="No safe craft quantity after goal limit/material reserve"
        state.upgradeNext=now()+20
        return false
    end
    state.upgradeLastOutputBatch=amount
    local snapshot=saveData(true)
    local called,response=network(remote,{item.uid,amount},true)
    state.upgradeLast=remote.." uid="..tostring(item.uid).." tier="..tostring(item.tier)
        .." count="..tostring(amount).." response="..describe(response)
    state.upgradeCount=state.upgradeCount+1
    state.upgradeNext=now()+Config.UpgradeInterval
    if called and response~=false then
        state.upgradePending={identity=goal.identity,kind=goal.kind,
            before=goal.progress,sent=now(),uid=item.uid,outputs=amount,
            goalUID=goal.raw and goal.raw.UID,
            starsBefore=snapshot and tonumber(snapshot.RankStars),
            completedBefore=snapshot and tonumber(snapshot.GoalsCompleted)}
        leaseMovement("upgrade",9)
        log("Submitted "..amount.." "..goal.kind.." upgrade(s); checking quest progress", "UPGRADE")
    else
        -- A false response is an explicit refusal. Retry a DIFFERENT item
        -- stack, never spam the same UID and never claim it succeeded.
        state.upgradeRejectedUIDs[goal.kind..":"..tostring(item.uid)]=now()+Config.UpgradeRejectedUIDCooldown
        state.upgradeRejectedCount=state.upgradeRejectedCount+1
        state.upgradeNext=now()+3
        leaseMovement("upgrade",8)
        if cooldownReady("upgrade:reject:"..goal.kind,12) then
            log("Rejected "..tostring(item.id).." tier "..tostring(item.tier)
                .." ("..describe(response).."); checking other stack", "WAIT")
        end
    end
    return called and response~=false
end

-- Public Griffin autoRanker: GoldMachine_Activate(petUid, outputCount),
-- ten matching normal pets per gold output. The best egg's source ModuleScript
-- defines its pet species. ON by default since the v3.7 gold workflow request;
-- it keeps ConversionPetReserve regular pets per species and verifies credit.
local function tryGoldenConversion()
    if state.rankStage and state.rankStage.ready then return false end
    if not (Config.AutoGoldConversion and state.running and Config.AutoRank
        and Config.AutoParallelQuests and now()>=state.goldenNext) then return false end
    local goal
    for _,g in ipairs(state.goals) do
        if g.kind=="convert" and g.title:lower():find("golden",1,true)
            and g.title:lower():find("best egg",1,true) then goal=g;break end
    end
    if state.goldenPending then
        local pending=state.goldenPending
        if now()-pending.sent<7 then return false end
        local data=saveData(true)
        local current
        if data then
            for _,g in ipairs(readGoals(data)) do
                if g.identity==pending.identity then current=g;break end
            end
        end
        if current and current.progress>pending.before then
            state.goldenCredited=state.goldenCredited+(current.progress-pending.before)
            state.goldenLast="Gold pets: quest verified +"..(current.progress-pending.before)
            state.goldenNext=now()+3
        else
            state.goldenLast="Gold conversion request uncredited; suspended (items/currency may have been spent)"
            state.goldenRetryAt=now()+300
            state.goldenNext=state.goldenRetryAt
        end
        state.goldenPending=nil
        return false
    end
    if not goal then return false end
    if now()<state.goldenRetryAt or not movementAvailable("gold") then return false end
    local egg=findEgg()
    if not egg or type(egg.pets)~="table" then
        state.goldenLast="Best egg species metadata unavailable; no pets spent"
        state.goldenNext=now()+45
        return false
    end
    local species={}
    for _,row in pairs(egg.pets) do
        if type(row)=="table" and type(row[1])=="string" then
            species[row[1]]=true
        end
    end
    if not next(species) then
        state.goldenLast="No recognized pet IDs in best egg definition"
        state.goldenNext=now()+45
        return false
    end
    local data=saveData()
    local pets=data and data.Inventory and data.Inventory.Pet
    local chosen=nil
    if type(pets)=="table" then
        for uid,row in pairs(pets) do
            local info=type(row)=="table" and (row._data or row) or nil
            local petDirectory=state.clients.Directory and state.clients.Directory.Pets
            local definition=type(petDirectory)=="table" and info and rawget(petDirectory,info.id) or nil
            local valuable=type(definition)=="table" and (definition.huge or definition.titanic)
            if type(info)=="table" and species[info.id] and not valuable
                and (info.pt==nil or info.pt==false or info.pt==0)
                and not info.sh and not info.lk and not info.fav then
                local amount=tonumber(info._am or row._am) or 1
                local reserve=math.max(0,tonumber(Config.ConversionPetReserve) or 10)
                if amount>=10+reserve and (not chosen or amount>chosen.amount) then
                    chosen={uid=uid,id=info.id,amount=amount}
                end
            end
        end
    end
    if not chosen then
        state.goldenLast="No regular best-egg stack with 10 + reserve pets available"
        state.goldenNext=now()+30
        return false
    end
    local marker,msg=loadedTechMachine()
    if not marker then
        state.goldenLast=msg or "Supercomputer not loaded"
        state.goldenNext=now()+18
        return false
    end
    if not leaseMovement("gold",8) then return false end
    local root=currentRoot()
    if not root then clearMovement("gold");return false end
    local previous=root.CFrame
    if (root.Position-marker.Position).Magnitude>12 then
        local moved=pcall(function() root.CFrame=marker.CFrame+Vector3.new(0,4,0) end)
        if not moved then clearMovement("gold");return false end
        task.wait(0.5)
    end
    if (root.Position-marker.Position).Magnitude>18 then
        clearMovement("gold")
        state.goldenLast="Cannot reach verified Supercomputer"
        state.goldenNext=now()+15
        return false
    end
    local called,response=network("GoldMachine_Activate",{chosen.uid,1},true)
    state.goldenAttempts=state.goldenAttempts+1
    pcall(function() root.CFrame=previous end)
    clearMovement("gold")
    state.goldenLast="GoldMachine_Activate uid="..tostring(chosen.uid).." response="..describe(response)
    if called and response~=false then
        state.goldenPending={identity=goal.identity,before=goal.progress,sent=now()}
        state.goldenNext=now()+8
    else
        state.goldenLast=state.goldenLast.." (rejected or unavailable; backing off)"
        state.goldenRetryAt=now()+180
        state.goldenNext=state.goldenRetryAt
    end
    return called and response~=false
end

-- Rainbow prerequisite: GoldMachine_Activate(normalBestEggUID, outputs),
-- then wait for the corresponding gold inventory amount to rise. This is
-- separate from an ordinary Make Golden Pets quest and only runs while a
-- best-egg rainbow rank quest is active. Never assume the request alone
-- proves materials were crafted.
local function tryPrepareRainbowGold(goal, species, data)
    if not Config.AutoGoldForRainbow then return false end
    local pets=data and data.Inventory and data.Inventory.Pet
    if type(pets)~="table" then
        state.rainbowPrepLast="Cannot read pet inventory for prerequisite gold"
        return false
    end
    local goldBySpecies,regular={},{}
    for uid,row in pairs(pets) do
        local info=type(row)=="table" and (row._data or row) or nil
        if type(info)=="table" and species[info.id] and not info.sh
            and not info.lk and not info.fav then
            local count=tonumber(info._am or row._am) or 1
            if info.pt==1 or info.pt=="1" then
                goldBySpecies[info.id]=(goldBySpecies[info.id] or 0)+count
            elseif info.pt==nil or info.pt==false or info.pt==0 then
                regular[#regular+1]={uid=uid,id=info.id,amount=count}
            end
        end
    end
    local pending=state.rainbowPrepPending
    if pending then
        if now()-pending.sent<6 then return false end
        local latest=saveData(true)
        local after=0
        local inventory=latest and latest.Inventory and latest.Inventory.Pet
        if type(inventory)=="table" then
            for _,row in pairs(inventory) do
                local info=type(row)=="table" and (row._data or row) or nil
                if type(info)=="table" and info.id==pending.species
                    and (info.pt==1 or info.pt=="1") and not info.sh then
                    after=after+(tonumber(info._am or row._am) or 1)
                end
            end
        end
        if after>pending.before then
            state.rainbowPrepCredited=state.rainbowPrepCredited+(after-pending.before)
            state.rainbowPrepLast="Verified "..(after-pending.before).." new gold best-egg pets"
            state.rainbowPrepNext=now()+1
            log(state.rainbowPrepLast,"RAINBOW")
        else
            state.rainbowPrepLast="Gold prerequisite not verified; pausing to protect pets"
            state.rainbowPrepRetryAt=now()+180
            state.rainbowPrepNext=state.rainbowPrepRetryAt
        end
        state.rainbowPrepPending=nil
        return false
    end
    if now()<state.rainbowPrepRetryAt or now()<state.rainbowPrepNext then return false end
    local chosen,outputs,bestScore=nil,0,-math.huge
    local reserve=math.max(0,tonumber(Config.ConversionPetReserve) or 10)
    for _,pet in ipairs(regular) do
        local existing=goldBySpecies[pet.id] or 0
        local need=math.max(0,10-(existing%10))
        if existing%10==0 then need=10 end
        local possible=math.floor((pet.amount-reserve)/10)
        local batch=math.max(0,math.min(need,possible,
            math.max(1,tonumber(Config.RainbowGoldBatchMax) or 10)))
        -- VY: finish the existing partial stack of the SAME pet species first.
        -- This wastes fewer separate gold stacks than selecting the largest batch.
        local score=(existing%10>0 and 1000 or 0)+batch*10+existing%10
        if batch>0 and score>bestScore then
            chosen,outputs,bestScore=pet,batch,score
        end
    end
    if not chosen then
        state.rainbowPrepLast="Waiting for best-egg regular pets to prepare 10 matching gold pets"
        state.rainbowPrepNext=now()+8
        return false
    end
    if not movementAvailable("rainbow") then return false end
    local marker,msg=loadedTechMachine()
    if not marker then
        state.rainbowPrepLast=msg or "Supercomputer unavailable"
        state.rainbowPrepNext=now()+15
        return false
    end
    if not leaseMovement("rainbow",9) then return false end
    local root=currentRoot()
    if not root then clearMovement("rainbow");return false end
    local previous=root.CFrame
    if (root.Position-marker.Position).Magnitude>12 then
        local moved=pcall(function() root.CFrame=marker.CFrame+Vector3.new(0,4,0) end)
        if not moved then clearMovement("rainbow");return false end
        task.wait(0.5)
    end
    if (root.Position-marker.Position).Magnitude>18 then
        clearMovement("rainbow")
        state.rainbowPrepLast="Cannot reach verified Supercomputer"
        state.rainbowPrepNext=now()+15
        return false
    end
    local called,response=network("GoldMachine_Activate",{chosen.uid,outputs},true)
    state.rainbowPrepAttempts=state.rainbowPrepAttempts+1
    pcall(function() root.CFrame=previous end)
    clearMovement("rainbow")
    state.rainbowPrepLast="Prerequisite GoldMachine_Activate "..tostring(outputs)
        .." best-egg gold outputs; response="..describe(response)
    state.rainbowPrepNext=now()+8
    if called and response~=false then
        state.rainbowPrepPending={species=chosen.id,before=goldBySpecies[chosen.id] or 0,
            sent=now(),outputs=outputs}
    else
        state.rainbowPrepRetryAt=now()+120
        state.rainbowPrepLast=state.rainbowPrepLast.." (rejected; backing off)"
    end
    return called and response~=false
end

-- Rainbow crafting is supported by the user's decompiled source:
-- RainbowMachine_Activate(goldPetUID, outputCount). One rainbow output consumes
-- 10 golden pets. Off by default and credit-verified, like gold conversion.
local function tryRainbowConversion()
    if state.rankStage and state.rankStage.ready then return false end
    if not (Config.AutoRainbowConversion and state.running and Config.AutoRank
        and Config.AutoParallelQuests) then return false end
    -- Server quest credit can arrive AFTER our first timeout. If the actual
    -- quest counter later advanced, permit another cautious request sooner.
    for _,g in ipairs(state.goals or {}) do
        if g.kind=="convert" and g.title:lower():find("rainbow",1,true)
            and g.title:lower():find("best egg",1,true) then
            if state.rainbowLastGoalProgress and g.progress>state.rainbowLastGoalProgress
                and not state.rainbowPending then
                state.rainbowRetryAt=0
                state.rainbowNext=math.min(state.rainbowNext or 0,now()+2)
                state.rainbowValidated=state.rainbowValidated or
                    ((state.rainbowAttempts or 0)>0 and
                    now()-(state.rainbowLastRequestAt or 0)<40)
                state.rainbowLast="Late rainbow quest credit observed; resuming conversions"
            end
            state.rainbowLastGoalProgress=g.progress
            break
        end
    end
    if now()<(state.rainbowNext or 0) then return false end
    local goal
    for _,g in ipairs(state.goals) do
        if g.kind=="convert" and g.title:lower():find("rainbow",1,true)
            and g.title:lower():find("best egg",1,true) then goal=g;break end
    end
    if state.rainbowPending then
        local pending=state.rainbowPending
        if now()-pending.sent<6 then return false end
        local data=saveData(true)
        local current
        if data then
            for _,g in ipairs(readGoals(data)) do
                if g.identity==pending.identity or (pending.uid and g.uid==pending.uid)
                    or (pending.key and g.key==pending.key and g.kind=="convert"
                        and g.title:lower():find("rainbow",1,true)) then
                    current=g;break
                end
            end
        end
        local gained=current and math.max(0,current.progress-pending.before) or 0
        local questGone=current==nil
        local starsNow=data and tonumber(data.RankStars)
        local completedNow=data and tonumber(data.GoalsCompleted)
        local rankAwarded=questGone and ((starsNow and pending.starsBefore
            and starsNow>pending.starsBefore) or (completedNow
            and pending.completedBefore and completedNow>pending.completedBefore))
        if gained>0 or rankAwarded then
            local credited=gained>0 and gained or (pending.outputs or 1)
            state.rainbowCredited=state.rainbowCredited+credited
            state.rainbowValidated=true
            if current and current.identity~=pending.identity then
                state.rainbowStableIdentityFixes=state.rainbowStableIdentityFixes+1
            end
            state.rainbowLast="Rainbow pets: verified +"..credited
                ..(rankAwarded and " (quest completed)" or " (quest counter)")
            state.rainbowRetryAt=0
            state.rainbowNext=now()+0.7
        elseif now()-pending.sent<18 then
            -- Give saved quest and inventory data time to replicate before
            -- declaring failure on a successful-but-delayed machine response.
            return false
        else
            state.rainbowLast="Rainbow request uncredited after 18s; paused to protect pets/diamonds"
            state.rainbowRetryAt=now()+60
            state.rainbowNext=state.rainbowRetryAt
        end
        state.rainbowPending=nil
        return false
    end
    if not goal then return false end
    if now()<state.rainbowRetryAt or not movementAvailable("rainbow") then return false end
    local egg=findEgg()
    if not egg or type(egg.pets)~="table" then
        state.rainbowLast="Best egg species metadata unavailable; no pets spent"
        state.rainbowNext=now()+45
        return false
    end
    local species={}
    for _,row in pairs(egg.pets) do
        if type(row)=="table" and type(row[1])=="string" then
            species[row[1]]=true
        end
    end
    if not next(species) then
        state.rainbowLast="No recognized pet IDs in best egg definition"
        state.rainbowNext=now()+45
        return false
    end
    local data=saveData()
    local pets=data and data.Inventory and data.Inventory.Pet
    local chosen=nil
    if type(pets)=="table" then
        for uid,row in pairs(pets) do
            local info=type(row)=="table" and (row._data or row) or nil
            if type(info)=="table" and species[info.id]
                and (info.pt==1 or info.pt=="1") and not info.sh
                and not info.lk and not info.fav then
                local amount=tonumber(info._am or row._am) or 1
                if amount>=10 and (not chosen or amount>chosen.amount) then
                    chosen={uid=uid,id=info.id,amount=amount}
                end
            end
        end
    end
    -- A gold prerequisite may have completed while inventory is replicating.
    -- Verify that craft before consuming the new gold pets for rainbow.
    if state.rainbowPrepPending then
        return tryPrepareRainbowGold(goal,species,data)
    end
    if not chosen then
        state.rainbowLast="No stack of 10 GOLD best-egg pets; preparing materials"
        if Config.AutoGoldForRainbow then
            local started=tryPrepareRainbowGold(goal,species,data)
            state.rainbowNext=now()+2
            return started
        end
        state.rainbowNext=now()+20
        return false
    end
    local marker,msg=loadedTechMachine()
    if not marker then
        state.rainbowLast=msg or "Supercomputer not loaded"
        state.rainbowNext=now()+18
        return false
    end
    if not leaseMovement("rainbow",8) then return false end
    local root=currentRoot()
    if not root then clearMovement("rainbow");return false end
    local previous=root.CFrame
    if (root.Position-marker.Position).Magnitude>12 then
        local moved=pcall(function() root.CFrame=marker.CFrame+Vector3.new(0,4,0) end)
        if not moved then clearMovement("rainbow");return false end
        task.wait(0.5)
    end
    if (root.Position-marker.Position).Magnitude>18 then
        clearMovement("rainbow")
        state.rainbowLast="Cannot reach verified Supercomputer"
        state.rainbowNext=now()+15
        return false
    end
    local remaining=math.max(1,(goal.required or 0)-(goal.progress or 0))
    local maxBatch=math.max(1,tonumber(Config.RainbowMaxOutputBatch) or 10)
    -- Test one conversion first. After actual quest credit, batch future
    -- requests to avoid thirty separate machine visits for thirty pets.
    local outputs=state.rainbowValidated
        and math.min(math.floor(chosen.amount/10),remaining,maxBatch) or 1
    local before=saveData(true)
    -- Do not spend on a stale quest that was already replaced by the server.
    local freshGoal=before and activeBestEggRainbowQuest(before)
    if not freshGoal then
        pcall(function() root.CFrame=previous end)
        clearMovement("rainbow")
        return false
    end
    -- Some older module wrappers return only true for quest presence.
    -- Prefer a full freshly parsed goal, but preserve the inspected snapshot.
    if type(freshGoal)~="table" then freshGoal=goal end
    local called,response=network("RainbowMachine_Activate",{chosen.uid,outputs},true)
    state.rainbowAttempts=state.rainbowAttempts+1
    state.rainbowLastRequestAt=now()
    pcall(function() root.CFrame=previous end)
    clearMovement("rainbow")
    state.rainbowLast="RainbowMachine_Activate "..tostring(outputs)
        .." outputs uid="..tostring(chosen.uid).." response="..describe(response)
    if called and response~=false then
        state.rainbowPending={identity=freshGoal.identity,uid=freshGoal.uid,
            key=freshGoal.key,before=freshGoal.progress,sent=now(),
            outputs=outputs,starsBefore=before and tonumber(before.RankStars),
            completedBefore=before and tonumber(before.GoalsCompleted)}
        state.rainbowNext=now()+6
    else
        state.rainbowLast=state.rainbowLast.." (rejected or unavailable; backing off)"
        state.rainbowRetryAt=now()+180
        state.rainbowNext=state.rainbowRetryAt
    end
    return called and response~=false
end

-- Reversible client-only gain text suppression. The user's current PS99
-- client shows numbers like "703k" and "1.29k" WITHOUT a leading +.
-- Restrict anonymous numeric labels to workspace-anchored 3D billboards.
-- Do not hide quest counters, the player's balance, or reward collection.
local function popupIsAmount(txt)
    if type(txt)~="string" then return false end
    txt=txt:gsub(",",""):gsub("%s+","")
    return txt:match("^%+?%d+%.?%d*[kKmMbBtTqQ]?$" )~=nil
end
local function popupLooksLikePickup(node)
    if not (node:IsA("BillboardGui") or node:IsA("ScreenGui")) then return false end
    -- Explicit HUD safety: ScreenGui needs a very specific gain/pickup name.
    local path=node.Name:lower()
    local parent=node.Parent
    for _=1,3 do
        if not parent then break end
        path=path.."/"..parent.Name:lower()
        parent=parent.Parent
    end
    local gainName=path:find("pickup",1,true) or path:find("floating",1,true)
        or path:find("gain",1,true) or path:find("popup",1,true)
    local currencyName=path:find("currency",1,true) or path:find("coin",1,true)
        or path:find("diamond",1,true) or path:find("loot",1,true)
        or path:find("reward",1,true) or path:find("drop",1,true)
    if node:IsA("ScreenGui") then
        return not not (gainName and currencyName)
    end
    local playerGui=LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui and node:IsDescendantOf(playerGui) and not gainName then return false end
    if not node:IsDescendantOf(Workspace) and not gainName then return false end
    if gainName and currencyName then return true end
    local amount,icon=false,false
    local labels=0
    for _,child in ipairs(node:GetDescendants()) do
        if child:IsA("TextLabel") then
            labels=labels+1
            if labels>14 then return false end -- not a temporary popup
            if popupIsAmount(child.Text) then amount=true end
        elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
            icon=true
        end
    end
    -- Require an amount AND a pickup icon for ambiguous numeric 3D labels;
    -- do not hide floating NPC names or chest health readouts.
    return amount and icon
end
local function suppressPopup(node)
    if not Config.HidePickupPopups or not node or not node.Parent then return end
    if not popupLooksLikePickup(node) then return end
    if state.popupRecords[node]==nil then
        state.popupRecords[node]=node.Enabled
        state.popupHidden=state.popupHidden+1
    end
    local ok=pcall(function() node.Enabled=false end)
    if ok then state.popupLastStatus="Hidden pickup overlay: "..node.Name end
end
local function checkPopupAfterCreation(node)
    if not node or state.popupPending[node] then return end
    state.popupPending[node]=true
    -- Some scripts create BillboardGui first and add text/images a tick later.
    task.delay(0.07,function()
        state.popupPending[node]=nil
        if not state.shutdown then pcall(suppressPopup,node) end
    end)
end
local function refreshPopups(force)
    if not Config.HidePickupPopups then return end
    if not force and now()-state.popupLastScan<45 then return end
    state.popupLastScan=now()
    local roots={LocalPlayer:FindFirstChild("PlayerGui")}
    local things=findChild(Workspace,"__THINGS")
    if things then
        for _,folder in ipairs(things:GetChildren()) do
            local name=folder.Name:lower()
            if name:find("popup",1,true) or name:find("effect",1,true)
                or name:find("floating",1,true) or name:find("notification",1,true)
                or name:find("pickup",1,true) then roots[#roots+1]=folder end
        end
    end
    for _,r in ipairs(roots) do
        if r then
            for _,node in ipairs(r:GetDescendants()) do
                if node:IsA("BillboardGui") or node:IsA("ScreenGui") then
                    pcall(suppressPopup,node)
                end
            end
        end
    end
end
local function restorePopups()
    for gui,enabled in pairs(state.popupRecords) do
        pcall(function() if gui.Parent then gui.Enabled=enabled end end)
        state.popupRecords[gui]=nil
    end
    state.popupHidden=0
    state.popupLastStatus="Restored prior GUI visibility"
end
local function bindPopupListeners()
    if state.popupBound then return end
    state.popupBound=true
    local function onAdded(node)
        if not Config.HidePickupPopups then return end
        if node:IsA("BillboardGui") or node:IsA("ScreenGui") then
            pcall(suppressPopup,node)
            checkPopupAfterCreation(node)
        elseif node:IsA("TextLabel") or node:IsA("ImageLabel") then
            local parent=node.Parent
            for _=1,5 do
                if not parent then break end
                if parent:IsA("BillboardGui") then
                    checkPopupAfterCreation(parent)
                    break
                end
                parent=parent.Parent
            end
        end
    end
    -- Workspace listener catches transient 3D pickup billboards regardless
    -- of the actual effects folder; the filter never scans all breakables.
    for _,r in ipairs({LocalPlayer:FindFirstChild("PlayerGui"), Workspace}) do
        if r then
            table.insert(state.connections,r.DescendantAdded:Connect(onAdded))
        end
    end
    refreshPopups(true)
end

-- VY v1.0.0 local workspace re-exec after a REAL place teleport.
-- Requires a user-supplied local file; never fetches code from a web URL.
local function vyQueueLocalReexecution()
    if state.vyWorldQueued then return true end
    if type(queue_on_teleport)~="function" or type(isfile)~="function"
        or type(readfile)~="function" or type(loadstring)~="function" then
        state.vyWorldTravelLast="Potassium queue_on_teleport / workspace file APIs unavailable"
        return false
    end
    local filename=Config.VYLocalWorkspaceFile
    if type(filename)~="string" or filename=="" then return false end
    local good,exists=pcall(isfile,filename)
    if not good or not exists then
        state.vyWorldTravelLast="Save this complete script to executor workspace as "..filename
        return false
    end
    local payload=string.format([[
        local file=%q
        local ok,err=pcall(function()
            local source=readfile(file)
            local chunk,loaderr=loadstring(source)
            assert(chunk,loaderr)
            chunk()
        end)
        if not ok then warn("[RankPilot VY reexec] "..tostring(err)) end
    ]],filename)
    local queued,err=pcall(queue_on_teleport,payload)
    if queued then
        state.vyWorldQueued=true
        state.vyWorldTravelLast="Local workspace continuation queued for "..filename
        return true
    end
    state.vyWorldTravelLast="queue_on_teleport failed: "..tostring(err)
    return false
end

local function vyTravelWorld(worldNumber)
    local number=math.floor(tonumber(worldNumber) or 0)
    if not Config.VYWorldTravel or number<1 or number>4 then return false end
    if number==state.world.number then return false end
    if now()-(state.vyWorldTravelAt or -math.huge)
        <math.max(60,tonumber(Config.VYWorldTravelCooldown) or 90) then return false end
    if not vyQueueLocalReexecution() then return false end
    state.vyWorldTravelAt=now()
    state.vyWorldAttempted=number
    local ok,result=network("World"..number.."Teleport",{},true)
    state.vyWorldTravelLast="World"..number.."Teleport request: "..tostring(result)
    if not ok or result==false then
        state.vyWorldQueued=false
        state.vyWorldTravelLast=state.vyWorldTravelLast.." (failed, cooldown applies)"
    end
    return ok and result~=false
end

-- v5.2: rebirth is checked independently of the next-gate purchase, which
-- previously returned early (all zones owned / unaffordable / other world)
-- exactly when a rebirth is due. Still OFF by default (AutoRebirth=false).
local function tryRebirth()
    if not Config.AutoRebirth or not healthy("rebirth") then return false end
    local c=state.clients
    local ok2,rebirth=callMethod(c.RebirthCmds,"GetNextRebirth")
    if not ok2 or type(rebirth)~="table" then return false end
    local current=getZoneInfo()
    local required=tonumber(rebirth.ZoneNumberRequired)
    local number=rebirth.RebirthNumber or rebirth._id
    if not (current and current.number and required and current.number>=required and number) then
        state.rebirthLast="Next rebirth needs area "..tostring(required).." (current "..tostring(current and current.number)..")"
        return false
    end
    local data=saveData(true)
    local before=data and tonumber(data.Rebirths)
    if attemptNetwork("rebirth","Rebirth_Request",{tostring(number)},true,80) then
        state.rebirthLast="Rebirth "..tostring(number).." requested; checking save"
        log("Rebirth request: "..tostring(number).." (rebirths before="..tostring(before)..")","WORLD")
        task.delay(6,function()
            local after=saveData(true)
            local count=after and tonumber(after.Rebirths)
            state.rebirthLast=(before and count and count>before) and ("Rebirth confirmed: "..tostring(count))
                or ("Rebirth not confirmed by Save (rebirths="..tostring(count)..")")
        end)
        return true
    end
    return false
end
local function tryAdvanceWorld()
    if not healthy("zone") then return false end
    if now()-state.lastWorldCheck<Config.WorldCheckSeconds then return false end
    state.lastWorldCheck=now()
    if Config.AutoRebirth then pcall(tryRebirth) end
    local c=state.clients
    local ok,name=callMethod(c.ZoneCmds,"GetNextZone")
    if not ok or type(name)~="string" or name=="" then
        state.worldTransition="No next purchasable area returned in World "..describe(state.world.number)
        return false
    end
    local dir=c.Directory and c.Directory.Zones
    local zoneData=dir and dir[name]
    local targetWorld=zoneWorld(name,zoneData)
    local active=state.world and state.world.number
    if targetWorld and active and targetWorld~=active then
        state.worldTransition="Next area '"..name.."' is in World "..targetWorld
            .."; move to that world through the in-game portal"
        if cooldownReady("world:transition",60) then log(state.worldTransition,"WORLD") end
        if Config.VYWorldTravel then vyTravelWorld(targetWorld) end
        return false
    end
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
    return accepted
end

-- Optional game-native teleports for owned areas that are not streamed in.
-- Source: the uploaded DZ Hub calls Teleports_RequestTeleport(zoneName).
-- This is not a verified cross-place world-transition API.
local function requestLocalZoneTeleport(zoneName)
    if not Config.AutoZoneTeleports then return false end
    if now()-state.lastWorldTeleport<75 then return false end
    local targetWorld=zoneWorld(zoneName)
    if targetWorld and state.world.number and targetWorld~=state.world.number then
        state.worldTransition="Different world required; native zone teleport not attempted"
        return false
    end
    local ownsOk,owned=callMethod(state.clients.ZoneCmds,"Owns",zoneName)
    if not ownsOk or owned~=true then
        state.worldTransition="Native teleport skipped: destination ownership not verified"
        return false
    end
    state.lastWorldTeleport=now()
    local accepted=attemptNetwork("zone-teleport","Teleports_RequestTeleport",{zoneName},true,75)
    state.worldTransition=accepted and "Native game teleport requested to "..zoneName
        or "Game teleport rejected or unavailable for "..zoneName
    log(state.worldTransition,"WORLD")
    return accepted
end

-- Reward thresholds can be cumulative. Source: DZ Hub ranksPending().
-- Uses the current rank ID from RanksUtil, instead of indexing only by integer rank.
local function pendingRankRewardIds(rankData, redeemed, stars)
    if type(rankData)~="table" or type(rankData.Rewards)~="table" then return {} end
    local out, total = {}, 0
    for idx, reward in ipairs(rankData.Rewards) do
        local required=type(reward)=="table" and tonumber(reward.StarsRequired) or nil
        if not required or required<0 then break end
        if type(reward)=="table" then
            total=total+required
            if total<=stars and not redeemed[tostring(idx)] and not redeemed[idx] then
                out[#out+1]=idx
            end
        end
    end
    return out
end
local function claimRankRewards()
    if not healthy("claim") or state.rankConflict then return end
    -- When star track is already full, reduce the reward-claming latency.
    -- Individual network requests remain rate-limited by attemptNetwork.
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
    if state.rewardClaimRank~=rank then state.rewardClaimRank=rank;state.rewardClaimTries={} end
    if not idx then return end
    -- v5.2: after 3 unconfirmed claims of the same reward, retry once a minute
    -- (VY AutoRank uses the same back-off) instead of every 4 seconds.
    state.rewardClaimTries=state.rewardClaimTries or {}
    local tries=state.rewardClaimTries[idx] or {count=0,at=-math.huge}
    if tries.count>=3 and now()-tries.at<60 then return end
    if attemptNetwork("claim","Ranks_ClaimReward",{idx},false,4) then
        tries.count=tries.count+1;tries.at=now()
        state.rewardClaimTries[idx]=tries
        log("Rank reward claim request "..tostring(idx).." (attempt "..tries.count..")","REWARD")
    end
end

local function diamonds()
    local ok,n=callMethod(state.clients.CurrencyCmds,"Get","Diamonds")
    return (ok and tonumber(n)) or nil
end
local function buySlot(kind)
    if not healthy("slots") then return false end
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
    if not healthy("equip") then return end
    if now()-state.lastEquip<Config.EquipCheckSeconds then return end
    state.lastEquip=now()
    local ok,_=callMethod(state.clients.PetCmds,"EquipBest")
    if not ok and cooldownReady("equipMissing",90) then
        log("PetCmds.EquipBest unavailable (source DZ Hub)","WAIT")
    end
end
local function extraProgression()
    if Config.AutoEquipBest then equipBest() end
    if now()-state.lastSlots>=Config.SlotCheckSeconds then
        state.lastSlots=now()
        if Config.AutoPetSlots then buySlot("pet") end
        if Config.AutoEggSlots then buySlot("egg") end
    end
end

local function claimFreeGift()
    if not healthy("freegifts") or not Config.AutoFreeGifts or now()-state.lastGifts<Config.GiftCheckSeconds then return end
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
-- v5.2: consumables are spent only while the quest moves. Uses are spaced
-- 2.5 s apart while unconfirmed, and 4 uses without any Save progress pause
-- that quest for 2 minutes instead of draining the stack.
local function consumeTracked(goal)
    state.consumeWatch=state.consumeWatch or {}
    local watch=state.consumeWatch[goal.identity]
    if watch and (goal.progress or 0)>watch.progress then
        watch=nil;state.consumeWatch[goal.identity]=nil
    end
    if watch then
        if watch.sent>=4 then
            state.consumeWatch[goal.identity]=nil
            blockGoal(goal,120,"no quest credit after 4 "..goal.kind.." uses")
            return false
        end
        if now()-watch.last<2.5 then return false end
    end
    local used=consume(goal)
    if used then
        watch=watch or {progress=goal.progress or 0,sent=0,last=0}
        watch.sent=watch.sent+1;watch.last=now()
        state.consumeWatch[goal.identity]=watch
    end
    return used
end
local function performGoal(goal)
    if not goal then return false end
    if goal.kind == "hatch" then return Config.AutoHatch and healthy("hatch") end -- separate worker executes hatching
    if goal.kind == "fruit" or goal.kind == "potion" or goal.kind == "flag" then
        return consumeTracked(goal)
    end
    if goal.kind == "collect_potion" or goal.kind == "collect_enchant" then
        return vendingForGoal(goal)
    end
    if goal.kind == "zone" then return tryAdvanceWorld() end
    if goal.kind == "rebirth" then return tryRebirth() end
    if itemTypes[goal.kind] then return spawnQuestObject(goal) end
    if goal.kind == "farm" or goal.kind == "diamond" or goal.kind == "minichest" or goal.kind == "safe" then
        if Config.FastFarm then return true end -- dedicated fast worker owns farm ticks
        return farm(goal)
    end
    return false
end

local function stop()
    pcall(function() if state.extras and state.extras.slingshot then state.extras.slingshot=false;network("Slingshot_Unequip",{},true) end end)
    pcall(function()
        local lighting=game:GetService("Lighting")
        for field,value in pairs(state.extras.lightOriginal or {}) do lighting[field]=value end
        state.extras.lightOriginal=nil
        Config.Fullbright=false
        for obj,entry in pairs(state.extras.visuals or {}) do
            if obj.Parent then
                if entry.kind=="local" then obj.LocalTransparencyModifier=entry.old
                elseif entry.kind=="enabled" then obj.Enabled=entry.old
                elseif entry.kind=="transparency" then obj.Transparency=entry.old end
            end
            state.extras.visuals[obj]=nil
        end
    end)
    state.running = false
    state.shutdown = true
    Config.Enabled = false
    state.status = "STOPPED"
    state.generations = state.generations + 1
    for _, conn in ipairs(state.connections) do pcall(function() conn:Disconnect() end) end
    state.connections = {}
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    petTurbo(false)
    state.vyPetAssignment={}
    updateSuperMagnet(false)
    skipEggAnimation(false)
    if state.upgradeVisitStart>0 then pcall(finishUpgradeVisit) end
    restorePopups()
    pcall(restoreLootbagVisuals)
    pcall(restorePetVisuals)
    if type(Modules.cleanupAll) == "function" then pcall(Modules.cleanupAll, "stop") end
    if state.gui then pcall(function() state.gui:Destroy() end) end
    environment.RankPilot = nil
    log("Controller stopped and disconnected", "SYSTEM")
end
local function pause(reason)
    pcall(function() if state.extras and state.extras.slingshot then state.extras.slingshot=false;network("Slingshot_Unequip",{},true) end end)
    Config.Enabled = false
    state.running = false
    state.status = reason or "PAUSED"
    if state.upgradeVisitStart>0 then pcall(finishUpgradeVisit) end
    petTurbo(false)
    updateSuperMagnet(false)
    skipEggAnimation(false)
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    if type(Modules.pauseAll) == "function" then pcall(Modules.pauseAll, reason) end
    persist()
    log("Paused", "SYSTEM")
end
local function recheck()
    state.failures = {}
    state.blocked = {}
    state.questWatch = {}
    state.hudRankAt = -math.huge
    refreshClients()
    inspectState()
    if type(Modules.recheckAll) == "function" then pcall(Modules.recheckAll) end
    log("Capabilities reloaded and temporary blocks cleared", "SYSTEM")
end
local function run()
    if state.shutdown then return end
    if not refreshClients() then
        state.status = "No readable Save interface"
        log("Cannot start: PS99 Save.Get not available in this client", "ERROR")
        return
    end
    if not inspectState() then
        state.status = "Save not ready: press RECHECK"
        return
    end
    if state.rankConflict then
        state.status = "SAVE/HUD RANK CONFLICT: copy report"
        log("Start blocked: visible rank differs from game Save.Get rank", "SAFEGUARD")
        return
    end
    state.running = true
    Config.Enabled = true
    state.lastProgressAt = now()
    petTurbo(true)
    updateSuperMagnet(true)
    skipEggAnimation(true)
    if type(Modules.startAll) == "function" then pcall(Modules.startAll) end
    log("Rank controller enabled", "SYSTEM")
    persist()
end


-- ============================================================================
-- RANKPILOT X v5.1 ADDITIONAL FEATURES
-- The game actions below originate in the user's readable DZ Hub sample.
-- Requests are gated, throttled, opt-in and logged as attempts until confirmed.
-- Cosmetic optimization never destroys a model or collectible UID.
-- ============================================================================
local function extraAlert(message)
    if not Config.LocalNotifications then return end
    local alerts=state.extras.alerts
    table.insert(alerts,1,os.date("%H:%M:%S").."  "..tostring(message))
    while #alerts>12 do table.remove(alerts) end
end

local function inspectMinigameCapabilities()
    local library=ReplicatedStorage:FindFirstChild("Library")
    local clients=library and library:FindFirstChild("Client")
    if not clients then return "PS99 client folder missing" end
    local names={"FishingCmds","AdvancedFishingCmds","DigsiteCmds",
        "AdvancedDigsiteCmds","InstancingCmds","MinigameCmds","SpinnyWheelCmds",
        "DaycareCmds","MailboxCmds","UltimateCmds","LootboxCmds"}
    local found={}
    for _,name in ipairs(names) do
        if clients:FindFirstChild(name) then table.insert(found,name) end
    end
    local msg=#found>0 and table.concat(found,", ") or "none of the sampled modules loaded"
    state.extras.capabilityLast=msg
    return msg
end

local function inspectInventoryCounts()
    local data=saveData(true)
    if not data or type(data.Inventory)~="table" then
        state.extras.inventoryLast="Inventory unavailable"
        return state.extras.inventoryLast
    end
    local categories={"Pet","Potion","Enchant","Fruit","Misc","Lootbox","Gift"}
    local res={}
    for _,cat in ipairs(categories) do
        local rows=data.Inventory[cat]
        if type(rows)=="table" then
            local stacks,total=0,0
            for _,entry in pairs(rows) do
                if type(entry)=="table" then
                    stacks=stacks+1
                    total=total+math.max(0,tonumber(entry._am) or 1)
                end
            end
            res[#res+1]=cat.." "..stacks.." stacks / "..math.floor(total).." items"
        end
    end
    state.extras.inventoryLast=#res>0 and table.concat(res," | ") or "No inspected categories found"
    return state.extras.inventoryLast
end

-- Login streak: fail closed unless the game's own CanClaim returns true.
local function claimLoginStreak()
    local ex=state.extras
    if not Config.AutoLoginStreak or now()<ex.loginNext then return false end
    ex.loginNext=now()+math.max(45,tonumber(Config.LoginCheckSeconds) or 75)
    local commands=state.clients.LoginStreakCmds
    local checked,available=callMethod(commands,"CanClaim")
    if not checked or available~=true then
        ex.loginLast=checked and "not ready according to CanClaim()" or "LoginStreakCmds.CanClaim unavailable"
        return false
    end
    local sent,response=network("Login Streaks: Claim",{},true)
    if not sent or response==false then
        ex.loginLast="server refused streak claim: "..tostring(response)
        return false
    end
    ex.loginLast="claim sent; awaiting server state"
    task.wait(0.5)
    local verified,stillAvailable=callMethod(commands,"CanClaim")
    if verified and stillAvailable==false then
        ex.loginClaims=ex.loginClaims+1
        ex.loginLast="confirmed claimed by CanClaim()"
        extraAlert("Daily login streak claimed")
        return true
    end
    ex.loginLast="request accepted but NOT verified"
    ex.loginNext=now()+120
    return false
end

-- Timed rewards use Directory.TimedRewards, TimedRewardTimestamps, MachineCmds.GetModels
-- and DailyRewards_Redeem, as observed in the DZ Hub reference.
local function timedRewardCandidates(data)
    local directory=state.clients.Directory
    local defs=directory and directory.TimedRewards
    local stamps=data and data.TimedRewardTimestamps
    if type(defs)~="table" or type(stamps)~="table" then return {} end
    local serverNow=os.time()
    pcall(function() serverNow=Workspace:GetServerTimeNow() end)
    local list={}
    for key,def in pairs(defs) do
        if type(key)=="string" and type(def)=="table"
            and key~="GroupRewards" and key~="SocialRewards" and key~="VIPRewards" then
            local cooldown=tonumber(def.Cooldown)
            local prev=tonumber(stamps[key])
            if cooldown and cooldown>=0 and (not prev or serverNow-prev>=cooldown) then
                list[#list+1]={id=key,def=def,stamp=prev}
            end
        end
    end
    table.sort(list,function(a,b) return a.id<b.id end)
    return list
end

local function findTimedMachineSpot(def)
    local machines=state.clients.MachineCmds
    if type(def.MachineName)~="string" then return nil end
    local ok,models=callMethod(machines,"GetModels",def.MachineName)
    if not ok or type(models)~="table" then return nil end
    for _,model in pairs(models) do
        if typeof(model)=="Instance" and model.Parent then
            local pad=model:FindFirstChild("Pad",true)
            if pad and pad:IsA("BasePart") then return pad.Position end
            local good,pivot=pcall(function() return model:GetPivot() end)
            if good and typeof(pivot)=="CFrame" then return pivot.Position end
        end
    end
    return nil
end

local function claimTimedReward()
    local ex=state.extras
    if not Config.AutoTimedRewards or now()<ex.timedNext then return false end
    ex.timedNext=now()+math.max(40,tonumber(Config.TimedCheckSeconds) or 80)
    local data=saveData(true)
    local list=timedRewardCandidates(data)
    if #list==0 then ex.timedLast="no verified ready timed rewards";return false end
    if not movementAvailable("timed-reward") then
        ex.timedLast="waiting for movement lease"
        ex.timedNext=now()+12
        return false
    end
    for _,item in ipairs(list) do
        local pos=findTimedMachineSpot(item.def)
        local root=currentRoot()
        if pos and root and leaseMovement("timed-reward",14) then
            local before=root.CFrame
            local moved=true
            if (root.Position-pos).Magnitude>16 then
                moved=pcall(function() root.CFrame=CFrame.new(pos+Vector3.new(0,4,0)) end)
                if moved then task.wait(0.7) end
            end
            local inRange=moved and root.Parent and (root.Position-pos).Magnitude<=22
            local sent,response=false,"machine out of range"
            if inRange and state.running and Config.AutoTimedRewards then
                sent,response=network("DailyRewards_Redeem",{item.id},true)
            end
            pcall(function() if root.Parent then root.CFrame=before end end)
            clearMovement("timed-reward")
            if sent and response~=false then
                local updated=saveData(true)
                local nextStamp=updated and updated.TimedRewardTimestamps
                    and tonumber(updated.TimedRewardTimestamps[item.id])
                if nextStamp and (not item.stamp or nextStamp>item.stamp) then
                    ex.timedClaims=ex.timedClaims+1
                    ex.timedLast="confirmed "..item.id
                    extraAlert("Timed reward claimed: "..item.id)
                    return true
                end
                ex.timedLast="claim requested, waiting for server confirmation: "..item.id
                return false
            end
            ex.timedLast="request failed "..item.id..": "..tostring(response)
            return false
        end
    end
    ex.timedLast=tostring(#list).." ready, but no reachable machine in this world"
    return false
end

-- Player upgrades are independent of rank-quest potion/enchant upgrades.
-- The module API and data fields were observed in the uploaded DZ source.
local function buyAffordablePlayerUpgrade()
    local ex=state.extras
    if not Config.AutoPlayerUpgrades or now()<ex.playerUpgradeNext then return false end
    ex.playerUpgradeNext=now()+65
    local commands=state.clients.UpgradeCmds
    local directory=state.clients.Directory
    if not commands or not directory or type(directory.Upgrades)~="table" then
        ex.playerUpgradeLast="UpgradeCmds or Directory.Upgrades missing"
        return false
    end
    local listed,upgrades=callMethod(commands,"All")
    if not listed or type(upgrades)~="table" then
        ex.playerUpgradeLast="UpgradeCmds.All() unavailable"
        return false
    end
    if not movementAvailable("player-upgrade") then
        ex.playerUpgradeLast="waiting for movement lease"
        ex.playerUpgradeNext=now()+15
        return false
    end
    for _,upgrade in pairs(upgrades) do
        if type(upgrade)=="table" and upgrade.UpgradeID~=nil and upgrade.ZoneID~=nil then
            local can,ready=callMethod(commands,"CanInteractWith",upgrade.UpgradeID,upgrade.ZoneID)
            if can and ready==true then
                local definition=directory.Upgrades[upgrade.UpgradeID]
                local tier=tonumber(upgrade.UpgradeTier)
                local cost=tier and definition and definition.TierCosts
                    and tonumber(definition.TierCosts[tier])
                local currency=tier and definition and definition.TierCurrencies
                    and definition.TierCurrencies[tier]
                local balanceOK,balance=callMethod(state.clients.CurrencyCmds,"Get",currency)
                local spare=tonumber(balance)
                if type(currency)=="string" and cost and cost>=0 and balanceOK
                    and spare and spare>0 and cost<=spare*math.clamp(Config.PlayerUpgradeSpendFraction,0,0.5) then
                    if not leaseMovement("player-upgrade",12) then return false end
                    local root=currentRoot()
                    local previous=root and root.CFrame
                    local moved=true
                    if root and typeof(upgrade.Model)=="Instance" and upgrade.Model.Parent then
                        local ok,point=pcall(function() return upgrade.Model:GetPivot().Position end)
                        if ok and typeof(point)=="Vector3" and (root.Position-point).Magnitude>18 then
                            moved=pcall(function() root.CFrame=CFrame.new(point+Vector3.new(0,5,0)) end)
                            if moved then task.wait(0.6) end
                        end
                    end
                    local purchased,value=false,"unavailable"
                    if moved and root and state.running and Config.AutoPlayerUpgrades then
                        purchased,value=callMethod(commands,"Purchase",upgrade.UpgradeID,upgrade.ZoneID)
                    end
                    if previous and root and root.Parent then
                        pcall(function() root.CFrame=previous end)
                    end
                    clearMovement("player-upgrade")
                    if purchased and value~=false then
                        local checked,latest=callMethod(commands,"All")
                        local confirmed=false
                        if checked and type(latest)=="table" then
                            for _,after in pairs(latest) do
                                if type(after)=="table" and after.UpgradeID==upgrade.UpgradeID
                                    and after.ZoneID==upgrade.ZoneID
                                    and tonumber(after.UpgradeTier)
                                    and tonumber(after.UpgradeTier)>tier then
                                    confirmed=true;break
                                end
                            end
                        end
                        if confirmed then
                            ex.playerUpgradeConfirmed=ex.playerUpgradeConfirmed+1
                            ex.playerUpgradeLast="confirmed "..tostring(upgrade.UpgradeID).." tier "..tostring(tier)
                            extraAlert("Player upgrade confirmed: "..tostring(upgrade.UpgradeID))
                            return true
                        end
                        ex.playerUpgradeLast="request accepted, not yet confirmed: "..tostring(upgrade.UpgradeID)
                        return false
                    end
                    ex.playerUpgradeLast="upgrade refused: "..tostring(value)
                    return false
                end
            end
        end
    end
    ex.playerUpgradeLast="no affordable eligible upgrades within budget"
    return false
end

local function applyFullbright()
    local ex=state.extras
    local lighting=game:GetService("Lighting")
    if Config.Fullbright and not ex.lightOriginal then
        local old={}
        local ok=pcall(function()
            for _,field in ipairs({"Brightness","ClockTime","FogEnd","GlobalShadows","Ambient"}) do
                old[field]=lighting[field]
            end
        end)
        if not ok then return end
        ex.lightOriginal=old
    end
    if Config.Fullbright then
        pcall(function()
            lighting.Brightness=2
            lighting.ClockTime=12
            lighting.FogEnd=1000000
            lighting.GlobalShadows=false
            lighting.Ambient=Color3.fromRGB(178,178,178)
        end)
    elseif ex.lightOriginal then
        pcall(function()
            for field,value in pairs(ex.lightOriginal) do lighting[field]=value end
        end)
        ex.lightOriginal=nil
    end
end

local function filteredBalloonList(data)
    local out={}
    if type(data)~="table" then return out end
    local types={
        ["Small Balloon"]=Config.BalloonSmall,
        ["Medium Balloon"]=Config.BalloonMedium,
        ["Huge Balloon"]=Config.BalloonHuge,
    }
    for _,b in pairs(data) do
        if type(b)=="table" and b.Popped~=true and b.Id~=nil
            and typeof(b.Position)=="Vector3" and types[b.BalloonTypeId]==true then
            out[#out+1]=b
        end
    end
    return out
end

local function unequipBalloonSlingshot()
    if not state.extras.slingshot then return end
    state.extras.slingshot=false
    pcall(function() network("Slingshot_Unequip",{},true) end)
end

local function popBalloon()
    local ex=state.extras
    if not Config.AutoPopBalloons then
        if ex.slingshot then unequipBalloonSlingshot() end
        return false
    end
    if now()<ex.balloonNext then return false end
    ex.balloonNext=now()+math.max(1.2,tonumber(Config.BalloonCheckSeconds) or 3)
    local data=saveData()
    local rebirths=data and tonumber(data.Rebirths)
    if not rebirths then
        local ok,v=callMethod(state.clients.RebirthCmds,"Get")
        if ok then rebirths=tonumber(v) end
    end
    if not rebirths or rebirths<3 then
        ex.balloonLast="requires 3 rebirths; current="..tostring(rebirths or "unknown")
        return false
    end
    if not ex.slingshot then
        local ok,result=network("Slingshot_Equip",{},true)
        if not ok or result==false then
            ex.balloonLast="cannot equip slingshot: "..tostring(result)
            ex.balloonNext=now()+30
            return false
        end
        ex.slingshot=true
    end
    local ok,list=network("BalloonGifts_GetActiveBalloons",{},true)
    if not ok then ex.balloonLast="active balloon request failed";return false end
    local balloons=filteredBalloonList(list)
    local root=currentRoot()
    if not root then ex.balloonLast="character unavailable";return false end
    for _,b in ipairs(balloons) do
        local key=tostring(b.Id)
        if now()>=(ex.balloonSeen[key] or 0) then
            local d=b.Position-root.Position
            local horizontal=Vector2.new(d.X,d.Z).Magnitude
            local azimuth=math.atan2(d.Z,d.X)
            local elevation=math.atan2(d.Y,math.max(0.001,horizontal))
            local fired,result=network("Slingshot_FireProjectile",
                {root.Position,azimuth,elevation,200},true)
            if fired and result~=false then
                local hit=network("BalloonGifts_BalloonHit",{b.Id},false)
                ex.balloonSeen[key]=now()+30
                if hit then
                    ex.balloonHits=ex.balloonHits+1
                    ex.balloonLast="hit REQUEST sent: "..key.." (awaiting server confirmation)"
                    extraAlert("Balloon hit requested: "..key)
                    ex.balloonNext=now()+math.max(1.2,tonumber(Config.BalloonHitCooldown) or 1.5)
                    return true
                end
                ex.balloonLast="slingshot fired but BalloonGifts_BalloonHit unavailable: "..key
                return false
            end
            ex.balloonLast="balloon fire refused: "..key
            ex.balloonSeen[key]=now()+15
            return false
        end
    end
    ex.balloonLast="no eligible balloons in current registry"
    return false
end

local function visuallyHideTree(root)
    local ex=state.extras
    local count=0
    local function hide(obj)
        if ex.visuals[obj] then return end
        local classVisual=obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture")
        local effect=obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail")
        if classVisual then
            local old
            local ok=pcall(function()
                old=obj:IsA("BasePart") and obj.LocalTransparencyModifier or obj.Transparency
            end)
            if ok then
                ex.visuals[obj]={kind=obj:IsA("BasePart") and "local" or "transparency",old=old}
                pcall(function()
                    if obj:IsA("BasePart") then obj.LocalTransparencyModifier=1
                    else obj.Transparency=1 end
                end)
                count=count+1
            end
        elseif effect then
            local ok,old=pcall(function() return obj.Enabled end)
            if ok then
                ex.visuals[obj]={kind="enabled",old=old}
                pcall(function() obj.Enabled=false end)
                count=count+1
            end
        end
    end
    hide(root)
    for _,node in ipairs(root:GetDescendants()) do
        hide(node)
        if count>=1100 then break end
    end
    return count
end

local function restoreAdditionalVisuals()
    for obj,entry in pairs(state.extras.visuals) do
        pcall(function()
            if obj.Parent then
                if entry.kind=="local" then obj.LocalTransparencyModifier=entry.old
                elseif entry.kind=="enabled" then obj.Enabled=entry.old
                elseif entry.kind=="transparency" then obj.Transparency=entry.old end
            end
        end)
        state.extras.visuals[obj]=nil
    end
end

local function refreshAdditionalVisuals()
    local ex=state.extras
    if now()<ex.visualNext then return end
    ex.visualNext=now()+12
    if not (Config.HideBalloonVisuals or Config.HideBreakableVisuals) then
        restoreAdditionalVisuals()
        ex.visualHidden=0
        return
    end
    -- v5.2: incremental. visuallyHideTree skips objects it already hid, so
    -- only new models are touched; everything is restored only when the
    -- enabled toggle combination changes (and on stop).
    local mode=tostring(Config.HideBalloonVisuals)..":"..tostring(Config.HideBreakableVisuals)
    if ex.visualMode~=mode then
        restoreAdditionalVisuals()
        ex.visualHidden=0
        ex.visualMode=mode
    end
    local things=Workspace:FindFirstChild("__THINGS")
    if not things then return end
    local maxModels=Config.LowLagMode and 40 or 110
    for _,folderName in ipairs({"BalloonGifts","Breakables"}) do
        local enabled=(folderName=="BalloonGifts" and Config.HideBalloonVisuals)
            or (folderName=="Breakables" and Config.HideBreakableVisuals)
        local folder=things:FindFirstChild(folderName)
        if enabled and folder then
            local models=folder:GetChildren()
            for i=1,math.min(#models,maxModels) do
                ex.visualHidden=ex.visualHidden+visuallyHideTree(models[i])
            end
        end
    end
end

local function extrasWorker(generation)
    local first=true
    while not state.shutdown and generation==state.generations do
        if first then
            state.extras.lastRankAlert=tonumber(state.rank)
            first=false
        end
        if state.running then
            local rank=tonumber(state.rank)
            if rank then
                if state.extras.lastRankAlert and rank>state.extras.lastRankAlert then
                    extraAlert("Rank advanced: "..state.extras.lastRankAlert.." → "..rank)
                end
                state.extras.lastRankAlert=rank
            end
            local ok1,err1=pcall(claimLoginStreak)
            if not ok1 and cooldownReady("extras:login-error",50) then
                state.extras.loginLast=tostring(err1);log("Login: "..tostring(err1),"EXTRAS")
            end
            local ok2,err2=pcall(claimTimedReward)
            if not ok2 and cooldownReady("extras:timed-error",50) then
                state.extras.timedLast=tostring(err2);log("Timed rewards: "..tostring(err2),"EXTRAS")
                clearMovement("timed-reward")
            end
            local ok4,err4=pcall(buyAffordablePlayerUpgrade)
            if not ok4 and cooldownReady("extras:player-upgrade-error",50) then
                state.extras.playerUpgradeLast=tostring(err4)
                clearMovement("player-upgrade")
            end
            local ok3,err3=pcall(popBalloon)
            if not ok3 and cooldownReady("extras:balloon-error",50) then
                state.extras.balloonLast=tostring(err3);log("Balloons: "..tostring(err3),"EXTRAS")
            end
        elseif state.extras.slingshot then
            unequipBalloonSlingshot()
        end
        if Config.HideBalloonVisuals or Config.HideBreakableVisuals then
            pcall(refreshAdditionalVisuals)
        elseif next(state.extras.visuals) then
            pcall(restoreAdditionalVisuals)
        end
        task.wait(1.1)
    end
    pcall(unequipBalloonSlingshot)
    pcall(restoreAdditionalVisuals)
    Config.Fullbright=false
    pcall(applyFullbright)
end

local function getReport()
    local c = state.clients
    local keys = {"Save", "QuestCmds", "ZoneCmds", "RankCmds", "PetCmds", "EggCmds", "PlayerPet", "BreakableFrontend", "ZonesUtil", "RanksUtil", "Directory", "Balancing",
        "PotionCmds", "FruitCmds", "ZoneFlagCmds", "RebirthCmds", "InventoryCmds"}
    local data = saveData()
    local rawGoals = data and data.Goals
    local goalCount = 0
    if type(rawGoals) == "table" then for _ in pairs(rawGoals) do goalCount = goalCount + 1 end end
    local report = {"RankPilot X v5.2 module hub / v5.1 engine, v4.6 VY automation engine plus v3.10 review",
        "World: "..describe(state.world.number).." ("..state.world.name..") via "..state.world.source,
        "Current World zone: "..describe(state.world.zone).." | Highest owned: "..describe(state.world.best),
        "Highest owned World: "..describe(state.world.bestWorld),
        "Loaded map roots: "..describe(state.worldMapCount),
        "Save/zone world mismatch: "..describe(state.worldSaveConflict),
        "World transition status: "..describe(state.worldTransition),
        "VY cross-world travel: "..tostring(Config.VYWorldTravel)
            .." | status: "..tostring(state.vyWorldTravelLast),
        "AutoZoneTeleports enabled: "..describe(Config.AutoZoneTeleports),
        "Auto-load best owned area: "..describe(Config.AutoLoadBestArea)
            .." | target: "..describe(state.bestAreaTarget),
        "Best-area travel: "..describe(state.bestAreaTravelStatus)
            .." | anchor moves: "..tostring(state.bestAreaAnchorMoves or 0)
            .." | game teleport attempts: "..tostring(state.bestAreaNativeRequests or 0),
        "Save.Get().Rank: " .. describe(data and data.Rank),
        "Visible HUD rank (candidate, may be missing): " .. describe(state.hudRank),
        "Save/HUD mismatch: " .. describe(state.rankConflict),
        "Save.Get().RankStars: " .. describe(data and data.RankStars),
        "Actual maximum rank via "..state.maxRankSource..": "..describe(state.maxRank),
        "Rank milestone: "..tostring(state.rankStage.status),
        "Rank stars total requirement: "..describe(state.rankStage.starsNeeded).." | Remaining "..describe(state.rankStage.starsLeft),
        "Pending rank reward claim IDs: "..table.concat(state.rankStage.pending,","),
        "Rank gate area: "..describe(state.rankStage.requiredZone).." | Rebirth shortfall: "..describe(state.rankStage.rebirthsMissing),
        "High-star planner: "..describe(Config.PreferHighStars).." | Extra weight: "..tostring(Config.StarPriorityWeight),
        "Save.Get().RecentWorld: " .. describe(data and data.RecentWorld),
        "Save.Get().MaximumAvailableEgg: " .. describe(data and data.MaximumAvailableEgg),
        "Save.Get().EggsHatched: " .. describe(data and data.EggsHatched),
        "AutoHatch: " .. describe(Config.AutoHatch) .. " | hatch quest active: " .. describe(state.hatchGoalActive),
        "Always hatch: " .. describe(Config.AutoHatchAlways) .. " | Skip animations: " .. describe(Config.SkipEggAnimations),
        "Hatch during farming probe: "..tostring(Config.HatchFarmRemoteProbe)
            .." | validated remote: "..tostring(state.hatchFarmRemoteSupported)
            .." | "..tostring(state.hatchFarmRemoteLast),
        "Skip animation installed: " .. describe(state.eggAnimation.installed),
        "Hatch requests: " .. tostring(state.attempts.hatch) .. " | independently verified eggs: " .. tostring(state.hatchConfirmed),
        "Hatch API: " .. tostring(state.hatchLastApi) .. " | Egg: " .. describe(state.hatchLastEgg),
        "Hatch last batch: " .. tostring(state.hatchLastQty) .. " | Current trial batch: " .. describe(state.hatchBatch),
        "Hatch last result: " .. tostring(state.hatchLastResult),
        "Hatch capacity source: " .. tostring(state.hatchCapacitySource),
        "Egg discovery: " .. tostring(state.eggDiscovery),
        "Egg candidates eligible: " .. tostring(state.eggWorldEligibleCount),
        "Egg unlock requests: " .. tostring(state.eggUnlockRequests)
            .. " | verified after hatch: " .. tostring(state.eggUnlockSuccess),
        "Egg unlock status: " .. tostring(state.eggUnlockStatus)
            .. " | evidence: " .. tostring(state.eggUnlockSource),
        "Egg unlock last: " .. tostring(state.eggUnlockLast),
        "Save.PurchasedEggs count: " .. tostring((function()
            local n=0
            if data and type(data.PurchasedEggs)=="table" then
                for _ in pairs(data.PurchasedEggs) do n=n+1 end
            end
            return n
        end)()),
        "Egg selected source: " .. tostring(state.eggSource),
        "EggsUtil fallback: " .. tostring(state.eggFallbackStatus),
        "Save.UnlockedEggs count: " .. tostring((function() local n=0; if data and type(data.UnlockedEggs)=="table" then for _ in pairs(data.UnlockedEggs) do n=n+1 end end; return n end)()),
        "Currency farming fallback: " .. describe(state.hatchNeedsCoins),
        "Save.Get().Rebirths: " .. describe(data and data.Rebirths),
        "Save.Get().Goals count: " .. describe(goalCount),
        "Rank cap (not RankCmds.GetMaxRank): " .. describe(state.maxRank), "Area: " .. state.area,
        "Status: " .. state.status, "PlaceId: " .. describe(game.PlaceId),
        "Parallel quest mode: " .. tostring(Config.AutoParallelQuests),
        "Defer mini/superior chests: "..tostring(Config.DeferMiniChestQuests)
            .." | count: "..tostring(state.deferredChestCount),
        "Chest scheduling: "..tostring(state.chestDeferralReason),
        "Farm lane: " .. tostring(state.concurrent.farm),
        "Hatch lane: " .. tostring(state.concurrent.hatch),
        "Collection lane: " .. tostring(state.concurrent.collect),
        "Consumables lane: " .. tostring(state.concurrent.passive),
        "Quest event item requests: "..tostring(state.spawnActions),
        "Event spawn last: "..tostring(state.spawnLast),
        "Event spawn toggle: "..tostring(Config.AutoEventItems)
            .." | event cooldown: "..tostring(Config.SpawnItemSeconds).."s",
        "Hatch-first movement: "..tostring(Config.HatchFirstMode)
            .." | active: "..tostring(state.hatchExclusive)
            .." | decision: "..tostring(state.hatchExclusiveLast),
        "Potion multi-use: "..tostring(Config.PotionBatchUse)
            .." | verified: "..tostring(state.potionBatchVerified)
            .." | attempts: "..tostring(state.potionBatchedRequests)
            .." | singles: "..tostring(state.potionFallbackUses)
            .." | result: "..tostring(state.potionBatchLast),
        "Collect machine upgrades: "..tostring(state.upgradeCount).." | quest credits: "..tostring(state.collectionCredits),
        "Golden pets conversion: "..tostring(Config.AutoGoldConversion).." | requests "..state.goldenAttempts.." | verified gold quest points "..state.goldenCredited,
        "Golden conversion last: "..state.goldenLast,
        "Rainbow pets conversion: "..tostring(Config.AutoRainbowConversion).." | requests "..state.rainbowAttempts.." | verified points "..state.rainbowCredited,
        "Rainbow conversion last: "..state.rainbowLast,
        "Rainbow batch unlocked after verified credit: "..tostring(state.rainbowValidated),
        "Stable rainbow quest match recoveries: "..tostring(state.rainbowStableIdentityFixes),
        "Lean mode enabled: "..tostring(Config.LowLagMode)
            .." | visuals every "..tostring(Config.VisualRefreshSeconds)
            .."s | farm requests "..tostring(Config.FarmTapRate)
            .." configured / "..tostring(math.min(Config.FarmTapRate,Config.LowLagMode and 7 or 16))
            .." effective per second | pet assignment "..tostring(Config.MaxPetsPerTick)
            .." max / "..tostring(Config.PetAssignSeconds).."s"
            .." | saved speed "..tostring(Config.PetSpeedMultiplier).."x (cap 20x)",
        "Rainbow prerequisite gold attempts: "..state.rainbowPrepAttempts
            .." | verified gold pets: "..state.rainbowPrepCredited,
        "Rainbow prerequisite last: "..state.rainbowPrepLast,
        "Game Auto Hatch toggle: left unchanged (script uses EggCmds purchase API; Golden Eggs costs 50x)",
        "Auto hatch for GOLD quests: "..tostring(Config.AutoHatchForGold),
        "Auto hatch for rainbow quests: "..tostring(Config.AutoHatchForRainbow)
            .." | hatch intent: "..tostring(state.hatchIntent or "none"),
        "Farm recovery after empty scan: "..tostring(state.farmReturnCount)
            .." | last: "..tostring(state.farmReturnLastStatus),
        "Upgrade last: "..tostring(state.upgradeLast),
        "Upgrade output batch: "..tostring(state.upgradeLastOutputBatch)
            .." | max "..tostring(Config.UpgradeMaxOutputBatch)
            .." | verification: "..tostring(state.upgradeLastCreditMethod),
        "Rejected upgrade stacks: "..tostring(state.upgradeRejectedCount)
            .." | completed machine visits: "..tostring(state.upgradeVisitCompleted),
        "Upgrade selected input: "..tostring(state.upgradeSelectionLast)
            .." | Tier: "..tostring(state.upgradeTierLast),
        "Upgrade collect enabled: "..tostring(Config.AutoUpgradeCollections)
            .." | Max ingredient tier: "..tostring(Config.MaxUpgradeInputTier),
        "SuperMachine discovery: "..tostring(state.machineStatus),
        "Tech Spawn travel attempts: "..tostring(state.machineTravelCount),
        "Floating popup UI hidden: "..tostring(state.popupHidden),
        "Pet visual objects hidden: "..tostring(state.petHidden)
            .." | detected pet sources: "..tostring(state.petVisualCount),
        "Pet visual status: "..tostring(state.petVisualLast),
        "Extra yellow bag meshes concealed: "..tostring(state.lootbagYellowHidden)
            .." | latest: "..tostring(state.lootbagYellowLast),
        "Lootbag visual objects hidden: "..tostring(state.lootbagHidden)
            .." | collector on: "..tostring(Config.AutoCollectLootbags),
        "Lootbag visuals: "..tostring(state.lootbagVisualLast),
        "Lootbag render roots: "..tostring(state.lootbagSourceCount)
            .." | FX objects checked: "..tostring(state.lootbagScannedObjects)
            .." | named particle templates: "..tostring(state.lootbagParticleSourceCount),
        "Popup suppression: "..tostring(state.popupLastStatus),
        "Diamond rotation enabled: "..tostring(Config.DiamondZoneRotation)
            .." | moves="..tostring(state.diamondMoveCount)
            .." | scouting visits="..tostring(state.diamondScoutCount)
            .." | loaded owned areas="..tostring(state.diamondCandidateCount),
        "Diamond target zone: "..tostring(state.diamondZone)
            .." | Status: "..tostring(state.diamondLastStatus),
        "Diamond scouting status: "..tostring(state.diamondScoutLast),
        "Diamond visit normal farm attacks: "..tostring(state.diamondWarmupActions)
            .." | Total diamond quest credits observed: "..tostring(state.diamondWarmupDiamonds)
            .." | Last regular attack: "..tostring(state.diamondLastNormalFarm),
        "Dry diamond scouting visits: "..tostring(state.diamondDryZoneVisits)
            .." | deferrals: "..tostring(state.diamondDryDeferrals)
            .." | last: "..tostring(state.diamondLastDefer),
        "Diamond visit minimum: "..tostring(Config.DiamondWarmupSeconds)
            .."s | last move clock: "..tostring(state.diamondLastTravelAt),
        "Farming field: "..tostring(state.farmFieldLast)
            .." | verified="..tostring(state.farmFieldValidated)
            .." | field-entry failures="..tostring(state.diamondArrivalFailures),
        "Farm quest switches: "..tostring(state.farmSwitchCount)
            .." | last deferred: "..tostring(state.farmSwitchLast),
        "Verified diamond targets in chosen area: "..tostring(state.diamondChosenTargetCount)
            .." | no-progress threshold "..tostring(Config.DiamondStallSeconds).."s",
        "Movement lease: "..tostring(state.movementOwner or "none"),
        "Farm last error: " .. tostring(state.farmError),
        "Farm recovery: " .. tostring(state.failures.farm and state.failures.farm.retryAt or "none"),
        "Breakable interface: " .. state.lastFarmInterface,
        "Farming attempts: "..state.attempts.farm.." / modern="..state.farmStats.dz.." / cmd+workspace="..state.farmStats.workspace.." / empty="..state.farmStats.empty,
        "Orbs requested: "..state.orbClaims.." | Lootbags requested: "..state.lootClaims,
        "Lootbag UID folder children: "..tostring(state.lootbagKnownChildren)
            .." | claim attempts: "..tostring(state.lootbagClaimAttempts)
            .." | failures: "..tostring(state.lootbagClaimErrors)
            .." | last: "..tostring(state.lootbagLastClaimStatus),
        "Confirmed farming quest credits during run: "..tostring(state.farmProgressObserved)
            .." | last credit clock: "..tostring(state.farmProgressRecentAt or "none"),
        "Farm focus: "..tostring(state.focusTargetUID)
            .." | target changes: "..tostring(state.focusTargetChanges)
            .." | pet commands: "..tostring(state.petTargetCommands)
            .." | skipped reassignment: "..tostring(state.petTargetSkipped)
            .." | damage requests (not confirmed kills): "..tostring(state.targetDamageRequests),
        "Pet speed override: "..tostring(Config.PetTurbo)
            .." | VY EXACT math.huge: "..tostring(Config.InfinitePetSpeed)
            .." | hook: "..tostring(state.vySpeedStatus),
        "VY bulk targeting: "..tostring(Config.VYPersistentPetBulk)
            .." | success="..tostring(state.vyPetBulkSent)
            .." fail="..tostring(state.vyPetBulkFailed)
            .." skipped="..tostring(state.vyPetBulkSkipped),
        "VY bulk last: "..tostring(state.vyPetBulkLast),
        "VY event watcher: "..tostring(state.vyBreakableListenerStatus)
            .." | events="..tostring(state.vyEventBreakables)
            .." priority commands="..tostring(state.vyEventBulkActions),
        "Orb module: "..(type(c.OrbModule)=="table" and "present" or "missing"),
        "BreakableCmds: "..(type(c.BreakableCmds)=="table" and "present" or "missing"),
        "Goals: " .. #state.goals, "Controllers: " .. describe(state.chosen)}
    for _,k in ipairs(keys) do
        table.insert(report, k .. ": " .. (type(c[k]) == "table" and "present" or "missing"))
    end
    for _,g in ipairs(state.goals) do
        table.insert(report, "QUEST [" .. g.key .. "][" .. g.kind .. "]["..starValue(g).." stars]: " .. g.title .. " (" .. g.progress .. "/" .. g.required .. ")")
    end
    for i=1,math.min(#state.logs, 15) do table.insert(report, state.logs[i]) end
    table.insert(report,"EXTRAS: login="..tostring(state.extras.loginLast).." verified="..tostring(state.extras.loginClaims))
    table.insert(report,"EXTRAS: timed="..tostring(state.extras.timedLast).." verified="..tostring(state.extras.timedClaims))
    table.insert(report,"EXTRAS: player upgrades="..tostring(state.extras.playerUpgradeLast).." confirmed="..tostring(state.extras.playerUpgradeConfirmed))
    table.insert(report,"EXTRAS: balloons="..tostring(state.extras.balloonLast).." hits requested="..tostring(state.extras.balloonHits))
    table.insert(report,"EXTRAS: visual hidden="..tostring(state.extras.visualHidden).." | notifications="..tostring(#state.extras.alerts))
    table.insert(report,"EXTRAS: inventory="..tostring(state.extras.inventoryLast))
    table.insert(report,"EXTRAS: discovered minigames="..tostring(state.extras.capabilityLast))
    if type(Modules) == "table" and type(Modules.reportLines) == "function" then
        local okLines, lines = pcall(Modules.reportLines)
        if okLines and type(lines) == "table" then
            for _, line in ipairs(lines) do table.insert(report, tostring(line)) end
        end
    end
    return table.concat(report, "\n")
end

-- ============================================================================
-- v5.2 FEATURE MODULES (spliced from src/modules/*.lua by tools/build.py)
-- ============================================================================
-- ==== module: 00_framework.lua ====
do
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
end
-- ==== module: 10_rank.lua ====
do
-- Rank telemetry, stall recovery and rank-reward confirmation.
-- Speed is measured as CONFIRMED quest progress: deltas of Save.Goals[*].Progress
-- keyed by the stable goal UID, plus RankStars / Rank increases. Nothing here
-- sends a network request; recovery only reloads capabilities and resets the
-- planner's local state, so it is safe to leave on.
(function()
    local M = {id = "rank", title = "Rank telemetry", page = "ranks", interval = 6}
    M.defaults = {RankStallRecovery = true, RankStallMinutes = 8}
    M.features = {
        {key = "RankStallRecovery", name = "Automatic stall recovery", status = "UNVERIFIED",
            evidence = "Local only: RECHECK + planner reset when Save.Goals progress stops"},
    }
    local tele = {goals = {}, window = {}, stars = nil, rank = nil, redeemed = nil,
        lastCreditAt = nil, startedAt = nil, credited = 0, fraction = 0, completed = 0,
        rewardsConfirmed = 0, recoveries = 0, stage = 0, last = "waiting for Save data"}
    M.tele = tele

    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    -- One sample: credit = sum of positive Progress deltas for goals with the
    -- same UID. A goal that disappears while stars rise counts as completed.
    function M.sample(data)
        if type(data) ~= "table" or type(data.Goals) ~= "table" then return nil end
        local t = now()
        tele.startedAt = tele.startedAt or t
        tele.lastCreditAt = tele.lastCreditAt or t
        local seen, credit, fraction = {}, 0, 0
        for _, goal in pairs(data.Goals) do
            if type(goal) == "table" and goal.UID ~= nil then
                local uid = tostring(goal.UID)
                local progress = tonumber(goal.Progress) or 0
                local amount = math.max(1, tonumber(goal.Amount) or 1)
                local prev = tele.goals[uid]
                if prev and progress > prev.progress then
                    credit = credit + (progress - prev.progress)
                    fraction = fraction + (progress - prev.progress) / amount
                end
                tele.goals[uid] = {progress = progress, amount = amount}
                seen[uid] = true
            end
        end
        local stars, rank = tonumber(data.RankStars), tonumber(data.Rank)
        local starsUp = tele.stars and stars and stars > tele.stars
        local rankUp = tele.rank and rank and rank > tele.rank
        for uid, prev in pairs(tele.goals) do
            if not seen[uid] then
                tele.goals[uid] = nil
                if starsUp or rankUp then
                    tele.completed = tele.completed + 1
                    fraction = fraction + math.max(0, prev.amount - prev.progress) / prev.amount
                end
            end
        end
        if type(data.RedeemedRankRewards) == "table" then
            local redeemed = countKeys(data.RedeemedRankRewards)
            if tele.redeemed and redeemed > tele.redeemed and not rankUp then
                tele.rewardsConfirmed = tele.rewardsConfirmed + (redeemed - tele.redeemed)
                Modules.note("rank", "rewards", "confirmed", "rank reward redeemed (Save.RedeemedRankRewards)")
            end
            tele.redeemed = redeemed
        end
        if credit > 0 or starsUp or rankUp then
            tele.lastCreditAt = t
            tele.stage = 0
        end
        tele.credited = tele.credited + credit
        tele.fraction = tele.fraction + fraction
        table.insert(tele.window, {t = t, credit = credit, fraction = fraction, stars = stars or 0})
        while #tele.window > 0 and t - tele.window[1].t > 600 do table.remove(tele.window, 1) end
        tele.stars, tele.rank = stars or tele.stars, rank or tele.rank
        return credit
    end

    -- Rates over the last 10 minutes (or since start when shorter).
    function M.rates()
        local w = tele.window
        if #w < 2 then return 0, 0, 0 end
        local minutes = math.max(0.5, (w[#w].t - w[1].t) / 60)
        local credit, fraction = 0, 0
        for i = 2, #w do
            credit = credit + w[i].credit
            fraction = fraction + w[i].fraction
        end
        local starsPerHour = math.max(0, (w[#w].stars - w[1].stars)) / minutes * 60
        return credit / minutes, fraction / minutes, starsPerHour
    end

    -- Escalating, local-only recovery. Stage 1 reloads client modules and
    -- clears temporary quest blocks; stage 2 also resets planner targeting and
    -- releases a stuck movement lease. Each stage runs once per stall.
    function M.recover(idleMinutes)
        local limit = math.max(3, tonumber(Config.RankStallMinutes) or 8)
        if idleMinutes >= limit and tele.stage == 0 then
            tele.stage = 1
            tele.recoveries = tele.recoveries + 1
            pcall(recheck)
            tele.last = string.format("No credited progress for %.0f min: reloaded APIs and cleared quest blocks", idleMinutes)
            log(tele.last, "RECOVERY")
            extraAlert("Stall recovery 1: " .. tele.last)
            return 1
        elseif idleMinutes >= limit * 2 and tele.stage == 1 then
            tele.stage = 2
            tele.recoveries = tele.recoveries + 1
            state.farmGoal, state.diamondZone, state.diamondZoneSince = nil, nil, 0
            state.scannedKey, state.lastTargetScan = "", 0
            state.eventFocus, state.eventFocusUntil = nil, 0
            state.movementOwner, state.movementUntil = nil, 0
            state.hatchNeedsCoins = false
            tele.last = string.format("Still stalled after %.0f min: reset targeting and released movement lease", idleMinutes)
            log(tele.last, "RECOVERY")
            extraAlert("Stall recovery 2: " .. tele.last)
            return 2
        end
        return 0
    end

    function M.tick()
        local data = saveData()
        if not data then
            tele.last = "Save.Get unavailable"
            return
        end
        M.sample(data)
        local idle = (now() - (tele.lastCreditAt or now())) / 60
        local perMinute, questsPerMinute, starsPerHour = M.rates()
        Modules.state("rank").last = string.format("%.1f progress/min, %.2f quests/min, %.1f stars/h",
            perMinute, questsPerMinute, starsPerHour)
        if Config.RankStallRecovery and Config.AutoRank and state.running then M.recover(idle) end
    end
    M.active = function() return true end
    -- A pause is not a stall: restart the idle clock whenever START is pressed.
    function M.onStart()
        tele.lastCreditAt = now()
        tele.stage = 0
    end

    function M.report()
        local perMinute, questsPerMinute, starsPerHour = M.rates()
        return string.format("confirmed progress %.1f/min, quests %.2f/min, stars %.1f/h, total credited %d, "
            .. "goals completed %d, rank rewards confirmed %d, recoveries %d, last=%s",
            perMinute, questsPerMinute, starsPerHour, tele.credited, tele.completed,
            tele.rewardsConfirmed, tele.recoveries, tostring(tele.last))
    end

    function M.buildUI(h, ui)
        local p = h.page("ranks")
        h.section(p, "SPEED (CONFIRMED BY SAVE DATA)", "Quest progress counted only when Save.Goals actually changes")
        ui.rankSpeed = h.rowLabel(p, "Measuring: progress/min not available yet")
        ui.rankStall = h.rowLabel(p, "Stall watchdog: waiting")
        h.toggle(p, "RankStallRecovery", "Automatic stall recovery",
            "No credited progress for the set minutes: reload APIs, then reset targeting (no spending)")
        h.choice(p, "Stall recovery after", "Minutes without credited quest progress",
            function() return tostring(Config.RankStallMinutes) .. " min  >" end,
            function()
                local opts, idx = {5, 8, 12, 20}, 1
                for i, v in ipairs(opts) do if v == Config.RankStallMinutes then idx = i break end end
                Config.RankStallMinutes = opts[idx % #opts + 1]
            end)
    end

    function M.render(ui)
        if ui.activePage ~= "ranks" or not ui.rankSpeed then return end
        local perMinute, questsPerMinute, starsPerHour = M.rates()
        ui.rankSpeed.Text = string.format("Confirmed: %.1f progress/min  |  %.2f quests/min  |  %.1f stars/hour",
            perMinute, questsPerMinute, starsPerHour)
        local idle = tele.lastCreditAt and (now() - tele.lastCreditAt) / 60 or 0
        ui.rankStall.Text = string.format("Last credited progress %.1f min ago  |  recoveries %d  |  %s",
            idle, tele.recoveries, tostring(tele.last))
    end
    Modules.define(M)
end)()
end
-- ==== module: 20_rewards.lua ====
do
-- Drops & Rewards page. The claim workers themselves are the v5.1 engine's
-- (rank rewards, free gifts, login streak, timed rewards, orbs, lootbags,
-- balloons); this module gathers their controls in one place and adds
-- Save-based confirmation counters so "requested" and "received" differ.
(function()
    local M = {id = "rewards", title = "Drops & Rewards", page = "drops", interval = 15}
    local seen = {gifts = nil, redeemed = nil}
    M.seen = seen

    local function size(t)
        local n = 0
        if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
        return n
    end

    -- Confirmation only: counts grow in Save when the server granted a reward.
    function M.tick()
        local data = saveData()
        if type(data) ~= "table" then return end
        local gifts = type(data.FreeGiftsRedeemed) == "table" and size(data.FreeGiftsRedeemed) or nil
        if gifts and seen.gifts and gifts > seen.gifts then
            for _ = 1, gifts - seen.gifts do
                Modules.note("rewards", "freegifts", "confirmed", "free gift redeemed (Save.FreeGiftsRedeemed)")
            end
        elseif gifts and seen.gifts and gifts < seen.gifts then
            Modules.state("rewards").last = "free gift cycle reset"
        end
        seen.gifts = gifts or seen.gifts
        Modules.state("rewards").last = string.format("orb claims sent %d, lootbag claims sent %d, free gifts confirmed %d",
            tonumber(state.orbClaims) or 0, tonumber(state.lootClaims) or 0, Modules.stat("rewards", "freegifts").confirmed)
    end
    M.active = function() return Config.AutoFreeGifts == true or Config.AutoCollectLootbags == true or Config.AutoCollectOrbs == true end

    function M.report()
        return string.format("lootbag claim attempts=%s errors=%s last=%s | orb claims sent=%s",
            tostring(state.lootbagClaimAttempts), tostring(state.lootbagClaimErrors),
            tostring(state.lootbagLastClaimStatus), tostring(state.orbClaims))
    end

    function M.buildUI(h, ui)
        local p = h.page("drops")
        h.section(p, "DROPS", "Orbs and lootbags are claimed with the game's own claim requests")
        h.toggle(p, "AutoCollectOrbs", "Collect orbs", "Orbs: Collect for loaded orb IDs; bounded batches")
        h.toggle(p, "AutoCollectLootbags", "Collect lootbags", "Lootbags_Claim for loaded bag IDs; never deletes bag objects")
        h.toggle(p, "SuperMagnet", "Super magnet", "Larger client pickup distance while running; restored on pause")
        h.toggle(p, "HideLootbagVisuals", "Hide lootbag models", "Local and reversible")
        h.toggle(p, "HidePickupPopups", "Hide floating pickup numbers", "Local and reversible")
        h.section(p, "REWARDS", "Each claim is checked against Save data before it counts as received")
        h.toggle(p, "AutoClaimRankRewards", "Claim rank rewards", "Ranks_ClaimReward for rewards your stars already unlocked")
        h.toggle(p, "AutoFreeGifts", "Claim free playtime gifts", "Redeem Free Gift when Save.FreeGiftsTime passes the wait time")
        h.toggle(p, "AutoLoginStreak", "Claim daily login streak", "Only when LoginStreakCmds.CanClaim() says it is ready")
        h.toggle(p, "AutoTimedRewards", "Claim timed rewards", "DailyRewards_Redeem near a loaded reward machine; cooldown from Save")
        h.toggle(p, "AutoPopBalloons", "Pop gift balloons", "Slingshot balloon gifts (needs 3 rebirths)")
        ui.rewardsStatus = h.rowLabel(p, "Rewards: not checked")
        ui.dropsStatus = h.rowLabel(p, "Drops: not checked")
        h.note(p, "Mailbox claiming is on the Trading & Mailbox page. Gift bags, lootboxes, keys and spin wheels are listed on Items & Boosts with their research status.", 52)
    end

    function M.render(ui)
        if ui.activePage ~= "drops" or not ui.rewardsStatus then return end
        local ex = state.extras or {}
        ui.rewardsStatus.Text = string.format("Login: %s  |  Timed: %s  |  Free gifts confirmed: %d",
            tostring(ex.loginLast), tostring(ex.timedLast), Modules.stat("rewards", "freegifts").confirmed)
        ui.dropsStatus.Text = string.format("Orb claims sent %s  |  Lootbag claims sent %s  |  %s",
            tostring(state.orbClaims or 0), tostring(state.lootClaims or 0), tostring(state.lootbagLastClaimStatus or "no lootbag claim yet"))
    end
    Modules.define(M)
end)()
end
-- ==== module: 30_items.lua ====
do
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
end
-- ==== module: 40_events.lua ====
do
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
end
-- ==== module: 60_player.lua ====
do
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
end

-- ============================================================================
-- RANKPILOT v2.8 UI  |  independent, source-contained Roblox Instances
-- App-style layout inspired by the user's ZAP example; no external UI loader.
-- ============================================================================
local ui: any = {pages = {}, nav = {}, toggleRefresh = {}, questRows = {}, diagRows = {}}
-- ZapHub-inspired visual hierarchy, original RankPilot X branding and no borrowed assets.
-- The colors are presentation-only; every automation function is inherited intact.
local THEME = {
    base = Color3.fromRGB(14, 15, 21),
    sidebar = Color3.fromRGB(20, 21, 31),
    surface = Color3.fromRGB(26, 28, 40),
    card = Color3.fromRGB(33, 35, 49),
    hover = Color3.fromRGB(46, 48, 65),
    border = Color3.fromRGB(65, 68, 92),
    gold = Color3.fromRGB(126, 121, 250), -- named gold for backwards-compatible UI references
    green = Color3.fromRGB(94, 219, 164),
    red = Color3.fromRGB(238, 110, 128),
    white = Color3.fromRGB(244, 245, 250),
    muted = Color3.fromRGB(162, 166, 188),
}
local function create(class, properties, parent)
    local obj = Instance.new(class)
    for key, value in pairs(properties or {}) do obj[key] = value end
    if parent then obj.Parent = parent end
    return obj
end
local function rounded(object, r)
    return create("UICorner", {CornerRadius = UDim.new(0, r or 8)}, object)
end
local function outlined(object, color)
    return create("UIStroke", {Color = color or THEME.border, Thickness = 1, Transparency = 0.25}, object)
end
local function label(parent, text, x, y, w, h, size, color, bold)
    return create("TextLabel", {
        BackgroundTransparency = 1, Text = tostring(text or ""),
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        TextColor3 = color or THEME.white,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize = size or 12, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(state.connections, c)
    return c
end
local function action(parent, text, x, y, w, h, callback, color)
    local control = create("TextButton", {
        BackgroundColor3 = color or THEME.card, BorderSizePixel = 0,
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        Text = text, TextColor3 = THEME.white, Font = Enum.Font.GothamBold,
        TextSize = 12, AutoButtonColor = true,
    }, parent)
    rounded(control, 7)
    if callback then connect(control.MouseButton1Click, callback) end
    return control
end
local function accessibleUIParents()
    -- Never access CoreGui directly: some executors throw a Plugin permission error.
    local parents = {}
    local ok, pg = pcall(function()
        return LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 12)
    end)
    if ok and pg then parents[#parents + 1] = pg end
    if type(gethui) == "function" then
        local good, hidden = pcall(gethui)
        if good and typeof(hidden) == "Instance" and hidden ~= pg then
            parents[#parents + 1] = hidden
        end
    end
    return parents
end
local function applyFeatureSetting(field, value)
    Config[field] = value
    if state.running then
        if field == "PetTurbo" then pcall(petTurbo, value) end
        if field == "InfinitePetSpeed" then pcall(petTurbo, false);pcall(petTurbo,true) end
        if field == "VYInstantEvents" and value then pcall(vyInstallEventListener) end
        if field == "SuperMagnet" then pcall(updateSuperMagnet, value) end
        if field == "SkipEggAnimations" then pcall(skipEggAnimation, value) end
    end
    if field == "HidePickupPopups" then
        if value then pcall(refreshPopups, true) else pcall(restorePopups) end
    end
    if field == "HideLootbagVisuals" then
        if value then pcall(refreshLootbagVisuals,true)
        else pcall(restoreLootbagVisuals) end
    end
    if field == "HidePetVisuals" then
        if value then pcall(refreshPetVisuals,true)
        else pcall(restorePetVisuals) end
    end
    if field == "RenderOff" then
        pcall(function() RunService:Set3dRenderingEnabled(not (state.running and value)) end)
    end
    if field == "Fullbright" then pcall(applyFullbright) end
    if field == "AutoPopBalloons" and not value then pcall(unequipBalloonSlingshot) end
    if field == "HideBalloonVisuals" or field == "HideBreakableVisuals" then
        state.extras.visualNext=0
        pcall(refreshAdditionalVisuals)
    end
    if type(Modules) == "table" and type(Modules.onSetting) == "function" then
        pcall(Modules.onSetting, field, value)
    end
    persist()
end
local function buildUI()
    local parents = accessibleUIParents()
    if #parents == 0 then error("[RankPilot] No accessible UI parent (PlayerGui/gethui)", 0) end
    for _, pg in ipairs(parents) do
        local ok, old = pcall(function() return pg:FindFirstChild("RankPilotUI") end)
        if ok and old then pcall(function() old:Destroy() end) end
    end
    local screen = create("ScreenGui", {
        Name = "RankPilotUI", ResetOnSpawn = false, DisplayOrder = 510,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local attached = false
    local reason = "No usable parent"
    for _, pg in ipairs(parents) do
        local ok, err = pcall(function() screen.Parent = pg end)
        if ok then attached = true; break else reason = tostring(err) end
    end
    if not attached then
        pcall(function() screen:Destroy() end)
        error("[RankPilot] UI cannot attach to PlayerGui: " .. reason, 0)
    end
    state.gui = screen
    local window = create("Frame", {
        Name = "Window", BackgroundColor3 = THEME.base, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(900, 590), Active = true,
    }, screen)
    rounded(window, 11); outlined(window)
    ui.window = window
    local camera = Workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local uiScale = create("UIScale", {
        Scale = math.max(0.60, math.min(1, (vp.X - 24)/900, (vp.Y - 24)/590)),
    }, window)
    ui.scale = uiScale
    local top = create("Frame", {Name = "Topbar", BackgroundColor3 = THEME.sidebar,
        BorderSizePixel = 0, Size = UDim2.fromOffset(900, 66), Active = true}, window)
    rounded(top, 11)
    create("Frame", {BackgroundColor3 = THEME.sidebar, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 45), Size = UDim2.fromOffset(900, 21)}, top)
    label(top, "RANKPILOT  X", 19, 12, 240, 28, 20, THEME.gold, true)
    label(top, "PS99  /  ZAP-STYLE WORKSPACE", 20, 39, 295, 15, 10, THEME.muted)
    local titleRight = label(top, "v5.2   |   VY ENGINE", 640, 23, 141, 17, 10, THEME.muted)
    titleRight.TextXAlignment = Enum.TextXAlignment.Right
    action(top, "_", 801, 16, 37, 33, function()
        window.Visible = false
        if ui.restoreButton then ui.restoreButton.Visible = true end
    end, THEME.card)
    action(top, "X", 846, 16, 36, 33, stop, THEME.card)
    local sidebar = create("Frame", {Name = "Sidebar", BackgroundColor3 = THEME.sidebar,
        BorderSizePixel = 0, Position = UDim2.fromOffset(0, 66),
        Size = UDim2.fromOffset(190, 473)}, window)
    create("Frame", {BackgroundColor3 = THEME.border, BorderSizePixel = 0,
        Position = UDim2.fromOffset(190, 66), Size = UDim2.fromOffset(1, 473)}, window)
    label(sidebar, "RANKPILOT TOOLS", 15, 8, 160, 23, 10, THEME.gold, true)
    local main = create("Frame", {Name = "Content", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(205, 73), Size = UDim2.fromOffset(681, 466)}, window)
    ui.pageTitle = label(main, "Dashboard", 1, 0, 660, 31, 20, THEME.white, true)
    ui.pageSubtitle = label(main, "Your rank, active quests and automation state", 2, 31, 658, 21, 11, THEME.muted)
    local bottom = create("Frame", {Name = "Footer", BackgroundColor3 = THEME.sidebar,
        BorderSizePixel = 0, Position = UDim2.fromOffset(0, 539),
        Size = UDim2.fromOffset(900, 51)}, window)
    rounded(bottom, 11)
    create("Frame", {BackgroundColor3 = THEME.sidebar, BorderSizePixel = 0,
        Size = UDim2.fromOffset(900, 17)}, bottom)
    ui.footerStatus = label(bottom, "● PAUSED", 18, 12, 360, 26, 11, THEME.gold, true)
    ui.footerRequests = label(bottom, "Hatches 0  |  Hits 0", 391, 13, 195, 22, 10, THEME.muted)
    ui.footerRequests.TextXAlignment = Enum.TextXAlignment.Right
    action(bottom, "RECHECK", 601, 9, 103, 33, recheck)
    action(bottom, "COPY REPORT", 713, 9, 113, 33, function()
        local report = getReport()
        if type(setclipboard) == "function" then
            local ok = pcall(setclipboard, report)
            log(ok and "Report copied to clipboard" or "Clipboard write failed", "SYSTEM")
        else
            print(report)
            log("Report printed in executor console", "SYSTEM")
        end
    end)
    ui.playButton = action(bottom, "START", 835, 9, 55, 33, function()
        if state.running then pause() else run() end
    end, THEME.green)
    ui.playButton.TextColor3 = THEME.base
    local restore = action(screen, "RANKPILOT X  ▢", 0, 0, 185, 43, function()
        window.Visible = true
        if ui.restoreButton then ui.restoreButton.Visible = false end
    end, THEME.sidebar)
    restore.AnchorPoint = Vector2.new(0.5, 0)
    restore.Position = UDim2.fromScale(0.5, 0.10)
    restore.Visible = false
    restore.TextColor3 = THEME.gold
    ui.restoreButton = restore

    -- Drag only the topbar; leave the game view accessible through transparent areas.
    local dragging, dragPosition, initialPosition = false, nil, nil
    connect(top.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragPosition = input.Position
            initialPosition = window.Position
        end
    end)
    connect(top.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    connect(game:GetService("UserInputService").InputChanged, function(input)
        if not dragging or not initialPosition then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragPosition
        window.Position = UDim2.new(initialPosition.X.Scale, initialPosition.X.Offset + delta.X,
            initialPosition.Y.Scale, initialPosition.Y.Offset + delta.Y)
    end)

    -- RightControl toggles the entire hub without pausing the automation.
    connect(game:GetService("UserInputService").InputBegan, function(input, gameProcessed)
        if gameProcessed or input.KeyCode ~= Enum.KeyCode.RightControl then return end
        window.Visible = not window.Visible
        if ui.restoreButton then ui.restoreButton.Visible = not window.Visible end
    end)

    -- Fifth field is the category rendered above each cluster in the scrollable sidebar.
    -- All active controls below are connected to real opt-in feature code.
    local pageInfo = {
        {"home", "Home", "Dashboard", "Account progress and worker status", "OVERVIEW"},
        {"ranks", "Auto Rank", "Auto Rank Quests", "Live rank goals, stars and milestone requirements", "AUTOMATION"},
        {"farm", "Auto Farm", "Auto Farm", "Pet targeting, breakables and diamond scouting", "AUTOMATION"},
        {"worlds", "Worlds", "Worlds & Areas", "Zone progression, rebirths and cross-world travel", "AUTOMATION"},
        {"eggs", "Eggs & Pets", "Eggs & Pets", "Hatching, pets, gold and rainbow conversion", "AUTOMATION"},
        {"items", "Items & Boosts", "Items & Boosts", "Event items, potions, fruits, flags and boosts", "TOOLS"},
        {"machines", "Machines", "Machines & Collection", "Bulk potion and enchant upgrading", "TOOLS"},
        {"drops", "Drops & Rewards", "Drops & Rewards", "Lootbags, orbs, gifts, rank rewards and daily rewards", "TOOLS"},
        {"events", "Events", "Events & Balloons", "Random events, event items and balloons", "WORLD"},
        {"minigames", "Minigames", "Minigames", "Minigame and instance capability status", "WORLD"},
        {"farmworld", "Farming World", "Farming World", "Permanent Farming World status and tools", "WORLD"},
        {"trading", "Trading & Mailbox", "Trading & Mailbox", "Protected inventory, mailbox and booth safety", "WORLD"},
        {"notifications", "Notifications", "Local Notifications", "Rank advancement and locally recorded automation alerts", "SYSTEM"},
        {"performance", "Optimization", "Optimization", "Rendering, pet speed and low-CPU controls", "SYSTEM"},
        {"settings", "Settings", "Settings", "Progression, saved preferences and profiles", "SYSTEM"},
        {"diagnostics", "Diagnostics", "Diagnostics", "Live logs, request status and copied reports", "SYSTEM"},
    }
    local function page(id)
        return ui.pages[id]
    end
    local function showPage(id)
        ui.activePage = id
        for name, frame in pairs(ui.pages) do
            frame.Visible = (name == id)
        end
        for name, nav in pairs(ui.nav) do
            local active = name == id
            nav.BackgroundColor3 = active and THEME.card or THEME.sidebar
            nav.TextColor3 = active and THEME.white or THEME.muted
            local strip = ui.navIndicator and ui.navIndicator[name]
            if strip then strip.Visible = active end
        end
        for _, data in ipairs(pageInfo) do
            if data[1] == id then
                ui.pageTitle.Text = data[3]
                ui.pageSubtitle.Text = data[4]
                break
            end
        end
    end
    -- The scrolling sidebar supports extra tabs without clipping below the footer.
    local navScroll = create("ScrollingFrame", {
        Name = "NavScroll", BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(4, 34), Size = UDim2.fromOffset(181, 435),
        ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.border,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
    }, sidebar)
    ui.navIndicator = {}
    local navY, lastGroup = 2, nil
    for _, data in ipairs(pageInfo) do
        local id, group = data[1], data[5]
        if group ~= lastGroup then
            if lastGroup ~= nil then navY = navY + 11 end
            label(navScroll, group, 11, navY, 147, 17, 10, THEME.gold, true)
            navY = navY + 21
            lastGroup = group
        end
        local nav = action(navScroll, data[2], 5, navY, 164, 33, function()
            showPage(id)
        end, THEME.sidebar)
        nav.TextXAlignment = Enum.TextXAlignment.Left
        nav.TextSize = 11
        rounded(nav, 6)
        create("UIPadding", {PaddingLeft = UDim.new(0, 20)}, nav)
        ui.nav[id] = nav
        ui.navIndicator[id] = create("Frame", {
            Name = "Selected", Visible = false, BorderSizePixel = 0,
            BackgroundColor3 = THEME.gold,
            Position = UDim2.fromOffset(0, 7), Size = UDim2.fromOffset(3, 19),
        }, nav)
        navY = navY + 36
        local scroll = create("ScrollingFrame", {
            Name = id .. "Page", Visible = false, BackgroundTransparency = 1,
            BorderSizePixel = 0, Position = UDim2.fromOffset(0, 65),
            Size = UDim2.fromOffset(672, 389), ScrollBarThickness = 4,
            ScrollBarImageColor3 = THEME.border,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.fromOffset(0, 0),
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, main)
        create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 9)}, scroll)
        create("UIPadding", {PaddingTop = UDim.new(0, 4),
            PaddingBottom = UDim.new(0, 15), PaddingRight = UDim.new(0, 12)}, scroll)
        scroll:SetAttribute("NextOrder", 0)
        ui.pages[id] = scroll
    end
    navScroll.CanvasSize = UDim2.fromOffset(0, navY + 8)
    local function order(scroll, object)
        local n = (scroll:GetAttribute("NextOrder") or 0) + 1
        scroll:SetAttribute("NextOrder", n)
        object.LayoutOrder = n
        return object
    end
    local function section(scroll, name, description)
        local box = order(scroll, create("Frame", {BackgroundTransparency = 1,
            Size = UDim2.new(1, -1, 0, description and 43 or 26)}, scroll))
        create("Frame", {BackgroundColor3 = THEME.gold, BorderSizePixel = 0,
            Position = UDim2.fromOffset(3, 6), Size = UDim2.fromOffset(3, 13)}, box)
        label(box, name, 13, 0, 585, 23, 13, THEME.white, true)
        if description then label(box, description, 13, 22, 610, 17, 10, THEME.muted) end
        return box
    end
    local function note(scroll, text, height)
        local n = order(scroll, create("Frame", {BackgroundColor3 = THEME.surface,
            BorderSizePixel = 0, Size = UDim2.new(1, -5, 0, height or 52)}, scroll))
        rounded(n, 7)
        local t = label(n, text, 14, 7, 610, (height or 52) - 14, 11, THEME.muted)
        t.TextWrapped = true
        t.TextTruncate = Enum.TextTruncate.None
        t.TextYAlignment = Enum.TextYAlignment.Center
        return t
    end
    local function interactiveToggle(scroll, key, name, description)
        local row = order(scroll, create("TextButton", {
            Name = "Toggle_" .. key, BackgroundColor3 = THEME.card,
            BorderSizePixel = 0, Text = "", AutoButtonColor = true,
            Size = UDim2.new(1, -5, 0, 58),
        }, scroll))
        rounded(row, 8)
        label(row, name, 14, 7, 483, 24, 12, THEME.white, true)
        local hint = label(row, description, 14, 31, 483, 18, 10, THEME.muted)
        hint.TextTruncate = Enum.TextTruncate.AtEnd
        ui.searchIndex = ui.searchIndex or {}
        table.insert(ui.searchIndex, {row = row, page = string.gsub(scroll.Name, "Page$", ""),
            text = string.lower(tostring(name) .. " " .. tostring(description) .. " " .. tostring(key))})
        if type(Modules) == "table" and type(Modules.statusFor) == "function" then
            local okChip, chipText, chipColor = pcall(Modules.statusFor, key)
            if okChip and chipText then
                local chip = create("TextLabel", {Name = "Chip", BackgroundColor3 = THEME.surface,
                    BorderSizePixel = 0, Position = UDim2.new(1, -184, 0, 19),
                    Size = UDim2.fromOffset(92, 19), Font = Enum.Font.GothamBold, TextSize = 9,
                    TextColor3 = chipColor or THEME.muted, Text = chipText}, row)
                rounded(chip, 5)
                ui.chips = ui.chips or {}
                table.insert(ui.chips, {key = key, label = chip, page = string.gsub(scroll.Name, "Page$", "")})
            end
        end
        local badge = create("TextLabel", {BackgroundColor3 = THEME.surface,
            BorderSizePixel = 0, Position = UDim2.new(1,-85,0,15),
            Size = UDim2.fromOffset(67, 27), Font = Enum.Font.GothamBold,
            TextSize = 11, TextColor3 = THEME.white, Text = "OFF",
        }, row)
        rounded(badge, 6)
        local function refresh()
            local on = Config[key] == true
            badge.Text = on and "ON" or "OFF"
            badge.TextColor3 = on and THEME.base or THEME.muted
            badge.BackgroundColor3 = on and THEME.green or THEME.surface
        end
        connect(row.MouseButton1Click, function()
            applyFeatureSetting(key, not Config[key])
            refresh()
        end)
        local owner = string.gsub(scroll.Name, "Page$", "")
        table.insert(ui.toggleRefresh, function()
            if ui.activePage == owner then refresh() end
        end)
        refresh()
        return row
    end
    local function choice(scroll, title, caption, valueFn, nextFn)
        local row = order(scroll, create("Frame", {BackgroundColor3 = THEME.card,
            BorderSizePixel = 0, Size = UDim2.new(1, -5, 0, 59)}, scroll))
        rounded(row, 8)
        label(row, title, 14, 6, 420, 26, 12, THEME.white, true)
        label(row, caption, 14, 32, 425, 18, 10, THEME.muted)
        ui.searchIndex = ui.searchIndex or {}
        table.insert(ui.searchIndex, {row = row, page = string.gsub(scroll.Name, "Page$", ""),
            text = string.lower(tostring(title) .. " " .. tostring(caption))})
        local b = action(row, "", 523, 14, 122, 31, function()
            nextFn()
            persist()
        end, THEME.surface)
        local function refresh() b.Text = valueFn() end
        local owner = string.gsub(scroll.Name, "Page$", "")
        table.insert(ui.toggleRefresh, function()
            if ui.activePage == owner then refresh() end
        end)
        refresh()
        return b
    end
    local function rowLabel(scroll, text, color)
        local box = order(scroll, create("Frame", {BackgroundColor3 = THEME.card,
            BorderSizePixel = 0, Size = UDim2.new(1, -5, 0, 39)}, scroll))
        rounded(box, 7)
        local t = label(box, text or "-", 13, 4, 622, 30, 11, color or THEME.white)
        return t
    end
    local function toolbar(scroll, data)
        local bar = order(scroll, create("Frame", {BackgroundTransparency = 1,
            Size = UDim2.new(1, -5, 0, 40)}, scroll))
        local width = math.floor((656 - (#data-1)*8) / #data)
        for i, entry in ipairs(data) do
            action(bar, entry[1], (i-1)*(width+8), 2, width, 34, entry[2], entry[3])
        end
        return bar
    end

    -- Home: concise overview instead of a giant wall of toggles.
    section(page("home"), "LIVE ACCOUNT", "Everything important in one screen")
    local kpis = order(page("home"), create("Frame", {BackgroundTransparency = 1,
        Size = UDim2.new(1, -5, 0, 84)}, page("home")))
    local function metric(name, index)
        local card = create("Frame", {BackgroundColor3 = THEME.card, BorderSizePixel = 0,
            Position = UDim2.fromOffset((index-1)*224, 0), Size = UDim2.fromOffset(215, 80)}, kpis)
        rounded(card, 8)
        label(card, name, 14, 8, 190, 22, 11, THEME.muted)
        return label(card, "--", 14, 30, 190, 36, 19, THEME.gold, true)
    end
    ui.metricRank = metric("CURRENT RANK", 1)
    ui.metricZone = metric("CURRENT AREA", 2)
    ui.metricQuests = metric("ACTIVE QUESTS", 3)
    section(page("home"), "ACTIVITY LANES", "Independent workers can run compatible quests together")
    ui.homeFarm = rowLabel(page("home"), "Farm: waiting")
    ui.homeHatch = rowLabel(page("home"), "Hatch: waiting")
    ui.homeCollect = rowLabel(page("home"), "Collect: waiting")
    ui.homeEvent = rowLabel(page("home"), "Item placement: waiting")
    section(page("home"), "QUICK CONTROLS")
    toolbar(page("home"), {{"START / PAUSE", function() if state.running then pause() else run() end end, THEME.green},
        {"CHECK APIS", recheck}, {"COPY REPORT", function()
            if type(setclipboard) == "function" then
                pcall(setclipboard, getReport()); log("Report copied", "SYSTEM")
            else print(getReport()) end
        end}})
    note(page("home"), "Automation is account-independent. Use Rank Quests to see goal progress and Diagnostics for request errors. A sent request is not proof of an in-game quest credit.", 56)

    section(page("ranks"), "ACTIVE RANK QUESTS", "Live data from the current account's saved Goals")
    for i=1,7 do
        local q = order(page("ranks"), create("Frame", {BackgroundColor3 = THEME.card,
            BorderSizePixel = 0, Size = UDim2.new(1, -5, 0, 54)}, page("ranks")))
        rounded(q, 7)
        local name = label(q, "Waiting for rank quests ...", 13, 5, 513, 25, 11, THEME.white, true)
        local progress = label(q, "0 / 0", 525, 5, 115, 25, 11, THEME.muted)
        progress.TextXAlignment = Enum.TextXAlignment.Right
        local track = create("Frame", {BackgroundColor3 = THEME.surface, BorderSizePixel = 0,
            Position = UDim2.fromOffset(13, 37), Size = UDim2.new(1, -26, 0, 6)}, q)
        rounded(track, 4)
        local fill = create("Frame", {BackgroundColor3 = THEME.green, BorderSizePixel = 0,
            Size = UDim2.fromScale(0, 1)}, track)
        rounded(fill, 4)
        ui.questRows[i] = {root = q, name = name, progress = progress, fill = fill}
    end
    section(page("ranks"), "LIVE RANK MILESTONE", "Game directory star requirements, reward track and next-area/rebirth gates")
    ui.rankStageLabel=rowLabel(page("ranks"),"Rank status: checking current reward track...")
    ui.rankStarsLabel=rowLabel(page("ranks"),"Stars: ? / ?  |  Next rank: ?")
    ui.rankBlockLabel=rowLabel(page("ranks"),"Required area/rebirth: checking...")
    section(page("ranks"), "RANK PLANNER")
    interactiveToggle(page("ranks"), "AutoRankMilestones", "Read live rank milestones", "Track stars, claimable rewards and world/rebirth requirements")
    interactiveToggle(page("ranks"), "PreferHighStars", "Prioritize high-star quests", "Favor 4-star/3-star quests when they are actionable; keeps concurrent lanes")
    interactiveToggle(page("ranks"), "DeferMiniChestQuests", "Do other quests before mini-chests", "Skip normal and superior mini-chest goals while another supported quest remains; chest quests resume when others finish")
    interactiveToggle(page("ranks"), "AutoRank", "Automate rank quests", "Plan supported goals using current rank data")
    interactiveToggle(page("ranks"), "AutoParallelQuests", "Parallel quest workers", "Farm, hatch, collect and consume when compatible")
    interactiveToggle(page("ranks"), "AutoClaimRankRewards", "Claim rank rewards", "Claim rewards that the account is eligible for")
    interactiveToggle(page("ranks"), "AutoWorld", "Advance unlocked areas", "Buy the next area when affordable and allowed")

    section(page("worlds"), "WORLD DETECTION", "Live game data; no fixed zone coordinates or account usernames")
    ui.worldNumber = rowLabel(page("worlds"),"World: detecting ...")
    ui.worldCurrent = rowLabel(page("worlds"),"Current zone: detecting ...")
    ui.worldBest = rowLabel(page("worlds"),"Best owned zone: detecting ...")
    ui.worldTravel = rowLabel(page("worlds"),"Travel status: not checked")
    section(page("worlds"),"AREA PROGRESSION", "Current-world gate purchases only")
    interactiveToggle(page("worlds"),"AutoWorld","Automatically buy next areas","Uses live gate price and ownership data, no fixed last area")
    interactiveToggle(page("worlds"),"VYWorldTravel","VY cross-world teleport + local reload","Opt-in: save this script in the executor workspace as "..tostring(Config.VYLocalWorkspaceFile))
    interactiveToggle(page("worlds"),"AutoZoneTeleports","Use game teleport for owned areas","Experimental: current-world owned areas only; never guesses cross-world place IDs")
    interactiveToggle(page("worlds"),"AutoLoadBestArea","Auto-load unloaded best area","When the best owned farming field is not loaded, use the game's zone anchor and bounded local teleport; never teleport across worlds")
    toolbar(page("worlds"),{{"RECHECK WORLD",recheck},
        {"GO TO BEST LOADED AREA",function()
            local zone=getZoneInfo()
            if zone and placeInZone(zone) then
                log("Requested best-area movement: "..zone.name,"WORLD")
            elseif zone then
                requestLocalZoneTeleport(zone.name)
            end
        end}})
    note(page("worlds"),"Supported world data: Coins (1-99), Tech (100-199), Void (200-239), Fantasy (240-279). Game directory values take priority. Changing Roblox places may require relaunch or executor auto-execute; cross-world teleport is not guessed.",75)
    section(page("farm"), "BREAKABLES", "Prefer regular quests; defer scarce mini/superior chests while other tasks remain")
    interactiveToggle(page("farm"), "DeferMiniChestQuests", "Delay mini and superior mini-chests", "Prioritize hatch, collect, generic farm and other enabled quests; chest goals are handled last")
    interactiveToggle(page("farm"), "AutoFarm", "Auto farm breakables", "Target loaded breakables in the applicable area")
    interactiveToggle(page("farm"), "FastFarm", "High frequency farm worker", "Separate bounded worker; automatically backs off on errors")
    interactiveToggle(page("farm"), "SpreadPets", "Distribute pets over targets", "Efficient on many weak breakables")
    interactiveToggle(page("farm"), "PetTurbo", "Pet travel speed override", "Client-side setting; server movement may differ")
    choice(page("farm"), "Pet speed multiplier", "Finite fallback; used only while Infinite pet speed is OFF",
        function() return tostring(Config.PetSpeedMultiplier) .. "x  >" end,
        function()
            local values = {1,3,5,8,12,20}
            local found = 1
            for i, v in ipairs(values) do if v==Config.PetSpeedMultiplier then found=i; break end end
            Config.PetSpeedMultiplier = values[(found % #values) + 1]
            if state.running and Config.PetTurbo then pcall(petTurbo, true) end
        end)
    choice(page("farm"), "Farm taps per second", "Requests per second; real damage and kills depend on the game. Low-lag mode caps at 7/s.",
        function() return tostring(Config.FarmTapRate) .. " configured / "
            .. tostring(math.min(Config.FarmTapRate,Config.LowLagMode and 7 or 16)) .. " effective >" end,
        function()
            local options={3,5,7,10,16}; local index=1
            for i,v in ipairs(options) do if v==Config.FarmTapRate then index=i;break end end
            Config.FarmTapRate=options[(index%#options)+1]
        end)
    interactiveToggle(page("farm"), "DiamondZoneRotation", "Scout unlocked areas for diamond targets", "Visit owned, loaded areas even before their targets are streamed in; farm and rotate")
    interactiveToggle(page("farm"), "AdaptiveFarmPriority", "Switch stalled quests automatically", "If a farm quest does not gain credit, try a different supported quest and revisit later")
    choice(page("farm"), "Diamond area farming warm-up", "Attack ordinary breakables after arriving. This may spawn new diamond targets.",
        function() return tostring(Config.DiamondWarmupSeconds).." seconds  >" end,
        function()
            local opts={5,9,12,16,24};local i=1
            for j,v in ipairs(opts) do if v==Config.DiamondWarmupSeconds then i=j;break end end
            Config.DiamondWarmupSeconds=opts[i%#opts+1]
        end)
    choice(page("farm"), "Diamond area dwell time", "How long to wait before trying another owned area",
        function() return tostring(Config.DiamondZoneDwell).." seconds  >" end,
        function()
            local opts={5,8,10,12,16,22};local i=1
            for j,v in ipairs(opts) do if v==Config.DiamondZoneDwell then i=j;break end end
            Config.DiamondZoneDwell=opts[i%#opts+1]
        end)
    interactiveToggle(page("farm"), "AutoCollectOrbs", "Auto collect orbs", "Try to claim locally spawned orb IDs")
    interactiveToggle(page("farm"), "AutoCollectLootbags", "Auto collect lootbags", "Claim bag IDs without deleting unverified drops")
    section(page("farm"), "VY SOURCE TARGETING", "Stable pet assignments and faster reactions to spawned special breakables")
    interactiveToggle(page("farm"), "VYPersistentPetBulk", "VY persistent bulk pet assignments", "Use Breakables_JoinPetBulk; fall back to DZ targeting if unsupported")
    interactiveToggle(page("farm"), "VYMultiTargetSpread", "VY distribute pets across targets", "Each pet keeps a live breakable target; disable to concentrate damage")
    interactiveToggle(page("farm"), "VYInstantEvents", "VY immediate special-breakable targeting", "React to new jars, comets and mini-chests for matching live quests")

    section(page("eggs"), "EGG OPENING", "A dedicated hatch worker runs independently of the main planner")
    interactiveToggle(page("eggs"), "AutoHatch", "Auto hatch rank quests", "Use a confirmed unlocked egg when a hatch goal is active")
    interactiveToggle(page("eggs"), "AutoHatchAlways", "Hatch without an active quest", "Optional, consumes coins outside ranking quests")
    interactiveToggle(page("eggs"), "AutoHatchForRainbow", "Hatch best eggs for rainbow quests", "Only when a matching rainbow quest needs more material")
    interactiveToggle(page("eggs"), "AutoHatchForGold", "Hatch best eggs for golden quests", "Only when a matching golden best-egg quest lacks regular pets")
    interactiveToggle(page("eggs"), "HatchFarmRemoteProbe", "Test farming + hatching together", "Try one remote hatch during farming; only continue away from egg if counter rises")
    interactiveToggle(page("eggs"), "SkipEggAnimations", "Skip egg opening animations", "Hide opening effects and tap-to-open prompt where possible")
    interactiveToggle(page("eggs"), "HatchFirstMode", "Finish hatching before farming", "Stay by best egg until hatch/material quest finishes; farm coins only if a single hatch fails")
    interactiveToggle(page("eggs"), "HatchMovementShare", "Legacy shared travel windows", "Used only when hatch-first mode is disabled")
    section(page("eggs"), "PET MANAGEMENT")
    interactiveToggle(page("eggs"), "AutoEquipBest", "Equip best pets", "Refresh equipped pets from your account inventory")
    interactiveToggle(page("eggs"), "HidePetVisuals", "Hide all pet graphics", "Client visuals only. Pets stay equipped and can keep targeting breakables")
    interactiveToggle(page("eggs"), "InfinitePetSpeed", "VY infinite pet speed (math.huge)", "EXACT infinity: may cause movement bugs or lag; reversible on PAUSE/STOP")
    interactiveToggle(page("eggs"), "AutoGoldConversion", "Convert best-egg pets to golden", "Only for best-egg gold quests. Uses 10 regular pets per output, keeps a reserve, verifies quest credit")
    interactiveToggle(page("eggs"), "AutoRainbowConversion", "Auto craft rainbow pets for rank quests", "ON for matching best-egg rainbow quests; consumes 10 gold pets per output and may cost diamonds")
    interactiveToggle(page("eggs"), "AutoGoldForRainbow", "Prepare gold pets for rainbow", "Convert best-egg regular pets to gold only when a rainbow rank quest needs them; uses inventory verification")
    ui.rainbowProgress = rowLabel(page("eggs"), "Rainbow pipeline: idle")
    interactiveToggle(page("eggs"), "AutoEggSlots", "Purchase affordable egg slots", "Optional spending, capped by account balance")
    interactiveToggle(page("eggs"), "AutoPetSlots", "Purchase affordable pet slots", "Optional spending, checks the rank cap")
    ui.eggLast = rowLabel(page("eggs"), "Last hatch: not attempted")

    section(page("items"), "QUEST EVENT ITEMS", "Place one item per request and verify progress before repeating")
    interactiveToggle(page("items"), "AutoEventItems", "Spawn quest event items", "Coin jars, comets, mini pinatas, mini lucky blocks; only for matching quests")
    ui.eventLast = rowLabel(page("items"), "Last placement: not attempted")
    interactiveToggle(page("items"), "AutoConsumables", "Use quest consumables", "Use fruit, correct potion tiers and flags for USE quests")
    interactiveToggle(page("items"), "PotionBatchUse", "Try verified multi-potion use", "Probe 2 potions first; if credited, batch up to 8. If unsupported, use faster single requests")
    section(page("items"), "DROPS AND COLLECTION")
    interactiveToggle(page("items"), "AutoCollectOrbs", "Collect orbs", "Collect orb drops while other quests run")
    interactiveToggle(page("items"), "AutoCollectLootbags", "Collect lootbags", "Watch claimable lootbag IDs and submit bounded claim batches")
    interactiveToggle(page("items"), "HideLootbagVisuals", "Hide lootbag visuals", "Hide bags without deleting their models or stopping item collection")
    interactiveToggle(page("items"), "HideYellowBagFX", "Hide yellow bag effects", "Extra suppression for yellow loot visuals in client effect containers only")
    interactiveToggle(page("items"), "SuperMagnet", "Super Magnet", "Modify client collection distances, if the module exists")
    interactiveToggle(page("items"), "HidePickupPopups", "Hide floating pickup numbers", "Remove cosmetic gain text while preserving real rewards")

    section(page("machines"), "COLLECTION QUEST UPGRADES", "Upgrades consume items and possibly diamonds")
    interactiveToggle(page("machines"), "AutoUpgradeCollections", "Upgrade potions and enchants", "Try Tier I-VI surplus stacks; confirm collection quest credit before increasing batches")
    choice(page("machines"), "Highest upgrade input tier", "Select maximum INGREDIENT tier. Using Tier VI creates Tier VII and may cost more diamonds.",
        function() return "Tier "..tostring(Config.MaxUpgradeInputTier).."  >" end,
        function()
            local values={3,4,5,6};local index=1
            for i,value in ipairs(values) do if value==Config.MaxUpgradeInputTier then index=i;break end end
            Config.MaxUpgradeInputTier=values[(index % #values)+1]
            Config.UpgradeTierSelectionVersion=1
        end)
    choice(page("machines"), "Minimum ingredient reserve", "Protect this many items in each material stack",
        function() return tostring(Config.UpgradeMaterialReserve).." items  >" end,
        function()
            local opts={5,8,10,20};local i=1
            for j,v in ipairs(opts) do if v==Config.UpgradeMaterialReserve then i=j;break end end
            Config.UpgradeMaterialReserve=opts[i%#opts+1]
        end)
    choice(page("machines"), "Maximum crafted outputs per request", "Caps potion/enchant bulk crafting to the uncompleted quest and spare materials",
        function() return tostring(Config.UpgradeMaxOutputBatch).." outputs  >" end,
        function()
            local opts={1,5,10,20,40,60};local i=1
            for j,v in ipairs(opts) do if v==Config.UpgradeMaxOutputBatch then i=j;break end end
            Config.UpgradeMaxOutputBatch=opts[i%#opts+1]
        end)
    ui.machineState = rowLabel(page("machines"), "Supercomputer: not checked")
    ui.upgradeLast = rowLabel(page("machines"), "Last upgrade: not attempted")
    note(page("machines"), "Tier I-VI input support uses public PS99 cost tables, adjusted for available crafting mastery. The worker reserves ingredients, verifies quest progress and may spend diamonds. Using Tier VI creates Tier VII. Live game validation is still required.", 76)
    section(page("machines"), "OTHER MACHINES AND REWARDS")
    interactiveToggle(page("machines"), "AutoVending", "Buy vending items for quests", "Optional purchase when collection quests need items")
    interactiveToggle(page("machines"), "AutoClaimRankRewards", "Claim rank rewards", "Claims only rewards detected as eligible")
    interactiveToggle(page("machines"), "AutoFreeGifts", "Claim free gifts", "Collect ready gifts, if the interface is available")
    interactiveToggle(page("machines"), "AutoEggSlots", "Buy egg hatch slots", "Optional diamond spending")
    interactiveToggle(page("machines"), "AutoPetSlots", "Buy pet equip slots", "Optional diamond spending")

    section(page("performance"), "VISUAL OPTIMIZATION", "Reduce distracting effects without disabling the actual rewards")
    interactiveToggle(page("performance"), "HidePickupPopups", "Hide floating number popups", "Conceal cosmetic coin, loot and item gain numbers")
    interactiveToggle(page("performance"), "HideLootbagVisuals", "Hide lootbag models", "Known bag models and effects become invisible; collection remains enabled")
    interactiveToggle(page("performance"), "HidePetVisuals", "Hide pet graphics", "Hide rendered pets without removing controllers or inventory")
    interactiveToggle(page("performance"), "SkipEggAnimations", "Hide hatch animations", "Skip the egg-opening interface where supported")
    interactiveToggle(page("performance"), "RenderOff", "Disable 3D rendering", "Only while the controller is running")
    section(page("performance"), "FARMING PERFORMANCE")
    interactiveToggle(page("performance"), "LowLagMode", "Low-lag worker pacing", "Recommended: fewer scanner and rendering wake-ups while keeping auto rank running")
    interactiveToggle(page("performance"), "FastFarm", "Fast farming loop", "Separate bounded farm worker")
    interactiveToggle(page("performance"), "SpreadPets", "Spread pets across many targets", "Off favors stable, concentrated pet targeting. Turn on only if pets already destroy objects quickly")
    interactiveToggle(page("performance"), "PetTurbo", "Pet movement speed", "Client-side override; does not guarantee server-side effects")
    interactiveToggle(page("performance"), "SuperMagnet", "Collect orbs with magnet", "Avoid visibly chasing orbs across the area")
    choice(page("performance"), "Pet speed multiplier", "Moderate client speed presets (1x-20x); high values can cause lag",
        function() return tostring(Config.PetSpeedMultiplier) .. "x  >" end,
        function()
            local values = {1, 3, 5, 8, 12, 20};local index=1
            for i,v in ipairs(values) do if v==Config.PetSpeedMultiplier then index=i;break end end
            Config.PetSpeedMultiplier=values[(index % #values)+1]
            if state.running and Config.PetTurbo then pcall(petTurbo,true) end
        end)

    section(page("settings"), "PROGRESSION")
    interactiveToggle(page("settings"), "AutoRank", "Enable rank planner", "Detect and prioritize supported current goals")
    interactiveToggle(page("settings"), "AutoParallelQuests", "Parallel quest execution", "Run compatible workers and coordinate travel")
    interactiveToggle(page("settings"), "AutoWorld", "Auto purchase areas", "Use current-world area requirements")
    interactiveToggle(page("settings"), "AutoZoneTeleports", "Game teleport to owned areas", "Optional only; not a cross-world portal bypass")
    interactiveToggle(page("settings"), "AutoRebirth", "Automatic rebirth", "Optional game progression reset")
    interactiveToggle(page("settings"), "AutoEquipBest", "Automatically equip best", "Refresh pets as inventory changes")
    choice(page("settings"), "Rank stopping target", "Unlimited = run until game rank cap or manually paused",
        function() return (Config.TargetRank == 0 and "UNLIMITED" or tostring(Config.TargetRank)) .. "  >" end,
        function()
            local values={0,10,20,30,40,50}
            local i=1
            for j,v in ipairs(values) do if v==Config.TargetRank then i=j;break end end
            Config.TargetRank=values[(i%#values)+1]
        end)
    note(page("settings"), "There are no account-specific hardcoded usernames, and the hub uses no external UI loader. Saved settings only change this local hub's behavior.", 52)

    section(page("diagnostics"), "RUNTIME DIAGNOSTICS", "Use COPY REPORT if a quest sends requests but earns no progress")
    ui.diagStatus = rowLabel(page("diagnostics"), "Status: paused")
    ui.diagApi = rowLabel(page("diagnostics"), "Farm interface: not checked")
    ui.diagHatch = rowLabel(page("diagnostics"), "Hatch: not attempted")
    ui.diagUpgrade = rowLabel(page("diagnostics"), "Upgrade: not attempted")
    toolbar(page("diagnostics"), {{"RECHECK APIS", recheck},
        {"COPY FULL REPORT", function()
            if type(setclipboard)=="function" then pcall(setclipboard,getReport());log("Report copied", "SYSTEM")
            else print(getReport()) end
        end},
        {"STOP / UNLOAD", stop, THEME.red}})
    section(page("diagnostics"), "LATEST SYSTEM LOGS")
    for i=1,10 do
        ui.diagRows[i] = rowLabel(page("diagnostics"), "No log entry")
    end


-- Real expansion pages. Future systems are called out and remain non-interactive.
section(page("events"), "BALLOONS / SLINGSHOT", "Source: uploaded DZ Hub, with 3 rebirths required")
interactiveToggle(page("events"), "AutoPopBalloons", "Automatically pop balloons", "Opt in. Uses active balloon list and slingshot; counts attempts, not confirmed pops")
interactiveToggle(page("events"), "BalloonSmall", "Target Small Balloons", "Filter the eligible balloon registry")
interactiveToggle(page("events"), "BalloonMedium", "Target Medium Balloons", "Filter the eligible balloon registry")
interactiveToggle(page("events"), "BalloonHuge", "Target Huge Balloons", "Filter the eligible balloon registry")
interactiveToggle(page("events"), "HideBalloonVisuals", "Hide balloon models locally", "Reversible cosmetic suppression; keeps game objects and IDs intact")
ui.balloonState = rowLabel(page("events"), "Balloons: waiting for enabled scan")
section(page("events"), "RANK EVENT ITEMS", "Existing auto rank event worker remains in control")
interactiveToggle(page("events"), "AutoEventItems", "Auto spawn quest event items", "Coin jar, comet, mini pinata and mini lucky block items for matching quests")
toolbar(page("events"), {{"VIEW FARM TARGETING", function() showPage("farm") end},
    {"VIEW ITEM COLLECTION", function() showPage("items") end}})
note(page("events"), "Current event-specific currencies and raid automations require readable, current sources. They are not implemented in this build.", 75)

section(page("machines"), "DAILY / TIMED REWARDS", "Additional non-rank automation, with independent cooldowns")
interactiveToggle(page("machines"), "AutoLoginStreak", "Claim daily login streak", "Only claims when LoginStreakCmds.CanClaim() says ready")
interactiveToggle(page("machines"), "AutoTimedRewards", "Claim timed machine rewards", "Checks eligible timestamps, teleports to a loaded machine with a movement lease, then returns")
interactiveToggle(page("machines"), "AutoPlayerUpgrades", "Buy affordable player upgrades", "Opt-in. Maximum 15% of current currency balance per upgrade; confirms upgraded tier")
ui.loginState = rowLabel(page("machines"), "Login streak: not checked")
ui.timedState = rowLabel(page("machines"), "Timed rewards: not checked")
ui.playerUpgradeState = rowLabel(page("machines"), "Player upgrades: not checked")

section(page("performance"), "ADDITIONAL GRAPHICS OPTIMIZATION", "Purely client-side and reversible")
interactiveToggle(page("performance"), "Fullbright", "Fullbright lighting", "Brightens the game locally; restores original Lighting settings on disable/stop")
interactiveToggle(page("performance"), "HideBreakableVisuals", "Hide breakable graphics", "Keeps models and targeting UIDs; visually hides loaded models")
interactiveToggle(page("performance"), "HideBalloonVisuals", "Hide balloon graphics", "Does not destroy or remove the balloon data")

section(page("minigames"), "SOURCE DETECTION", "Module availability is not proof of functional automation")
ui.minigameStatus = rowLabel(page("minigames"), "Not checked")
toolbar(page("minigames"), {{"SCAN LOADED MODULES", function()
    local result=inspectMinigameCapabilities()
    log("Minigame modules: "..result,"SOURCE")
end}})
note(page("minigames"), "Fishing, digsite, obbies and raids are not automatically completed yet. Exact current actions and reward verification must be researched and tested before adding controls.", 87)

section(page("trading"), "READ-ONLY INVENTORY", "No pet transfers, trades or external destinations")
ui.inventoryStatus = rowLabel(page("trading"), "Inventory: not checked")
toolbar(page("trading"), {{"REFRESH INVENTORY COUNTS", function()
    log(inspectInventoryCounts(),"INVENTORY")
end}})
note(page("trading"), "Booth selling and mailbox transfers are intentionally absent until exact game APIs and user-specified item safeguards are available. This tab never transfers or lists pets.", 80)

section(page("notifications"), "LOCAL EVENT ALERTS", "No remote webhook, account data upload or other external destination")
interactiveToggle(page("notifications"), "LocalNotifications", "Record local alerts", "Track rank changes and confirmed daily rewards in the hub")
toolbar(page("notifications"), {{"CLEAR LOCAL ALERTS", function() state.extras.alerts={} end},
    {"OPEN DIAGNOSTICS", function() showPage("diagnostics") end}})
for i=1,7 do
    ui.alertRows = ui.alertRows or {}
    ui.alertRows[i]=rowLabel(page("notifications"), "Waiting for local events...")
end
    ui.helpers = {page = page, showPage = showPage, section = section, note = note,
        toggle = interactiveToggle, choice = choice, rowLabel = rowLabel, toolbar = toolbar,
        create = create, rounded = rounded, label = label, action = action, theme = THEME}
    if type(Modules) == "table" and type(Modules.buildUI) == "function" then
        local okModules, moduleError = pcall(Modules.buildUI, ui, ui.helpers)
        if not okModules then log("Module UI failed: " .. tostring(moduleError), "ERROR") end
    end
    -- Search filters toggles and choices on every page and jumps to the first match.
    pcall(function()
        local box = create("TextBox", {Name = "Search", BackgroundColor3 = THEME.card,
            BorderSizePixel = 0, Position = UDim2.fromOffset(330, 18), Size = UDim2.fromOffset(300, 30),
            Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = THEME.white,
            PlaceholderText = "Search features...", PlaceholderColor3 = THEME.muted,
            Text = "", ClearTextOnFocus = false}, top)
        rounded(box, 7)
        create("UIPadding", {PaddingLeft = UDim.new(0, 10)}, box)
        ui.searchBox = box
        local function applySearch()
            local query = string.lower(tostring(box.Text or ""))
            query = (string.gsub(query, "^%s+", ""))
            query = (string.gsub(query, "%s+$", ""))
            local firstPage = nil
            for _, entry in ipairs(ui.searchIndex or {}) do
                local match = query == "" or string.find(entry.text, query, 1, true) ~= nil
                entry.row.Visible = match
                if match and query ~= "" and not firstPage then firstPage = entry.page end
            end
            if firstPage and firstPage ~= ui.activePage then showPage(firstPage) end
        end
        ui.applySearch = applySearch
        connect(box:GetPropertyChangedSignal("Text"), applySearch)
    end)
    showPage("home")
end

local function renderUI()
    if state.shutdown or not ui.window then return end
    if state.running then refreshPopups(false) end
    for _, refresh in ipairs(ui.toggleRefresh) do refresh() end
    local rank = describe(state.rank)
    local area = tostring(state.area or "unknown")
    ui.metricRank.Text = "RANK " .. rank
    ui.metricZone.Text = area
    if ui.worldNumber then
        ui.worldNumber.Text = "Current world: " .. describe(state.world.number) .. " / " .. describe(state.world.name) .. " (" .. state.world.source .. ")"
    end
    if ui.worldCurrent then ui.worldCurrent.Text="Current zone: "..describe(state.world.zone) end
    if ui.worldBest then
        ui.worldBest.Text = "Highest-owned area: " .. describe(state.world.best) .. " / World " .. describe(state.world.bestWorld)
    end
    if ui.worldTravel then ui.worldTravel.Text="World travel: "..describe(state.worldTransition) end
    ui.metricQuests.Text = tostring(#state.goals) .. " ACTIVE"
    local stage=state.rankStage or {status="not checked",pending={}}
    local pending=stage.pending or {}
    if ui.rankStageLabel then ui.rankStageLabel.Text="Rank status: "..tostring(stage.status) end
    if ui.rankStarsLabel then
        ui.rankStarsLabel.Text="Stars: "..tostring(state.starCount).." / "..tostring(stage.starsNeeded or "?")
            .."  |  Current: "..tostring(state.rank).." / Max: "..tostring(state.maxRank)
    end
    if ui.rankBlockLabel then
        ui.rankBlockLabel.Text="Rank gate: "..(stage.blocked and stage.status or
            (#pending>0 and ("Claim "..#pending.." earned rewards") or "No active area/rebirth block"))
    end
    ui.homeFarm.Text = "FARM    " .. tostring(state.concurrent.farm or "idle")
    ui.homeHatch.Text = "HATCH   " .. tostring(state.concurrent.hatch or "idle")
    ui.homeCollect.Text = "COLLECT " .. tostring(state.concurrent.collect or "idle")
    ui.homeEvent.Text = "ITEMS   " .. tostring(state.spawnLast or "none")
    ui.eggLast.Text = "Last hatch: " .. tostring(state.hatchLastResult or "not attempted")
    ui.eventLast.Text = "Last placement: " .. tostring(state.spawnLast or "not attempted")
    ui.machineState.Text = "Supercomputer: " .. tostring(state.machineStatus or "not checked")
    if ui.rainbowProgress then
        ui.rainbowProgress.Text="Rainbow: "..tostring(state.rainbowLast or "idle")
            .." | Gold prep: "..tostring(state.rainbowPrepLast or "idle")
    end
    ui.upgradeLast.Text = "Last upgrade: " .. tostring(state.upgradeLast or "not attempted")
    if ui.balloonState then ui.balloonState.Text="Balloons: "..tostring(state.extras.balloonLast) end
    if ui.loginState then ui.loginState.Text="Login: "..tostring(state.extras.loginLast) end
    if ui.timedState then ui.timedState.Text="Timed: "..tostring(state.extras.timedLast) end
    if ui.playerUpgradeState then ui.playerUpgradeState.Text="Player upgrades: "..tostring(state.extras.playerUpgradeLast) end
    if ui.inventoryStatus then ui.inventoryStatus.Text="Inventory: "..tostring(state.extras.inventoryLast) end
    if ui.minigameStatus then ui.minigameStatus.Text="Modules: "..tostring(state.extras.capabilityLast) end
    for i,entry in ipairs(ui.alertRows or {}) do entry.Text=state.extras.alerts[i] or "No local alert" end
    ui.diagStatus.Text = "STATUS    " .. tostring(state.status or "unknown")
    ui.diagApi.Text = "FARM API    " .. tostring(state.lastFarmInterface or "none") .. " / Errors: " .. tostring(state.farmError or "none")
    ui.diagHatch.Text = "HATCH    " .. tostring(state.hatchLastApi or "none") .. " / " .. tostring(state.hatchLastResult or "none")
    ui.diagUpgrade.Text = "UPGRADE    " .. tostring(state.upgradeLast or "none")
    for i, row in ipairs(ui.questRows) do
        local goal = state.goals[i]
        row.root.Visible = goal ~= nil
        if goal then
            row.name.Text = tostring(goal.title or goal.kind or "Quest")
                .."  ["..starValue(goal).." star"..(starValue(goal)==1 and "" or "s").."]"
            local progress = tonumber(goal.progress) or 0
            local required = tonumber(goal.required) or 0
            row.progress.Text = tostring(math.floor(progress)) .. " / " .. tostring(math.floor(required))
            row.fill.Size = UDim2.fromScale(math.clamp(progress / math.max(1, required), 0, 1), 1)
        end
    end
    for i, row in ipairs(ui.diagRows) do row.Text = tostring(state.logs[i] or "") end
    ui.footerStatus.Text = (state.running and "● RUNNING  " or "● PAUSED  ") .. tostring(state.status or "")
    ui.footerStatus.TextColor3 = state.running and THEME.green or THEME.gold
    ui.footerRequests.Text = "Hatches " .. tostring(state.attempts.hatch or 0)
        .. "  |  Hits " .. tostring(state.attempts.farm or 0)
    ui.playButton.Text = state.running and "PAUSE" or "START"
    ui.playButton.BackgroundColor3 = state.running and THEME.gold or THEME.green
    if type(Modules) == "table" and type(Modules.render) == "function" then pcall(Modules.render, ui) end
    if type(Modules) == "table" and type(Modules.statusFor) == "function" and ui.chips then
        for _, chip in ipairs(ui.chips) do
            local okChip, chipText, chipColor = false, nil, nil
            if chip.page == ui.activePage then okChip, chipText, chipColor = pcall(Modules.statusFor, chip.key) end
            if okChip and chipText then
                chip.label.Text = chipText
                if chipColor then chip.label.TextColor3 = chipColor end
            end
        end
    end
end

local function mainLoop(generation)
    while not state.shutdown and generation == state.generations do
        if state.running then
            if not healthy("controller") then
                pause("CONTROLLER DISABLED: press RECHECK")
            else
            local ok, errorMessage=pcall(function()
                if not inspectState() then return end
                if state.rankConflict then
                    pause("SAVE/HUD RANK CONFLICT: copy report")
                    return
                end
                local target = tonumber(Config.TargetRank) or 0
                if target > 0 and type(state.rank)=="number" and state.rank >= target then
                    state.status = "TARGET RANK REACHED"
                    pause("TARGET RANK REACHED")
                    return
                end
                if Config.RenderOff then pcall(function() RunService:Set3dRenderingEnabled(false) end) end
                if Config.VYInstantEvents and (not state.vyBreakableListenerBound
                    or (state.vyBreakableFolder and state.vyBreakableFolder.Parent==nil))
                    and cooldownReady("vy:bind",15) then
                    pcall(vyInstallEventListener)
                end
                if Config.AutoClaimRankRewards and healthy("claim") then claimRankRewards() end
                if Config.AutoWorld and healthy("zone") then tryAdvanceWorld() end
                if healthy("upgrades") then guarded("upgrades", extraProgression) end
                if healthy("gifts") then guarded("gifts", claimFreeGift) end
                if Config.AutoRank and Config.AutoParallelQuests then
                    -- Independent goal progress clock: a productive unrelated
                    -- quest must not hide a stalled diamond/chest/farm quest.
                    local oldFarm=state.farmGoal
                    if Config.AdaptiveFarmPriority and oldFarm and eligible(oldFarm)
                        and oldFarm.kind~="minichest" then
                        local watch=state.questWatch[oldFarm.identity]
                        local bestGoal=oldFarm.title:lower():find("best area",1,true)
                        if bestGoal and state.farmFieldValidated==false then
                            -- Arrival/loading isn't a failed quest attempt.
                            if watch then watch.changedAt=now() end
                        end
                        local seconds=now()-(watch and watch.changedAt or now())
                        if seconds>=math.max(30,tonumber(Config.FarmQuestStallSeconds) or 58) then
                            blockGoal(oldFarm,Config.FarmQuestRetrySeconds,
                                "no credited quest progress for "..math.floor(seconds)
                                .."s; trying a different quest")
                            -- Reset that quest's retry clock; otherwise its
                            -- old stale timestamp would re-block it instantly.
                            if watch then watch.changedAt=now() end
                            state.farmSwitchCount=state.farmSwitchCount+1
                            state.farmSwitchLast=oldFarm.title
                            -- Allow future diamond scouting to start afresh.
                            state.diamondZone=nil;state.diamondZoneSince=0
                            state.scannedKey=""
                        end
                    end
                    local farmGoal=chooseFarmGoal()
                    local collectGoal=activeCollectGoal()
                    local hatchGoal=activeHatchQuest()
                    local foreground=chooseGoal()
                    state.farmGoal=farmGoal
                    state.concurrent.farm=farmGoal and farmGoal.title or "background breakables"
                    state.concurrent.hatch=hatchGoal and hatchGoal.title or "none"
                    state.concurrent.collect=collectGoal and collectGoal.title or "none"
                    -- Foreground actions only: world and opted-in event spawns.
                    -- Consumables/collecting/hatching/farming have independent workers.
                    if foreground and (foreground.kind=="zone" or foreground.kind=="rebirth") then
                        performGoal(foreground)
                    end -- Event worker handles every item quest independently.

                    -- v5.2: with the high-frequency worker OFF, this loop owns
                    -- farm ticks; previously parallel mode then farmed nothing.
                    if Config.AutoFarm and not Config.FastFarm and healthy("farm")
                        and not inHatchMovementWindow() and movementAvailable("farm") then
                        local laneGoal=farmGoal
                        if state.hatchNeedsCoins then laneGoal=nil end
                        local farmed,farmErr=pcall(farm,laneGoal)
                        if not farmed then state.farmError=tostring(farmErr);failFeature("farm",farmErr) end
                    end
                    local laneCount=0
                    if farmGoal then laneCount=laneCount+1 end
                    if hatchGoal then laneCount=laneCount+1 end
                    if collectGoal then laneCount=laneCount+1 end
                    state.status="Running "..tostring(laneCount).." quest lanes + passive collection"
                    local label=(farmGoal and ("Farm: "..farmGoal.kind) or "Farm: background")
                        ..(hatchGoal and " | Hatch" or "")
                        ..(collectGoal and (" | Collect "..(collectGoal.kind=="collect_potion" and "potions" or "enchants")) or "")
                    state.chosen=label
                elseif Config.AutoRank then
                    local selected=chooseGoal()
                    if selected then
                        state.chosen=selected.title.."  ["..selected.kind.."]"
                        state.status="Running "..selected.kind
                        state.farmGoal=selected
                        performGoal(selected)
                        local watch=state.questWatch[selected.identity]
                        if watch and now()-watch.changedAt>Config.StallSeconds
                            and selected.kind~="collect_potion" and selected.kind~="collect_enchant" then
                            blockGoal(selected,Config.BlockedQuestSeconds,"no observed progress")
                            watch.changedAt=now()
                        end
                    else
                        state.farmGoal=nil
                        state.chosen="No supported quest ready"
                        state.status="Waiting / fallback farming"
                        if Config.AutoFarm and not Config.FastFarm then farm(nil) end
                    end
                else
                    state.farmGoal=nil
                    state.chosen="Quest planner disabled"
                    state.status="Farming"
                    if Config.AutoFarm and not Config.FastFarm then farm(nil) end
                end
            end)
            if not ok then failFeature("controller",errorMessage) end
            end
        end
        pcall(renderUI)
        task.wait(Config.TickSeconds)
    end
end

-- Separate high-frequency farming controller, never dependent on the 1.2s UI/quest loop.
local function fastWorker(generation)
    while not state.shutdown and generation==state.generations do
        if state.running then
            if Config.PetTurbo and not state.petSpeedApplied and cooldownReady("turbo:retry",30) then
                if not petTurbo(true) then log("Pet turbo module unavailable; normal speed remains", "WAIT") end
            end
            if Config.FastFarm and Config.AutoFarm and healthy("farm") then
                -- Farming runs while collection, hatch-request and consumable
                -- workers operate. Only teleporting conflicts get a lock.
                if not inHatchMovementWindow() and movementAvailable("farm") then
                    local goal=state.farmGoal
                    if not Config.AutoRank or Config.AutoParallelQuests
                        or state.hatchNeedsCoins or not goal or farmKinds[goal.kind] then
                        local chosenFarmGoal = goal
                        if state.hatchNeedsCoins then chosenFarmGoal = nil end
                        local ok,err=pcall(farm,chosenFarmGoal)
                        if not ok then
                            state.farmError=tostring(err)
                            failFeature("farm",err)
                        end
                    end
                end
            end
            if now()>=(state.nextBagBindAt or 0) then
                state.nextBagBindAt=now()+6
                pcall(watchClaimableLootbags)
            end
            local ok,err=pcall(collectDrops)
            if not ok and cooldownReady("collector:error",25) then
                log("Collector: "..describe(err),"ERROR")
            end
        end
        -- The DescendantAdded listeners hide new pet/bag renders in real time.
        -- Full graphics-root discovery is expensive during teleport streaming.
        -- Do not call even the early-return checks on every farm tick.
        if now()>=(state.nextVisualWorkerAt or 0) then
            state.nextVisualWorkerAt=now()+5
            -- v5.2: cosmetic hiding follows its toggle only. Restoring on
            -- pause while the DescendantAdded listeners re-hid new objects
            -- caused hide/restore churn every 5 s.
            if Config.HideLootbagVisuals then
                if state.running then pcall(refreshLootbagVisuals,false) end
            elseif state.lootbagHidden>0 then
                pcall(restoreLootbagVisuals)
            end
            if Config.HidePetVisuals then
                if state.running then pcall(refreshPetVisuals,false) end
            elseif state.petHidden>0 then
                pcall(restorePetVisuals)
            end
        end
        -- Throttle heavy breakable scans and mesh visibility refreshes.
        task.wait(Config.FastFarm and (Config.LowLagMode and 0.20 or 0.14) or 0.6)
    end
end

-- Independent hatch scheduler. It does not depend on the current primary
-- quest, and it never fires an egg request every render frame.
local function hatchWorker(generation)
    while not state.shutdown and generation==state.generations do
        if state.running and Config.AutoHatch and healthy("hatch") then
            local goal=activeHatchQuest()
            local hatchSave=saveData()
            local intended,intent=false,"save unavailable"
            if hatchSave then
                local okIntent,isIntended,why=pcall(hatchIntended,hatchSave)
                if okIntent then intended,intent=isIntended,why
                else intent="hatch planner error: "..describe(isIntended) end
            end
            state.hatchGoalActive=intended
            state.hatchIntent=intent
            if Config.HatchFirstMode and intended and not state.hatchNeedsCoins
                and now()>=(state.hatchNoEggUntil or 0) then
                if not state.hatchExclusive then state.hatchExclusiveSince=now() end
                state.hatchExclusive=true
                state.hatchExclusiveLast="Hatching prioritized: "..tostring(intent)
            else
                state.hatchExclusive=false
                state.hatchExclusiveLast=(intended and now()<(state.hatchNoEggUntil or 0)) and "No egg identified: farming until the next egg check"
                    or (intended and "Eggs unaffordable: farming coins briefly" or "No hatch/material quest")
            end
            if intended then
                -- Currency farming has a bounded window. After it expires,
                -- allow the hatcher to travel back and re-test one egg.
                if state.hatchNeedsCoins and now()>=state.hatchRetryAt then
                    state.hatchNeedsCoins=false
                end
                if Config.SkipEggAnimations then
                    pcall(skipEggAnimation,true) -- retry if the frontend loaded late
                end
                -- Do not let a diamond/farm lane take the character away from
                -- an active egg quest. Normal farming resumes when the goal is
                -- finished or a real one-egg currency refusal occurs.
                local sharingWithBackground = Config.AutoParallelQuests and Config.AutoFarm
                    and Config.FastFarm and state.farmGoal==nil
                    and state.chestDeferralActive
                local allowMove=((Config.HatchFirstMode and state.hatchExclusive)
                    or (not sharingWithBackground and
                        (state.farmGoal==nil or state.farmGoal.kind=="hatch"))
                    or inHatchMovementWindow()) and movementAvailable("hatch")
                local ok,err=pcall(hatch,allowMove and not state.hatchNeedsCoins)
                if not ok then failFeature("hatch",err) end
            elseif state.hatchLastResult~="Hatch suspended: no active hatch or rainbow material need" then
                state.hatchLastResult="Hatch suspended: no active hatch or rainbow material need"
                state.hatchFarmRemoteProbe=nil
            end
        end
        task.wait(0.3)
    end
end

-- Passive quest worker never selects a destination or pauses the farm worker.
-- Crucial distinction: COLLECT potions means obtain new items (lootbags,
-- drops, optionally vending). USE potions means consume owned potions.
local function passiveQuestWorker(generation)
    while not state.shutdown and generation==state.generations do
        if state.running and Config.AutoRank and Config.AutoParallelQuests then
            local summary={}
            for _,goal in ipairs(state.goals) do
                if Config.AutoConsumables and (goal.kind=="fruit" or goal.kind=="potion"
                    or goal.kind=="flag") and eligible(goal) then
                    if healthy(goal.kind) then
                        local ok,err=pcall(consumeTracked,goal)
                        if not ok then failFeature(goal.kind,err) end
                        summary[#summary+1]=goal.kind
                    end
                end
            end
            state.concurrent.passive=(#summary>0) and table.concat(summary,",") or "none"
            local collectGoal=activeCollectGoal()
            if collectGoal and Config.AutoVending and not inHatchMovementWindow()
                and (not state.farmGoal or not Config.AutoFarm) then
                local ok,err=pcall(vendingForGoal,collectGoal)
                if not ok then failFeature("vending",err) end
            end
            if collectGoal and cooldownReady("collect:explain",65) then
                log("Collect-"..(collectGoal.kind=="collect_potion" and "potion" or "enchant")
                    .." quest: breaking objects and claiming orbs/lootbags; do NOT consume items."
                    ..(Config.AutoVending and " Optional vending enabled." or " Vending disabled (no automatic spending)."),"QUEST")
            end
        end
        task.wait(1.5)
    end
end

-- Events and collection upgrades are independent of choosing a foreground
-- quest. One quest can farm an existing jar while a hatch quest keeps advancing.
local function eventWorker(generation)
    while not state.shutdown and generation==state.generations do
        if state.running and Config.AutoRank and Config.AutoEventItems
            and not (state.rankStage and state.rankStage.ready) then
            -- Prioritize high-star event quests without spawning multiple items
            -- simultaneously in the same break area.
            local eventGoals={}
            for _,candidate in ipairs(state.goals) do
                if itemTypes[candidate.kind] and eligible(candidate) then
                    table.insert(eventGoals,candidate)
                end
            end
            table.sort(eventGoals,function(a,b)
                if starValue(a)~=starValue(b) then return starValue(a)>starValue(b) end
                return (a.required-a.progress)<(b.required-b.progress)
            end)
            for _,goal in ipairs(eventGoals) do
                if itemTypes[goal.kind] and eligible(goal)
                    and not inHatchMovementWindow() and movementAvailable("event") then
                    local ok,spawned=pcall(spawnQuestObject,goal)
                    if not ok then failFeature("spawn-"..goal.kind,spawned) end
                    -- At most one new item per tick; no repeated blind spawns.
                    if ok and spawned then break end
                end
            end
        end
        task.wait(0.9) -- More responsive to newly available rank-quest items.
    end
end
local function upgradeWorker(generation)
    while not state.shutdown and generation==state.generations do
        if state.running and Config.AutoUpgradeCollections
            and not (state.rankStage and state.rankStage.ready)
            and not inHatchMovementWindow() then
            local ok,err=pcall(tryCollectionUpgrade)
            if not ok then failFeature("upgrades-collect",err) end
        elseif state.upgradeVisitStart>0
            and (not state.running or not Config.AutoUpgradeCollections) then
            pcall(finishUpgradeVisit)
        end
        task.wait(1)
    end
end
local function goldConversionWorker(generation)
    while not state.shutdown and generation==state.generations do
        if state.running and Config.AutoGoldConversion
            and not inHatchMovementWindow() then
            local good,err=pcall(tryGoldenConversion)
            if not good and cooldownReady("gold:error",45) then
                state.goldenLast="Error: "..describe(err)
                log(state.goldenLast,"GOLD")
            end
        end
        task.wait(1.5)
    end
end
local function rainbowConversionWorker(generation)
    while not state.shutdown and generation==state.generations do
        if state.running and Config.AutoRainbowConversion and not inHatchMovementWindow() then
            local good,err=pcall(tryRainbowConversion)
            if not good and cooldownReady("rainbow:error",45) then
                state.rainbowLast="Error: "..describe(err)
                log(state.rainbowLast,"RAINBOW")
            end
        end
        task.wait(1.7)
    end
end
loadSettings()
local ok = refreshClients()
if ok then
    inspectState()
    log("Readable PS99 save module detected")
else
    log("PS99 save module unavailable. Hub will remain safely paused.","WAIT")
end
local uiOK, uiError = pcall(buildUI)
if not uiOK then
    log("UI initialization failed (automation controller remains loaded): " .. tostring(uiError), "ERROR")
    if state.gui then pcall(function() state.gui:Destroy() end); state.gui = nil end
end
bindPopupListeners()
if Config.VYInstantEvents then pcall(vyInstallEventListener) end
if Config.HideLootbagVisuals then pcall(refreshLootbagVisuals,true) end
if Config.HidePetVisuals then pcall(refreshPetVisuals,true) end
if Config.Fullbright then pcall(applyFullbright) end
state.status = uiOK and "PAUSED: press START" or "UI unavailable: see executor console"
if state.rankConflict then state.status="SAVE/HUD RANK CONFLICT: copy report" end
if uiOK then pcall(renderUI) end
state.generations=state.generations+1
local threadGeneration=state.generations
task.spawn(function() mainLoop(threadGeneration) end)
task.spawn(function() fastWorker(threadGeneration) end)
task.spawn(function() hatchWorker(threadGeneration) end)
task.spawn(function() passiveQuestWorker(threadGeneration) end)
task.spawn(function() eventWorker(threadGeneration) end)
task.spawn(function() upgradeWorker(threadGeneration) end)
task.spawn(function() goldConversionWorker(threadGeneration) end)
task.spawn(function() rainbowConversionWorker(threadGeneration) end)
task.spawn(function() extrasWorker(threadGeneration) end)
if type(Modules.worker) == "function" then task.spawn(function() Modules.worker(threadGeneration) end) end

environment.RankPilot = {
    Version="5.2.0-ModuleHub-Engine4.6",
    Config=Config,
    Status=state,
    Start=run,
    Pause=pause,
    Recheck=recheck,
    Stop=stop,
    GetReport=getReport,
    GetGoals=function() return state.goals end,
    HatchNow=function() return hatch(true) end,
    SkipAnimation=skipEggAnimation,
    InspectInventory=inspectInventoryCounts,
    InspectMinigames=inspectMinigameCapabilities,
    Extras=state.extras,
    Modules=Modules,
    ModuleState=state.modules,
}
log("RankPilot X v5.2 loaded: v5.1 rank engine with fixes, "..tostring(#Modules.list).." feature modules, 16-page hub.","SYSTEM")
