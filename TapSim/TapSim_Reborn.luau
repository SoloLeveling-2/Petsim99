-- =====================================================================================
--  Tap Simulator REBORN Helper v1.1 (Roblox place 72858262610964, by Cursor Makers)
--
--  One plain, readable file. It loads NO code from the internet (no loadstring/HttpGet),
--  sends nothing anywhere, and only fires the game's own request remotes, the same ones
--  its buttons fire. Every feature starts OFF except Anti-AFK; turn them on in the window.
--  Safe in autoexec: anything the game has not loaded yet is looked up again later.
--
--    Auto tap        TapService.TapRequested, paced to the server's tap interval
--    Game clicker    AutoClickService.AutoClickRequested (needs the game's Auto Clicker)
--    Auto rebirth    RebirthService.RebirthRequested, biggest unlocked pack you can afford
--    Auto hatch      EggService.EggHatchRequested, best affordable egg or a chosen one;
--                    stands you next to the egg (the server refuses hatches from afar)
--    Equip best      PetService.PetActionRequested { Action = "EquipBest" }
--    Upgrades        UpgradeService.Purchase, Skill tree: SkillTreeService.Unlock
--    Claims          QuestService.ClaimQuest, TapChestService.Claim, OfflineRewardsService
--    Anti-AFK        clicks through the idle kick
--    Remote list     prints the game's remote services (to re-check names after an update)
--
--  Game protocol (remote names, payloads, data paths, egg stand positions) as documented
--  in Slopix Hub's MIT-licensed source (github.com/TrustyCoding/slopix-hub). The code here
--  is written separately. Live status: Implemented Unverified until run in the game.
--  Using scripts breaks the Roblox Terms of Use and can get an account banned.
-- =====================================================================================
local VERSION = "1.1"
local GLOBAL_KEY = "TapSimReborn"
local SETTINGS_FILE = "TapSimReborn_settings.json"

local DEFAULTS = {
    AutoTap = false, TapRate = 10, GameAutoClicker = false,
    AutoRebirth = false, AutoHatch = false, HatchTeleport = true, HatchEgg = "",
    AutoEquip = false, EquipEvery = 5, AutoUpgrades = false, AutoSkillTree = false,
    AutoQuests = false, AutoChests = false, ClaimOffline = false, AntiAfk = true,
}

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- selene: allow(global_usage)
local genv = (type(getgenv) == "function" and getgenv()) or _G

if not game:IsLoaded() then game.Loaded:Wait() end

-- Re-execution: stop the copy that is already running before starting this one.
do
    local old = genv[GLOBAL_KEY]
    if type(old) == "table" and type(old.Stop) == "function" then
        pcall(old.Stop)
    end
end

-- Lifetime --------------------------------------------------------------------------------

local State = { alive = true, notes = {} }
local connections = {}

local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    print("[TapSim] " .. table.concat(parts, " "))
end

-- Game modules need identity 2; executor and GUI work stays at 8 (same as VY/tools probes).
local function setIdentity(level)
    if type(setthreadidentity) == "function" then pcall(setthreadidentity, level) end
end
local function asGame(fn, ...)
    setIdentity(2)
    local results = table.pack(pcall(fn, ...))
    setIdentity(8)
    return table.unpack(results, 1, results.n)
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

-- Workers report each distinct error once. A worker that errors (a character mid-respawn,
-- a game module that changed) starts again 3 seconds later instead of staying dead.
local lastError = {}
local function report(name, err)
    if State.alive and lastError[name] ~= tostring(err) then
        lastError[name] = tostring(err)
        log("loop error in", name .. ":", err)
    end
end
local function spawnWorker(name, fn)
    task.spawn(function()
        while State.alive do
            local ok, err = pcall(fn)
            if ok then return end
            report(name, err)
            task.wait(3)
        end
    end)
end
local function loop(name, every, fn)
    spawnWorker(name, function()
        while State.alive do
            local ok, err = pcall(fn)
            if not ok then report(name, err) end
            task.wait(every)
        end
    end)
end

local function note(feature, text) State.notes[feature] = text end

-- Settings --------------------------------------------------------------------------------

local Settings = table.clone(DEFAULTS)
pcall(function()
    if type(isfile) == "function" and type(readfile) == "function" and isfile(SETTINGS_FILE) then
        local saved = HttpService:JSONDecode(readfile(SETTINGS_FILE))
        for key, value in pairs(saved) do
            if DEFAULTS[key] ~= nil and type(value) == type(DEFAULTS[key]) then Settings[key] = value end
        end
    end
end)
local function saveSettings()
    if type(writefile) == "function" then
        pcall(writefile, SETTINGS_FILE, HttpService:JSONEncode(Settings))
    end
end
local function on(key) return State.alive and Settings[key] == true end

-- Game access -----------------------------------------------------------------------------

-- Remotes use sleitnick Comm: ReplicatedStorage.RemoteServices.<Service>.RE|RF.<Name>.
-- A remote that is not there yet is waited for as long as it takes (the game may still be
-- loading); after 30 seconds the wait is logged once, since an update may have renamed it.
local remoteCache, remoteWaitLogged = {}, {}
local function findRemote(service, name)
    local services = RS:FindFirstChild("RemoteServices")
    local svc = services and services:FindFirstChild(service)
    if not svc then return nil end
    local re, rf = svc:FindFirstChild("RE"), svc:FindFirstChild("RF")
    return (re and re:FindFirstChild(name)) or (rf and rf:FindFirstChild(name))
end
local function remote(service, name)
    local key = service .. "/" .. name
    local found = remoteCache[key]
    if found and found.Parent then return found end
    local started = os.clock()
    found = findRemote(service, name)
    while not found do
        if not State.alive then error("stopped", 0) end
        if os.clock() - started > 30 and not remoteWaitLogged[key] then
            remoteWaitLogged[key] = true
            log("still waiting for remote " .. key .. " (renamed by an update? press Print remote list)")
        end
        task.wait(0.5)
        found = findRemote(service, name)
    end
    remoteCache[key] = found
    return found
end

local function fire(service, name, payload)
    if not State.alive then return end
    remote(service, name):FireServer(payload)
end

-- InvokeServer can hang forever; give up after 10 seconds so a feature never stalls.
local function invoke(service, name, ...)
    if not State.alive then return false, "stopped" end
    local rf = remote(service, name)
    local args = table.pack(...)
    local done, result = false, nil
    task.spawn(function()
        result = table.pack(pcall(function() return rf:InvokeServer(table.unpack(args, 1, args.n)) end))
        done = true
    end)
    local deadline = os.clock() + 10
    while not done and os.clock() < deadline do task.wait(0.03) end
    if not done then return false, "timeout" end
    return table.unpack(result, 1, result.n)
end

-- Shared config modules under ReplicatedStorage.Shared, required once. One that is not
-- there yet (the game is still loading) is looked up again 5 seconds later.
local sharedCache, sharedRetryAt = {}, {}
local function shared(...)
    local key = table.concat({ ... }, ".")
    if sharedCache[key] then return sharedCache[key] end
    if os.clock() < (sharedRetryAt[key] or 0) then return nil end
    local path = { ... }
    local ok, module = asGame(function()
        local nodeAt = RS:FindFirstChild("Shared")
        for _, part in ipairs(path) do nodeAt = nodeAt and nodeAt:FindFirstChild(part) end
        return nodeAt and require(nodeAt)
    end)
    if ok and module then
        sharedCache[key] = module
        return module
    end
    sharedRetryAt[key] = os.clock() + 5
    return nil
end
-- Calls a function of a game module; returns its first result or nil.
local function call(module, method, ...)
    local fn = module and module[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = asGame(fn, ...)
    if ok then return value end
    return nil
end

-- Player data is a MadStudio Replica read through the client's DataController. Read only.
-- Until the controller exists (the game is still loading) it is looked for every 5 seconds.
local dataController, dataRetryAt = nil, 0
local function data()
    if not dataController and os.clock() >= dataRetryAt then
        local ok, module = asGame(function()
            local controllers = RS:FindFirstChild("Controllers")
            local core = controllers and controllers:FindFirstChild("Core")
            local dc = core and core:FindFirstChild("DataController")
            return dc and require(dc)
        end)
        if ok and type(module) == "table" then dataController = module else dataRetryAt = os.clock() + 5 end
    end
    if not dataController then return nil end
    local ok, replica = asGame(function()
        return (dataController.GetReplica and dataController:GetReplica()) or (dataController.Get and dataController:Get())
    end)
    return ok and type(replica) == "table" and type(replica.Data) == "table" and replica.Data or nil
end

local function field(tbl, ...)
    local value = tbl
    for i = 1, select("#", ...) do
        if type(value) ~= "table" then return nil end
        value = value[(select(i, ...))]
    end
    return value
end
local function coins(d) return tonumber(field(d, "Currencies", "Coins")) or 0 end

local function short(n)
    n = tonumber(n) or 0
    for _, unit in ipairs({ { 1e33, "Dc" }, { 1e30, "No" }, { 1e27, "Oc" }, { 1e24, "Sp" }, { 1e21, "Sx" },
        { 1e18, "Qi" }, { 1e15, "Q" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        if n >= unit[1] then return string.format("%.1f%s", n / unit[1], unit[2]) end
    end
    return tostring(math.floor(n))
end

local function rootPart()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

-- Auto tap --------------------------------------------------------------------------------
-- The server credits one tap per GameConfig.ManualTapInterval (0.1s) and drops faster ones.
-- It also only accepts a ClientSequence above the last one it took this session, so the
-- counter lives in getgenv and survives re-execution. If a run of taps goes unanswered on
-- TapResult (the game's own client got ahead), the counter jumps forward: doubling up to
-- 2^50, then a million at a time, so it only ever rises and stays an exact integer (a double
-- stops counting by 1 at 2^53, after which every tap would look stale).

local function tapInterval()
    local interval = tonumber(field(shared("Core", "GameConfig"), "ManualTapInterval"))
    return (interval and interval > 0) and interval or 0.1
end
local function maxRate() return math.max(1, math.floor(1 / tapInterval() + 1e-6)) end
local SEQ_KEY = "__TapSimTapSequence"
local tapSeq = tonumber(genv[SEQ_KEY]) or 0
local tapStats = { sent = 0, answered = 0, unanswered = 0, lastAnswer = os.clock(), resyncs = 0, listening = false }

spawnWorker("tap:results", function()
    connect(remote("TapService", "TapResult").OnClientEvent, function(result)
        if type(result) == "table" and result.ClientSequence ~= nil then
            tapStats.answered += 1
            tapStats.unanswered = 0
            tapStats.lastAnswer = os.clock()
        end
    end)
    tapStats.listening = true
end)

spawnWorker("tap:auto", function()
    local tapRemote = remote("TapService", "TapRequested")
    while State.alive do
        if on("AutoTap") then
            if tapStats.listening and tapStats.unanswered >= 25 and os.clock() - tapStats.lastAnswer > 2 then
                tapSeq = math.max(tapSeq + 1000000, math.min(tapSeq * 2, 2 ^ 50))
                tapStats.unanswered, tapStats.lastAnswer = 0, os.clock()
                tapStats.resyncs += 1
            end
            tapSeq += 1
            genv[SEQ_KEY] = tapSeq
            tapRemote:FireServer({ Auto = false, ClientSequence = tapSeq, Source = "button" })
            tapStats.sent += 1
            tapStats.unanswered += 1
            local top = maxRate()
            local rate = math.clamp(tonumber(Settings.TapRate) or top, 1, top)
            -- Jitter only lengthens a gap; a gap under the server interval is a wasted tap.
            task.wait(math.max(1 / rate, tapInterval() * 1.04) * (1 + math.random() * 0.12))
        else
            task.wait(0.2)
        end
    end
end)

-- Auto rebirth ----------------------------------------------------------------------------
-- RebirthRequested { Index } buys 5^(Index-1) rebirths priced at your current rebirth count,
-- so the biggest pack you can afford is the cheapest per rebirth. Only unlocked buttons
-- (1 + Upgrades.RebirthButtons) are pressed, at most every 1.5 seconds.

local rebirthStats = { last = -math.huge, startedAt = nil }

local function packAmount(index)
    return tonumber(call(shared("Progression", "RebirthConfig"), "GetAmountFromIndex", index)) or 5 ^ (index - 1)
end
local function packPrice(d, index)
    local rebirths = tonumber(field(d, "Statistics", "Rebirths")) or 0
    return tonumber(call(shared("Progression", "RebirthConfig"), "GetPrice", packAmount(index), rebirths))
end
local function unlockedButtons(d)
    local upgrades = tonumber(field(d, "Upgrades", "RebirthButtons")) or 0
    local world = field(d, "Progression", "World") or "Main"
    local buttons = shared("Progression", "RebirthButtonConfig")
    if buttons then
        local unlocked = call(buttons, "GetUnlockedCount", upgrades, world)
        local count = unlocked and call(buttons, "GetOptionCount", unlocked, world)
        if type(count) == "number" then return count end
    end
    return 1 + math.clamp(math.floor(upgrades), 0, 13)
end
local function bestPack(d)
    for index = unlockedButtons(d), 1, -1 do
        local price = packPrice(d, index)
        if price and price <= coins(d) then return index, price end
    end
    return nil
end

loop("rebirth", 0.25, function()
    if not on("AutoRebirth") then return end
    local d = data()
    if not d then return end
    if not shared("Progression", "RebirthConfig") then
        note("Rebirth", "waiting for the game's rebirth prices (Shared.Progression.RebirthConfig)")
        return
    end
    -- Counted from the save, so a refused request never shows up as a rebirth.
    local total = tonumber(field(d, "Statistics", "Rebirths")) or 0
    rebirthStats.startedAt = rebirthStats.startedAt or total
    local index, price = bestPack(d)
    if not index then
        note("Rebirth", "saving for x1 (" .. short(packPrice(d, 1) or 0) .. " coins)")
        return
    end
    if os.clock() - rebirthStats.last < 1.5 then return end
    rebirthStats.last = os.clock()
    local auto = call(shared("Progression", "SkillTreeFormula"), "HasAutoRebirth", d) == true
    fire("RebirthService", "RebirthRequested", auto and { Auto = true, Index = index } or { Index = index })
    note("Rebirth", string.format("pressed x%s for %s coins (+%s rebirths this session)", short(packAmount(index)),
        short(price), short(total - rebirthStats.startedAt)))
end)

-- Auto hatch ------------------------------------------------------------------------------
-- EggHatchRequested { Egg, Count, Auto, Seq } is answered on EggHatchResult with the same
-- Seq; the server holds the answer until the egg may open again, so one request in flight
-- is the fastest rate. Count: 8 with the x8 pass or an OctoHatch boost, else 3, else 1.

local EGGS = {} -- name -> { price, island }, filled once the game's egg config is readable
local function loadEggs()
    if next(EGGS) then return EGGS end
    local cfg = shared("Pets", "LaunchEggConfig")
    if type(cfg) == "table" then
        for name, def in pairs(cfg) do
            if type(def) == "table" and name ~= "Test" then
                EGGS[name] = { price = tonumber(def.Price) or 0, island = def.Island }
            end
        end
    end
    return EGGS
end

-- Where each egg stands (workspace.Eggs is streamed and may be empty far away).
local EGG_POSITIONS = {
    Basic = Vector3.new(6, -511, -1833), Spotted = Vector3.new(-5, -511, -1822),
    Spiked = Vector3.new(-23, -513, -1707), Sky = Vector3.new(-88, -48, -1904),
    Nimbus = Vector3.new(-97, -48, -1891), Pumpkin = Vector3.new(-143, 881, -1833),
    Forest = Vector3.new(-297, 1228, 267), Mushroom = Vector3.new(-6, 2032, -1925),
    Mycelium = Vector3.new(-21, 2032, -1932), Snowman = Vector3.new(-258, 2547, 345),
    Cactus = Vector3.new(-203, 3632, -1863), Crystal = Vector3.new(-53, 5438, -1992),
    Geode = Vector3.new(-68, 5438, -1987), Void = Vector3.new(-204, 7676, -1885),
    Volcanic = Vector3.new(-2, 11073, -1913), Draconic = Vector3.new(9, 11072, -1905),
}
local STAND_RANGE = 9

local function eggTotal(d, egg, count)
    local base = EGGS[egg].price
    return tonumber(call(shared("Pets", "EggPricing"), "GetTotal", d, egg, base, count)) or base * count
end
local function hatchCount(d, egg)
    local have = coins(d)
    local octo = call(shared("Monetization", "GamepassPerks"), "Has", d, "x8Egg") == true
        or call(shared("Items", "BoostFormula"), "HasType", d, "OctoHatch") == true
    if octo and eggTotal(d, egg, 8) <= have then return 8 end
    if eggTotal(d, egg, 3) <= have then return 3 end
    if eggTotal(d, egg, 1) <= have then return 1 end
    return nil
end

local function eggModel(egg)
    local folder = workspace:FindFirstChild("Eggs")
    return folder and folder:FindFirstChild(egg)
end
local function eggCenter(egg)
    local model = eggModel(egg)
    if model then
        local part = model:FindFirstChild("Egg")
        if part and part:IsA("BasePart") then return part.Position end
        local ok, pivot = pcall(model.GetPivot, model)
        if ok then return pivot.Position end
    end
    return EGG_POSITIONS[egg]
end

local function hatchable(d, egg)
    if not loadEggs()[egg] or field(d, "Eggs", "Unlocked", egg) ~= true or not eggCenter(egg) then return false end
    local island = EGGS[egg].island
    return island == nil or island == "Spawn" or field(d, "Progression", "UnlockedIslands", island) == true
end

local function eggList(d)
    local list = {}
    for egg in pairs(loadEggs()) do
        if not d or hatchable(d, egg) then list[#list + 1] = egg end
    end
    table.sort(list, function(a, b) return EGGS[a].price > EGGS[b].price end)
    return list
end

local hatchState = { current = nil, refused = {}, hatched = 0, seq = 7000000, waiting = nil }

-- Best affordable egg, but only move up to a pricier egg with 5 batches of it in the bank,
-- so a balance hovering at one price does not bounce you between eggs.
local function chooseEgg(d)
    local chosen = Settings.HatchEgg
    if chosen ~= "" then
        return (hatchable(d, chosen) and chosen) or nil
    end
    local current = hatchState.current
    local stay = current and hatchable(d, current) and hatchCount(d, current) ~= nil
    for _, egg in ipairs(eggList(d)) do
        if os.clock() >= (hatchState.refused[egg] or 0) then
            if stay and egg == current then return current end
            local count = hatchCount(d, egg)
            if count then
                local better = stay and EGGS[egg].price > EGGS[current].price
                if not better or coins(d) >= eggTotal(d, egg, count) * 5 then return egg end
            end
        end
    end
    return stay and current or nil
end

local function nearEgg(egg)
    local hrp, center = rootPart(), eggCenter(egg)
    return hrp ~= nil and center ~= nil and (hrp.Position - center).Magnitude <= STAND_RANGE
end

-- Solid ground on a ring around the egg (the pedestal does not collide), else beside it.
local function standSpot(egg, center)
    local ok, spot = pcall(function()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        -- Built without nil holes: Roblox cannot cast { nil, character } to an instance list.
        local ignore = {}
        for _, inst in ipairs({ eggModel(egg) or false, player.Character or false }) do
            if inst then ignore[#ignore + 1] = inst end
        end
        params.FilterDescendantsInstances = ignore
        for step = 0, 7 do
            local angle = step * math.pi / 4
            local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 5.5
            local hit = workspace:Raycast(center + offset + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
            if hit and hit.Instance.CanCollide and hit.Normal.Y > 0.6 then
                local pos = hit.Position + Vector3.new(0, 3, 0)
                if (pos - center).Magnitude <= STAND_RANGE then return CFrame.new(pos) end
            end
        end
        return nil
    end)
    return (ok and spot) or CFrame.new(center + Vector3.new(0, -1, 5))
end

local function goToEgg(egg)
    local target, hrp = eggCenter(egg), rootPart()
    if not target or not hrp then return false end
    task.spawn(pcall, function() player:RequestStreamAroundAsync(target, 5) end)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = CFrame.new(target + Vector3.new(0, 6, 0))
    local deadline = os.clock() + 8
    while State.alive and os.clock() < deadline and not (eggModel(egg) and eggModel(egg):FindFirstChild("Egg")) do
        task.wait(0.2)
    end
    hrp = rootPart()
    if not hrp then return false end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = standSpot(egg, eggCenter(egg))
    task.wait(0.3)
    return true
end

spawnWorker("hatch:results", function()
    connect(remote("EggService", "EggHatchResult").OnClientEvent, function(payload)
        local w = hatchState.waiting
        if w and type(payload) == "table" and (payload.Seq == w.seq or (payload.Seq == nil and payload.Egg == w.egg)) then
            w.result = payload
        end
    end)
end)

local function hatchOnce(egg, count)
    hatchState.seq += 1
    local slot = { seq = hatchState.seq, egg = egg }
    hatchState.waiting = slot
    fire("EggService", "EggHatchRequested", { Egg = egg, Count = count, Auto = true, Seq = slot.seq })
    local deadline = os.clock() + 12
    while State.alive and not slot.result and os.clock() < deadline do task.wait(0.03) end
    if hatchState.waiting == slot then hatchState.waiting = nil end
    return slot.result
end

spawnWorker("hatch:auto", function()
    local tooFar = 0
    while State.alive do
        local d = on("AutoHatch") and data()
        local egg = d and chooseEgg(d)
        local count = egg and hatchCount(d, egg)
        if not on("AutoHatch") then
            task.wait(0.2)
        elseif not d then
            task.wait(0.5)
        elseif not egg or not count then
            note("Hatch", Settings.HatchEgg ~= "" and ("cannot hatch " .. Settings.HatchEgg .. " yet (coins or locked)")
                or "no egg you can afford yet")
            task.wait(1)
        else
            if egg ~= hatchState.current then hatchState.current, tooFar = egg, 0 end
            if Settings.HatchTeleport and not nearEgg(egg) then
                note("Hatch", "going to the " .. egg .. " egg")
                goToEgg(egg)
            end
            local result = hatchOnce(egg, count)
            if not result then
                note("Hatch", "no answer from the server; retrying")
                task.wait(0.5)
            elseif result.Success then
                tooFar = 0
                hatchState.hatched += tonumber(result.Rolls) or count
                note("Hatch", string.format("%s x%d (%d this session)", egg, count, hatchState.hatched))
            elseif result.Error == "RateLimited" or result.Error == "Cancelled" then
                task.wait(0.4)
            elseif result.Error == "TooFar" then
                tooFar += 1
                note("Hatch", "too far from the " .. egg .. " egg")
                if tooFar >= 3 or not Settings.HatchTeleport then task.wait(2) else goToEgg(egg) end
            elseif result.Error == "StorageFull" then
                note("Hatch", "pet storage is full")
                task.wait(2)
            elseif result.Error == "NotEnoughCoins" then
                hatchState.refused[egg] = os.clock() + 5
            elseif result.Error == "IslandLocked" then
                hatchState.refused[egg] = os.clock() + 60
                note("Hatch", egg .. " is on an island you have not unlocked")
            else
                note("Hatch", "refused: " .. tostring(result.Error or result.Reason or "unknown"))
                task.wait(1)
            end
        end
    end
end)

-- Equip best, upgrades, skill tree -------------------------------------------------------

local lastEquip = -math.huge
loop("equip", 1, function()
    if not on("AutoEquip") then return end
    if os.clock() - lastEquip >= math.clamp(tonumber(Settings.EquipEvery) or 5, 2, 60) then
        lastEquip = os.clock()
        fire("PetService", "PetActionRequested", { Action = "EquipBest" })
        note("Equip", "equipped best pets")
    end
end)

local UPGRADE_ORDER = { "FreeAutoClicker", "ClickMultiplier", "HatchSpeed", "CriticalChance", "AutoClickerSpeed", "Teleport" }
local function upgradeOrder()
    local order = field(shared("Progression", "UpgradeConfig"), "Order")
    return (type(order) == "table" and #order > 0) and order or UPGRADE_ORDER
end
local upgradeBlocked = {} -- name -> os.clock() until which it is skipped
loop("upgrades", 2, function()
    if not on("AutoUpgrades") then return end
    for _, name in ipairs(upgradeOrder()) do
        if not on("AutoUpgrades") then return end
        if os.clock() >= (upgradeBlocked[name] or 0) then
            local ok, res = invoke("UpgradeService", "Purchase", { Name = name })
            if ok and type(res) == "table" then
                if res.Success then
                    note("Upgrades", string.format("bought %s (level %s)", tostring(name), tostring(res.Current or "?")))
                elseif res.Reason ~= "RateLimited" then
                    upgradeBlocked[name] = os.clock() + 30
                end
            end
            task.wait(0.4)
        end
    end
end)

local SKILL_NODES = {} -- filled once the game's skill tree config is readable
local function loadSkillNodes()
    if #SKILL_NODES > 0 then return SKILL_NODES end
    local cfg = shared("Progression", "SkillTreeConfig")
    local seen = {}
    local function walk(t, depth)
        if depth > 8 then return end
        for _, value in pairs(t) do
            if type(value) == "table" then
                if type(value.Name) == "string" and not seen[value.Name] then
                    seen[value.Name] = true
                    SKILL_NODES[#SKILL_NODES + 1] = value.Name
                end
                walk(value, depth + 1)
            end
        end
    end
    if type(cfg) == "table" then walk(cfg, 0) end
    table.sort(SKILL_NODES)
    return SKILL_NODES
end
local skillBlocked = {}
loop("skilltree", 3, function()
    if not on("AutoSkillTree") then return end
    local d = data()
    if not d then return end
    for _, nodeName in ipairs(loadSkillNodes()) do
        if not on("AutoSkillTree") then return end
        if field(d, "SkillTree", "Unlocked", nodeName) ~= true and os.clock() >= (skillBlocked[nodeName] or 0) then
            local ok, res = invoke("SkillTreeService", "Unlock", { Name = nodeName })
            if ok and type(res) == "table" and res.Success then
                note("Skills", "unlocked " .. nodeName)
                d = data() or d
            else
                skillBlocked[nodeName] = os.clock() + 15
            end
            task.wait(0.3)
        end
    end
end)

-- Claims ----------------------------------------------------------------------------------

local claimTried = {} -- "kind:id" -> os.clock() of the last try
local function due(kind, id, every)
    local key = kind .. ":" .. tostring(id)
    if os.clock() - (claimTried[key] or -math.huge) < every then return false end
    claimTried[key] = os.clock()
    return true
end

loop("quests", 2, function()
    if not on("AutoQuests") then return end
    local quests = field(data(), "Quests")
    if type(quests) ~= "table" then return end
    for id, quest in pairs(quests) do
        if type(quest) == "table" and quest.Completed and not quest.Claimed and due("quest", id, 10) then
            local ok, res = invoke("QuestService", "ClaimQuest", { Quest = id })
            if ok and res ~= false and not (type(res) == "table" and res.Success == false) then
                note("Quests", "claimed " .. tostring(id))
            end
            task.wait(0.3)
        end
    end
end)

loop("chests", 3, function()
    if not on("AutoChests") then return end
    local chests = field(data(), "TapChests")
    if type(chests) ~= "table" then return end
    for id in pairs(chests) do
        if due("chest", id, 10) then
            local ok, res = invoke("TapChestService", "Claim", id)
            if ok and res ~= false and not (type(res) == "table" and res.Success == false) then
                note("Chests", "claimed " .. tostring(id))
            end
            task.wait(0.3)
        end
    end
end)

local function claimOffline()
    local ok, res = invoke("OfflineRewardsService", "Claim", false)
    note("Offline", (ok and res ~= false) and "claimed offline earnings" or "nothing to claim")
end
spawnWorker("offline", function()
    task.wait(3)
    if on("ClaimOffline") then claimOffline() end
end)

-- Anti-AFK: Roblox kicks after 20 idle minutes; a virtual click resets the timer.
connect(player.Idled, function()
    if on("AntiAfk") then
        pcall(function()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

-- Read-only list of the game's remote services, to re-check names after a game update.
local function listRemotes()
    local services = RS:FindFirstChild("RemoteServices")
    if not services then
        log("ReplicatedStorage.RemoteServices not found")
        return
    end
    local lines = {}
    for _, svc in ipairs(services:GetChildren()) do
        for _, kind in ipairs({ "RE", "RF" }) do
            local folder = svc:FindFirstChild(kind)
            if folder then
                local names = {}
                for _, r in ipairs(folder:GetChildren()) do names[#names + 1] = r.Name end
                table.sort(names)
                lines[#lines + 1] = string.format("%s.%s: %s", svc.Name, kind, table.concat(names, ", "))
            end
        end
    end
    table.sort(lines)
    for _, l in ipairs(lines) do log(l) end
    if type(writefile) == "function" then pcall(writefile, "TapSimReborn_remotes.txt", table.concat(lines, "\n")) end
    log(#lines, "remote groups listed (also saved to TapSimReborn_remotes.txt)")
end

-- Window ----------------------------------------------------------------------------------

local COLORS = {
    bg = Color3.fromRGB(24, 26, 32), bar = Color3.fromRGB(36, 40, 50), text = Color3.fromRGB(235, 238, 245),
    dim = Color3.fromRGB(150, 156, 170), on = Color3.fromRGB(46, 160, 90), off = Color3.fromRGB(70, 74, 86),
    stop = Color3.fromRGB(190, 60, 60),
}

local guiParent
do
    local ok, hui = pcall(function() return gethui and gethui() end)
    guiParent = (ok and hui) or game:GetService("CoreGui")
end
local gui = Instance.new("ScreenGui")
gui.Name = "TapSimRebornGui"
gui.ResetOnSpawn = false
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(270, 470)
frame.Position = UDim2.fromOffset(24, 120)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Parent = gui

local bar = Instance.new("TextLabel")
bar.Name = "Title"
bar.Size = UDim2.new(1, 0, 0, 28)
bar.BackgroundColor3 = COLORS.bar
bar.BorderSizePixel = 0
bar.TextColor3 = COLORS.text
bar.Font = Enum.Font.GothamBold
bar.TextSize = 14
bar.Text = "  Tap Sim REBORN v" .. VERSION
bar.TextXAlignment = Enum.TextXAlignment.Left
bar.Parent = frame

local function barButton(name, text, x, color)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.fromOffset(26, 22)
    b.Position = UDim2.new(1, x, 0, 3)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.TextColor3 = COLORS.text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.Text = text
    b.Parent = frame
    return b
end
local closeButton = barButton("Close", "X", -30, COLORS.stop)
local minButton = barButton("Minimize", "-", -60, COLORS.off)

local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.Size = UDim2.new(1, -12, 1, -36)
body.Position = UDim2.fromOffset(6, 32)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.CanvasSize = UDim2.fromOffset(0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = frame
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local rowOrder = 0
local function row(class, name, height)
    rowOrder += 1
    local r = Instance.new(class)
    r.Name = name
    r.Size = UDim2.new(1, -6, 0, height or 26)
    r.LayoutOrder = rowOrder
    r.BorderSizePixel = 0
    r.TextColor3 = COLORS.text
    r.Font = Enum.Font.Gotham
    r.TextSize = 13
    r.Parent = body
    return r
end

local toggleButtons = {}
local function paintToggle(key, label)
    local b = toggleButtons[key]
    b.Text = (Settings[key] and "[ON]  " or "[off]  ") .. label
    b.BackgroundColor3 = Settings[key] and COLORS.on or COLORS.off
end
local function toggle(key, label, onChange)
    local b = row("TextButton", "Toggle_" .. key)
    b.TextXAlignment = Enum.TextXAlignment.Left
    toggleButtons[key] = b
    paintToggle(key, label)
    connect(b.MouseButton1Click, function()
        Settings[key] = not Settings[key]
        paintToggle(key, label)
        saveSettings()
        if onChange then onChange(Settings[key]) end
    end)
end
local function button(name, text, fn)
    local b = row("TextButton", name)
    b.BackgroundColor3 = COLORS.bar
    b.Text = text
    connect(b.MouseButton1Click, function() task.spawn(fn, b) end)
    return b
end

toggle("AutoTap", "Auto tap (" .. maxRate() .. "/s max)")
toggle("GameAutoClicker", "Game auto clicker", function(enabled)
    task.spawn(pcall, fire, "AutoClickService", "AutoClickRequested", { Enabled = enabled == true })
end)
toggle("AutoRebirth", "Auto rebirth (spends coins)")
toggle("AutoHatch", "Auto hatch")
toggle("HatchTeleport", "  Teleport to the egg")
local function eggLabel()
    return "  Egg: " .. (Settings.HatchEgg == "" and "best I can afford" or Settings.HatchEgg) .. "  (click to change)"
end
button("EggPick", eggLabel(), function(b)
    local options = { "" }
    for _, egg in ipairs(eggList(data())) do options[#options + 1] = egg end
    local at = table.find(options, Settings.HatchEgg) or 1
    Settings.HatchEgg = options[at % #options + 1]
    saveSettings()
    b.Text = eggLabel()
end).TextXAlignment = Enum.TextXAlignment.Left
toggle("AutoEquip", "Auto equip best pets")
toggle("AutoUpgrades", "Auto buy upgrades")
toggle("AutoSkillTree", "Auto unlock skill tree (gems)")
toggle("AutoQuests", "Auto claim quests")
toggle("AutoChests", "Auto claim tap chests")
toggle("ClaimOffline", "Claim offline earnings", function(enabled)
    if enabled then spawnWorker("offline", claimOffline) end
end)
toggle("AntiAfk", "Anti-AFK")
button("ListRemotes", "Print remote list (read-only)", listRemotes)

local statusLabel = row("TextLabel", "Status", 150)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = COLORS.dim
statusLabel.TextSize = 12
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top

-- Drag by the title bar; RightControl hides or shows the window.
do
    local dragging, startInput, startPos
    connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, startInput, startPos = true, input.Position, frame.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - startInput
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    connect(UserInputService.InputBegan, function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightControl then frame.Visible = not frame.Visible end
    end)
end

local minimized = false
connect(minButton.MouseButton1Click, function()
    minimized = not minimized
    body.Visible = not minimized
    frame.Size = minimized and UDim2.fromOffset(270, 28) or UDim2.fromOffset(270, 470)
end)

loop("status", 0.5, function()
    local d = data()
    local lines = {}
    if d then
        lines[#lines + 1] = string.format("Coins %s | Gems %s | Rebirths %s", short(coins(d)),
            short(field(d, "Currencies", "Gems")), short(field(d, "Statistics", "Rebirths")))
    else
        lines[#lines + 1] = "Waiting for your save data..."
    end
    if on("AutoTap") then
        lines[#lines + 1] = string.format("Tap: %d sent, %d answered%s", tapStats.sent, tapStats.answered,
            tapStats.resyncs > 0 and string.format(", %d re-syncs", tapStats.resyncs) or "")
    end
    for _, feature in ipairs({ "Rebirth", "Hatch", "Equip", "Upgrades", "Skills", "Quests", "Chests", "Offline" }) do
        if State.notes[feature] then lines[#lines + 1] = feature .. ": " .. State.notes[feature] end
    end
    statusLabel.Text = table.concat(lines, "\n")
end)

-- Stop ------------------------------------------------------------------------------------

local Handle = { Version = VERSION, State = State }
function Handle.Stop()
    if not State.alive then return end
    -- Turn the game's own auto clicker back off while requests are still allowed.
    -- Spawned, so Stop never waits on a remote that has not loaded.
    if Settings.GameAutoClicker then task.spawn(pcall, fire, "AutoClickService", "AutoClickRequested", { Enabled = false }) end
    State.alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    if genv[GLOBAL_KEY] == Handle then genv[GLOBAL_KEY] = nil end
    log("stopped")
end
connect(closeButton.MouseButton1Click, Handle.Stop)
genv[GLOBAL_KEY] = Handle

if Settings.GameAutoClicker then
    task.spawn(pcall, fire, "AutoClickService", "AutoClickRequested", { Enabled = true })
end
log("v" .. VERSION .. " loaded. RightControl hides the window; X stops everything.")
