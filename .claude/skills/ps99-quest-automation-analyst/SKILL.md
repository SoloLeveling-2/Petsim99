---
name: ps99-quest-automation-analyst
description: Compare PS99 rank quests (goal Type ids, slots/Stars, amounts, pools) with what VY AutoRank supports, and check cost/credit rules. Use when a rank goal shows "(manual)", a new quest type appears, a goal stalls, someone asks which ranks a method (e.g. Crystal Key) works at, or before adding a goal handler.
---

# PS99 quest automation analyst

## Scope and triggers
Goal-type coverage, slot rules, quest credit and resource cost for VY AutoRank (and RankPilot).

## Prerequisites
- VY enum and support map: `GOAL_TYPE_NAMES` (≈L135), sets (≈L157–173), `isSupported` (≈L1081), `activeGoals`, `currentRemaining`, `MinigameController.classify`.
- Official rank pools: BIG Games API Ranks collection (`https://biggamesapi.io/api/collection/Ranks`); a dated local copy may be in the session scratchpad. Use the newest `dateModified` per `RankNumber`. `configData.Goals[i]` is the weighted pool for slot i.
- The game UI places a goal by `goal.Stars` (1–4); a completed goal pays its Stars (×2 with the Double Stars gamepass).

## Safe read-first workflow
1. Read the live goal fields that VY logs at startup (`goal [N*] title progress/amount (type T)`). Ask for a redacted console snippet, never the whole Save.
2. Map Type → handler via `isSupported` and `craftTick`/`farmTick`/`hatchTick`/`eventTick`/minigame defs. Unknown ids stay "Unknown"/"Planned"; never invent a remote to cover them.
3. For pool questions, compute from the API data (script it; do not eyeball). Record the data date.
4. For cost questions, use measured evidence where it exists (e.g. one Crystal Key → +1 slot-1 collect progress in the user's live probe) and label estimates as estimates.

## Output
A mapping delta table (Type, name, slot pools, VY route, status, evidence), fixtures for any new handler, and a runtime acceptance check (exact quest progress delta).

## Evidence taxonomy / redaction
As in the handoff. Redact UserIds/UIDs from shared output (`uid-1` aliases).

## Exit criteria
Every Type in scope has a route or an explicit Planned/Unknown status with the reason.

## Worked example
"At which ranks can VY's Crystal mode engage?" `Crystal.inspect` requires slot-1 pool ⊆ {9,14,15,21} containing 9, 21 and 14/15. From the 2026-08-29 API data: true at ranks 4 and 7–40; ranks 5–6 add USE_POTION (34); ranks 1–3 lack the pattern. At ranks 10+ type 9 only rolls in slots 3–4.
