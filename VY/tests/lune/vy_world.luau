--!nocheck
-- Fake PS99 client + server for running the WHOLE VY AutoRank file in Lune.
-- Every value here is an invented test fixture shaped after what VY reads
-- (it is not game data). Remote calls are recorded and answered by small
-- server-side simulations with a replication delay, so the script's own
-- confirmation logic (Save deltas, UIDs, key counts) is exercised.
-- Passing these tests proves the script runs and keeps its own invariants
-- against these fakes; it does NOT prove live PS99/Potassium compatibility.
local R = require("./roblox_mock")
local luneTask = require("@lune/task")
local node = R.node
local Vector3, CFrame = R.Vector3, R.CFrame

local W = {calls = {}, files = {}, events = {}, handlers = {}}

local function vwait(seconds) luneTask.wait((seconds or 0) / R.SPEED) end
local function vdelay(seconds, fn) luneTask.delay((seconds or 0) / R.SPEED, fn) end
W.vwait = vwait

local function moduleScript(name, parent, value)
    local m = node("ModuleScript", name, parent)
    rawset(m, "__module", value)
    return m
end

function W.event(kind, detail)
    table.insert(W.events, {t = R.vclock(), kind = kind, detail = detail})
end

-- Options (all optional):
--   rank, rankStars, goals (slot -> goal), keys, world, bestZone = {id, number, world}
--   crystalReplicationDelay, crystalDrops (sequence), crystalRetainEvery
function W.build(opts)
    opts = opts or {}
    W.opts = opts
    local game = R.Instance.new("DataModel")
    game.Name = "Game"
    rawget(game, "__props").PlaceId = 8737899170
    rawget(game, "__props").JobId = "test-job"
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
    for _, n in ipairs({"RunService", "HttpService", "UserInputService", "Lighting", "TeleportService",
        "VirtualUser", "Stats", "TweenService", "StarterGui", "GuiService", "CoreGui"}) do service(n) end
    R.errors = {}

    W.world = opts.world or 1

    -- Player, character, hidden UI container (gethui).
    local player = node("Player", "Tester", players, {UserId = 4242, DisplayName = "Tester"})
    player:SetAttribute("__LOADED", true)
    rawget(players, "__props").LocalPlayer = player
    local playerGui = node("PlayerGui", "PlayerGui", player)
    local ps = node("Folder", "PlayerScripts", player)
    local scripts = node("Folder", "Scripts", ps)
    local gameScripts = node("Folder", "Game", scripts)
    node("LocalScript", "Egg Opening Frontend", gameScripts)
    local character = node("Model", "Tester", ws)
    local hrp = node("Part", "HumanoidRootPart", character)
    hrp.CFrame = CFrame.new(0, 5, 0)
    node("Humanoid", "Humanoid", character, {WalkSpeed = 16, Health = 100})
    rawget(player, "__props").Character = character
    character.PrimaryPart = hrp
    W.hui = node("Folder", "HiddenUI", game)
    W.player, W.root, W.playerGui = player, hrp, playerGui

    -- Zones: Castle (World 1, zone 3) holds the Crystal Chest; the best zone farms.
    local best = opts.bestZone or {id = "Best Zone", number = 25, world = 1}
    W.best = best
    local zones = {
        ["Castle"] = {_id = "Castle", ZoneName = "Castle", ZoneNumber = 3, WorldNumber = 1, Currency = "Coins"},
        [best.id] = {_id = best.id, ZoneName = best.id, ZoneNumber = best.number, WorldNumber = best.world, Currency = "Coins"},
    }
    W.zones = zones
    local zoneCenter = {["Castle"] = Vector3.new(500, 0, 0), [best.id] = Vector3.new(0, 0, 0)}
    W.zoneCenter = zoneCenter

    local things = node("Folder", "__THINGS", ws)
    local breakables = node("Folder", "Breakables", things)
    local map = node("Folder", "Map", ws)
    local interactByZone = {}
    local function zoneFolder(id, number)
        local folder = node("Folder", tostring(number) .. " | " .. id, map)
        local interact = node("Folder", "INTERACT", folder)
        local bz = node("Folder", "BREAK_ZONES", interact)
        local part = node("Part", "BREAK_ZONE", bz, {Size = Vector3.new(80, 2, 80)})
        part.CFrame = CFrame.new(zoneCenter[id])
        interactByZone[id] = interact
        return interact
    end
    local castle = zoneFolder("Castle", 3)
    zoneFolder(best.id, best.number)
    local chest = node("Model", "CrystalChest", castle)
    local pad = node("Part", "Pad", chest, {Size = Vector3.new(8, 1, 8)})
    pad.CFrame = CFrame.new(520, 0, 0)
    W.pad = pad
    for i = 1, 8 do
        local model = node("Model", tostring(2000 + i), breakables)
        model:SetAttribute("BreakableUID", tostring(2000 + i))
        model:SetAttribute("ParentID", best.id)
        model:SetAttribute("BreakableID", i <= 2 and "Diamond Pile" or "Coins Pile")
        model:SetAttribute("BreakableClass", "Normal")
        local part = node("Part", "Part", model)
        part.CFrame = CFrame.new(i * 3, 1, 0)
        model.PrimaryPart = part
    end

    -- Save (one shared table, mutated by the fake server after a delay).
    local save = {
        Rank = opts.rank or 12, RankStars = opts.rankStars or 3, Rebirths = opts.rebirths or 2,
        RedeemedRankRewards = {}, Goals = opts.goals,
        Inventory = {
            Misc = {ck = {id = "Crystal Key", _am = opts.keys or 150}, half = {id = "Crystal Key Upper Half", _am = 9}},
            Pet = {p1 = {id = "Cat", _am = 40, pt = 0}}, Potion = {}, Enchant = {}, Fruit = {},
        },
    }
    W.save = save
    W.equipped = 5
    W.uidCounter = 0

    -- Directory: rank pools copied from the official Ranks data shape (rank 12 slot pools).
    local pool1 = {{Type = 21, Amount = 1700, Weight = 1}, {Type = 14, Amount = 32, Weight = 1},
        {Type = 15, Amount = 32, Weight = 1}, {Type = 9, Amount = 450, Weight = 1}}
    local rankId = tostring(save.Rank) .. " | Test Rank"
    local ranks = {[rankId] = {Title = "Test Rank", _id = rankId,
        Rewards = {{StarsRequired = 2}, {StarsRequired = 400}, {StarsRequired = 400}},
        Goals = {pool1, {{Type = 21, Amount = 2200}, {Type = 14, Amount = 40}, {Type = 15, Amount = 40}, {Type = 20, Amount = 60}},
            {{Type = 9, Amount = 900}, {Type = 21, Amount = 3000}, {Type = 34, Amount = 10}},
            {{Type = 9, Amount = 1500}, {Type = 21, Amount = 4000}, {Type = 42, Amount = 3}}}}}
    W.rankId = rankId
    local eggs = {["Egg One"] = {name = "Egg One", pets = {{"Cat"}}}}

    -- Network: record, then dispatch to fake server handlers.
    local function record(kind, name, ...)
        local args = table.pack(...)
        table.insert(W.calls, {kind = kind, name = name, args = args, n = args.n, t = R.vclock()})
        local h = W.handlers[name]
        if h then return h(...) end
        return true
    end
    W.record = record
    R.invokeRemote = function(name, ...) return record("Invoke", name, ...) end
    R.fireRemote = function(name, ...) record("Fire", name, ...) end

    local library = node("Folder", "Library", rs)
    local clientScript = moduleScript("Client", library, {})
    local function client(name, value) moduleScript(name, clientScript, value) return value end
    client("Save", {Get = function() return save end})
    client("Network", {
        Fire = function(name, ...) record("Fire", name, ...) end,
        Invoke = function(name, ...) return record("Invoke", name, ...) end,
        UnreliableFire = function(name, ...) record("UnreliableFire", name, ...) end,
    })
    client("QuestCmds", {MakeTitle = function(goal) return "Goal type " .. tostring(goal.Type) end})
    client("RankCmds", {IsMaxRank = function() return false end, IsRankBlockedByZone = function() return false, false end})
    client("ZoneCmds", {
        GetMaxOwnedZone = function() return best.id, zones[best.id] end,
        GetNextZone = function() return nil end,
    })
    local function zoneAt(pos)
        for id, c in pairs(zoneCenter) do
            if (pos - c).Magnitude <= 60 then return id end
        end
        return nil
    end
    W.zoneAt = zoneAt
    client("MapCmds", {
        GetCurrentZone = function() return zoneAt(hrp.Position) end,
        IsInDottedBox = function() return zoneAt(hrp.Position) ~= nil end,
    })
    client("EggCmds", {GetMaxHatch = function() return 3 end, GetHighestEggNumberAvailable = function() return 1 end})
    client("PetCmds", {
        GetEquipped = function()
            local t = {}
            for i = 1, W.equipped do t["pet" .. i] = true end
            return t
        end,
        Restore = function() W.event("pets-restore") W.equipped = 5 return true end,
        EquipBest = function() W.event("pets-equipbest") W.equipped = 5 end,
    })
    client("PlayerPet", {
        CalculateSpeedMultiplier = function() return 1 end,
        BelongsToLocalPlayer = function() return true end,
        GetAll = function()
            local t = {}
            for i = 1, W.equipped do t[i] = {euid = "pet" .. i} end
            return t
        end,
    })
    client("CurrencyCmds", {Get = function() return 1e9 end})
    client("PotionCmds", {})
    client("FruitCmds", {})
    client("FlexibleFlagCmds", {Consume = function() return false, "no flag" end})
    client("RandomEventCmds", {GetActive = function() return {} end})
    client("InstancingCmds", {IsInInstance = function() return false end, GetInstanceID = function() return nil end,
        Get = function() return nil end})
    client("RebirthCmds", {GetNextRebirth = function() return nil end})
    client("EnchantCmds", {GetPower = function() return 1 end})
    client("UpgradeCmds", {GetPower = function() return 1 end})
    local placeFile = {}
    for n = 1, 4 do placeFile["IsWorld" .. n] = function() return W.world == n end end
    local modules = node("Folder", "Modules", library)
    moduleScript("PlaceFile", modules, placeFile)

    local directory = moduleScript("Directory", library, {Ranks = ranks, Zones = zones, Eggs = eggs,
        Potions = {}, Enchants = {}, RandomEvents = {}})
    local _ = directory
    local balancing = node("Folder", "Balancing", library)
    moduleScript("CalcPotionsPerTierRequired", balancing, function() return 3 end)
    moduleScript("CalcEnchantsPerTierRequired", balancing, function() return 3 end)
    moduleScript("CalcGatePrice", balancing, function() return 100 end)
    local util = node("Folder", "Util", library)
    moduleScript("RanksUtil", util, {
        RankIDFromNumber = function(n) return n == save.Rank and rankId or nil end,
        GetTotalStarsRequired = function() return 802 end,
    })
    moduleScript("ZonesUtil", util, {
        GetInteractFolder = function(id) return interactByZone[id] end,
        GetTeleportPartLocation = function(id) return zoneCenter[id] and CFrame.new(zoneCenter[id] + Vector3.new(0, 5, 0)) end,
    })
    local eggPart = node("Part", "EggOne", ws)
    eggPart.CFrame = CFrame.new(10, 3, 10)
    moduleScript("EggsUtil", util, {
        GetIdByNumber = function() return "Egg One" end,
        GetEggPart = function() return eggPart end,
    })
    moduleScript("WorldsUtil", util, {GetWorldNumber = function() return W.world end})

    local remotes = node("Folder", "Network", rs)
    for _, n in ipairs({"Pets_UnequipAll", "Instancing_FireCustomFromClient"}) do node("RemoteEvent", n, remotes) end
    for _, n in ipairs({"CrystalKey_Unlock", "Instancing_InvokeCustomFromClient"}) do node("RemoteFunction", n, remotes) end

    W.installServer(opts)
    W.game = game
    return game
end

-- ----------------------------------------------------------------- fake server
local function goalsBySlot()
    local out = {}
    for _, g in pairs(W.save.Goals) do
        if type(g) == "table" then out[g.Stars] = g end
    end
    return out
end
W.goalsBySlot = goalsBySlot

local function newUid()
    W.uidCounter += 1
    return "uid-" .. W.uidCounter
end

local function keyStack()
    for _, row in pairs(W.save.Inventory.Misc) do
        if row.id == "Crystal Key" then return row end
    end
    return nil
end
W.keyStack = keyStack

-- Completes a goal: pays its slot's stars and rolls a replacement of a type
-- that no other active goal holds (the player-reported no-duplicate rule).
local function complete(slot)
    local goals = W.save.Goals
    local key, g
    for k, v in pairs(goals) do if v.Stars == slot then key, g = k, v end end
    if not g then return end
    W.save.RankStars += slot
    local held = {}
    for _, v in pairs(goals) do if v ~= g then held[v.Type] = true end end
    local pool = W.opts.rollPools and W.opts.rollPools[slot] or {14, 15}
    local nextType = nil
    for _, t in ipairs(pool) do
        if not held[t] and t ~= g.Type then nextType = t break end
    end
    W.event("goal-complete", {slot = slot, type = g.Type, next = nextType})
    if nextType then
        goals[key] = {UID = newUid(), Type = nextType, Amount = g.Amount, Progress = 0, Stars = slot}
    else
        goals[key] = nil
    end
end
W.complete = complete

local function credit(predicate, amount)
    for slot = 1, 4 do
        local g = goalsBySlot()[slot]
        if g and predicate(g) then
            g.Progress = math.min(g.Amount, g.Progress + amount)
            if g.Progress >= g.Amount then complete(slot) end
        end
    end
end
W.credit = credit

function W.installServer(opts)
    local h = W.handlers
    local delay = opts.crystalReplicationDelay or 0.6
    local drops = opts.crystalDrops or {1, 2, 3, 2, 1, 3}
    local retainEvery = opts.crystalRetainEvery or 20
    W.crystalOpens = 0
    h["CrystalKey_Unlock"] = function(...)
        vwait(0.1) -- round trip
        if select("#", ...) ~= 0 then W.event("crystal-bad-args") return false, "bad args" end
        local stack = keyStack()
        if not stack or stack._am < 1 then return false, "You need a Crystal Key" end
        if (W.zoneAt(W.root.Position) ~= "Castle") or (W.root.Position - W.pad.Position).Magnitude > 20 then
            W.event("crystal-too-far")
            return false, "Too far from the chest"
        end
        W.crystalOpens += 1
        local n = W.crystalOpens
        local keep = n % retainEvery == 0
        local items = drops[(n - 1) % #drops + 1]
        vdelay(delay, function()
            if not keep then stack._am -= 1 end
            -- Chest drops count toward every active collect goal (both potions and enchants assumed).
            credit(function(g) return g.Type == 14 or g.Type == 15 end, items)
            W.event("crystal-replicated", {open = n, items = items, keep = keep})
        end)
        return true
    end
    h["Pets_UnequipAll"] = function() vdelay(0.3, function() W.equipped = 0 end) end
    h["Breakables_JoinPetBulk"] = function(map)
        if next(map) == nil then return end
        -- Farming the best area advances breakable quests (incl. the held ones).
        if W.zoneAt(W.root.Position) == W.best.id then
            credit(function(g) return g.Type == 21 or g.Type == 1 end, 5)
            credit(function(g) return g.Type == 9 end, 1)
        end
    end
    h["Eggs_RequestPurchase"] = function(_, amount)
        vwait(0.05)
        credit(function(g) return g.Type == 20 end, amount or 1)
        return true
    end
    h["Ranks_ClaimReward"] = function(i) vdelay(0.3, function() W.save.RedeemedRankRewards[tostring(i)] = true end) end
    for n = 1, 4 do
        h["World" .. n .. "Teleport"] = function()
            W.event("world-teleport", n)
            vwait(0.2)
            return true
        end
    end
end

function W.count(name, sinceIndex)
    local n = 0
    for i = sinceIndex or 1, #W.calls do if W.calls[i].name == name then n += 1 end end
    return n
end

return W
