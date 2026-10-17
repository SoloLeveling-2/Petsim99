# VY AutoRank v1.1.9 — release notes

Date: 2026-10-17. File: `VY/VY_AutoRank-v1.1.9.luau` (CRLF, 4,804 lines, SHA-256 `8F637EB9E367A0CB5E5A431834598F1FBE1613D6EDABA0FEB133C240B408D545`).
Base: v1.1.8 (`5E623657…2F69`). Built by `python3 -I VY/tools/patch_v119.py VY/VY_AutoRank-v1.1.8.luau out.luau` from 5 exact, single-match edits. The rebuild is byte-identical. All other v1.1.8 behaviour is unchanged.

Status: **Implemented, Unverified** live. Offline: **Verified Working (mocked Lune runtime)**. 25/25 checks pass on v1.1.9 (`luau-compile` and 24 scenarios, two full runs). On v1.1.8 exactly the 2 new identity scenarios fail. `luau-compile` passes. `luau-analyze` gives the v1.1.8 diagnostics (line numbers shift) plus 2 "unknown global `getthreadidentity`" notes, the same kind the other executor globals get. Selene: 0 errors, the same 6 warnings.

## Fix

| # | Area | v1.1.8 behaviour (reproduced offline) | v1.1.9 behaviour | Scenario |
|---|---|---|---|---|
| 1 | Identity | `gcall()` ran game code at identity 2, then always set identity **8**. A `gcall` made inside another `gcall` left the outer call at 8, after both a normal and an erroring inner call. On an executor whose threads run at 7, every VY thread was raised to 8 after its first game call (mock: all 1,688 GUI writes at 8). | `gcall()` reads `getthreadidentity()` first and restores that value. If the executor has no `getthreadidentity`, it falls back to 8 (the old behaviour). Nested calls stay at 2, and an executor's own identity is kept. | `identity-nested-gcall`, `identity-executor-7` |

**What this changes live.** v1.1.8 never nests `gcall`: all 46 call sites were checked, and the only two VY closures it wraps (`directoryTable`, `petEuids`) make no inner `gcall`. No `gcall` runs on a game thread either: the speed and magnet hooks never call it. So the fix is hardening for future code, such as an event module that wraps a VY helper. Live behaviour only differs if Potassium's threads do **not** start at identity 8. VY's startup console line shows this: `VY AutoRank v1.1.x starting (identity N)`. If it says 8, v1.1.8 and v1.1.9 behave the same.

The executor-7 scenario also confirms that every one of the 1,056 game-module calls in the run happened at identity 2: VY never calls the game outside `gcall`.

## Install (user action, no admin rights)
Same procedure as `P0-01_DEPLOYMENT_AND_FISHING.md`. Put exactly one copy in the Potassium autoexec folder and check its SHA-256 against the value above. The hub title should say `VY AutoRank v1.1.9`. Please also run `.\Verify-Handoff.ps1 -SourcePath <path to v1.1.9>` on the PC. Anchors for `gcall` may need updating.

## Rollback
Reinstall v1.1.8 (`VY/VY_AutoRank-v1.1.8.luau`, `5E623657…2F69`). The saved-file format is unchanged.
