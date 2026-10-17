--!nocheck
-- Offline checks for the read-only probes in VY/tools (mocked runtime, not live PS99).
--   lune run probe_recorder.luau <probe.luau> <event|general>
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
local lp = new("Player", "TestUser", players, { UserId = 123456 })
data[players].props.LocalPlayer = lp
local RS = new("ReplicatedStorage", "ReplicatedStorage", game)
local workspace = new("Workspace", "Workspace", game, { StreamingEnabled = true })
new("HttpService", "HttpService", game)
local net = new("Folder", "Network", RS)
local remote = new("RemoteEvent", "DiamondMountain_SendPets", net)
local remoteFn = new("RemoteFunction", "Expedition_Claim", net)
new("RemoteEvent", "Breakables_PlayerDealDamage", net)
local library = new("Folder", "Library", RS)
local client = new("Folder", "Client", library)
local SAVE = {
    Rank = 3, Goals = {}, Inventory = { Pet = { a = { id = "Cat" } }, Misc = {} },
    Events = { Mountain = { Camps = { Camp1 = { WallHP = 50 } } } },
    Instances = { DM = { State = { Deep = { Progress = 1 } } } },
}
local saveMod = new("ModuleScript", "Save", client)
data[saveMod].module = { Get = function() return SAVE end }
local dirMod = new("ModuleScript", "Directory", library)
data[dirMod].module = { DiamondMountainCamps = { Camp1 = { Order = 1 } }, Ranks = {} }
local things = new("Folder", "__THINGS", workspace)
local ic = new("Folder", "__INSTANCE_CONTAINER", things)
local active = new("Folder", "Active", ic)
new("Model", "DiamondMountain", active)
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
        defer = function(f, ...) return luneTask.defer(f, ...) end,
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
    setnamecallmethod = function(m) M.atom = m end,
    hookmetamethod = function(_, name, fn)
        assert(name == "__namecall", "only __namecall is modelled")
        local prev = NC
        NC = fn
        return prev
    end,
    writefile = function(p, c) M.files[p] = c end,
    setclipboard = function() end,
    getgenv = function() return {} end,
}

local source = fs.readFile(PROBE)
-- Shorten the recording window (the general probe ships with recording OFF).
source = source:gsub("local RECORD_SECONDS = %d+", "local RECORD_SECONDS = 30", 1)
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

luneTask.wait(45 / SPEED) -- recording window (30 virtual s) is over
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
end

print(#failures == 0 and "ALL OK" or (#failures .. " FAILED"))
process.exit(#failures == 0 and 0 or 1)
