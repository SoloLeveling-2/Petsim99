# Tap Simulator REBORN helper

`TapSim_Reborn.luau` is a single readable executor script for the Roblox game **Tap Simulator REBORN** (place `72858262610964`, developer Cursor Makers). It loads no code from the internet, sends nothing anywhere, and only fires the game's own request remotes. Every feature starts **off**.

> Using scripts breaks the Roblox Terms of Use and can get an account banned. Use an alt account.

## Use
1. Join Tap Simulator REBORN.
2. Paste the whole contents of `TapSim_Reborn.luau` into your executor and run it. You can also save it in the executor's autoexec folder.
3. Turn features on in the window. **RightControl** hides or shows the window. **X** stops everything and removes the window. Running the script again replaces the running copy.

Your toggles are saved to `TapSimReborn_settings.json` in the executor workspace and come back the next time you run it.

| Toggle | What it sends | Notes |
| :--- | :--- | :--- |
| Auto tap | `TapService.TapRequested {Auto=false, ClientSequence, Source="button"}` | Max 10/s, the server's limit (`GameConfig.ManualTapInterval` = 0.1s). The sequence counter survives re-execution and re-syncs if the server stops answering. |
| Game auto clicker | `AutoClickService.AutoClickRequested {Enabled}` | Turns on the game's own clicker. You must own it (20 gems in Gem Upgrades). |
| Auto rebirth | `RebirthService.RebirthRequested {Index}` | Buys the biggest **unlocked** pack you can afford, at most every 1.5s. **Spends your coins**, so turn it off while you save for an egg or a gate. |
| Auto hatch | `EggService.EggHatchRequested {Egg, Count, Auto=true, Seq}` | Best affordable egg (only moves up with 5 batches banked), or a chosen egg. Teleports you next to it, because the server answers `TooFar` otherwise. Count is 8/3/1 depending on pass, boost and coins. One request in flight at a time. |
| Auto equip best | `PetService.PetActionRequested {Action="EquipBest"}` | Every 5s. |
| Auto buy upgrades | `UpgradeService.Purchase {Name}` | In the game's `UpgradeConfig.Order`. Skips a refused upgrade for 30s. |
| Auto skill tree | `SkillTreeService.Unlock {Name}` | Every node in `SkillTreeConfig`, paid in gems. Locked subtrees are retried. |
| Auto claim quests / chests | `QuestService.ClaimQuest {Quest}`, `TapChestService.Claim(id)` | Only items the save data shows as ready, each tried at most every 10s. |
| Claim offline on start | `OfflineRewardsService.Claim(false)` | |
| Anti-AFK | none (virtual click on `Idled`) | On by default. |
| Print remote list | none (read-only) | Prints every `RemoteServices.<Service>.RE/RF` name and saves it to `TapSimReborn_remotes.txt`. Use it after a game update to see whether names changed. |

## Status (evidence words as in `VY/README.md`)
- **Live game: Implemented Unverified.** The script has not been run in the real game from this repository. The remote names, payloads and data paths come from a public, readable, MIT-licensed hub (see `docs/RESEARCH.md`), not from our own observation.
- **Offline: Verified Working (Lune 0.10.4, mocked runtime).** `tests/lune/smoke.luau` runs the whole file against a fake game and server: 47 checks, including tap pacing and sequence re-sync, hatch range and one-in-flight, locked rebirth buttons, re-execution and Stop. Planted bugs (no re-sync, taps too fast, no teleport, locked button) each turn it red. A green run proves the script keeps its own rules against these fakes. It does not prove the live server accepts the requests.

```
lune run TapSim/tests/lune/smoke.luau TapSim/TapSim_Reborn.luau
```

If something stops working after a game update, press **Print remote list** and compare the names with the table above.
