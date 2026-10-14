"""Build VY_AutoRank v1.1.8 from the frozen v1.1.7 by exact single-match edits.

Usage: python3 -I patch_v118.py <v1.1.7 CRLF source> <v1.1.8 CRLF output>
Each edit must match exactly once; any mismatch aborts without writing.
"""
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
raw = open(src_path, "rb").read().decode("utf-8")
assert "\r\n" in raw
s = raw.replace("\r\n", "\n")
EDITS = []


def edit(name, old, new):
    EDITS.append((name, old, new))


# --- identity -----------------------------------------------------------------------
edit("version", 'local VERSION = "1.1.7"', 'local VERSION = "1.1.8"')
edit("F7 replaced-copy log",
"""if type(genv.VyAutoRank) == "table" and type(genv.VyAutoRank.Stop) == "function" then
    pcall(genv.VyAutoRank.Stop)""",
"""if type(genv.VyAutoRank) == "table" and type(genv.VyAutoRank.Stop) == "function" then
    -- v1.1.8: name the copy being replaced; two copies per place load point to a duplicate autoexec file.
    log("replacing running AutoRank v%s", tostring(genv.VyAutoRank.Version))
    pcall(genv.VyAutoRank.Stop)""")

# --- F1: Stop before restore must not overwrite the account file ----------------------
edit("F1 Stop persist guard",
"""    if persistHook then pcall(persistHook) end
    if genv.VyAutoRank == handle then""",
"""    -- v1.1.8: never persist before this run restored the account file; a copy stopped while
    -- still loading would otherwise overwrite saved controls and an in-flight transaction.
    if persistHook and state.persistReady then pcall(persistHook) end
    if genv.VyAutoRank == handle then""")
edit("F1 persistReady after restore",
"""    restoreStateFile()
    installPatches()""",
"""    restoreStateFile()
    state.persistReady = true
    installPatches()""")
edit("F7 restore log",
"""        log("Restored counters from %s", STATE_FILE)""",
"""        log("Restored saved counters and controls")""")
edit("F7 bootstrap stopped while loading",
"""    repeat task.wait(0.25) until game:IsLoaded() or not state.alive or os.clock() - loadedAt > 90
    if not game:IsLoaded() then""",
"""    repeat task.wait(0.25) until game:IsLoaded() or not state.alive or os.clock() - loadedAt > 90
    if not state.alive then return false end
    if not game:IsLoaded() then""")

# --- Crystal: slot by Stars, partial setup, stars complete ----------------------------
edit("C inspect slot by Stars",
"""            local slot, t = tonumber(tier), tonumber(goal.Type)
            local rem = math.max(0, (tonumber(goal.Amount) or 0) - (tonumber(goal.Progress) or 0))
            if slot == 1 then first = goal""",
"""            -- v1.1.8: the game's quest panel places a goal by goal.Stars (1-4); fall back to the key.
            local stars, t = tonumber(goal.Stars), tonumber(goal.Type)
            local slot = (stars and stars >= 1 and stars <= 4 and stars % 1 == 0) and stars or tonumber(tier)
            local rem = math.max(0, (tonumber(goal.Amount) or 0) - (tonumber(goal.Progress) or 0))
            if slot == 1 then first = goal""")
edit("C inspect partial + starsComplete",
"""    if not (diamond and area) then return nil, "rerolling higher slots for both breakable quests" end
    if not first then return nil, "waiting for rank data" end
    if tonumber(first.Type) ~= 14 and tonumber(first.Type) ~= 15 then
        return nil, "clearing slot 1 for a collection quest"
    end
    return { rank = tonumber(save.Rank), diamond = diamond, area = area, first = first, keys = Crystal.keyCount(save) }
end""",
"""    if not (diamond and area) then
        local partial = { diamond = diamond, area = area, first = first }
        if diamond then return nil, "keeping the diamond quest; rerolling for a best-area quest", partial end
        if area then return nil, "rerolling for a diamond quest (best-area quest is farmed meanwhile)", partial end
        return nil, "rerolling higher slots for both breakable quests", partial
    end
    if not first then return nil, "waiting for rank data" end
    if tonumber(first.Type) ~= 14 and tonumber(first.Type) ~= 15 then
        return nil, "clearing slot 1 for a collection quest"
    end
    -- v1.1.8: once the rank's stars are complete, more keys earn nothing until the rank-up.
    local total = tonumber(info.totalStars) or 0
    return { rank = tonumber(save.Rank), diamond = diamond, area = area, first = first, keys = Crystal.keyCount(save),
        starsComplete = total > 0 and (tonumber(save.RankStars) or 0) >= total }
end""")
edit("C eligible respects expired rank wait",
"""    local setup = Crystal.inspect(getSave(), state.rank)
    if not setup or setup.keys <= math.max(0, tonumber(CONFIG.CrystalKeyReserve) or 100) then return nil end
    return setup
end""",
"""    local setup = Crystal.inspect(getSave(), state.rank)
    if not setup or setup.keys <= math.max(0, tonumber(CONFIG.CrystalKeyReserve) or 100) then return nil end
    if setup.starsComplete and c.rankWaitExpired == setup.rank then return nil end
    return setup
end
-- v1.1.8: while Crystal mode waits for its setup, an unfinished diamond quest in slots 2-4
-- is the scarce piece (type 9 only rolls in slots 3-4 from rank 10). Keep it unfinished:
-- skip diamond targets and Diamonds Flags until a best-area quest joins it. A lone
-- best-area quest cannot be protected this way (any best-area farming advances it).
function Crystal.keepDiamondHolder()
    local c = state.crystal
    if not CONFIG.AutoCrystalRank or c.halted or c.hold then return false end
    local save = getSave()
    local setup, _, partial = Crystal.inspect(save, state.rank)
    if setup or type(partial) ~= "table" or not partial.diamond or partial.area then return false end
    return Crystal.keyCount(save) > math.max(0, tonumber(CONFIG.CrystalKeyReserve) or 100)
end""")
edit("C finish clears v1.1.8 fields",
"""    c.dataAt, c.rotationAt, c.chestWaitAt = nil, nil, nil
    Crystal.release()""",
"""    c.dataAt, c.rotationAt, c.chestWaitAt = nil, nil, nil
    c.travelAt, c.rankWaitAt, c.uncredited = nil, nil, 0
    Crystal.release()""")

# --- Crystal: protect the diamond holder while assembling ------------------------------
edit("C3 farm skips diamonds",
"""    addGroup("diamonds", p2, wantsDiamonds() and 2 or 1)""",
"""    if not Crystal.keepDiamondHolder() then addGroup("diamonds", p2, wantsDiamonds() and 2 or 1) end""")
edit("C3 no diamond flag",
"""    if not (CONFIG.AutoFarm and CONFIG.AutoUseFlags and CONFIG.AutoDiamondFlags and wantsDiamonds()) then return end""",
"""    if not (CONFIG.AutoFarm and CONFIG.AutoUseFlags and CONFIG.AutoDiamondFlags and wantsDiamonds()) then return end
    if Crystal.keepDiamondHolder() then return end""")

# --- Crystal controller: rank wait, re-pin, bounded travel ------------------------------
edit("C controller",
"""    if c.pins and (c.pins.rank ~= setup.rank or c.pins.diamond ~= setup.diamond or c.pins.area ~= setup.area) then
        Crystal.finish("Crystal: quest setup changed; rerolling", false)
        return
    end
    c.hold = true
    c.pins = c.pins or { rank = setup.rank, diamond = setup.diamond, area = setup.area }
    if not Crystal.pause() then return end
    if currentWorld() ~= 1 then
        c.status = "Crystal: travelling to World 1"
    else
        c.status = string.format("Crystal: opening | requests %d/%d | reserve %d", c.used, limit, reserve)
    end""",
"""    if setup.starsComplete and c.rankWaitExpired == setup.rank then
        if c.hold or c.pausedPets then Crystal.finish("rank stars complete; waiting for the rank-up", false) end
        c.status = "Crystal: rank stars complete; waiting for the rank-up"
        return
    end
    if c.pins and (c.pins.rank ~= setup.rank or c.pins.diamond ~= setup.diamond or c.pins.area ~= setup.area) then
        -- v1.1.8: inspect re-validated the live setup (for example a rank-up that kept both held
        -- quests). Keep the hold and the World 1 position: re-pin instead of releasing, which sent
        -- the player to the best area's world and straight back.
        log("Crystal: setup still valid after a change (rank %s -> %s); continuing", tostring(c.pins.rank), tostring(setup.rank))
        c.pins = nil
    end
    c.hold = true
    c.pins = c.pins or { rank = setup.rank, diamond = setup.diamond, area = setup.area }
    if not Crystal.pause() then return end
    if currentWorld() ~= 1 then
        -- v1.1.8: bounded trip; a refused or disabled World 1 teleport must not idle the
        -- account with pets unequipped and every other worker held.
        c.travelAt = c.travelAt or os.clock()
        if os.clock() - c.travelAt > 300 then
            Crystal.finish("could not reach World 1 within 5 minutes", true)
            return
        end
        c.status = CONFIG.AutoWorldTeleport and "Crystal: travelling to World 1"
            or "Crystal: go to World 1 (AutoWorldTeleport is off)"
    else
        c.travelAt = nil
        c.status = setup.starsComplete and "Crystal: rank stars complete; waiting for the rank-up"
            or string.format("Crystal: opening | requests %d/%d | reserve %d", c.used, limit, reserve)
    end""")

# --- Crystal openTick ------------------------------------------------------------------
edit("C openTick pins",
"""    if not setup or not c.pins or setup.rank ~= c.pins.rank or setup.diamond ~= c.pins.diamond or setup.area ~= c.pins.area then
        Crystal.finish("Crystal: quest setup changed; rerolling", false)
        return
    end""",
"""    if not setup then
        Crystal.finish("Crystal: quest setup changed; rerolling", false)
        return
    end
    if not c.pins or setup.rank ~= c.pins.rank or setup.diamond ~= c.pins.diamond or setup.area ~= c.pins.area then
        c.status = "Crystal: re-checking the quest setup" -- the controller re-pins a still-valid setup
        return
    end""")
edit("C openTick stars complete",
"""    if not Crystal.atChest() then return end
    if now < (c.nextAt or 0) then return end
    local batch = c.batch""",
"""    if not Crystal.atChest() then return end
    if now < (c.nextAt or 0) then return end
    if setup.starsComplete then
        -- v1.1.8: keep the hold (and the held quests) for the rank-up instead of spending keys.
        if c.batch then c.reserved = math.max(0, c.reserved - c.batch.left); c.batch = nil end
        c.rankWaitAt = c.rankWaitAt or now
        c.status = "Crystal: rank stars complete; waiting for the rank-up"
        if now - c.rankWaitAt > 120 then
            c.rankWaitExpired, c.rankWaitAt = setup.rank, nil
            Crystal.finish("rank stars complete; the rank-up did not arrive within 2 minutes", false)
        end
        return
    end
    c.rankWaitAt = nil
    local batch = c.batch""")
edit("C1 uncredited budget",
"""        if credited then
            c.batch, c.reserved = nil, 0
            writeStateFile()
        elseif now - batch.lastAt > math.max(1, tonumber(CONFIG.CrystalCreditWait) or 10) then
            Crystal.finish("no collection credit after opening; no retry", true)
        else c.status = "Crystal: waiting for collection credit" end""",
"""        if credited then
            c.batch, c.reserved, c.uncredited = nil, 0, 0
            writeStateFile()
        elseif now - batch.lastAt > math.max(1, tonumber(CONFIG.CrystalCreditWait) or 10) then
            -- v1.1.8: near a quest's end a burst is only 1-2 keys and a key can drop no matching
            -- item. Halt only after a full burst's worth of keys in a row earned nothing.
            c.uncredited = (c.uncredited or 0) + (batch.size or 1)
            if c.uncredited >= math.max(1, tonumber(CONFIG.CrystalBurst) or 10) then
                Crystal.finish("no collection credit after opening; no retry", true)
            else
                c.batch, c.reserved = nil, 0
                writeStateFile()
            end
        else c.status = "Crystal: waiting for collection credit" end""")
edit("C6 settled key resync",
"""        if n < 1 then Crystal.finish("key limit or reserve reached", true); return end
        batch = { left = n, before""",
"""        if n < 1 then
            -- v1.1.8: the estimate drops one per request, but Keys Mastery can keep a key. Once no
            -- request was sent for CrystalCreditWait (replication settled), trust the live count.
            if setup.keys > reserve and limit - c.used >= 1 and c.keyEstimate < setup.keys then
                if now - (c.lastSendAt or -math.huge) >= math.max(1, tonumber(CONFIG.CrystalCreditWait) or 10) then
                    c.keyEstimate = setup.keys
                end
                c.status = "Crystal: re-reading the key count"
                return
            end
            Crystal.finish("key limit or reserve reached", true)
            return
        end
        batch = { left = n, size = n, before""")
edit("C lastSendAt",
"""    batch.lastAt = os.clock()
    c.nextAt = batch.lastAt + math.max(0.05, tonumber(CONFIG.CrystalOpenDelay) or 0.15)""",
"""    batch.lastAt = os.clock()
    c.lastSendAt = batch.lastAt
    c.nextAt = batch.lastAt + math.max(0.05, tonumber(CONFIG.CrystalOpenDelay) or 0.15)""")
edit("C setEnabled resets",
"""        c.batch, c.pins, c.rotationAt, c.chestWaitAt = nil, nil, nil, nil
        c.status = "Crystal: preparing quests\"""",
"""        c.batch, c.pins, c.rotationAt, c.chestWaitAt = nil, nil, nil, nil
        c.uncredited, c.travelAt, c.rankWaitAt, c.rankWaitExpired = 0, nil, nil, nil
        c.status = "Crystal: preparing quests\"""")
edit("C GUI status line",
"""        GUI.crystalKeys.Text = string.format("Keys %s | requests %s/%s | reserve %s", int(Crystal.keyCount(getSave())),
            int(crystal.used or 0), int(CONFIG.CrystalKeyLimit or 5000), int(CONFIG.CrystalKeyReserve or 100))""",
"""        local keys = int(Crystal.keyCount(getSave()))
        -- v1.1.8: while the mode is ON, show why it is (or is not) opening.
        GUI.crystalKeys.Text = CONFIG.AutoCrystalRank and string.format("Keys %s | %s", keys, tostring(crystal.status or ""))
            or string.format("Keys %s | requests %s/%s | reserve %s", keys,
                int(crystal.used or 0), int(CONFIG.CrystalKeyLimit or 5000), int(CONFIG.CrystalKeyReserve or 100))""")

# --- Fishing / minigames ------------------------------------------------------------------
edit("F2 visit budget",
"""            if not mg.priorityFirst and M.hasNormalGoals() and now - tx.timestamp >= (CONFIG.MinigameVisitSeconds or 90) and not mg.operation then""",
"""            -- v1.1.8: the visit budget counts from this visit's first EXECUTE tick (travel and
            -- loading no longer use it up) and a deferral waits for an idle stage, never
            -- abandoning a cast, bite or catch. The session survives EXECUTE<->VERIFY.
            mg.session.visitAt = mg.session.visitAt or now
            if not mg.priorityFirst and M.hasNormalGoals() and now - mg.session.visitAt >= (CONFIG.MinigameVisitSeconds or 90)
                and not mg.operation and (mg.session.fishStage or "READY") == "READY" then""")
edit("F3 newest debris first",
"""        local inspected = 0
        for _, host in ipairs(debris:GetChildren()) do
            inspected += 1
            if inspected > 256 then break end
            if host.Name == "host\"""",
"""        -- v1.1.8: new bubble hosts are normally appended last; inspect the newest 256 first.
        local children = debris:GetChildren()
        for i = #children, math.max(1, #children - 255), -1 do
            local host = children[i]
            if host.Name == "host\"""")

for name, old, new in EDITS:
    count = s.count(old)
    if count != 1:
        sys.exit(f"edit '{name}': expected 1 match, found {count}")
    s = s.replace(old, new)
open(out_path, "wb").write(s.replace("\n", "\r\n").encode("utf-8"))
print(f"applied {len(EDITS)} edits -> {out_path}")
