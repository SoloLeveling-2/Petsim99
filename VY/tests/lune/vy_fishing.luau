--!nocheck
-- Fake normal-Fishing instance for the VY harness. Shapes follow what VY's
-- adapter reads (instance container, Water.Layer1, rod FishingLine with two
-- attachments, Bobbers, __DEBRIS bubble hosts, the current "Keep tapping to
-- reel!" prompt). The real game's protocol is only partly observed (handoff
-- F16); this fake follows VY's own assumptions so the WHOLE transaction can be
-- exercised offline. It cannot show whether the live server accepts them.
local R = require("./roblox_mock")
local luneTask = require("@lune/task")
local W = require("./vy_world")
local node, Vector3, CFrame = R.node, R.Vector3, R.CFrame

local F = {casts = 0, reels = 0, taps = 0, catches = 0, tapsPerCatch = 8, biteDelay = 2, creditDelay = 1}
local function vdelay(s, fn) luneTask.delay(s / R.SPEED, fn) end

function F.install(opts)
    opts = opts or {}
    F.layout = opts.layout or "current" -- "current" prompt text or "legacy" GameBar
    local things, ws = W.things, W.ws
    local instances = node("Folder", "Instances", things)
    local portal = node("Folder", "Fishing", instances)
    local teleports = node("Folder", "Teleports", portal)
    local enter = node("Part", "Enter", teleports)
    enter.CFrame = CFrame.new(300, 2, 0)
    local container = node("Folder", "__INSTANCE_CONTAINER", things)
    F.active = node("Folder", "Active", container)
    F.debris = node("Folder", "__DEBRIS", ws)

    W.instancing.Enter = function(name)
        W.event("instance-enter", name)
        luneTask.wait(0.2 / R.SPEED)
        local model = node("Model", name, F.active)
        local water = node("Folder", "Water", model)
        local layer = node("Part", "Layer1", water, {Size = Vector3.new(200, 2, 200)})
        layer.CFrame = CFrame.new(1000, 0, 120)
        F.bobbers = node("Folder", "Bobbers", model)
        F.model = model
        W.instance = name
        W.root.CFrame = CFrame.new(1000, 5, 0)
        F.rod = node("Model", "Rod", W.character)
        node("Attachment", "Tip", F.rod, {WorldPosition = Vector3.new(1000, 8, 0)})
        return true
    end
    W.instancing.Leave = function()
        W.event("instance-leave")
        luneTask.wait(0.2 / R.SPEED)
        if F.model then F.model:Destroy() F.model = nil end
        if F.rod then F.rod:Destroy() F.rod = nil end
        W.instance = nil
        W.root.CFrame = CFrame.new(300, 5, 0)
        return true
    end

    W.handlers["Instancing_FireCustomFromClient"] = function(name, cmd, arg)
        if name ~= "Fishing" or W.instance ~= "Fishing" then return end
        if cmd == "RequestCast" then
            F.casts += 1
            local target = arg
            vdelay(0.3, function()
                if not F.rod then return end
                local bob = node("Model", "Bobber" .. F.casts, F.bobbers)
                local part = node("Part", "Bobber", bob)
                part.CFrame = CFrame.new(target)
                local endAttachment = node("Attachment", "LineEnd", part, {WorldPosition = target})
                node("Beam", "FishingLine", F.rod, {Attachment0 = F.rod:FindFirstChild("Tip"), Attachment1 = endAttachment})
                F.bobber = part
                vdelay(F.biteDelay, function()
                    if F.bobber ~= part then return end
                    local host = node("Part", "host", F.debris)
                    host.CFrame = CFrame.new(target)
                    local a = node("Attachment", "Attachment", host)
                    node("ParticleEmitter", "Bubbles", a, {Enabled = false})
                    F.host = host
                end)
            end)
        elseif cmd == "RequestReel" then
            F.reels += 1
            if F.host then F.host:Destroy() F.host = nil end
            vdelay(0.5, function() F.showPrompt(true) end)
        end
    end
    W.handlers["Instancing_InvokeCustomFromClient"] = function(name, cmd)
        luneTask.wait(0.05 / R.SPEED)
        if name ~= "Fishing" or cmd ~= "Clicked" or not F.promptShown then return false, "not catching" end
        F.taps += 1
        F.tapsThisCatch = (F.tapsThisCatch or 0) + 1
        if F.tapsThisCatch >= F.tapsPerCatch then
            F.tapsThisCatch = 0
            F.showPrompt(false)
            local line = F.rod and F.rod:FindFirstChild("FishingLine")
            if line then line:Destroy() end
            if F.bobber then F.bobber.Parent:Destroy() F.bobber = nil end
            F.catches += 1
            vdelay(F.creditDelay, function() W.credit(function(g) return g.Type == 26 end, 1) end)
        end
        return true
    end
end

function F.showPrompt(on)
    F.promptShown = on
    local pg = W.playerGui
    if F.layout == "legacy" then
        local inst = pg:FindFirstChild("_INSTANCES") or node("Folder", "_INSTANCES", pg)
        local gui = inst:FindFirstChild("FishingGame") or node("ScreenGui", "FishingGame", inst, {Enabled = true})
        local bar = gui:FindFirstChild("GameBar") or node("Frame", "GameBar", gui, {Visible = true})
        gui.Enabled = on
        bar.Visible = on
    else
        local gui = pg:FindFirstChild("Main") or node("ScreenGui", "Main", pg, {Enabled = true})
        local frame = gui:FindFirstChild("Fishing") or node("Frame", "Fishing", gui, {Visible = true})
        local label = frame:FindFirstChild("Instruction")
            or node("TextLabel", "Instruction", frame, {Visible = true, Text = "Keep tapping to reel!", TextTransparency = 0})
        frame.Visible = on
        local _ = label
    end
end

return F
