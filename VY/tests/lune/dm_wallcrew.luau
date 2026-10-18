--!nocheck
-- VY Wall Crew (Diamond Mountain) offline scenarios (mocked runtime, not live PS99).
-- Usage: lune run VY/tests/lune/dm_wallcrew.luau <script.luau> <scenario>
-- scenarios: dry-run | load | wall-break | new-hatch | not-inside | refused | stop
-- The fake server follows the two live probe runs (2026-10-17/18): DM_Walls_Load adds
-- `count` pets of one stack to the wall's crew (keyed "id|pt|sh"), capped at what the
-- player owns; pets stay in the inventory; a broken wall's crew is released.
local process = require("@lune/process")
local luneTask = require("@lune/task")
local R = require("./roblox_mock")
local W = require("./vy_world")
local H = require("./harness")

local path, scenario = process.args[1], process.args[2] or "load"
local function said(text) return #H.console(text) > 0 end
local source = H.loadSource(path)
if scenario ~= "dry-run" then
    H.source = source:gsub("DRY_RUN = true,", "DRY_RUN = false,", 1)
end

W.build({ rank = 12, keys = 20, goals = {} })
W.instance = scenario ~= "not-inside" and "DiamondMountain" or nil

-- Directory.Pets: event pets come from zone 279 (live Directory data).
local dir = rawget(W.rs:FindFirstChild("Library"):FindFirstChild("Directory"), "__module")
dir.Pets = {
    Marmot = { fromZoneNumber = 279 },
    ["Hiker Raccoon"] = { fromZoneNumber = 279 },
    ["Climber Goat"] = { fromZoneNumber = 279 },
    ["Huge Marmot"] = { fromZoneNumber = 279, huge = true },
    Cat = { fromZoneNumber = 5 },
}
local inv = W.save.Inventory.Pet
inv.m1 = { id = "Marmot", _am = 331 }
inv.m2 = { id = "Marmot", sh = true }
inv.r1 = { id = "Hiker Raccoon", _am = 254 }
inv.g1 = { id = "Climber Goat", _am = 10, pt = 1 }
inv.h1 = { id = "Huge Marmot" }
-- p1 (Cat x40) comes from the fake world.
local dm = {
    Walls = { Broken = { true, false, false, false, false }, Dealt = { 130000000, 0, 0, 0, 0 } },
    InstanceZones = { __Zone_1 = true, __Zone_2 = true },
    WallCrew = { [2] = { ["Hiker Raccoon|0|0"] = { count = 178, id = "Hiker Raccoon", power = 150 } } },
}
W.save.InstanceVars = { DiamondMountain = dm }

local function key(item) return item.id .. "|" .. (tonumber(item.pt) or 0) .. "|" .. (item.sh and 1 or 0) end
local function owned(k)
    local n = 0
    for _, item in pairs(inv) do if key(item) == k then n += item._am or 1 end end
    return n
end
local function activeWall()
    for n = 1, 5 do if not dm.Walls.Broken[n] then return n end end
    return nil
end
local EVENT = { Marmot = true, ["Hiker Raccoon"] = true, ["Climber Goat"] = true }
local loads, refused = {}, scenario == "refused"
W.handlers["Instancing_InvokeCustomFromClient"] = function(instance, action, wall, map)
    if instance ~= "DiamondMountain" or action ~= "DM_Walls_Load" then return true end
    table.insert(loads, { wall = wall, map = map, t = os.clock(), inside = W.instance })
    if W.instance ~= "DiamondMountain" then return false, "Not in instance" end
    if refused then return false, "Wall is busy" end
    if wall ~= activeWall() then return false, "Wrong wall" end
    for uid, n in pairs(map) do
        local item = inv[uid]
        if not item or not EVENT[item.id] then return false, "Not an event pet" end
        local k = key(item)
        luneTask.delay(0.5 / R.SPEED, function() -- replication delay (0.5 virtual s)
            dm.WallCrew[wall] = dm.WallCrew[wall] or {}
            local e = dm.WallCrew[wall][k] or { count = 0, id = item.id }
            e.count = math.min(owned(k), e.count + n)
            dm.WallCrew[wall][k] = e
        end)
    end
    return true
end

local function crewCount(wall, k)
    local c = dm.WallCrew[wall]
    return c and c[k] and c[k].count or 0
end
local function loadsOf(uid)
    local n = 0
    for _, l in ipairs(loads) do if l.map[uid] then n += 1 end end
    return n
end
local function everyEventPetOn(wall)
    return crewCount(wall, "Marmot|0|0") == 331 and crewCount(wall, "Marmot|0|1") == 1
        and crewCount(wall, "Hiker Raccoon|0|0") == 254 and crewCount(wall, "Climber Goat|1|0") == 10
end
local function nothingWrongSent()
    for _, l in ipairs(loads) do
        if l.map.h1 or l.map.p1 then return false end
    end
    return true
end

local genv = H.newVM("wall crew")
local handle = genv.VyWallCrew
H.check(handle ~= nil and type(handle.Stop) == "function", "global handle with Stop")

if scenario == "dry-run" then
    H.wait(40)
    H.check(#loads == 0, "dry run sends no load (" .. #loads .. ")")
    H.check(said("would load 331 x Marmot onto wall 2"), "dry run names the Marmots for wall 2")
    H.check(said("would load 1 x Marmot (shiny)"), "dry run names the shiny Marmot")
    H.check(said("would load 76 x Hiker Raccoon onto wall 2"), "dry run counts only the 76 Raccoons not yet on the wall")
    H.check(said("would load 10 x Climber Goat (golden)"), "dry run names the golden Goats")
    H.check(not said("Huge Marmot") and not said("x Cat"), "dry run never plans Huge or non-event pets")
elseif scenario == "load" then
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    H.check(everyEventPetOn(2), "every event pet is on wall 2 (Marmot 331+1, Raccoon 254, golden Goat 10)")
    H.check(nothingWrongSent(), "no Huge or non-event pet was sent")
    H.check(loadsOf("r1") == 1, "the Raccoon stack needed one load of the missing 76 (" .. loadsOf("r1") .. ")")
    local r1 = nil
    for _, l in ipairs(loads) do if l.map.r1 then r1 = l.map.r1 end end
    H.check(r1 == 76, "Raccoon load asked for exactly the missing 76 (" .. tostring(r1) .. ")")
    local mark = #loads
    H.wait(60)
    H.check(#loads == mark, "no further loads once every pet is on the wall (" .. (#loads - mark) .. ")")
    local gap = math.huge
    for i = 2, #loads do gap = math.min(gap, loads[i].t - loads[i - 1].t) end
    H.check(gap >= 1.4 / R.SPEED, "loads are at least 1.5 virtual s apart")
    H.check(inv.m1._am == 331 and inv.r1._am == 254, "inventory unchanged (pets stay owned)")
elseif scenario == "wall-break" then
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    -- Wall 2 breaks: its crew is released and camp 3 opens.
    dm.Walls.Broken[2] = true
    dm.WallCrew[2] = nil
    dm.InstanceZones.__Zone_3 = true
    H.waitFor(function() return everyEventPetOn(3) end, 120)
    H.check(everyEventPetOn(3), "after wall 2 breaks, every event pet is loaded onto wall 3")
    H.check(not said("did not show on the wall"), "a wall breaking during a load is not counted as a failed load")
    H.check(nothingWrongSent(), "no Huge or non-event pet was sent")
    dm.Walls.Broken[3] = true
    dm.WallCrew[3] = nil
    local mark = #loads
    H.wait(60)
    H.check(#loads == mark, "camp 4 not unlocked: nothing is sent to wall 4 (" .. (#loads - mark) .. ")")
    H.check(said("camp 4 is not unlocked"), "status says camp 4 is not unlocked")
elseif scenario == "new-hatch" then
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    inv.r1._am = 264 -- 10 more Raccoons hatched
    H.waitFor(function() return crewCount(2, "Hiker Raccoon|0|0") == 264 end, 60)
    H.check(crewCount(2, "Hiker Raccoon|0|0") == 264, "10 newly hatched Raccoons are added to the wall")
    local last = loads[#loads]
    H.check(last and last.map.r1 == 10, "the top-up asked for exactly 10 (" .. tostring(last and last.map.r1) .. ")")
elseif scenario == "not-inside" then
    H.wait(60)
    H.check(#loads == 0, "not on Diamond Mountain: nothing is sent (" .. #loads .. ")")
    H.check(said("not on Diamond Mountain"), "status says it waits for Diamond Mountain")
    W.instance = "DiamondMountain" -- the player enters
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    H.check(everyEventPetOn(2), "after entering, every event pet is loaded")
elseif scenario == "refused" then
    H.wait(80)
    H.check(#loads == 2, "stops after two loads the wall did not show (" .. #loads .. ")")
    H.check(said("Wall is busy"), "the server's reply is printed")
    H.check(genv.VyWallCrew == nil, "the script stopped itself")
elseif scenario == "stop" then
    H.wait(1)
    handle.Stop()
    local mark = #loads
    H.wait(60)
    H.check(#loads == mark, "no requests after Stop (" .. (#loads - mark) .. ")")
    H.check(genv.VyWallCrew == nil, "Stop removes the global handle")
    -- Re-running replaces a running copy.
    H.runIn(genv, "second run")
    local second = genv.VyWallCrew
    H.runIn(genv, "third run")
    H.check(second ~= nil and genv.VyWallCrew ~= second and genv.VyWallCrew ~= nil, "a new run replaces the running copy")
    genv.VyWallCrew.Stop()
end
if process.env.WALLCREW_SHOW == "1" then for _, l in ipairs(H.printed) do print("   | " .. l) end end
H.scanErrors(scenario)
process.exit(H.finish() and 0 or 1)
