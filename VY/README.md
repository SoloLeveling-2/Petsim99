# VY AutoRank — repository workspace

This folder holds VY AutoRank work done from Claude Code cloud sessions. The user's primary project stays on their Windows PC (`C:\Users\thebe\OneDrive\Documents\ChatGPT\Roblox`, with `HANDOFF_TO_CLAUDE.md`, `handoff_archive/` and `Verify-Handoff.ps1`). Nothing here is installed automatically. Deploying to Potassium autoexec is a manual step on the PC (see `docs/P0-01_DEPLOYMENT_AND_FISHING.md`).

| Path | What it is |
| :--- | :--- |
| `source/VY_AutoRank-v1.1.7.luau` | Frozen baseline, byte-identical to the handoff source (CRLF, 4,700 lines, SHA-256 `CDE5F944688D9722B677755A88708001FFB56F329964BFE2A46B7BE61D6D51FC`). `.gitattributes` keeps it binary-exact. Never edit it. |
| `tests/run_tests.py` | Runs every offline scenario against one source file: `LUNE=/path/to/lune python3 VY/tests/run_tests.py <file.luau> [version]` |
| `tests/lune/` | Whole-file harness: the real Luau VM (Lune 0.10.x) runs the complete script against a fake PS99 client/server with replication delays. A teleport is modelled as a new VM plus an autoexec re-run. |
| `tools/selene/` | Selene config with the executor globals VY uses |
| `docs/` | Tooling audit, P0-01 plan and live test, Crystal Key analysis, engineering log |
| `../.claude/skills/` | The six project skills required by the handoff |

## Offline scenarios (mocked runtime — not live PS99)
`smoke` (start, ordinary work, same-VM re-execution, GUI X/Stop, quiet after Stop) · `crystal-flow` · `crystal-travel` (World 2 → 1 → 2) · `crystal-slow-replication` · `crystal-no-credit` · `crystal-refused` · `crystal-not-ready` · `crystal-stars-keys` · `fishing-current-prompt` · `fishing-legacy-gamebar` · `fishing-cross-world`.

The fakes follow VY's own protocol assumptions where the live game is only partly observed (handoff F16 and F14). A green run therefore means "the script keeps its invariants against these fakes". It does not mean the live server accepts the requests. Live acceptance still uses the user-run procedures in `docs/`.

## Evidence words
Verified Working (always say which runtime), Implemented Unverified, Partially Working, Broken, Planned, Unknown — as defined in the handoff.
