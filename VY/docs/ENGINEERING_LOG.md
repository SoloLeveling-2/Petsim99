# VY AutoRank — engineering log

Newest first. Each entry: what changed, why, evidence, tests, limits, rollback.

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
