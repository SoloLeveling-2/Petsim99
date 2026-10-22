--!nocheck
-- Copied from VY/tests/lune/roblox_mock.luau so the TapSim harness is self-contained.
-- One change: FireServer/InvokeServer report a remote as "<Service>.<Name>" when it sits in
-- a sleitnick Comm folder (<Service>/RE|RF/<Name>), because Tap Simulator reuses remote names
-- (Claim, Hit, Purchase) across services. Fake Roblox datatypes/instances/signals only.
-- Minimal Roblox + PS99 client mock for running the WHOLE RankPilot bundle in
-- the real Luau VM (Lune). It fakes Instances, datatypes, services and a few
-- PS99 client modules. Time runs SPEED times faster than real time so a few
-- real seconds exercise minutes of worker loops. This proves the script
-- loads, builds its UI, runs its workers and shuts down without runtime
-- errors against these fakes; it does NOT prove live PS99 compatibility.
local luneTask = require("@lune/task")
local serde = require("@lune/serde")

local M = {}
M.SPEED = 40
local realClock = os.clock
local startReal = realClock()
local function vclock() return 1000 + (realClock() - startReal) * M.SPEED end
M.vclock = vclock

-- ------------------------------------------------------------------ datatypes
local Vector3 = {}
Vector3.__index = function(self, key)
    if key == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) end
    if key == "Unit" then
        local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
        if m == 0 then return Vector3.new(0, 0, 0) end
        return Vector3.new(self.X / m, self.Y / m, self.Z / m)
    end
    return rawget(Vector3, key)
end
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, __kind = "Vector3"}, Vector3) end
Vector3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3.__mul = function(a, b)
    if type(a) == "number" then return Vector3.new(b.X * a, b.Y * a, b.Z * a) end
    if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
    return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
Vector3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
Vector3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3.__tostring = function(a) return string.format("%g, %g, %g", a.X, a.Y, a.Z) end
function Vector3.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function Vector3.Lerp(a, b, t) return a + (b - a) * t end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)

local Vector2 = {}
Vector2.__index = function(self, key)
    if key == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y) end
    return rawget(Vector2, key)
end
function Vector2.new(x, y) return setmetatable({X = x or 0, Y = y or 0, __kind = "Vector2"}, Vector2) end
Vector2.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
Vector2.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
Vector2.zero = Vector2.new(0, 0)

local CFrame = {}
CFrame.__index = function(self, key)
    if key == "Position" or key == "p" then return Vector3.new(self.X, self.Y, self.Z) end
    if key == "LookVector" then return Vector3.new(0, 0, -1) end
    if key == "RightVector" then return Vector3.new(1, 0, 0) end
    if key == "UpVector" then return Vector3.new(0, 1, 0) end
    return rawget(CFrame, key)
end
function CFrame.new(x, y, z)
    if type(x) == "table" and x.__kind == "Vector3" then x, y, z = x.X, x.Y, x.Z end
    return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, __kind = "CFrame"}, CFrame)
end
function CFrame.lookAt(a) return CFrame.new(a) end
CFrame.Angles = function() return CFrame.new(0, 0, 0) end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.__add = function(a, b) return CFrame.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
CFrame.__sub = function(a, b) return CFrame.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
CFrame.__mul = function(a, b)
    if type(b) == "table" and b.__kind == "Vector3" then return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
    return CFrame.new(a.X + (b.X or 0), a.Y + (b.Y or 0), a.Z + (b.Z or 0))
end
function CFrame.ToWorldSpace(a, b) return a * b end
-- Rotation-free approximation: enough for containment checks in tests.
function CFrame.PointToObjectSpace(a, v) return Vector3.new(v.X - a.X, v.Y - a.Y, v.Z - a.Z) end
function CFrame.VectorToObjectSpace(_, v) return v end
function CFrame.VectorToWorldSpace(_, v) return v end
function CFrame.ToObjectSpace(a, b) return CFrame.new(b.X - a.X, b.Y - a.Y, b.Z - a.Z) end
function CFrame.Inverse(a) return CFrame.new(-a.X, -a.Y, -a.Z) end
function CFrame.Lerp(a, b, t) return CFrame.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
function CFrame.GetComponents(a) return a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1 end
function CFrame.PointToWorldSpace(a, b) return a * b end
CFrame.identity = CFrame.new(0, 0, 0)

local function datatype(kind, fields) fields.__kind = kind return fields end
local Color3 = {
    new = function(r, g, b) return datatype("Color3", {R = r or 0, G = g or 0, B = b or 0}) end,
    fromRGB = function(r, g, b) return datatype("Color3", {R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255}) end,
    fromHSV = function() return datatype("Color3", {R = 1, G = 1, B = 1}) end,
}
local UDim = {new = function(s, o) return datatype("UDim", {Scale = s or 0, Offset = o or 0}) end}
local UDim2 = {
    new = function(xs, xo, ys, yo) return datatype("UDim2", {X = UDim.new(xs, xo), Y = UDim.new(ys, yo)}) end,
}
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end

local enumCache = {}
local Enum = setmetatable({}, {__index = function(_, group)
    enumCache[group] = enumCache[group] or setmetatable({}, {__index = function(t, item)
        local token = datatype("EnumItem", {Name = item, EnumType = group, Value = 0})
        rawset(t, item, token)
        return token
    end})
    return enumCache[group]
end})

-- ------------------------------------------------------------------ signals
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({handlers = {}, __kind = "RBXScriptSignal"}, Signal) end
function Signal:Connect(fn)
    local entry = {fn = fn, Connected = true}
    table.insert(self.handlers, entry)
    return {Connected = true, Disconnect = function(c) entry.Connected = false c.Connected = false end, __kind = "RBXScriptConnection"}
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
    local c
    c = self:Connect(function(...) c:Disconnect() fn(...) end)
    return c
end
function Signal:Fire(...)
    for _, entry in ipairs(table.clone(self.handlers)) do
        if entry.Connected then
            local ok, err = pcall(entry.fn, ...)
            if not ok then M.recordError("signal handler: " .. tostring(err)) end
        end
    end
end
function Signal:Wait() luneTask.wait(0.03 / M.SPEED) return nil end
M.Signal = Signal

-- ------------------------------------------------------------------ instances
local EVENTS = {ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
    Changed = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, Activated = true,
    InputBegan = true, InputEnded = true, InputChanged = true, FocusLost = true, Focused = true,
    MouseEnter = true, MouseLeave = true, Idled = true, CharacterAdded = true, CharacterRemoving = true,
    Stepped = true, Heartbeat = true, RenderStepped = true, AncestryChanged = true, Died = true,
    JumpRequest = true, PlayerAdded = true, PlayerRemoving = true, OnClientEvent = true, Touched = true}
local ISA = {
    BasePart = {Part = true, MeshPart = true, UnionOperation = true, WedgePart = true, BasePart = true, TrussPart = true},
    GuiObject = {Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true,
        ImageButton = true, ScrollingFrame = true, CanvasGroup = true},
    GuiButton = {TextButton = true, ImageButton = true},
    LayerCollector = {ScreenGui = true, BillboardGui = true, SurfaceGui = true},
    LuaSourceContainer = {ModuleScript = true, LocalScript = true, Script = true},
    ValueBase = {StringValue = true, NumberValue = true, IntValue = true, BoolValue = true, ObjectValue = true},
    Light = {PointLight = true, SpotLight = true, SurfaceLight = true},
    PVInstance = {Model = true, Part = true, MeshPart = true},
}
local Instance = {}
local instanceMeta = {}
local allInstances = setmetatable({}, {__mode = "k"})
M.created = 0

local function isInstance(v) return type(v) == "table" and rawget(v, "__instance") == true end
M.isInstance = isInstance

local methods = {}
function methods:IsA(class)
    local cls = rawget(self, "ClassName")
    if cls == class or class == "Instance" then return true end
    local group = ISA[class]
    return group ~= nil and group[cls] == true
end
function methods:GetChildren() return table.clone(rawget(self, "__children")) end
function methods:GetDescendants()
    local out = {}
    local function walk(node)
        for _, child in ipairs(rawget(node, "__children")) do
            table.insert(out, child)
            walk(child)
        end
    end
    walk(self)
    return out
end
function methods:FindFirstChild(name, recursive)
    for _, child in ipairs(rawget(self, "__children")) do
        if rawget(child, "__props").Name == name then return child end
    end
    if recursive then
        for _, child in ipairs(rawget(self, "__children")) do
            local found = child:FindFirstChild(name, true)
            if found then return found end
        end
    end
    return nil
end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(rawget(self, "__children")) do
        if rawget(child, "ClassName") == class then return child end
    end
    return nil
end
function methods:FindFirstChildWhichIsA(class, recursive)
    for _, child in ipairs(rawget(self, "__children")) do
        if child:IsA(class) then return child end
    end
    if recursive then
        for _, child in ipairs(rawget(self, "__children")) do
            local found = child:FindFirstChildWhichIsA(class, true)
            if found then return found end
        end
    end
    return nil
end
function methods:FindFirstAncestor(name)
    local node = rawget(self, "__props").Parent
    while node do
        if node.Name == name then return node end
        node = rawget(node, "__props").Parent
    end
    return nil
end
function methods:FindFirstAncestorOfClass(class)
    local node = rawget(self, "__props").Parent
    while node do
        if rawget(node, "ClassName") == class then return node end
        node = rawget(node, "__props").Parent
    end
    return nil
end
function methods:WaitForChild(name)
    return self:FindFirstChild(name)
end
function methods:IsDescendantOf(other)
    local node = rawget(self, "__props").Parent
    while node do
        if node == other then return true end
        node = rawget(node, "__props").Parent
    end
    return false
end
function methods:IsAncestorOf(other) return isInstance(other) and other:IsDescendantOf(self) end
function methods:Destroy()
    self.Parent = nil
    rawset(self, "__destroyed", true)
    for _, child in ipairs(table.clone(rawget(self, "__children"))) do child:Destroy() end
end
function methods:ClearAllChildren()
    for _, child in ipairs(table.clone(rawget(self, "__children"))) do child:Destroy() end
end
function methods:Clone()
    local copy = Instance.new(rawget(self, "ClassName"))
    for k, v in pairs(rawget(self, "__props")) do if k ~= "Parent" then copy[k] = v end end
    return copy
end
function methods:GetAttribute(name) return rawget(self, "__attributes")[name] end
function methods:SetAttribute(name, value) rawget(self, "__attributes")[name] = value end
function methods:GetAttributes() return table.clone(rawget(self, "__attributes")) end
function methods:GetPropertyChangedSignal(prop)
    local signals = rawget(self, "__propSignals")
    signals[prop] = signals[prop] or Signal.new()
    return signals[prop]
end
function methods:GetFullName()
    local parts, node = {}, self
    while node do
        table.insert(parts, 1, node.Name)
        node = rawget(node, "__props").Parent
    end
    return table.concat(parts, ".")
end
function methods:GetPivot() return CFrame.new(self.Position or Vector3.zero) end
function methods:PivotTo(cf) self.CFrame = cf end
function methods:GetBoundingBox() return CFrame.new(self.Position or Vector3.zero), Vector3.new(4, 4, 4) end
function methods:GetService(name) return M.services[name] or M.service(name) end
function methods:FindService(name) return M.services[name] end
function methods:IsLoaded() return true end
function methods:GetPlayers() return {M.player} end
function methods:CaptureController() end
function methods:ClickButton2() end
function methods:Set3dRenderingEnabled(v) M.render3d = v end
function methods:JSONEncode(v) return serde.encode("json", v) end
function methods:JSONDecode(s) return serde.decode("json", s) end
function methods:GenerateGUID() return "00000000-0000-0000-0000-000000000000" end
function methods:GetTotalMemoryUsageMb() return 512 end
function methods:Teleport() M.teleports = (M.teleports or 0) + 1 end
function methods:TeleportToPlaceInstance() M.teleports = (M.teleports or 0) + 1 end
function methods:Kick() M.recordError("script kicked the player") end
function methods:GetMouse() return Instance.new("Mouse") end
function methods:ChangeState() end
function methods:MoveTo() end
function methods:LoadAnimation() return {Play = function() end, Stop = function() end} end
local function remoteKey(self)
    local props = rawget(self, "__props")
    local folder = props.Parent
    local folderName = folder and rawget(folder, "__props").Name
    local service = folder and rawget(folder, "__props").Parent
    if service and (folderName == "RE" or folderName == "RF") then
        return rawget(service, "__props").Name .. "." .. props.Name
    end
    return props.Name
end
function methods:InvokeServer(...) return M.invokeRemote(remoteKey(self), ...) end
function methods:FireServer(...) M.fireRemote(remoteKey(self), ...) end
function methods:TweenSize() end
function methods:TweenPosition() end

instanceMeta.__index = function(self, key)
    local m = methods[key]
    if m then return m end
    local props = rawget(self, "__props")
    local v = props[key]
    if v ~= nil then return v end
    if EVENTS[key] then
        local s = Signal.new()
        props[key] = s
        return s
    end
    local child = self:FindFirstChild(key)
    if child then return child end
    return nil
end
instanceMeta.__newindex = function(self, key, value)
    local props = rawget(self, "__props")
    if key == "Parent" then
        local old = props.Parent
        if old == value then return end
        if old then
            local kids = rawget(old, "__children")
            local i = table.find(kids, self)
            if i then table.remove(kids, i) end
        end
        props.Parent = value
        if value then
            if not isInstance(value) then error("Parent must be an Instance", 2) end
            table.insert(rawget(value, "__children"), self)
            value.ChildAdded:Fire(self)
            local node = value
            while node do
                local s = rawget(node, "__props").DescendantAdded
                if s then s:Fire(self) end
                node = rawget(node, "__props").Parent
            end
        end
        return
    end
    if (key == "TextColor3" or key == "BackgroundColor3" or key == "BorderColor3" or key == "ImageColor3")
        and not (type(value) == "table" and value.__kind == "Color3") then
        error("bad " .. key .. ": Color3 expected, got " .. typeof(value), 2)
    end
    if key == "Position" and rawget(self, "ClassName") ~= "Frame" and type(value) == "table" and value.__kind == "Vector3" then
        props.CFrame = CFrame.new(value)
    elseif key == "CFrame" and type(value) == "table" and value.__kind == "CFrame" then
        props.Position = value.Position
    end
    props[key] = value
    local signals = rawget(self, "__propSignals")
    if signals[key] then signals[key]:Fire(value) end
end
instanceMeta.__tostring = function(self) return tostring(rawget(self, "__props").Name) end

function Instance.new(class, parent)
    M.created += 1
    local obj = setmetatable({__instance = true, ClassName = class, __children = {}, __attributes = {},
        __propSignals = {}, __props = {Name = class, Archivable = true}}, instanceMeta)
    allInstances[obj] = true
    if class == "TextBox" then rawget(obj, "__props").Text = "" end
    if class:find("Text") then rawget(obj, "__props").Text = rawget(obj, "__props").Text or "" end
    if ISA.BasePart[class] then
        local props = rawget(obj, "__props")
        props.Position, props.CFrame, props.Size = Vector3.zero, CFrame.new(0, 0, 0), Vector3.new(4, 4, 4)
        props.Transparency, props.LocalTransparencyModifier, props.CanCollide, props.Anchored = 0, 0, true, true
    end
    if parent then obj.Parent = parent end
    return obj
end
M.Instance = Instance

local function node(class, name, parent, props)
    local obj = Instance.new(class)
    obj.Name = name
    for k, v in pairs(props or {}) do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end
M.node = node

local function typeofMock(v)
    if isInstance(v) then return "Instance" end
    if type(v) == "table" and type(rawget(v, "__kind")) == "string" then return rawget(v, "__kind") end
    return typeof(v)
end
M.typeof = typeofMock

M.Vector3, M.Vector2, M.CFrame, M.Color3, M.UDim, M.UDim2, M.Enum = Vector3, Vector2, CFrame, Color3, UDim, UDim2, Enum

-- ------------------------------------------------------------------ errors
M.errors = {}
function M.recordError(msg)
    table.insert(M.errors, tostring(msg))
end

return M
