-- =====================================================================================
--  PS99 Event Probe v4 - Diamond Mountain (update 98, 2026-10-18)     READ-ONLY
--  (v3 added sections 6b and 8 and server replies; v4 tags requests that another
--  executor script sends, e.g. a script hub, with [script]. Check the version in a
--  report's first line.)
--
--  Finds the event's real names so an event script can be built on evidence:
--    0. the executor's name, thread identity and which executor functions exist;
--    1. remotes, client modules (+ functions), Directory tables and Save fields whose
--       names match the event keywords, plus this event's entries inside tables every
--       event shares (camp eggs, pets, Acorns/TrailCoins, boosts...);
--    2. matching objects in the world (camps, walls, Yeti, trails, chests, merchant...);
--    3. RECORDER: for RECORD_SECONDS it notes every request the GAME sends while YOU
--       do the actions by hand (send pets to a wall, feed/fight the Yeti, start/claim an
--       expedition, buy from the merchant, buy an upgrade, use a boost, teleport to a camp),
--       a few lines per remote plus totals, and the server's reply to each request kind.
--    4. SAVE DIFF: every Save value that changed while you did those actions, whatever
--       its name (finds event fields stored under unexpected parents), telemetry left out.
--    5. At the end: the instance state again, custom egg ids, and the mountain's layout
--       and prompts. Start the probe already ON the mountain for sections 4 and 5.
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

-- Like short(), but 3 levels deep and up to 12 keys per table, capped at 1500 characters
-- (server replies such as wall or expedition state).
local function long(v, depth)
    depth = depth or 0
    if typeof(v) ~= "table" then return short(v) end
    if depth >= 3 then return "{...}" end
    local parts, n = {}, 0
    for k, x in pairs(v) do
        n += 1
        if n <= 12 then parts[#parts + 1] = tostring(k) .. "=" .. long(x, depth + 1) end
    end
    local s = "{" .. table.concat(parts, ", ") .. (n > 12 and (", +" .. (n - 12)) or "") .. "}"
    if #s > 1500 then s = s:sub(1, 1500) .. "...}" end
    return s
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

line("PS99 Event Probe v4 (Diamond Mountain) | " .. os.date("!%Y-%m-%d %H:%M:%S UTC") .. " | PlaceId " .. game.PlaceId)

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
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        -- name/argument count (+ = takes more), to call the game's own functions right
                        local okInfo, nparams, vararg = pcall(debug.info, v, "a")
                        local arity = (okInfo and type(nparams) == "number") and ("/" .. nparams .. (vararg and "+" or "")) or ""
                        fns[#fns + 1] = tostring(k) .. arity
                    end
                end
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
    -- Telemetry filled most of run 1's diff (Engagement stats, notification counters, pet XP).
    local SKIP = { "Save.Engagement.", "Save.InventoryNotifications.", "._uq.xp" }
    local function skipped(p)
        for _, s in ipairs(SKIP) do if string.find(p, s, 1, true) then return true end end
        return false
    end
    local changes, telemetry = {}, 0
    for p, v in pairs(after) do
        if before[p] ~= v then
            if skipped(p) then telemetry += 1
            elseif before[p] == nil then changes[#changes + 1] = p .. " : (new) " .. v
            else changes[#changes + 1] = p .. " : " .. before[p] .. " -> " .. v end
        end
    end
    for p, v in pairs(before) do
        if after[p] == nil then
            if skipped(p) then telemetry += 1 else changes[#changes + 1] = p .. " : " .. v .. " -> (gone)" end
        end
    end
    -- The event's own data first.
    table.sort(changes, function(a, b)
        local ea, eb = string.find(a, "DiamondMountain", 1, true) ~= nil, string.find(b, "DiamondMountain", 1, true) ~= nil
        if ea ~= eb then return ea end
        return a < b
    end)
    for i = 1, math.min(#changes, 400) do line("  " .. changes[i]) end
    line("  changed: " .. #changes .. (#changes > 400 and " (first 400 shown)" or "")
        .. " | telemetry left out: " .. telemetry .. " (Engagement, notifications, pet XP)")
end

-- 8. The event instance at the end: you may have entered the mountain while recording.
local function instanceAfter()
    section("8. Event instance at the end (state, custom eggs, layout, prompts)")
    local thingsNow = workspace:FindFirstChild("__THINGS")
    local instances = thingsNow and thingsNow:FindFirstChild("Instances")
    local state = instances and instances:FindFirstChild("DiamondMountain")
    if state then
        local attrs = {}
        for k, v in pairs(state:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. short(v) end
        table.sort(attrs)
        line("  __THINGS.Instances.DiamondMountain: " .. table.concat(attrs, ", "))
    end
    local kids = {}
    for _, c in ipairs(thingsNow and thingsNow:GetChildren() or {}) do
        kids[#kids + 1] = c.Name .. "(" .. #c:GetChildren() .. ")"
        -- Egg folders: their children are the ids that egg hatch requests send.
        if string.find(string.lower(c.Name), "egg", 1, true) then
            for i, egg in ipairs(c:GetChildren()) do
                if i > 30 then break end
                local attrs = {}
                for k, v in pairs(egg:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. short(v) end
                table.sort(attrs)
                line("  " .. egg:GetFullName() .. " [" .. egg.ClassName .. "] " .. table.concat(attrs, ", "))
            end
        end
    end
    table.sort(kids)
    line("  __THINGS: " .. table.concat(kids, ", "))
    local containerNow = thingsNow and thingsNow:FindFirstChild("__INSTANCE_CONTAINER")
    local active = containerNow and containerNow:FindFirstChild("Active")
    if not active or #active:GetChildren() == 0 then
        line("  not inside an event instance at the end (be on the mountain when the time is up)")
        return
    end
    -- Folders/models near the top, anything with attributes, and every prompt or click
    -- detector (how players interact). Repeats collapse into one row.
    local iRows, iRowOf, iScanned = {}, {}, 0
    for _, d in ipairs(active:GetDescendants()) do
        iScanned += 1
        if iScanned % 5000 == 0 then task.wait() end
        local depth, p = 0, d.Parent
        while p and p ~= active do depth += 1 p = p.Parent end
        local attrs = {}
        for k, v in pairs(d:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. short(v) end
        local prompt = d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
        if prompt or #attrs > 0 or (depth <= 3 and (d:IsA("Folder") or d:IsA("Model"))) then
            local key = (d.Parent and d.Parent:GetFullName() or "?") .. "." .. d.Name:gsub("%d+", "#") .. "[" .. d.ClassName .. "]"
            local row = iRowOf[key]
            if row then
                row.count += 1
            elseif #iRows < 400 then
                table.sort(attrs)
                local extra = ""
                if d:IsA("ProximityPrompt") then
                    extra = string.format(' action="%s" object="%s" hold=%s', tostring(d.ActionText), tostring(d.ObjectText), tostring(d.HoldDuration))
                end
                row = { text = d:GetFullName() .. " [" .. d.ClassName .. "]" .. extra .. (#attrs > 0 and (" " .. table.concat(attrs, ", ")) or ""), count = 1 }
                iRowOf[key] = row
                iRows[#iRows + 1] = row
            end
        end
    end
    for _, row in ipairs(iRows) do line("  " .. row.text .. (row.count > 1 and ("  (x" .. row.count .. " similar)") or "")) end
    line("  shown " .. #iRows .. " rows (scanned " .. iScanned .. " objects in the instance)")
end

if RECORD_SECONDS > 0 then
    local before = (okSave and type(save) == "table") and flatten(save, "Save", 0, { n = 0, map = {} }).map or nil
    local canHook = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
    section("6. Requests the game sent while you played (" .. RECORD_SECONDS .. " s)")
    if not canHook then line("  RECORD skipped: hookmetamethod/getnamecallmethod not available in this executor") end
    print("[EventProbe] RECORDING " .. RECORD_SECONDS .. " s. Do what you can, each once, slowly: teleport to a camp,")
    print("[EventProbe] send pets to a Rubble Wall, fight the Yeti, feed ONE cheap pet, start + claim an expedition, open")
    print("[EventProbe] a trail chest, buy one merchant item, buy one mountain upgrade, use one boost, buy one camp egg.")
    print("[EventProbe] Skip what you can't do now; stay on the mountain; the report saves itself when the time is up.")
    local NOISE = { "Breakables_PlayerDealDamage", "Orbs", "Lootbags", "Idle", "Ping", "Mouse", "Camera", "Mark Approached" }
    -- Each remote (each event action for Instancing_* remotes) gets its own few lines, so one
    -- chatty remote cannot use up the report: in run 1, fps pings filled it after 138 s.
    local PER_REMOTE, MAX_LINES = 4, 400
    local seen, buckets, lines, captured, recording = {}, {}, 0, 0, true
    local function bucketOf(name, args)
        if string.sub(name, 1, 11) == "Instancing_" and type(args[2]) == "string" then return name .. " " .. args[2] end
        return name
    end
    -- fromScript: sent by an executor script (checkcaller), e.g. a script hub, not the game.
    local function bucketFor(method, name, args, fromScript)
        local base = bucketOf(name, args)
        local key = (fromScript and "[script] " or "") .. base
        local b = buckets[key]
        if not b then
            b = { key = key, base = base, tag = fromScript and "[script] " or "", method = method, calls = 0, shown = 0, replies = 0 }
            buckets[key] = b
        end
        return b
    end
    -- Formats one captured request. Runs in its own thread, outside the hook.
    local function record(at, method, name, args, fromScript)
        local b = bucketFor(method, name, args, fromScript)
        b.calls += 1
        if b.shown >= PER_REMOTE or lines >= MAX_LINES then return end
        local parts = {}
        for i = 1, args.n do parts[i] = short(args[i]) end
        local key = name .. "(" .. table.concat(parts, ", ") .. ")"
        if not seen[key] then
            seen[key] = true
            b.shown += 1
            lines += 1
            out[#out + 1] = redact(string.format("  [+%5.1fs] %s%s %s", at, fromScript and "[script] " or "", method, key))
        end
    end
    local function recordReply(at, name, args, text, fromScript)
        local b = bucketFor("InvokeServer", name, args, fromScript)
        if b.replies >= 2 or lines >= MAX_LINES then return end
        b.replies += 1
        lines += 1
        out[#out + 1] = redact(string.format("  [+%5.1fs]   %sreply %s -> %s", at, b.tag, b.base, text))
    end
    local function totals()
        section("6b. Request totals while recording (every remote, also those not shown above)")
        local list = {}
        for _, b in pairs(buckets) do list[#list + 1] = b end
        table.sort(list, function(a, b) return a.calls > b.calls end)
        for i = 1, math.min(#list, 150) do
            line(string.format("  %5d  %s%s %s", list[i].calls, list[i].tag, list[i].method, list[i].base))
        end
    end
    if canHook then
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            -- No colon calls on Instances in here: one would replace the namecall method
            -- that old() dispatches the game's own request as (FireServer -> GetFullName).
            if recording then
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer") and captured < 5000 and typeof(self) == "Instance" then
                    local name = self.Name
                    local noisy = false
                    for _, w in ipairs(NOISE) do
                        if string.find(name, w, 1, true) then noisy = true break end
                    end
                    if not noisy then
                        captured += 1
                        local fromScript = false
                        if type(checkcaller) == "function" then
                            local okCaller, caller = pcall(checkcaller)
                            fromScript = okCaller and caller == true
                        end
                        -- Copy table arguments now: the game may reuse and clear one right after
                        -- sending it. table.clone fails on a protected metatable; keep the original.
                        local args = table.pack(...)
                        for i = 1, args.n do
                            if typeof(args[i]) == "table" then
                                local okCopy, copy = pcall(table.clone, args[i])
                                if okCopy then args[i] = copy end
                            end
                        end
                        task.defer(record, os.clock() - started, method, name, args, fromScript)
                        -- The server's reply (wall HP, expedition state...). Only where this thread
                        -- may yield across our frame; otherwise pass the call straight through.
                        if method == "InvokeServer" and coroutine.isyieldable() then
                            local reply = table.pack(old(self, ...))
                            -- The request has been dispatched and answered: formatting (which makes
                            -- colon calls) can no longer change it. Errors here never reach the game.
                            local okText, text = pcall(function()
                                local parts = {}
                                for i = 1, reply.n do parts[i] = long(reply[i]) end
                                return table.concat(parts, ", ")
                            end)
                            if type(setnamecallmethod) == "function" then pcall(setnamecallmethod, method) end
                            task.defer(recordReply, os.clock() - started, name, args, okText and text or "?", fromScript)
                            return table.unpack(reply, 1, reply.n)
                        end
                    end
                end
            end
            return old(self, ...)
        end)
    end
    task.delay(RECORD_SECONDS, function()
        recording = false -- the hook becomes a pass-through; it is not re-hooked
        if canHook and lines == 0 then line("  nothing recorded") end
        if canHook then totals() end
        if before then saveDiff(before) end
        instanceAfter()
        finish()
    end)
else
    finish()
end
