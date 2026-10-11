"""Run the full-bundle Luau smoke test (tests/v52/lune/smoke.luau) with Lune.

Lune executes the real Luau VM, so this catches runtime errors the Lua 5.4
slice tests cannot (Luau-only semantics, chained-call parsing, whole-file
bootstrap). It uses a mock Roblox/PS99 world; it is not a live game test.
Set LUNE=/path/to/lune if lune is not on PATH.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
lune = os.environ.get("LUNE") or shutil.which("lune")
if not lune:
    print("SKIPPED: lune not found (set LUNE=/path/to/lune)")
    sys.exit(0)
proc = subprocess.run([lune, "run", str(ROOT / "tests/v52/lune/smoke.luau"), str(ROOT / "dist/RankPilot_X_v5_2.lua")],
                      capture_output=True, text=True, timeout=300, cwd=ROOT)
print(proc.stdout[-6000:])
if proc.returncode != 0:
    print(proc.stderr[-4000:])
    raise SystemExit("Lune smoke test failed")
print("PASS test_lune_smoke")
