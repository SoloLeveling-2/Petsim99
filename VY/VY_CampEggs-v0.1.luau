-- =====================================================================================
--  VY Camp Eggs v0.1 - Pet Simulator 99, Diamond Mountain (update 98)       2026-10-18
--  Status: tested offline (mocked Lune runtime). Its request was seen working live
--  (probe run 3, sent by ZapHub); v0.1 itself has not run live yet.
--
--  Hatches the Diamond Mountain camp egg you stand next to, again and again, as many
--  eggs at a time as the game lets you (your max hatch). It pays in TrailCoins, as the
--  game does. Walk to another camp's egg and it hatches that one instead.
--    * Only camp eggs: Workspace.__THINGS.CustomEggs.<uid> models with a DM_EggId.
--      Trail eggs (they also have DM_TrailEgg) and other events' eggs are left alone.
--    * It learns the price from its own hatches and waits when you cannot pay, then
--      goes on once farming has earned enough.
--    * KEEP_COINS: it never spends below that many TrailCoins (the first hatch is then
--      1 egg, to learn the price).
--  Run VY Wall Crew next to it to put the new event pets on the wall.
--
--  DRY_RUN = true (the default) only prints what it WOULD hatch and sends nothing.
--  Check the console (F9), then set DRY_RUN = false below and run it again.
--  Run it while you are on Diamond Mountain, with VY AutoRank stopped (VY teleports away).
--  Stop: getgenv().VyCampEggs.Stop()   Running it again also replaces a running copy.
--
--  Built from probe run 3 (VY/docs/DIAMOND_MOUNTAIN_FINDINGS.md):
--    request  CustomEggs_Hatch("<egg model name>", <eggs>)  -> true, nil
--    effect   TrailCoins down (~29,813 per Boulder Ridge Egg),
--             Save.PurchasedEggs["<DM_EggId>"] up by <eggs>
-- =====================================================================================
local CONFIG = {
    DRY_RUN = true,           -- true: print the plan only; false: hatch
    HATCH_GAP = 2,            -- seconds between hatches (the game's own takes ~1.6 s)
    RANGE = 40,               -- studs: only an egg this close to you is hatched
    KEEP_COINS = 0,           -- never spend below this many TrailCoins
    AMOUNT = 0,               -- eggs per hatch; 0 = your max hatch
    CONFIRM_SECONDS = 6,      -- how long to wait for a hatch to show in your save
    RETRY_SECONDS = 10,       -- wait after a refused hatch
}
local VERSION = "0.1"
local INSTANCE = "DiamondMountain"
local CURRENCY = "TrailCoins" -- shown as "Acorns" in the game
local TAG = "[CampEggs] "

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local genv = (type(getgenv) == "function" and getgenv()) or _G

local function log(f, ...)
    local ok, s = pcall(string.format, f, ...)
    print(TAG .. (ok and s or tostring(f)))
end

-- A running copy stops first, so only one copy ever sends.
if type(genv.VyCampEggs) == "table" and type(genv.VyCampEggs.Stop) == "function" then
    pcall(genv.VyCampEggs.Stop)
end

local alive, handle = true, nil
local function Stop(reason)
    if not alive then return end
    alive = false
    if genv.VyCampEggs == handle then genv.VyCampEggs = nil end
    log("stopped%s", reason and (": " .. reason) or "")
end
handle = { Stop = function() Stop() end, Config = CONFIG, Version = VERSION }
genv.VyCampEggs = handle

-- Game modules run at identity 2; afterwards the thread gets back the identity it had.
local function gcall(fn, ...)
    if type(fn) ~= "function" then return false, "not a function" end
    local canSet = type(setthreadidentity) == "function"
    local prior = 8
    if canSet and type(getthreadidentity) == "function" then
        local ok, id = pcall(getthreadidentity)
        if ok and type(id) == "number" then prior = id end
    end
    if canSet then pcall(setthreadidentity, 2) end
    local r = table.pack(pcall(fn, ...))
    if canSet then pcall(setthreadidentity, prior) end
    return table.unpack(r, 1, r.n)
end

-- require(ReplicatedStorage.Library.<path>)
local function module(...)
    local node = ReplicatedStorage:WaitForChild("Library", 30)
    for _, name in ipairs({ ... }) do
        node = node and node:WaitForChild(name, 30)
    end
    if not node then return nil end
    local ok, mod = gcall(require, node)
    return ok and mod or nil
end

local Save = module("Client", "Save")
local Network = module("Client", "Network")
local Instancing = module("Client", "InstancingCmds")
local EggCmds = module("Client", "EggCmds")
if type(Save) ~= "table" or type(Network) ~= "table" or type(Instancing) ~= "table" then
    Stop("game modules not found (is the game fully loaded?)")
    return
end

local function getSave()
    local ok, s = gcall(Save.Get)
    if ok and type(s) == "table" then return s end
    return nil
end
local function coinsOf(save)
    local n = 0
    local currency = type(save) == "table" and type(save.Inventory) == "table" and save.Inventory.Currency or nil
    for _, item in pairs(type(currency) == "table" and currency or {}) do
        if type(item) == "table" and item.id == CURRENCY then n += tonumber(item._am) or 0 end
    end
    return n
end
local function boughtOf(save, eggId)
    local bought = type(save) == "table" and save.PurchasedEggs or nil
    return tonumber(type(bought) == "table" and bought[eggId]) or 0
end

-- On the mountain: the game says so, or the mountain is the active instance in the world.
local function onMountain()
    local okId, where = gcall(Instancing.GetInstanceID)
    if okId and where == INSTANCE then return true end
    local things = workspace:FindFirstChild("__THINGS")
    local container = things and things:FindFirstChild("__INSTANCE_CONTAINER")
    local active = container and container:FindFirstChild("Active")
    return active ~= nil and active:FindFirstChild(INSTANCE) ~= nil
end

local function myPosition()
    local player = Players.LocalPlayer
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root.Position or nil
end

-- The nearest camp egg within RANGE: a CustomEggs model with DM_EggId, not a trail egg.
local function nearestCampEgg()
    local here = myPosition()
    local things = workspace:FindFirstChild("__THINGS")
    local folder = things and things:FindFirstChild("CustomEggs")
    if not (here and folder) then return nil end
    local best, bestDistance = nil, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        local ok, eggId, trail, distance = pcall(function()
            return model:GetAttribute("DM_EggId"), model:GetAttribute("DM_TrailEgg"),
                (model:GetPivot().Position - here).Magnitude
        end)
        if ok and type(eggId) == "string" and trail == nil and distance <= CONFIG.RANGE and distance < bestDistance then
            best, bestDistance = { uid = model.Name, eggId = eggId, distance = distance }, distance
        end
    end
    return best
end

local function maxHatch()
    if CONFIG.AMOUNT and CONFIG.AMOUNT > 0 then return math.floor(CONFIG.AMOUNT) end
    if type(EggCmds) == "table" then
        local ok, n = gcall(EggCmds.GetMaxHatch)
        if ok and tonumber(n) and tonumber(n) >= 1 then return math.floor(tonumber(n)) end
    end
    return 1
end

local lastStatus, lastPlan, misses = nil, nil, 0
local hatched, spent = 0, 0
-- Price per egg: the median of the last 5 hatches. Farming during a hatch makes one look
-- a little cheap; buying something else during one makes it look far too dear.
local seen = {}
local function price()
    if #seen == 0 then return nil end
    local sorted = table.clone(seen)
    table.sort(sorted)
    return sorted[math.ceil(#sorted / 2)]
end
local function status(f, ...)
    local ok, s = pcall(string.format, f, ...)
    s = ok and s or tostring(f)
    if s ~= lastStatus then
        lastStatus = s
        log("%s", s)
    end
end
local function replyText(ok, a, b)
    if not ok then return "error: " .. tostring(a) end
    return tostring(a) .. (b ~= nil and (", " .. tostring(b)) or "")
end

-- One step; returns how long to wait before the next.
local function step()
    if not onMountain() then
        status("waiting: you are not on Diamond Mountain")
        return 5
    end
    local egg = nearestCampEgg()
    if not egg then
        status("waiting: stand next to a Diamond Mountain camp egg (within %d studs)", CONFIG.RANGE)
        return 3
    end
    local save = getSave()
    if not save then
        status("waiting: your save is not loaded")
        return 5
    end
    local coins = coinsOf(save)
    local amount, each = maxHatch(), price()
    if each then
        amount = math.min(amount, math.floor((coins - CONFIG.KEEP_COINS) / each))
    elseif CONFIG.KEEP_COINS > 0 then
        amount = 1 -- learn the price with one egg, so the reserve holds
    end
    if coins <= CONFIG.KEEP_COINS or amount < 1 then
        if CONFIG.KEEP_COINS > 0 then
            status("waiting: keeping %d TrailCoins (you have %d)", CONFIG.KEEP_COINS, coins)
        else
            status("waiting: not enough TrailCoins (you have %d; an egg costs about %d)", coins, math.floor((each or 0) + 0.5))
        end
        return 5
    end
    if CONFIG.DRY_RUN then
        local text = string.format("would hatch %d x %s (egg %s, %d studs away); you have %d TrailCoins",
            amount, egg.eggId, egg.uid, math.floor(egg.distance + 0.5), coins)
        if text ~= lastPlan then
            lastPlan = text
            log("DRY RUN: %s", text)
            log("DRY RUN: nothing was sent. Set DRY_RUN = false at the top and run the script again.")
        end
        return 3
    end
    local before = boughtOf(save, egg.eggId)
    local ok, a, b = gcall(Network.Invoke, "CustomEggs_Hatch", egg.uid, amount)
    local reply = replyText(ok, a, b)
    -- Confirmed by the save, not the reply: the egg's purchase count must grow.
    local deadline, now, latest = os.clock() + CONFIG.CONFIRM_SECONDS, before, save
    while ok and a ~= false and alive and now <= before and os.clock() < deadline do
        task.wait(0.25)
        latest = getSave() or latest
        now = boughtOf(latest, egg.eggId)
    end
    if not alive then return 0 end
    if now > before then
        misses = 0
        lastStatus = nil
        local n, paid = now - before, coins - coinsOf(latest)
        hatched += n
        spent += math.max(0, paid)
        if paid > 0 then
            if #seen == 0 then log("%s: %d TrailCoins each", egg.eggId, math.floor(paid / n + 0.5)) end
            table.insert(seen, paid / n)
            if #seen > 5 then table.remove(seen, 1) end
        end
        if hatched == n or math.floor(hatched / 500) > math.floor((hatched - n) / 500) then
            log("eggs hatched so far: %d (%d TrailCoins); last: %d x %s", hatched, spent, n, egg.eggId)
        end
        return CONFIG.HATCH_GAP
    end
    misses += 1
    log("hatching %d x %s did not show in your save | reply: %s", amount, egg.eggId, reply)
    if misses >= 3 then
        Stop("three hatches in a row did not go through, so nothing more is sent. Copy the lines above for the next fix.")
        return 0
    end
    return CONFIG.RETRY_SECONDS
end

log("v%s started%s", VERSION, CONFIG.DRY_RUN and " in DRY RUN (nothing is sent)" or "")
task.spawn(function()
    while alive do
        local ok, wait = pcall(step)
        if not ok then
            log("step failed: %s", tostring(wait))
            wait = 5
        end
        local waited = 0
        while alive and waited < (tonumber(wait) or 5) do
            task.wait(0.5)
            waited += 0.5
        end
    end
end)
