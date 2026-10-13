"""Trading & Mailbox safety and mailbox claim logic (mock data, not live PS99)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run_modules, bundle_text

src = bundle_text()
assert "AutoOpenMailbox" not in src
run_modules(r'''
local trading = Modules.byId.trading
assert(Config.AutoClaimMailbox == false and Config.AllowMailSend == false and Config.MailRecipient == "",
    "mail features default OFF and no preset recipient")
-- Mailbox claim: Mark Approached then Claim All; inventory growth confirms.
Config.AutoClaimMailbox = true
fake.save = {Inventory = {Misc = {a = {id = "Gift Bag", _am = 1}}}}
fake.responses["Machines: Mark Approached"] = true
fake.responses["Mailbox: Claim All"] = function() return true end
tickModule("trading")
assert(sent("Machines: Mark Approached") == 1 and sent("Mailbox: Claim All") == 1)
assert(lastRequest("Machines: Mark Approached").args[1] == "MailboxMachine")
fake.save.Inventory.Misc.b = {id = "Huge Cat Mail", _am = 1}
advance(5) tickModule("trading")
assert(trading.mail.claimed == 1 and Modules.stat("trading", "mailbox").confirmed == 1)
-- Not again before 60 s.
advance(10) tickModule("trading")
assert(sent("Mailbox: Claim All") == 1)
-- Server cooldown message backs off 31 s and is not counted as a claim.
fake.responses["Mailbox: Claim All"] = function() return false, "You must wait 30 seconds before using the mailbox!" end
advance(60) tickModule("trading")
assert(sent("Mailbox: Claim All") == 2 and trading.mail.last:find("wait", 1, true), trading.mail.last)
advance(20) tickModule("trading")
assert(sent("Mailbox: Claim All") == 2, "cooldown respected")
print("PASS mailbox: approach + claim, inventory confirmation, 60 s cadence, server cooldown")

-- Manual mail: every gate must hold before anything is sent.
fake.clients.Directory = {Pets = {Cat = {}, ["Huge Cat"] = {huge = true}}}
fake.save = {Inventory = {Pet = {p1 = {id = "Huge Cat", _am = 1}, p2 = {id = "Cat", _am = 5, _lk = true},
    p3 = {id = "Cat", _am = 4, sh = true}, p4 = {id = "Cat", _am = 3}}}}
local list = trading.sendable()
assert(#list == 1 and list[1].uid == "p4", "only the plain unlocked Cat stack is sendable")
local before = sent("Mailbox: Send")
local ok, why = trading.send()
assert(not ok and why:find("Allow one manual mail send", 1, true))
Config.AllowMailSend = true
Config.MailRecipient = "x"
ok, why = trading.send()
assert(not ok and why:find("exact Roblox username", 1, true))
Config.MailRecipient = "Tester"
ok, why = trading.send()
assert(not ok, "cannot mail yourself")
Config.MailRecipient = "Friend_123"
ok, why = trading.send()
assert(not ok and why:find("cost unreadable", 1, true), "unknown postage refuses: " .. tostring(why))
-- Provide postage constants and affordability.
local constants = {module = {MailboxDiamondCost = 10000}}
local balancing = {FindFirstChild = function(_, n) return n == "Constants" and constants or nil end}
local library = {FindFirstChild = function(_, n) return n == "Balancing" and balancing or nil end}
ReplicatedStorage = {FindFirstChild = function(_, n) return n == "Library" and library or nil end}
fake.clients.CurrencyCmds = {CanAfford = function(currency, amount) return currency == "Diamonds" and amount == 10000 end}
ok, why = trading.send()
assert(not ok and why:find("press SEND again", 1, true), "first click only arms")
assert(sent("Mailbox: Send") == before)
advance(6)
ok, why = trading.send()
assert(not ok and why:find("press SEND again", 1, true), "confirmation window expired: re-armed")
fake.responses["Mailbox: Send"] = true
ok, why = trading.send()
assert(ok, why)
local r = lastRequest("Mailbox: Send")
assert(r.args[1] == "Friend_123" and r.args[2] == "" and r.args[3] == "Pet" and r.args[4] == "p4" and r.args[5] == 1)
assert(Config.AllowMailSend == false, "switch turns itself off after one send")
ok, why = trading.send()
assert(not ok and sent("Mailbox: Send") == before + 1, "no second send without a new opt-in")
print("PASS manual mail: protected/locked/shiny excluded, recipient rules, postage + double click, one send per opt-in")
''', names=["70_trading.lua"], name="trading")
print("PASS test_trading")
