# Diamond Mountain (PS99 update 98) — live findings

Sources (redacted reports, kept by the user), Potassium v2.5.3, one account. "Unknown" means no run showed it yet.
- **Run 1:** 2026-10-17 23:29 UTC. First entry, the tutorial, wall 1 loads, a camp egg.
- **Run 2:** 2026-10-18 00:21 UTC, 120 FPS. Wall 1 already broken; 642 pets loaded on wall 2, 252 camp-2 eggs, Offline Hours bought, a lift ride.
  - This run used the **previous** probe copy (no replies, no sections 6b/8). Its recorder filled at +29 s with farming requests, so only the Save diff covers the whole 300 s.

## Where the event runs
- **Not a separate place.** The probe ran in PlaceId `16498369169` (Tech World, World 2). The event is an **instance in that server**:
  - state folder `Workspace.__THINGS.Instances.DiamondMountain`, scenery `__THINGS.__INSTANCE_SCENERY.DiamondMountain` (`Mountain`, `Camps`), ground `__THINGS.__FAKE_INSTANCE_GROUND.DiamondMountain`.
  - Entering needs no teleport and no VM restart. Whether World 1/3/4 servers also host it is unknown.
- **Enter** (the game's own requests, +21.2 s / +22.3 s): `Instancing_PrepareEnter("DiamondMountain")` (FireServer), then `Instancing_PlayerEnterInstance("DiamondMountain")` (InvokeServer).
- **On join the client sends:**
  - InvokeCustom `DM_Walls_Status`, `DM_Expedition_State`, `DM_Lifts_Riders`, `DM_Trips_Status`, `DM_Drip_WallSpot(1, Vector3)`;
  - `AutoHatch_Disable()`, `Instances: Mark Entered("DiamondMountain")`, `SM_Recall()`, `MachineScreens_Get("DiamondMountainUpgradeMachine")`.
- **Executor:** Potassium v2.5.3, thread identity **8**, all 21 checked functions present (hookmetamethod, setnamecallmethod, firetouchinterest, fireproximityprompt, queue_on_teleport…). VY v1.1.9's identity fix therefore changes nothing live here.

## Event actions: one remote
`Instancing_InvokeCustomFromClient("DiamondMountain", "<DM_action>", ...)` (RemoteFunction). Seen:

| Action | Arguments seen | Effect (Save diff) |
|---|---|---|
| `DM_Walls_Load` | `1, {<pet stack uid> = 1}`, `1, {<uid> = 2}` | Pets join wall 1's crew: `InstanceVars.DiamondMountain.WallCrew.1["<id>\|<pt>\|<sh>"] = {count, power, id, data}` |
| `DM_Drip_WallSpot` | `1, Vector3` (on join) | Falling diamonds: `Drip.Paid` 77, `Drip.Rain.1` 77; Diamonds +77 |
| `DM_Tutorial_CutsceneSeen` / `_Step` / `_Skip` | `"intro"` / `1`…`4` / `5` | `Tutorial` = 5, `Cutscenes` = 1, `StarterPet` = true |

Camp egg: `CustomEggs_Hatch("<egg uid>", 3)` and `(…, 1)` (InvokeServer). Then the game sends `SM_Unmask({<new pet uids>})`. Where the egg uid comes from is unknown; the improved probe lists `__THINGS` egg folders.

## Walls (run 2)
- **Wall 1 HP is 130,000,000.** At the start of run 2, `Walls.Broken.1` = true and `Walls.Dealt.1` = 130,000,000 exactly.
- **A broken wall releases its crew:** `WallCrew.1` was gone. Breaking it unlocked camp 2 (`InstanceZones.__Zone_2`).
- **Pets stay in the inventory.** The Marmot stack stayed at 331 while `WallCrew.2` held 331 Marmots, so the wall only counts pets you own.
- **No crew limit seen:** 642 pets on wall 2. `DiamondMountainWallSlots` is still disabled.
- **Power per pet** (`WallCrew.<wall>.<kind>.power`), normal / golden (×1.5) / shiny (×1.75):
  - Marmot 100 / 150 / 175
  - Hiker Raccoon 150 / 225 / 263
  - Hiker Red Panda 220 / 330 / –
  - Climber Bear 330
  - Climber Goat 480
- **Wall 2 progress:** `Walls.Dealt.2` went 0 → 20,120,604 in ~302 s (`Walls.At` moved 302.5 s) while the crew was being loaded. The full crew's base power is 91,958. Wall 2's HP is unknown.
- **Camp 2's egg is `Russet Falls Egg`** (`PurchasedEggs` 252 in run 2; `Trailhead Egg` 515 in all). `EventEggReach.DiamondMountain` went 1 → 2.
- **Falling diamonds** (`Drip`) are a big diamond source. `Drip.Paid` went 79,825 → 418,506 and Diamonds rose by the same 418,506 in 5 minutes.
  - `Drip.WindowStart` moved to 2026-10-18 00:00 UTC, so the counter is per UTC day.
  - `Drip.Rain.<camp>` and `Drip.Walls["<wall>:<stage>"]` track the rain and the stage drops of each wall.
- **Camp-2 join:** `DM_Drip_WallSpot` is sent for walls 1 and 2.
- **Lifts:** `DM_Lifts_Sit(1, 10)` then `DM_Lifts_Stand()`; new `BestAltitude` 60.
- **Camp farming** uses the normal `Breakables_JoinPetBulk({<pet> = "<breakable uid>"})`, the same request VY's farming sends.
- **TrailCoins** went 31,246 → 78,486 despite 252 egg hatches.
- **Upgrades:** owned `DiamondMountainWallPower` 1 and `CoinFinder` 1, plus `OfflineHours` 1 bought during run 2. The purchase request was not recorded.

## Save layout (`Save.InstanceVars.DiamondMountain`, created on first entry)
- `Walls.Broken.1..5` (all false) and `Walls.Dealt.1..5` (wall 1: 161,386): **5 walls**. `Walls.At` (unix time, likely for offline smashing), `Walls.Frac`, `WallDamage` (161,386), `WallBoost` (1).
- `WallCrew.<wall>.<"Id|pt|sh">`: base **power per pet** at normal/no-shiny: Marmot 100, Hiker Raccoon 150, Hiker Red Panda 220. Wall 1 crew at the end: 2 Marmot, 3 Raccoon, 1 Red Panda.
- `Drip.Paid`, `Drip.Rain.<camp>`, `Drip.WindowStart` (2026-10-17 00:00 UTC).
- `InstanceZones.__Zone_1`. Elsewhere: `Save.EnteredInstances.DiamondMountain`, `Save.EventEggReach.DiamondMountain` = 1, `Save.ApproachedMachines.DiamondMountainUpgradeMachine`.
- **Currency.** The mountain pays **`TrailCoins`** (3,592 after the visit). In `Directory.Currency` both `Acorns` and `TrailCoins` have DisplayName **"Acorns"**. Which one eggs, upgrades and the merchant charge is unknown.
- Drops: consumable `Trail Coins Boost` (also in Directory: `Trail Damage Boost`, `Trail Luck Boost`).

## Directory (game data in the client)
- Eggs: `Trailhead Egg` (`Eggs.Events.DiamondMountain.1`) … `Diamond Summit Egg` (`….6`). The names of camps 2–5's eggs contain no event word; read them from that folder next time.
- EventUpgrades, in order:
  1. `DiamondMountainWallPower`
  2. `DiamondMountainWallSlots` (**Disabled = true** today)
  3. `DiamondMountainOfflineHours`
  4. `DiamondMountainCoinFinder` ("Acorn Finder")
  5. `DiamondMountainTrailLuck`
  6. `DiamondMountainExpeditionSpeed`

  Likely remote: `EventUpgrades: Purchase` (not yet seen).
- Boosts: `DiamondMountainCoins1/2` (Acorns), `DiamondMountainDamage1/2`, `DiamondMountainLuck1/2`.
- Merchant `DiamondMountainMerchant`. Its offers come from a function. Candidate remotes: `TravelingMerchant_GetState`, `TravelingMerchant_RequestPurchase`. The client util `DiamondMountainMerchant` has `CampOf`, `VisitAt`, `NextVisitAt`, `MoveSeconds`, so the wagon's schedule is computable.
- Leaderboard `DiamondMountainYetiPoints` ends **Fri 2026-10-23 16:00 UTC**.
- Event pets (zone 279): Marmot, Hiker Raccoon, Hiker Red Panda, Climber Goat, Climber Bear, Expedition Wolf/Leopard/Dog, Equinox Fox/Deer, Amber Markhor, Abominable Yeti.

## Client code worth calling or reading
- `Library.Client.DiamondMountainCmds`, with children:
  - `Walls`: `FillBest`, `Load`, `LoadAll`, `Status`, `Target`, `WallPower`…
  - `Yeti`: `Load`, `LoadAll`, `LoadStacks`, `CanLoad`, `Menu`…
  - `Expedition`: `State`, `Read`, `Refresh`, `Sync`
  - `Merchant`, `Summit`, `Trails` (`Closed`, `EggLeft`…), `Upgrades` (`Buy`, `CanAfford`, `Cost`, `IsMax`, `Tracks`)
- `Library.Modules.InstanceDamageModules.DiamondMountain` (`IsEventPet`, `ComputeBestPetDamage`, `BoostMult`, `Compute`): wall damage seems to count event pets only.
- Utils:
  - `DiamondMountainYetiMath`, `…Trips` (`Accrue`, `Cap`, `Rate`: probably expeditions), `…TripLoot`
  - `…TrailLuck`, `…Drip`, `…Merchant`, `…Accrual`, `…Copy`

## Live state on `__THINGS.Instances.DiamondMountain` (attributes)
- `DM_YetiHealth` 199,905,791 / `DM_YetiMaxHealth` 212,940,000 (93.9%), plus `DM_YetiAt`, `DM_YetiFloor`, `DM_YetiUid`. The Yeti's state can be read without any request.
- `DM_Trail1Chest`…`DM_Trail6Chest` (the chest index per trail).
- `DM_Hype*`: `Meter` 0, `Need` 980,000, `Stage` 1, `Holding`, `Pad`, `PadReach` 32, `Top`.

## Probe limits found in run 1 (fixed after it)
- The recorder's 200 lines were full at +138 s, mostly fps pings (`UnreliableRemoteEvent`). Later actions are missing; for example, the Red Panda load is in the Save diff but not in the recording.
- No server replies were recorded.
- The world scan ran before entering the mountain.
- The Save diff was capped at 300 lines, of which about 170 were telemetry.

## Still unknown (the v3 probe captures these)
- The server's replies: `DM_Walls_Status` (wall 2+ HP) and what `DM_Walls_Load` returns. Also whether the game's own "load all" sends many stacks in one request.
- The camp egg uid source, the names of camp eggs 2–5, and which currency eggs, upgrades and the merchant use.
- The requests for: an upgrade purchase, the merchant, using a boost, feeding/fighting the Yeti, expeditions, trail chests, lifts (`DM_Lifts_Riders`).
- Whether World 1/3/4 servers host the mountain too. (Answered: pets on a wall stay in the inventory.)
