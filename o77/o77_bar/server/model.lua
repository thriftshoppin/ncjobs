-- o77_bar model: pure functions. No Open77 calls, no clock, no I/O: everything here runs in a
-- plain Lua 5.4 VM (tests/model_test.lua).
local M = {}

local function int(v) return math.tointeger(tonumber(v)) end
M.int = int

-- ---------------------------------------------------------------------------------------------
-- Ticket states
--   ordering   menu handed, waiting for the customer to pick       (no money)
--   ordered    customer picked, waiting for the bartender's bill   (no money)
--   billed     kiosk open on the customer                          (no money)
--   paying     escrow charge in flight                             (money may be moving)
--   paid       escrow holds total; drinks being made               (money held)
--   ready      every drink made, waiting for the hand-over         (money held)
--   settling   payout from escrow in flight / retried              (money held until done)
--   refunding  refund from escrow in flight / retried              (money held until done)
--   settled | refunded | cancelled                                 (final)
-- ---------------------------------------------------------------------------------------------
M.HOLDS_MONEY = { paying = true, paid = true, ready = true, settling = true, refunding = true }
M.FINAL = { settled = true, refunded = true, cancelled = true }
M.PRE_PAY = { ordering = true, ordered = true, billed = true }

function M.payOp(t) return ("o77bar:%s:pay"):format(t.id) end
function M.settleOp(t) return ("o77bar:%s:settle:%d"):format(t.id, t.attempt or 1) end
function M.refundOp(t) return ("o77bar:%s:refund:%d"):format(t.id, t.attempt or 1) end

-- ---------------------------------------------------------------------------------------------
-- Orders and money
-- ---------------------------------------------------------------------------------------------

-- items: { { drink = id, qty = n }, ... } from the client. Answers the cleaned list and the
-- subtotal, or nil, reason. Duplicates merge; unknown drinks or ones not on this bar's menu
-- are refused rather than dropped, so the customer never pays for less than they picked.
function M.priceOrder(cfg, bar, items)
    if type(items) ~= "table" then return nil, "invalid_order" end
    local onMenu = {}
    for _, id in ipairs(bar.menu or {}) do onMenu[id] = true end
    local qtyOf, order = {}, {}
    for _, it in ipairs(items) do
        if type(it) ~= "table" then return nil, "invalid_order" end
        local id, qty = it.drink, int(it.qty)
        if type(id) ~= "string" or not onMenu[id] or not cfg.drinks[id] then return nil, "not_on_menu" end
        if not qty or qty < 1 then return nil, "invalid_quantity" end
        if not qtyOf[id] then order[#order + 1] = id end
        qtyOf[id] = (qtyOf[id] or 0) + qty
    end
    if #order == 0 then return nil, "empty_order" end
    local lines, subtotal, count = {}, 0, 0
    for _, id in ipairs(order) do
        local qty = qtyOf[id]
        if qty > cfg.limits.maxQtyPerDrink then return nil, "too_many_of_one" end
        count = count + qty
        local price = int(cfg.drinks[id].price) or 0
        lines[#lines + 1] = { drink = id, qty = qty, price = price }
        subtotal = subtotal + price * qty
    end
    if count > cfg.limits.maxItems then return nil, "too_many_items" end
    return lines, subtotal
end

function M.tipFor(cfg, subtotal, tipPct)
    local pct = int(tipPct)
    local allowed = false
    for _, p in ipairs(cfg.tips) do if p == pct then allowed = true end end
    if not allowed then return nil, "invalid_tip" end
    return (subtotal * pct + 50) // 100   -- rounded to the nearest eddy
end

-- The till gets floor(subtotal * tillShare); the bartender gets the rest of the subtotal and the
-- whole tip. Parts always sum to the total.
function M.split(cfg, subtotal, tip)
    local till = math.floor(subtotal * (cfg.split.tillShare or 0.6))
    if till < 0 then till = 0 end
    if till > subtotal then till = subtotal end
    return { till = till, bartender = subtotal - till + tip, total = subtotal + tip }
end

-- One entry per glass to make, in ticket order: { drink, n } with n the copy number.
function M.queue(lines)
    local q = {}
    for _, l in ipairs(lines) do
        for n = 1, l.qty do q[#q + 1] = { drink = l.drink, n = n } end
    end
    return q
end

-- ---------------------------------------------------------------------------------------------
-- Pour checks
-- ---------------------------------------------------------------------------------------------

function M.beatFor(cfg, grade)
    local g = int(grade) or 0
    if g < 0 then g = 0 end
    while g > 0 and not cfg.shakeByGrade[g] do g = g - 1 end
    return cfg.shakeByGrade[g] or cfg.shakeByGrade[0]
end

-- The least time a person could take to make this drink, in seconds.
function M.minSeconds(cfg, drink)
    local p, total = cfg.pour, 0
    for _, s in ipairs(drink.steps) do
        if s.type == "pour" then total = total + s.ml / (s.rate or p.rateMlPerSec)
        elseif s.type == "count" then total = total + s.count * p.minSecondsPerIce
        elseif s.type == "beat" then total = total + s.beats * p.minSecondsPerBeat
        end
    end
    return total * (p.speedSlack or 0.8)
end

-- Re-scores what the page sent. `submitted` must have one entry per recipe step, same ids, in
-- order. Pour amounts are clamped to the glass; counts must be exact; beat grades are taken as
-- reported (they decide quality only, never money). Answers score 0..100 or nil, reason.
local BEAT_POINTS = { perfect = 100, good = 70, off = 20 }
function M.scorePour(cfg, drink, submitted)
    if type(submitted) ~= "table" then return nil, "invalid_pour" end
    local steps = drink.steps
    if #submitted ~= #steps then return nil, "steps_mismatch" end
    local cap = (cfg.glasses[drink.glass] or {}).capacityMl or 300
    local sum = 0
    for i, s in ipairs(steps) do
        local got = submitted[i]
        if type(got) ~= "table" or got.id ~= s.id then return nil, "steps_mismatch" end
        local score
        if s.type == "pour" then
            local ml = tonumber(got.ml)
            if not ml or ml ~= ml or ml < 0 then return nil, "invalid_pour" end
            if ml > cap then ml = cap end
            -- tolerance is in time: a tap that pours 3x faster allows 3x the millilitres
            local scale = (s.rate or cfg.pour.rateMlPerSec) / cfg.pour.rateMlPerSec
            score = math.max(0, 100 - math.abs(ml - s.ml) / scale * 4)
        elseif s.type == "count" then
            if int(got.count) ~= s.count then return nil, "invalid_pour" end
            score = 100
        elseif s.type == "beat" then
            local hits = got.hits
            if type(hits) ~= "table" or #hits ~= s.beats then return nil, "invalid_pour" end
            local pts = 0
            for _, h in ipairs(hits) do
                if not BEAT_POINTS[h] then return nil, "invalid_pour" end
                pts = pts + BEAT_POINTS[h]
            end
            score = pts / s.beats
        else
            return nil, "unknown_step"
        end
        sum = sum + score
    end
    return math.floor(sum / #steps + 0.5)
end

-- What the pour page needs for one glass (no prices, nothing the client could act on).
function M.pourOrder(cfg, t, index, grade)
    local entry = t.queue[index]
    local drink = cfg.drinks[entry.drink]
    local glass = cfg.glasses[drink.glass] or {}
    return {
        ticketId = t.id, item = index - 1, of = #t.queue, stool = t.stool, customer = t.customer.name,
        label = drink.label, steps = drink.steps,
        glass = { label = glass.label, capacityMl = glass.capacityMl, top = glass.top, bottom = glass.bottom, height = glass.height },
        beat = M.beatFor(cfg, grade),
    }
end

return M
