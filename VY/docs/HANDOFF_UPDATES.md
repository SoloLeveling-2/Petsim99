# Updates to apply to `HANDOFF_TO_CLAUDE.md` (handoff Rule 16)

The permanent handoff lives on the user's PC, out of reach of this cloud session. These are the status and roadmap changes to copy into it. Statuses use the handoff taxonomy; "mocked Lune" means the real Luau VM running the whole file against a fake PS99 world (`VY/tests`), not Roblox.

## Section 2 — current status rows
- **Delivered source:** add v1.1.9 (`VY/VY_AutoRank-v1.1.9.luau`, 4,804 lines, CRLF, SHA-256 `8F637EB9…D545`, built from v1.1.8 by `VY/tools/patch_v119.py`). Status: Implemented, Unverified live. Compile verified. 25/25 offline checks pass (`luau-compile` and 24 scenarios). It contains v1.1.8 (`VY/VY_AutoRank-v1.1.8.luau`, built from v1.1.7 by `VY/tools/patch_v118.py`) plus the `gcall` identity fix.
- **Isolated behaviour suites:** add a second, independent suite. `python3 VY/tests/run_tests.py <file>` runs `luau-compile` and 24 scenarios (Verified Working, mocked Lune): 22 whole-file and identity scenarios plus the two probe recorders. It does not replace `Verify-Handoff.ps1` (254 extraction checks). Run that one on v1.1.9 with `-SourcePath`; anchors for changed functions (`gcall`) may need updating.
- **Installed autoexec:** unchanged (Broken v1.1.6 per the handoff audit; not re-inspected — PC not reachable from cloud).

## Section 3 — feature records
- **F14 Crystal:** integrated loop "Verified Working (mocked Lune, whole file)" for:
  - setup gate, pet pause, World 1 trip with VM replacement, pad, no-arg opens, ≤10 per burst;
  - credit wait, rotation, reserve, refusal, no-credit, release, return;
  - rank-up re-pin, stars-complete wait, travel deadline, key-count resync, diamond-holder protection (v1.1.8).

  Live status stays Implemented, Unverified. Bugs list: remove "key estimate doesn't increase" (fixed in v1.1.8). Add "held quests surviving a rank-up is unknown live".
- **F15/F16 Fishing transaction:** "Verified Working (mocked Lune, whole file)" for:
  - a complete normal-Fishing transaction with the current prompt and with the legacy GameBar, in the same world and cross-world (two VM replacements);
  - the v1.1.8 visit-budget and debris-scan fixes.

  Live status stays Partially Working. New open risks from review: fishing-04 re-cast after a prompt flicker, fishing-05 instance flag before model replication, fishing-06 single false tap reply aborts the visit.
- **F18 controls/fairness:** the visit budget now counts from the first EXECUTE tick and defers only at an idle stage (v1.1.8).
- **F19 persistence:** Stop before restore no longer writes the file (v1.1.8). The same-account multi-process race and non-atomic writes remain (P0-03).
- **F21 GUI:** the Crystal status line is shown while the mode is ON (v1.1.8).

## Section 12 — debugging register (new rows)
| ID | Summary | Root cause | Status |
|---|---|---|---|
| BUG-20 | Crystal false sticky halt near a quest's end | Burst clamped to items left; one zero-drop key looked like "no credit" | Fixed in v1.1.8; mocked Lune verified |
| BUG-21 | World round trip on every Crystal rank-up | Pins mismatch released the hold; same-tick `checkWorld` sent the player to the best world | Fixed v1.1.8; mocked |
| BUG-22 | Keys spent after the rank's stars are complete | No stars-complete check in `Crystal.inspect`/`openTick` | Fixed v1.1.8; mocked |
| BUG-23 | Crystal hold outside World 1 never times out | No travel deadline | Fixed v1.1.8 (5 min, sticky); mocked |
| BUG-24 | Duplicate/early copy overwrites the account file | `Stop()` persisted before `restoreStateFile` | Fixed v1.1.8; mocked |
| BUG-25 | Cross-world minigame visit defers before fishing | Visit budget counted from transaction start | Fixed v1.1.8; mocked |
| BUG-26 | Bite missed when `__DEBRIS` > 256 children | Scan read the oldest 256 | Fixed v1.1.8; mocked |
| BUG-27 | `gcall` always restored identity 8: a nested gcall left the outer call at 8; an executor below 8 was raised to 8 | Hardcoded `IDENTITY_EXEC` on restore | Fixed v1.1.9 (restores `getthreadidentity()`); mocked. No nested gcall exists in v1.1.8, so live impact only if Potassium threads start below 8 |
| BUG-28 | Probe recorder silently dropped the game's request when an argument was an Instance | `GetFullName()` colon call inside the `__namecall` hook replaced the namecall method | Fixed in both probes (2026-10-17); mocked |

## Section 15 — tooling
Replace the provisional table with `VY/docs/TOOLING_AUDIT.md` (cloud environment). The six skills now exist under `.claude/skills/` in the GitHub repo. Copy them into the PC project if Claude Code is used there.

## Section 17 — roadmap
- **P0-01:** next step unchanged: user-run install + one Fishing observation. Use v1.1.9 (or v1.1.8). The startup console line `starting (identity N)` also tells whether BUG-27 mattered live (it did only if N is not 8). Procedure: `VY/docs/P0-01_DEPLOYMENT_AND_FISHING.md`.
- **P1-03 Crystal:** offline acceptance done (mocked). Live: one key, then one small burst, then observe a rank-up.
- **P1-04 build:** `VY/tools/patch_v118.py` rebuilds v1.1.8 byte-identically from the frozen v1.1.7, and `VY/tools/patch_v119.py` rebuilds v1.1.9 from v1.1.8. They are the portable, deterministic build steps.
