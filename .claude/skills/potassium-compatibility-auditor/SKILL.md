---
name: potassium-compatibility-auditor
description: Check which executor (Potassium) and Roblox client APIs VY AutoRank relies on, their identity boundaries, fallbacks and cleanup. Use when a feature silently does nothing, an executor function may be missing, before using a new executor API, or when Stop/re-execution leaves something behind.
---

# Potassium compatibility auditor

## Scope
Executor globals (`getgenv`, `setthreadidentity`, `hookfunction`, `getsenv`, `getconnections`, `setreadonly`, `gethui`, `setclipboard`, `isfile`/`readfile`/`writefile`, optional `queue_on_teleport`/`loadstring`) and the local `gcall` identity wrapper (identity 2 for game modules, then 8).

## Prerequisites
- `rg -n "getgenv|setthreadidentity|hookfunction|getsenv|getconnections|setreadonly|gethui|setclipboard|isfile|readfile|writefile|queue_on_teleport|loadstring" <source>`
- Handoff section 7 capability table.

## Safe read-first workflow
1. For each API: where used, guarded by `type(x) == "function"`?, behaviour when absent (must degrade visibly, not crash), and what Stop restores.
2. `gcall` is project code, not an executor global; model it as such in any analyzer config.
3. Never add Studio-only or another executor's private functions. Never assume an API exists because a public hub uses it.
4. Live probes must be minimal, read-only and user-run; give the user the exact one-liner and the expected output.

## Output
Capability table: API | used at | guard | absent behaviour | cleanup on Stop | status.

## Offline check
`VY/tests/lune/harness.luau` builds a fake environment; remove one API from `makeEnv` and run `smoke.luau` to see the degraded path (mocked runtime only).

## Redaction / exit criteria
No credentials or account files in output. Done when every used API has a guard and an absent-API behaviour.

## Worked example
`hookfunction` (speed hook): guarded at `installSpeedHook`; absent → one log line, feature off; Stop does not unhook (known: handoff BUG-18, P2-02).
