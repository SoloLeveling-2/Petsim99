--!nocheck
-- Thread identity around game-module calls (mocked runtime, not live PS99).
-- Usage: lune run VY/tests/lune/identity.luau <path to VY_AutoRank .luau> <executor7|nested>
--   executor7: the whole file on an executor whose threads run at identity 7. Every
--              game-module call must run at 2 and VY's own work (its GUI) must stay at 7,
--              never raised to 8.
--   nested:    the delivered gcall() itself, cut from the file: a gcall made while
--              another gcall is running must leave the outer call at identity 2.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local R = require("./roblox_mock")
local W = require("./vy_world")
local H = require("./harness")

local path, mode = process.args[1] or "VY/source/VY_AutoRank-v1.1.7.luau", process.args[2] or "executor7"

if mode == "nested" then
    local source = fs.readFile(path):gsub("\r\n", "\n")
    local first = source:find("local state -- captured by gcall", 1, true)
    local last = source:find("-- First result of a successful gcall", 1, true)
    if not H.check(first ~= nil and last ~= nil and last > first, "gcall() found in the source") then
        process.exit(H.finish() and 0 or 1)
    end
    local env = {
        setthreadidentity = function(n) H.setIdentity(n) end,
        getthreadidentity = function() return H.currentIdentity() end,
    }
    local gcall = luau.load(source:sub(first, last - 1) .. "\nreturn gcall", {debugName = "gcall", environment = env})()
    H.identity.base = 7

    local seen = {}
    local function inner() seen.inner = H.currentIdentity() return "inner done" end
    local function outer()
        seen.before = H.currentIdentity()
        local ok, r = gcall(inner)
        seen.innerOk, seen.innerResult = ok, r
        seen.after = H.currentIdentity()
        local okErr = gcall(function() error("game module failed") end)
        seen.errOk, seen.afterError = okErr, H.currentIdentity()
        return "outer done"
    end
    local ok, r = gcall(outer)
    H.check(ok and r == "outer done", "outer gcall returns its result")
    H.check(seen.before == 2 and seen.inner == 2, "both calls run their function at identity 2")
    H.check(seen.innerOk and seen.innerResult == "inner done", "inner gcall returns its result")
    H.check(seen.after == 2, "after an inner gcall the outer call is still at identity 2 (got " .. tostring(seen.after) .. ")")
    H.check(seen.errOk == false and seen.afterError == 2,
        "after an inner gcall that errors the outer call is still at identity 2 (got " .. tostring(seen.afterError) .. ")")
    H.check(H.currentIdentity() == 7, "after the outer gcall the thread is back at the executor's 7 (got " .. H.currentIdentity() .. ")")
    process.exit(H.finish() and 0 or 1)
end

-- executor7 ------------------------------------------------------------------------------
H.loadSource(path)
W.build({
    rank = 12, keys = 20,
    goals = {
        [1] = {UID = "g1", Type = 21, Amount = 1700, Progress = 0, Stars = 1},
        [2] = {UID = "g2", Type = 14, Amount = 40, Progress = 0, Stars = 2},
        [3] = {UID = "g3", Type = 9, Amount = 900, Progress = 0, Stars = 3},
        [4] = {UID = "g4", Type = 42, Amount = 3, Progress = 0, Stars = 4},
    },
})
H.identity.base = 7

-- Record the identity of every call into a game module.
local gameCalls, badGame = 0, {}
local function probe(name, f)
    return function(...)
        gameCalls += 1
        local id = H.currentIdentity()
        if id ~= 2 then badGame[name .. "@" .. id] = (badGame[name .. "@" .. id] or 0) + 1 end
        return f(...)
    end
end
local library = W.rs:FindFirstChild("Library")
for _, m in ipairs(library:GetDescendants()) do
    local value = rawget(m, "__module")
    if type(value) == "function" then
        rawset(m, "__module", probe(m.Name, value))
    elseif type(value) == "table" then
        for k, f in pairs(value) do
            if type(f) == "function" then value[k] = probe(m.Name .. "." .. tostring(k), f) end
        end
    end
end

-- Record the identity of every GUI property write.
local GUI = {ScreenGui = true, Frame = true, TextLabel = true, TextButton = true, TextBox = true,
    ImageLabel = true, ImageButton = true, ScrollingFrame = true}
local guiWrites, guiById = 0, {}
R.onWrite = function(obj)
    local cls = rawget(obj, "ClassName")
    if GUI[cls] or string.sub(cls, 1, 2) == "UI" then
        guiWrites += 1
        local id = H.currentIdentity()
        guiById[id] = (guiById[id] or 0) + 1
    end
end

local genv = H.newVM("executor at identity 7")
H.wait(20)
H.check(W.count("Breakables_JoinPetBulk") > 0, "VY farms (sanity)")
H.check(gameCalls > 0, "game modules were called (" .. gameCalls .. ")")
local bad = {}
for k, n in pairs(badGame) do bad[#bad + 1] = k .. " x" .. n end
table.sort(bad)
H.check(#bad == 0, "every game-module call ran at identity 2" .. (#bad > 0 and (" - not: " .. table.concat(bad, ", ")) or ""))
local ids = {}
for id, n in pairs(guiById) do ids[#ids + 1] = "identity " .. id .. " x" .. n end
table.sort(ids)
H.check(guiWrites > 0 and guiById[7] == guiWrites,
    "every GUI write ran at the executor's identity 7 (" .. table.concat(ids, ", ") .. ")")
H.handle(genv).Stop()
H.scanErrors("identity")
process.exit(H.finish() and 0 or 1)
