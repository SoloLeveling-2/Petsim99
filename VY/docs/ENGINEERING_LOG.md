# VY AutoRank — engineering log

Newest first. Each entry: what changed, why, evidence, tests, limits, rollback.

## 2026-10-17 — Event probe: one run collects everything

**Why.** The user asked what to execute to get all the missing facts. Before handing over the event probe, I compared its sections with the list of unknowns. Four gaps:
- Section 3 matched only table *names*, so this event's entries in tables every event shares (`Eggs`, `Pets`, `Currency`) never showed. Child-module tables that load lazily were skipped.
- The shared `Boosts` table matches "boost", so section 3 dumped its first 30 keys (mostly other events') and could cut off the Diamond Mountain ones.
- No executor information (functions, thread identity).
- A 120 s window was short for ten actions, and nothing warned when VY AutoRank was running. VY's own requests would mix into the recording, and it may teleport away.

**Red** (new checks in `probe_recorder.luau`, event probe): 9 FAIL.

**Change.**
- Section 0: executor name (`identifyexecutor`), thread identity, available/MISSING executor functions, and a warning if `getgenv().VyAutoRank` is alive.
- Section 3: lists every Directory table, including child modules (read via `Directory[name]`, else `require`, at identity 2). Tables over 40 entries show only this event's keys.
- New 3b: this event's entries in every table, matched by key or `DisplayName` with stricter event words, bounded to 300.
- `RECORD_SECONDS` 120 → 300, and the on-screen instructions say to skip what isn't available.
- Selene std: added `firetouchinterest` and `setnamecallmethod`.

**Green.**
- Event probe 26/26 checks, general probe 13/13.
- Full suite on v1.1.9: 25/25.
- Event probe Selene: 0 errors, 0 warnings. Compile OK.

**Limits.** Mocked runtime. The event words were chosen from the patch notes and the public API names; an entry named with none of them is still found by the recorder and the Save diff, not by 3b.

## 2026-10-17 — v1.1.9: `gcall` restores the identity it found; probe table copies; harness identity model

**Why.** The user asked to fix `gcall`'s hardcoded `setthreadidentity(8)` after a review explained the nested case. A second review point: the probe recorder formats arguments one deferred step later, so a scratch table the game clears right after sending would be logged as `{}`.

**Reachability check (all 46 `gcall`/`gval` call sites in v1.1.8).**
- Only two VY closures run under `gcall`: `directoryTable` and `petEuids`. Neither makes an inner `gcall`; `logEvery` only prints.
- The game-thread hooks (speed, magnet `GetPower`/`InstancingCmds.Get`, hatch animation) never call `gcall`.
- So the nested case is not reachable today; the fix is hardening. Live impact only if Potassium threads start below 8; the startup log line `starting (identity N)` shows it.

**Harness (mocked runtime).**
- The harness now models per-thread identity. `setthreadidentity`/`getthreadidentity` act on the current thread. `task.spawn`/`defer`/`delay` threads inherit their creator's identity. A signal handler runs at the identity of the thread that connected it.
- Default 8, so existing scenarios run as before.
- New `identity.luau` has two modes:
  - `nested`: runs the delivered `gcall` itself, cut from the file between fixed markers.
  - `executor7`: the whole file on an executor at identity 7, recording the identity of every game-module call and every GUI write.

**Red on v1.1.8.**
- `identity-nested-gcall`: after an inner `gcall` (normal and erroring) the outer call is at 8. After the outer call the thread is at 8, not the executor's 7.
- `identity-executor-7`: all 1,688 GUI writes ran at 8, none at 7.
- In the same run all 1,056 game-module calls were at 2 (VY never calls the game outside `gcall`).

**Change (v1.1.9).** `VY/tools/patch_v119.py`: 5 single-match edits to v1.1.8 (version, header, `gcall` reads `getthreadidentity()` first and restores it; 8 stays the fallback). Output `VY/VY_AutoRank-v1.1.9.luau`, SHA-256 `8F637EB9E367A0CB5E5A431834598F1FBE1613D6EDABA0FEB133C240B408D545`, 4,804 lines, CRLF. Two builds are byte-identical, and `patch_v118.py` still rebuilds v1.1.8 byte-identically.

**Green.**
- v1.1.9: 25/25 in two full runs.
- v1.1.8: 23/25, exactly the two identity scenarios. v1.1.7: 14/25, exactly its 9 documented defects plus the two identity scenarios.
- `luau-compile` OK. `luau-analyze`: the v1.1.8 diagnostics (shifted lines) plus 2 "unknown global `getthreadidentity`" (executor global). Selene: 0 errors, the same 6 warnings.

**Test fix found on the way (`crystal-slow-replication`).** It failed once in a full v1.1.9 run (11 requests), then passed 12/12 on both v1.1.8 and v1.1.9.
- Root cause: the check waited until 10 requests, then 3 virtual s, and expected still 10. The virtual clock is 40× real time, so a burst stretched past ~75 ms real by CPU load let the first 6 s credit replicate inside the wait, and VY correctly started the next burst.
- Reproduced: with the CPU loaded, the old check failed 1/8.
- Fix: probe at the moment of request 11 (the repo rule) and assert that credit had already replicated. The new check failed 0/8 under the same load.
- Mutation `CrystalBurst = 12`: the new check fails (0 credit before request 11), so it still guards the burst limit.

**Probes.** In the hook, table arguments are copied with `pcall(table.clone, …)` before the deferred formatting. The check uses `typeof`, so Instances are never copied; it gives the same result as `type` in real Roblox. A protected metatable makes `table.clone` fail; the original is kept and the request still goes through. Red on the previous probes: a scratch table cleared after sending showed as `{}` (event probe) or `table(0)` (general probe). Both are green now.

**Limits.** Mocked runtime. Roblox's identity semantics are modelled, not measured on Potassium. The table copy is one level, which is what the report prints.

**Rollback.** Install v1.1.8 again (`5E623657…2F69`). The saved-file format is unchanged.

## 2026-10-17 — Probe recorder fixes (both probes) and event-probe coverage

**Why.** A review the user pasted listed five defects in `PS99_EventProbe_DiamondMountain.luau`. Each was checked against the code. Bugs 1–3 are also in `PS99_Probe.luau` (same recorder). `VY_AutoRank` has no `__namecall` hook, so bug 1 does not affect it. Its `gcall` does hardcode identity 8 on restore (bug 3 pattern); not changed here.

**Verdicts.**
- Bug 1 (real, severe). `short()` called `v:GetFullName()` inside the hook. The colon call re-enters the hook and leaves the namecall method set to `GetFullName`. `old(self, ...)` then dispatched the game's `FireServer`/`InvokeServer` as `GetFullName`. The request was silently dropped, with no error. This happened whenever an argument was an Instance.
- Bug 2 (real). Re-hooking `old` after the window drops any `__namecall` hook another script added meanwhile.
- Bug 3 (half). The restore to a hardcoded 8 is real. "Stuck at identity 2 after an error" is not: `pcall` always returns before the restore line.
- Bug 4 (real limit). The name search stopped 3 levels deep, and a matched table printed only one level (`{...}`).
- Bug 5 (real limit). One camp's repeated children could fill the 250-row cap, and streaming/instance state was not reported.

**Red on the unchanged probes** (`tests/lune/probe_recorder.luau`; its mock models the namecall method register): event probe 9 FAIL, general probe 5 FAIL. Bug 1 showed as "got nothing": the server never received the request.

**Change.**
- Both probes:
  - The hook only copies the arguments and formats them in a `task.defer` thread. It makes no colon calls on Instances and uses `string.find` for the noise filter.
  - After the window a `recording` flag makes the hook a pass-through; it is never re-hooked.
  - `asGame` restores the identity read from `getthreadidentity()`.
- Event probe only:
  - The Save name search goes 5 levels deep; matched tables are dumped 4 levels (bounded to 400 lines).
  - New section 7: a before/after Save diff over the recording window, any field name (bounded).
  - World rows collapse repeats (digits → `#`, same parent and class) with a count, cap 400. `StreamingEnabled` and the active instance are printed. The header says to run it at base camp and at the summit.

**Green.** Both probe scenarios pass (14 and 10 checks). Both files compile (`luau-compile`). Selene: 0 errors (1 pre-existing warning, unused `HttpService` in `PS99_Probe.luau`). The full suite against v1.1.8: 23/23 (the two probe scenarios are now in `run_tests.py`). SHA-256: event probe `2A3D04A0…08461BF`, general probe `998E2696…7F52B71`.

**Limits.**
- Mocked runtime: the namecall model reproduces the documented Luau behaviour but is not Potassium.
- The recorded arguments are formatted one deferred step later, so a table the game mutates in that instant would show its new value.
- The pass-through hook stays until the client leaves the server.

**Rollback.** `git checkout c953701 -- VY/tools/` (the probes are standalone; nothing depends on them).

## 2026-10-14 — v1.1.8: 12 reproduced fixes (Crystal, Fishing scheduling, persistence)

**Why.** A five-area review workflow ran (Crystal, Fishing/P0-01, areas, consumables, lifecycle; each with two adversarial verifiers). The Crystal and Fishing reviewers finished: 6 and 7 findings, each reproduced in the reviewer's extract harness. The other agents hit the session limit and were resumed. I re-reproduced every finding I chose to fix in the **whole-file** harness before editing (red), then fixed it (green).

**Red on v1.1.7 (whole file, mocked Lune):**
- `crystal-zero-drop-tail`: sticky halt "no collection credit".
- `crystal-stars-complete`: 41 keys spent after stars complete.
- `crystal-travel-refused`: hold forever, pets unequipped.
- `crystal-retain-strand`: stops with 140 keys left at reserve 100.
- `crystal-protect-setup`: held diamond quest farmed 0 → 4 before the setup formed.
- `crystal-rankup`: one World2Teleport right after the rank-up.
- `persist-race`: saved Minigames OFF became ON.
- `fishing-slow-travel`: DEFERRED after 1 cast, 0 catches.
- `fishing-busy-debris`: ABORTED "no observed bite after cast".

**Change.** 22 exact single-match edits in `VY/tools/patch_v118.py`, which rebuilds the file byte-identically. Output: `VY/VY_AutoRank-v1.1.8.luau`, SHA-256 `5E623657F368F5E61218D30B63530575645493948AE7DC1708D0B1CB988E2F69`, 4,795 lines, CRLF. Details in `VY_AUTORANK_v1.1.8_NOTES.md`.

**Green.** 21/21 scenarios pass on v1.1.8, three consecutive runs. On v1.1.7, exactly the 9 scenarios above fail. `luau-compile` OK. `luau-analyze` diagnostics are identical to v1.1.7 apart from shifted line numbers. Selene: 0 errors, the same 6 warnings.

**Deliberately not changed.** These need live evidence first:
- fishing-04: re-cast while an old line exists; could stall casting if the live rod keeps a hidden line.
- fishing-05: instance flag set before the model replicates.
- fishing-06: one `false` tap reply aborts the visit.
- The 45 s destination timeout re-sends a world request when a place load takes longer.
- Crystal low-confidence items: empty slot-1 candidate set when slot 2 holds a collect quest; exact `workspace.Map` name; one-shot pet restore.

**Limits.** Offline only. The fakes encode VY's own protocol assumptions. Live acceptance stays user-run (P0-01, then P1-03).

**Rollback.** Install v1.1.7 again. The saved-file format is unchanged.

## 2026-10-14 — Cloud session onboarding (Claude Code)

**Context.** The user pasted the permanent handoff and later the full v1.1.7 source. This session runs in a Linux cloud container, so the Windows project, `Verify-Handoff.ps1`, Potassium autoexec and the Roblox client are not reachable. All live steps are written as user-run procedures.

**Baseline identity.** The pasted source has 4,700 lines. With CRLF line endings its SHA-256 is `CDE5F944688D9722B677755A88708001FFB56F329964BFE2A46B7BE61D6D51FC`, exactly the handoff value, so it is the same file. It is stored as `VY/source/VY_AutoRank-v1.1.7.luau`; the git blob hashes to the same value. Luau 0.742 `luau-compile` passes. `luau-analyze` exits 1: "Type inference failed to complete" plus unknown Roblox/executor types, matching the handoff's new-solver baseline. Selene with executor globals: 0 errors, 6 warnings.

**Tooling.** See `TOOLING_AUDIT.md`. The plugin remote MCPs are blocked by the network proxy (403). Serena is connected but not needed. Luau, Lune, Selene and StyLua are verified with fixtures.

**Skills.** Created the six handoff skills under `.claude/skills/`. Each has a worked example; their line references were checked against the frozen file.

**Offline harness (new).** `VY/tests/lune` runs the whole file in Lune against a fake PS99 world: replication delays, pets, chest pad, a Fishing instance, a VM replacement per teleport and a per-account JSON file. 12/12 scenarios pass on unmodified v1.1.7:
- Crystal: the integrated loop works and its invariants hold. Farming/hatching stop while held, held quests survive, opens use no arguments from the pad, bursts are ≤10 before credit, the mode halts after a no-credit burst or a refusal (no retry), the reserve is kept, pets are restored and farming resumes. The setting survives teleports and the World 2 → 1 → 2 trip uses exactly two world requests.
- Fishing: full transaction COMPLETED with the current prompt, the legacy GameBar, and cross-world (VM replaced twice): entry, 3 casts/reels, 24 serialized taps, exact quest credit, exit, return, restore to the best area, pets restored, farming resumed, and no farming during the transaction.
- Lifecycle: same-VM re-execution stops the previous instance and leaves one GUI; the X button stops everything; no requests after Stop.

**Findings so far (no source change yet).**
- Crystal halts a few keys above the reserve when Keys Mastery keeps a key (mock: 102–103 left with reserve 100). Cause: `c.keyEstimate` decrements per request and only resyncs downward (`min(estimate, actual)`). Safe, conservative; documented.
- Crystal setup assembly is unprotected: before both holders are present, ordinary farming advances a lone held 9 or 21 (shown in the `crystal-not-ready` and `crystal-flow` phase 1). This is a design choice for the user, not a defect.
- Crystal eligibility from official pools: VY's strict slot-1 check engages at ranks 4 and 7–40; ranks 5–6 have USE_POTION in slot 1.
- Cosmetic: the restore log says "Restored counters from VY_AutoRank_State.json" even when the per-account file was read (it prints the legacy constant).

**Status changes proposed for the handoff (Rule 16).**
- F14 Crystal: integrated loop "Implemented, Unverified" live; add "Verified Working (mocked Lune runtime, whole file)".
- F15/F16 Fishing transaction: add "Verified Working (mocked Lune runtime, whole file, current + legacy prompt, cross-world)". Live stays "Partially Working".
- P0-01: unchanged. Needs the user-run install and observation in `P0-01_DEPLOYMENT_AND_FISHING.md`.

**Rollback.** No production source was modified. The frozen baseline is unchanged.
