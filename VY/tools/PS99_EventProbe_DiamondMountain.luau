-- =====================================================================================
--  PS99 Event Probe - Diamond Mountain (update 98, 2026-10-17)        READ-ONLY
--
--  Finds the event's real names so an event script can be built on evidence:
--    0. the executor's name, thread identity and which executor functions exist;
--    1. remotes, client modules (+ functions), Directory tables and Save fields whose
--       names match the event keywords, plus this event's entries inside tables every
--       event shares (camp eggs, pets, Acorns/TrailCoins, boosts...);
--    2. matching objects in the world (camps, walls, Yeti, trails, chests, merchant...);
--    3. RECORDER: for RECORD_SECONDS it notes every request the GAME sends while YOU
--       do the actions by hand (send pets to a wall, feed/fight the Yeti, start/claim an
--       expedition, buy from the merchant, buy an upgrade, use a boost, teleport to a camp).
--    4. SAVE DIFF: every Save value that changed while you did those actions, whatever
--       its name (finds event fields stored under unexpected parents).
--  It sends nothing itself and never blocks or changes a request. After recording, its
--  hook stays as a pass-through until you leave the server (re-hooking could drop hooks
--  other scripts added meanwhile). Your UserId/name become <me>. Report:
--  PS99_EventProbe_<date>.txt. Stop VY AutoRank first (GUI X). Run it once at base camp
--  and once at the summit: far parts of the mountain may not be loaded where you stand.
-- =====================================================================================
local RECORD_SECONDS = 300   -- time you have to do the actions by hand (0 = no recording)
local KEYWORDS = { "mountain", "yeti", "camp", "rubble", "wall", "trail", "expedition", "artifact",
    "acorn", "merchant", "summit", "season", "boost", "upgrade", "climb", "pedestal", "marmot", "equinox" }
-- Stricter words for this event's own entries inside tables shared by all events
-- (Eggs, Pets, Currency, Boosts...): "boost" or "merchant" there would list every event.
local ENTRY_KEYWORDS = { "mountain", "yeti", "summit", "acorn", "trail", "expedition", "rubble", "camp",
    "marmot", "markhor", "equinox", "hiker", "climber", "abominable" }

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local out = {}
local me, myName = tostring(player and player.UserId or "?"), tostring(player and player.Name or "?")
local started = os.clock()

local function esc(x) return (x:gsub("%p", "%%%0")) end
local function redact(s)
    s = tostring(s)
    if #me > 2 then s = s:gsub(esc(me), "<me>") end
    if #myName > 2 then s = s:gsub(esc(myName), "<me>") end
    return s
end
local function line(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    out[#out + 1] = redact(table.concat(parts, " "))
end
local function section(t) line("") line("==== " .. t .. " ====") end
local function matches(name)
    local l = string.lower(tostring(name))
    for _, k in ipairs(KEYWORDS) do if l:find(k, 1, true) then return true end end
    return false
end
-- A Directory entry of this event: by its key or by its display name.
local function entryMatches(key, value)
    local function has(s)
        if type(s) ~= "string" then return false end
        s = string.lower(s)
        for _, k in ipairs(ENTRY_KEYWORDS) do if s:find(k, 1, true) then return true end end
        return false
    end
    if has(tostring(key)) then return true end
    if type(value) ~= "table" then return false end
    local ok, name = pcall(function() return value.DisplayName or value.name or value.Name end)
    return ok and has(name)
end
-- Game modules need identity 2; afterwards restore whatever identity this thread had.
local function asGame(fn, ...)
    local canSet = type(setthreadidentity) == "function"
    local prior = 8
    if type(getthreadidentity) == "function" then
        local ok, id = pcall(getthreadidentity)
        if ok and type(id) == "number" then prior = id end
    end
    if canSet then pcall(setthreadidentity, 2) end
    local r = table.pack(pcall(fn, ...))
    if canSet then pcall(setthreadidentity, prior) end
    return table.unpack(r, 1, r.n)
end
local function short(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then return string.format("%q", #v > 48 and v:sub(1, 48) .. "..." or v) end
    if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    if t == "Instance" then return "Instance<" .. v.ClassName .. ">" .. v:GetFullName() end
    if t == "Vector3" or t == "CFrame" then return t end
    if t == "table" then
        if depth >= 1 then return "{...}" end
        local parts, n = {}, 0
        for k, x in pairs(v) do
            n += 1
            if n <= 6 then parts[#parts + 1] = tostring(k) .. "=" .. short(x, depth + 1) end
        end
        return "{" .. table.concat(parts, ", ") .. (n > 6 and (", +" .. (n - 6)) or "") .. "}"
    end
    return t
end

-- Prints a matched table's contents several levels deep (bounded).
local function dump(t, path, depth, budget)
    for k, v in pairs(t) do
        if budget.n >= 400 then return end
        local p = path .. "." .. tostring(k)
        if type(v) == "table" and depth < 4 then
            dump(v, p, depth + 1, budget)
        else
            budget.n += 1
            line("  " .. p .. " : " .. short(v))
        end
    end
end

-- Flattens Save into path -> printable value, for the before/after diff.
local function flatten(t, path, depth, acc)
    for k, v in pairs(t) do
        if acc.n >= 60000 then return acc end
        local p = path .. "." .. tostring(k)
        if type(v) == "table" then
            if depth < 7 then flatten(v, p, depth + 1, acc) end
        else
            acc.n += 1
            acc.map[p] = short(v)
        end
    end
    return acc
end

line("PS99 Event Probe (Diamond Mountain) | " .. os.date("!%Y-%m-%d %H:%M:%S UTC") .. " | PlaceId " .. game.PlaceId)

-- 0. Executor ---------------------------------------------------------------------------
section("0. Executor (what an event script can use here)")
local okExec, execName, execVersion = false, nil, nil
if type(identifyexecutor) == "function" then okExec, execName, execVersion = pcall(identifyexecutor) end
line("  executor: " .. (okExec and (tostring(execName) .. (execVersion ~= nil and (" " .. tostring(execVersion)) or "")) or "unknown"))
local okIdentity, identity = false, nil
if type(getthreadidentity) == "function" then okIdentity, identity = pcall(getthreadidentity) end
line("  thread identity: " .. (okIdentity and tostring(identity) or "unknown"))
local CAPS = {
    { "checkcaller", checkcaller }, { "fireclickdetector", fireclickdetector },
    { "fireproximityprompt", fireproximityprompt }, { "firesignal", firesignal },
    { "firetouchinterest", firetouchinterest }, { "getconnections", getconnections }, { "getgenv", getgenv },
    { "gethui", gethui }, { "getnamecallmethod", getnamecallmethod }, { "getsenv", getsenv },
    { "getthreadidentity", getthreadidentity }, { "hookfunction", hookfunction }, { "hookmetamethod", hookmetamethod },
    { "identifyexecutor", identifyexecutor }, { "isfile", isfile }, { "queue_on_teleport", queue_on_teleport },
    { "readfile", readfile }, { "setclipboard", setclipboard }, { "setnamecallmethod", setnamecallmethod },
    { "setthreadidentity", setthreadidentity }, { "writefile", writefile },
}
local available, missing = {}, {}
for _, cap in ipairs(CAPS) do
    if type(cap[2]) == "function" then available[#available + 1] = cap[1] else missing[#missing + 1] = cap[1] end
end
line("  available: " .. table.concat(available, ", "))
line("  MISSING: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
local okGenv, genv = pcall(function() return type(getgenv) == "function" and getgenv() or nil end)
local vy = okGenv and type(genv) == "table" and genv.VyAutoRank or nil
if type(vy) == "table" and type(vy.State) == "table" and vy.State.alive then
    line("  WARNING: VY AutoRank is running - its own requests mix into section 6 and it may leave the mountain.")
    line("           Stop it (GUI X), then run this probe again for a clean report.")
    print("[EventProbe] VY AutoRank is running - stop it (GUI X) first for a clean recording")
end

-- 1. Remotes ---------------------------------------------------------------------------
section("1. Event remotes (ReplicatedStorage.Network)")
local net = RS:FindFirstChild("Network")
if net then
    local rows = {}
    for _, r in ipairs(net:GetChildren()) do
        if matches(r.Name) then rows[#rows + 1] = string.format("  %-48s %s", r.Name, r.ClassName) end
    end
    table.sort(rows)
    for _, r in ipairs(rows) do line(r) end
    line("  matching: " .. #rows .. " of " .. #net:GetChildren())
end

-- 2. Client modules ---------------------------------------------------------------------
local library = RS:FindFirstChild("Library")
section("2. Event modules under ReplicatedStorage.Library (with their functions)")
if library then
    local found = 0
    for _, m in ipairs(library:GetDescendants()) do
        if m:IsA("ModuleScript") and matches(m.Name) and found < 80 then
            found += 1
            local ok, mod = asGame(require, m)
            local fns = {}
            if ok and type(mod) == "table" then
                for k, v in pairs(mod) do if type(v) == "function" then fns[#fns + 1] = tostring(k) end end
                table.sort(fns)
            end
            line("  " .. m:GetFullName() .. (ok and "" or " (require failed)") .. "\n      fns: " .. table.concat(fns, ", "))
        end
    end
    line("  modules found: " .. found)
end

-- 3. Directory tables -------------------------------------------------------------------
section("3. Event tables in Library.Directory (keys + one sample entry)")
local dirMod = library and library:FindFirstChild("Directory")
local okDir, Dir = false, nil
if dirMod then okDir, Dir = asGame(require, dirMod) end
-- Every Directory table: those already in Directory plus its child modules, which may
-- only load when first asked for.
local dirTables = {}
if okDir and type(Dir) == "table" then
    for name, tbl in pairs(Dir) do
        if type(tbl) == "table" then dirTables[tostring(name)] = tbl end
    end
end
for _, child in ipairs(dirMod and dirMod:GetChildren() or {}) do
    local childName = child.Name
    if child:IsA("ModuleScript") and dirTables[childName] == nil then
        local okT, tbl = false, nil
        if okDir and type(Dir) == "table" then okT, tbl = asGame(function() return Dir[childName] end) end
        if not (okT and type(tbl) == "table") then okT, tbl = asGame(require, child) end
        if okT and type(tbl) == "table" then dirTables[childName] = tbl end
    end
end
local dirNames = {}
for name in pairs(dirTables) do dirNames[#dirNames + 1] = name end
table.sort(dirNames)
line("  tables (" .. #dirNames .. "): " .. table.concat(dirNames, ", "))
for _, name in ipairs(dirNames) do
    if matches(name) then
        local keys, eventKeys, sample = {}, {}, nil
        for k, v in pairs(dirTables[name]) do
            keys[#keys + 1] = tostring(k)
            if entryMatches(k, v) then eventKeys[#eventKeys + 1] = tostring(k) end
            sample = sample or v
        end
        table.sort(keys)
        table.sort(eventKeys)
        if #keys <= 40 then
            line("  Directory." .. name .. " (" .. #keys .. "): " .. table.concat(keys, ", "))
            line("      sample: " .. short(sample))
        else -- a table shared by all events: only this event's keys (details in 3b)
            line("  Directory." .. name .. " (" .. #keys .. ", shared): event keys " .. (#eventKeys > 0 and table.concat(eventKeys, ", ") or "none"))
        end
    end
end

section("3b. This event's entries in every Directory table (camp eggs, pets, currencies, boosts...)")
local entryRows, visited = {}, 0
for _, name in ipairs(dirNames) do
    for k, v in pairs(dirTables[name]) do
        visited += 1
        if visited % 5000 == 0 then task.wait() end
        if #entryRows < 300 and entryMatches(k, v) then
            entryRows[#entryRows + 1] = "  Directory." .. name .. "[" .. string.format("%q", tostring(k)) .. "] = " .. short(v)
        end
    end
end
table.sort(entryRows)
for _, r in ipairs(entryRows) do line(r) end
line("  entries: " .. #entryRows .. (#entryRows >= 300 and " (first 300)" or "") .. " (checked " .. visited .. ")")

-- 4. Save fields ------------------------------------------------------------------------
section("4. Event fields in Save.Get() (name matches up to 5 levels deep, contents shown)")
local client = library and library:FindFirstChild("Client")
local saveMod = client and client:FindFirstChild("Save")
local okSave, save = false, nil
if saveMod then
    local okReq, S = asGame(require, saveMod)
    if okReq and type(S) == "table" and type(S.Get) == "function" then okSave, save = asGame(S.Get) end
end
if okSave and type(save) == "table" then
    local budget = { n = 0 }
    local function walk(t, path, depth)
        for k, v in pairs(t) do
            if budget.n >= 400 then return end
            local p = path .. "." .. tostring(k)
            if matches(k) then
                if type(v) == "table" then
                    dump(v, p, 0, budget)
                else
                    budget.n += 1
                    line("  " .. p .. " : " .. short(v))
                end
            elseif type(v) == "table" and depth < 4 and k ~= "Inventory" then
                walk(v, p, depth + 1)
            end
        end
    end
    walk(save, "Save", 0)
    -- event currencies / items in the inventory
    for cat, items in pairs(save.Inventory or {}) do
        if type(items) == "table" then
            for _, it in pairs(items) do
                if type(it) == "table" and matches(it.id) then line("  Inventory." .. tostring(cat) .. " item: " .. short(it)) end
            end
        end
    end
end

-- 5. World objects ----------------------------------------------------------------------
section("5. Event objects in the world (path, class, attributes)")
local okStream, streaming = pcall(function() return workspace.StreamingEnabled end)
line("  StreamingEnabled: " .. (okStream and tostring(streaming) or "?") .. " (if true, only nearby parts are loaded)")
local things = workspace:FindFirstChild("__THINGS")
local ic = things and things:FindFirstChild("__INSTANCE_CONTAINER")
local activeIc = ic and ic:FindFirstChild("Active")
local activeNames = {}
for _, c in ipairs(activeIc and activeIc:GetChildren() or {}) do activeNames[#activeNames + 1] = c.Name end
line("  Active instance(s): " .. (#activeNames > 0 and table.concat(activeNames, ", ") or "none"))
-- Repeats (Torch1..Torch300 in one camp) collapse into one row, so one crowded camp
-- cannot use up the list before the summit, trails and pedestals.
local rows, rowOf, scanned = {}, {}, 0
for _, d in ipairs(workspace:GetDescendants()) do
    scanned += 1
    if scanned % 5000 == 0 then task.wait() end
    if matches(d.Name) and not (d.Parent and matches(d.Parent.Name) and d:IsA("BasePart")) then
        local parentPath = d.Parent and d.Parent:GetFullName() or "?"
        local key = parentPath .. "." .. d.Name:gsub("%d+", "#") .. "[" .. d.ClassName .. "]"
        local row = rowOf[key]
        if row then
            row.count += 1
        elseif #rows < 400 then
            local attrs = {}
            for k, v in pairs(d:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. short(v) end
            row = { text = d:GetFullName() .. " [" .. d.ClassName .. "]" .. (#attrs > 0 and (" " .. table.concat(attrs, ", ")) or ""), count = 1 }
            rowOf[key] = row
            rows[#rows + 1] = row
        end
    end
end
for _, row in ipairs(rows) do line("  " .. row.text .. (row.count > 1 and ("  (x" .. row.count .. " similar)") or "")) end
line("  shown " .. #rows .. " rows (scanned " .. scanned .. " objects)")

-- 6. Recorder ---------------------------------------------------------------------------
local function finish()
    line("")
    line("Done in " .. math.floor(os.clock() - started) .. " s.")
    local text = table.concat(out, "\n")
    for i = 1, #out, 60 do print(table.concat(out, "\n", i, math.min(i + 59, #out))) end
    if type(writefile) == "function" then
        local name = "PS99_EventProbe_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
        local ok = pcall(writefile, name, text)
        print(ok and ("[EventProbe] saved " .. name .. " in your executor workspace folder") or "[EventProbe] save failed")
    end
    if type(setclipboard) == "function" then pcall(setclipboard, text) end
end

local function saveDiff(before)
    section("7. Save values that changed while you played (any name)")
    local okNow, now = false, nil
    if saveMod then
        local okReq, S = asGame(require, saveMod)
        if okReq and type(S) == "table" and type(S.Get) == "function" then okNow, now = asGame(S.Get) end
    end
    if not (okNow and type(now) == "table") then line("  Save.Get() unavailable") return end
    local after = flatten(now, "Save", 0, { n = 0, map = {} }).map
    local changes = {}
    for p, v in pairs(after) do
        if before[p] == nil then changes[#changes + 1] = p .. " : (new) " .. v
        elseif before[p] ~= v then changes[#changes + 1] = p .. " : " .. before[p] .. " -> " .. v end
    end
    for p, v in pairs(before) do
        if after[p] == nil then changes[#changes + 1] = p .. " : " .. v .. " -> (gone)" end
    end
    table.sort(changes)
    for i = 1, math.min(#changes, 300) do line("  " .. changes[i]) end
    line("  changed: " .. #changes .. (#changes > 300 and " (first 300 shown)" or ""))
end

if RECORD_SECONDS > 0 then
    local before = (okSave and type(save) == "table") and flatten(save, "Save", 0, { n = 0, map = {} }).map or nil
    local canHook = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
    section("6. Requests the game sent while you played (" .. RECORD_SECONDS .. " s)")
    if not canHook then line("  RECORD skipped: hookmetamethod/getnamecallmethod not available in this executor") end
    print("[EventProbe] RECORDING " .. RECORD_SECONDS .. " s. Do what you can, each once, slowly: teleport to a camp,")
    print("[EventProbe] send pets to a Rubble Wall, fight the Yeti, feed ONE cheap pet, start + claim an expedition, open")
    print("[EventProbe] a trail chest, buy one merchant item, buy one mountain upgrade, use one boost, buy one camp egg.")
    print("[EventProbe] Skip what you can't do now; the report saves itself when the time is up.")
    local NOISE = { "Breakables_PlayerDealDamage", "Orbs", "Lootbags", "Idle", "Ping", "Mouse", "Camera", "Mark Approached" }
    local seen, count, captured, recording = {}, 0, 0, true
    -- Formats one captured request. Runs in its own thread, outside the hook.
    local function record(at, method, name, args)
        if count >= 200 then return end
        local parts = {}
        for i = 1, args.n do parts[i] = short(args[i]) end
        local key = name .. "(" .. table.concat(parts, ", ") .. ")"
        if not seen[key] then
            seen[key] = true
            count += 1
            out[#out + 1] = redact(string.format("  [+%5.1fs] %s %s", at, method, key))
        end
    end
    if canHook then
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            -- No colon calls on Instances in here: one would replace the namecall method
            -- that old() dispatches the game's own request as (FireServer -> GetFullName).
            if recording then
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer") and captured < 2000 and typeof(self) == "Instance" then
                    local name = self.Name
                    local noisy = false
                    for _, w in ipairs(NOISE) do
                        if string.find(name, w, 1, true) then noisy = true break end
                    end
                    if not noisy then
                        captured += 1
                        -- Copy table arguments now: the game may reuse and clear one right after
                        -- sending it. table.clone fails on a protected metatable; keep the original.
                        local args = table.pack(...)
                        for i = 1, args.n do
                            if typeof(args[i]) == "table" then
                                local okCopy, copy = pcall(table.clone, args[i])
                                if okCopy then args[i] = copy end
                            end
                        end
                        task.defer(record, os.clock() - started, method, name, args)
                    end
                end
            end
            return old(self, ...)
        end)
    end
    task.delay(RECORD_SECONDS, function()
        recording = false -- the hook becomes a pass-through; it is not re-hooked
        if canHook and count == 0 then line("  nothing recorded") end
        if before then saveDiff(before) end
        finish()
    end)
else
    finish()
end
