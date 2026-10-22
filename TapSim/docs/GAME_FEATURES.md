# Tap Simulator REBORN: every system, for scripting (2026-10-22)

Source: the module comments and calls in Slopix Hub's MIT-licensed source (`games/72858262610964.lua`, built 2026-10-18), plus the player guides listed in `RESEARCH.md`. Nothing here was observed live by us. Names can change with any game update. Check them with the helper's **Print remote list** button.

## How to talk to the game
- **Remotes:** `ReplicatedStorage.RemoteServices.<Service>.RE.<Name>` (RemoteEvent: `FireServer`, results come back on another RE's `OnClientEvent`) or `.RF.<Name>` (RemoteFunction: `InvokeServer` returns the answer). In the tables below, **(RE)** means fire and **(RF)** means invoke.
- **Save data (read only):** `require(ReplicatedStorage.Controllers.Core.DataController):GetReplica().Data`. The server owns it, so you change it only by firing remotes.
- **Configs:** `require(ReplicatedStorage.Shared.<Group>.<Module>)`.
- **Identity:** require game modules at thread identity 2 and do GUI work at 8 (see `asGame` in `TapSim_Reborn.luau`).
- **Range:** most actions check that you stand near the thing, so a script has to teleport first. The "Range" column gives the distance.
- **Streaming:** the world is streamed in. Far-away models (eggs, machines, stars) may not exist until you go near. Keep their coordinates, and use `player:RequestStreamAroundAsync(pos)`.

The **In helper** column says whether `TapSim_Reborn.luau` v1.1 already does it.

## Core loop
| System | Remote / call | Range | Data / config | In helper |
| :--- | :--- | :--- | :--- | :--- |
| Tap | `TapService.TapRequested {Auto=false, ClientSequence, Source="button"}` (RE), answered on `TapService.TapResult` | none | `Shared.Core.GameConfig.ManualTapInterval` = 0.1s. ClientSequence must rise. | ✅ |
| Game's auto clicker | `AutoClickService.AutoClickRequested {Enabled}` (RE) | none | needs the Auto Clicker unlock | ✅ |
| Rebirth | `RebirthService.RebirthRequested {Index}` (RE); add `Auto=true` with the Auto Rebirth skill | none | Button n = 5^(n-1) rebirths. `Shared.Progression.RebirthConfig` (`GetAmountFromIndex`, `GetPrice(amount, rebirths)`), `RebirthButtonConfig` (14 buttons on Main). Unlocked = 1 + `Data.Upgrades.RebirthButtons`. Game's own auto rebirth runs every 1.5s at most. | ✅ |
| Hatch | `EggService.EggHatchRequested {Egg, Count, Auto=true, Seq}` (RE), answered on `EggService.EggHatchResult {Seq, Success, Rolls, Pets, Spent, Error}` | stand ≤ ~10 studs from the egg | Count 8 (x8 pass or OctoHatch boost), 3 or 1. Errors: `TooFar`, `RateLimited`, `Cancelled`, `StorageFull`, `NotEnoughCoins`, `IslandLocked`. `Shared.Pets.LaunchEggConfig`, `EggPricing`. `Data.Eggs.Unlocked`, `Data.Eggs.SecretDroughtSeconds` (secret pity up to x4 luck over 24h). | ✅ |
| Auto delete (per egg) | `EggService.AutoDeleteRequested {Egg, Entries={petNames}}` (RE) | none | the egg's pet list with chances | ❌ |
| Stop offline hatch | `EggService.StopOfflineHatch` (RE) | none | | ❌ |
| Equip best | `PetService.PetActionRequested {Action="EquipBest"}` (RE) | none | `Data.Pets.Owned/Equipped/StorageLimit` | ✅ |
| Upgrades | `UpgradeService.Purchase {Name}` (RF), returns `{Success, Reason, Current}` | some are zone-locked | Order: FreeAutoClicker, ClickMultiplier, HatchSpeed, CriticalChance, AutoClickerSpeed, Teleport (`Shared.Progression.UpgradeConfig`) | ✅ |
| Skill tree (gems) | `SkillTreeService.Unlock {Name}` (RF), returns `{Success, Reason, Price, Missing}` | none | `Shared.Progression.SkillTreeConfig`. Locked children answer `SubtreeLocked`. `Data.SkillTree.Unlocked`. | ✅ |
| Settings | `SettingsService.UpdateSetting {Name, Value}` (RF) | none | `Shared.Core.SettingsConfig` (hatch animation, pets, pop-ups, screen shake) | ❌ |

**Eggs** (stand position): Basic (6,-511,-1833), Spotted (-5,-511,-1822), Spiked (-23,-513,-1707), Sky (-88,-48,-1904), Nimbus (-97,-48,-1891), Pumpkin (-143,881,-1833), Forest (-297,1228,267), Mushroom (-6,2032,-1925), Mycelium (-21,2032,-1932), Snowman (-258,2547,345), Cactus (-203,3632,-1863), Crystal (-53,5438,-1992), Geode (-68,5438,-1987), Void (-204,7676,-1885), Volcanic (-2,11073,-1913), Draconic (9,11072,-1905). Early odds: Basic gives Doggy 55%, Kitty 35%, Bunny 10%. Spotted gives Chick 45%, Lamb 30%, Deer 20%, Bear 5%.

## Pets
| System | Remote / call | Range | Notes | In helper |
| :--- | :--- | :--- | :--- | :--- |
| Craft Golden / Diamond | `MachineService.MachineCraftRequested {Action="Craft", Machine="Golden"\|"Diamond", PetIds}` or `{Action="CraftAll", Machine, Names}` (RE), answered on `MachineService.MachineCraftResult` | near the machine's `InteractionPoint` ("You must be near the Golden Machine") | Same-name pets of the tier below. The chance rises with count (Diamond: 20/40/60/80/100% for 1–5 pets). **A failed roll destroys every pet put in.** Craft All does up to 60 batches at 100% and skips equipped, locked, enchanted and Secret pets (`Shared.Pets.MachineConfig`, `CraftAllPlan`). | ❌ |
| Rainbow ("Shiny" machine) | `MachineCraftRequested {Machine="Shiny", Action="Start", PetIds}` / `{Action="Claim", CraftId}` | at the machine | A timed queue of up to 3 crafts, 2–5 Diamond pets each. The more pets, the faster: 2 pets take 8h, 5 pets take 30s. | ❌ |
| Enchant | `EnchantService.SetFilters(keepList)`, `AutoStart {PetId, Slot, Replace?}`, `Claim()` (RF). Stop arrives on `EnchantService.AutoEvent {Kind="Stop", Reason}`. | start only inside the Enchant machine point; it keeps rolling after you leave | Each roll costs gems (`EnchantConfig.GetRollPrice`). Tier III+ traits are protected: to roll over one, send its name in `Replace`. Good traits: Renewal (+7.5% rebirths per level, max 3), Glass Cannon (best pet), Power III, Lucky III. | ❌ |
| Feed treats | `ItemService.UseOnPet {Item, PetId, Amount}` (RF), returns `{Success, Level, LevelsGained}` | none | Pet level multiplies power. Level caps by rarity (`Shared.Pets.PetLevelConfig`). Unlocks after the bridge. | ❌ |
| Shrine blessing | `ShrineService.Choose(key)` (RF): Luck, Golden Chance or Auto Clicker | ≤ 45 studs from the shrine (Autumn island) | Grows x1.1, then x1.25 after 10 min, then x1.5 after 25 min. **Choosing again restarts it.** Player attributes `ShrineBlessing`, `ShrineTier`. | ❌ |
| Pet Index rewards | `PetIndexService.RewardClaimRequested(egg)` (RE), answered on `RewardClaimResult` | none | Gems per egg for finding every pet, again per Golden/Diamond/Rainbow tier, plus "Secrets". `Shared.Pets.PetIndexRewardConfig`. | ❌ |
| Mastery rings | `MasteryService.EquipRelic {Name}` (RF) | none | Ring earned at mastery level 100 (`Shared.Progression.RelicConfig`) | ❌ |

## Free rewards
| System | Remote / call | Range | Notes | In helper |
| :--- | :--- | :--- | :--- | :--- |
| Quests | `QuestService.ClaimQuest {Quest=id}` (RF) | none | `Data.Quests[id].Completed/Claimed` | ✅ |
| Tap chests | `TapChestService.Claim(id)` (RF) | none | `Data.TapChests` | ✅ |
| Offline earnings | `OfflineRewardsService.Claim(instant)`, `AcknowledgeHatches()` (RF) | none | | ✅ (Claim) |
| Event spin wheel | `EventWheelService.Spin {WheelType}` (RF) | none | `Data.Spinwheels` | ❌ |
| Leaderboard rewards | `LeaderboardService.GetPendingRewards()`, then `ClaimReward(LeaderboardId)` (RF) | none | | ❌ |
| Gifts | `GiftService.OpenGift {Gift, Amount}` (RF) | none | `Shared.Items.GiftConfig` | ❌ |
| Shiny Stars (15 hidden) | `ShinyStarService.Collect(id)` (RF) | ≤ 22 studs | All 15 double the Shiny chance on every hatch (2% → 4%). `Data.ShinyStars.Found`, `Shared.Game.ShinyStarConfig`. | ❌ |

## Boosts and items
| System | Remote / call | Range | Notes | In helper |
| :--- | :--- | :--- | :--- | :--- |
| Potion machine (Spawn) | `PotionMachineService.Brew(name, slot)`, `ClaimAll()`, `Craft(output)` (RF), returns `{Success, Error}` | at the machine (`TooFar`) | 3 slots, 5 min each. Coins, Luck or Gems Potion I. Costs gems (1 + 5% of rebirths). 3× Potion I → Potion II. | ❌ |
| Drink a boost | `BoostService.Use(name)` (RF) | anywhere | Same-type boosts stack. Timer in `Data.ActiveBoosts[name]`. | ❌ |
| Totems | `ItemService.PlaceTotem {TotemName, Position}`, `GetActiveTotems()` (RF) | where you stand | Boost everyone within 12–28 studs for 5–17 min (`Shared.Items.TotemConfig`) | ❌ |
| Weather dials | `WeatherDialService.CanUse(kind)`, then `Use(kind)`; kind is `"Rain"` or `"Acid"` (RF) | anywhere | | ❌ |
| Honey Pot (Sky Island height) | `HoneyPotService.Craft(key, amount)`, `Claim(slot)`, `Stop(slot)` (RF) | ≤ 25 studs | 3 timed slots. Turns creature drops (Cloud Puff, Pumpkin Seeds, Glow Spore, Cactus Fruit, Crystal Shard) into treats and boosts. `Shared.Items.HoneyPotConfig`. | ❌ |

## World events and things to break
| System | Remote / call | Range | Notes | In helper |
| :--- | :--- | :--- | :--- | :--- |
| Island creatures | Broken by your **taps** while you stand near it. No separate remote. | tap range 14 studs (12 up/down) | One per island, yours alone: Fluffy Cloud, Giant Pumpkin, Glow Mushroom, Prickly Cactus, Crystal Cluster, Void Crystal. 20–35 hits, then 150–400 taps' worth of coins plus Honey Pot ingredients. It hops away when hit. Spots: `workspace.IslandBreakableSpots`. Ready time: `Data.IslandBreakables[spot]`. | ❌ |
| Meteor Shower, Mystery Egg | Taps, as above. Mystery Egg: `EggDropService.Incoming` / `Cracked` / `FlewOff` (RE events). `EggDropService.Travel()` (RF) takes you there. | 14 studs | `Shared.Admin.WorldEventConfig`, `EggDropConfig` | ❌ |
| Cloud Rain | Pickups you collect by touching them | touch | | ❌ |
| Lucky Ducky | `LuckyDuckyService.Spawn {Id, Lifetime}` (RE event), then `LuckyDuckyService.Claim(Id)` (RF), no sooner than 0.3s after the spawn | none | After 1h of playtime, every 20–30 min. Rolls x2 coins (60%), a coin pile (27%), x3 coins (10%) or golden hatches (3%). | ❌ |
| Balloon Party | `BalloonPartyService.Launched {Uid, ...}` (RE event), then `BalloonPartyService.Hit(Uid)` | ≤ 150 studs | Every 45 min, lasts 2 min. Spawns around you. Path from `Shared.Admin.BalloonFlight`. | ❌ |
| Pigs could fly | `PigsCouldFlyService.Launched` (RE event), then `PigsCouldFlyService.Hit(Uid)` | ≤ 120 studs | One hit catches a pig | ❌ |
| Lucky Block (admin event) | `LuckyBlockEventService` (`CreateFalling`, `CollectRequested`, `PlayCutscene`) | ? | Pickup method unknown: Slopix only records it | ❌ |

## Minigames
| System | Remote / call | Range | Notes | In helper |
| :--- | :--- | :--- | :--- | :--- |
| Pet Defense (Mushroom island) | `ColosseumService.StartWaveDefense`, `AttackOpponent(id)` / `CriticalAttackOpponent(id)`, `EndWaveDefense`, `ClaimMinigameReward("replace"\|"keep")`, `ReturnFromArena` (RF) | start at the arena entrance | 3 lanes, 3 lives. A crit does 10x and pushes back. Each wave raises the ring (relic) reward, plus treats, dials and totems from wave 11. One run per 30 min (`Data.Colosseum.Cooldown`). | ❌ |
| Mining (under Crystal Cave) | `MiningService.Hit(id, x, y, z)`; `Purchase("BuyTool"\|"BuyStorage", name)`; `DailyBuy(id)`; Enter/Sell/Exit by standing on pads | inside the mine | A 20×20×25 mine per player, fresh daily. Ores → mining coins → pickaxes, bags and daily packs of Coins/Gems. Milestones at 25/50/75/100% cleared. | ❌ |
| Dig site (Autumn island) | `DigService.Begin()` → round `{Epoch, Phase, Speed, Center, Width, Sequence}`, then `Hit(id, Sequence, serverTime)`, `Cancel(id)` (RF) | on the dig site | 10 digs per hour. It's a timing bar: a hit takes off a layer, a miss puts 2 back (`Shared.Minigames.DigConfig`). Rewards: treats. | ❌ |
| Memory Match | `MemoryMatchService.Open(true)`, `Flip(boardId, card)` (RF) | ≤ 24 studs of `workspace.MemoryMatch.TouchToPlay` | 12 cards (6 pairs), once per 30 min | ❌ |
| Boingo's quest | `NpcQuestService.Talk {Line="BouncyBall"}`, `Collect {Line, Core}` (RF) | ≤ 14 studs of each of the 5 Bounce Cores | Reward: 5 Slime | ❌ |
| Bouncy Obby | `BouncyObbyService.CraftKey` (20 Slime), `Enter`, `Reach {Index}` per checkpoint, `Finish` (RF) | on the course | Finishing under 45s is refused (`TooFast`), as is skipping checkpoints. The first finish unlocks the Bouncy Ball license. | ❌ |

## Halloween event (October 2026)
| System | Remote / call | Range | Notes | In helper |
| :--- | :--- | :--- | :--- | :--- |
| Hallow Boss | Damage comes from your **taps** while you stand on the boss platform. State: `HallowBossService.RP.State` (Comm property: Phase, StartsAt, EndsAt, Health). Bomb volleys: `Attack {Targets, Radius=9, Delay}`. | on `workspace.HalloweenIsland.BossPlatform` | Every hour: 2 min warning, then up to 7 min of fight. Deal 25+ damage for CandyCorn (250 + 0.5 per damage; top three get 600/450/350), a potion roll and a 1/5000 Hallow Lord pet. | ❌ |
| Trick or treat | `TrickOrTreatService.Knock(houseId)` (RF) | inside the house pad's Zone | 11 houses, 20–40 CandyCorn each, 80% potion chance, ready again after 30 min (`Data.TrickOrTreat`). All 11 give +150 and a Bag of Treats. | ❌ |
| Candy Witch | `HalloweenDailyService.Accept()` (RF) | | 3 daily jobs, 100–150 CandyCorn each, +300 for all three | ❌ |
| Candy shop | `HalloweenShopService.Purchase {Id}` (RF) | anywhere | Limits per event, or per day for Daily items (`Shared.Items.HalloweenShopConfig`) | ❌ |

## Done by hand / no known remote
- **Breaking the spawn bridge** at 700 power: you click the bridge itself.
- **Buying island gates** (Sky Island is 10M coins). Ouroboros Hub offers "Auto Unlock All Islands", but its code is obfuscated, so the remote is unknown.
- **Codes:** none are active yet; the Codes button sits in Settings.
- **Starter pet and nickname** (tutorial).

To find a remote yourself: run the helper's **Print remote list**, then watch which remote the game fires when you do the action by hand. The repo's `VY/tools/PS99_Probe.luau` has a read-only recorder you could adapt for this game.

## Islands (in order of height)
Spawn → Sky (Sky, Nimbus) → Autumn/Pumpkin (Shrine, dig site) → Forest → Mushroom (Pet Defense) → Snow → Desert (Cactus) → Crystal Cave (Crystal, Geode, mine) → Void → Volcanic (Draconic). The Halloween island is the event island. Unlocked islands are in `Data.Progression.UnlockedIslands`.
