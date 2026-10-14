---
name: cross-world-state-debugger
description: Follow one VY AutoRank transaction (minigame, Crystal trip, area/rebirth) through persisted intent, request lease, world arrival, instance, return and restore. Use when travel, fishing/digsite visits, Crystal World-1 trips or restores stall, time out, loop or run old code after a teleport.
---

# Cross-world state debugger

## Scope
`worldTeleport`/`checkWorld`/`navigationDestination`, `MinigameController` phases (PREPARE … RESUME, RECOVERY/ABORTED), Crystal hold/travel, `AreaProgression` leases, per-account JSON (`VY_AutoRank_State_<UserId>.json`) and the autoexec re-run after every place teleport.

## Prerequisites
- A world teleport replaces the client VM. Only what `writeStateFile` persisted survives; the installed autoexec copy is what runs next (check its version first; handoff P0-01).
- Handoff section 9: the 11 mandatory edge cases.

## Safe read-first workflow
1. Identify the running build: GUI title `VY AutoRank vX`, console `VY AutoRank vX starting`, `getgenv().VyAutoRank.Version`. Before AND after a teleport.
2. Ask for a redacted trace: phase, operation key and age, world before/after, retries per leg, last failure, tap count/progress for minigames, crystal status line.
3. Map the stall to one boundary: request not returned (lease held), accepted but no arrival (45 s switch timeout), arrival but no instance, instance but no progress (75 s), exit/return/restore.
4. Reproduce offline: `VY/tests/lune/crystal_travel.luau` shows how to model a teleport as kill-VM + re-run with the same files; add a scenario for the failing boundary first (red), then fix.

## Never
Clear a pending lease or ABORTED ownership just to make the UI resume; resend a request whose reply is still pending; treat a remote's `true` as arrival or credit.

## Output
Phase timeline with redacted aliases, the boundary, and the proposed one-boundary change.

## Exit criteria
The failing boundary is reproduced offline (or clearly marked live-only) and the 11 cases still hold.

## Worked example
Crystal trip (mocked runtime): World 2 → toggle → pets paused → `World1Teleport` → VM2 restores `crystal.enabled` → opens → reserve halt → `Restore` → `World2Teleport` → VM3 farms. Two teleports exactly; see `crystal_travel.luau`.
