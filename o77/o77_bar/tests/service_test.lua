-- Run from the resource folder: lua5.4 tests/service_test.lua
-- The ticket service against a fake economy that keeps real balances and is idempotent per
-- opId, like rp_economy. After every scenario: escrow is 0 and money is conserved.
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
local ESCROW = "soc:" .. C.escrowSociety
local TILL = "soc:" .. BAR.society

-- ------------------------------------------------------------------ fake world
local function world()
    local W = { t = 1000000, pos = {}, jobs = {}, grade = {}, notes = {}, ui = {}, saved = {}, events = {} }
    W.bal = { ["sub:cust:cash"] = 500, ["sub:cust:bank"] = 2000, ["sub:barb:cash"] = 0, [ESCROW] = 0, [TILL] = 0 }
    W.ops = {}           -- opId -> receipt (idempotency)
    W.failNext = nil     -- { kind = "charge"|"pay", reason, info }
    W.duringCharge = nil -- function() run while a charge is "in flight"
    W.statusOf = {}      -- opId -> state override for status()
    local function acct(party)
        if party.society then return "soc:" .. party.society end
        return ("sub:%s:%s"):format(party.subject, party.wallet or "cash")
    end
    local function total() local n = 0 for _, v in pairs(W.bal) do n = n + v end return n end
    W.total = total
    local function move(from, to, amount)
        if (W.bal[from] or 0) < amount then return false end
        W.bal[from] = W.bal[from] - amount
        W.bal[to] = (W.bal[to] or 0) + amount
        return true
    end
    W.economy = {
        charge = function(spec)
            if W.duringCharge then local f = W.duringCharge; W.duringCharge = nil; f() end
            if W.ops[spec.opId] then return W.ops[spec.opId] end
            if W.failNext and W.failNext.kind == "charge" then
                local f = W.failNext; W.failNext = nil
                if f.reason == "in_doubt_committed" then
                    move(acct(spec.from), acct(spec.to), spec.amount)
                    W.ops[spec.opId] = { opId = spec.opId, state = "committed" }
                    return nil, "in_doubt", { retryable = true }
                end
                return nil, f.reason, f.info
            end
            if not move(acct(spec.from), acct(spec.to), spec.amount) then return nil, "insufficient_funds" end
            W.ops[spec.opId] = { opId = spec.opId, state = "committed" }
            return W.ops[spec.opId]
        end,
        pay = function(spec)
            if W.ops[spec.opId] then return W.ops[spec.opId] end
            if W.failNext and W.failNext.kind == "pay" then
                local f = W.failNext; W.failNext = nil
                return nil, f.reason, f.info
            end
            local from = acct(spec.from)
            local lines = spec.payees or { { subject = spec.to.subject, society = spec.to.society, wallet = spec.to.wallet, amount = spec.amount } }
            local sum = 0
            for _, l in ipairs(lines) do sum = sum + l.amount end
            if (W.bal[from] or 0) < sum then return nil, "insufficient_funds" end
            for _, l in ipairs(lines) do move(from, acct(l), l.amount) end
            W.ops[spec.opId] = { opId = spec.opId, state = "committed" }
            return W.ops[spec.opId]
        end,
        status = function(opId)
            if W.statusOf[opId] then return { state = W.statusOf[opId] } end
            if W.ops[opId] then return { state = "committed" } end
            return { state = "unknown" }
        end,
    }
    W.P = {
        now = function() return W.t end, bootId = function() return "B1" end,
        log = function() end,
        position = function(pid) return W.pos[pid] end,
        hasJob = function(pid, job) return W.jobs[pid] == job end,
        subject = function(pid) return ({ [1] = "cust", [2] = "barb", [3] = "barb2", [4] = "cust2" })[pid] end,
        name = function(pid) return "P" .. pid end,
        grade = function(pid) return W.grade[pid] or 0 end,
        employed = function() local o = {} for pid, j in pairs(W.jobs) do if j == C.job then o[#o + 1] = pid end end return o end,
        notify = function(pid, msg) W.notes[#W.notes + 1] = { pid, msg } end,
        ui = function(pid, view, data) W.ui[#W.ui + 1] = { pid = pid, view = view, data = data } end,
        toCustomer = function() end, toBartender = function() end,
        event = function(...) W.events[#W.events + 1] = { ... } end,
        handover = function() end,
        balances = function(pid) local s = W.P.subject(pid) return { cash = W.bal["sub:" .. s .. ":cash"] or 0, bank = W.bal["sub:" .. s .. ":bank"] or 0 } end,
        store = { save = function(t) W.saved[t.id] = { state = t.state } return true end },
        economy = W.economy,
    }
    return W
end

local function lastUi(W, pid, view)
    for i = #W.ui, 1, -1 do local u = W.ui[i] if u.pid == pid and u.view == view then return u.data end end
end

-- Seat customer 1, clock in bartender 2 at the station; answers W, svc.
local function setup()
    local W = world()
    local svc = S.new(C, M, W.P)
    W.pos[1] = { x = STATION.x + 1.0, y = STATION.y, z = STATION.z }   -- customer on a stool by the station
    W.pos[2] = { x = STATION.x, y = STATION.y, z = STATION.z }         -- bartender at the station
    W.jobs[2] = C.job
    svc:onSeated(1, "stool_1")
    assert(svc:clockIn(2))
    return W, svc
end

-- Menu -> order -> bill -> pay. Answers the ticket.
local function orderAndPay(W, svc, items, tip, method)
    assert(svc:lockOn(2, 1) == "menu")
    local menu = lastUi(W, 1, "menu")
    assert(svc:menuSubmit(1, menu.ticketId, items or { { drink = "johnny_silverhand", qty = 1 }, { drink = "broseph", qty = 1 } }))
    assert(svc:lockOn(2, 1) == "bill")
    local ok, why = svc:kioskPay(1, menu.ticketId, tip or 15, method or "cash")
    return svc.tickets[menu.ticketId] or { id = menu.ticketId }, ok, why
end

local PERFECT = {
    johnny_silverhand = { { id = "tequila", ml = 60 }, { id = "agave", ml = 10 }, { id = "bitters", count = 2 }, { id = "ice", count = 2 },
        { id = "stir", hits = { "perfect", "good", "perfect" } }, { id = "lime", ml = 15 }, { id = "cerveza", ml = 30 }, { id = "chili", count = 1 } },
    broseph = { { id = "lager", ml = 455 } },
    nicola = { { id = "ice", count = 3 }, { id = "nicola", ml = 140 } },
}

local function makeAll(W, svc, t)
    for i, q in ipairs(t.queue) do
        assert(svc:startPour(2, t.id, i))
        W.t = W.t + 20000
        local score, left = svc:pourSubmit(2, t.id, i - 1, PERFECT[q.drink])
        assert(score, left)
    end
end

local function conserved(name, W, start)
    check(name .. ": escrow empty", W.bal[ESCROW] == 0, W.bal[ESCROW])
    check(name .. ": money conserved", W.total() == start, W.total() - start)
end

-- ------------------------------------------------------------------ 1. happy path
do
    local W, svc = setup()
    local start = W.total()
    local t, ok = orderAndPay(W, svc)
    check("1 paid", ok == true and t.state == "paid")
    check("1 escrow holds total", W.bal[ESCROW] == t.split.total, W.bal[ESCROW])
    makeAll(W, svc, t)
    check("1 ready", t.state == "ready")
    check("1 serve", svc:lockOn(2, 1) == "served")
    check("1 settled", W.saved[t.id].state == "settled")
    -- 120 + 30 = 150, tip 15 % = 23 (22.5 rounded), total 173; till 60 % of 150 = 90; bartender 60 + 23 = 83
    check("1 customer paid total", W.bal["sub:cust:cash"] == 500 - 173, W.bal["sub:cust:cash"])
    check("1 till", W.bal[TILL] == 90, W.bal[TILL])
    check("1 bartender cut + tip", W.bal["sub:barb:cash"] == 83, W.bal["sub:barb:cash"])
    check("1 ticket gone", svc.tickets[t.id] == nil and svc.ticketOf[1] == nil)
    local served = 0
    for _, e in ipairs(W.events) do if e[1] == "o77_bar:served" then served = served + 1 end end
    check("1 served events per glass", served == 2, served)
    conserved("1", W, start)
end

-- ------------------------------------------------------------------ 2. customer stands up after paying
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    svc:onStood(1)
    check("2 refunded", W.saved[t.id].state == "refunded")
    check("2 customer whole", W.bal["sub:cust:cash"] == 500)
    conserved("2", W, start)
end

-- ------------------------------------------------------------------ 3. customer stands up while the charge is in flight
do
    local W, svc = setup()
    local start = W.total()
    W.duringCharge = function() svc:onStood(1) end
    local t, ok, why = orderAndPay(W, svc)
    check("3 pay reports refund", ok == true or why == "ticket_gone", why)
    check("3 refunded", W.saved[t.id] and W.saved[t.id].state == "refunded", W.saved[t.id] and W.saved[t.id].state)
    check("3 customer whole", W.bal["sub:cust:cash"] == 500, W.bal["sub:cust:cash"])
    conserved("3", W, start)
end

-- ------------------------------------------------------------------ 4. bartender walks out after payment
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    W.pos[2] = { x = STATION.x + 200, y = STATION.y, z = STATION.z }
    svc:tick()
    check("4 off shift", svc.shifts[2] == nil)
    check("4 refunded", W.saved[t.id].state == "refunded")
    conserved("4", W, start)
end

-- ------------------------------------------------------------------ 5. double tap on Pay
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    local ok, why = svc:kioskPay(1, t.id, 15, "cash")
    check("5 second tap refused", ok == nil and why == "ticket_gone", why)
    check("5 charged once", W.bal["sub:cust:cash"] == 500 - t.split.total)
    svc:onStood(1)
    conserved("5", W, start)
end

-- ------------------------------------------------------------------ 6. too-fast pours end the shift and refund
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc, { { drink = "johnny_silverhand", qty = 1 } })
    for strike = 1, C.pour.tooFastStrikes do
        if svc.shifts[2] then
            assert(svc:startPour(2, t.id, 1))
            W.t = W.t + 500
            local ok, why = svc:pourSubmit(2, t.id, 0, PERFECT.johnny_silverhand)
            check("6 too fast " .. strike, ok == nil and why == "too_fast", why)
        end
    end
    check("6 shift ended", svc.shifts[2] == nil)
    check("6 refunded", W.saved[t.id].state == "refunded")
    conserved("6", W, start)
end

-- ------------------------------------------------------------------ 7. payout fails once, retried, paid once
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    makeAll(W, svc, t)
    W.failNext = { kind = "pay", reason = "store_unavailable", info = { retryable = true } }
    check("7 serve", svc:lockOn(2, 1) == "served")
    check("7 still settling", t.state == "settling")
    W.t = W.t + C.retryMs + 1
    svc:tick()
    check("7 settled after retry", W.saved[t.id].state == "settled")
    W.t = W.t + C.retryMs + 1
    svc:tick()
    check("7 bartender paid once", W.bal["sub:barb:cash"] == t.split.bartender, W.bal["sub:barb:cash"])
    conserved("7", W, start)
end

-- ------------------------------------------------------------------ 8. fenced payout id: new id, paid once
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    makeAll(W, svc, t)
    local firstOp = M.settleOp(t)
    W.failNext = { kind = "pay", reason = "store_unavailable", info = { state = "aborted" } }
    svc:lockOn(2, 1)
    check("8 attempt bumped", t.attempt == 2 and M.settleOp(t) ~= firstOp)
    W.t = W.t + C.retryMs + 1
    svc:tick()
    check("8 settled", W.saved[t.id].state == "settled")
    conserved("8", W, start)
end

-- ------------------------------------------------------------------ 9. charge in doubt, then committed
do
    local W, svc = setup()
    local start = W.total()
    W.failNext = { kind = "charge", reason = "in_doubt_committed" }
    local t, ok, why = orderAndPay(W, svc)
    check("9 in doubt", ok == nil and why == "in_doubt" and t.state == "paying", why)
    W.t = W.t + C.retryMs + 1
    svc:tick()
    check("9 resolved to paid", t.state == "paid", t.state)
    svc:onStood(1)
    conserved("9", W, start)
end

-- ------------------------------------------------------------------ 10. charge in doubt, customer leaves, then committed
do
    local W, svc = setup()
    local start = W.total()
    W.failNext = { kind = "charge", reason = "in_doubt_committed" }
    local t = orderAndPay(W, svc)
    svc:onStood(1)
    check("10 marked abandoning", t.state == "abandoning")
    W.t = W.t + C.retryMs + 1
    svc:tick()
    check("10 refunded", W.saved[t.id].state == "refunded", W.saved[t.id].state)
    conserved("10", W, start)
end

-- ------------------------------------------------------------------ 11. charge refused: back to the bill, nothing moved
do
    local W, svc = setup()
    local start = W.total()
    local t, ok, why = orderAndPay(W, svc, { { drink = "johnny_silverhand", qty = 4 } }, 20, "cash")  -- 576 > 500 cash
    check("11 refused", ok == nil and why == "insufficient_funds", why)
    check("11 back to billed", t.state == "billed")
    local ok2 = svc:kioskPay(1, t.id, 20, "bank")
    check("11 bank works", ok2 == true and t.state == "paid")
    svc:onStood(1)
    conserved("11", W, start)
end

-- ------------------------------------------------------------------ 12. restart: paid ticket is refunded on boot
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    local row = {}
    for k, v in pairs(t) do row[k] = v end
    local svc2 = S.new(C, M, W.P)   -- the server came back: nobody seated, nobody on shift
    svc2:recover({ row })
    check("12 refunded on boot", W.saved[t.id].state == "refunded")
    conserved("12", W, start)
end

-- ------------------------------------------------------------------ 13. restart mid-settle: paid out, not refunded
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    makeAll(W, svc, t)
    W.failNext = { kind = "pay", reason = "store_unavailable", info = { retryable = true } }
    svc:lockOn(2, 1)
    local row = {}
    for k, v in pairs(t) do row[k] = v end
    local svc2 = S.new(C, M, W.P)
    svc2:recover({ row })
    check("13 settled on boot", W.saved[t.id].state == "settled")
    check("13 bartender paid", W.bal["sub:barb:cash"] == t.split.bartender)
    conserved("13", W, start)
end

-- ------------------------------------------------------------------ 14. guards
do
    local W, svc = setup()
    W.jobs[3] = C.job
    W.pos[3] = { x = STATION.x, y = STATION.y + 0.5, z = STATION.z }
    assert(svc:clockIn(3))
    local t = orderAndPay(W, svc)
    check("14 other bartender refused", select(2, svc:lockOn(3, 1)) == "another_bartender")
    check("14 bad tip", select(2, svc:kioskPay(1, t.id, 7, "cash")) == "ticket_gone")
    check("14 self service", select(2, svc:lockOn(2, 2)) == "not_seated_here")
    check("14 not a bartender", select(2, svc:clockIn(4)) == "not_a_bartender")
    check("14 wrong item submit", select(2, svc:pourSubmit(2, t.id, 0, PERFECT.broseph)) == "not_pouring")
    assert(svc:startPour(2, t.id, 1))
    check("14 station busy", select(2, svc:startPour(3, t.id, 2)) == "ticket_gone")
    W.t = W.t + 20000
    check("14 wrong steps", select(2, svc:pourSubmit(2, t.id, 0, PERFECT.broseph)) == "steps_mismatch")
    check("14 cannot cancel after pay", select(2, svc:kioskCancel(1, t.id)) == "already_paid")
    svc:onStood(1)
end

-- ------------------------------------------------------------------ 15. serve timeout refunds
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    W.t = W.t + C.limits.serveTimeoutMs + 1
    svc:tick()
    check("15 refunded", W.saved[t.id].state == "refunded")
    conserved("15", W, start)
end

-- ------------------------------------------------------------------ 16. tab closed before paying: nothing moves
do
    local W, svc = setup()
    local start = W.total()
    assert(svc:lockOn(2, 1) == "menu")
    local id = lastUi(W, 1, "menu").ticketId
    assert(svc:menuSubmit(1, id, { { drink = "broseph", qty = 1 } }))
    assert(svc:lockOn(2, 1) == "bill")
    check("16 cancel", svc:kioskCancel(1, id) == true)
    check("16 next customer can order", svc:lockOn(2, 1) == "menu")
    conserved("16", W, start)
end

-- ------------------------------------------------------------------ 17. refund retried until it lands
do
    local W, svc = setup()
    local start = W.total()
    local t = orderAndPay(W, svc)
    W.failNext = { kind = "pay", reason = "store_unavailable", info = { retryable = true } }
    svc:onStood(1)
    check("17 refunding", t.state == "refunding")
    W.t = W.t + C.retryMs + 1
    svc:tick()
    check("17 refunded", W.saved[t.id].state == "refunded")
    conserved("17", W, start)
end

-- ------------------------------------------------------------------ 18. difficulty follows the title
do
    local W, svc = setup()
    W.grade[2] = 3
    local t = orderAndPay(W, svc, { { drink = "johnny_silverhand", qty = 1 } })
    assert(svc:startPour(2, t.id, 1))
    check("18 boss beat", lastUi(W, 2, "pour").beat == C.shakeByGrade[3])
    svc:onStood(1)
end

print(("service: %d checks, %d failed"):format(runs, fails))
os.exit(fails == 0 and 0 or 1)
