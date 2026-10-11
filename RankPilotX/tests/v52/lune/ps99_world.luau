--!nocheck
-- Fake PS99 client world built on roblox_mock.luau. Values are invented test
-- fixtures, not game data; remote calls are recorded, never sent anywhere.
local R = require("./roblox_mock")
local luneTask = require("@lune/task")
local Instance, node = R.Instance, R.node
local Vector3, CFrame = nil, nil

local W = {calls = {}, responses = {}, files = {}}
R.services = {}

local function moduleScript(name, parent, value)
    local m = node("ModuleScript", name, parent)
    rawset(m, "__module", value)
    return m
end

function W.build(env)
    Vector3, CFrame = env.Vector3, env.CFrame
    local game = Instance.new("DataModel")
    game.Name = "Game"
    rawget(game, "__props").PlaceId = 8737899170
    rawget(game, "__props").JobId = "test-job"
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
    for _, n in ipairs({"RunService", "HttpService", "UserInputService", "Lighting", "TeleportService",
        "VirtualUser", "Stats", "TweenService", "StarterGui", "GuiService", "SoundService"}) do service(n) end
    local lighting = R.services.Lighting
    lighting.Brightness, lighting.ClockTime, lighting.FogEnd, lighting.GlobalShadows = 1, 14, 1000, true
    lighting.Ambient = env.Color3.fromRGB(0, 0, 0)
    lighting.OutdoorAmbient = env.Color3.fromRGB(0, 0, 0)

    -- Player + character
    local player = node("Player", "Tester", players, {UserId = 1, DisplayName = "Tester"})
    R.player = player
    rawget(players, "__props").LocalPlayer = player
    local playerGui = node("PlayerGui", "PlayerGui", player)
    local character = node("Model", "Tester", ws)
    local hrp = node("Part", "HumanoidRootPart", character)
    hrp.CFrame = CFrame.new(0, 5, 0)
    local humanoid = node("Humanoid", "Humanoid", character, {WalkSpeed = 16, Health = 100})
    node("Part", "Head", character)
    rawget(player, "__props").Character = character
    character.PrimaryPart = hrp
    W.player, W.humanoid, W.root, W.playerGui = player, humanoid, hrp, playerGui

    local camera = node("Camera", "Camera", ws, {ViewportSize = env.Vector2.new(1600, 900)})
    rawget(ws, "__props").CurrentCamera = camera
    function ws.GetServerTimeNow() return os.time() end

    -- Map with one owned zone and a breakable field.
    local things = node("Folder", "__THINGS", ws)
    local breakables = node("Folder", "Breakables", things)
    node("Folder", "Orbs", things)
    node("Folder", "Lootbags", things)
    node("Folder", "BalloonGifts", things)
    local map = node("Folder", "Map", ws)
    local zoneFolder = node("Folder", "1 | Spawn", map)
    local interact = node("Folder", "INTERACT", zoneFolder)
    local breakZones = node("Folder", "BREAK_ZONES", interact)
    local field = node("Part", "BREAK_ZONE", breakZones, {Size = Vector3.new(80, 2, 80)})
    field.CFrame = CFrame.new(0, 0, 0)
    for i = 1, 6 do
        local model = node("Model", tostring(1000 + i), breakables)
        model:SetAttribute("BreakableUID", tostring(1000 + i))
        model:SetAttribute("ParentID", "Spawn")
        model:SetAttribute("BreakableID", i == 6 and "Basic Coin Jar" or "Coins Pile")
        model:SetAttribute("BreakableClass", i == 6 and "Chest" or "Normal")
        local part = node("Part", "Part", model)
        part.CFrame = CFrame.new(i * 3, 1, 0)
        model.PrimaryPart = part
    end

    -- Save data (mutable fixture).
    local save = {
        Rank = 5, RankStars = 2, RedeemedRankRewards = {}, GoalsCompleted = 10, Rebirths = 0,
        Goals = {
            {UID = "goal-farm", Type = 1, Amount = 500, Progress = 20, Stars = 2, Title = "Break 500 breakables in Best Area"},
            {UID = "goal-hatch", Type = 2, Amount = 50, Progress = 0, Stars = 1, Title = "Hatch 50 Best Eggs"},
            {UID = "goal-potion", Type = 3, Amount = 3, Progress = 0, Stars = 1, Title = "Use 3 Tier II Potions", PotionTier = 2},
        },
        Inventory = {Pet = {p1 = {id = "Cat", _am = 30}}, Potion = {po1 = {id = "Coins", tn = 2, _am = 8}},
            Enchant = {}, Fruit = {f1 = {id = "Apple", _am = 20}}, Misc = {m1 = {id = "Basic Coin Jar", _am = 3}},
            Lootbox = {}, Gift = {}},
        MaximumAvailableEgg = 3, UnlockedEggs = {}, EggHatchCount = 1, RecentWorld = 1,
        FreeGiftsTime = 0, FreeGiftsRedeemed = {}, TimedRewardTimestamps = {}, VendingStocks = {},
        EggSlotsPurchased = 0, PetSlotsPurchased = 0, UnlockedZones = {Spawn = true},
    }
    W.save = save

    local function record(kind, name, ...)
        table.insert(W.calls, {kind = kind, name = name, args = {...}})
        local response = W.responses[name]
        if type(response) == "function" then return response(...) end
        if response == nil then return true end
        return response
    end
    W.record = record
    R.invokeRemote = function(name, ...) return record("Invoke", name, ...) end
    R.fireRemote = function(name, ...) record("Fire", name, ...) end

    local library = node("Folder", "Library", rs)
    local clients = {}
    local clientScript = moduleScript("Client", library, clients)
    local function client(name, value)
        clients[name] = value
        moduleScript(name, clientScript, value)
        return value
    end
    client("Save", {Get = function() return save end, GetStatChangedSignal = function() return R.Signal.new() end})
    client("Network", {
        Fire = function(name, ...) record("Fire", name, ...) end,
        Invoke = function(name, ...) return record("Invoke", name, ...) end,
        UnreliableFire = function(name, ...) record("UnreliableFire", name, ...) end,
        Fired = function() return R.Signal.new() end,
    })
    client("QuestCmds", {MakeTitle = function(goal) return goal.Title end})
    client("RankCmds", {GetMaxRank = function() return save.Rank end, AllRewardsReady = function() return false end,
        AllRewardsRedeemed = function() return true end, IsRankBlockedByZone = function() return false, false end,
        GetMaxPurchasableEggSlots = function() return 0 end, GetMaxPurchasableEquipSlots = function() return 0 end,
        IsMaxRank = function() return false end})
    client("ZoneCmds", {GetMaxOwnedZone = function() return "Spawn" end, GetNextZone = function() return nil end,
        Owns = function() return true end})
    client("MapCmds", {GetCurrentZone = function() return "Spawn" end, IsInDottedBox = function() return true end})
    client("EggCmds", {GetMaxHatch = function() return 3 end, IsUnlocked = function() return true end,
        RequestPurchase = function(id, n) return record("Invoke", "EggCmds.RequestPurchase", id, n) end})
    client("PetCmds", {EquipBest = function() end, GetEquipped = function() return {} end})
    client("PlayerPet", {CalculateSpeedMultiplier = function() return 1 end, GetByPlayer = function() return {} end,
        GetAll = function() return {} end})
    local orbCmds = client("OrbCmds", {})
    moduleScript("Orb", clientScript:FindFirstChild("OrbCmds"), {DefaultPickupDistance = 10, CollectDistance = 10})
    client("BreakableFrontend", {AllByZoneAndClass = function() return {} end})
    client("BreakableCmds", {Get = function() return nil end})
    client("CurrencyCmds", {Get = function() return 100000 end, CanAfford = function() return true end})
    client("RebirthCmds", {Get = function() return save.Rebirths end, GetNextRebirth = function() return nil end})
    client("LoginStreakCmds", {CanClaim = function() return false end})
    client("MachineCmds", {GetModels = function() return {} end, Owns = function() return false end})
    client("UpgradeCmds", {All = function() return {} end})
    client("InventoryCmds", {State = function() return nil end})
    client("FruitCmds", {Consume = function(uid) return record("Invoke", "FruitCmds.Consume", uid) end})
    client("PotionCmds", {})
    client("MasteryCmds", {GetPerkPower = function() return 0 end})
    client("SettingsCmds", {Get = function() return "Off" end})
    client("ZoneFlagCmds", {})
    client("RandomEventCmds", {GetActive = function() return {} end})
    client("InstancingCmds", {IsInInstance = function() return false end})
    client("HatchingCmds", {IsEnabled = function() return false end})
    client("Gamepasses", {Owns = function() return false end})
    local _ = orbCmds

    -- The live game freezes Directory tables; indexing an unknown key throws.
    local function frozen(t, label)
        return setmetatable(t, {__index = function(_, key)
            error("Directory." .. label .. " has no key " .. tostring(key), 2)
        end})
    end
    moduleScript("Directory", library, frozen({
        Ranks = frozen({Rank5 = {RankNumber = 5, Title = "Rank 5", Rewards = {{StarsRequired = 2}, {StarsRequired = 3}}, Goals = {}}}, "Ranks"),
        Zones = frozen({Spawn = {ZoneNumber = 1, WorldNumber = 1, _id = "Spawn", ZoneName = "Spawn"}}, "Zones"),
        Eggs = frozen({}, "Eggs"), Pets = frozen({Cat = {}}, "Pets"), FreeGifts = frozen({}, "FreeGifts"),
        TimedRewards = frozen({}, "TimedRewards"), Gamepasses = frozen({VIP = {ProductId = 1}}, "Gamepasses"),
        RandomEvents = frozen({}, "RandomEvents"),
    }, "root"))
    moduleScript("Balancing", library, {CalcGatePrice = function() return 100 end})
    local util = node("Folder", "Util", library)
    moduleScript("ZonesUtil", util, {
        GetBreakableZones = function() return breakZones end,
        GetTeleportPartLocation = function() return CFrame.new(0, 5, 0) end,
        GetArray = function() return {{_id = "Spawn", ZoneNumber = 1}} end,
        GetInteractFolder = function() return interact end,
    })
    moduleScript("RanksUtil", util, {
        GetMaximumRank = function() return {RankNumber = 40} end,
        RankIDFromNumber = function(n) return "Rank" .. tostring(n) end,
        GetArray = function() return {} end,
    })
    node("Folder", "Network", rs)
    W.game = game
    return game
end

return W
