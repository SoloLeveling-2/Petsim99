--!nocheck
-- VY Wall Crew (Diamond Mountain) offline scenarios (mocked runtime, not live PS99).
-- Usage: lune run VY/tests/lune/dm_wallcrew.luau <script.luau> <scenario>
-- scenarios: dry-run | load | wall-break | new-hatch | unknown-kind | no-spare | not-inside
--            refused | no-effect | stop | no-egg-data
-- The fake server follows the live probe runs (2026-10-17/18). Run 3 (ZapHub) showed
-- DM_Walls_FillBest(wall): the server puts every spare event pet on the wall (crew keyed
-- "id|pt|sh", capped at what the player owns) and answers `true, nil`, or
-- `false, "No spare pets to send!"`. Pets stay in the inventory; a broken wall's crew is
-- released.
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
-- Live Directory.Pets raises on an unknown name ("Unknown Directory Pets.'Nice'",
-- Wall Crew v0.2 crashed on it at start, 2026-10-18).
dir.Pets = setmetatable({
    Marmot = { fromZoneNumber = 279 },
    ["Hiker Raccoon"] = { fromZoneNumber = 279 },
    ["Climber Goat"] = { fromZoneNumber = 279 },
    ["Huge Marmot"] = { fromZoneNumber = 279, huge = true },
    -- Other events' pets share zone 279: the live v0.1 dry run (2026-10-18) planned
    -- 13,343 Stitched Cats and 94 Mothmen for the wall.
    ["Stitched Cat"] = { fromZoneNumber = 279 },
    Mothman = { fromZoneNumber = 279 },
    Cat = { fromZoneNumber = 5 },
}, { __index = function(_, k) error("Unknown Directory Pets.'" .. tostring(k) .. "'", 2) end })
-- Directory.Eggs: this event's camp eggs are modules under Eggs.Events.DiamondMountain
-- (live `_script` paths); another event's egg sits beside them.
local function child(class, name, parent)
    local x = R.Instance.new(class)
    x.Name = name
    x.Parent = parent
    return x
end
local events = child("Folder", "Events", child("Folder", "Eggs", W.rs))
local dmEggs, otherEggs = child("Folder", "DiamondMountain", events), child("Folder", "BloodMoon", events)
dir.Eggs = {
    ["Trailhead Egg"] = { _script = child("ModuleScript", "1 | Trailhead Egg", dmEggs),
        pets = { { "Marmot", 60, "Nice" }, { "Hiker Raccoon", 40 } } },
    -- The live pet-list format is unknown: three plausible shapes.
    ["Russet Falls Egg"] = { _script = child("ModuleScript", "2 | Russet Falls Egg", dmEggs),
        pets = { ["Climber Goat"] = 50, ["Huge Marmot"] = 0.01 } },
    ["Summit Test Egg"] = { _script = child("ModuleScript", "3 | Summit Test Egg", dmEggs),
        pets = { { name = "Marmot", rarity = "Common" } } },
    ["Stitched Egg"] = { _script = child("ModuleScript", "Stitched Egg", otherEggs),
        pets = { { "Stitched Cat", 90 }, { "Mothman", 10 } } },
}
if scenario == "no-egg-data" then dir.Eggs = {} end
local inv = W.save.Inventory.Pet
inv.m1 = { id = "Marmot", _am = 331 }
inv.m2 = { id = "Marmot", sh = true }
inv.r1 = { id = "Hiker Raccoon", _am = 254 }
inv.g1 = { id = "Climber Goat", _am = 10, pt = 1 }
inv.h1 = { id = "Huge Marmot" }
inv.s1 = { id = "Stitched Cat", _am = 13343 }
inv.mo1 = { id = "Mothman", _am = 94 }
-- p1 (Cat x40) comes from the fake world.
local dm = {
    Walls = { Broken = { true, false, false, false, false }, Dealt = { 130000000, 0, 0, 0, 0 } },
    InstanceZones = { __Zone_1 = true, __Zone_2 = true },
    WallCrew = { [2] = { ["Hiker Raccoon|0|0"] = { count = 178, id = "Hiker Raccoon", power = 150 } } },
}
if scenario == "no-spare" then
    dm.WallCrew[2] = {
        ["Marmot|0|0"] = { count = 331, id = "Marmot" }, ["Marmot|0|1"] = { count = 1, id = "Marmot" },
        ["Hiker Raccoon|0|0"] = { count = 254, id = "Hiker Raccoon" },
    }
end
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
-- The server's own list of event pets. Expedition Wolf is in none of the fake eggs' pet
-- lists, so the script cannot tell it is an event pet; only the server can.
local EVENT = { Marmot = true, ["Hiker Raccoon"] = true, ["Climber Goat"] = true, ["Expedition Wolf"] = true }
if scenario == "no-spare" then EVENT["Climber Goat"] = nil end -- e.g. busy elsewhere: the server keeps them
local fills, other = {}, {}
W.handlers["Instancing_InvokeCustomFromClient"] = function(instance, action, ...)
    if instance ~= "DiamondMountain" or action ~= "DM_Walls_FillBest" then
        table.insert(other, action)
        return true
    end
    local wall = ...
    table.insert(fills, { wall = wall, n = select("#", ...), t = os.clock(), inside = W.instance })
    if W.instance ~= "DiamondMountain" then return false, "Not in instance" end
    if scenario == "refused" then return false, "Wall is busy" end
    if scenario == "no-effect" then return true, nil end
    if wall ~= activeWall() then return false, "Wrong wall" end
    local added = false
    for _, item in pairs(inv) do
        local k = key(item)
        local onIt = (dm.WallCrew[wall] and dm.WallCrew[wall][k] and dm.WallCrew[wall][k].count) or 0
        if EVENT[item.id] and owned(k) > onIt then
            added = true
            luneTask.delay(0.5 / R.SPEED, function() -- replication delay (0.5 virtual s)
                dm.WallCrew[wall] = dm.WallCrew[wall] or {}
                local e = dm.WallCrew[wall][k] or { count = 0, id = item.id }
                e.count = owned(k)
                dm.WallCrew[wall][k] = e
            end)
        end
    end
    if not added then return false, "No spare pets to send!" end
    return true, nil
end

local function crewCount(wall, k)
    local c = dm.WallCrew[wall]
    return c and c[k] and c[k].count or 0
end
local function everyEventPetOn(wall)
    return crewCount(wall, "Marmot|0|0") == 331 and crewCount(wall, "Marmot|0|1") == 1
        and crewCount(wall, "Hiker Raccoon|0|0") == 254 and crewCount(wall, "Climber Goat|1|0") == 10
end
-- FillBest names only the wall; the server picks the pets.
local function onlyWallSent()
    for _, f in ipairs(fills) do
        if f.n ~= 1 or type(f.wall) ~= "number" then return false end
    end
    return true
end
local function noOtherRequests() return #other == 0 end

local genv = H.newVM("wall crew")
local handle = genv.VyWallCrew
H.check(handle ~= nil and type(handle.Stop) == "function", "global handle with Stop")

if scenario == "dry-run" then
    H.wait(40)
    H.check(#fills == 0 and noOtherRequests(), "dry run sends nothing (" .. #fills .. " fills)")
    H.check(said("would ask the server to fill wall 2"), "dry run names the wall it would fill")
    H.check(said("331 x Marmot") and said("1 x Marmot (shiny)"), "dry run lists the Marmots not on the wall")
    H.check(said("76 x Hiker Raccoon"), "dry run counts only the 76 Raccoons not yet on the wall")
    H.check(said("10 x Climber Goat (golden)"), "dry run lists the golden Goats")
    H.check(not said("Huge Marmot") and not said("x Cat"), "dry run never lists Huge or non-event pets")
    H.check(not said("Stitched Cat") and not said("Mothman"), "dry run never lists other events' pets that share zone 279")
    H.check(said("event pets (from 3 Diamond Mountain eggs): Climber Goat, Hiker Raccoon, Marmot"),
        "dry run lists the event pets it found, from the camp eggs")
    H.check(#H.console("would ask the server") == 1, "the dry-run plan is printed once, not every check")
elseif scenario == "load" then
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    H.check(everyEventPetOn(2), "every event pet is on wall 2 (Marmot 331+1, Raccoon 254, golden Goat 10)")
    H.check(#fills == 1 and fills[1].wall == 2, "one FillBest for wall 2 did it (" .. #fills .. ")")
    H.check(onlyWallSent() and noOtherRequests(), "FillBest names only the wall; nothing else is sent")
    local mark = #fills
    H.wait(60)
    H.check(#fills == mark, "nothing more is sent while nothing changes (" .. (#fills - mark) .. ")")
    H.check(said("wall 2: +418 pets (now 596 on the wall)"), "the gain on the wall is printed")
    H.check(inv.m1._am == 331 and inv.r1._am == 254, "inventory unchanged (pets stay owned)")
elseif scenario == "wall-break" then
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    -- Wall 2 breaks: its crew is released and camp 3 opens.
    dm.Walls.Broken[2] = true
    dm.WallCrew[2] = nil
    dm.InstanceZones.__Zone_3 = true
    H.waitFor(function() return everyEventPetOn(3) end, 120)
    H.check(everyEventPetOn(3), "after wall 2 breaks, every event pet goes onto wall 3")
    H.check(fills[#fills].wall == 3, "the fill names wall 3")
    H.check(not said("did not reach the wall"), "a wall break is not counted as a failed fill")
    dm.Walls.Broken[3] = true
    dm.WallCrew[3] = nil
    local mark = #fills
    H.wait(60)
    H.check(#fills == mark, "camp 4 not unlocked: nothing is sent to wall 4 (" .. (#fills - mark) .. ")")
    H.check(said("camp 4 is not unlocked"), "status says camp 4 is not unlocked")
elseif scenario == "new-hatch" then
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    local mark = #fills
    inv.r1._am = 264 -- 10 more Raccoons hatched
    H.waitFor(function() return crewCount(2, "Hiker Raccoon|0|0") == 264 end, 60)
    H.check(crewCount(2, "Hiker Raccoon|0|0") == 264, "10 newly hatched Raccoons are added to the wall")
    H.check(#fills == mark + 1, "one more fill for the new pets (" .. (#fills - mark) .. ")")
elseif scenario == "unknown-kind" then
    -- A kind no fake egg lists: only the server knows it is an event pet. Any change in the
    -- pets you own makes the script ask once.
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    inv.w1 = { id = "Expedition Wolf", _am = 5 }
    H.waitFor(function() return crewCount(2, "Expedition Wolf|0|0") == 5 end, 60)
    H.check(crewCount(2, "Expedition Wolf|0|0") == 5, "a new pet kind the script cannot identify still reaches the wall")
    local mark = #fills
    H.wait(60)
    H.check(#fills == mark, "then nothing more is sent (" .. (#fills - mark) .. ")")
elseif scenario == "no-spare" then
    -- Everything the server counts is already on the wall; it keeps the golden Goats off
    -- (EVENT above), while the script's own list says they are missing.
    H.waitFor(function() return #fills >= 1 end, 60)
    H.check(said("No spare pets to send!"), "the server's answer is printed")
    H.check(said("not on it: 10 x Climber Goat (golden)"), "it names the pets the server did not take")
    local mark = #fills
    H.wait(90)
    H.check(#fills == mark, "after 'No spare pets to send!' the same request is not repeated (" .. (#fills - mark) .. ")")
    H.check(genv.VyWallCrew ~= nil, "'No spare pets' is not a failure: the script keeps running")
    inv.r1._am = 260 -- new pets: worth asking again
    H.waitFor(function() return crewCount(2, "Hiker Raccoon|0|0") == 260 end, 60)
    H.check(crewCount(2, "Hiker Raccoon|0|0") == 260, "after a hatch it asks again")
    mark = #fills
    H.wait(60)
    H.check(#fills == mark, "the Goats the server kept off are not asked about again (" .. (#fills - mark) .. ")")
elseif scenario == "not-inside" then
    H.wait(60)
    H.check(#fills == 0, "not on Diamond Mountain: nothing is sent (" .. #fills .. ")")
    H.check(said("not on Diamond Mountain"), "status says it waits for Diamond Mountain")
    W.instance = "DiamondMountain" -- the player enters
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    H.check(everyEventPetOn(2), "after entering, every event pet is loaded")
elseif scenario == "refused" then
    H.wait(80)
    H.check(#fills == 2, "stops after two refused fills (" .. #fills .. ")")
    H.check(said("Wall is busy"), "the server's reply is printed")
    H.check(genv.VyWallCrew == nil, "the script stopped itself")
elseif scenario == "no-effect" then
    -- The server says yes but the wall's crew never changes.
    H.wait(80)
    H.check(#fills == 2, "stops after two fills that did not reach the wall (" .. #fills .. ")")
    H.check(said("did not reach the wall"), "says the fill did not reach the wall")
    H.check(genv.VyWallCrew == nil, "the script stopped itself")
elseif scenario == "no-egg-data" then
    -- Without the eggs' pet lists the server still knows the event pets: one fill does it.
    H.waitFor(function() return everyEventPetOn(2) end, 120)
    H.check(said("could not read"), "says it could not read the camp eggs' pet lists")
    H.check(everyEventPetOn(2) and #fills == 1, "one fill still puts every event pet on the wall (" .. #fills .. ")")
elseif scenario == "stop" then
    H.wait(1)
    handle.Stop()
    local mark = #fills
    H.wait(60)
    H.check(#fills == mark, "no requests after Stop (" .. (#fills - mark) .. ")")
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
