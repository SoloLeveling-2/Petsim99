"""Run every VY offline scenario against one source file.

Usage:
    python3 VY/tests/run_tests.py [path/to/VY_AutoRank.luau] [expected version]

Needs Lune 0.10.x (set LUNE=/path/to/lune or have `lune` on PATH) and, for the
compile step, luau-compile (LUAU_COMPILE=/path or on PATH; skipped if absent).
These are mocked-runtime checks: they exercise the real script in the real Luau
VM against a fake PS99 world. They do NOT prove live Roblox/Potassium behavior.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "VY", "source", "VY_AutoRank-v1.1.7.luau")
EXPECTED = sys.argv[2] if len(sys.argv) > 2 else None
LUNE = os.environ.get("LUNE") or shutil.which("lune")
COMPILE = os.environ.get("LUAU_COMPILE") or shutil.which("luau-compile")
LUNE_DIR = os.path.join(ROOT, "VY", "tests", "lune")

SCENARIOS = [
    ("smoke", ["smoke.luau", SOURCE] + ([EXPECTED] if EXPECTED else [])),
    ("crystal-flow", ["crystal_flow.luau", SOURCE]),
    ("crystal-travel", ["crystal_travel.luau", SOURCE]),
]
for edge in ["slow-replication", "no-credit", "refused", "not-ready", "stars-keys"]:
    SCENARIOS.append(("crystal-" + edge, ["crystal_edge.luau", SOURCE, edge]))
SCENARIOS += [
    ("fishing-current-prompt", ["fishing_flow.luau", SOURCE, "current"]),
    ("fishing-legacy-gamebar", ["fishing_flow.luau", SOURCE, "legacy"]),
    ("fishing-cross-world", ["fishing_flow.luau", SOURCE, "current", "travel"]),
]


def main():
    data = open(SOURCE, "rb").read()
    print("source:", SOURCE)
    print("sha256:", hashlib.sha256(data).hexdigest().upper(), "| bytes", len(data), "| lines", data.count(b"\n"))
    results = []
    if COMPILE:
        p = subprocess.run([COMPILE, "--binary", SOURCE], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        results.append(("luau-compile", p.returncode == 0, p.stderr.strip()[:300]))
    else:
        results.append(("luau-compile", None, "luau-compile not found"))
    if not LUNE:
        print("SKIP all Lune scenarios: set LUNE=/path/to/lune")
        return 1
    for name, args in SCENARIOS:
        script = os.path.join(LUNE_DIR, args[0])
        started = time.time()
        p = subprocess.run([LUNE, "run", script] + [os.path.abspath(a) if a == SOURCE else a for a in args[1:]],
                           cwd=ROOT, capture_output=True, text=True, timeout=900)
        fails = [line for line in p.stdout.splitlines() if line.startswith("FAIL")]
        oks = sum(1 for line in p.stdout.splitlines() if line.startswith("ok"))
        ok = p.returncode == 0 and not fails
        detail = f"{oks} checks" + ("" if ok else "; " + "; ".join(fails[:5]) + (p.stderr.strip()[-300:] if p.stderr.strip() else ""))
        results.append((name, ok, detail + f" ({time.time() - started:.1f}s)"))
    width = max(len(r[0]) for r in results)
    for name, ok, detail in results:
        status = "SKIP" if ok is None else ("PASS" if ok else "FAIL")
        print(f"{status}  {name.ljust(width)}  {detail}")
    failed = [r for r in results if r[1] is False]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed" + (" (mocked runtime, not live PS99)" if not failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
