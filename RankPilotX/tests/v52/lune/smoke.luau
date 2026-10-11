--!nocheck
-- Full-bundle smoke test in the real Luau VM (Lune 0.10).
-- Usage: lune run tests/v52/lune/smoke.luau <path to RankPilot_X_v5_2.lua>
-- Proves: the whole file loads, builds its 16-page UI in PlayerGui, runs every
-- worker against fake PS99 modules without runtime errors, survives toggles,
-- search, pause/start, re-execution and Stop. Does NOT prove live compatibility.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local luneTask = require("@lune/task")
local process = require("@lune/process")
local R = require("./roblox_mock")
local W = require("./ps99_world")

local bundlePath = process.args[1] or "dist/RankPilot_X_v5_2.lua"
local source = fs.readFile(bundlePath)
local failures = {}
local function check(cond, msg)
    if cond then print("ok   " .. msg) else table.insert(failures, msg) print("FAIL " .. msg) end
end

local SPEED = R.SPEED
local printed = {}
local genv = {}
local fakeTask = {
    spawn = function(f, ...) return luneTask.spawn(f, ...) end,
    defer = function(f, ...) return luneTask.defer(f, ...) end,
    delay = function(t, f, ...) return luneTask.delay((t or 0) / SPEED, f, ...) end,
    wait = function(t) t = t or 0.03 luneTask.wait(t / SPEED) return t end,
    cancel = function(th) return luneTask.cancel(th) end,
}
local fakeOs = table.clone(os)
fakeOs.clock = R.vclock
local env = {
    Vector3 = R.Vector3, Vector2 = R.Vector2, CFrame = R.CFrame, Color3 = R.Color3,
    UDim = R.UDim, UDim2 = R.UDim2, Enum = R.Enum, Instance = R.Instance,
    typeof = R.typeof, task = fakeTask, os = fakeOs,
    tick = function() return R.vclock() end, time = function() return R.vclock() end,
    wait = fakeTask.wait,
    warn = function(...) table.insert(printed, "WARN " .. table.concat({...}, " ")) end,
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(printed, table.concat(parts, " "))
    end,
    getgenv = function() return genv end,
    setclipboard = function(text) W.clipboard = text end,
    isfile = function(p) return W.files[p] ~= nil end,
    readfile = function(p) return W.files[p] end,
    writefile = function(p, c) W.files[p] = c end,
    hookfunction = function(target) return target end,
    getsenv = function() return {} end,
    setfpscap = function(n) W.fps = n end,
    getfpscap = function() return 60 end,
    unpack = table.unpack,
    require = function(mod)
        if R.isInstance(mod) and rawget(mod, "__module") ~= nil then return rawget(mod, "__module") end
        error("require on a non-module: " .. tostring(mod), 2)
    end,
}
local game = W.build(env)
env.game = game
env.workspace = R.services.Workspace
env.Workspace = R.services.Workspace

local function execute(label)
    local ok, fn = pcall(luau.load, source, {debugName = "RankPilot_X_v5_2", environment = env})
    check(ok, label .. ": bundle compiles in Luau (" .. tostring(ok or fn) .. ")")
    if not ok then return false end
    local ran, err = pcall(fn)
    check(ran, label .. ": bundle runs to the end (" .. tostring(err) .. ")")
    return ran
end
local function wait(virtualSeconds) luneTask.wait(virtualSeconds / SPEED) end
local function scanErrors(st, label)
    local bad = {}
    local patterns = {"attempt to", "invalid argument", "stack overflow", "Color3 expected", "is not a valid member",
        "has no key", "require on a non-module"}
    local function scan(text, where)
        text = tostring(text)
        for _, p in ipairs(patterns) do
            if string.find(text, p, 1, true) then table.insert(bad, where .. ": " .. text) break end
        end
    end
    for _, line in ipairs(st.logs or {}) do scan(line, "log") end
    -- Every log() line is also printed; scan the whole console, not just the
    -- 55 most recent log entries.
    for _, line in ipairs(printed) do scan(line, "console") end
    for feature, record in pairs(st.failures or {}) do
        scan(tostring(record.lastError or record.error or record.last or ""), "failure " .. tostring(feature))
    end
    for _, e in ipairs(R.errors) do scan(e, "signal") end
    for _, line in ipairs(bad) do print("   " .. line) end
    check(#bad == 0, label .. ": no Lua runtime errors in logs/failures (" .. #bad .. ")")
end
local function descendantsNamed(root, suffix)
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if type(d.Name) == "string" and string.sub(d.Name, -#suffix) == suffix then table.insert(out, d) end
    end
    return out
end

-- 1) First execution: load, UI, paused state.
execute("first run")
local api = genv.RankPilot
check(type(api) == "table" and type(api.Version) == "string" and string.sub(api.Version, 1, 3) == "5.2",
    "exported API with v5.2 version: " .. tostring(api and api.Version))
local st = api and api.Status
check(st and st.running == false and api.Config.Enabled == false, "starts paused")
local gui = W.playerGui:FindFirstChild("RankPilotUI")
check(gui ~= nil, "UI parented to PlayerGui")
check(#descendantsNamed(gui, "Page") == 16, "16 pages built (" .. #descendantsNamed(gui, "Page") .. ")")
local toggles = descendantsNamed(gui, "")
local toggleRows = {}
for _, d in ipairs(gui:GetDescendants()) do
    if type(d.Name) == "string" and string.sub(d.Name, 1, 7) == "Toggle_" then table.insert(toggleRows, d) end
end
check(#toggleRows >= 60, "real toggle rows present (" .. #toggleRows .. ")")
local chips = 0
for _, d in ipairs(gui:GetDescendants()) do if d.Name == "Chip" then chips += 1 end end
check(chips >= 40, "status chips on toggles (" .. chips .. ")")
check(api.Modules and #api.Modules.list >= 6, "modules registered (" .. tostring(api.Modules and #api.Modules.list) .. ")")

-- 2) Start and let every worker run ~2 virtual minutes.
api.Start()
check(st.running == true, "START runs the controller")
wait(120)
check(st.running == true, "still running after 120 virtual seconds")
local remoteNames = {}
for _, call in ipairs(W.calls) do remoteNames[call.name] = (remoteNames[call.name] or 0) + 1 end
local summary = {}
for name, n in pairs(remoteNames) do table.insert(summary, name .. "=" .. n) end
table.sort(summary)
print("   remote calls: " .. table.concat(summary, ", "))
check((remoteNames["Breakables_PlayerDealDamage"] or 0) + (remoteNames["Breakables_JoinPetBulk"] or 0) > 0,
    "farm lane sends breakable requests")
scanErrors(st, "after run")

-- 3) Exercise every toggle twice (ON/OFF round trip) and the search box.
for _, row in ipairs(toggleRows) do
    row.MouseButton1Click:Fire()
    row.MouseButton1Click:Fire()
end
wait(10)
scanErrors(st, "after toggling every control")
local search = gui:FindFirstChild("Search", true)
check(search ~= nil, "search box exists")
if search then
    search.Text = "lootbag"
    local visible, hidden = 0, 0
    for _, row in ipairs(toggleRows) do if row.Visible == false then hidden += 1 else visible += 1 end end
    check(visible > 0 and hidden > 0, "search filters rows (" .. visible .. " visible, " .. hidden .. " hidden)")
    search.Text = ""
end
local copied = api.GetReport()
check(type(copied) == "string" and string.find(copied, "MODULE rank", 1, true) ~= nil, "report includes module lines")

-- 4) Pause / resume.
api.Pause()
check(st.running == false, "PAUSE stops automation")
wait(5)
api.Start()
wait(20)
scanErrors(st, "after pause/resume")

-- 5) Re-execution: the old instance must stop, one GUI must remain.
local oldState = st
execute("second run")
wait(10)
check(oldState.shutdown == true, "re-execution stopped the previous instance")
local guis = 0
for _, child in ipairs(W.playerGui:GetChildren()) do if child.Name == "RankPilotUI" then guis += 1 end end
check(guis == 1, "exactly one RankPilotUI after re-execution (" .. guis .. ")")
local api2 = genv.RankPilot
check(api2 ~= api and api2.Status.running == false, "new instance starts paused")

-- 6) Stop: everything restored.
api2.Start()
wait(15)
api2.Config.WalkSpeedOverride = 50
wait(5)
api2.Stop()
wait(5)
check(genv.RankPilot == nil, "Stop removes the global API")
check(W.playerGui:FindFirstChild("RankPilotUI") == nil, "Stop destroys the GUI")
check(R.render3d ~= false, "3D rendering restored")
check(W.humanoid.WalkSpeed == 16, "walk speed restored (" .. tostring(W.humanoid.WalkSpeed) .. ")")
scanErrors(api2.Status, "after stop")
local callsAfterStop = #W.calls
wait(20)
check(#W.calls == callsAfterStop, "no requests after Stop (" .. (#W.calls - callsAfterStop) .. " extra)")

local errorLines = {}
for _, line in ipairs(printed) do
    if string.find(line, "[ERROR]", 1, true) or string.find(line, "[SAFEGUARD]", 1, true) then errorLines[line] = (errorLines[line] or 0) + 1 end
end
for line, n in pairs(errorLines) do print(string.format("   console x%d: %s", n, line)) end
print(string.format("\n%d checks failed; %d instances created; %d prints", #failures, R.created, #printed))
if #failures > 0 then
    for i = math.max(1, #printed - 25), #printed do print("   console: " .. tostring(printed[i])) end
    process.exit(1)
end
process.exit(0)
