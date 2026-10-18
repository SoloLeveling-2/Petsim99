# VY AutoRank — engineering log

Newest first. Each entry: what changed, why, evidence, tests, limits, rollback.

## 2026-10-18 — Probe run 4: wall-HP clock model, other players redacted (probe v5.2)

**Evidence.** The user sent a second recording, run 4: `PS99_EventProbe_20261018_025024.txt` (02:50–02:55 UTC, probe v5), with Wall Crew v0.3 running. A workflow ran 4 analysts and 4 skeptics; each finding was re-derived from the raw reports with python. All verified facts are in `DIAMOND_MOUNTAIN_FINDINGS.md` (run 4). The main ones:
- **Wall 3's HP follows the clock:** `max = 5.2e9 − 90,277.78 × floor(at − 1792281600)`, i.e. 325 M per hour in 1-second steps. It fits all 8 recorded replies exactly; 3-second steps, a continuous line, per-minute steps and a link to damage dealt are all ruled out.
- **Damage is not crew power × a fixed factor:** 2.352 in run 3, 1.3228 in run 4 (19 kinds, 4,476 pets). The cause is unknown; the reply's `stacks` should tell.
- **Power** for Expedition Wolf (720) and Leopard (1,070), and the golden/shiny variants.
- **Save layouts** for boosts, the merchant, potions and pass quests; Yeti max health per spawn; trail egg windows.
- **The `[script]` traffic** (farming, a status poll every 6 s) came from another script: Wall Crew sends neither, and VY AutoRank does not farm inside instances. Wall Crew v0.3 correctly sent nothing, because every pet was already on the wall.
- **Privacy:** the reports named 20 other players on 68 lines. They appeared in character paths, a hoverboard folder, the game's own `Get Stats(<player>)` requests with profile replies, and `DM_HypeTop`.

**Change (probe v5.2; both probes where they share the code).**
- **Other players:**
  - Each gets an alias `<pN>`, from `GetPlayers` and `PlayerAdded`. Player instances and characters, per-player `__THINGS` folders and `Players:GetPlayerFromCharacter` owners print as aliases.
  - Character models are counted, not listed.
  - JSON name and id fields are scrubbed: your own entry shows `<me>`, a known player their alias, an event item keeps its name.
  - Lua tables with a user-id field (leaderboard pages) have their name and id fields hidden.
  - A structured reply to a request about another player (by Player, username or UserId) is replaced; plain `true`/`false`/numbers are kept.
  - Text arguments of mail, trade, clan, friend and invite requests are not printed.
  - The text backstop matches registered usernames case-insensitively, with `_` as a boundary, and UserIds of 6+ digits at digit edges. Display names are hidden only structurally, because they are not unique and can be game words. Names that are game words are left to the structural rules.
  - Long strings are redacted before they are cut. The whole report is redacted once more at save time, for players who joined after a line was written.
  - The local UserId no longer damages numbers that contain it. The local display name no longer replaces a game word.
- **Section 6c (new):** every `DM_Walls_Status` reply as one row (section 6 keeps 2 per request), and each wall's `stacks` in full when they change. The reply is copied before the deferred thread reads it, partial saves include 6c, and dropped stack changes are counted.
- **6b:** first-seen time per row ("not logged" when unknown). A reply whose request was not logged no longer makes a 0-call row.
- **Section 4:**
  - also lists Save keys named after this event's Directory entries (Hiker pets, `PurchasedEggs["Boulder Ridge Egg"]`), always shows `Save.Potions`, and skips `Engagement`/`UpgradesOwned`/`ZoneQuests`/`Achievements`/`GymUpgradeSkillMachine`;
  - its cap is 700 lines, and it says how many fields it left out.

**Review.** A second workflow (3 reviewers, 3 skeptics) checked the v5.2 change: privacy, hook safety and data integrity. All 17 findings were confirmed or partly confirmed, and all were fixed. They included:
- the reply being read after the caller could change it;
- partial saves without 6c;
- display names wiping game words;
- leaderboard records;
- names cut in two before redaction;
- names joined by `_`;
- case;
- typed mail recipients;
- late joiners;
- short UserIds;
- collided names in paths;
- the own HypeTop entry;
- item names in JSON;
- boolean replies;
- the 6c stack cap;
- the 6b first-seen time;
- the local display name.

The hook rules still hold: there are no reads before dispatch, and only pcall'd defers.

**Tests.** probe_recorder gained other players, including a late joiner, a name that is a game word, a display name inside a pet name and a 6-digit UserId. It also gained a hoverboard folder, Get Stats by Player and by UserId, a leaderboard page, a long notice, joined and lower-case names, a mailbox send, live-shaped wall-status replies (40 with changing stacks), a reply the caller changes, and a one-shot defer failure. The new checks were red on the committed probes (12 in the general probe) and are green now. Each new guard was mutation-checked. The two mutants that first survived led to stronger tests. Fixture names are synthetic: no real player name from the reports is in the repo. Event probe 117 checks, general 34; full suite 49/49 three times; luau-compile OK; selene 0 errors (only the existing unused-HttpService warning).

**Limits.** All offline. Live checks still needed:
- whether `stacks` explains the damage;
- whether wall 3's HP keeps falling after 02:54 UTC or has a floor;
- whether the redaction misses a name source the reports have not shown yet.

Other players' names could also reach the console through prints by other scripts, which the probe does not control.

**Rollback.** `git checkout 2043d1b -- VY/tools/ VY/tests/lune/probe_recorder.luau` brings back probe v5.1.

## 2026-10-18 — Probe run 3 (ZapHub): Wall Crew v0.4 uses the server's fill; new Camp Eggs v0.1

**Evidence.** The user ran probe v5 on the mountain with ZapHub (report `PS99_EventProbe_20261018_023610.txt`, 02:36–02:41 UTC). Facts are recorded in `DIAMOND_MOUNTAIN_FINDINGS.md` (run 3). Probe v5 worked live: replies were captured and ZapHub's requests were tagged `[script]`. The ones that mattered:
- `DM_Walls_FillBest(3)` → `true, nil`. The Save diff shows every spare event pet joined wall 3 (crew 768 → 957). A second call → `false, "No spare pets to send!"`. The client code has the same function (`DiamondMountainCmds.Walls.FillBest/1`), so the server chooses the pets.
- `CustomEggs_Hatch("<model name>", 63)` ×23 → `true, nil`; 1,449 Boulder Ridge Eggs for 43.2 M TrailCoins. The uid is a `Workspace.__THINGS.CustomEggs` model with `DM_EggId`. Trail eggs also carry `DM_TrailEgg`.
- `DM_Walls_Status` gives every wall's HP: 130 M, 760 M, ~4.35 B, 34 B, 250 B. Damage per second is crew power × 2.352 for this account.

**Change.**
- `VY_WallCrew-v0.4.luau` (renamed from v0.3):
  - Sends `DM_Walls_FillBest(wall)` instead of per-stack `DM_Walls_Load` maps, and only when the picture changes: event pets not on the wall (by its egg-based list), a change in the inventory's total pet count, or another wall. The count trigger means kinds it cannot identify (e.g. Expedition Wolf, if an egg list cannot be read) still get loaded.
  - "No spare pets to send!" is normal and is not repeated for the same picture. A fill counts only when the Save crew grows; two misses in a row stop the script.
  - DRY_RUN is still the default. Huge pets are no longer the script's choice, since the server picks; the header says so.
- `VY_CampEggs-v0.1.luau` (new):
  - Hatches the nearest camp egg within 40 studs (a CustomEggs model with `DM_EggId`, never a trail egg or another event's egg), at your max hatch (`EggCmds.GetMaxHatch`), every 2 s.
  - It learns the price from its own hatches (the median of the last 5, so one hatch that overlaps another purchase does not stall it). When you cannot pay, it waits instead of stopping.
  - `KEEP_COINS` is a TrailCoins reserve; with one set, the first hatch is 1 egg, to learn the price.
  - A hatch counts only when `PurchasedEggs[<egg>]` grows; three misses in a row stop it. DRY_RUN is the default.
- Event probe v5.1: section 3b also lists entries whose module sits in a `DiamondMountain` folder, because run 3's 3b missed camp eggs 2–5 (names without an event word).

**Tests.**
- Probe: a new check for an egg found only by its module folder, red before the fix.
- Wall Crew: 11 scenarios, rewritten for FillBest. New ones are `unknown-kind`, `no-spare` and `no-effect`. They were red on the v0.3 code.
- Camp Eggs: 11 new scenarios: dry-run, hatch, nearest, trail-egg, far, keep-coins, out-of-coins, refused, no-effect, not-inside, stop.
  - `out-of-coins` (and a price spike inside `hatch`) came from my own review of the first draft. The draft stopped itself after three "not enough" refusals, and with the dearest-hatch price it stalled after one dear-looking hatch. Both were red before the fix.
- Mutation check: removing each guard turns its scenario red. Camp Eggs: trail filter, reserve, gap, nearest, range, stop-after-misses, confirm, median price, affordability, progress-log rate. Wall Crew: count trigger, no-spare handling, no-repeat, wall break, always-ask, stop-after-misses.
- Full suite 49/49 (mocked runtime), three runs in a row. luau-compile OK; selene 0 errors (only the existing `_G` fallback warning).

**Limits.** None of this has run live as VY code; only the requests have, sent by ZapHub. Unknown live:
- whether a camp egg must be near you to hatch (v0.1 asks you to stand there);
- whether FillBest ever puts an event Huge on a wall;
- what `slots` = 17 and `stackMax` = 100 in the status reply limit.

**Rollback.** `git checkout aa2bb7f -- VY/` brings back Wall Crew v0.3 and probe v5 (Camp Eggs did not exist).

## 2026-10-18 — Event probe v5 for a ZapHub test: two adversarial review rounds

**Why.** The user asked about testing ZapHub's event features (ZapHub is a third-party PS99 script hub; RankPilot X's interface was modelled on it). The idea: let ZapHub run Diamond Mountain features while the probe records, to learn the requests for features the user cannot reach yet.

**Research (workflow agent, sources in the run).** No public ZapHub page lists Diamond Mountain features as of 2026-10-18:
- The ScriptBlox listing still shows the Lucky Race event tab (last updated 2026-04-10). zaphub.xyz has no feature list and says releases go to its Discord, which could not be read.
- ZapHub is closed, remote-loaded code (Luarmor/Luraph) with auto-mail features.
- Many "ZapHub" re-uploads load stealer-style code (hard-coded webhooks, "keyless", "self dupe"). ZapHub's own FAQ says to use an alt.

**Review round 1 (3 lenses, 27 agents; each finding independently verified).** 18 confirmed, 4 refuted. Main points:
- (high) The hook read `self.Name` before dispatch. Another script's `__index` hook that makes a colon call would change the namecall method, so the game's request went out as the wrong method (dropped in the mock).
- (high) Calls that bypass `__namecall` (`remote.FireServer(remote, …)`, VM-obfuscated code) are invisible, and the report never said so.
- The silent 5000-request cap; NOISE remotes missing from 6b; event lines crowded out; dedupe ignoring the tag; no partial saves; `[script]` semantics not explained.

**Review round 2 (11 agents) on the v5 rewrite.** 8 confirmed, 0 refuted:
- (high) An unprotected `task.defer` before dispatch. Roblox raises "Maximum re-entrancy depth (80) exceeded" in a thread already at that depth, so the request would be dropped.
- The general probe's 1000 cap now also counted noise, so the one hand action could be lost.
- The camp-egg hatch (`CustomEggs_Hatch`) was not treated as an event line.
- Replies did not name their request.
- A non-ASCII display name was not redacted.
- The tests masked pre-dispatch reads, because the mock always restored the method.

**Change (both probes where relevant).**
- No Instance reads or colon calls before dispatch: name lookup, noise filtering and formatting happen in the deferred thread. The method is re-asserted before dispatch, and `pcall(task.defer, …)` is used (lost log lines are counted).
- No capture caps; every request is counted.
- Four line pools: event/other × game/`[script]`. Event requests are `Instancing_*`, event words, egg/hatch/unmask, or a `"DiamondMountain"` argument.
- 6b lists event rows, then the 20 busiest, then rare game requests, with a cut marker.
- Reply lines name their request (at most 2 distinct per request); replies after the window are dropped.
- The report so far, with a 6b snapshot, is saved every 60 s.
- The display name is redacted on word edges (bytes ≥ 0x80 count as letters).
- Section 6 says what the recorder cannot see and what `[script]` means.

**Tests.**
- Every finding fixed got a failing check first. Committed v5 (`b5f1c9d`) fails the round-2 checks: 5 in the event probe and 1 in the general probe.
- New suite entries `probe-*-recorder-nosnm` run the probes without `setnamecallmethod`, so a pre-dispatch read cannot hide behind the re-assert.
- The partial-save check now records every write. A fixed-time poll raced the test window under load, and a mutation that removes partial saves still turns it red.
- Suite 35/35, three consecutive runs.

**Still not covered (by design).** Calls that bypass `__namecall`; the report says so. A `hookfunction` capture of `RemoteEvent.FireServer` etc. would cover them, but adds a second hook on every request; it is left for a separate change with its own live check.

## 2026-10-18 — VY Wall Crew v0.3: protected pet-list lookups

**Live evidence.** v0.2 stopped at start with `ReplicatedStorage.Library.Directory.Pets:28: Unknown Directory Pets.'Nice'`. The stack went through `__index` → `add` → `addPetNames` → the egg-reading block, before any request was sent.
- The live `Directory.Pets` raises on a name that is not a pet.
- A camp egg's pet entries contain non-pet strings ("Nice"). v0.2 checked `Pets[name] ~= nil` without protection.

**Red.** The fixture's `Directory.Pets` now raises on unknown names like the live one, and an egg entry carries "Nice". v0.2 failed with "source runs to the end ([string]:110: Unknown Directory Pets.'Common')" in every scenario.

**Change (v0.3, file renamed).**
- `petEntry()` does every `Directory.Pets` lookup through `gcall` (pcall at identity 2) and caches it; `isBig` and the egg reader use it.
- The whole egg-reading step runs in `pcall` (it logs and keeps what it read), and each egg runs in its own `pcall`.

**Green.** 8 Wall Crew scenarios pass; compile OK; Selene 0 errors (1 `_G` warning, as before).

**Note.** The other `Directory` reads in the script were also checked: `Directory.Pets` and `Directory.Eggs` go through `gcall`, the Save tables are plain, and remote calls go through `gcall`.

## 2026-10-18 — VY Wall Crew v0.2: event pets from the camp eggs

**Live evidence.** The user's first live run of v0.1 (DRY_RUN, nothing sent) planned the genuine wall pets (5 Climber Goat, 76 + 4 golden Hiker Raccoon, 25 Hiker Red Panda). It also planned other events' pets: 13,343 + 421 golden + 23 shiny Stitched Cat, 613 Stitched Dragon, 94 Mothman, Lucky Stacked Bunny/Capybara/Elephant, Lucky Surprise Ducky. Cause: v0.1 took `Directory.Pets[id].fromZoneNumber == 279` as "Diamond Mountain pet", and other events' pets share that zone. Without DRY_RUN, the server would probably have refused them (v0.1 then stops after two refusals); either way it was wrong.

**Red.** `dm_wallcrew.luau` now has other-event pets in zone 279, Diamond Mountain egg modules and another event's egg, plus a `no-egg-data` scenario. Against v0.1:
- `dry-run` 2 FAIL (it planned Stitched Cat/Mothman);
- `load` 1 FAIL (it sent them after the event pets);
- `no-egg-data` 3 FAIL.

**Change (v0.2, file renamed).**
- Event pets are the pets named in eggs whose module sits in the Directory's `Eggs.Events.DiamondMountain` folder (live `_script` paths), plus any kind a wall's crew has held this session.
- The pet-list reader accepts strings, `{name, weight}` pairs, `{name = …}` tables and `{[name] = weight}` maps, keeping only names that exist in `Directory.Pets`.
- Huge/Titanic/Gargantuan are still never loaded.
- If no egg list can be read, it says so and only tops up kinds already on a wall (fail closed).
- The pet list it found is printed once, so a dry run shows it.

**Green.**
- 8 Wall Crew scenarios pass (three egg formats in the fixture).
- Compile OK; Selene 0 errors, 1 warning (`_G` fallback, as in VY).

**Limits.** The real format of `Directory.Eggs[...].pets` is still unseen live. The printed list of event pets is the check.

## 2026-10-18 — Live run 2; VY Wall Crew v0.1 (first Diamond Mountain automation)

**Evidence (run 2).** The user redid run 1 at 120 FPS with the previous probe copy, whose recorder filled at +29 s; the Save diff is complete (222 changes). Facts are in `DIAMOND_MOUNTAIN_FINDINGS.md` ("Walls (run 2)"):
- Wall 1 has 130,000,000 HP.
- A broken wall releases its crew.
- Pets on a wall stay in the inventory, and there is no crew limit (642 pets).
- Per-pet power is listed per kind (golden ×1.5, shiny ×1.75).
- Camp 2's egg is `Russet Falls Egg`.
- Falling diamonds paid 418,506 in 5 min.

**Why a separate script.** The wall action is one known request (`DM_Walls_Load`, 3 live samples in run 1), and its effect is visible in the Save. Inside VY it would compete with VY's travel and farming. A small standalone script is easier to verify live first.

**Change.** New `VY/VY_WallCrew-v0.1.luau`:
- Each check (15 s), while on the mountain, it finds the first unbroken wall whose camp is unlocked.
- It compares the owned event pets (Directory `fromZoneNumber` 279, never Huge/Titanic/Gargantuan) with that wall's `WallCrew` count per kind, and loads only the missing count, one stack per request.
- Requests are 1.5 s apart, at most 8 per check.
- Each load is confirmed by the Save (the crew count grows) and the server's reply is printed.
- It stops after two unconfirmed loads in a row. A wall breaking during a load is not counted as a failure.
- `DRY_RUN = true` by default.
- Re-running replaces the running copy; `getgenv().VyWallCrew.Stop()`.
- Probe: the header says "v3", so reports show which copy ran.

**Red → green.**
- `dm_wallcrew.luau` (7 scenarios, fake server modelled on the live runs) failed against an empty script and passes on v0.1.
- While writing it, the wall-break scenario exposed a real flaw: a wall breaking right after a load was logged as "did not show" and counted toward the stop. The new check failed first, then passed; it held in 5 repeats.

**Green.**
- Full suite on v1.1.9: 32/32.
- Wall Crew: compile OK; Selene 0 errors, 1 warning (the same `_G` fallback warning VY has).

**Limits.**
- Mocked runtime only.
- Live unknowns: the server's reply to `DM_Walls_Load`; whether a load of a part-loaded kind is additive for big counts (run 1 showed 2+1 = 3); whether `GetInstanceID()` returns "DiamondMountain" (with a fallback on the active instance container).

**Rollback.** Stop it (`getgenv().VyWallCrew.Stop()`) and don't run it; it changes nothing else.

## 2026-10-17 — Live event probe run 1; probe fixes for run 2

**Evidence.** The user ran the event probe once (Potassium v2.5.3, World 2 server), entered Diamond Mountain, went through the tutorial, loaded pets on wall 1 and hatched the camp egg. The facts are in `DIAMOND_MOUNTAIN_FINDINGS.md`. Main points:
- The event is an instance in the World 2 server.
- All actions go through `Instancing_InvokeCustomFromClient("DiamondMountain", "DM_…")`.
- Wall state is under `Save.InstanceVars.DiamondMountain` (5 walls).
- Yeti health is on instance attributes.
- Potassium's thread identity is 8, so v1.1.9's identity fix is inert live.

**Defects the run exposed (data lost).**
1. `UnreliableRemoteEvent({fps=…})` pings, each with a new value, filled the 200-line recorder at +138 s. The last 160 s are missing; for example, a Red Panda load shows in the Save diff but not in the recording.
2. No server replies are recorded, so the wall HP from `DM_Walls_Status` is unknown.
3. The world scan ran before the player entered the mountain.
4. The Save diff (cap 300) was ~170 lines of `Save.Engagement.Stats` telemetry.

**Red** (new checks in `probe_recorder.luau` modelled on run 1): 8 FAIL.

**Change.**
- Recorder:
  - At most 4 lines per remote (per action for `Instancing_*`), 400 lines in all.
  - Section 6b gives each remote's total calls.
  - Replies to InvokeServer requests are recorded. This happens only when `coroutine.isyieldable()` (otherwise the call passes straight through as before), and is formatted after the server answered: inside `pcall`, with the namecall method restored afterwards.
- Save diff: leaves out telemetry (counted), puts DiamondMountain first, cap 400.
- New section 8 at the end:
  - the instance attributes again;
  - `__THINGS` children, plus the children of egg folders (custom egg ids);
  - the active instance's layout: folders/models to depth 3, anything with attributes, every ProximityPrompt/ClickDetector with its action text.
- Section 2 shows each function's argument count (`debug.info(f, "a")`).

**Green.**
- Event probe 35/35 checks, general probe 13/13.
- Full suite on v1.1.9: 25/25.
- Probe compile OK; Selene 0 errors, 0 warnings.
- Probe SHA-256 `BB2D0578…DA79`.

**Limits.**
- Mocked runtime.
- Reply capture relies on yielding inside the hook. That is the same pattern as the game's own `local r = remote:InvokeServer()`, but it is unobserved on Potassium.

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
