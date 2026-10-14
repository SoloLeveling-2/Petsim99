--!nocheck
-- Loads the whole VY AutoRank source into a fake Potassium environment.
-- Each H.newVM() call models one Roblox client VM (its own getgenv table);
-- a world teleport kills the VM without calling Stop, like the real client.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local luneTask = require("@lune/task")
local R = require("./roblox_mock")
local W = require("./vy_world")

local H = {failures = {}, printed = {}}

function H.check(cond, msg)
    if cond then print("ok   " .. msg) else table.insert(H.failures, msg) print("FAIL " .. msg) end
    return cond
end

function H.wait(virtualSeconds) luneTask.wait(virtualSeconds / R.SPEED) end

-- Wait until predicate() is true or the virtual timeout passes.
function H.waitFor(predicate, timeout, step)
    local deadline = R.vclock() + (timeout or 30)
    while R.vclock() < deadline do
        if predicate() then return true end
        H.wait(step or 0.25)
    end
    return predicate()
end

function H.loadSource(path)
    H.source = fs.readFile(path)
    return H.source
end

local function makeEnv(genv)
    local SPEED = R.SPEED
    local fakeTask = {
        spawn = function(f, ...) return luneTask.spawn(f, ...) end,
        defer = function(f, ...) return luneTask.defer(f, ...) end,
        delay = function(t, f, ...) return luneTask.delay((t or 0) / SPEED, f, ...) end,
        wait = function(t) t = t or 0.03 luneTask.wait(t / SPEED) return t end,
        cancel = function(th) return luneTask.cancel(th) end,
    }
    local fakeOs = table.clone(os)
    fakeOs.clock = R.vclock
    -- Wall clock on the same virtual timeline (persistence ages, travel throttles).
    fakeOs.time = function(t)
        if t ~= nil then return os.time(t) end
        return 1800000000 + math.floor(R.vclock())
    end
    local printed = H.printed
    local env = {
        Vector3 = R.Vector3, Vector2 = R.Vector2, CFrame = R.CFrame, Color3 = R.Color3,
        UDim = R.UDim, UDim2 = R.UDim2, Enum = R.Enum, Instance = R.Instance,
        typeof = R.typeof, task = fakeTask, os = fakeOs,
        warn = function(...) table.insert(printed, "WARN " .. table.concat({...}, " ")) end,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
            table.insert(printed, table.concat(parts, " "))
        end,
        getgenv = function() return genv end,
        setthreadidentity = function() end,
        getthreadidentity = function() return 8 end,
        hookfunction = function(target) return target end,
        getsenv = function() return {} end,
        getconnections = function() return {} end,
        setreadonly = function() end,
        gethui = function() return W.hui end,
        setclipboard = function(text) W.clipboard = text end,
        isfile = function(p) return W.files[p] ~= nil end,
        readfile = function(p)
            if W.files[p] == nil then error("file not found: " .. tostring(p)) end
            return W.files[p]
        end,
        writefile = function(p, c) W.files[p] = c end,
        require = function(mod)
            if R.isInstance(mod) and rawget(mod, "__module") ~= nil then return rawget(mod, "__module") end
            error("require on a non-module: " .. tostring(mod), 2)
        end,
    }
    env.game = W.game
    env.workspace = R.services.Workspace
    env.Workspace = R.services.Workspace
    return env
end

-- Runs the source in the VM that owns genv (same-VM re-execution when reused).
function H.runIn(genv, label)
    local env = makeEnv(genv)
    local ok, fn = pcall(luau.load, H.source, {debugName = "VY_AutoRank", environment = env})
    H.check(ok, (label or "vm") .. ": source compiles in Luau (" .. tostring(ok or fn) .. ")")
    if not ok then return genv end
    local ran, err = pcall(fn)
    H.check(ran, (label or "vm") .. ": source runs to the end (" .. tostring(err) .. ")")
    return genv
end

-- Starts one new client VM running the source; returns its getgenv table.
function H.newVM(label) return H.runIn({}, label) end

-- Simulates a place teleport: the old VM stops existing (no Stop/persist).
function H.killVM(genv)
    local handle = genv.VyAutoRank
    if handle and handle.State then handle.State.alive = false end
    for _, d in ipairs(W.hui:GetChildren()) do d:Destroy() end
end

function H.handle(genv) return genv.VyAutoRank end

function H.findButton(name)
    for _, d in ipairs(W.hui:GetDescendants()) do
        if d.Name == name then return d end
    end
    return nil
end

local ERROR_PATTERNS = {"attempt to", "invalid argument", "stack overflow", "Color3 expected",
    "is not a valid member", "require on a non-module", "loop error", "fatal error", "handler for goal type"}
function H.scanErrors(label)
    local bad = {}
    for _, line in ipairs(H.printed) do
        for _, p in ipairs(ERROR_PATTERNS) do
            if string.find(line, p, 1, true) then table.insert(bad, line) break end
        end
    end
    for _, e in ipairs(R.errors) do table.insert(bad, "signal: " .. tostring(e)) end
    for i = 1, math.min(#bad, 8) do print("   " .. bad[i]) end
    H.check(#bad == 0, label .. ": no Lua runtime errors in console (" .. #bad .. ")")
end

function H.console(pattern)
    local hits = {}
    for _, line in ipairs(H.printed) do
        if string.find(line, pattern, 1, true) then table.insert(hits, line) end
    end
    return hits
end

function H.finish()
    print(string.format("\n%d checks failed; %d console lines", #H.failures, #H.printed))
    if #H.failures > 0 then
        for i = math.max(1, #H.printed - 30), #H.printed do print("   console: " .. tostring(H.printed[i])) end
    end
    return #H.failures == 0
end

return H
