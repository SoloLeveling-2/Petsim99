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
METHODS.GetPlayerFromCharacter = function(self, char)
    for _, c in ipairs(data[self].children) do
        if data[c].props.ClassName == "Player" and data[c].props.Character == char then return c end
    end
    return nil
end
METHODS.GetPlayers = function(self)
    local list = {}
    for _, c in ipairs(data[self].children) do if data[c].props.ClassName == "Player" then list[#list + 1] = c end end
    return list
end
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
    if data[self].props.Name == "Get Stats" then return { Rank = 14, SelectedHoverboard = "Cat Board" } end -- another player's profile
    if data[self].props.Name == "Leaderboards_GetPage" then -- players from anywhere, as plain tables
        return { { UserId = 1122334455, Name = "Top_Climber_X", DisplayName = "Topper", Points = 9 } }
    end
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
-- Other players (run 4 printed 20 other players' names on 68 lines). "Acorns" collides with
-- an event name: their text must survive, only the player is hidden.
local other = new("Player", "Other_Player7", players, { UserId = 98765432, DisplayName = "Goldie" })
-- Display names are not unique and may be game words: this one is part of "Hiker Raccoon".
local wordPlayer = new("Player", "Acorns", players, { UserId = 7777777, DisplayName = "Raccoon" })
local oldAccount = new("Player", "Early_Bird", players, { UserId = 654321, DisplayName = "Early" }) -- a short UserId
data[players].props.PlayerAdded = { Connect = function(_, f)
    M.playerAdded = f
    return { Disconnect = function() M.playerAdded = nil end }
end }
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
    Rank = 3, Goals = {}, Inventory = { Pet = { a = { id = "Cat" }, hr = { id = "Hiker Raccoon", _am = 363 } }, Misc = {} },
    Events = { Mountain = { Camps = { Camp1 = { WallHP = 50 } } } },
    Instances = { DM = { State = { Deep = { Progress = 1 } } } },
    -- Run 4: event items whose names hold no keyword were missing from section 4.
    PurchasedEggs = { ["Boulder Ridge Egg"] = 1449, ["Cat Egg"] = 3 },
    ItemIndex = { Pet = { ['{"id":"Hiker Raccoon"}'] = 1, ['{"id":"Cat"}'] = 1 } },
    -- Not event data, though "upgrade" matches: run 4 spent ~40 of its 400 lines on it.
    UpgradesOwned = { Magnet = { 1, 3, 4 } },
    -- Not an event field, but a Damage potion changes wall damage (run 4).
    Potions = { Damage = { [6] = 47266.5 } },
}
-- A matching table too big for the section: the report must say what it left out.
local bigLog = {}
for i = 1, 900 do bigLog[i] = i end
SAVE.Events.Mountain.Log = bigLog
local saveMod = new("ModuleScript", "Save", client)
data[saveMod].module = { Get = function() return SAVE end }
local dirMod = new("ModuleScript", "Directory", library)
local boosts = { ["Boost | DiamondMountainLuck1"] = { DisplayName = "Luck Boost" } }
for i = 1, 80 do boosts["Boost | Garden" .. i] = { DisplayName = "Garden Boost " .. i } end -- other events
data[dirMod].module = {
    DiamondMountainCamps = { Camp1 = { Order = 1 } }, Ranks = {},
    Currency = { Acorns = { DisplayName = "Acorns" }, Coins = { DisplayName = "Coins" } },
    Boosts = boosts,
    Pets = { ["Hiker Raccoon"] = { name = "Hiker Raccoon" }, Cat = { name = "Cat" } },
    Consumables = { ["Trail Coins Boost"] = { DisplayName = "Trail Coins Boost" } },
}
-- A Directory table that is only a child module (not yet loaded into Directory).
local eggsMod = new("ModuleScript", "Eggs", dirMod)
-- Camp eggs 2-5 have no event word in their name; only their module's folder says so (run 3).
local dmEggsFolder = new("Folder", "DiamondMountain", new("Folder", "Events", eggsMod))
data[eggsMod].module = {
    ["Boulder Ridge Egg"] = { _script = new("ModuleScript", "3 | Boulder Ridge Egg", dmEggsFolder) },
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
-- Characters (Roblox's default "Climbing" sound matches the keyword) and a per-player folder.
for _, p in ipairs({ lp, other, wordPlayer }) do
    local char = new("Model", data[p].props.Name, workspace)
    new("Sound", "Climbing", new("Part", "HumanoidRootPart", char))
    data[p].props.Character = char
end
new("Trail", "Trail", new("Model", "Hoverboard", new("Model", "Other_Player7", new("Folder", "Hoverboards", things))))
local getStats = new("RemoteFunction", "Get Stats", net)
local leaderboard = new("RemoteFunction", "Leaderboards_GetPage", net)
local notice = new("RemoteEvent", "Notice_Show", net)
local mailbox = new("RemoteFunction", "Mailbox: Send", net)
local peek = new("RemoteFunction", "Egg_Peek", net) -- an event remote (always in 6b), called once, its log line lost
new("Trail", "Trail", new("Model", "Acorns", things:FindFirstChild("Hoverboards"))) -- a folder named after a player whose name is a game word
local gift = new("RemoteEvent", "Gift_Send", net)

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
            if (M.deferFail or 0) > 0 then -- only the next N calls fail
                M.deferFail -= 1
                error("Maximum re-entrancy depth (80) exceeded calling task.defer")
            end
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

-- During the recording: the game asks for other players' profiles; a player joins and is named.
local playersDone = false
luneTask.spawn(function()
    getStats:InvokeServer(other)
    local late = new("Player", "Late_Joiner99", players, { UserId = 55555555, DisplayName = "Latecomer" })
    if M.playerAdded then M.playerAdded(late) end
    getStats:InvokeServer(late)
    chat:FireServer("gg Late_Joiner99") -- usernames are unique; display names are hidden only structurally
    -- Review of v5.2 (2026-10-18): more ways a player could reach the report.
    leaderboard:InvokeServer("DiamondMountainYetiPoints", 1)
    getStats:InvokeServer(98765432) -- a profile asked for by UserId, not by Player
    notice:FireServer("Yeti down! The most damage was done by Other_Player7") -- cut at 48 characters
    notice:FireServer("x", "Other_Player7_board", "TestUser_board", "98765432_1")
    notice:FireServer("gg other_player7 and testuser") -- usernames are not case-sensitive
    mailbox:InvokeServer("Far_Away_Friend", "gift", 1) -- a player never in this server
    notice:FireServer("before join: Pre_Joiner42")
    luneTask.wait(1 / SPEED) -- the line is written before the player joins
    local pre = new("Player", "Pre_Joiner42", players, { UserId = 44444444, DisplayName = "Pre" })
    if M.playerAdded then M.playerAdded(pre) end
    gift:FireServer(654321)
    remote:FireServer(data[wordPlayer].props.Character) -- a character passed as an argument
    M.replies = M.replies or {}
    M.replies.DM_Crew_Invite = false
    custom:InvokeServer("DiamondMountain", "DM_Crew_Invite", other)
    -- Only the request's log defer fails; the reply's succeeds (the thread is fresh again).
    M.deferFail = 1
    peek:InvokeServer(1)
    M.deferFail = 0
    gift:FireServer(1234567, 98765432) -- a number that contains my UserId; another player's UserId
    playersDone = true
end)
while not playersDone do luneTask.wait(0.001) end
-- The GAME sends requests with an Instance argument while the recorder runs.
local mark0 = #M.received
remote:FireServer(pet, 5)
local first = M.received[mark0 + 1]
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
    -- Run 4: the live reply shape. Section 6 keeps 2 replies per request; 6c keeps them all.
    local stacks = { { id = "Climber Bear", count = 100, power = 330 }, { id = "Expedition Wolf", count = 57, power = 720 } }
    for i = 1, 5 do
        M.replies.DM_Walls_Status = { at = 1792291836.25 + i, total = 2283257371 + i, slots = 17, stackMax = 100, cap = 21600,
            walls = { [3] = { n = 3, open = true, broken = false, max = 4275916666.6666665 - i, dealt = 1392911792.5 + i,
                rate = 2318361.6927431747, stacks = stacks } } }
        local st = custom:InvokeServer("DiamondMountain", "DM_Walls_Status")
        if i == 5 and type(st) == "table" then -- the caller changes the reply it got back
            st.at = nil
            table.clear(st.walls)
        end
    end
    M.replies.DM_Walls_Status = { at = 1792291900.5, walls = { [3] = { open = true, max = 1, dealt = 0, rate = 1,
        stacks = { { id = "Climber Bear", count = 100, power = 330 } } } } }
    custom:InvokeServer("DiamondMountain", "DM_Walls_Status")
    for i = 1, 40 do -- the stacks change on every reply
        M.replies.DM_Walls_Status = { at = 1792292000 + i, walls = { [4] = { open = true, max = 2, dealt = 0, rate = 1,
            stacks = { { id = "Climber Goat", count = 100 + i, power = 480 } } } } }
        custom:InvokeServer("DiamondMountain", "DM_Walls_Status")
    end
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
data[dmState].attrs.DM_HypeTop = '[{"name":"TopFarmer","coins":81234567},{"name":"Dolphin","coins":5}]'
data[dmState].attrs.DM_HypeMine = '[{"name":"TestUser","coins":1},{"name":"Late_Joiner99","coins":2}]'
data[dmState].attrs.DM_TrailLoot = '[{"name":"Trail Coins Boost","n":3}]'
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
check(not report:find("%f[%d]123456%f[%D]") and not report:find("TestUser", 1, true), "report is redacted")
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

-- Run 4 (2026-10-18): other players were printed by name (both probes).
for _, secret in ipairs({ "Other_Player7", "Goldie", "98765432", "Late_Joiner99", "Latecomer", "55555555", "7777777" }) do
    check(not report:find(secret, 1, true), "another player's name or id is not in the report (" .. secret:sub(1, 2) .. "...)")
end
check(report:find("Get Stats(Instance<Player><p", 1, true) ~= nil, "a request about another player names them by alias")
-- Review of v5.2: cut names, joined names, case, typed recipients, late joiners, short ids, paths.
for _, secret in ipairs({ "Other_Pla", "other_player7", "testuser", "TestUser", "Far_Away_Friend", "Pre_Joiner42",
    "654321", "Workspace.Acorns" }) do
    check(not report:find(secret, 1, true), "review: no player name, id or path in the report (" .. secret:sub(1, 3) .. "...)")
end
check(report:find("1234567", 1, true) ~= nil and report:find("<me>7", 1, true) == nil,
    "a number that contains my UserId is not damaged")
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
    check(report:find('Directory.Eggs["Boulder Ridge Egg"]', 1, true) ~= nil,
        "run 3: an event egg named without an event word is found by its module's folder")
    check(report:find('Directory.Currency["Acorns"]', 1, true) ~= nil, "event currency entry is shown")
    -- Run 4 (2026-10-18): section 4 used keywords only and stopped silently at 400 lines.
    check(report:find("Save.PurchasedEggs.Boulder Ridge Egg : 1449", 1, true) ~= nil,
        "run 4: a Save field named after an event egg (no keyword) is shown")
    check(report:find('Inventory.Pet item: {id="Hiker Raccoon"', 1, true) ~= nil
        or report:find('Inventory.Pet item: {_am=363, id="Hiker Raccoon"', 1, true) ~= nil,
        "run 4: an inventory stack of an event pet (no keyword) is shown")
    check(report:find('Save.ItemIndex.Pet.{"id":"Hiker Raccoon"}', 1, true) ~= nil,
        "run 4: an item-index key naming an event pet is shown")
    check(report:find("Cat Egg : 3", 1, true) == nil and report:find('{"id":"Cat"}', 1, true) == nil,
        "run 4: other eggs and pets stay out of section 4")
    check(report:find("Save.UpgradesOwned", 1, true) == nil, "run 4: the game's global upgrades are not listed as event data")
    check(report:find("Save fields not shown", 1, true) ~= nil, "run 4: section 4 says when it stops early")
    check(report:find("Save.Potions.Damage.6 : 47266.5", 1, true) ~= nil, "run 4: active potions are shown in section 4")
    local series = report:match("==== 6c%. Wall status over time.-\n(.-)\n\n") or ""
    local _, rows = series:gsub("w3 open ", "")
    check(rows == 6, "run 4: 6c keeps every wall-status reply, not 2 (" .. rows .. ")")
    check(series:find("at=1792291837.25 total=2283257372 slots=17 stackMax=100 cap=21600 | w3 open 1392911793.5/4275916665.6666665 rate 2318361.6927431747", 1, true) ~= nil,
        "run 4: a 6c row keeps every digit of at, dealt, max and rate")
    local _, stackLines = series:gsub("wall 3 stacks: ", "")
    check(stackLines == 2, "run 4: a wall's stacks are printed when they change, not every reply (" .. stackLines .. ")")
    check(series:find('id="Expedition Wolf"', 1, true) ~= nil and series:find("count=57", 1, true) ~= nil,
        "run 4: the stacks are printed in full (the reply line shows {...})")
    check(series:find("at=1792291841.25 ", 1, true) ~= nil and series:find("w3 open 1392911797.5/", 1, true) ~= nil,
        "run 4 review: 6c shows the reply as the server sent it, even if the caller changes it afterwards")
    local partial6c = false
    for i = 1, #(M.writes or {}) - 1 do
        if M.writes[i]:find("==== 6c so far ====", 1, true) and M.writes[i]:find("w3 open", 1, true) then partial6c = true end
    end
    check(partial6c, "run 4 review: the partial saves keep the wall-status rows")
    check(report:find("Breakables_PlayerDealDamage  (first +", 1, true) ~= nil,
        "run 4: 6b says when a remote was first seen (noisy remotes get no line in section 6)")
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
    -- Run 4 (2026-10-18): other players were printed by name.
    for _, secret in ipairs({ "Other_Player7", "Goldie", "98765432", "Late_Joiner99", "Latecomer", "55555555", "7777777", "TopFarmer", "Dolphin" }) do
        check(not report:find(secret, 1, true), "run 4: another player's name or id is not in the report (" .. secret:sub(1, 2) .. "...)")
    end
    check(report:find("Get Stats(Instance<Player><p", 1, true) ~= nil, "run 4: a request about another player names them by alias")
    check(report:find("Rank=14", 1, true) == nil and report:find("another player's data", 1, true) ~= nil,
        "run 4: the reply with another player's profile is not printed")
    check(report:find("player characters", 1, true) ~= nil and report:find("Climbing", 1, true) == nil,
        "run 4: player characters are counted, not listed")
    check(report:find("Hoverboards.<p", 1, true) ~= nil, "run 4: a folder named after a player shows the alias")
    check(report:find('\\"name\\":\\"<player>\\"', 1, true) ~= nil and report:find("81234567", 1, true) ~= nil,
        "run 4: names in a JSON attribute are hidden, the numbers kept")
    check(report:find("1234567", 1, true) ~= nil and report:find("<me>7", 1, true) == nil,
        "run 4: a number that contains my UserId is not damaged")
    -- Review of v5.2.
    for _, secret in ipairs({ "Top_Climber_X", "1122334455", "Topper", "Other_Pla", "other_player7", "testuser",
        "TestUser", "Far_Away_Friend", "Pre_Joiner42", "654321", "Workspace.Acorns", "Hoverboards.Acorns" }) do
        check(not report:find(secret, 1, true), "review: no other player's name, id or path in the report (" .. secret:sub(1, 3) .. "...)")
    end
    check(report:find("Points=9", 1, true) ~= nil, "review: a leaderboard reply keeps its numbers")
    check(report:find('\\"name\\":\\"<me>\\"', 1, true) ~= nil and report:find('\\"name\\":\\"<p', 1, true) ~= nil,
        "review: a JSON list names me as <me> and a known player by alias")
    check(report:find('Trail Coins Boost\\",\\"n\\":3', 1, true) ~= nil, "review: game items in a JSON attribute keep their names")
    check(report:find('"DM_Crew_Invite", Instance<Player><p1>) -> false', 1, true) ~= nil,
        "review: a plain reply to a request about another player is shown")
    check(report:find("more stack changes not listed", 1, true) ~= nil, "review: 6c says when stack changes were left out")
    check(report:find("not logged)", 1, true) == nil, "review: a reply whose request was not logged makes no 6b row of its own")
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
