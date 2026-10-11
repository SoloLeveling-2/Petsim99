#!/usr/bin/env python3
"""Assemble the single-file RankPilot X bundle.

The core (src/core/RankPilot_X_core.lua) is the v5.1 engine plus v5.2 hooks.
Every file in src/modules/ is spliced, in file-name order, at the marker line
``-- @@RANKPILOT_MODULES@@`` in the core.  The result is written to
dist/RankPilot_X_v5_2.lua and copied to the repository root so it can be
pasted into an executor as one file.

Usage:
    python3 tools/build.py          # build
    python3 tools/build.py --check  # fail if dist/ is stale
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "src" / "core" / "RankPilot_X_core.lua"
MODULES = ROOT / "src" / "modules"
DIST = ROOT / "dist" / "RankPilot_X_v5_2.lua"
REPO_COPY = ROOT.parent / "RankPilot_X_v5_2.lua"
MARKER = "-- @@RANKPILOT_MODULES@@"


def assemble() -> str:
    core = CORE.read_text()
    if core.count(MARKER) != 1:
        raise SystemExit(f"expected exactly one module marker in {CORE}")
    parts = []
    for path in sorted(MODULES.glob("*.lua")):
        body = path.read_text().rstrip() + "\n"
        code_lines = [l for l in body.splitlines() if l.strip() and not l.strip().startswith("--")]
        if not code_lines or code_lines[0].strip() != "(function()" or code_lines[-1].strip() != "end)()":
            raise SystemExit(f"{path.name}: a module must be exactly one (function() ... end)() block")
        # `do ... end` keeps consecutive `(function() ... end)()` blocks from
        # parsing as one chained call: `(f)()(g)()` would call nil at runtime.
        parts.append(f"-- ==== module: {path.name} ====\ndo\n{body}end\n")
    bundle = core.replace(MARKER, "".join(parts).rstrip("\n"))
    if "\t" in bundle:
        raise SystemExit("tabs found in bundle; use spaces")
    return bundle


def main() -> int:
    bundle = assemble()
    if "--check" in sys.argv:
        stale = [p for p in (DIST, REPO_COPY) if not p.exists() or p.read_text() != bundle]
        if stale:
            print("STALE:", ", ".join(str(p) for p in stale))
            return 1
        print("bundle up to date")
        return 0
    DIST.parent.mkdir(parents=True, exist_ok=True)
    DIST.write_text(bundle)
    REPO_COPY.write_text(bundle)
    print(f"wrote {DIST} ({len(bundle.splitlines())} lines)")
    print(f"wrote {REPO_COPY}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
