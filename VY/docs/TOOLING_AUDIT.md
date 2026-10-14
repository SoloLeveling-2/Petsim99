# Tooling & Capability Audit — Claude Code cloud session

Date: 2026-10-14. Environment: Claude Code 2.1.299 in a Linux cloud container (not the user's Windows PC). Repository: `SoloLeveling-2/Petsim99`, branch `claude/read-it-o4o53f`. This audit covers what this session can actually reach. The user's Windows project (`C:\Users\thebe\OneDrive\Documents\ChatGPT\Roblox`), Potassium autoexec and Roblox client are **not reachable** from here.

Status values follow the handoff (Pre-Installed / Installed / Blocked / Unnecessary). Verification Result records what was actually run.

| Tool / MCP / Skill | Category | Status (Pre-Installed / Installed / Blocked / Unnecessary) | Verification Result | Specific Project Role & Priority |
| :--- | :--- | :--- | :--- | :--- |
| Luau 0.742 `luau`, `luau-compile`, `luau-analyze`, `luau-ast` (official release, session scratchpad) | CLI | Installed | Fixture: `x += 2` runs (prints 3); broken fixture fails compile (exit 1); analyzer exit 0 on fixture. v1.1.7: compile OK; full-file analyze exit 1 ("Type inference failed to complete", Roblox/executor types unknown), same as handoff baseline | P0 compile gate for every build; analyzer delta check |
| Lune 0.10.4 | CLI | Installed | Runs the whole VY file in the real Luau VM with `VY/tests/lune` mocks; 9/9 offline scenarios pass on v1.1.7 | P0 offline regression harness (mocked runtime only) |
| Selene 0.30.0 + `VY/tools/selene` std (`roblox_exec` + `setthreadidentity`, `getthreadidentity`, `setreadonly`) | CLI | Installed | v1.1.7: 0 errors, 6 warnings (shadowed `handle`/`water`/`ok`, unused `zone`/`info`, `_G` fallback) | P1 lint of changed regions |
| StyLua 2.6.0 | CLI | Installed | `--check` on a disposable fixture reports reformat (exit 1) as expected. Not applied to VY: whole-file formatting would hide functional diffs | Formatting of new test files only |
| ripgrep 14.1.0, Git 2.43, Python 3.13, Node 22 | CLI | Pre-Installed | Version commands OK; ripgrep used for the call-graph/line audit | Search, hashing, test runner |
| Claude Code built-in tools (Read/Edit/Write/Bash/Grep/Glob, Agent, Workflow) | Built-in | Pre-Installed | Used throughout; Workflow ran a 5-area review with 2 adversarial verifiers per area | Analysis, multi-agent review |
| Serena MCP (plugin) | MCP | Pre-Installed | `claude mcp list`: Connected. Not needed (no Luau language server behind it) | Unnecessary for Luau work |
| GitHub MCP (session tools `mcp__github__*`, scoped to `sololeveling-2/petsim99`) | MCP | Pre-Installed | Available as deferred tools; git push over the session proxy works | Commits/PRs only when asked |
| Plugin `engineering` remote MCPs (slack, linear, asana, atlassian, notion, github copilot, pagerduty) | MCP | Blocked | `claude mcp list`: "Proxy refused to open a tunnel: 403 Forbidden" (environment network policy) | Not needed for this project |
| Plugin `engineering` datadog | MCP | Blocked | "Needs authentication" (OAuth not available in this session) | Not needed |
| context7 MCP | MCP | Blocked | ERR_PROXY_TUNNEL | Not needed (no Luau/Roblox library docs there) |
| Firecrawl / Exa web MCP | MCP | Pre-Installed | Used earlier this session for public PS99 data (rank pools, chest drop tables) | Read-only evidence gathering |
| Official BIG Games API Ranks data (`biggamesapi.io/api/collection/Ranks`, local copy dated 2026-08-29) | Data | Pre-Installed | Parsed: 57 configs / 40 ranks; slot-pool analysis reproducible | Quest pool / Crystal eligibility evidence |
| Six project skills (`.claude/skills/*`) | Workflow | Installed | Created this session; each has a worked example checked against the frozen source (line numbers verified with `rg`) | P0 repeatable workflows |
| `Verify-Handoff.ps1` + 254-check suite, Luau Windows binaries in `handoff_archive` | CLI | Blocked | Files live on the user's Windows PC; not in this container or repo | User should run `.\Verify-Handoff.ps1 -SourcePath <new build>` locally |
| Potassium executor, Roblox client, autoexec folder | Runtime | Blocked | Not reachable from a cloud container | All live acceptance is user-run |
| luau-lsp | LSP | Unnecessary | Not installed: luau-analyze already gives the same diagnostics; a Roblox type-definition setup is a separate P1-04 task | Revisit with P1-04 |
| Windows performance counters | CLI | Blocked | No Windows host here | P2-01 five-client measurement is user-run |

## Discovery commands run
`claude --version`, `claude mcp list` (output redacted of query keys), `claude plugin list`, `ls ~/.claude/skills`, version/fixture checks for every CLI above. No credentials were printed or stored.

## Fallbacks
- Live behaviour: give the user an exact, bounded test procedure (`VY/docs/P0-01_DEPLOYMENT_AND_FISHING.md`) instead of claiming success.
- 254-check suite: our own Lune suite (`VY/tests/run_tests.py`) covers the whole file offline; the user's suite stays the extraction-level baseline on Windows.
