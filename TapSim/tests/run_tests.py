"""Run every Tap Simulator REBORN helper scenario against one source file.

Usage:
    python TapSim/tests/run_tests.py [path/to/TapSim_Reborn.luau]

Needs Lune 0.10.x (set LUNE=/path/to/lune or have `lune` on PATH). These are mocked-runtime
checks: the real script runs in the real Luau VM against a fake game. They do NOT prove
the live game accepts the requests.
"""
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "TapSim", "TapSim_Reborn.luau")
LUNE = os.environ.get("LUNE") or shutil.which("lune")
LUNE_DIR = os.path.join(ROOT, "TapSim", "tests", "lune")

SCENARIOS = [("smoke", ["smoke.luau", SOURCE])]
for case in ["late-load", "silent-taps", "worker-restart", "offline-later", "stand-spot"]:
    SCENARIOS.append((case, ["edge.luau", SOURCE, case]))


def main():
    if not LUNE:
        print("SKIP: set LUNE=/path/to/lune or put lune on PATH")
        return 1
    print("source:", SOURCE)
    results = []
    for name, args in SCENARIOS:
        started = time.time()
        p = subprocess.run([LUNE, "run", os.path.join(LUNE_DIR, args[0])] + args[1:],
                           cwd=ROOT, capture_output=True, text=True, timeout=900)
        lines = p.stdout.splitlines()
        fails = [line for line in lines if line.startswith("FAIL")]
        oks = sum(1 for line in lines if line.startswith("ok"))
        ok = p.returncode == 0 and not fails
        detail = f"{oks} checks" + ("" if ok else "; " + "; ".join(fails[:5]) + p.stderr.strip()[-300:])
        results.append((name, ok, f"{detail} ({time.time() - started:.1f}s)"))
    width = max(len(r[0]) for r in results)
    for name, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name.ljust(width)}  {detail}")
    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed (mocked runtime, not the live game)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
