# RankPilot X v5.1 Feature Expansion

## What is in this build

This is the **second stage** of the ZapHub-style RankPilot X project. The preexisting 14-page v5.0 interface and its later v4.6 VY-enhanced automation engine are the working foundation. The user's newly uploaded `RankPilot_PS99_DZ_v3.lua.txt` is a v3.10 source revision dated October 9, 2026. It was examined and included as a reference. It is **not** silently swapped into the newer engine, which has extra fixes and VY features not present in v3.10.

### Implemented additions

- **Login streak**: only claim when `LoginStreakCmds.CanClaim()` explicitly reports ready; verify afterward.
- **Timed rewards**: inspect `Directory.TimedRewards`, `Save.TimedRewardTimestamps`, and `MachineCmds.GetModels`; use a movement lease and return to origin.
- **Auto balloons**: optional Small/Medium/Huge filtering, rebirth requirement, slingshot equip/fire/hit with cooldown and disarm on pause/stop. Hit count is attempts, not confirmed pops.
- **Player upgrades**: read `UpgradeCmds.All`, `CanInteractWith`, `Directory.Upgrades`, and `CurrencyCmds.Get`. Opt-in and maximum 15% of the currency balance for each purchase. Only count a confirmed increase in upgrade tier.
- **Visual cleanup**: new reversible hide-balloon and hide-breakable graphics, optional Fullbright with restoration.
- **Notifications**: local in-hub rank/reward alerts; no webhook, credential reads or account uploads.
- **Inventory**: read-only counts by category.
- **Minigame discovery**: inspect loaded client module names without claiming to automate the games.
- **All previously working v4.6 RankPilot/VY functions** are retained, including `math.huge` pet speed (ON by default) and stable bulk pet targeting.

### How to run

1. Save `RankPilot_X_v5_1_Feature_Expansion.lua` to your Potassium executor workspace. Do not execute v5.0 or v3.10 at the same time.
2. Execute this file in Pet Simulator 99. It starts **PAUSED** by default, so press START.
3. In the sidebar, open `Machines & Collection` to opt in to Login Streak, Timed Rewards, or Player Upgrades.
4. Open `Events` to opt in to balloon popping. It needs at least three rebirths according to the sampled source.
5. Open `Optimization` for Hide Breakable Visuals, Hide Balloon Visuals, or Fullbright.
6. Open `Notifications` to see local alerts, `Trading & Mailbox` for read-only inventory counts, and `Minigames` to inspect available modules.
7. Use `Diagnostics > COPY FULL REPORT` if a feature fails. The report distinguishes requests from verified game progress when supported.

A cross-world travel reload must use the same workspace filename specified by `Config.VYLocalWorkspaceFile`. This option is OFF by default.

### Important limitations

This was **not tested in live PS99/Potassium**. Roblox and the executor can change. Some requests can be accepted without completing a game action. Infinite client pet speed `math.huge` can cause instability and does not increase server-side pet damage. The new opt-in systems may need adjustments after a real game report.

Minigame automation, booth selling, automated mailbox transfers, timed raids, fishing, digging and the complete advertised ZapHub 100+ feature list are **not yet implemented**. The corresponding pages do not pretend they are.

The helper files in `tests/` use Lua 5.4 mocks and Python. They cannot validate remote compatibility with the live game.
