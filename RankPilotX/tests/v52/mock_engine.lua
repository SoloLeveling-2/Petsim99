-- Mock RankPilot engine for v5.2 module tests (Lua 5.4).
-- Provides the main-chunk locals that src/modules/*.lua capture as upvalues,
-- backed by an in-memory fake PS99 client. Tests mutate `fake` to simulate
-- game responses and inspect `requests` for what the module sent.
local clock = 1000
local function now() return clock end
function advance(seconds) clock = clock + seconds end
math.clamp = math.clamp or function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
table.find = table.find or function(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
unpack = unpack or table.unpack

Color3 = {fromRGB = function(r, g, b) return {_color = true, r = r, g = g, b = b} end}
Vector3 = {new = function(x, y, z) return {X = x or 0, Y = y or 0, Z = z or 0} end}
CFrame = {new = function(x, y, z) return {X = x or 0, Y = y or 0, Z = z or 0, _cf = true} end}
function typeof(v)
    if type(v) == "table" and v._color then return "Color3" end
    if type(v) == "table" and v.ClassName then return "Instance" end
    return type(v)
end
task = {wait = function(s) advance(s or 0.03) return s end, spawn = function(f, ...) return f(...) end,
    delay = function(_, f, ...) return f(...) end, defer = function(f, ...) return f(...) end}

logs = {}
requests = {}
fake = {responses = {}, save = {Inventory = {}, Rank = 10, RankStars = 0, Goals = {}}, clients = {}}

local Config = {Enabled = false, AutoRank = true, LowLagMode = true, MaxErrorsPerFeature = 5,
    SaveRefreshSeconds = 1.8, LocalNotifications = true}
local state = {running = true, shutdown = false, generations = 1, modules = {}, failures = {},
    cooldowns = {}, logs = {}, connections = {}, clients = fake.clients, commandCount = 0,
    blocked = {}, goals = {}, extras = {alerts = {}}, attempts = {}, world = {number = 1}}
local Modules = {list = {}, byId = {}}
local environment = {}
local leases = {owner = nil, untilAt = 0}

local function describe(v) return tostring(v) end
local function log(text, category) table.insert(logs, "[" .. tostring(category or "INFO") .. "] " .. tostring(text)) end
local function cooldownReady(key, seconds)
    if now() < (state.cooldowns[key] or 0) then return false end
    state.cooldowns[key] = now() + seconds
    return true
end
local function failFeature(feature, err)
    local r = state.failures[feature] or {count = 0, disabled = false}
    r.count = r.count + 1
    r.lastError = tostring(err)
    if r.count >= Config.MaxErrorsPerFeature then r.disabled = true end
    state.failures[feature] = r
end
local function healthy(feature)
    local r = state.failures[feature]
    return not (r and r.disabled)
end
local function guarded(feature, fn)
    if not healthy(feature) then return false end
    local ok, v = pcall(fn)
    if not ok then failFeature(feature, v) end
    return ok, v
end
local function findChild(parent, name)
    if type(parent) ~= "table" or type(parent.FindFirstChild) ~= "function" then return nil end
    return parent:FindFirstChild(name)
end
local function callMethod(tbl, name, ...)
    if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return false, "missing " .. tostring(name) end
    return pcall(tbl[name], ...)
end
local function movementAvailable(owner) return leases.owner == nil or leases.owner == owner or now() >= leases.untilAt end
local function leaseMovement(owner, seconds)
    if not movementAvailable(owner) then return false end
    leases.owner, leases.untilAt = owner, now() + (seconds or 5)
    return true
end
local function clearMovement(owner) if leases.owner == owner then leases.owner = nil end end
local hatchWindow = false
local function inHatchMovementWindow() return hatchWindow end
local root = {Parent = true, CFrame = CFrame.new(0, 0, 0), Position = Vector3.new(0, 0, 0)}
local function currentRoot() return root end
local function tryModule(node) return type(node) == "table" and node.module or nil end
local function refreshClients() state.clients = fake.clients return true end
local function saveData() return fake.save end
-- network(): every request is recorded; fake.responses[name] decides the result.
local function network(name, args, invoke)
    table.insert(requests, {name = name, args = args or {}, invoke = invoke})
    local response = fake.responses[name]
    if response == nil then return false, "remote missing or wrong type: " .. name end
    if type(response) == "function" then return pcall(response, table.unpack(args or {})) end
    return true, response
end
local function attemptNetwork(feature, name, args, invoke, interval)
    if not cooldownReady("remote:" .. name, interval or 3) then return false end
    local ok, result = network(name, args, invoke)
    if not ok then failFeature(feature, result) return false end
    return result ~= false
end
local function persist() end
local function extraAlert(message) table.insert(state.extras.alerts, 1, tostring(message)) end
local function recheck() end
local function getZoneInfo() return fake.zone end
local function placeInZone() return true end
local function readGoals() return state.goals end
local function inspectState() return true end
local function eligible(goal) return goal ~= nil and not goal.ineligible end
local farmZoneName = "Zone A"
local function currentFarmZone() return farmZoneName end
function setFarmZone(name) farmZoneName = name end
function setHatchWindow(v) hatchWindow = v end
ReplicatedStorage = {FindFirstChild = function() return nil end}
local Workspace = {FindFirstChild = function() return nil end, GetServerTimeNow = function() return clock end}
local LocalPlayer = {Name = "Tester", UserId = 1}
local RunService = {Set3dRenderingEnabled = function() end}
local HttpService = {JSONEncode = function() return "{}" end, JSONDecode = function() return {} end}
game = {GetService = function(_, name) return fake.services and fake.services[name] or {} end, PlaceId = 1, JobId = "job"}

function sent(name)
    local n = 0
    for _, r in ipairs(requests) do if r.name == name then n = n + 1 end end
    return n
end
function lastRequest(name)
    for i = #requests, 1, -1 do if requests[i].name == name then return requests[i] end end
    return nil
end
function tickModule(id)
    local m = Modules.byId[id]
    assert(m, "module " .. tostring(id) .. " not registered")
    local bucket = state.modules[id]
    if bucket then bucket.nextAt = 0 end
    if type(m.active) == "function" and not m.active() then return false, "inactive" end
    return m.tick()
end
