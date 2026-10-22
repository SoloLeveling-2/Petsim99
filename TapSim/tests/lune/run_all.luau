--!nocheck
-- Runs all six scenarios (each in its own Lune process) and prints one PASS/FAIL line each.
-- Needs only Lune, no Python. From the folder that holds TapSim\:
--   Windows:  .\tools\lune.exe run TapSim/tests/lune/run_all.luau
--   Linux:    lune run TapSim/tests/lune/run_all.luau
-- Optional: run_all.luau <script path> <lune path>. The lune path defaults to $LUNE, then
-- tools/lune.exe or tools/lune if present, then "lune" on PATH.
-- Mocked runtime: a green run does not prove the live game accepts the requests.
local fs = require("@lune/fs")
local process = require("@lune/process")

local source = process.args[1] or "TapSim/TapSim_Reborn.luau"
local lune = process.args[2] or process.env.LUNE
if not lune then
    for _, candidate in ipairs({ "tools/lune.exe", "tools/lune" }) do
        if fs.isFile(candidate) then lune = candidate break end
    end
end
lune = lune or "lune"

local scenarios = { { "smoke", { "run", "TapSim/tests/lune/smoke.luau", source } } }
for _, case in ipairs({ "late-load", "silent-taps", "worker-restart", "offline-later", "stand-spot" }) do
    table.insert(scenarios, { case, { "run", "TapSim/tests/lune/edge.luau", source, case } })
end

print("source: " .. source .. "  lune: " .. lune .. "  (silent-taps is the slow one)")
local passed = 0
for _, scenario in ipairs(scenarios) do
    local name, args = scenario[1], scenario[2]
    local started = os.clock()
    local result = process.exec(lune, args)
    local oks, fails = 0, {}
    for line in string.gmatch(result.stdout, "[^\r\n]+") do
        if string.sub(line, 1, 2) == "ok" then oks += 1 end
        if string.sub(line, 1, 4) == "FAIL" then table.insert(fails, line) end
    end
    local ok = result.ok and #fails == 0
    if ok then passed += 1 end
    print(string.format("%s  %-15s %d checks (%.0fs)", ok and "PASS" or "FAIL", name, oks, os.clock() - started))
    for i = 1, math.min(#fails, 5) do print("      " .. fails[i]) end
    if not result.ok and #fails == 0 then print("      " .. string.sub(result.stderr, -300)) end
end
print(string.format("\n%d/%d passed (mocked runtime, not the live game)", passed, #scenarios))
process.exit(passed == #scenarios and 0 or 1)
