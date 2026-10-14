---
name: regression-test-engineer
description: Reproduce a VY AutoRank defect first (red), fix it, then rerun the whole offline suite (green) against the exact delivered file. Use for any VY bug fix or behaviour change, before shipping a new VY_AutoRank version, or when someone claims a fix works.
---

# Regression test engineer (VY AutoRank)

## Suites in this repo (mocked runtime: real Luau VM, fake PS99 world)
`python3 VY/tests/run_tests.py <source.luau> [expected version]` with `LUNE=/path/to/lune` and optionally `LUAU_COMPILE=/path/to/luau-compile`. Runs:
- `smoke.luau` — start, ordinary work, same-VM re-execution, GUI X/Stop, quiet after Stop.
- `crystal_flow.luau` — integrated Crystal mode in World 1 with invariant probes.
- `crystal_travel.luau` — World 2 → World 1 → World 2 with VM replacement per teleport.
- `crystal_edge.luau <scenario>` — slow-replication, no-credit, refused, not-ready, stars-keys.
The user's local 254-check suite (`Verify-Handoff.ps1`, Windows) is separate; ask the user to run it with `-SourcePath` on any new build. Never add its counts to ours.

## Workflow
1. Write the scenario that shows the defect against the unchanged file; confirm it FAILS for the stated reason.
2. Make the smallest source change; keep CRLF line endings (the delivered file is CRLF) and bump `VERSION`.
3. Run the targeted scenario (green), then the full suite, `luau-compile`, and `luau-analyze` (compare diagnostic counts to the baseline; the full file is not type-clean).
4. Record red/green output, hashes and limits in `VY/docs/ENGINEERING_LOG.md`.

## Rules
- Tests assert user-visible outcomes (requests sent, Save deltas, reserve kept), not implementation details.
- Avoid timing races in assertions: probe invariants at the moment of the request (see the hold probe in `crystal_flow.luau`).
- A green offline run is "Verified Working (mocked Lune runtime)" at most; gameplay stays "Implemented, Unverified" until a live run.

## Exit criteria
Red before, green after, full suite green, compile OK, log entry written.

## Worked example
Race found while writing `crystal_flow.luau`: checking held-quest progress after the halt failed 1/3 runs because farming resumes immediately after release. Fix: wrap the fake server handlers and record any farm/hatch request while `State.crystal.hold` is true.
