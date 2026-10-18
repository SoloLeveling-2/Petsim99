# Diamond Mountain (PS99 update 98) — live findings

Sources (redacted reports, kept by the user), Potassium v2.5.3, one account. "Unknown" means no run showed it yet.
- **Run 1:** 2026-10-17 23:29 UTC. First entry, the tutorial, wall 1 loads, a camp egg.
- **Run 2:** 2026-10-18 00:21 UTC, 120 FPS. Wall 1 already broken; 642 pets loaded on wall 2, 252 camp-2 eggs, Offline Hours bought, a lift ride.
  - This run used the **previous** probe copy (no replies, no sections 6b/8). Its recorder filled at +29 s with farming requests, so only the Save diff covers the whole 300 s.
- **Run 3:** 2026-10-18 02:36–02:41 UTC, probe v5, with **ZapHub** running. Walls 1 and 2 already broken, wall 3 being smashed.
  - ZapHub's requests carry `[script]`: 12× `DM_Walls_Status`, 2× `DM_Walls_FillBest`, 23× `CustomEggs_Hatch`. Nothing else was tagged.
  - So in this window ZapHub bought no upgrade, used no merchant or boost, and did not touch the Yeti or expeditions. It may have done something without `remote:InvokeServer/FireServer`, which the probe cannot see.
  - **v5 works live:** server replies were captured, and `[script]` told ZapHub's requests apart from the game's own.

## Where the event runs
- **Not a separate place.** The probe ran in PlaceId `16498369169` (Tech World, World 2). The event is an **instance in that server**:
  - state folder `Workspace.__THINGS.Instances.DiamondMountain`, scenery `__THINGS.__INSTANCE_SCENERY.DiamondMountain` (`Mountain`, `Camps`), ground `__THINGS.__FAKE_INSTANCE_GROUND.DiamondMountain`.
  - Entering needs no teleport and no VM restart. Whether World 1/3/4 servers also host it is unknown.
- **Enter** (the game's own requests, +21.2 s / +22.3 s): `Instancing_PrepareEnter("DiamondMountain")` (FireServer), then `Instancing_PlayerEnterInstance("DiamondMountain")` (InvokeServer).
- **On join the client sends:**
  - InvokeCustom `DM_Walls_Status`, `DM_Expedition_State`, `DM_Lifts_Riders`, `DM_Trips_Status`, `DM_Drip_WallSpot(1, Vector3)`;
  - `AutoHatch_Disable()`, `Instances: Mark Entered("DiamondMountain")`, `SM_Recall()`, `MachineScreens_Get("DiamondMountainUpgradeMachine")`.
- **While on the mountain the client polls** `DM_Walls_Status` about every 15 s and `DM_Trips_Status` about every 20 s (run 3: 20 and 15 calls in 300 s).
- **Executor:** Potassium v2.5.3, thread identity **8**, all 21 checked functions present (hookmetamethod, setnamecallmethod, firetouchinterest, fireproximityprompt, queue_on_teleport…). VY v1.1.9's identity fix therefore changes nothing live here.

## Event actions: one remote
`Instancing_InvokeCustomFromClient("DiamondMountain", "<DM_action>", ...)` (RemoteFunction). Seen:

| Action | Arguments seen | Reply / effect |
|---|---|---|
| `DM_Walls_FillBest` | `3` (the wall) | `true, nil`: the server put **every spare event pet** on wall 3 (crew 768 → 957, same 10 kinds). Again: `false, "No spare pets to send!"`. Sent by ZapHub (run 3) |
| `DM_Walls_Load` | `1, {<pet stack uid> = 1}`, `1, {<uid> = 2}` | Pets join wall 1's crew: `InstanceVars.DiamondMountain.WallCrew.1["<id>\|<pt>\|<sh>"] = {count, power, id, data}`. Reply not seen |
| `DM_Walls_Status` | — | Every wall's HP and damage rate (see Walls) |
| `DM_Trips_Status` | — | Expedition pedestals (see Expeditions) |
| `DM_Drip_WallSpot` | `1, Vector3` (on join) | Falling diamonds: `Drip.Paid` 77, `Drip.Rain.1` 77; Diamonds +77 |
| `DM_Tutorial_CutsceneSeen` / `_Step` / `_Skip` | `"intro"` / `1`…`4` / `5` | `Tutorial` = 5, `Cutscenes` = 1, `StarterPet` = true |

## Camp eggs
- **Hatch:** `CustomEggs_Hatch("<egg model name>", <eggs>)` (InvokeServer) → `true, nil`. Runs 1–2: `3` and `1` (the game). Run 3: ZapHub sent `("385d37df6d1b4dff90f08efe14bb4e2f", 63)` 23 times, about one every 1.6 s.
  - After each hatch the game itself sends `SM_Unmask({<the new pets' uids>})`.
- **The egg uid is the name of a model in `Workspace.__THINGS.CustomEggs`.** The model's attribute `DM_EggId` names the egg. Its `PriceHUD.PriceHUD.Acorns` frame shows the price. Run 3:
  - `385d37df…` `DM_EggId="Boulder Ridge Egg"`: the camp-3 egg ZapHub hatched.
  - `ecb2a9e1…` `DM_EggId="Russet Falls Egg"`: the camp-2 egg.
  - `e72555ee…` `DM_EggId="Boulder Ridge Egg", DM_TrailEgg=3, DM_TrailHugeRow=true, DM_TrailTitanicRow=false`: a **trail egg** (trail 3). Whether trail eggs hatch the same way is unknown.
  - Other events' custom eggs (Witching Egg, Werewolf Egg…) sit in the same folder without `DM_EggId`. Camp 1's egg was not in the folder at the end (camp 3), so far eggs may not be loaded.
- **Camp eggs:** 1 `Trailhead Egg`, 2 `Russet Falls Egg`, 3 `Boulder Ridge Egg`, …, 6 `Diamond Summit Egg`. The modules sit in the Directory's `Eggs.Events.DiamondMountain` folder, as `"<camp> | <name>"`. Camps 4 and 5's names are still unknown (probe v5.1 lists them).
- **Price:** 1,449 Boulder Ridge Eggs cost TrailCoins 99,406,234 → 56,206,744, so **about 29,813 each**. Farming added coins meanwhile, so the real price is a little higher. `PurchasedEggs["Boulder Ridge Egg"]` went from none to 1,449, and `EventEggReach.DiamondMountain` went 2 → 3.
- **Boulder Ridge Egg drops (1,449 eggs):**
  - Climber Bear 865 + 21 golden (61%)
  - Climber Goat 290 + 8 golden (21%). The 290 went to the stack that held 17; both the Climber Goat and the golden Marmot stacks held 17, and Goat is far more likely.
  - Expedition Wolf 208 + 9 golden + 1 shiny (15%)
  - Expedition Leopard 45 + 2 golden (3%)

## Walls
- **HP (`DM_Walls_Status` `walls[n].max`):**

  | Wall | HP |
  |---|---|
  | 1 | 130,000,000 |
  | 2 | 760,000,000 |
  | 3 | ~4,350,000,000 |
  | 4 | 34,000,000,000 |
  | 5 | 250,000,000,000 |

  - **Wall 3's HP went down while we watched:** 4,353,645,833 → 4,348,770,833 in 53.7 s, about 90,800 a second. Why, and whether walls 4 and 5 do the same once open, is unknown.
- **The `DM_Walls_Status` reply:** `{at, total, cap = 21600, stackMax = 100, slots = 17, walls = {[n] = {n, open, broken, max, dealt, rate, stacks}}}`.
  - `total` matches `Save…WallDamage` (lifetime damage). `open` matches `InstanceZones.__Zone_n`: wall 4 was `open = false` with camp 4 locked. `rate` is damage per second.
  - `cap` 21,600 s = 6 h, probably the offline cap. `slots` and `stackMax` are unexplained: wall 3 held 10 kinds, and one kind held 331 pets, more than 100.
- **Damage per second = the crew's power × 2.352** for this account (Wall Power tier 2), measured twice: 117,603 → 276,602/s before FillBest, 157,188 → 369,702/s after. `Walls.Dealt.3` grew by 350,182/s on average over the 5 minutes.
- **A broken wall releases its crew:** `WallCrew.1` was gone. Breaking it unlocked camp 2 (`InstanceZones.__Zone_2`).
- **Pets stay in the inventory.** The Marmot stack stayed at 331 while `WallCrew.2` held 331 Marmots, so the wall only counts pets you own.
- **No crew limit seen:** 642 pets on wall 2 (run 2), 957 on wall 3 (run 3). `DiamondMountainWallSlots` is still disabled.
- **Power per pet** (`WallCrew.<wall>.<kind>.power`), normal / golden (×1.5) / shiny (×1.75):
  - Marmot 100 / 150 / 175
  - Hiker Raccoon 150 / 225 / 263
  - Hiker Red Panda 220 / 330 / –
  - Climber Bear 330 / 495 / –
  - Climber Goat 480
  - Expedition Wolf / Leopard: unknown. They were hatched after the last fill, so they were never on a wall.
- **Wall 2 progress (run 2):** `Walls.Dealt.2` went 0 → 20,120,604 in ~302 s while the crew was being loaded.
- **Falling diamonds** (`Drip`) are a big diamond source. `Drip.Paid` went 79,825 → 418,506 in run 2 (Diamonds rose by the same amount), but only +4,206 in run 3.
  - `Drip.WindowStart` moved to 2026-10-18 00:00 UTC, so the counter is per UTC day (1,178,284 paid by 02:36).
  - `Drip.Rain.<camp>`, `Drip.Avalanche.<camp>` and `Drip.Walls["<wall>:<stage>"]` track the rain, the avalanches and each wall's stage drops.
- **Camp-2 join:** `DM_Drip_WallSpot` is sent for walls 1 and 2.
- **Lifts:** `DM_Lifts_Sit(1, 10)` then `DM_Lifts_Stand()`; new `BestAltitude` 60 (135 by run 3).
- **Camp farming** uses the normal `Breakables_JoinPetBulk({<pet> = "<breakable uid>"})`, the same request VY's farming sends.
- **TrailCoins** went 31,246 → 78,486 in run 2 despite 252 egg hatches. The account had 99.4 M by run 3.

## Expeditions (`DM_Trips_Status`, run 3)
- The reply is `{at, trayHours = 8, on = true, subscriber = false, ready = 0, readyRolls = 0, loot = {}, pedestals = {...}}`.
- Each pedestal is `{n, unlocked, price, rolls, rollFrom, away}`:
  - 1: unlocked, price 0
  - 2: 150,000,000,000
  - 3: 400,000,000,000
  - 4: 1,000,000,000,000

  The prices' currency is unknown.
- At the summit, `Summit.Expedition.PedestalN` has a ProximityPrompt "Unlock" / "Expedition N", and there is a `ClaimPillar`. Save: `Expedition.Shown` 0, `.Rolled` 0, `.Merchant` true.
- The requests to start or claim an expedition are unknown.

## Yeti, hype train, trails (attributes on `__THINGS.Instances.DiamondMountain`)
- **Yeti:** run 3 started at `DM_YetiHealth` 424,247,788 / `DM_YetiMaxHealth` 608,400,000 (run 1: 212,940,000).
  - By the end the health attributes were gone and `DM_YetiBackAt` = 02:44:01 UTC, so the Yeti was beaten during the run and comes back on a timer.
  - Also `DM_YetiAt`, `DM_YetiFloor`, `DM_YetiUid`; `Workspace.DM_YetiLoad` is a part. Client: `DiamondMountainCmds.Yeti` `Load/LoadAll/LoadStacks/CanLoad`, so the Yeti also takes pets. Its request is unknown.
- **Hype train:** `DM_HypeNeed` 24,000,000 (run 1: 980,000), `DM_HypeStage` 5 → 4, `DM_HypeMeter`, `DM_HypeHolding`, `DM_HypePad` + `DM_HypePadReach` 32, `DM_HypeTop` (a JSON top list of `{name, coins}`).
- **Trails 1–6:** `DM_Trail<n>Chest` (1) and `DM_Trail<n>SleepUntil` (unix time; trail 6 slept until 02:49 UTC).
  - In the world, `Trails.<n>` holds `Gate`, `Sign`, `Chest1..3` and `Room1..3` (attribute `Room`), and `Clearing.EggPedestal`.
  - The Directory has `Chests.DiamondMountainTrailChest`.

## World layout (`__INSTANCE_CONTAINER.Active.DiamondMountain`, run 3)
- `Camps.<n>`:
  - `Wall`: `Opens` = n+1. Its `Blocker` has `WallState` "Cleared" or "Intact" (camp 5's wall says `Camp=4`).
  - `WallFront`, `Merchant`, `MerchantSign`, `EntrySign`, `Lift` (`Layer`), `LiftTop` (`From`), `Shelters`. Camp 6 also has the Yeti leaderboard.
- `SkiLifts.<n>` (`From`, `To`) with numbered `SkiChair`s; `Pitches.<n>` (`Grade`, `Rise`, `Walk`; `Base`/`Top` name camps); `Teleports.1..6` (zone teleports); `BREAK_ZONES.Zone1..6`.
- `Artifacts.1..6` are PSX doors: Pet Collection Machine, Upgrade Station, Enchanting (`PadGui="EnchantPets"`), Bank, Shop Sign, Grand Heaven Chest.
- `Summit`: `Diamond`, `YetiArena`, `HypeTrain`, `Expedition` (`Pedestal1..4`, `ClaimPillar`), `XDoorFrame`.
- `INTERACT.Machines.DiamondMountainUpgradeMachine` (`DisplayName="Upgrades"`).

## Save layout (`Save.InstanceVars.DiamondMountain`, created on first entry)
- **Walls:**
  - `Walls.Broken.1..5`, `Walls.Dealt.1..5`: **5 walls**.
  - `Walls.At` (unix time of the last accrual), `Walls.Frac`, `WallDamage` (lifetime), `WallBoost` (1).
  - `WallCrew.<wall>.<"Id|pt|sh">` = `{id, count, power, data = {id, _am, pt, sh}}`.
- **Drip:** `Drip.Paid`, `.Rain.<camp>`, `.Avalanche.<camp>`, `.Walls`, `.WindowStart`.
- **Other fields:**
  - `InstanceZones.__Zone_<camp>`, `Expedition.*`, `BestAltitude`, `Tutorial`, `Cutscenes`, `StarterPet`.
  - Elsewhere: `Save.EnteredInstances.DiamondMountain`, `Save.EventEggReach.DiamondMountain` (3 after the first Boulder Ridge hatch), `Save.PurchasedEggs["<egg>"]`, `Save.ApproachedMachines.DiamondMountainUpgradeMachine`.
- **Upgrades:** `Save.EventUpgrades.DiamondMountain<Name>` = tier. In run 3: WallPower 2, OfflineHours 2, CoinFinder 2, TrailLuck 1.
- **Merchant:** `Save.MerchantPurchases.DiamondMountainMerchant.Seed`.
- **Currency.** The mountain pays **`TrailCoins`** (`Save.Inventory.Currency.<uid> = {id = "TrailCoins", _am}`); camp eggs charge it. In `Directory.Currency` both `Acorns` and `TrailCoins` have DisplayName **"Acorns"**. Which currency upgrades and the merchant charge is unknown.
- **Drops:** consumables `Trail Coins Boost` (7 owned in run 3), `Trail Luck Boost`, `Trail Damage Boost` (tradable, with tiers).

## Directory (game data in the client)
- EventUpgrades, in order:
  1. `DiamondMountainWallPower`
  2. `DiamondMountainWallSlots` (**Disabled = true** today)
  3. `DiamondMountainOfflineHours`
  4. `DiamondMountainCoinFinder` ("Acorn Finder")
  5. `DiamondMountainTrailLuck`
  6. `DiamondMountainExpeditionSpeed`

  Likely remote: `EventUpgrades: Purchase` (RemoteFunction; client `EventUpgradeCmds.Purchase/1`, `DiamondMountainCmds.Upgrades.Buy/1`). Not yet seen.
- Boosts: `DiamondMountainCoins1/2` (Acorns), `DiamondMountainDamage1/2`, `DiamondMountainLuck1/2`.
- Merchant `DiamondMountainMerchant` (`PriceMult` 1, `GetOffers` and `OnPurchased` functions, `DisableApproachOpen`). Candidate remotes: `Merchant_RequestPurchase`, `Merchant_GetOffers`. The client util `DiamondMountainMerchant` has `CampOf`, `VisitAt`, `NextVisitAt`, `MoveSeconds`, so the wagon's schedule is computable.
- Leaderboard `DiamondMountainYetiPoints` ends **Fri 2026-10-23 16:00 UTC**.
- Event pets: Marmot, Hiker Raccoon, Hiker Red Panda, Climber Goat, Climber Bear, Expedition Wolf/Leopard/Dog, Equinox Fox/Deer, Amber Markhor, Abominable Yeti.
  - **Zone 279 does not identify them.** The Wall Crew v0.1 dry run (2026-10-18) found other events' pets in that zone too: Stitched Cat/Dragon, Mothman, Lucky Stacked Bunny/Capybara/Elephant, Lucky Surprise Ducky.
  - The camp eggs' modules (above) list them. So does the server: `DM_Walls_FillBest` picks them itself.
- **`Directory.Pets` raises an error for an unknown name:** `ReplicatedStorage.Library.Directory.Pets:28: Unknown Directory Pets.'Nice'`, from its `__index` (live, Wall Crew v0.2). A camp egg's pet entries also hold non-pet words such as "Nice". Look up any name that may not be a pet only inside `pcall`.

## Client code worth calling or reading
- `Library.Client.DiamondMountainCmds`, with children:
  - `Walls`: `FillBest/1`, `Load/2`, `LoadAll/2`, `Status/0`, `Target/1`, `WallPower/1`, `OpenMenu`, `PickerOrder`…
  - `Yeti`: `Load`, `LoadAll/1`, `LoadStacks/1`, `CanLoad`, `Menu`, `PickUp/2`…
  - `Expedition`: `State`, `Read`, `Refresh`, `Sync`, `EggLuck`
  - `Merchant` (`Open`, `LookAtWagon`), `Summit` (`Open`, `State`), `Trails` (`Closed`, `ClosedFor`, `EggLeft`, `GateProbe`…), `Upgrades` (`Buy`, `CanAfford`, `Cost/2`, `IsMax`, `Tracks`)
- `Library.Modules.InstanceDamageModules.DiamondMountain` (`IsEventPet/1`, `ComputeBestPetDamage/1`, `BoostMult/1`, `Compute/3`): wall damage seems to count event pets only.
- Utils:
  - `DiamondMountainYetiMath`, `…Trips` (`Accrue`, `Cap`, `Rate`, `RollRate`), `…TripLoot`
  - `…TrailLuck`, `…Drip`, `…Merchant`, `…Accrual`, `…Copy`, `…Route`, `…Looks`, `…Money`, `…YetiLoot`

## Probe limits found (fixed after each run)
- Run 1:
  - The recorder's 200 lines were full at +138 s, mostly fps pings (`UnreliableRemoteEvent`). Later actions are missing; for example, the Red Panda load is in the Save diff but not in the recording.
  - No server replies were recorded.
  - The world scan ran before entering the mountain.
  - The Save diff was capped at 300 lines, of which about 170 were telemetry.
- Run 3: section 3b missed camp eggs 2–5, because their names hold no event word. v5.1 also matches an entry whose module sits in a `DiamondMountain` folder.

## Still unknown
- The requests for: an upgrade purchase, the merchant, using a boost, loading or fighting the Yeti, starting or claiming an expedition, trail chests and trail eggs.
- Camps 4 and 5's egg names and prices, and the currency of upgrades, the merchant and expedition pedestals.
- What `DM_Walls_Load` replies, what `slots` and `stackMax` limit, and why wall 3's HP shrinks.
- Whether a camp egg must be near you to hatch (ZapHub's position was not recorded).
- Whether World 1/3/4 servers host the mountain too.
