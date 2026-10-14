---
name: luau-architecture-analyst
description: Map ownership, call graphs and lifetimes in the VY AutoRank Luau monolith before any change. Use when asked how a VY subsystem works, before editing VY_AutoRank*.luau, when a worker/loop/lease/handle/connection seems duplicated, stuck or leaked, or when choosing the smallest change seam.
---

# Luau architecture analyst (VY AutoRank)

## Scope and triggers
- Any question about how VY AutoRank's controllers, workers, leases or state interact.
- Mandatory first step before a source edit (handoff Rule 4: inspect the exact implementation and call graph first).

## Prerequisites
- Source of truth: `VY/source/VY_AutoRank-v1.1.7.luau` (frozen, CRLF, SHA-256 `CDE5F944…51FC`) or the newest `VY/VY_AutoRank-v*.luau`. Check the hash with `sha256sum` before quoting line numbers; `S:L<n>` references in the handoff only hold for the frozen file.
- Handoff manual: sections 4 (component map), 6 (startup flow) and 19 (excerpts). In this repo the summary lives in `VY/docs/`.

## Safe read-first workflow
1. Hash the file; record version (`local VERSION =` near line 105).
2. Locate symbols with `rg -n "function (Crystal|M)\.|^local function " <file>`; read whole functions, not snippets.
3. For the subsystem, list: owners (`state.*`, `genv.Vy*` leases), who sets/clears each field, every loop that reads it (`spawnLoop` names at `startThreads`), and the guards (`normalWorkAllowed`, `Crystal.holdsWork`, `MinigameController.holdsWork`, `state.areaProgression.hold`, `gcall`'s thread check).
4. Trace one tick end to end from `controllerTick` (and the worker loops) to the network wrapper (`netFire`/`netInvoke`/`netUnreliable` → `gcall`).
5. Name the minimal change seam: one function, one guard or one field.

## Output (artifact)
A short ownership/call-graph note: function → line, state written/read, lease lifetime, the guard that prevents overlap, and the proposed seam. Put durable findings in `VY/docs/ENGINEERING_LOG.md`.

## Evidence taxonomy
Use only: Verified Working (name the runtime: mocked Lune vs live Roblox/Potassium), Implemented Unverified, Partially Working, Broken, Planned, Unknown. Static reading is never "Verified Working".

## Redaction
Never paste UserIds, account JSON, cookies or tokens into notes. Use aliases (`account A`).

## Exit criteria
Every claim has a line reference in a hashed file; no edit proposed without the guard/lease it interacts with.

## Worked example
Question: "Can farming run while Crystal mode opens chests?"
- `farmTick` (≈L1779) returns early when `Crystal.holdsWork()` (≈L1254) is true and calls `Crystal.pause()`.
- `holdsWork` is true when `state.crystal.hold` or when `Crystal.eligible()` finds a full setup; it yields to an active area operation.
- `onBreakableAdded`, `hatchTick`, `craftTick`, `eventTick`, `maintainDiamondFlag`, `ensureInBestZone` carry the same guard.
- Seam for any change: `Crystal.holdsWork`. Evidence: `VY/tests/lune/crystal_flow.luau` probes "no farming or hatching request while held" (mocked runtime).
