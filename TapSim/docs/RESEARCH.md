# Tap Simulator REBORN: research notes (2026-10-22)

## The game
- **Tap Simulator REBORN** by Cursor Makers. Roblox place `72858262610964` (ScriptBlox lists the same id). Released October 2026; there are no official wiki or Trello pages yet, and the Codes menu is not active.
- **Loop:** tap for Coins, buy eggs with Coins, and equip pets. Each pet has a power multiplier (Doggy x2, Chick x6). Rebirth spends Coins and gives Gems plus a permanent tap boost. Pets, islands, gem upgrades and passes are kept.
- **Early route:** tap 5 times to hatch a starter (Dog, Cat or Bunny). Get 100 coins for a Basic Egg (100, then 200). Rebirth around 1,000 coins. Buy Auto Clicker in Gem Upgrades (20 gems). Hatch Spotted Eggs (shown at 2.5K to 10K) until you reach 700 power. Then click the spawn bridge to break it. Next come the Spiked Egg and Index, then Sky Island (10M gate).
- **Egg odds:** Basic: Doggy 55%, Kitty 35%, Bunny 10%. Spotted: Chick 45%, Lamb 30%, Deer 20%, Bear 5%.
- **Rebirth buttons:** +1 at the start. +5 and +25 unlock after the first rebirth, then +125 and +625, and so on. Each button is 5^(n-1) rebirths, priced at your current rebirth count.
- **Gem Upgrades (first buys):** Auto Clicker 20, Click Anywhere 10, Egg Luck I 10, Auto Rebirth 10. Gem Upgrades also has a skill tree (Click Power, Critical Clicks, ...).
- **Later systems:**
  - Shrines on the third island: Auto Clicker, Luck or Rebirth blessing.
  - Pet Defense (waves, 3 lives) and Masteries, which give Rings.
  - Enchants. Renewal gives +7.5% rebirths per level (max 3); Glass Cannon goes on your best pet; Power III; Lucky III.
  - Golden, Diamond and Rainbow crafting.
  - Mining and digging, Lucky Ducky, the Halloween event.
  - Each egg variant collected adds 5 storage slots; each secret adds 10.
- **Egg list (from the game's `LaunchEggConfig`, via Slopix):** Basic, Spotted, Spiked, Sky, Nimbus, Pumpkin, Forest, Mushroom, Mycelium, Snowman, Cactus, Crystal, Geode, Void, Volcanic, Draconic.

## How the client is built (from Slopix Hub's readable source)
- Player data is a MadStudio Replica at `ReplicatedStorage.Controllers.Core.DataController` (`:GetReplica().Data`). It has `Currencies`, `Statistics.Rebirths`, `Upgrades`, `Progression.UnlockedIslands`, `Eggs.Unlocked`, `Pets.Owned/Equipped/StorageLimit`, `SkillTree.Unlocked`, `Quests` and `TapChests`. The server owns it, so scripts only fire request remotes.
- Remotes use sleitnick Comm: `ReplicatedStorage.RemoteServices.<Service>.RE|RF.<Name>`.
- Config modules live under `ReplicatedStorage.Shared`:
  - `Core.GameConfig` (`ManualTapInterval`)
  - `Progression.RebirthConfig`, `RebirthButtonConfig`, `UpgradeConfig`, `SkillTreeConfig`, `SkillTreeFormula`
  - `Pets.LaunchEggConfig`, `EggPricing`
  - `Monetization.GamepassPerks`, `Items.BoostFormula`
- Server rules the hub documents:
  - At most one tap per 0.1s.
  - `ClientSequence` must rise.
  - Hatch only within ~10 studs of the egg. The answer comes on `EggHatchResult` with the same `Seq`. Errors: `TooFar`, `RateLimited`, `StorageFull`, `NotEnoughCoins`, `IslandLocked`.
  - Upgrade purchases can be refused with `RateLimited` or `ZoneLocked`.
- **Other services seen:**
  - Breakables and drops: `LuckyDuckyService`, `BalloonPartyService`, `PigsCouldFlyService`, `EggDropService`, `ShinyStarService`
  - Minigames: `ColosseumService` (Pet Defense), `MiningService`, `DigService`, `MemoryMatchService`, `BouncyObbyService`
  - Crafting and items: `MachineService` (crafting), `EnchantService`, `PotionMachineService`, `HoneyPotService`, `ItemService`, `BoostService`, `GiftService`, `WeatherDialService`
  - Progression: `ShrineService`, `MasteryService`, `NpcQuestService`, `PetIndexService`, `LeaderboardService`
  - Halloween: `TrickOrTreatService`, `HalloweenShopService`, `HalloweenDailyService`, `EventWheelService`
  - Other: `SettingsService`

## Open-source survey: what is actually readable
| Script | Where | Source | Verdict |
| :--- | :--- | :--- | :--- |
| **Slopix Hub** | github.com/TrustyCoding/slopix-hub, `games/72858262610964.lua` | **Readable, commented, MIT license** (bundled from `src/games/tapsim/*`) | The only real open source found. It covers tap, rebirth, hatch, craft, enchant, defense, mining and events. Network use checked: it loads its UI library from its own repo, has a Discord invite, and has an optional webhook the user configures. Nothing else is sent. |
| Ouroboros Hub | github.com/joustingmatch/Ouroboros (rscripts "[KEYLESS]", 7.5K runs) | Public repo, but every game file is obfuscated (luast; strings encrypted) | Not open source in practice. The rscripts copy also loads an analytics script. |
| Paddle Hub | gitlab.com/paddles/paddle `scripts/TapSimulatorREBORN.lua` | Obfuscated (MoonVeil 2.1.0) | Not readable. |
| Snowy, Axon, Fishy, Espa, "AUTO EVENT FARM", "[KEYLESS] TAP SIMULATOR" | ScriptBlox / rscripts | `loadstring(HttpGet(...))` to key systems or Luarmor loaders | Closed. They run whatever the server sends. |
| `Error9soul/tap-simulator-reborn-script` | GitHub | **No code.** HTML only. Asks you to download an unsigned `.exe` and whitelist it in antivirus. Has bot commits with random messages and describes a "web build" that does not exist for Roblox. | **Likely malware lure. Do not download.** |

## Sources
- allthings.how: "Tap Simulator REBORN: How to Play on Roblox (Full Guide)" (game link, route, egg odds, rebirth buttons, gem upgrades)
- roonby.com: "11 Tap Simulator: Reborn Guide Tips and Tricks" (Shrines, Pet Defense, Masteries, enchants, storage)
- Destructoid, Dexerto, Pro Game Guides, SuperCheats code pages (no active codes as of Oct 15–16, 2026)
- ScriptBlox API search and rscripts.net listings for the place id
- github.com/TrustyCoding/slopix-hub (MIT), github.com/joustingmatch/Ouroboros, gitlab.com/paddles/paddle
