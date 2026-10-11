#!/usr/bin/env python3
"""Run every offline test (legacy v2.6-v5.1 suite plus v5.2 tests).

These are mock tests. They prove the Lua logic behaves as designed against
fake game modules; they do NOT prove compatibility with the live PS99 server.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    tests = sorted((ROOT / "tests" / "legacy").glob("*.py")) + sorted((ROOT / "tests" / "v52").glob("test_*.py"))
    failed, skipped = [], []
    for test in tests:
        proc = subprocess.run([sys.executable, "-I", str(test)], capture_output=True, text=True, cwd=ROOT)
        status = "PASS" if proc.returncode == 0 else "FAIL"
        if proc.returncode == 0 and "SKIPPED" in proc.stdout:
            status = "SKIP"
            skipped.append(test)
        print(f"{status} {test.relative_to(ROOT)}")
        if proc.returncode != 0:
            failed.append(test)
            print(proc.stdout[-2000:])
            print(proc.stderr[-4000:])
    passed = len(tests) - len(failed) - len(skipped)
    print(f"\n{passed}/{len(tests)} test files passed, {len(skipped)} skipped, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
