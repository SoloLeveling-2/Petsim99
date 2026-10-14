---
name: multi-instance-performance-profiler
description: Measure VY AutoRank's CPU, memory, loop and remote rates for one and five Roblox clients before tuning anything. Use when the user reports lag with several clients, before adding a loop/listener/scan, or when comparing two builds' cost.
---

# Multi-instance performance profiler

## Scope
Per-client loop cadence (controller 1 s / 0.2 s in minigames, farm 0.25 s, hatch 0.75 s, craft 4 s, events 3 s, flags 3 s, Crystal 0.1 s, GUI 0.5 s, persist 60 s), remote rates and Windows process CPU/RAM for ~5 clients.

## Rules
- No invented percentages. Report measured numbers with duration, hardware, Roblox/Potassium build and source hash.
- Same workload before/after (same zone, pet count, settings, time window). Redact player names/IDs.
- Every new continuous task needs a cost estimate across five clients (handoff Rule 11).

## Workflow
1. Offline: count requests per virtual minute from the Lune harness (`W.calls` in `VY/tests/lune/vy_world.luau`) to spot request storms; this measures the script's own pacing only.
2. Live (user-run): Windows `Get-Process RobloxPlayerBeta | Select Id,CPU,WorkingSet64` sampled every 10 s for 5 min per scenario (idle, farming, Crystal, minigame); compute CPU% from CPU-second deltas.
3. Change one hotspot at a time; re-measure the same scenario.

## Output
Table: scenario | clients | duration | avg CPU% | peak working set | requests/min | notes. Store in `VY/docs/PERFORMANCE.md`.

## Exit criteria
A before/after pair on the same scenario, or an explicit "not measured" with the reason.

## Worked example
Offline: Crystal flow sends ~1 chest request per ~0.35 virtual s inside a burst, at most 10 before replicated credit (`crystal_edge.luau slow-replication`). That is script pacing, not server acceptance.
