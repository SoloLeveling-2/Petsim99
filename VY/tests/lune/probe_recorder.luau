--!nocheck
-- Offline checks for the read-only probes in VY/tools (mocked runtime, not live PS99).
--   lune run probe_recorder.luau <probe.luau> <event|general> [nosnm]
-- The mock models the one Roblox detail the recorder depends on: a `obj:Method()` call
-- on an Instance sets the thread's namecall method and runs the (possibly hooked)
-- __namecall handler, which reads that method when it dispatches. A colon call made
-- inside a hook therefore changes the method the game's own call is dispatched as.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local luneTask = require("@lune/task")
local process = require("@lune/process")

local PROBE, KIND = process.args[1], process.args[2] or "event"
local SPEED = 100 -- virtual seconds per real second for task.delay / task.wait

local failures = {}
local function check(cond, msg)
    if cond then print("ok   " .. msg) else table.insert(failures, msg) print("FAIL " .. msg) end
    return cond
end

-- Instances ----------------------------------------------------------------------------
local M = { atom = nil, identity = 7, received = {}, otherHookSeen = 0, files = {}, printed = {} }
local data = setmetatable({}, { __mode = "k" })
local METHODS = {}
local NC -- current __namecall handler (hookmetamethod replaces it)
local mt = {}
mt.__index = function(self, k)
    -- Another script's __index hook that makes a colon call (seen in public hub code).
    if M.indexHook and k == "Name" then M.indexHook(self) end
    local d = data[self]
    if d.props[k] ~= nil then return d.props[k] end
    if METHODS[k] then
        return function(selfArg, ...)
            M.atom = k -- what a NAMECALL does before the metamethod runs
            return NC(selfArg, ...)
        end
    end
    for _, c in ipairs(d.children) do if data[c].props.Name == k then return c end end
    return nil
end
mt.__tostring = function(self) return data[self].props.Name end

local function new(class, name, parent, extra)
    local inst = setmetatable({}, mt)
    local props = { ClassName = class, Name = name or class, Parent = parent }
    for k, v in pairs(extra or {}) do props[k] = v end
    data[inst] = { props = props, children = {}, attrs = {}, module = nil }
    if parent then table.insert(data[parent].children, inst) end
    return inst
end

local function descendants(inst, acc)
    for _, c in ipairs(data[inst].children) do
        acc[#acc + 1] = c
        descendants(c, acc)
    end
    return acc
end
local ISA = { BasePart = { Part = true, MeshPart = true }, ModuleScript = { ModuleScript = true } }
METHODS.GetService = function(self, name)
    for _, c in ipairs(data[self].children) do if data[c].props.ClassName == name then return c end end
    error("no service " .. name)
end
METHODS.FindFirstChild = function(self, name)
    for _, c in ipairs(data[self].children) do if data[c].props.Name == name then return c end end
    return nil
end
METHODS.GetChildren = function(self) return table.clone(data[self].children) end
METHODS.GetDescendants = function(self) return descendants(self, {}) end
METHODS.IsA = function(self, class)
    local cls = data[self].props.ClassName
    return cls == class or (ISA[class] ~= nil and ISA[class][cls] == true)
end
METHODS.GetAttributes = function(self) return table.clone(data[self].attrs) end
METHODS.GetFullName = function(self)
    local parts, cur = {}, self
    while cur and data[cur].props.ClassName ~= "DataModel" do
        table.insert(parts, 1, data[cur].props.Name)
        cur = data[cur].props.Parent
    end
    return table.concat(parts, ".")
end
METHODS.FireServer = function(self, ...)
    table.insert(M.received, { method = "FireServer", remote = data[self].props.Name, args = table.pack(...) })
end
METHODS.InvokeServer = function(self, ...)
    table.insert(M.received, { method = "InvokeServer", remote = data[self].props.Name, args = table.pack(...) })
    local action = select(2, ...)
    if M.replies and M.replies[action] ~= nil then return M.replies[action] end
    return true
end
-- The game's own __namecall: dispatches on the CURRENT namecall method.
local function original(self, ...)
    local f = METHODS[M.atom]
    if not f then error(tostring(M.atom) .. " is not a valid member") end
    return f(self, ...)
end
NC = original

-- Fake PS99 world ----------------------------------------------------------------------
local game = new("DataModel", "Game", nil, { PlaceId = 8737899170 })
local players = new("Players", "Players", game)
local lp = new("Player", "TestUser", players, { UserId = 123456, DisplayName = "ÉloïseShown" })
data[players].props.LocalPlayer = lp
local RS = new("ReplicatedStorage", "ReplicatedStorage", game)
local workspace = new("Workspace", "Workspace", game, { StreamingEnabled = true })
new("HttpService", "HttpService", game)
local net = new("Folder", "Network", RS)
local remote = new("RemoteEvent", "DiamondMountain_SendPets", net)
local remoteFn = new("RemoteFunction", "Expedition_Claim", net)
local dmg = new("RemoteEvent", "Breakables_PlayerDealDamage", net)
local chat = new("RemoteEvent", "Chat_Say", net)
local hatch = new("RemoteFunction", "CustomEggs_Hatch", net)
local others = {}
for i = 1, 420 do others[i] = new("RemoteEvent", "Other_" .. i, net) end
local pings = new("RemoteEvent", "UnreliableRemoteEvent", net)
local custom = new("RemoteFunction", "Instancing_InvokeCustomFromClient", net)
local library = new("Folder", "Library", RS)
local client = new("Folder", "Client", library)
local dmCmds = new("ModuleScript", "DiamondMountainCmds", client)
data[dmCmds].module = { OnJoin = function() end }
local wallsCmds = new("ModuleScript", "Walls", dmCmds)
data[wallsCmds].module = { FillBest = function(_wall, _all) end }
local SAVE = {
    Rank = 3, Goals = {}, Inventory = { Pet = { a = { id = "Cat" } }, Misc = {} },
    Events = { Mountain = { Camps = { Camp1 = { WallHP = 50 } } } },
    Instances = { DM = { State = { Deep = { Progress = 1 } } } },
}
local saveMod = new("ModuleScript", "Save", client)
data[saveMod].module = { Get = function() return SAVE end }
local dirMod = new("ModuleScript", "Directory", library)
local boosts = { ["Boost | DiamondMountainLuck1"] = { DisplayName = "Luck Boost" } }
for i = 1, 80 do boosts["Boost | Garden" .. i] = { DisplayName = "Garden Boost " .. i } end -- other events
data[dirMod].module = {
    DiamondMountainCamps = { Camp1 = { Order = 1 } }, Ranks = {},
    Currency = { Acorns = { DisplayName = "Acorns" }, Coins = { DisplayName = "Coins" } },
    Boosts = boosts,
}
-- A Directory table that is only a child module (not yet loaded into Directory).
local eggsMod = new("ModuleScript", "Eggs", dirMod)
data[eggsMod].module = {
    ["Camp Egg 3"] = { DisplayName = "Camp Egg 3", Currency = "TrailCoins" },
    ["Egg 251"] = { DisplayName = "Summit Egg" }, -- event name only in DisplayName
    ["Cat Egg"] = { DisplayName = "Cat Egg" },
}
local things = new("Folder", "__THINGS", workspace)
local ic = new("Folder", "__INSTANCE_CONTAINER", things)
local active = new("Folder", "Active", ic)
local instances = new("Folder", "Instances", things)
local dmState = new("Folder", "DiamondMountain", instances)
local customEggs = new("Folder", "CustomEggs", things)
local campEgg = new("Model", "9af55dac", customEggs)
data[campEgg].attrs.EggId = "Trailhead Egg"
local camp = new("Model", "Camp1", workspace)
for i = 1, 300 do new("Model", "CampTorch" .. i, camp) end -- one camp's many matching parts
new("Model", "YetiArena", workspace)
local pet = new("Model", "PetModel", workspace)

-- Environment --------------------------------------------------------------------------
local env = {
    game = game, workspace = workspace, Workspace = workspace,
    typeof = function(v) return data[v] and "Instance" or typeof(v) end,
    task = {
        wait = function(t) luneTask.wait((t or 0.03) / SPEED) return t end,
        delay = function(t, f, ...) return luneTask.delay((t or 0) / SPEED, f, ...) end,
        defer = function(f, ...)
            -- Roblox raises "Maximum re-entrancy depth (80) exceeded calling task.defer" in a thread
            -- that is already 80 deferrals deep (v5 review); M.deferLimit models that thread.
            if M.deferLimit then error("Maximum re-entrancy depth (80) exceeded calling task.defer") end
            return luneTask.defer(f, ...)
        end,
        spawn = function(f, ...) return luneTask.spawn(f, ...) end,
    },
    print = function(...)
        local p = {}
        for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
        table.insert(M.printed, table.concat(p, " "))
    end,
    require = function(m)
        local mod = data[m] and data[m].module
        if mod == nil then error("require on a non-module") end
        return mod
    end,
    setthreadidentity = function(n) M.identity = n end,
    getthreadidentity = function() return M.identity end,
    getnamecallmethod = function() return M.atom end,
    checkcaller = function() return M.fromScript == true end, -- true: an executor script called
    -- "nosnm": an executor without setnamecallmethod, so the probe's re-assert cannot hide a
    -- property read or colon call before dispatch.
    setnamecallmethod = (process.env.PROBE_NO_SNM ~= "1" and process.args[3] ~= "nosnm") and function(m) M.atom = m end or nil,
    hookmetamethod = function(_, name, fn)
        assert(name == "__namecall", "only __namecall is modelled")
        local prev = NC
        NC = fn
        return prev
    end,
    writefile = function(p, c)
        M.files[p] = c
        M.writes = M.writes or {}
        table.insert(M.writes, c) -- every save, so a partial one is seen even if the final replaces it
    end,
    setclipboard = function() end,
    identifyexecutor = function() return "Potassium", "1.0" end,
    getgenv = function() return { VyAutoRank = { State = { alive = true } } } end, -- VY still running
}

local source = fs.readFile(PROBE)
-- Shorten the recording window (the general probe ships with recording OFF).
source = source:gsub("local RECORD_SECONDS = %d+", "local RECORD_SECONDS = 30", 1)
source = source:gsub("local SAVE_EVERY = %d+", "local SAVE_EVERY = 10", 1) -- partial saves at 10 and 20 s
local fn = luau.load(source, { debugName = "probe", environment = env })
local ran, err = pcall(fn)
check(ran, "probe runs to the end of its main chunk (" .. tostring(err) .. ")")

-- Another script hooks __namecall while the probe is recording.
local prevOther
prevOther = env.hookmetamethod(game, "__namecall", function(self, ...)
    local m = env.getnamecallmethod()
    if m == "FireServer" or m == "InvokeServer" then M.otherHookSeen += 1 end
    return prevOther(self, ...)
end)

-- The GAME sends requests with an Instance argument while the recorder runs.
remote:FireServer(pet, 5)
local first = M.received[1]
check(first ~= nil and first.method == "FireServer" and first.remote == "DiamondMountain_SendPets",
    "bug 1: game's FireServer with an Instance argument reaches the server during recording (got "
        .. (first and (first.method .. " " .. first.remote) or "nothing") .. ")")
check(first ~= nil and first.args.n == 2 and first.args[1] == pet and first.args[2] == 5,
    "bug 1: the request keeps its arguments unchanged")
local okInvoke, reply = pcall(function() return remoteFn:InvokeServer(pet) end)
check(okInvoke and reply == true, "bug 1: game's InvokeServer with an Instance argument returns the server reply")

-- The game reuses one scratch table and clears it right after sending it.
local scratch = { Wall = 3, Slot = 2 }
remote:FireServer(scratch)
table.clear(scratch)
-- A table whose metatable is protected: copying it fails; the request must still go through.
local locked = setmetatable({ Locked = 1 }, { __metatable = "locked" })
local before0 = #M.received
remote:FireServer(locked)
check(#M.received == before0 + 1 and M.received[#M.received].args[1] == locked,
    "a table argument with a protected metatable is sent unchanged")

SAVE.Instances.DM.State.Deep.Progress = 2 -- a Save field changes while the user plays

-- Run 1 lost its last 160 s: ~130 fps pings (each with a new value) filled the 200 lines.
M.replies = { DM_Walls_Status = { Walls = { [1] = { HP = 1000000, Dealt = 5 } } } }
luneTask.spawn(function() -- the game's own threads
    for i = 1, 300 do pings:FireServer({ fps = 14 + i / 1000 }) end
    custom:InvokeServer("DiamondMountain", "DM_Walls_Status")
    custom:InvokeServer("DiamondMountain", "DM_Walls_Load", 1, { ada4 = 1 })
    -- Another executor script (e.g. a script hub) sends an event action.
    M.fromScript = true
    custom:InvokeServer("DiamondMountain", "DM_Yeti_Feed", { y1 = 1 })
    M.fromScript = false
end)
-- ZapHub-test review (2026-10-18): a hub's hooks, heavy traffic, identical requests.
local hookedFire = nil
luneTask.spawn(function()
    if KIND == "general" then -- heavy farming noise, then the one action the user does by hand
        for _ = 1, 1000 do dmg:FireServer({ x = 1 }) end
        chat:FireServer("the one action")
    end
    M.indexHook = function(inst) inst:IsA("Model") end
    remote:FireServer(pet, 7)
    hookedFire = M.received[#M.received]
    M.indexHook = nil
    for _ = 1, 5 do dmg:FireServer({ x = 1 }) end
    for i = 1, 6000 do pings:FireServer({ fps = 120 + i / 1000 }) end
    M.fromScript = true
    custom:InvokeServer("DiamondMountain", "DM_Walls_Load", 1, { ada4 = 1 })
    M.fromScript = false
    chat:FireServer("hello ÉloïseShown")
    for i = 1, 420 do others[i]:FireServer(i) end
    custom:InvokeServer("DiamondMountain", "DM_Expedition_Start", 1)
    hatch:InvokeServer("9af55dac", 3)
    M.replies.DM_Walls_Status = { Walls = { [2] = { HP = 2000000 } } }
    custom:InvokeServer("DiamondMountain", "DM_Walls_Status")
    custom:InvokeServer("DiamondMountain", "DM_Walls_Status")
end)
-- A game thread already at Roblox's task.defer re-entrancy limit sends a request.
local limitFire, limitInvoke = nil, nil
luneTask.spawn(function()
    local before = #M.received
    M.deferLimit = true
    local okF = pcall(function() remote:FireServer(pet, 9) end)
    local okI, r = pcall(function() return remoteFn:InvokeServer(pet) end)
    M.deferLimit = false
    limitFire = okF and #M.received >= before + 1
    limitInvoke = okI and r == true
end)
-- Telemetry and the event's own Save data change; the player enters the mountain.
SAVE.Engagement = { Stats = { ["Eggs Opened"] = { [1] = 22 } } }
SAVE.InstanceVars = { DiamondMountain = { WallDamage = 161386 } }
data[dmState].attrs.DM_YetiHealth = 123
local inside = new("Model", "DiamondMountain", active)
local camps = new("Folder", "Camps", inside)
local wall = new("Model", "RubbleWall", new("Model", "Camp1", camps))
data[wall].attrs.WallIndex = 1
new("ProximityPrompt", "LoadPrompt", wall, { ActionText = "Load Pets", ObjectText = "Rubble Wall" })

luneTask.wait(45 / SPEED) -- recording window (30 virtual s) is over
local partialSaved = false
for i = 1, #(M.writes or {}) - 1 do -- any save before the final one
    if M.writes[i]:find("PARTIAL report", 1, true) then partialSaved = true end
end
local name, report = next(M.files)
check(report ~= nil, "report file written (" .. tostring(name) .. ")")
report = report or ""
if process.env.PROBE_SHOW == "1" then print(report) end

local before = #M.received
local seenBefore = M.otherHookSeen
remote:FireServer(pet, 6)
check(#M.received == before + 1 and M.received[#M.received].method == "FireServer",
    "after recording: game requests still reach the server")
check(M.otherHookSeen == seenBefore + 1,
    "bug 2: a __namecall hook installed by another script during recording still runs after recording ends")
check(M.identity == 7, "bug 3: thread identity restored to the executor's own value (7), got " .. tostring(M.identity))
check(report:find("DiamondMountain_SendPets(Instance<Model>Workspace.PetModel, 5)", 1, true) ~= nil,
    "recorder: the request is reported with its Instance argument path")
check(not report:find("123456", 1, true) and not report:find("TestUser", 1, true), "report is redacted")
check(limitFire == true and limitInvoke == true,
    "a request from a thread at the task.defer limit is still sent and answered (only its log line may be lost)")
check(not report:find("Breakables_PlayerDealDamage({x=1})", 1, true), "noise remotes get no lines")
if KIND == "general" then
    check(report:find('Chat_Say("the one action")', 1, true) ~= nil, "general probe: 1000 noise requests do not hide the one action")
end
check(hookedFire ~= nil and hookedFire.method == "FireServer" and hookedFire.remote == "DiamondMountain_SendPets"
    and hookedFire.args[2] == 7, "a hub's __index hook (colon call on .Name) cannot change how the game's request is sent")
-- The event probe prints a table's entries; the general probe prints its size.
local scratchShown = KIND == "event" and (report:find("Wall=3", 1, true) and report:find("Slot=2", 1, true))
    or report:find("DiamondMountain_SendPets(table(2))", 1, true)
check(scratchShown ~= nil, "a scratch table cleared right after the request is reported as it was sent")
local lockedShown = KIND == "event" and report:find("Locked=1", 1, true)
    or report:find("DiamondMountain_SendPets(table(1))", 1, true)
check(lockedShown ~= nil, "a protected-metatable table argument is still reported")

if KIND == "event" then
    check(report:find("WallHP", 1, true) ~= nil, "bug 4: nested fields inside a matched Save table are shown")
    check(report:find("Save.Instances.DM.State.Deep.Progress : 1 -> 2", 1, true) ~= nil,
        "bug 4: a Save change under non-keyword names is found by the before/after diff")
    check(report:find("YetiArena", 1, true) ~= nil, "bug 5: summit objects still listed after a crowded camp")
    check(report:find("Active instance", 1, true) ~= nil, "bug 5: active instance and streaming state reported")
    -- One run collects everything the event script needs.
    check(report:find("executor: Potassium 1.0", 1, true) ~= nil, "executor name reported")
    check(report:find("thread identity: 7", 1, true) ~= nil, "executor thread identity reported")
    check(report:find("MISSING: ", 1, true) ~= nil and report:find("firetouchinterest", 1, true) ~= nil,
        "missing executor functions are listed by name")
    check(report:find("VY AutoRank is running", 1, true) ~= nil, "warns when VY AutoRank is running during the probe")
    check(report:find('Directory.Eggs["Camp Egg 3"]', 1, true) ~= nil,
        "event entry in a lazily loaded Directory table (camp egg) is shown")
    check(report:find('Directory.Eggs["Egg 251"]', 1, true) ~= nil, "event entry matched by its DisplayName is shown")
    check(report:find('Directory.Currency["Acorns"]', 1, true) ~= nil, "event currency entry is shown")
    check(report:find('Directory.Boosts["Boost | DiamondMountainLuck1"]', 1, true) ~= nil, "event boost entry is shown")
    check(report:find("Garden", 1, true) == nil and report:find('"Cat Egg"', 1, true) == nil,
        "other events' entries are not listed")
    -- Lessons from live run 1 (2026-10-17).
    check(report:find('"DM_Walls_Load", 1', 1, true) ~= nil, "run 1: an event request after 300 fps pings is still recorded")
    check(report:find(" 6300  FireServer UnreliableRemoteEvent", 1, true) ~= nil, "every request is counted, also past 5000")
    check(report:find("    5  FireServer Breakables_PlayerDealDamage", 1, true) ~= nil, "noise remotes are counted in 6b (not shown)")
    check(report:find('[script] InvokeServer Instancing_InvokeCustomFromClient("DiamondMountain", "DM_Walls_Load", 1, {ada4=1})', 1, true) ~= nil,
        "a hub request identical to an earlier game request still gets its [script] line")
    check(not report:find("ÉloïseShown", 1, true), "the display name is redacted too (also when it starts with a non-ASCII letter)")
    check(report:find('"DM_Expedition_Start", 1', 1, true) ~= nil, "event lines are not crowded out by 420 other remotes")
    check(report:find('CustomEggs_Hatch("9af55dac", 3)', 1, true) ~= nil, "the camp-egg hatch is an event line, not crowded out either")
    check(report:find('reply CustomEggs_Hatch("9af55dac", 3) -> true', 1, true) ~= nil, "a reply line names the request it answers")
    check(report:find("more remotes not listed", 1, true) ~= nil, "6b says when its list is cut")
    local _, hp2 = report:gsub("HP=2000000", "")
    check(hp2 == 1, "an identical reply is shown once (" .. hp2 .. ")")
    check(partialSaved, "the report so far is saved while recording (a kick keeps it)")
    check(report:find("PARTIAL report", 1, true) == nil, "the final report replaces the partial one")
    check(report:find("only remote:FireServer", 1, true) ~= nil and report:find("untagged", 1, true) ~= nil,
        "section 6 explains what it cannot see and what [script] means")
    check(report:find('reply Instancing_InvokeCustomFromClient("DiamondMountain", "DM_Walls_Status") ->', 1, true) ~= nil
        and report:find("HP=1000000", 1, true) ~= nil, "run 1: the server's reply to a status request is recorded")
    check(report:find("Save.Engagement.", 1, true) == nil, "run 1: telemetry is left out of the Save diff")
    check(report:find("Save.InstanceVars.DiamondMountain.WallDamage : (new) 161386", 1, true) ~= nil,
        "run 1: the event's own Save data is in the diff")
    check(report:find("DM_YetiHealth=123", 1, true) ~= nil, "run 1: instance state is read again at the end")
    check(report:find("9af55dac", 1, true) ~= nil and report:find("EggId", 1, true) ~= nil,
        "run 1: custom egg ids (the camp egg hatch argument) are listed")
    check(report:find("Load Pets", 1, true) ~= nil and report:find("WallIndex=1", 1, true) ~= nil,
        "run 1: mountain objects and prompts are scanned after entering")
    check(report:find("FillBest/2", 1, true) ~= nil, "run 1: game function argument counts are shown")
    -- Script-hub test: requests from executor scripts are told apart from the game's.
    check(report:find('[script] InvokeServer Instancing_InvokeCustomFromClient("DiamondMountain", "DM_Yeti_Feed"', 1, true) ~= nil,
        "a request from an executor script is tagged [script]")
    check(report:find("1  [script] InvokeServer Instancing_InvokeCustomFromClient DM_Yeti_Feed", 1, true) ~= nil,
        "script requests have their own totals row")
    check(report:find('s] InvokeServer Instancing_InvokeCustomFromClient("DiamondMountain", "DM_Walls_Load"', 1, true) ~= nil,
        "the game's own requests stay untagged")
end

print(#failures == 0 and "ALL OK" or (#failures .. " FAILED"))
process.exit(#failures == 0 and 0 or 1)
