--!nocheck
-- VY Camp Eggs (Diamond Mountain) offline scenarios (mocked runtime, not live PS99).
-- Usage: lune run VY/tests/lune/dm_campeggs.luau <script.luau> <scenario>
-- scenarios: dry-run | hatch | nearest | trail-egg | far | keep-coins | out-of-coins | refused
--            no-effect | not-inside | stop
-- The fake server follows probe run 3 (2026-10-18, sent by ZapHub):
--   CustomEggs_Hatch("<model name>", n) -> true, nil; TrailCoins go down (~29,813 per
--   Boulder Ridge Egg), Save.PurchasedEggs["Boulder Ridge Egg"] goes up by n.
-- Camp eggs are Workspace.__THINGS.CustomEggs.<uid> models with DM_EggId = "<egg name>";
-- trail eggs also carry DM_TrailEgg = <trail> and are left alone.
local process = require("@lune/process")
local luneTask = require("@lune/task")
local R = require("./roblox_mock")
local W = require("./vy_world")
local H = require("./harness")
local Vector3, CFrame = R.Vector3, R.CFrame

local path, scenario = process.args[1], process.args[2] or "hatch"
local function said(text) return #H.console(text) > 0 end
local source = H.loadSource(path)
if scenario ~= "dry-run" then
    source = source:gsub("DRY_RUN = true,", "DRY_RUN = false,", 1)
end
if scenario == "keep-coins" then
    source = source:gsub("KEEP_COINS = 0,", "KEEP_COINS = 100000,", 1)
end
H.source = source

W.build({ rank = 12, keys = 20, goals = {} })
W.instance = scenario ~= "not-inside" and "DiamondMountain" or nil
W.root.CFrame = CFrame.new(0, 5, 0) -- GetMaxHatch is 3 in the fake world

local PRICE = 30000
local start = ({ ["keep-coins"] = 250000, ["out-of-coins"] = 100000, hatch = 12000000 })[scenario] or 99406234
local coins = { id = "TrailCoins", _am = start }
W.save.Inventory.Currency = { c0b8 = coins, d1 = { id = "Diamonds", _am = 73512965 } }
W.save.PurchasedEggs = { ["Trailhead Egg"] = 515 }
W.save.InstanceVars = { DiamondMountain = { InstanceZones = { __Zone_1 = true, __Zone_2 = true, __Zone_3 = true } } }

local customEggs = R.Instance.new("Folder")
customEggs.Name = "CustomEggs"
customEggs.Parent = W.things
local function egg(uid, eggId, at, attrs)
    local m = R.Instance.new("Model")
    m.Name = uid
    m.Position = at
    m:SetAttribute("DM_EggId", eggId)
    for k, v in pairs(attrs or {}) do m:SetAttribute(k, v) end
    m.Parent = customEggs
    return m
end
-- Another event's custom egg right next to you: never hatched.
local other = R.Instance.new("Model")
other.Name = "Witching Egg"
other.Position = Vector3.new(2, 5, 0)
other:SetAttribute("WorldNum", 1)
other.Parent = customEggs
if scenario == "trail-egg" then
    egg("e72555ee", "Boulder Ridge Egg", Vector3.new(8, 5, 0), { DM_TrailEgg = 3, DM_TrailHugeRow = true })
elseif scenario == "far" then
    egg("385d37df", "Boulder Ridge Egg", Vector3.new(100, 5, 0))
elseif scenario == "nearest" then
    egg("ecb2a9e1", "Russet Falls Egg", Vector3.new(30, 5, 0))
    egg("385d37df", "Boulder Ridge Egg", Vector3.new(10, 5, 0))
else
    egg("385d37df", "Boulder Ridge Egg", Vector3.new(12, 5, 0))
end

local hatches, other_ = {}, {}
-- "hatch": once, something else is bought during a hatch (an upgrade): that hatch looks
-- 100x dearer. The price estimate must not stay that high.
local spikeAt = scenario == "hatch" and 2 or nil
W.handlers["CustomEggs_Hatch"] = function(uid, n, ...)
    table.insert(hatches, { uid = uid, n = n, extra = select("#", ...), t = os.clock() })
    if W.instance ~= "DiamondMountain" then return false, "Not in instance" end
    if scenario == "refused" then return false, "You need to be closer to the egg!" end
    if scenario == "no-effect" then return true, nil end
    local model = customEggs:FindFirstChild(uid)
    if not model or model:GetAttribute("DM_EggId") == nil then return false, "Unknown egg" end
    if coins._am < PRICE * n then return false, "Not enough Acorns!" end
    local eggId = model:GetAttribute("DM_EggId")
    local extra = (#hatches == spikeAt) and PRICE * n * 99 or 0
    luneTask.delay(0.5 / R.SPEED, function() -- replication delay (0.5 virtual s)
        coins._am -= PRICE * n + extra
        W.save.PurchasedEggs[eggId] = (W.save.PurchasedEggs[eggId] or 0) + n
    end)
    return true, nil
end
W.handlers["Instancing_InvokeCustomFromClient"] = function(...) table.insert(other_, { ... }) return true end

local function bought(eggId) return W.save.PurchasedEggs[eggId] or 0 end
local function allTo(uid)
    for _, h in ipairs(hatches) do if h.uid ~= uid then return false end end
    return true
end

local genv = H.newVM("camp eggs")
local handle = genv.VyCampEggs
H.check(handle ~= nil and type(handle.Stop) == "function", "global handle with Stop")

if scenario == "dry-run" then
    H.wait(30)
    H.check(#hatches == 0, "dry run hatches nothing (" .. #hatches .. ")")
    H.check(said("would hatch 3 x Boulder Ridge Egg"), "dry run names the egg and your max hatch")
    H.check(#H.console("would hatch") == 1, "the dry-run plan is printed once, not every check")
elseif scenario == "hatch" then
    H.waitFor(function() return bought("Boulder Ridge Egg") >= 30 end, 120)
    H.check(bought("Boulder Ridge Egg") >= 30, "keeps hatching the camp egg you stand at (" .. bought("Boulder Ridge Egg") .. ")")
    H.check(allTo("385d37df"), "every hatch names that egg's model")
    local amounts = true
    for _, h in ipairs(hatches) do if h.n ~= 3 or h.extra ~= 0 then amounts = false end end
    H.check(amounts, "each hatch asks for your max (3) and nothing else")
    local gap = math.huge
    for i = 2, #hatches do gap = math.min(gap, hatches[i].t - hatches[i - 1].t) end
    H.check(gap >= 1.9 / R.SPEED, "hatches are at least 2 virtual s apart")
    H.check(said("30000 TrailCoins each"), "prints what one egg costs")
    local lines = H.console("eggs hatched so far")
    H.check(#lines >= 1 and #lines <= 3, "progress is printed now and then, not every hatch (" .. #lines .. " lines)")
    local mark = bought("Boulder Ridge Egg")
    H.waitFor(function() return bought("Boulder Ridge Egg") >= mark + 6 end, 30)
    H.check(bought("Boulder Ridge Egg") >= mark + 6 and hatches[#hatches].n == 3,
        "one dear-looking hatch does not shrink later hatches")
    H.check(#other_ == 0, "sends nothing but the hatch")
    H.check(W.save.PurchasedEggs["Trailhead Egg"] == 515, "other eggs untouched")
elseif scenario == "nearest" then
    H.waitFor(function() return #hatches >= 3 end, 60)
    H.check(#hatches >= 3 and allTo("385d37df"), "hatches the nearest camp egg (Boulder Ridge, 10 studs), not Russet Falls (30)")
elseif scenario == "trail-egg" then
    H.wait(40)
    H.check(#hatches == 0, "a trail egg (DM_TrailEgg) is never hatched (" .. #hatches .. ")")
    H.check(said("stand next to a Diamond Mountain camp egg"), "status says where to stand")
elseif scenario == "far" then
    H.wait(40)
    H.check(#hatches == 0, "an egg 100 studs away is not hatched (" .. #hatches .. ")")
    H.check(said("stand next to a Diamond Mountain camp egg"), "status says where to stand")
    W.root.CFrame = CFrame.new(95, 5, 0) -- the player walks over
    H.waitFor(function() return #hatches >= 1 end, 60)
    H.check(#hatches >= 1 and allTo("385d37df"), "hatches once you stand at it")
elseif scenario == "keep-coins" then
    -- 250,000 coins, keep 100,000: 3 eggs (unknown price yet), then 2, then none.
    H.wait(60)
    H.check(coins._am >= 100000, "never spends below KEEP_COINS (" .. coins._am .. ")")
    H.check(bought("Boulder Ridge Egg") == 5, "hatched what it could afford above the reserve (" .. bought("Boulder Ridge Egg") .. ")")
    H.check(said("keeping 100000 TrailCoins"), "status says it is keeping the reserve")
    H.check(genv.VyCampEggs ~= nil, "waiting for coins is not a failure: the script keeps running")
elseif scenario == "out-of-coins" then
    -- No reserve set: 100,000 coins buy 3 eggs, then it waits for coins instead of stopping.
    H.wait(40)
    H.check(bought("Boulder Ridge Egg") == 3 and #hatches == 1, "hatched what the coins paid for, then no refused hatch (" .. #hatches .. ")")
    H.check(said("not enough TrailCoins"), "status says it waits for TrailCoins")
    H.check(genv.VyCampEggs ~= nil, "running out of coins is not a failure: the script keeps running")
    coins._am += 90000 -- farming earned more
    H.waitFor(function() return bought("Boulder Ridge Egg") == 6 end, 30)
    H.check(bought("Boulder Ridge Egg") == 6, "hatches again once you can pay (" .. bought("Boulder Ridge Egg") .. ")")
elseif scenario == "refused" then
    H.wait(80)
    H.check(#hatches == 3, "stops after three refused hatches (" .. #hatches .. ")")
    H.check(said("You need to be closer to the egg!"), "the server's reply is printed")
    H.check(genv.VyCampEggs == nil, "the script stopped itself")
elseif scenario == "no-effect" then
    H.wait(80)
    H.check(#hatches == 3, "stops after three hatches that changed nothing (" .. #hatches .. ")")
    H.check(said("did not show"), "says the hatch did not show in your save")
    H.check(genv.VyCampEggs == nil, "the script stopped itself")
elseif scenario == "not-inside" then
    H.wait(40)
    H.check(#hatches == 0, "not on Diamond Mountain: nothing is sent (" .. #hatches .. ")")
    H.check(said("not on Diamond Mountain"), "status says it waits for Diamond Mountain")
elseif scenario == "stop" then
    H.waitFor(function() return #hatches >= 1 end, 30)
    handle.Stop()
    H.wait(1)
    local mark = #hatches
    H.wait(40)
    H.check(#hatches == mark, "no hatches after Stop (" .. (#hatches - mark) .. ")")
    H.check(genv.VyCampEggs == nil, "Stop removes the global handle")
    H.runIn(genv, "second run")
    local second = genv.VyCampEggs
    H.runIn(genv, "third run")
    H.check(second ~= nil and genv.VyCampEggs ~= second and genv.VyCampEggs ~= nil, "a new run replaces the running copy")
    genv.VyCampEggs.Stop()
end
if process.env.CAMPEGGS_SHOW == "1" then for _, l in ipairs(H.printed) do print("   | " .. l) end end
H.scanErrors(scenario)
process.exit(H.finish() and 0 or 1)
