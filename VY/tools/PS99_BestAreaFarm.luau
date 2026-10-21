--!nocheck
-- PS99 Best Area Auto Farm (standalone)
-- Teleports you into your highest unlocked zone and sends every equipped pet at its
-- breakables (event/chest piles first, then diamonds, then everything else).
-- Uses the same game calls as VY_AutoRank v1.1.8 (ZoneCmds.GetMaxOwnedZone,
-- Breakables_JoinPetBulk). Run it again, or call getgenv().PS99BestAreaFarm.Stop(), to stop.

local CONFIG = {
    TickSeconds = 0.5,        -- how often pets are re-targeted
    ZoneRecheckSeconds = 10,  -- how often the best zone is looked up again (picks up new unlocks)
    TeleportTolerance = 60,   -- studs away from the break zone before teleporting back
    TapBreakables = true,     -- also deal click damage yourself
}

local genv = getgenv and getgenv() or _G
if genv.PS99BestAreaFarm and genv.PS99BestAreaFarm.Stop then
    genv.PS99BestAreaFarm.Stop()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local alive = true

-- Game modules must be required at game identity (2); executor identity (8) is restored after.
local canSetIdentity = type(setthreadidentity) == "function"
local function gcall(fn, ...)
    if type(fn) ~= "function" then return false, "not a function" end
    if canSetIdentity then pcall(setthreadidentity, 2) end
    local r = table.pack(pcall(fn, ...))
    if canSetIdentity then pcall(setthreadidentity, 8) end
    return table.unpack(r, 1, r.n)
end

local function load(...)
    local inst = RS
    for _, name in ipairs({ ... }) do
        inst = inst and inst:WaitForChild(name, 10)
    end
    if not inst then return nil end
    local ok, mod = gcall(require, inst)
    return ok and mod or nil
end

local Network = load("Library", "Client", "Network")
local ZoneCmds = load("Library", "Client", "ZoneCmds")
local ZonesUtil = load("Library", "Util", "ZonesUtil")
local MapCmds = load("Library", "Client", "MapCmds")
local PlayerPet = load("Library", "Client", "PlayerPet")
local InstancingCmds = load("Library", "Client", "InstancingCmds")
if not (Network and ZoneCmds and PlayerPet) then
    warn("[BestAreaFarm] Required game modules not found - is this Pet Simulator 99?")
    return
end

local function log(fmt, ...) print("[BestAreaFarm] " .. string.format(fmt, ...)) end

-- ---- best zone ---------------------------------------------------------------------
local zoneId, zoneAt = nil, -math.huge
local function bestZoneId()
    if os.clock() - zoneAt < CONFIG.ZoneRecheckSeconds then return zoneId end
    zoneAt = os.clock()
    local ok, id = gcall(ZoneCmds.GetMaxOwnedZone)
    if ok and type(id) == "table" then id = id._id end
    if ok and type(id) == "string" then
        if id ~= zoneId then log("Best area: %s", id) end
        zoneId = id
    end
    return zoneId
end

local function standPosition(id)
    if ZonesUtil and ZonesUtil.GetInteractFolder then
        local ok, folder = gcall(ZonesUtil.GetInteractFolder, id)
        local bz = ok and typeof(folder) == "Instance" and folder:FindFirstChild("BREAK_ZONES")
        if bz then
            for _, d in ipairs(bz:GetDescendants()) do
                if d:IsA("BasePart") then return d.Position + Vector3.new(0, 4, 0) end
            end
        end
    end
    if ZonesUtil and ZonesUtil.GetTeleportPartLocation then
        local ok, cf = gcall(ZonesUtil.GetTeleportPartLocation, id)
        if ok and typeof(cf) == "CFrame" then return cf.Position + Vector3.new(0, 3, 0) end
        if ok and typeof(cf) == "Vector3" then return cf + Vector3.new(0, 3, 0) end
    end
    return nil
end

local function inInstance()
    if not (InstancingCmds and InstancingCmds.IsInInstance) then return false end
    local ok, v = gcall(InstancingCmds.IsInInstance)
    return ok and v == true
end

local function ensureInZone(id)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local pos = standPosition(id)
    if not (hrp and pos) then return end
    local current = nil
    if MapCmds and MapCmds.GetCurrentZone then
        local ok, cz = gcall(MapCmds.GetCurrentZone)
        if ok then current = cz end
    end
    if (hrp.Position - pos).Magnitude > CONFIG.TeleportTolerance or (current ~= nil and current ~= id) then
        hrp.CFrame = CFrame.new(pos)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

-- ---- breakables and pets -----------------------------------------------------------
local EVENT_WORDS = { "comet", "pinata", "jar", "lucky", "chest" } -- same list as VY_AutoRank

local function breakables(id)
    local things = workspace:FindFirstChild("__THINGS")
    local folder = things and things:FindFirstChild("Breakables")
    local events, diamonds, normal = {}, {}, {}
    if not folder then return events, diamonds, normal end
    for _, m in ipairs(folder:GetChildren()) do
        local uid = m:IsA("Model") and m:GetAttribute("ParentID") == id and m:GetAttribute("BreakableUID")
        if uid ~= nil and uid ~= false then
            local bid = string.lower(tostring(m:GetAttribute("BreakableID") or ""))
            local class = m:GetAttribute("BreakableClass")
            local bucket = normal
            if string.find(bid, "diamond", 1, true) then
                bucket = diamonds
            elseif class ~= nil and class ~= "Normal" then
                bucket = events
            else
                for _, w in ipairs(EVENT_WORDS) do
                    if string.find(bid, w, 1, true) then bucket = events; break end
                end
            end
            bucket[#bucket + 1] = uid
        end
    end
    return events, diamonds, normal
end

local function myPets()
    local ok, all = gcall(PlayerPet.GetAll)
    local out = {}
    if not ok or type(all) ~= "table" then return out end
    for _, p in pairs(all) do
        if type(p) == "table" and p.euid ~= nil then
            local mine = true
            if PlayerPet.BelongsToLocalPlayer then
                local okB, r = gcall(PlayerPet.BelongsToLocalPlayer, p)
                mine = not (okB and r == false)
            end
            if mine then out[#out + 1] = p.euid end
        end
    end
    return out
end

-- ---- main loop ---------------------------------------------------------------------
local tap = 0
local function tick()
    if inInstance() then return end
    local id = bestZoneId()
    if not id then return end
    ensureInZone(id)
    local pets = myPets()
    if #pets == 0 then return end
    local events, diamonds, normal = breakables(id)
    local targets = {}
    for _, list in ipairs({ events, diamonds, normal }) do
        for _, uid in ipairs(list) do targets[#targets + 1] = uid end
    end
    if #targets == 0 then return end
    -- Spread pets over targets in priority order (one pet per target until pets run out).
    local map = {}
    for i, euid in ipairs(pets) do
        map[euid] = targets[((i - 1) % #targets) + 1]
    end
    gcall(Network.Fire, "Breakables_JoinPetBulk", map)
    if CONFIG.TapBreakables and Network.UnreliableFire then
        tap = (tap % #targets) + 1
        gcall(Network.UnreliableFire, "Breakables_PlayerDealDamage", targets[tap])
    end
end

genv.PS99BestAreaFarm = {
    Stop = function()
        alive = false
        log("Stopped")
    end,
}

task.spawn(function()
    log("Started - farming your best area")
    while alive do
        local ok, err = pcall(tick)
        if not ok then warn("[BestAreaFarm] " .. tostring(err)) end
        task.wait(CONFIG.TickSeconds)
    end
end)
