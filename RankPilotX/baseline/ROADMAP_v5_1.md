# RankPilot X feature roadmap

## Next stage: general gameplay (research required)
- Auto ultimate activation only after verifying current `UltimateCmds` API.
- Toy and gift consumption, lootbox opening, and keys/chests after verifying inventory and network methods.
- Fast but bounded area upgrades and reward machines; additional tests on real player save data.
- Balloon pop confirmation using updated server state rather than hit requests only.

## Minigames and events
- Fishing / advanced fishing, digsite / advanced digsite, obbies and races.
- New live events as individual adapters. Do not enable retired-event remotes.

## Trading
- Booth seller with exact item UID/price checks and protected-pet exclusion.
- Mailbox claim and manually configured transfers with explicit destination, item limits and opt-in confirmation.

## Performance and reliability
- Live measurement of quest credit/minute, CPU/FPS, world hops and request counts.
- Frame-effect optimization with restoration rather than removing server-linked instances.
- Verify the open source VY/ZAP-like behavior inside the current Roblox client; don't infer success from offline mocks.
