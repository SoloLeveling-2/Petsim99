# VY AutoRank v1.1.8 — release notes

Date: 2026-10-14. File: `VY/VY_AutoRank-v1.1.8.luau` (CRLF, 4,795 lines). SHA-256 is recorded in `ENGINEERING_LOG.md` and printed by `python3 VY/tests/run_tests.py`.
Base: v1.1.7 (`CDE5F944…51FC`). Built by 22 exact, single-match edits (`git diff` shows each one), so all other v1.1.7 behaviour is unchanged.

Status: **Implemented, Unverified** live. Offline: **Verified Working (mocked Lune runtime, whole file)**. 21/21 scenarios pass on v1.1.8. On v1.1.7 exactly the 9 new defect scenarios fail. `luau-compile` passes. `luau-analyze` gives the same diagnostics as v1.1.7 (line numbers shift only). Selene: 0 errors, the same 6 warnings.

## Fixes

| # | Area | v1.1.7 behaviour (reproduced offline) | v1.1.8 behaviour | Scenario |
|---|---|---|---|---|
| 1 | Crystal | With 1–2 items left, the burst is 1–2 keys. One key that drops no matching item (≈7% for potions per the wiki odds) sticky-halts the mode: "no collection credit". | Halts only after a full burst's worth of keys (10) in a row earned nothing. Waste without credit stays ≤10 keys. | `crystal-zero-drop-tail` |
| 2 | Crystal | On a rank-up that keeps both held quests, the mode releases. The same tick sends the player to the best area's world and the next tick back to World 1. | It re-checks the setup and keeps the World 1 hold (re-pins). No round trip. | `crystal-rankup` |
| 3 | Crystal | After the rank's stars are complete it keeps spending keys (41 extra in the mock), then hits a sticky halt. | Stops opening, keeps the hold and waits up to 2 minutes for the rank-up. Then it continues on the new rank, or releases without a sticky halt. | `crystal-stars-complete` |
| 4 | Crystal | If World 1 can't be reached (refused trip or AutoWorldTeleport OFF), the account idles forever with pets unequipped and every other worker held. | Gives up after 5 minutes (sticky, with the reason shown) and restores pets. With AutoWorldTeleport OFF the status says to go to World 1. | `crystal-travel-refused` |
| 5 | Crystal | When Keys Mastery keeps keys, the internal estimate drifts low, so it stops early with spare keys (140 left at a 20% keep rate, reserve 100). | Once no request was sent for 10 s (replication settled), it re-reads the live key count and stops exactly at the reserve. Newly earned keys are picked up too. | `crystal-retain-strand` |
| 6 | Crystal | While waiting for the setup, normal farming targets diamonds (double weight plus Diamonds Flags). That finishes the scarce held diamond quest before a best-area quest appears. | Only while Crystal mode is ON with spare keys, a diamond quest is held in slots 2–4 and no best-area quest is held yet: diamond targets and Diamonds Flags are skipped. Everything else farms normally. | `crystal-protect-setup` |
| 7 | Crystal | The slot came from the Save table key. | The slot comes from `goal.Stars` (what the game's quest panel uses), falling back to the key. | `crystal-stars-keys` |
| 8 | Crystal UI | The reason was visible only during a hold. | While ON, the line under the button shows `Keys N \| <status>`. | — |
| 9 | Persistence | A copy stopped while still loading wrote its unrestored defaults over the account file. Saved Minigames OFF became ON, and an in-flight transaction or pet-restore intent was lost. This happens with two autoexec copies, or a manual re-run during travel. | `Stop()` writes the file only after this run restored it. | `persist-race` |
| 10 | Identity | The replaced copy left no trace. | Console: `replacing running AutoRank vX` when a running copy is stopped by a new one. Restore log no longer prints the legacy filename. A copy stopped while loading no longer prints "client did not load". | `persist-race` |
| 11 | Minigames | The 90 s visit budget counted from transaction start, so travel and loading used it up. With "Do minigames first" OFF, a cross-world visit deferred right after its first cast with 0 catches, every time. | The budget counts from the first EXECUTE tick of the visit. A deferral waits for an idle fishing stage and never abandons a cast, bite or catch. | `fishing-slow-travel` |
| 12 | Fishing | The bite scan read only the first 256 `__DEBRIS` children. A new bubble host appended later was never seen, giving "no observed bite after cast", recovery and a 600 s cooldown. | It scans the newest 256 children first. | `fishing-busy-debris` |

## Not changed (needs live evidence first)
- Re-cast while an old fishing line still exists after the prompt flickers (review finding fishing-04). Requiring "no line before casting" could stall casting completely if the live rod keeps a hidden line, so it waits for the P0-01 observation.
- "Another instance is already active" before the own instance model replicates (fishing-05), and one `false` reply to a `Clicked` tap aborting the visit (fishing-06). Reply semantics and replication order are unknown.
- A 45 s destination timeout means a place load longer than 45 s re-sends the world request (handoff edge case 1). Real load times have not been measured.
- Key budget counts requests, not confirmed key use. The 5000-request limit and 100-key reserve are kept as before.

## Install (user action, no admin rights)
Same procedure as `P0-01_DEPLOYMENT_AND_FISHING.md`. Put exactly one copy in the Potassium autoexec folder and check its SHA-256 against the value above. Then check that the hub title says `VY AutoRank v1.1.8`. Please also run `.\Verify-Handoff.ps1 -SourcePath <path to v1.1.8>` on the PC. Its extractor anchors may need updating where a function body changed (Crystal, minigame EXECUTE, bubble scan, Stop, main).

## Rollback
Reinstall v1.1.7 (`VY/source/VY_AutoRank-v1.1.7.luau`, hash `CDE5F944…51FC`). No saved-file format change: v1.1.8 writes the same JSON fields.
