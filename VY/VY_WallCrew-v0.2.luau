-- =====================================================================================
--  VY Wall Crew v0.2 - Pet Simulator 99, Diamond Mountain (update 98)       2026-10-18
--  Status: tested offline (mocked Lune runtime); live: v0.1 dry run only.
--
--  Keeps every event pet you own on the Rubble Wall you are smashing:
--    * event pets you hatch are added to the wall's crew;
--    * when a wall breaks (its crew is released), they all go onto the next wall.
--  Pets stay in your inventory (the wall only counts them), so nothing is spent.
--  Event pets = the pets in Diamond Mountain's own eggs, plus kinds a wall already took.
--  Huge, Titanic and Gargantuan pets are never loaded.
--  v0.2: v0.1 took every pet from game zone 279 for an event pet; its first live dry run
--  showed other events' pets share that zone (it planned 13,343 Stitched Cats).
--
--  DRY_RUN = true (the default) only prints what it WOULD load and sends nothing.
--  Check the console (F9), then set DRY_RUN = false below and run it again.
--  Run it while you are on Diamond Mountain, with VY AutoRank stopped (VY teleports away).
--  Stop: getgenv().VyWallCrew.Stop()   Running it again also replaces a running copy.
--
--  Built from two live probe runs (VY/docs/DIAMOND_MOUNTAIN_FINDINGS.md):
--    request  Instancing_InvokeCustomFromClient("DiamondMountain", "DM_Walls_Load",
--             wall, { [pet stack uid] = count })   adds `count` pets of that stack
--    state    Save.InstanceVars.DiamondMountain: Walls.Broken[n], InstanceZones.__Zone_n,
--             WallCrew[n]["<id>|<pt>|<sh>"].count
-- =====================================================================================
local CONFIG = {
    DRY_RUN = true,           -- true: print the plan only; false: send the loads
    CHECK_EVERY = 15,         -- seconds between checks
    REQUEST_GAP = 1.5,        -- seconds between two load requests
    MAX_LOADS_PER_CHECK = 8,  -- load requests per check, at most
    CONFIRM_SECONDS = 6,      -- how long to wait for the wall's crew to show a load
}
local VERSION = "0.2"
local INSTANCE = "DiamondMountain"
local TAG = "[WallCrew] "

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local genv = (type(getgenv) == "function" and getgenv()) or _G

local function log(f, ...)
    local ok, s = pcall(string.format, f, ...)
    print(TAG .. (ok and s or tostring(f)))
end

-- A running copy stops first, so only one copy ever sends.
if type(genv.VyWallCrew) == "table" and type(genv.VyWallCrew.Stop) == "function" then
    pcall(genv.VyWallCrew.Stop)
end

local alive, handle = true, nil
local function Stop(reason)
    if not alive then return end
    alive = false
    if genv.VyWallCrew == handle then genv.VyWallCrew = nil end
    log("stopped%s", reason and (": " .. reason) or "")
end
handle = { Stop = function() Stop() end, Config = CONFIG, Version = VERSION }
genv.VyWallCrew = handle

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
local Directory = module("Directory")
if type(Save) ~= "table" or type(Network) ~= "table" or type(Instancing) ~= "table" or type(Directory) ~= "table" then
    Stop("game modules not found (is the game fully loaded?)")
    return
end
local okPets, Pets = gcall(function() return Directory.Pets end)
if not (okPets and type(Pets) == "table") then Pets = module("Directory", "Pets") end

local function isBig(id)
    local entry = type(Pets) == "table" and Pets[id] or nil
    if type(entry) == "table" and (entry.huge or entry.titanic or entry.gargantuan) then return true end
    return id:find("^Huge ") ~= nil or id:find("^Titanic ") ~= nil or id:find("^Gargantuan ") ~= nil
end

-- This event's pets: the pets in Diamond Mountain's eggs (the egg modules sit in the
-- Directory's Eggs.Events.DiamondMountain folder), plus any kind a wall has accepted.
-- Not Directory.Pets[...].fromZoneNumber: other events' pets share zone 279.
local eggPets, eggCount = {}, 0
-- An egg's pet entry may be "Marmot", {"Marmot", 60}, {name = "Marmot", ...} or a
-- { Marmot = 60 } pair; take every string and keep only real pet names.
local function addPetNames(key, entry)
    local function add(name)
        if type(name) == "string" and (type(Pets) ~= "table" or Pets[name] ~= nil) and not isBig(name) then
            eggPets[name] = true
        end
    end
    add(key)
    add(entry)
    if type(entry) == "table" then
        for _, v in pairs(entry) do add(v) end
    end
end
do
    local okEggs, eggs = gcall(function() return Directory.Eggs end)
    if not (okEggs and type(eggs) == "table") then eggs = module("Directory", "Eggs") end
    for _, egg in pairs(type(eggs) == "table" and eggs or {}) do
        local okDm, fromMountain = pcall(function()
            local script = type(egg) == "table" and egg._script or nil
            return typeof(script) == "Instance" and script.Parent ~= nil and script.Parent.Name == INSTANCE
        end)
        if okDm and fromMountain then
            eggCount += 1
            for key, entry in pairs(type(egg.pets) == "table" and egg.pets or {}) do
                addPetNames(key, entry)
            end
        end
    end
end
local accepted = {} -- pet ids a wall's crew has held: the server took them
local function isEventPet(id)
    return (eggPets[id] == true or accepted[id] == true) and not isBig(id)
end
local function learnAccepted(dm)
    for _, crew in pairs(type(dm.WallCrew) == "table" and dm.WallCrew or {}) do
        for kind, entry in pairs(type(crew) == "table" and crew or {}) do
            local id = type(entry) == "table" and entry.id or (type(kind) == "string" and kind:match("^(.-)|")) or nil
            if type(id) == "string" then accepted[id] = true end
        end
    end
end
local announced = false
local function announce()
    if announced then return end
    announced = true
    local names = {}
    for name in pairs(eggPets) do names[#names + 1] = name end
    table.sort(names)
    if #names > 0 then
        log("event pets (from %d Diamond Mountain eggs): %s", eggCount, table.concat(names, ", "))
    else
        log("could not read the Diamond Mountain eggs' pet lists; only pet kinds already on a wall are topped up")
    end
end

local function getSave()
    local ok, s = gcall(Save.Get)
    if ok and type(s) == "table" then return s end
    return nil
end
-- Save tables may use number or string keys.
local function at(t, k)
    if type(t) ~= "table" then return nil end
    local v = t[k]
    if v == nil then v = t[tostring(k)] end
    if v == nil and type(k) == "string" and tonumber(k) then v = t[tonumber(k)] end
    return v
end
local function mountain(save)
    local vars = type(save) == "table" and save.InstanceVars or nil
    local dm = type(vars) == "table" and vars[INSTANCE] or nil
    return type(dm) == "table" and dm or nil
end
-- The wall counts pets per kind: "<id>|<pt>|<sh>" (pt 1 golden, 2 rainbow; sh 1 shiny).
local function kindOf(item)
    return tostring(item.id) .. "|" .. tostring(math.floor(tonumber(item.pt) or 0)) .. "|" .. (item.sh and "1" or "0")
end
local function label(id, kind)
    local pt, sh = kind:match("|(%d+)|(%d+)$")
    local s = id
    if pt == "1" then s ..= " (golden)" elseif pt == "2" then s ..= " (rainbow)" end
    if sh == "1" then s ..= " (shiny)" end
    return s
end
local function onWall(dm, wall, kind)
    local crew = at(dm.WallCrew, wall)
    local entry = type(crew) == "table" and crew[kind] or nil
    return tonumber(type(entry) == "table" and entry.count) or 0
end

-- The wall being smashed: the first one not broken, if its camp is unlocked.
local function activeWall(dm)
    local broken = type(dm.Walls) == "table" and dm.Walls.Broken or nil
    if type(broken) ~= "table" then return nil, "no wall data in your save yet" end
    local count = 0
    for k in pairs(broken) do
        local n = tonumber(k)
        if n and n > count then count = math.floor(n) end
    end
    for n = 1, count do
        if at(broken, n) ~= true then
            if at(dm.InstanceZones, "__Zone_" .. n) == true then return n end
            return nil, string.format("camp %d is not unlocked yet", n)
        end
    end
    return nil, "every wall is broken"
end

-- Event pets not yet on the wall, one entry per inventory stack.
local function plan(save, dm, wall)
    local inventory = type(save.Inventory) == "table" and save.Inventory.Pet or nil
    local stacks = {}
    for uid, item in pairs(type(inventory) == "table" and inventory or {}) do
        if type(item) == "table" and type(item.id) == "string" and isEventPet(item.id) then
            stacks[#stacks + 1] = { uid = tostring(uid), id = item.id, kind = kindOf(item),
                amount = math.max(1, math.floor(tonumber(item._am) or 1)) }
        end
    end
    table.sort(stacks, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.uid < b.uid
    end)
    -- Spread the wall's count of a kind over that kind's stacks in a fixed order.
    local counted, todo = {}, {}
    for _, s in ipairs(stacks) do
        local left = onWall(dm, wall, s.kind) - (counted[s.kind] or 0)
        local covered = math.max(0, math.min(s.amount, left))
        counted[s.kind] = (counted[s.kind] or 0) + covered
        if s.amount > covered then
            todo[#todo + 1] = { uid = s.uid, id = s.id, kind = s.kind, count = s.amount - covered }
        end
    end
    return todo
end

local lastStatus, lastPlan, misses = nil, nil, 0
local function status(f, ...)
    local ok, s = pcall(string.format, f, ...)
    s = ok and s or tostring(f)
    if s ~= lastStatus then
        lastStatus = s
        log("%s", s)
    end
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

local function tick()
    if not onMountain() then
        status("waiting: you are not on Diamond Mountain")
        return
    end
    local save = getSave()
    local dm = mountain(save)
    if not dm then
        status("waiting: no Diamond Mountain data in your save yet")
        return
    end
    announce()
    learnAccepted(dm)
    local wall, why = activeWall(dm)
    if not wall then
        status("waiting: %s", why)
        return
    end
    local todo = plan(save, dm, wall)
    if #todo == 0 then
        status("wall %d: every event pet you own is on it", wall)
        return
    end
    lastStatus = nil
    if CONFIG.DRY_RUN then
        local lines = {}
        for _, p in ipairs(todo) do
            lines[#lines + 1] = string.format("would load %d x %s onto wall %d", p.count, label(p.id, p.kind), wall)
        end
        local text = table.concat(lines, "\n")
        if text ~= lastPlan then
            lastPlan = text
            for _, l in ipairs(lines) do log("DRY RUN: %s", l) end
            log("DRY RUN: nothing was sent. Set DRY_RUN = false at the top and run the script again.")
        end
        return
    end
    for i = 1, math.min(#todo, CONFIG.MAX_LOADS_PER_CHECK) do
        if not alive then return end
        local p = todo[i]
        local before = onWall(mountain(getSave()) or dm, wall, p.kind)
        local ok, a, b = gcall(Network.Invoke, "Instancing_InvokeCustomFromClient", INSTANCE, "DM_Walls_Load", wall, { [p.uid] = p.count })
        local reply = ok and (tostring(a) .. (b ~= nil and (", " .. tostring(b)) or "")) or ("error: " .. tostring(a))
        -- Confirmed by the save, not the reply: the wall's count of this kind must grow.
        local deadline, now, broke = os.clock() + CONFIG.CONFIRM_SECONDS, before, false
        while alive and now <= before and os.clock() < deadline do
            task.wait(0.5)
            local fresh = mountain(getSave()) or dm
            now = onWall(fresh, wall, p.kind)
            broke = at(type(fresh.Walls) == "table" and fresh.Walls.Broken or nil, wall) == true
            if broke then break end
        end
        if not alive then return end
        if broke then -- its crew was released; not a failed load
            log("wall %d broke; the next check loads the next wall", wall)
            return
        end
        if now > before then
            misses = 0
            log("wall %d: +%d %s (now %d on the wall) | reply: %s", wall, now - before, label(p.id, p.kind), now, reply)
        else
            misses += 1
            log("wall %d: loading %d x %s did not show on the wall | reply: %s", wall, p.count, label(p.id, p.kind), reply)
            if misses >= 2 then
                Stop("two loads in a row did not reach the wall, so nothing more is sent. Copy the lines above for the next fix.")
                return
            end
        end
        task.wait(CONFIG.REQUEST_GAP)
    end
end

log("v%s started%s; checking every %d s", VERSION, CONFIG.DRY_RUN and " in DRY RUN (nothing is sent)" or "", CONFIG.CHECK_EVERY)
task.spawn(function()
    while alive do
        local ok, err = pcall(tick)
        if not ok then log("check failed: %s", tostring(err)) end
        local waited = 0
        while alive and waited < CONFIG.CHECK_EVERY do
            task.wait(1)
            waited += 1
        end
    end
end)
