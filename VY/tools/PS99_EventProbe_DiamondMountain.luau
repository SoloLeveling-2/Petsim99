-- =====================================================================================
--  PS99 Event Probe - Diamond Mountain (update 98, 2026-10-17)        READ-ONLY
--
--  Finds the event's real names so an event script can be built on evidence:
--    1. remotes, client modules (+ functions), Directory tables and Save fields whose
--       names match the event keywords;
--    2. matching objects in the world (camps, walls, Yeti, trails, chests, merchant...);
--    3. RECORDER: for RECORD_SECONDS it notes every request the GAME sends while YOU
--       do the actions by hand (send pets to a wall, feed/fight the Yeti, start/claim an
--       expedition, buy from the merchant, buy an upgrade, use a boost, teleport to a camp).
--  It sends nothing itself, never blocks or changes a request, removes its hook at the
--  end, and replaces your UserId/name with <me>. Report: PS99_EventProbe_<date>.txt
-- =====================================================================================
local RECORD_SECONDS = 120   -- time you have to do the actions by hand (0 = no recording)
local KEYWORDS = { "mountain", "yeti", "camp", "rubble", "wall", "trail", "expedition", "artifact",
    "acorn", "merchant", "summit", "season", "boost", "upgrade", "climb", "pedestal", "marmot", "equinox" }

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
local function asGame(fn, ...)
    if type(setthreadidentity) == "function" then pcall(setthreadidentity, 2) end
    local r = table.pack(pcall(fn, ...))
    if type(setthreadidentity) == "function" then pcall(setthreadidentity, 8) end
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

line("PS99 Event Probe (Diamond Mountain) | " .. os.date("!%Y-%m-%d %H:%M:%S UTC") .. " | PlaceId " .. game.PlaceId)

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
if okDir and type(Dir) == "table" then
    for name, tbl in pairs(Dir) do
        if matches(name) and type(tbl) == "table" then
            local keys, sample = {}, nil
            for k, v in pairs(tbl) do
                keys[#keys + 1] = tostring(k)
                sample = sample or v
            end
            table.sort(keys)
            line("  Directory." .. tostring(name) .. " (" .. #keys .. "): " .. table.concat(keys, ", ", 1, math.min(#keys, 30)))
            line("      sample: " .. short(sample))
        end
    end
end

-- 4. Save fields ------------------------------------------------------------------------
section("4. Event fields in Save.Get() (name matches, 3 levels deep)")
local client = library and library:FindFirstChild("Client")
local saveMod = client and client:FindFirstChild("Save")
local okSave, save = false, nil
if saveMod then
    local okReq, S = asGame(require, saveMod)
    if okReq and type(S) == "table" and type(S.Get) == "function" then okSave, save = asGame(S.Get) end
end
if okSave and type(save) == "table" then
    local shown = 0
    local function walk(t, path, depth)
        for k, v in pairs(t) do
            if shown > 150 then return end
            local p = path .. "." .. tostring(k)
            if matches(k) then
                shown += 1
                line("  " .. p .. " : " .. short(v))
            elseif type(v) == "table" and depth < 2 and k ~= "Inventory" then
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
local shown, scanned = 0, 0
for _, d in ipairs(workspace:GetDescendants()) do
    scanned += 1
    if scanned % 5000 == 0 then task.wait() end
    if shown < 250 and matches(d.Name) and not (d.Parent and matches(d.Parent.Name) and d:IsA("BasePart")) then
        shown += 1
        local attrs = {}
        for k, v in pairs(d:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. short(v) end
        line("  " .. d:GetFullName() .. " [" .. d.ClassName .. "]" .. (#attrs > 0 and (" " .. table.concat(attrs, ", ")) or ""))
    end
end
line("  shown " .. shown .. " (scanned " .. scanned .. " objects; stand on the mountain for best results)")

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

if RECORD_SECONDS > 0 and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    section("6. Requests the game sent while you played (" .. RECORD_SECONDS .. " s)")
    print("[EventProbe] RECORDING " .. RECORD_SECONDS .. " s. Do each once, slowly: teleport to a camp, send pets to a")
    print("[EventProbe] Rubble Wall, fight the Yeti, feed ONE cheap pet, start + claim an expedition, open a trail chest,")
    print("[EventProbe] buy one merchant item, buy one mountain upgrade, use one boost, buy one camp egg.")
    local NOISE = { "Breakables_PlayerDealDamage", "Orbs", "Lootbags", "Idle", "Ping", "Mouse", "Camera", "Mark Approached" }
    local seen, count, old = {}, 0, nil
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and count < 200 then
            local name = self.Name
            local noisy = false
            for _, w in ipairs(NOISE) do if name:find(w, 1, true) then noisy = true break end end
            if not noisy then
                local args = table.pack(...)
                local parts = {}
                for i = 1, args.n do parts[i] = short(args[i]) end
                local key = name .. "(" .. table.concat(parts, ", ") .. ")"
                if not seen[key] then
                    seen[key] = true
                    count += 1
                    out[#out + 1] = redact(string.format("  [+%5.1fs] %s %s", os.clock() - started, method, key))
                end
            end
        end
        return old(self, ...)
    end)
    task.delay(RECORD_SECONDS, function()
        hookmetamethod(game, "__namecall", old)
        if count == 0 then line("  nothing recorded") end
        finish()
    end)
else
    if RECORD_SECONDS > 0 then line("RECORD skipped: hookmetamethod/getnamecallmethod not available in this executor") end
    finish()
end
