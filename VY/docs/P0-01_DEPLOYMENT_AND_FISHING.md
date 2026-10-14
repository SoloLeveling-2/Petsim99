# P0-01 — Deploy one identifiable build, then observe one Fishing cycle

Status: **Implemented, Unverified** live. Offline whole-file Fishing scenarios pass (mocked Lune runtime). The installed autoexec is **Broken** per the handoff audit; it was not re-inspected here because the PC is not reachable from this cloud session.

## Source-grounded diagnosis
1. The handoff audit found the installed `…\Potassium\autoexec\Crystal.luau` is v1.1.6 and ends with `end` instead of `end)` at line 4526. Luau rejects the file, so that copy cannot run at all. Whatever ran in recent sessions was not that file as it is now.
2. The delivered v1.1.7 (`Downloads\VY_AutoRank (16).luau`, SHA-256 `CDE5F944688D9722B677755A88708001FFB56F329964BFE2A46B7BE61D6D51FC`) compiles. It is stored byte-for-byte in this repo at `VY/source/VY_AutoRank-v1.1.7.luau`.
3. Offline, v1.1.7 completes a whole Fishing transaction in three variants: the current "Keep tapping to reel!" prompt, the legacy GameBar, and cross-world with a VM replacement on each teleport. It goes priority → pet pause → entry → cast/bite/reel → serialized taps → exact credit → exit → return → restore → resume. So no integration defect shows up under VY's own protocol assumptions. What remains unknown is live only: whether the current server accepts `RequestCast`/`RequestReel`/`Clicked` as VY sends them, whether the prompt text and layout still match, and whether credit replicates.

**Conclusion:** the next step is on your PC: install exactly one compile-checked build and observe one cycle.

**Which build:** v1.1.8 (`VY/VY_AutoRank-v1.1.8.luau`, 4,795 lines; hash in `ENGINEERING_LOG.md`) is recommended. Its Fishing-related changes are:
- the 90 s visit budget no longer counts travel and loading, so a cross-world visit with "Do minigames first" OFF no longer gives up right after its first cast;
- the bite scan looks at the newest `__DEBRIS` entries first;
- a copy stopped while loading no longer overwrites the saved settings or transaction;
- a replaced copy is named in the console.

Everything else in the Fishing adapter is unchanged from v1.1.7. If you want the exact handoff baseline instead, install v1.1.7. Both are kept here.

## Step 1 — install exactly one build (you run this; no admin rights needed)
In PowerShell:
```powershell
$src  = "$env:USERPROFILE\Downloads\VY_AutoRank-v1.1.8.luau"   # download from the repo, or use v1.1.7
(Get-FileHash $src -Algorithm SHA256).Hash   # compare with the hash in ENGINEERING_LOG.md (v1.1.7 = CDE5F944688D9722B677755A88708001FFB56F329964BFE2A46B7BE61D6D51FC)
$auto = "$env:LOCALAPPDATA\Potassium\autoexec"
Get-ChildItem $auto | Select-Object Name, Length, LastWriteTime   # list every autoexec script
```
- Move every other AutoRank copy out of the autoexec folder (for example into a `backup` folder you create). Keep exactly one.
- Replace the broken `Crystal.luau` with the chosen build (Explorer copy/paste, or `Copy-Item $src "$auto\Crystal.luau" -Force`), then confirm:
```powershell
(Get-FileHash "$auto\Crystal.luau" -Algorithm SHA256).Hash   # must equal the source hash above
(Get-Content "$auto\Crystal.luau").Count                     # v1.1.8 = 4795, v1.1.7 = 4700
```
- In game, check all three: the hub title says `VY AutoRank v1.1.8`, the console (F9) shows `[AutoRank] VY AutoRank v1.1.8 starting`, and `print(getgenv().VyAutoRank.Version)` prints `1.1.8` (or 1.1.7 if you installed that). Check again after one world teleport.
- With v1.1.8, a line `[AutoRank] replacing running AutoRank v…` right after joining means a second copy is running. Remove the duplicate before testing.

## Step 2 — one bounded Fishing observation
Preconditions: a "Fishing" rank quest (type 26) is active, World 1 area 27 is owned, and **Minigames: ON**. Press **Do minigames first: ON** to start immediately; otherwise ordinary quests get up to 5 minutes first.

Watch the minigame panel in the hub. It shows `Fishing | type 26 slot N | progress/amount`, the phase, worlds, retries, idle seconds and one session line. Write down:
- the version shown;
- the furthest session line reached and how long it stayed there;
- the tap count in `tapping catch bar | N taps`;
- quest progress before and after;
- the final console line `Minigame Fishing ended: …`;
- whether you are back in the best area with pets equipped, and whether farming continues.

| What you see | Where it is stuck | What to send back |
| :--- | :--- | :--- |
| `waiting for equipped rod/character` until it fails | READY: no `Rod` model under the character | Explorer screenshot of your character while fishing |
| `no replicated DeepPool/Water surface found` or `nearest fishing water is N studs away` | Water geometry/range | Explorer screenshot of the Fishing instance's water parts |
| `waiting for line after cast`, then `no observed bite after cast` | Cast not accepted, or the line is named differently | Whether a line/bobber appears on screen |
| `waiting for bobber connected to rod line` | Bobber/attachment layout | Explorer screenshot of `Bobbers` |
| `waiting for bite` until the 35 s timeout | Bubble detection (`__DEBRIS` host) | Whether bubbles appear on screen |
| `waiting for catch interaction`, then `catch UI did not activate after reel` while the reel prompt is visible | Prompt detector | The prompt's exact text and its PlayerGui path (no other text) |
| Tap count rises but progress doesn't, then `catch interaction exceeded time limit` | Server rejects or ignores `Clicked` | The tap count and whether the fish UI reacts |
| Catch credited, then `RESTORE timed out` or a stall after leaving | Return/restore (P0-02) | Phase and session line at the stall |
| Status goes back to `casting`/`preparing next cast` while the reel bar is still on screen | Prompt lost for a moment (review finding fishing-04, not changed yet) | The prompt text while it happens |
| `another instance is already active` right after entering | Instance flag set before the model replicated (fishing-05, not changed yet) | Time between entering and the error |
| `server refused fish-click` | A `false` reply to one tap (fishing-06, not changed yet) | Tap count when it happened |

Fishing completes only when the quest's progress changes in the rank panel. A disappearing prompt alone does not count.

## After P0-01: area 219 / Rebirth 9 (P1-01)
With the same identified build, watch the yellow area line (`Area N / 219 | Rebirth R / 9` plus a status). Note where it waits: currency, "next area unavailable", travelling to World 2 or 3, or a rebirth. Rebirths are authorized and capped at 9; purchases are capped at area 219. The World 3 quest-gated areas have no automatic solver yet.
