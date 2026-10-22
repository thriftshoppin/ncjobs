-- Run from the resource folder: lua5.4 tests/service_test.lua
-- The bar against a fake economy that keeps real balances and is idempotent per opId, like
-- rp_economy. After every scenario: money is conserved, and nobody is charged twice.
dofile("shared/config.lua")
local C = O77BarConfig
local M = dofile("server/model.lua")
local S = dofile("server/service.lua")

local fails, runs = 0, 0
local function check(name, cond, detail)
    runs = runs + 1
    if not cond then fails = fails + 1; print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "")) end
end

local BAR = C.bars.afterlife
local STATION = BAR.stations[1].position
local COOLER = BAR.coolers[1].position
local TILL = "soc:" .. BAR.society
local SUBJECT = { [1] = "cust", [2] = "barb", [3] = "barb2", [4] = "cust2" }

-- ------------------------------------------------------------------ fake world
local function world()
    local W = { t = 1000000, pos = {}, jobs = {}, grade = {}, notes = {}, ui = {}, events = {}, tabs = {}, debt = {}, settings = {}, charges = 0 }
    W.bal = { ["sub:cust:cash"] = 500, ["sub:cust:bank"] = 2000, ["sub:cust2:cash"] = 100, ["sub:cust2:bank"] = 0,
        ["sub:barb:cash"] = 0, ["sub:barb2:cash"] = 0, [TILL] = 0, ["soc:" .. C.escrowSociety] = 0 }
    W.ops = {}
    W.failNext = nil
    local function acct(party)
        if party.society then return "soc:" .. party.society end
        return ("sub:%s:%s"):format(party.subject, party.wallet or "cash")
    end
    function W.total() local n = 0 for _, v in pairs(W.bal) do n = n + v end return n end
    local function take(subject, instrument, amount)
        local cash, bank = "sub:" .. subject .. ":cash", "sub:" .. subject .. ":bank"
        local have = instrument == "cash" and (W.bal[cash] or 0) or instrument == "bank" and (W.bal[bank] or 0)
            or (W.bal[cash] or 0) + (W.bal[bank] or 0)
        if have < amount then return false end
        if instrument == "bank" then W.bal[bank] = W.bal[bank] - amount return true end
        local fromCash = math.min(W.bal[cash] or 0, amount)
        W.bal[cash] = (W.bal[cash] or 0) - fromCash
        if instrument == "cash" then return true end
        W.bal[bank] = (W.bal[bank] or 0) - (amount - fromCash)
        return true
    end
    W.economy = {
        charge = function(spec)
            if W.ops[spec.opId] then return W.ops[spec.opId] end
            if W.failNext then local f = W.failNext; W.failNext = nil; return nil, f.reason, f.info end
            local sum = 0
            for _, p in ipairs(spec.payees) do sum = sum + p.amount end
            assert(sum == spec.amount, ("payees %d ~= amount %d"):format(sum, spec.amount))
            if not take(spec.from.subject, spec.instrument, spec.amount) then return nil, "insufficient_funds" end
            for _, p in ipairs(spec.payees) do local a = acct(p); W.bal[a] = (W.bal[a] or 0) + p.amount end
            W.charges = W.charges + 1
            W.ops[spec.opId] = { opId = spec.opId, state = "committed" }
            return W.ops[spec.opId]
        end,
        pay = function(spec)
            if W.ops[spec.opId] then return W.ops[spec.opId] end
            if W.failNext then local f = W.failNext; W.failNext = nil; return nil, f.reason, f.info end
            local from = acct(spec.from)
            local lines = spec.payees or { { subject = spec.to.subject, society = spec.to.society, wallet = spec.to.wallet, amount = spec.amount } }
            local sum = 0
            for _, l in ipairs(lines) do sum = sum + l.amount end
            if (W.bal[from] or 0) < sum then return nil, "insufficient_funds" end
            W.bal[from] = W.bal[from] - sum
            for _, l in ipairs(lines) do local a = acct(l); W.bal[a] = (W.bal[a] or 0) + l.amount end
            W.ops[spec.opId] = { opId = spec.opId, state = "committed" }
            return W.ops[spec.opId]
        end,
        status = function(opId) return { state = W.ops[opId] and "committed" or "unknown" } end,
    }
    local function balancesOf(s) return { cash = W.bal["sub:" .. s .. ":cash"] or 0, bank = W.bal["sub:" .. s .. ":bank"] or 0 } end
    W.P = {
        now = function() return W.t end, bootId = function() return "B1" end, log = function() end,
        position = function(pid) return W.pos[pid] end,
        hasJob = function(pid, job) return W.jobs[pid] == job end,
        subject = function(pid) return SUBJECT[pid] end,
        name = function(pid) return "P" .. pid end,
        grade = function(pid) return W.grade[pid] or 0 end,
        employed = function() local o = {} for pid, j in pairs(W.jobs) do if j == C.job then o[#o + 1] = pid end end return o end,
        notify = function(pid, msg) W.notes[#W.notes + 1] = { pid, msg } end,
        ui = function(pid, view, data) W.ui[#W.ui + 1] = { pid = pid, view = view, data = data } end,
        toCustomer = function() end, toBartender = function() end,
        event = function(...) W.events[#W.events + 1] = { ... } end,
        handover = function() end,
        progress = function(pid, label, ms) W.progress = { pid, label, ms } end,
        giveBottles = function(pid, bottles) W.given = W.given or {}; for _, b in ipairs(bottles) do W.given[#W.given + 1] = { pid, b.item, b.qty } end end,
        balances = function(pid) return SUBJECT[pid] and balancesOf(SUBJECT[pid]) end,
        balancesOf = balancesOf,
        store = {
            saveTab = function(t) W.tabs[t.id] = { state = t.state, how = t.how } return true end,
            debtOf = function(s) return W.debt[s] or 0 end,
            addDebt = function(s, bar, amount) W.debt[s] = (W.debt[s] or 0) + amount end,
            saveSetting = function(bar, key, value) W.settings[bar .. ":" .. key] = value end,
            saveRound = function(r) W.rounds = W.rounds or {}; W.rounds[r.id] = r.state return true end,
        },
        economy = W.economy,
    }
    return W
end

local function lastUi(W, pid, view)
    for i = #W.ui, 1, -1 do local u = W.ui[i] if u.pid == pid and u.view == view then return u.data end end
end

local function at(p) return { x = p.x, y = p.y, z = p.z } end
local function setup()
    local W = world()
    local svc = S.new(C, M, W.P)
    W.pos[1] = { x = STATION.x + 1.0, y = STATION.y, z = STATION.z }
    W.pos[2] = at(STATION)
    W.pos[4] = { x = STATION.x + 1.5, y = STATION.y + 0.5, z = STATION.z }
    W.jobs[2] = C.job
    svc:onSeated(1, "stool_1")
    assert(svc:clockIn(2))
    return W, svc
end

local PERFECT = {
    johnny_silverhand = { { id = "tequila", ml = 60 }, { id = "agave", ml = 10 }, { id = "bitters", count = 2 }, { id = "ice", count = 2 },
        { id = "stir", hits = { "perfect", "good", "perfect" } }, { id = "lime", ml = 15 }, { id = "cerveza", ml = 30 }, { id = "chili", count = 1 } },
    jackie_welles = { { id = "ice", count = 3 }, { id = "vodka", ml = 45 }, { id = "lime", ml = 15 }, { id = "ginger", ml = 120 }, { id = "love", count = 1 } },
    broseph = { { id = "lager", ml = 455 } },
}

-- Hand the menu, order, make everything, serve. Answers the round's id, or nil, reason.
local function round(W, svc, barman, customer, items)
    local r, why = svc:lockOn(barman, customer, "menu")
    assert(r == "menu", why)
    local id = lastUi(W, customer, "menu").ticketId
    local ok, why2 = svc:menuSubmit(customer, id, items)
    if not ok then return nil, why2 end
    local rd = svc.rounds[id]
    local home = at(W.pos[barman])
    for i, q in ipairs(rd.queue) do
        if q.kind == "grab" then
            W.pos[barman] = at(COOLER); assert(svc:startGrab(barman, id, i)); W.t = W.t + 5000; assert(svc:finishGrab(barman))
        else
            W.pos[barman] = at(STATION); assert(svc:startPour(barman, id, i)); W.t = W.t + 20000
            assert(svc:pourSubmit(barman, id, i - 1, PERFECT[q.drink]))
        end
    end
    W.pos[barman] = home
    assert(svc:lockOn(barman, customer, "serve") == "served")
    return id
end

local function conserved(name, W, start) check(name .. ": money conserved", W.total() == start, W.total() - start) end
local function tabOf(svc, pid) return svc:tabOfPlayer(pid) end
local function lastHow(W) local how for _, t in pairs(W.tabs) do if t.how then how = t.how end end return how end
local OUTSIDE = { x = BAR.venue.position.x + 80, y = BAR.venue.position.y, z = BAR.venue.position.z }

-- ------------------------------------------------------------------ 1. two rounds on a tab, then close it at the kiosk
do
    local W, svc = setup()
    local start = W.total()
    round(W, svc, 2, 1, { { drink = "johnny_silverhand", qty = 1 } })
    check("1 nothing charged yet", W.charges == 0 and W.bal["sub:cust:cash"] == 500)
    round(W, svc, 2, 1, { { drink = "broseph", qty = 1 } })
    local tab = tabOf(svc, 1)
    check("1 tab owes 180", M.owed(tab) == 180, M.owed(tab))
    check("1 bill", svc:lockOn(2, 1, "bill") == "bill")
    local k = lastUi(W, 1, "kiosk")
    check("1 kiosk lists both", k and #k.items == 2)
    check("1 pay", svc:kioskPay(1, tab.id, 15, "cash") == true)
    -- 180, tip 27: till 108, bartender 72 + 27 = 99
    check("1 customer paid 207", W.bal["sub:cust:cash"] == 500 - 207, W.bal["sub:cust:cash"])
    check("1 till 108", W.bal[TILL] == 108, W.bal[TILL])
    check("1 bartender 99", W.bal["sub:barb:cash"] == 99, W.bal["sub:barb:cash"])
    check("1 one charge", W.charges == 1)
    check("1 tab settled", lastHow(W) == "closed" and tabOf(svc, 1) == nil)
    conserved("1", W, start)
end

-- ------------------------------------------------------------------ 2. only what you can afford
do
    local W, svc = setup()
    svc:onSeated(4, "stool_2")
    local _, why = round(W, svc, 2, 4, { { drink = "johnny_silverhand", qty = 1 } })   -- 150 > 100
    check("2 can't afford a Silverhand", why == "cannot_afford", why)
    svc:menuCancel(4, lastUi(W, 4, "menu").ticketId)
    check("2 a beer is fine", round(W, svc, 2, 4, { { drink = "broseph", qty = 1 } }) ~= nil)
    local _, why2 = round(W, svc, 2, 4, { { drink = "broseph", qty = 3 } })             -- 30 owed + 90 > 100
    check("2 tab counts against the limit", why2 == "cannot_afford", why2)
    check("2 menu shows what they can spend", lastUi(W, 4, "menu").canSpend == 70, lastUi(W, 4, "menu").canSpend)
end

-- ------------------------------------------------------------------ 3. carrying drinks around the club is fine
do
    local W, svc = setup()
    round(W, svc, 2, 1, { { drink = "jackie_welles", qty = 1 } })
    svc:onStood(1)
    W.pos[1] = { x = BAR.venue.position.x + 30, y = BAR.venue.position.y, z = BAR.venue.position.z }   -- dance floor
    svc:tick()
    check("3 tab still open", tabOf(svc, 1) and tabOf(svc, 1).state == "open")
    check("3 not charged", W.charges == 0)
    W.pos[2] = { x = W.pos[1].x + 1, y = W.pos[1].y, z = W.pos[1].z }
    check("3 bartender can bill them on the floor", svc:lockOn(2, 1, "bill") == "bill")
end

-- ------------------------------------------------------------------ 4. walkout: tab + fee, cash first then bank
do
    local W, svc = setup()
    local start = W.total()
    round(W, svc, 2, 1, { { drink = "johnny_silverhand", qty = 2 }, { drink = "broseph", qty = 3 } })   -- 390
    W.pos[1] = at(OUTSIDE)
    svc:tick()
    local fee = M.walkoutFee(C.tab.walkout, 390)
    check("4 fee is 25 %", fee == 98, fee)
    check("4 charged tab + fee", W.bal["sub:cust:cash"] + W.bal["sub:cust:bank"] == 2500 - 390 - fee)
    check("4 cash went first", W.bal["sub:cust:cash"] == 12, W.bal["sub:cust:cash"])
    check("4 fee to the till", W.bal[TILL] == math.floor(390 * 0.6) + fee, W.bal[TILL])
    check("4 bartender still paid", W.bal["sub:barb:cash"] == 390 - math.floor(390 * 0.6))
    check("4 recorded as walkout", lastHow(W) == "walkout", lastHow(W))
    svc:tick()
    check("4 charged once", W.charges == 1)
    conserved("4", W, start)
end

-- ------------------------------------------------------------------ 5. the boss sets the walkout fee
do
    local W, svc = setup()
    check("5 employee can't", select(2, svc:setWalkoutFee(2, "flat", 100)) == "not_the_boss")
    W.grade[2] = 3
    check("5 bad value", select(2, svc:setWalkoutFee(2, "percent", 400)) == "invalid_fee")
    check("5 bad mode", select(2, svc:setWalkoutFee(2, "free", 1)) == "invalid_fee")
    check("5 boss sets 100 flat", svc:setWalkoutFee(2, "flat", 100) ~= nil and W.settings["afterlife:walkout"].value == 100)
    round(W, svc, 2, 1, { { drink = "broseph", qty = 1 } })
    W.pos[1] = at(OUTSIDE)
    svc:tick()
    check("5 flat fee charged", W.bal["sub:cust:cash"] == 500 - 30 - 100, W.bal["sub:cust:cash"])
    local svc2 = S.new(C, M, W.P)
    svc2:loadSettings({ { bar = "afterlife", key = "walkout", value = W.settings["afterlife:walkout"] } })
    check("5 setting survives restart", svc2:feeSetting("afterlife").value == 100)
end

-- ------------------------------------------------------------------ 6. walkout they can't cover: pay what they have, rest is debt
do
    local W, svc = setup()
    svc:onSeated(4, "stool_2")
    round(W, svc, 2, 4, { { drink = "broseph", qty = 3 } })   -- 90 of their 100
    W.bal["sub:cust2:cash"] = 40                               -- spent it elsewhere
    W.bal["sub:other:cash"] = 60                               -- (where it went)
    local start = W.total()
    W.pos[4] = at(OUTSIDE)
    svc:tick()
    -- owes 90 + fee 50 (25 % = 23, minimum 50) = 140; has 40
    check("6 took everything", W.bal["sub:cust2:cash"] == 0)
    check("6 bartender paid first", W.bal["sub:barb:cash"] == 36, W.bal["sub:barb:cash"])
    check("6 rest is debt", W.debt.cust2 == 100, W.debt.cust2)
    W.pos[4] = { x = STATION.x + 1.5, y = STATION.y, z = STATION.z }
    svc:onSeated(4, "stool_2")
    check("6 no new tab while owing", select(2, svc:lockOn(2, 4, "menu")) == "customer_owes")
    conserved("6", W, start)
end

-- ------------------------------------------------------------------ 7. disconnect: grace, reconnect keeps the tab, no-show is charged without a fee
do
    local W, svc = setup()
    local start = W.total()
    round(W, svc, 2, 1, { { drink = "jackie_welles", qty = 1 } })
    svc:onDropped(1)
    W.t = W.t + C.tab.disconnectGraceMs - 1000
    svc:tick()
    check("7 not charged during grace", W.charges == 0)
    svc:onJoined(1)
    check("7 tab back", tabOf(svc, 1).customer.pid == 1)
    svc:onDropped(1)
    W.t = W.t + C.tab.disconnectGraceMs + 1
    svc:tick()
    check("7 charged tab only", W.bal["sub:cust:cash"] == 500 - 150, W.bal["sub:cust:cash"])
    check("7 recorded as leave", lastHow(W) == "leave", lastHow(W))
    conserved("7", W, start)
end

-- ------------------------------------------------------------------ 8. restart: open tabs come back and get the same grace
do
    local W, svc = setup()
    local start = W.total()
    round(W, svc, 2, 1, { { drink = "broseph", qty = 2 } })
    local tab = tabOf(svc, 1)
    local row = { id = tab.id, bar = tab.bar, customer = { subject = "cust", name = "P1", pid = 1 }, state = "open",
        served = tab.served, attempt = 1 }
    local svc2 = S.new(C, M, W.P)
    check("8 recovered", svc2:recover({ row }) == 1)
    svc2:onJoined(1)
    check("8 customer gets it back", svc2:tabOfPlayer(1) and svc2:tabOfPlayer(1).customer.pid == 1)
    svc2:onDropped(1)
    W.t = W.t + C.tab.disconnectGraceMs + 1
    svc2:tick()
    check("8 charged after grace", W.bal["sub:cust:cash"] == 440, W.bal["sub:cust:cash"])
    conserved("8", W, start)
end

-- ------------------------------------------------------------------ 9. kiosk charge fails once: retried, charged once
do
    local W, svc = setup()
    local start = W.total()
    round(W, svc, 2, 1, { { drink = "broseph", qty = 1 } })
    local tab = tabOf(svc, 1)
    W.failNext = { reason = "store_unavailable", info = { retryable = true } }
    check("9 first try fails", svc:kioskPay(1, tab.id, 0, "cash") == nil and tab.state == "closing")
    W.t = W.t + C.retryMs + 1
    svc:tick()
    check("9 resolved: unknown -> reopened", tab.state == "open" and tab.attempt == 2, tab.state)
    check("9 pay again", svc:kioskPay(1, tab.id, 0, "cash") == true)
    check("9 once", W.charges == 1 and W.bal["sub:cust:cash"] == 470)
    conserved("9", W, start)
end

-- ------------------------------------------------------------------ 10. two bartenders: cuts and tip follow who served what
do
    local W, svc = setup()
    local start = W.total()
    W.jobs[3] = C.job
    W.pos[3] = { x = STATION.x, y = STATION.y + 0.6, z = STATION.z }
    assert(svc:clockIn(3))
    round(W, svc, 2, 1, { { drink = "johnny_silverhand", qty = 1 } })   -- 150 by barb
    W.pos[3] = { x = STATION.x, y = STATION.y + 0.6, z = STATION.z }
    round(W, svc, 3, 1, { { drink = "broseph", qty = 1 } })             -- 30 by barb2
    local tab = tabOf(svc, 1)
    assert(svc:kioskPay(1, tab.id, 20, "bank"))                         -- 180 + 36
    -- till 108; cuts 72 split 150:30 -> 60 / 12; tip 36 -> 30 / 6
    check("10 barb", W.bal["sub:barb:cash"] == 90, W.bal["sub:barb:cash"])
    check("10 barb2", W.bal["sub:barb2:cash"] == 18, W.bal["sub:barb2:cash"])
    check("10 HUD earnings", svc.shifts[2].earned == 90 and svc.shifts[3].earned == 18)
    conserved("10", W, start)
end

-- ------------------------------------------------------------------ 11. too-fast pours end the shift; served drinks stay on the tab
do
    local W, svc = setup()
    round(W, svc, 2, 1, { { drink = "broseph", qty = 1 } })
    assert(svc:lockOn(2, 1, "menu") == "menu")
    local id = lastUi(W, 1, "menu").ticketId
    assert(svc:menuSubmit(1, id, { { drink = "johnny_silverhand", qty = 1 } }))
    for _ = 1, C.pour.tooFastStrikes do
        if svc.shifts[2] then
            W.pos[2] = at(STATION); assert(svc:startPour(2, id, 1)); W.t = W.t + 500
            svc:pourSubmit(2, id, 0, PERFECT.johnny_silverhand)
        end
    end
    check("11 off shift", svc.shifts[2] == nil)
    check("11 unmade round dropped", svc.rounds[id] == nil)
    check("11 served beer still owed", M.owed(tabOf(svc, 1)) == 30)
end

-- ------------------------------------------------------------------ 12. bottles: cooler, singles served open, bulk bagged, all on the tab
do
    local W, svc = setup()
    round(W, svc, 2, 1, { { drink = "odickin_whiskey", qty = 1 }, { drink = "nicola_blue", qty = 6 } })
    local held = 0
    for _, e in ipairs(W.events) do if e[1] == "o77_bar:servedBottle" and e[4] == "Items.MediumQualityAlcohol2" then held = held + 1 end end
    check("12 whiskey served open", held == 1)
    check("12 six NiCola Blue bagged", W.given and #W.given == 1 and W.given[1][3] == 6)
    check("12 on the tab", M.owed(tabOf(svc, 1)) == 45 + 6 * 10, M.owed(tabOf(svc, 1)))
end

-- ------------------------------------------------------------------ 13. guards
do
    local W, svc = setup()
    W.jobs[3] = C.job
    W.pos[3] = { x = STATION.x, y = STATION.y + 0.6, z = STATION.z }
    assert(svc:clockIn(3))
    assert(svc:lockOn(2, 1, "menu") == "menu")
    check("13 another bartender's round", select(2, svc:lockOn(3, 1, "menu")) == "another_bartender")
    check("13 self service", select(2, svc:lockOn(2, 2)) == "self_service")
    check("13 not a customer", select(2, svc:lockOn(2, 4)) == "not_a_customer_here")
    check("13 bill with nothing served", select(2, svc:lockOn(2, 1, "bill")) == "nothing_served")
    check("13 not a bartender", select(2, svc:clockIn(4)) == "not_a_bartender")
end

-- ------------------------------------------------------------------ 14. picking too long, or standing up mid-order, drops only that order
do
    local W, svc = setup()
    round(W, svc, 2, 1, { { drink = "broseph", qty = 1 } })
    assert(svc:lockOn(2, 1, "menu") == "menu")
    W.t = W.t + C.limits.orderTimeoutMs + 1
    svc:tick()
    check("14 order timed out", svc:roundOfCustomer(1) == nil)
    check("14 tab untouched", M.owed(tabOf(svc, 1)) == 30)
    assert(svc:lockOn(2, 1, "menu") == "menu")
    svc:onStood(1)
    check("14 standing drops the open menu", svc:roundOfCustomer(1) == nil and M.owed(tabOf(svc, 1)) == 30)
end

-- ------------------------------------------------------------------ 15. leaving with an empty tab costs nothing
do
    local W, svc = setup()
    assert(svc:lockOn(2, 1, "menu") == "menu")
    svc:menuCancel(1, lastUi(W, 1, "menu").ticketId)
    W.pos[1] = at(OUTSIDE)
    svc:tick()
    check("15 no charge", W.charges == 0 and tabOf(svc, 1) == nil)
end

-- ------------------------------------------------------------------ 16. difficulty follows the title
do
    local W, svc = setup()
    W.grade[2] = 3
    assert(svc:lockOn(2, 1, "menu") == "menu")
    local id = lastUi(W, 1, "menu").ticketId
    assert(svc:menuSubmit(1, id, { { drink = "johnny_silverhand", qty = 1 } }))
    assert(svc:startPour(2, id, 1))
    check("16 boss beat", lastUi(W, 2, "pour").beat == C.shakeByGrade[3])
end

-- ------------------------------------------------------------------ 17. split math: any tab, any tip, parts sum exactly
do
    local served = {}
    for i = 1, 7 do served[#served + 1] = { price = ({ 30, 150, 45, 20, 240, 10, 60 })[i], qty = i % 3 + 1, bartender = "b" .. (i % 3) } end
    for _, tip in ipairs({ 0, 1, 13, 99 }) do
        for _, fee in ipairs({ 0, 50, 97 }) do
            local sp = M.tabSplit(C, BAR, { served = served }, tip, fee)
            local sum = 0
            for _, p in ipairs(sp.payees) do sum = sum + p.amount; check("17 non-negative", p.amount >= 0) end
            check(("17 sums %d/%d"):format(tip, fee), sum == sp.total, sum - sp.total)
            local payees, debt, paid = M.partial(sp, 123)
            local s2 = 0
            for _, p in ipairs(payees) do s2 = s2 + p.amount end
            check("17 partial sums", s2 == paid and paid == math.min(123, sp.total) and debt == sp.total - paid)
        end
    end
end

-- ------------------------------------------------------------------ pay now
local ESCROW = "soc:" .. C.escrowSociety
-- Order a round as pay-now and pay it. Answers the round id.
local function payNow(W, svc, barman, customer, items, tip, method)
    assert(svc:lockOn(barman, customer, "menu") == "menu")
    local id = lastUi(W, customer, "menu").ticketId
    local ok, why = svc:menuSubmit(customer, id, items, "now")
    if ok ~= "pay" then return nil, why end
    check("kiosk shows the round", lastUi(W, customer, "kiosk").id == id)
    return id, svc:kioskPay(customer, id, tip or 0, method or "cash")
end
local function make(W, svc, barman, id)
    local rd = svc.rounds[id]
    local home = at(W.pos[barman])
    for i, q in ipairs(rd.queue) do
        if q.kind == "grab" then
            W.pos[barman] = at(COOLER); assert(svc:startGrab(barman, id, i)); W.t = W.t + 5000; assert(svc:finishGrab(barman))
        else
            W.pos[barman] = at(STATION); assert(svc:startPour(barman, id, i)); W.t = W.t + 20000
            assert(svc:pourSubmit(barman, id, i - 1, PERFECT[q.drink]))
        end
    end
    W.pos[barman] = home
end

-- 18. pay now: charged at the kiosk, held, paid out at the hand-over; nothing on the tab
do
    local W, svc = setup()
    local start = W.total()
    local id, ok = payNow(W, svc, 2, 1, { { drink = "johnny_silverhand", qty = 1 } }, 20, "cash")
    check("18 paid", ok == true and svc.rounds[id].state == "making")
    check("18 money held", W.bal[ESCROW] == 180 and W.bal["sub:cust:cash"] == 320, W.bal[ESCROW])
    make(W, svc, 2, id)
    check("18 serve", svc:lockOn(2, 1, "serve") == "served")
    check("18 escrow empty", W.bal[ESCROW] == 0)
    check("18 till 90", W.bal[TILL] == 90, W.bal[TILL])
    check("18 bartender 60 + 30 tip", W.bal["sub:barb:cash"] == 90, W.bal["sub:barb:cash"])
    check("18 nothing on the tab", M.owed(tabOf(svc, 1)) == 0)
    W.pos[1] = at(OUTSIDE); svc:tick()
    check("18 leaving costs nothing more", W.bal["sub:cust:cash"] == 320 and lastHow(W) == "empty", lastHow(W))
    conserved("18", W, start)
end

-- 19. pay now, then the customer leaves before it's served: refunded in full
do
    local W, svc = setup()
    local start = W.total()
    local id = payNow(W, svc, 2, 1, { { drink = "jackie_welles", qty = 2 } }, 15, "bank")
    check("19 held", W.bal[ESCROW] == 345, W.bal[ESCROW])
    W.pos[1] = at(OUTSIDE); svc:tick()
    check("19 refunded to bank", W.bal["sub:cust:bank"] == 2000 and W.bal[ESCROW] == 0, W.bal["sub:cust:bank"])
    check("19 round gone", svc.rounds[id] == nil)
    conserved("19", W, start)
end

-- 20. pay now, bartender clocks out: refunded; refund retried until it lands
do
    local W, svc = setup()
    local start = W.total()
    local id = payNow(W, svc, 2, 1, { { drink = "broseph", qty = 2 } })
    W.failNext = { reason = "store_unavailable", info = { retryable = true } }
    svc:clockOut(2, "manual")
    check("20 refund pending", svc.payouts[id] and svc.payouts[id].state == "refunding")
    W.t = W.t + C.retryMs + 1; svc:tick()
    check("20 refunded", W.bal["sub:cust:cash"] == 500 and W.bal[ESCROW] == 0)
    conserved("20", W, start)
end

-- 21. pay now and tab in one night: walkout charges only the tab
do
    local W, svc = setup()
    local start = W.total()
    round(W, svc, 2, 1, { { drink = "broseph", qty = 1 } })                              -- tab: 30
    local id = payNow(W, svc, 2, 1, { { drink = "johnny_silverhand", qty = 1 } }, 0)    -- paid: 150
    make(W, svc, 2, id); assert(svc:lockOn(2, 1, "serve") == "served")
    W.pos[1] = at(OUTSIDE); svc:tick()
    check("21 walkout = tab 30 + fee 50", W.bal["sub:cust:cash"] == 500 - 150 - 30 - 50, W.bal["sub:cust:cash"])
    conserved("21", W, start)
end

-- 22. pay now: can't afford it on that wallet -> back to the bill, try the other one
do
    local W, svc = setup()
    local start = W.total()
    local id, ok, why = payNow(W, svc, 2, 1, { { drink = "johnny_silverhand", qty = 4 } }, 0, "cash")   -- 600 > 500 cash
    check("22 refused on cash", ok == nil and why == "insufficient_funds" and svc.rounds[id].state == "billed", why)
    check("22 bank works", svc:kioskPay(1, id, 0, "bank") == true)
    check("22 standing up after paying keeps the order", (svc:onStood(1) or true) and svc.rounds[id] and svc.rounds[id].state == "making")
    conserved("22", W, start)
end

-- 23. pay now: kiosk ignored -> dropped after the timeout, nothing charged
do
    local W, svc = setup()
    assert(svc:lockOn(2, 1, "menu") == "menu")
    local id = lastUi(W, 1, "menu").ticketId
    assert(svc:menuSubmit(1, id, { { drink = "broseph", qty = 1 } }, "now") == "pay")
    W.t = W.t + C.limits.billTimeoutMs + 1; svc:tick()
    check("23 dropped", svc.rounds[id] == nil and W.charges == 0)
end

-- 24. restart with a paid round: refunded on boot
do
    local W, svc = setup()
    local start = W.total()
    local id = payNow(W, svc, 2, 1, { { drink = "broseph", qty = 1 } }, 10)
    local row = {}
    for k, v in pairs(svc.rounds[id]) do row[k] = v end
    row.customer = { subject = "cust", pid = 1, name = "P1" }; row.bartender = { subject = "barb", pid = 2, name = "P2" }
    local svc2 = S.new(C, M, W.P)
    check("24 recovered", svc2:recoverRounds({ row }) == 1)
    check("24 refunded", W.bal["sub:cust:cash"] == 500 and W.bal[ESCROW] == 0)
    conserved("24", W, start)
end

-- 25. a customer who has paid now can't order beyond what's left
do
    local W, svc = setup()
    svc:onSeated(4, "stool_2")
    local id = payNow(W, svc, 2, 4, { { drink = "broseph", qty = 3 } })   -- 90 of 100, paid
    check("25 paid", svc.rounds[id] and svc.rounds[id].paid)
    check("25 10 left, paid round not counted twice", svc:headroom(4, tabOf(svc, 4)) == 10, svc:headroom(4, tabOf(svc, 4)))
end

print(("service: %d checks, %d failed"):format(runs, fails))
os.exit(fails == 0 and 0 or 1)
