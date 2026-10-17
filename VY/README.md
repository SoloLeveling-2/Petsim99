# VY AutoRank — repository workspace

This folder holds VY AutoRank work done from Claude Code cloud sessions. The user's primary project stays on their Windows PC (`C:\Users\thebe\OneDrive\Documents\ChatGPT\Roblox`, with `HANDOFF_TO_CLAUDE.md`, `handoff_archive/` and `Verify-Handoff.ps1`). Nothing here is installed automatically. Deploying to Potassium autoexec is a manual step on the PC (see `docs/P0-01_DEPLOYMENT_AND_FISHING.md`).

| Path | What it is |
| :--- | :--- |
| `VY_AutoRank-v1.1.9.luau` | Current build: v1.1.8 plus the `gcall` identity fix (see `docs/VY_AUTORANK_v1.1.9_NOTES.md`). Rebuild it byte-identically with `python3 VY/tools/patch_v119.py VY/VY_AutoRank-v1.1.8.luau out.luau`. |
| `VY_AutoRank-v1.1.8.luau` | Previous build: v1.1.7 plus 12 reproduced fixes (see `docs/VY_AUTORANK_v1.1.8_NOTES.md`). Rebuild it byte-identically with `python3 VY/tools/patch_v118.py VY/source/VY_AutoRank-v1.1.7.luau out.luau`. |
| `source/VY_AutoRank-v1.1.7.luau` | Frozen baseline, byte-identical to the handoff source (CRLF, 4,700 lines, SHA-256 `CDE5F944688D9722B677755A88708001FFB56F329964BFE2A46B7BE61D6D51FC`). `.gitattributes` keeps it binary-exact. Never edit it. |
| `tests/run_tests.py` | Runs every offline scenario against one source file: `LUNE=/path/to/lune python3 VY/tests/run_tests.py <file.luau> [version]` |
| `tests/lune/` | Whole-file harness: the real Luau VM (Lune 0.10.x) runs the complete script against a fake PS99 client/server with replication delays. A teleport is modelled as a new VM plus an autoexec re-run. |
| `tools/PS99_EventProbe_DiamondMountain.luau`, `tools/PS99_Probe.luau` | Read-only probes (run by hand in Potassium) that report the game's modules, remotes, Save fields and world layout, and optionally record the requests the game sends while you play |
| `tools/selene/` | Selene config with the executor globals VY uses |
| `docs/` | Tooling audit, P0-01 plan and live test, Crystal Key analysis, engineering log |
| `../.claude/skills/` | The six project skills required by the handoff |

## Offline scenarios (mocked runtime — not live PS99)
24 scenarios (the runner adds a `luau-compile` row, so it reports 25): `smoke` (start, ordinary work, same-VM re-execution, GUI X/Stop, quiet after Stop); Crystal: `crystal-flow`, `crystal-travel` (World 2 → 1 → 2), `crystal-rankup`, and the edge cases slow-replication, no-credit, refused, not-ready, stars-keys, zero-drop-tail, stars-complete, travel-refused, retain-strand, protect-setup; `persist-race`; Fishing: current prompt, legacy GameBar, cross-world, slow travel, busy `__DEBRIS`; identity: nested `gcall`, executor at identity 7; the two read-only probes' recorders. The harness models per-thread identity (new threads inherit it, signal handlers run at the connector's). The runner marks which failures are the documented v1.1.7 and v1.1.8 defects.

The fakes follow VY's own protocol assumptions where the live game is only partly observed (handoff F16 and F14). A green run therefore means "the script keeps its invariants against these fakes". It does not mean the live server accepts the requests. Live acceptance still uses the user-run procedures in `docs/`.

## Evidence words
Verified Working (always say which runtime), Implemented Unverified, Partially Working, Broken, Planned, Unknown — as defined in the handoff.
