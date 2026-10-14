# Crystal Key rank-up method on VY AutoRank — does it work?

Date: 2026-10-14. Source analysed: VY AutoRank v1.1.7 (SHA-256 `CDE5F944…51FC`); fixes in v1.1.8 (see `VY_AUTORANK_v1.1.8_NOTES.md`).

## Short answer
- **The method is real, and VY already implements it.** v1.1.7 has a Crystal mode, OFF by default, behind the hub button "Crystal mode: OFF (uses keys)". It holds "break diamond breakables" (type 9) and "break breakables in best area" (type 21) in slots 2–4. It travels to World 1, pauses pets, stands on the Castle chest pad and opens the chest with `CrystalKey_Unlock()`. That call (no arguments) was confirmed once live: keys 15076→15075 and slot-1 potions 8/32→9/32.
- **Offline, the integrated loop works end to end** in a mocked runtime (real Luau VM, fake PS99 world, `VY/tests`). It has **not** been run end to end in the live game. Status: **Implemented, Unverified** live; **Verified Working (mocked Lune runtime)** for the script's own logic.
- **A code review found six Crystal problems in v1.1.7, all reproduced and fixed in v1.1.8:**
  - a false stop when a key drops nothing near a quest's end;
  - a World 1 → best world → World 1 round trip on every rank-up;
  - keys wasted after a rank's stars are complete;
  - no deadline when World 1 can't be reached;
  - stopping early when Keys Mastery keeps keys;
  - farming finishing the held diamond quest while waiting for the setup.
- **"500 stars in 2 minutes" is not supported by the game's published numbers.** One slot-1 completion pays 1 star (2 with Double Stars). A key gives about 1 (observed once) to about 2–3 (drop-table estimate) collect progress. High ranks need 90 items per completion. See the table below.

## Why the slot trick works (evidence)
- The game never gives two active rank quests the same type; this comes from player reports, not code. The client UI places each goal in a slot by `goal.Stars` (1–4).
- From the official Ranks data (BIG Games API, newest config 2026-08-29), the slot-1 pool is exactly {9, 14, 15, 21} at ranks 4 and 7–40. With 9 and 21 held elsewhere, slot 1 can only roll collect potions (14) or collect enchants (15).
- Ranks 5–6 also have USE_POTION (34) in slot 1, so VY's check refuses them (by design: holding a third quest is not implemented). Ranks 1–3 do not have the pattern.
- At ranks 10+, type 9 can only roll in slots 3–4, while 21 can be in 2, 3 or 4. Slot 2 can roll collect quests itself; chest drops then advance both.

## What it costs (estimates from official amounts)
A Monte Carlo of VY's own burst/credit logic with the wiki odds (6 items per key; 36% potions, 51% enchants) gives these keys per slot-1 star: R4 2.8, R7 6.3, R10 11.5, R12–14 13.0, R22–24 20.1, R29–31 28.0, R33–40 35.9. The table below brackets the same numbers.

"Keys per star" = slot-1 collect amount ÷ collect progress per key. The table shows two cases: 1 per key (the single live observation) and 2.2–3.0 per key (Fandom drop table: 6 items per open, ~36% potions, ~51% enchants). Double Stars halves every key figure.

| Rank | Slot-1 amount | Stars to finish rank | Keys/star at 1 per key | Keys/star at 2.2–3.0 per key | Keys for a whole rank via slot 1 (2.2–3.0 per key) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 6 | 46 | 6 | 2–3 | 92–138 |
| 7 | 15 | 121 | 15 | 5–7 | 605–847 |
| 10 | 28 | 319 | 28 | 10–13 | 3,190–4,147 |
| 15 | 35 | 513 | 35 | 12–16 | 6,156–8,208 |
| 20 | 40 | 698 | 40 | 14–19 | 9,772–13,262 |
| 25 | 60 | 780 | 60 | 20–28 | 15,600–21,840 |
| 30 | 70 | 870 | 70 | 24–32 | 20,880–27,840 |
| 33–40 | 90 | 964–990 | 90 | 30–41 | ~29,000–40,600 |

- A Crystal Key costs about 10–11k diamonds (community-reported price, not verified). Keys Mastery gives a 5%/10% chance to keep the key. Rank rewards hand out roughly 191–260 full keys along the 1→40 path.
- Best value is at ranks 4 and 7–10, where a few keys earn a star. At ranks 33–40 a rank costs tens of thousands of keys.
- Speed: VY sends at most 10 opens per burst (~0.35 s apart in the mock), then waits for replicated credit. That is roughly 100–150 opens/minute if the server allows it, so about 3–5 stars/minute at ranks 33–40 and much more at ranks 4–10.

## How VY's mode behaves (v1.1.8, checked offline)
1. **OFF by default.** When turned ON, it engages only if the live rank pool matches and slot 1 is a collect quest. 9 and 21 must be unfinished in slots 2–4, with more keys than the reserve (100). Otherwise the status line explains what is missing and ordinary farming continues.
2. Pins the two held quests by UID, pauses pets (`Pets_UnequipAll`) and travels to World 1 if needed. The setting survives the teleport through the per-account JSON. It then moves onto `Map["3 | Castle"].INTERACT.CrystalChest.Pad`.
3. Opens one key per request (no arguments), 10 per burst at most, ≥0.15 s apart, then waits up to 10 s for replicated credit (slot-1 progress, a new slot-1 quest, or stars).
4. Stops (and restores pets) when any of these happens:
   - the reserve is reached (exactly, after re-reading the live key count);
   - the 5000-request budget is reached;
   - an open is refused;
   - 10 keys in a row give no credit;
   - slot 1 doesn't rotate;
   - the setup becomes invalid;
   - World 1 can't be reached in 5 minutes;
   - the toggle is turned OFF.

   A safety stop shows "Crystal mode: PAUSED (toggle to reset)", and the line under the button shows the reason.
5. **Rank-up:** once the rank's stars are complete it stops opening and keeps the hold for up to 2 minutes. If the rank-up arrives and both held quests are still there, it continues on the new rank without leaving World 1.
6. **Setup assembly:** while Crystal is ON with spare keys, a held diamond quest is protected. Diamond targets and Diamonds Flags are skipped until a best-area quest arrives.
7. Afterwards ordinary farming resumes and, if needed, it travels back to the best area's world.

Offline evidence (`python3 VY/tests/run_tests.py`):
- `crystal-flow`: no farming or hatching while held, held quests survive, reserve kept, slot 1 rotates.
- `crystal-travel`: World 2 → 1 → 2 with one teleport each way.
- `crystal-slow-replication`: exactly 10 opens, then it waits for credit.
- `crystal-no-credit`: stops after one burst.
- `crystal-refused`: no retry.
- `crystal-not-ready`: no keys spent.
- `crystal-stars-keys`: string-keyed Save goals.
- Added for v1.1.8: `crystal-zero-drop-tail`, `crystal-rankup`, `crystal-stars-complete`, `crystal-travel-refused`, `crystal-retain-strand`, `crystal-protect-setup`.

## Known limits
- **Setup assembly still relies on rerolls.** v1.1.8 protects a held diamond quest. A lone held best-area quest cannot be protected, because any best-area farming advances it. Expect anywhere from minutes to hours; setting it up by hand, then turning the mode on, is still fastest.
- **Whether held quests survive a rank-up is unknown live.** If the server rerolls every slot, the setup has to be assembled again on each rank.
- **Credit attribution is broad.** Any star gain or slot-1 change counts as credit. With pets paused and farming held, nothing else should earn stars.
- **Not live-tested:** whether the server allows this pace, whether the pad distance is enforced, and bulk opens. The game UI can open up to 100 keys at once, but the request for that is unknown and is not guessed.

## Recommended live test (user-run, small)
1. Install exactly one VY build (see `P0-01_DEPLOYMENT_AND_FISHING.md`). Set `CrystalKeyReserve` so only ~20 keys are spendable.
2. Get the setup by hand: slot 1 = collect potions/enchants; 9 and 21 unfinished in slots 2–4.
3. Turn Crystal mode ON. Record key count, slot-1 progress and stars before and after. Note the status line, and whether pets come back and farming resumes when it stops.

## Next steps
- Live test of v1.1.8 as above: one small burst first, then a rank-up observation (do the held quests survive?).
- The default 5000-request budget ends a session after about one R12 rank or about 14% of an R33+ rank. Raising `CrystalKeyLimit` is your decision.
