-- =====================================================================================
--  PS99 Probe v1.0 - READ-ONLY game-structure report for Pet Simulator 99 (Potassium)
--
--  Sends NO game requests, buys/uses nothing and changes no settings. It only reads
--  what the client already has, then prints a report and saves it as a text file in the
--  executor workspace folder (PS99_Probe_<date>.txt). UserId and player name are
--  replaced with <me> in the output, so the report can be shared.
--
--  Optional RECORD mode (OFF by default): for RECORD_SECONDS seconds it notes which
--  remotes the GAME itself fires while YOU do one action by hand (for example open one
--  chest). It records names and argument types/short values only and never changes or
--  blocks anything. When the time is up its hook becomes a pass-through until you
--  leave the server (re-hooking could drop hooks other scripts added meanwhile).
-- =====================================================================================
local RECORD_SECONDS = 0          -- 0 = off. Set to e.g. 20, run, then do ONE action by hand.
local MAX_LINES_PER_SECTION = 400 -- keeps the report readable

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local out = {}
local me, myName = tostring(player and player.UserId or "?"), tostring(player and player.Name or "?")
local myDisplay = tostring(player and player.DisplayName or "")

local function esc(x) return (x:gsub("%p", "%%%0")) end
-- Display names may contain '_'; usernames are [A-Za-z0-9_] and never start or end with '_',
-- so for a username '_' is a boundary. Usernames are not case-sensitive.
local WORD_START, WORD_END = "%f[%w_\128-\255]", "%f[^%w_\128-\255]"
local NAME_START, NAME_END = "%f[%w\128-\255]", "%f[^%w\128-\255]"
local function anyCase(name) return (esc(name):gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)) end
-- Other players are never named in the report: each gets an alias <p1>, <p2>... The text
-- backstop knows only the unique ids (Name, UserId): a display name is not unique and may be
-- a game word, so it is hidden only where a Player is printed. Names that are also Directory
-- keys (game words) are likewise left to that structural rule.
local aliasOf, aliasCount, playerAlias = {}, 0, setmetatable({}, { __mode = "k" })
local knownPlayers = {} -- { text, pattern, alias, isId } per registered username and UserId
local collisionTables, collideMemo = {}, {}
local function register(p)
    if typeof(p) ~= "Instance" then return "<player>" end
    if p == player then return "<me>" end
    local a = playerAlias[p]
    if a then return a end
    aliasCount += 1
    a = "<p" .. aliasCount .. ">"
    playerAlias[p] = a
    pcall(function()
        local name, id = tostring(p.Name), tostring(p.UserId)
        if #name >= 3 and aliasOf[name] == nil then
            aliasOf[name] = a
            knownPlayers[#knownPlayers + 1] = { text = name, pattern = NAME_START .. anyCase(name) .. NAME_END, alias = a }
        end
        -- UserIds below 6 digits are the first ~100k accounts; shorter numbers are game values.
        if #id >= 6 and id:match("^%d+$") and aliasOf[id] == nil then
            aliasOf[id] = a
            knownPlayers[#knownPlayers + 1] = { text = id, pattern = "%f[%d]" .. id .. "%f[%D]", alias = a, isId = true }
        end
    end)
    return a
end
pcall(function() for _, p in ipairs(Players:GetPlayers()) do register(p) end end)
local joinedConn = nil
pcall(function() joinedConn = Players.PlayerAdded:Connect(register) end)
local function collides(t)
    local known = collideMemo[t]
    if known ~= nil then return known end
    local hit = rawget(collisionTables, t) ~= nil -- rawget: never run the Directory's __index
    if not hit then
        for _, tbl in pairs(collisionTables) do
            if type(tbl) == "table" and rawget(tbl, t) ~= nil then hit = true break end
        end
    end
    collideMemo[t] = hit
    return hit
end
local myNamePattern = NAME_START .. anyCase(myName) .. NAME_END
local function redact(s)
    s = tostring(s)
    if #me > 2 then s = s:gsub("%f[%d]" .. esc(me) .. "%f[%D]", "<me>") end
    if #myName > 2 then s = s:gsub(myNamePattern, "<me>") end
    -- Whole words only (a display name can be a common word); bytes >= 0x80 count as letters.
    if #myDisplay > 2 and myDisplay ~= myName and not collides(myDisplay) then
        s = s:gsub(WORD_START .. esc(myDisplay) .. WORD_END, "<me>")
    end
    -- Other players; names that are game words are left to the structural rule.
    for _, o in ipairs(knownPlayers) do
        if o.isId or not collides(o.text) then s = s:gsub(o.pattern, o.alias) end
    end
    return s
end
local function line(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    out[#out + 1] = redact(table.concat(parts, " "))
end
local function section(title) line("") line("==== " .. title .. " ====") end

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

-- An Instance's path, with players and their characters as aliases, and a per-player folder
-- (__THINGS.Hoverboards.<name>) too.
local function pathOf(inst)
    local ok, path = pcall(function()
        local parts, cur, hops = {}, inst, 0
        local thingsFolder = workspace:FindFirstChild("__THINGS")
        while cur ~= nil and cur ~= game and hops < 60 do
            hops += 1
            local seg = cur.Name
            local okOwner, owner = pcall(function() return Players:GetPlayerFromCharacter(cur) end)
            if cur:IsA("Player") then
                seg = register(cur)
            elseif okOwner and owner then
                seg = register(owner)
            elseif aliasOf[seg] and thingsFolder and cur.Parent and cur.Parent.Parent == thingsFolder then
                seg = aliasOf[seg]
            end
            table.insert(parts, 1, seg)
            cur = cur.Parent
        end
        return table.concat(parts, ".")
    end)
    if ok then return path end
    local okFull, fullName = pcall(function() return inst:GetFullName() end)
    return okFull and fullName or "?"
end

local function short(v)
    local t = typeof(v)
    if t == "string" then
        if #v > 40 then v = redact(v) end -- before the cut, so no name is cut in two
        return string.format("%q", #v > 40 and v:sub(1, 40) .. "..." or v)
    end
    if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    if t == "Instance" then
        local okP, isPlayer = pcall(function() return v:IsA("Player") end)
        if okP and isPlayer then return "Instance<Player>" .. register(v) end
        return "Instance<" .. v.ClassName .. ">" .. pathOf(v)
    end
    if t == "table" then
        local n = 0
        for _ in pairs(v) do n += 1 end
        return "table(" .. n .. ")"
    end
    return t
end

-- Shape of a table: keys with value types, nested to a small depth.
local function shape(tbl, depth, indent, budget)
    budget = budget or { n = 0 }
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        budget.n += 1
        if budget.n > MAX_LINES_PER_SECTION then line(indent .. "... (truncated)") return end
        local v = tbl[k]
        line(indent .. tostring(k) .. " : " .. (type(v) == "table" and short(v) or typeof(v) .. " = " .. short(v)))
        if type(v) == "table" and depth > 0 then shape(v, depth - 1, indent .. "  ", budget) end
    end
end

line("PS99 Probe v1.0 | " .. os.date("!%Y-%m-%d %H:%M:%S UTC") .. " | PlaceId " .. tostring(game.PlaceId))

-- 1. Executor capabilities -----------------------------------------------------------
section("1. Executor functions available")
local caps = { getgenv = getgenv, setthreadidentity = setthreadidentity, getthreadidentity = getthreadidentity,
    hookfunction = hookfunction, hookmetamethod = hookmetamethod, getnamecallmethod = getnamecallmethod,
    getsenv = getsenv, getconnections = getconnections, setreadonly = setreadonly, gethui = gethui,
    setclipboard = setclipboard, readfile = readfile, writefile = writefile, isfile = isfile,
    makefolder = makefolder, queue_on_teleport = queue_on_teleport, loadstring = loadstring }
local capNames = {}
for k in pairs(caps) do capNames[#capNames + 1] = k end
table.sort(capNames)
for _, name in ipairs(capNames) do line(string.format("  %-20s %s", name, type(caps[name]) == "function" and "yes" or "NO")) end

-- 2. Client modules and their functions ----------------------------------------------
local library = RS:FindFirstChild("Library")
local client = library and library:FindFirstChild("Client")
section("2. ReplicatedStorage.Library.Client modules (functions each one exposes)")
if not client then line("  Library.Client not found (game not loaded yet?)") else
    local mods = client:GetChildren()
    table.sort(mods, function(a, b) return a.Name < b.Name end)
    for _, m in ipairs(mods) do
        if m:IsA("ModuleScript") then
            local ok, mod = asGame(require, m)
            if ok and type(mod) == "table" then
                local fns = {}
                for k, v in pairs(mod) do if type(v) == "function" then fns[#fns + 1] = tostring(k) end end
                table.sort(fns)
                line("  " .. m.Name .. " (" .. #fns .. "): " .. table.concat(fns, ", "))
            else
                line("  " .. m.Name .. " : " .. (ok and typeof(mod) or "require failed: " .. tostring(mod)))
            end
        end
    end
end
section("2b. Library.Util / Balancing / Modules children")
for _, folder in ipairs({ "Util", "Balancing", "Modules" }) do
    local f = library and library:FindFirstChild(folder)
    if f then
        local names = {}
        for _, c in ipairs(f:GetChildren()) do names[#names + 1] = c.Name end
        table.sort(names)
        line("  " .. folder .. ": " .. table.concat(names, ", "))
    end
end

-- 3. Remotes -------------------------------------------------------------------------
section("3. Remotes (ReplicatedStorage.Network): name -> class")
local net = RS:FindFirstChild("Network")
if net then
    local rows = {}
    for _, r in ipairs(net:GetChildren()) do rows[#rows + 1] = string.format("  %-45s %s", r.Name, r.ClassName) end
    table.sort(rows)
    for _, r in ipairs(rows) do line(r) end
    line("  total: " .. #rows)
else line("  Network folder not found") end

-- 4. Save structure ------------------------------------------------------------------
local saveMod = client and client:FindFirstChild("Save")
local okSave, save = false, nil
if saveMod then
    local okReq, S = asGame(require, saveMod)
    if okReq and type(S) == "table" and type(S.Get) == "function" then okSave, save = asGame(S.Get) end
end
section("4. Save.Get(): top-level keys")
if okSave and type(save) == "table" then
    for k, v in pairs(save) do
        if k ~= "Inventory" and k ~= "Goals" then line("  " .. tostring(k) .. " : " .. typeof(v) .. " = " .. short(v)) end
    end
    section("4b. Active rank quests (Save.Goals)")
    for key, g in pairs(save.Goals or {}) do
        if type(g) == "table" then
            local f = {}
            for k, v in pairs(g) do
                f[#f + 1] = tostring(k) .. "=" .. (k == "UID" and "<uid>" or short(v))
            end
            table.sort(f)
            line("  key " .. tostring(key) .. " (" .. typeof(key) .. "): " .. table.concat(f, ", "))
        end
    end
    section("4c. Inventory: categories, stack counts, field names of one sample")
    for cat, items in pairs(save.Inventory or {}) do
        if type(items) == "table" then
            local n, sample = 0, nil
            for _, it in pairs(items) do n += 1 sample = sample or it end
            local fields = {}
            if type(sample) == "table" then
                for k, v in pairs(sample) do fields[#fields + 1] = tostring(k) .. ":" .. typeof(v) end
                table.sort(fields)
            end
            line(string.format("  %-12s %5d stacks | sample fields: %s | sample id: %s", tostring(cat), n,
                table.concat(fields, ", "), type(sample) == "table" and short(sample.id) or "-"))
        end
    end
    local keys = 0
    for _, it in pairs((save.Inventory or {}).Misc or {}) do
        if type(it) == "table" and it.id == "Crystal Key" then keys += tonumber(it._am) or 1 end
    end
    line("  Crystal Key (full) count: " .. keys)
else line("  Save.Get() unavailable: " .. tostring(save)) end

-- 5. Directory -----------------------------------------------------------------------
section("5. Library.Directory tables and current rank quest pools")
local dirMod = library and library:FindFirstChild("Directory")
local okDir, Dir = false, nil
if dirMod then okDir, Dir = asGame(require, dirMod) end
if okDir and type(Dir) == "table" then
    collisionTables = Dir
    collideMemo = {}
    local names = {}
    for k, v in pairs(Dir) do names[#names + 1] = tostring(k) .. "(" .. short(v) .. ")" end
    table.sort(names)
    line("  " .. table.concat(names, ", "))
    local util = library:FindFirstChild("Util")
    local ru = util and util:FindFirstChild("RanksUtil")
    local okRU, RU = false, nil
    if ru then okRU, RU = asGame(require, ru) end
    if okRU and type(RU) == "table" and okSave and type(save) == "table" and type(RU.RankIDFromNumber) == "function" then
        local _, id = asGame(RU.RankIDFromNumber, tonumber(save.Rank))
        local rank = id ~= nil and type(Dir.Ranks) == "table" and Dir.Ranks[id] or nil
        line("  current rank id: " .. tostring(id))
        if type(rank) == "table" and type(rank.Goals) == "table" then
            for slot, pool in pairs(rank.Goals) do
                local entries = {}
                for _, e in pairs(pool) do
                    if type(e) == "table" then
                        local extra = ""
                        for _, f in ipairs({ "PotionTier", "EnchantTier", "BreakableType", "CurrencyID" }) do
                            if e[f] ~= nil then extra = extra .. " " .. f .. "=" .. tostring(e[f]) end
                        end
                        entries[#entries + 1] = "T" .. tostring(e.Type) .. "x" .. tostring(e.Amount) .. extra
                    end
                end
                line("  slot " .. tostring(slot) .. ": " .. table.concat(entries, " | "))
            end
        end
    end
else line("  Directory unavailable") end

-- 6. World layout --------------------------------------------------------------------
section("6. Workspace layout")
local things = workspace:FindFirstChild("__THINGS")
if things then
    local names = {}
    for _, c in ipairs(things:GetChildren()) do names[#names + 1] = c.Name end
    table.sort(names)
    line("  __THINGS: " .. table.concat(names, ", "))
    local br = things:FindFirstChild("Breakables")
    if br then
        local kids = br:GetChildren()
        line("  Breakables: " .. #kids)
        local s = kids[1]
        if s then
            local attrs = {}
            for k, v in pairs(s:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. short(v) end
            table.sort(attrs)
            line("  sample breakable " .. s.ClassName .. " '" .. s.Name .. "': " .. table.concat(attrs, ", "))
        end
    end
    local ic = things:FindFirstChild("__INSTANCE_CONTAINER")
    local act = ic and ic:FindFirstChild("Active")
    if act then
        local n = {}
        for _, c in ipairs(act:GetChildren()) do n[#n + 1] = c.Name end
        line("  active instance(s): " .. (#n > 0 and table.concat(n, ", ") or "none"))
    end
end
local maps = {}
for _, c in ipairs(workspace:GetChildren()) do
    if c.Name:find("Map") then maps[#maps + 1] = c.Name .. "(" .. #c:GetChildren() .. " children)" end
end
line("  map folders: " .. table.concat(maps, ", "))
local map = workspace:FindFirstChild("Map")
local castle = map and map:FindFirstChild("3 | Castle")
local pad = castle and castle:FindFirstChild("INTERACT") and castle.INTERACT:FindFirstChild("CrystalChest")
pad = pad and pad:FindFirstChild("Pad")
line("  Crystal Chest pad (Map['3 | Castle'].INTERACT.CrystalChest.Pad): " .. (pad and "FOUND" or "not loaded / not found"))
local debris = workspace:FindFirstChild("__DEBRIS")
line("  __DEBRIS children: " .. (debris and #debris:GetChildren() or "none"))

-- 7. Optional recorder (read-only observation of the game's own requests) -------------
local function save_report()
    if joinedConn then pcall(function() joinedConn:Disconnect() end) end
    -- Once more with every alias known now: a player who joined later may be named earlier.
    local text = redact(table.concat(out, "\n"))
    for i = 1, #out, 60 do print(redact(table.concat(out, "\n", i, math.min(i + 59, #out)))) end
    if type(writefile) == "function" then
        local name = "PS99_Probe_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
        local ok, err = pcall(writefile, name, text)
        print(ok and ("[Probe] saved " .. name .. " in your executor workspace folder") or ("[Probe] save failed: " .. tostring(err)))
    end
    if type(setclipboard) == "function" then pcall(setclipboard, text) print("[Probe] report also copied to clipboard") end
end

if RECORD_SECONDS > 0 and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    section("7. Recorded game requests (" .. RECORD_SECONDS .. " s) - do ONE action by hand now")
    print("[Probe] RECORDING for " .. RECORD_SECONDS .. " s: do ONE action by hand now")
    local seen, count, recording, old = {}, 0, true, nil
    local NOISE = { "Breakables_", "Orbs", "Lootbags", "Pets_", "Idle", "Ping", "Mouse", "Camera" }
    -- Formats one request in its own thread, after it was sent: the remote's Name is read
    -- here, never in the hook, so no other script's __index hook runs before dispatch.
    local function record(method, remote, args)
        if count >= 60 then return end
        local okName, name = pcall(function() return remote.Name end)
        name = okName and tostring(name) or "?"
        for _, w in ipairs(NOISE) do
            if string.find(name, w, 1, true) then return end
        end
        -- Mail, trade, clan, friend and invite requests carry typed player names that no
        -- registry can know: their text arguments are not printed.
        local hide = false
        for _, w in ipairs({ "Mailbox", "Trad", "Clan", "Friend", "Invite" }) do
            if string.find(name, w, 1, true) then hide = true end
        end
        local parts = {}
        for i = 1, args.n do parts[i] = (hide and type(args[i]) == "string") and '"<text>"' or short(args[i]) end
        local key = name .. "(" .. table.concat(parts, ", ") .. ")"
        if not seen[key] then
            seen[key] = true
            count += 1
            out[#out + 1] = redact(string.format("  %s %s  args=%d", method, key, args.n))
        end
    end
    old = hookmetamethod(game, "__namecall", function(self, ...)
        -- Before old() dispatches the request nothing here may run other code that could
        -- change the namecall method: no colon calls and no property reads on Instances
        -- (another script's __index hook may make a colon call).
        if recording then
            local method = getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
                -- Copy table arguments now: the game may reuse and clear one right after
                -- sending it. table.clone fails on a protected metatable; keep the original.
                local args = table.pack(...)
                for i = 1, args.n do
                    if typeof(args[i]) == "table" then
                        local okCopy, copy = pcall(table.clone, args[i])
                        if okCopy then args[i] = copy end
                    end
                end
                -- task.defer raises in a thread already at Roblox's re-entrancy limit: then only
                -- this log line is lost, never the request.
                pcall(task.defer, record, method, self, args)
                if type(setnamecallmethod) == "function" then pcall(setnamecallmethod, method) end
            end
        end
        return old(self, ...)
    end)
    task.delay(RECORD_SECONDS, function()
        recording = false -- the hook becomes a pass-through; it is not re-hooked
        if count == 0 then line("  nothing recorded (noise filtered or no action done)") end
        save_report()
    end)
else
    if RECORD_SECONDS > 0 then line("  RECORD skipped: hookmetamethod/getnamecallmethod not available") end
    save_report()
end
