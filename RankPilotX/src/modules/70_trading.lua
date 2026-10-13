-- Trading & Mailbox. Sources (research 2026-10-11):
--   Machines: Mark Approached (Fire) ("MailboxMachine") + "Mailbox: Claim All" (Invoke) -> (ok, err);
--     30 s server cooldown "You must wait 30 seconds before using the mailbox!"
--     [qvirthh ps99.ui 2026-10-03; fornamess 2026-06; kyro 2026-08; others]
--   "Mailbox: Send" (Invoke) (recipient, message, class, uid, amount) -> true | (false, reason)
--     [Xinity0324 automail 2026-06; PandaOvO 2026-08; 5-argument form in every 2024-2026 source]
--   Trading Plaza place ids 15502339080 / 15588442388 [sakahr315 Booth 2026-06; kyro 2026-08]
-- Safety: claiming only receives items. Sending is MANUAL ONLY: an exact
-- recipient typed by the user, one selected non-protected stack, the
-- "Allow mail sending" switch (OFF by default, switched OFF again after each
-- send), a second click within 5 s, an affordability check, and a Save check
-- afterwards. Nothing is ever sent automatically, on a timer, or to a preset
-- account. Booth listing and trade requests are not implemented: there is no
-- evidenced remote to undo a listing.
(function()
    local M = {id = "trading", title = "Trading & Mailbox", page = "trading", interval = 10}
    M.defaults = {AutoClaimMailbox = false, AllowMailSend = false, MailRecipient = ""}
    M.features = {
        {key = "AutoClaimMailbox", name = "Claim mailbox", status = "UNVERIFIED",
            evidence = "Mailbox: Claim All - 5+ sources 2026"},
        {key = "AllowMailSend", name = "Allow one manual mail send", status = "EXPERIMENTAL",
            evidence = "Mailbox: Send (5 args) - 2026 automail sources; manual only"},
    }
    M.PLAZA = {[15502339080] = true, [15588442388] = true}
    M.CLASSES = {"Pet", "Misc", "Potion", "Enchant", "Fruit", "Consumable", "Lootbox"}
    local mail = {next = 0, last = "not checked", claimed = 0, pendingTotal = nil, pendingAt = 0,
        selection = 0, amountMode = 1, confirmAt = -100, sendLast = "nothing sent"}
    M.mail = mail

    local function inventoryTotal(data)
        local inv = type(data) == "table" and data.Inventory
        if type(inv) ~= "table" then return nil end
        local total = 0
        for _, class in ipairs(M.CLASSES) do
            for _, row in pairs(type(inv[class]) == "table" and inv[class] or {}) do
                if type(row) == "table" then total = total + math.max(0, tonumber(row._am) or 1) end
            end
        end
        return total
    end
    M.inventoryTotal = inventoryTotal

    function M.claimTick()
        if now() < mail.next then return false end
        mail.next = now() + 60
        local before = inventoryTotal(saveData(true))
        pcall(network, "Machines: Mark Approached", {"MailboxMachine"}, false)
        local ok, result, reason = Modules.call("trading", "mailbox", "Mailbox: Claim All", {}, true, 30)
        local message = type(reason) == "string" and reason or (type(result) == "string" and result) or nil
        if message and string.find(string.lower(message), "wait", 1, true) then
            mail.next = now() + 31 -- server cooldown: "You must wait 30 seconds..."
            mail.last = message
            return false
        end
        if not ok then
            mail.last = "Claim All refused: " .. describe(message or result)
            return false
        end
        mail.pendingTotal, mail.pendingAt = before, now()
        mail.last = "Claim All accepted; checking inventory"
        return true
    end

    function M.confirmClaim()
        if not mail.pendingTotal or now() - mail.pendingAt < 4 then return end
        local after = inventoryTotal(saveData(true))
        if after and after > mail.pendingTotal then
            mail.claimed = mail.claimed + 1
            Modules.note("trading", "mailbox", "confirmed", "mail claimed: inventory +" .. (after - mail.pendingTotal))
            mail.last = "Mail claimed (inventory +" .. (after - mail.pendingTotal) .. ")"
        else
            mail.last = "Mailbox empty or nothing new"
        end
        mail.pendingTotal = nil
    end

    function M.tick()
        M.confirmClaim()
        if Config.AutoClaimMailbox then M.claimTick() end
    end
    M.active = function() return Config.AutoClaimMailbox == true or mail.pendingTotal ~= nil end

    -- ------------------------------------------------------------- manual mail
    function M.validRecipient(name)
        name = tostring(name or "")
        if #name < 3 or #name > 20 then return false end
        if string.find(name, "^[%w_]+$") == nil then return false end
        if LocalPlayer and name == LocalPlayer.Name then return false end
        return true
    end

    -- Sendable stacks: never pets the framework marks protected (huge,
    -- titanic, exclusive, shiny, locked, listed), never locked items.
    function M.sendable()
        local data = saveData()
        local inv = type(data) == "table" and data.Inventory or {}
        local list = {}
        for _, class in ipairs(M.CLASSES) do
            for uid, row in pairs(type(inv[class]) == "table" and inv[class] or {}) do
                if type(row) == "table" and type(row.id) == "string" and row._lk ~= true then
                    local blocked = class == "Pet" and Modules.isProtectedPet(uid, row)
                    if not blocked then
                        table.insert(list, {class = class, uid = uid, id = row.id, amount = math.max(1, tonumber(row._am) or 1)})
                    end
                end
            end
        end
        table.sort(list, function(a, b)
            if a.class ~= b.class then return a.class < b.class end
            if a.id ~= b.id then return a.id < b.id end
            return tostring(a.uid) < tostring(b.uid)
        end)
        return list
    end

    function M.selected()
        local list = M.sendable()
        if #list == 0 then return nil end
        local index = (mail.selection % #list) + 1
        return list[index]
    end
    function M.sendAmount(entry)
        if not entry then return 0 end
        if mail.amountMode == 1 then return 1 end
        if mail.amountMode == 2 then return math.min(10, entry.amount) end
        return entry.amount
    end

    -- Base cost from the game's own constants; nil means "unknown -> refuse".
    function M.mailCost()
        local library = findChild(ReplicatedStorage, "Library")
        local constants = tryModule(findChild(findChild(library, "Balancing"), "Constants"))
        local base = constants and tonumber(constants.MailboxDiamondCost)
        return base
    end

    function M.send()
        local entry = M.selected()
        local recipient = tostring(Config.MailRecipient or "")
        if not Config.AllowMailSend then return false, "turn ON 'Allow one manual mail send' first" end
        if not M.validRecipient(recipient) then return false, "enter an exact Roblox username (3-20 letters/digits/_)" end
        if not entry then return false, "no sendable (non-protected, unlocked) stack" end
        local amount = M.sendAmount(entry)
        local cost = M.mailCost()
        if not cost then return false, "mail cost unreadable; refusing to send" end
        local okAfford, canAfford = callMethod(state.clients.CurrencyCmds, "CanAfford", "Diamonds", cost)
        if not okAfford or canAfford ~= true then return false, "cannot verify " .. tostring(cost) .. " diamonds for postage" end
        if now() - mail.confirmAt > 5 then
            mail.confirmAt = now()
            return false, string.format("press SEND again within 5 s to mail %d x %s (%s) to %s", amount, entry.id, entry.class, recipient)
        end
        mail.confirmAt = -100
        Config.AllowMailSend = false -- one send per explicit opt-in
        persist()
        local ok, result = Modules.call("trading", "mailsend", "Mailbox: Send",
            {recipient, "", entry.class, entry.uid, amount}, true, 5)
        if not ok or result ~= true then return false, "Mailbox: Send refused: " .. describe(result) end
        task.delay(4, function()
            local rows = Modules.inventory(entry.class, true)
            local row = rows and rows[entry.uid]
            local left = type(row) == "table" and (tonumber(row._am) or 1) or 0
            if left < entry.amount then
                Modules.note("trading", "mailsend", "confirmed", "sent " .. amount .. " x " .. entry.id .. " to " .. recipient)
            end
        end)
        return true, "sent request: " .. amount .. " x " .. entry.id .. " to " .. recipient
    end

    function M.report()
        return string.format("mailbox=%s claimed=%d | mail send=%s | plaza=%s", tostring(mail.last), mail.claimed,
            tostring(mail.sendLast), tostring(M.PLAZA[game.PlaceId] == true))
    end

    function M.buildUI(h, ui)
        local p = h.page("trading")
        h.section(p, "MAILBOX", "Claiming only receives items")
        h.toggle(p, "AutoClaimMailbox", "Claim mailbox", "Mailbox: Claim All every 60 s; respects the 30 s server cooldown")
        ui.mailStatus = h.rowLabel(p, "Mailbox: not checked")
        h.section(p, "PROTECTED INVENTORY", "Huge, titanic, exclusive, shiny, locked and listed pets are never mailed or used")
        ui.protectedStatus = h.rowLabel(p, "Protected pets: not counted")
        h.section(p, "MANUAL MAIL (OPTIONAL)", "Never automatic. One send per opt-in, exact recipient, second click to confirm")
        local recipientRow = h.rowLabel(p, "Recipient:")
        pcall(function()
            local box = h.create("TextBox", {Name = "MailRecipient", BackgroundColor3 = h.theme.surface,
                BorderSizePixel = 0, Position = UDim2.fromOffset(110, 5), Size = UDim2.fromOffset(250, 28),
                Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = h.theme.white, Text = tostring(Config.MailRecipient or ""),
                PlaceholderText = "exact username", ClearTextOnFocus = false}, recipientRow.Parent)
            h.rounded(box, 6)
            table.insert(state.connections, box.FocusLost:Connect(function()
                Config.MailRecipient = string.gsub(tostring(box.Text or ""), "%s", "")
                box.Text = Config.MailRecipient
                persist()
            end))
        end)
        h.choice(p, "Item to send", "Cycles through non-protected, unlocked stacks",
            function()
                local entry = M.selected()
                return entry and (entry.id .. " x" .. entry.amount .. "  >") or "none  >"
            end,
            function() mail.selection = mail.selection + 1 end)
        h.choice(p, "Amount", "1, up to 10, or the whole stack",
            function() return ({"1", "up to 10", "whole stack"})[mail.amountMode] .. "  >" end,
            function() mail.amountMode = mail.amountMode % 3 + 1 end)
        h.toggle(p, "AllowMailSend", "Allow one manual mail send", "Turns itself OFF after one send. Postage diamonds are spent")
        h.toolbar(p, {{"SEND (PRESS TWICE)", function()
            local ok, message = M.send()
            mail.sendLast = tostring(message)
            log("Mail: " .. tostring(message), ok and "TRADE" or "SAFEGUARD")
        end, h.theme.red}})
        ui.mailSendStatus = h.rowLabel(p, "Mail send: nothing sent")
        h.section(p, "BOOTHS & TRADES", "Read-only")
        ui.plazaStatus = h.rowLabel(p, "Trading Plaza: not checked")
        h.note(p, "Booth listing and trade requests are intentionally not automated: there is no evidenced remote to remove a listing, and selling/trading must never run unattended.", 52)
    end

    function M.render(ui)
        if ui.activePage ~= "trading" or not ui.mailStatus then return end
        ui.mailStatus.Text = string.format("Mailbox: %s  |  claims confirmed %d", tostring(mail.last), mail.claimed)
        local data = saveData()
        local pets = type(data) == "table" and data.Inventory and data.Inventory.Pet or {}
        local protected, total = 0, 0
        for uid, row in pairs(type(pets) == "table" and pets or {}) do
            total = total + 1
            if Modules.isProtectedPet(uid, row) then protected = protected + 1 end
        end
        ui.protectedStatus.Text = string.format("Protected pet stacks: %d of %d", protected, total)
        ui.mailSendStatus.Text = "Mail send: " .. tostring(mail.sendLast)
        ui.plazaStatus.Text = "Trading Plaza: " .. (M.PLAZA[game.PlaceId] and "in a plaza server" or "not in the plaza")
    end
    Modules.define(M)
end)()
