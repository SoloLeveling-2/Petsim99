"""v5.2 module framework: registration, defaults, stats, worker isolation, cleanup, chips."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run_modules, bundle_text, lua54, run

src = bundle_text()
# Structural invariants of the core hooks.
assert src.count("local Modules: any = {list = {}, byId = {}}") == 1
assert src.index("local Modules: any") < src.index("local function stop()"), "registry must precede lifecycle"
for hook in ("pcall(Modules.cleanupAll", "pcall(Modules.pauseAll", "pcall(Modules.startAll",
             "pcall(Modules.recheckAll", "pcall(Modules.onSetting", "pcall(Modules.buildUI",
             "pcall(Modules.render", "Modules.worker(threadGeneration)", "Modules=Modules"):
    assert hook in src, hook
assert "AutoOpenMailbox" not in src and "loadstring(game:HttpGet(" not in src
# The whole bundle must still be Lua 5.4 syntax after stripping local type annotations.
run("return function() " + lua54(src) + " end", "bundle-syntax")

run_modules(r'''
local m = Modules.define({id = "demo", interval = 2, defaults = {DemoToggle = false, DemoLimit = 3},
    features = {{key = "DemoToggle", name = "Demo", status = "UNVERIFIED"}},
    active = function() return Config.DemoToggle end,
    tick = function()
        local ok = Modules.call("demo", "ping", "Demo_Ping", {1}, true, 5)
        if ok then Modules.note("demo", "ping", "confirmed", "pong") end
    end})
assert(Config.DemoToggle == false and Config.DemoLimit == 3, "defaults merged")
Config.DemoLimit = 9
Modules.define({id = "demo2", defaults = {DemoLimit = 1}})
assert(Config.DemoLimit == 9, "existing (saved) value wins over a later default")
assert(Modules.define({id = "demo"}) == m, "duplicate ids return the original")

-- Chips: module features, core keys, unknown keys, runtime unavailability.
assert(Modules.statusFor("DemoToggle") == "UNVERIFIED")
assert(Modules.statusFor("AutoRank") == "VERIFIED")
assert(Modules.statusFor("InfinitePetSpeed") == "EXPERIMENTAL")
assert(Modules.statusFor("NoSuchKey") == nil)
state.modules.demo.available = false
assert(Modules.statusFor("DemoToggle") == "UNAVAILABLE")
state.modules.demo.available = true

-- Inactive modules never send anything.
assert(tickModule("demo") == false)
assert(sent("Demo_Ping") == 0)
Config.DemoToggle = true
fake.responses.Demo_Ping = true
tickModule("demo")
assert(sent("Demo_Ping") == 1)
local row = Modules.stat("demo", "ping")
assert(row.attempted == 1 and row.accepted == 1 and row.confirmed == 1)
-- Rate limit: an immediate second tick is refused by the cooldown.
tickModule("demo")
assert(sent("Demo_Ping") == 1 and row.attempted == 1)
advance(6)
fake.responses.Demo_Ping = false
tickModule("demo")
assert(row.attempted == 2 and row.failed == 1 and row.confirmed == 1, "a false response is not success")
advance(6)
fake.responses.Demo_Ping = nil
tickModule("demo")
assert(row.failed == 2 and state.failures["mod:demo"].count == 1, "missing remote is a feature failure")

-- A throwing module is isolated by the worker and backs off after repeated errors.
Config.DemoToggle = false
local calls = 0
Modules.define({id = "boom", interval = 1, tick = function() calls = calls + 1 error("kaboom") end})
state.running = true
local generation = state.generations
local loops = 0
local realWait = task.wait
task.wait = function(s) loops = loops + 1 advance(s) if loops > 40 then state.shutdown = true end end
Modules.worker(generation)
task.wait = realWait
assert(calls >= 1 and calls <= Config.MaxErrorsPerFeature, "unhealthy module stops ticking: " .. calls)
assert(state.failures["mod:boom"].disabled == true)
assert(Modules.cleaned == true, "worker exit runs cleanup once")

-- Report lines include attempted/accepted/confirmed counts.
local text = table.concat(Modules.reportLines(), "\n")
assert(text:find("demo.ping attempted=3 accepted=1 confirmed=1 failed=2", 1, true), text)

-- Protected pets: unknown directory entries, huge, titanic, shiny, locked, listed UIDs.
fake.clients.Directory = {Pets = {Cat = {}, ["Huge Cat"] = {huge = true}, ["Titanic Cat"] = {titanic = true}}}
assert(Modules.isProtectedPet("a", {id = "Cat"}) == false)
assert(Modules.isProtectedPet("a", {id = "Huge Cat"}) == true)
assert(Modules.isProtectedPet("a", {id = "Titanic Cat"}) == true)
assert(Modules.isProtectedPet("a", {id = "Cat", sh = true}) == true)
assert(Modules.isProtectedPet("a", {id = "Cat", _lk = true}) == true)
assert(Modules.isProtectedPet("a", {id = "Unknown"}) == true)
Config.ProtectedPetUids = {"keep"}
assert(Modules.isProtectedPet("keep", {id = "Cat"}) == true)

-- Movement helper respects the shared lease and the hatch window.
assert(leaseMovement("farm", 30))
local ran = false
assert(Modules.withMovement("mod:x", 5, true, function() ran = true end) == false and not ran)
clearMovement("farm")
assert(Modules.withMovement("mod:x", 5, true, function() ran = true end) == true and ran)
assert(movementAvailable("farm"), "lease released after the action")
print("PASS framework: defaults, chips, stats, rate limit, isolation, cleanup, protection, movement")
''', names=[], name="framework")
print("PASS test_framework")
