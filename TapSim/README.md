# Tap Simulator REBORN helper

`TapSim_Reborn.luau` is a single readable executor script for the Roblox game **Tap Simulator REBORN** (place `72858262610964`, developer Cursor Makers). It loads no code from the internet, sends nothing anywhere, and only fires the game's own request remotes. Every feature starts **off** except Anti-AFK. It is safe to put in autoexec, because anything the game has not loaded yet is looked up again later.

> Using scripts breaks the Roblox Terms of Use and can get an account banned. Use an alt account.

## Use
1. Join Tap Simulator REBORN.
2. Paste the whole contents of `TapSim_Reborn.luau` into your executor and run it. You can also save it in the executor's autoexec folder.
3. Turn features on in the window. **RightControl** hides or shows the window. **X** stops everything and removes the window. Running the script again replaces the running copy.

Your toggles are saved to `TapSimReborn_settings.json` in the executor workspace and come back the next time you run it.

| Toggle | What it sends | Notes |
| :--- | :--- | :--- |
| Auto tap | `TapService.TapRequested {Auto=false, ClientSequence, Source="button"}` | Max 10/s, the server's limit (`GameConfig.ManualTapInterval` = 0.1s). The sequence counter survives re-execution and re-syncs if the server stops answering. It only ever rises and stays below 2^53. |
| Game auto clicker | `AutoClickService.AutoClickRequested {Enabled}` | Turns on the game's own clicker. You must own it (20 gems in Gem Upgrades). |
| Auto rebirth | `RebirthService.RebirthRequested {Index}` | Buys the biggest **unlocked** pack you can afford, at most every 1.5s. **Spends your coins**, so turn it off while you save for an egg or a gate. |
| Auto hatch | `EggService.EggHatchRequested {Egg, Count, Auto=true, Seq}` | Best affordable egg (only moves up with 5 batches banked), or a chosen egg. Teleports you next to it, because the server answers `TooFar` otherwise. Count is 8/3/1 depending on pass, boost and coins. One request in flight at a time. |
| Auto equip best | `PetService.PetActionRequested {Action="EquipBest"}` | Every 5s. |
| Auto buy upgrades | `UpgradeService.Purchase {Name}` | In the game's `UpgradeConfig.Order`. Skips a refused upgrade for 30s. |
| Auto skill tree | `SkillTreeService.Unlock {Name}` | Every node in `SkillTreeConfig`, paid in gems. Locked subtrees are retried. |
| Auto claim quests / chests | `QuestService.ClaimQuest {Quest}`, `TapChestService.Claim(id)` | Only items the save data shows as ready, each tried at most every 10s. |
| Claim offline earnings | `OfflineRewardsService.Claim(false)` | Claims on start, and once whenever you switch it on. |
| Anti-AFK | none (virtual click on `Idled`) | On by default. |
| Print remote list | none (read-only) | Prints every `RemoteServices.<Service>.RE/RF` name and saves it to `TapSimReborn_remotes.txt`. Use it after a game update to see whether names changed. |

## Status (evidence words as in `VY/README.md`)
- **Live game: Implemented Unverified.** The script has not been run in the real game from this repository. The remote names, payloads and data paths come from a public, readable, MIT-licensed hub (see `docs/RESEARCH.md`), not from our own observation.
- **Offline: Verified Working (Lune 0.10.4, mocked runtime).** Six scenarios, 82 checks, run the whole file against a fake game and server. A green run proves the script keeps its own rules against these fakes. It does not prove the live server accepts the requests.
  - `smoke`: tap pacing and sequence re-sync, hatch range and one request in flight, locked rebirth buttons, re-execution and Stop.
  - `late-load`: the script starts 40s before the game's folders exist, as from autoexec.
  - `silent-taps`: the server stops answering taps for 400s.
  - `worker-restart`: the tap remote appears late.
  - `offline-later`: the offline toggle is switched on after start.
  - `stand-spot`: egg models are not streamed in.
- **Proof the tests catch bugs:** each v1.1 fix was first reproduced as a failing scenario on v1.0. Planted bugs (no re-sync, taps too fast, no teleport, locked button, or a 2^52 cap on the tap counter) each turn a scenario red.

Run all six scenarios with Lune alone, no Python needed. Run it from the folder that holds `TapSim\`.
```
.\tools\lune.exe run TapSim/tests/lune/run_all.luau        # Windows, lune.exe in tools\
lune run TapSim/tests/lune/run_all.luau                    # Linux/macOS, lune on PATH
lune run TapSim/tests/lune/edge.luau TapSim/TapSim_Reborn.luau late-load   # one scenario
```
`python TapSim/tests/run_tests.py` does the same if you have Python.

Virtual time runs 40x faster than real time, or 4x on Windows. Windows never sleeps less than ~15.6 ms, which at 40x stretched the 0.1s tap gap and failed the tap checks. On Windows the full run takes about 3 minutes, most of it `silent-taps`. Set `TAPSIM_SPEED=<n>` to override the speed.

## Changes in v1.1
- **Autoexec:** v1.0 read the game's config and save data once at start. If the game had not loaded yet, hatch, rebirth and the status line stayed dead all session. They are now looked up again until found, and remotes are waited for instead of timing out.
- **Workers restart:** a feature whose worker hits an error starts again 3 seconds later. In v1.0, auto tap or auto hatch stopped until you re-ran the script.
- **Tap counter:** the re-sync doubled the tap counter with no limit. After about 90 seconds of unanswered taps it passed 2^53, where adding 1 no longer changes it, so every tap was ignored. It now doubles up to 2^50, then rises by a million at a time, and never goes down. (A plain cap at 2^52 resets it lower, which also stops taps.)
- **Stand spot:** the raycast ignore list had a nil hole when the egg model had not streamed in, which sent you to the fallback spot. It no longer does.
- **Offline toggle:** switching "Claim offline earnings" on now claims right away.
- **Status lines:** the rebirth count is read from your save, and quests and chests only show as claimed when the server accepted the claim.
- **Stop:** Stop no longer waits on a remote that never loaded.

If something stops working after a game update, press **Print remote list** and compare the names with the table above.
