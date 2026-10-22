-- o77_bar model: pure functions. No Open77 calls, no clock, no I/O: everything here runs in a
-- plain Lua 5.4 VM (tests/model_test.lua).
local M = {}

local function int(v) return math.tointeger(tonumber(v)) end
M.int = int

-- ---------------------------------------------------------------------------------------------
-- Rounds and tabs
--   A ROUND is one order: ordering -> making -> ready -> served (or cancelled). No money moves.
--   A TAB is what a customer owes at one bar: every served round adds its lines.
--     open -> closing (kiosk charge in flight) -> settled
--     open -> walking (walkout charge in flight) -> settled
--     open -> leaving (disconnect / restart charge, no fee) -> settled
--   A tab is saved whenever it changes, so a restart never forgets what is owed.
-- ---------------------------------------------------------------------------------------------
M.ROUND_LIVE = { ordering = true, making = true, ready = true }

function M.closeOp(tab) return ("o77bar:%s:close:%d"):format(tab.id, tab.attempt or 1) end
function M.walkOp(tab) return ("o77bar:%s:walkout:%d"):format(tab.id, tab.attempt or 1) end
function M.leaveOp(tab) return ("o77bar:%s:leave:%d"):format(tab.id, tab.attempt or 1) end

-- ---------------------------------------------------------------------------------------------
-- Orders and money
-- ---------------------------------------------------------------------------------------------

-- The bottle ids a bar sells, in config order (sorted by kind, tier price, label).
function M.barBottles(cfg, bar)
    local rule, out = bar.bottles, {}
    if not rule or not cfg.bottles then return out end
    local skipTier = {}
    for _, t in ipairs(type(rule) == "table" and rule.exceptTiers or {}) do skipTier[t] = true end
    if type(rule) == "table" and rule[1] then
        for _, id in ipairs(rule) do if cfg.bottles[id] then out[#out + 1] = id end end
        return out
    end
    for id, b in pairs(cfg.bottles) do
        if not skipTier[b.tier] then out[#out + 1] = id end
    end
    table.sort(out, function(a, b)
        local x, y = cfg.bottles[a], cfg.bottles[b]
        if x.kind ~= y.kind then return x.kind == "alcohol" end
        if x.price ~= y.price then return x.price < y.price end
        return x.label < y.label
    end)
    return out
end

-- items: { { drink = id, qty = n }, ... } from the client. Answers the cleaned list and the
-- subtotal, or nil, reason. Duplicates merge; unknown drinks or ones not on this bar's menu
-- are refused rather than dropped, so the customer never pays for less than they picked.
function M.priceOrder(cfg, bar, items)
    if type(items) ~= "table" then return nil, "invalid_order" end
    local onMenu = {}
    for _, id in ipairs(bar.menu or {}) do onMenu[id] = "mixed" end
    for _, id in ipairs(M.barBottles(cfg, bar)) do onMenu[id] = "bottle" end
    local qtyOf, order = {}, {}
    for _, it in ipairs(items) do
        if type(it) ~= "table" then return nil, "invalid_order" end
        local id, qty = it.drink, int(it.qty)
        if type(id) ~= "string" or not onMenu[id] then return nil, "not_on_menu" end
        if not qty or qty < 1 then return nil, "invalid_quantity" end
        if not qtyOf[id] then order[#order + 1] = id end
        qtyOf[id] = (qtyOf[id] or 0) + qty
    end
    if #order == 0 then return nil, "empty_order" end
    local lines, subtotal, count = {}, 0, 0
    for _, id in ipairs(order) do
        local qty = qtyOf[id]
        local kind = onMenu[id]
        local bulk = kind == "bottle" and qty >= cfg.limits.bulkFrom
        if kind == "mixed" and qty > cfg.limits.maxQtyPerDrink then return nil, "too_many_of_one" end
        if kind == "bottle" and qty > cfg.limits.maxBulk then return nil, "too_many_of_one" end
        if not bulk then count = count + qty end     -- a bulk buy goes in the bag, not on the counter
        local def = kind == "mixed" and cfg.drinks[id] or cfg.bottles[id]
        local price = int(def.price) or 0
        lines[#lines + 1] = { drink = id, qty = qty, price = price, kind = kind, item = def.item, bulk = bulk or nil }
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

-- What a tab owes: the sum of its served lines.
function M.owed(tab)
    local n = 0
    for _, l in ipairs(tab.served or {}) do n = n + l.price * l.qty end
    return n
end

-- The walkout fee for a tab, from the bar's setting { mode = "percent"|"flat", value, min }.
function M.walkoutFee(setting, owed)
    if owed <= 0 then return 0 end
    local fee
    if setting.mode == "flat" then fee = setting.value
    else fee = (owed * setting.value + 50) // 100 end
    if setting.min and fee < setting.min then fee = setting.min end
    return math.max(0, math.floor(fee))
end

-- Splits `n` into integer parts proportional to `weights` (largest remainder); parts sum to n.
local function apportion(n, weights)
    local total, parts, rems = 0, {}, {}
    for i, w in ipairs(weights) do total = total + w end
    if total <= 0 then
        for i in ipairs(weights) do parts[i] = 0 end
        if #weights > 0 then parts[1] = n end
        return parts
    end
    local given = 0
    for i, w in ipairs(weights) do
        local exact = n * w / total
        parts[i] = math.floor(exact)
        rems[#rems + 1] = { i = i, r = exact - parts[i] }
        given = given + parts[i]
    end
    table.sort(rems, function(a, b) if a.r ~= b.r then return a.r > b.r end return a.i < b.i end)
    for k = 1, n - given do parts[rems[k].i] = parts[rems[k].i] + 1 end
    return parts
end
M.apportion = apportion

-- Who gets what when a tab is paid. The till takes floor(subtotal * tillShare) plus any fee;
-- each bartender gets the rest of the subtotal in proportion to what they served, and the tip
-- in the same proportion. Answers { payees = { {society=..|subject=.., amount} }, total }, parts
-- always summing to total.
function M.tabSplit(cfg, bar, tab, tip, fee)
    local subtotal = M.owed(tab)
    local till = math.floor(subtotal * (cfg.split.tillShare or 0.6))
    local order, by = {}, {}
    for _, l in ipairs(tab.served or {}) do
        local who = l.bartender
        if not by[who] then by[who] = 0; order[#order + 1] = who end
        by[who] = by[who] + l.price * l.qty
    end
    local weights = {}
    for i, who in ipairs(order) do weights[i] = by[who] end
    local cuts = apportion(subtotal - till, weights)
    local tips = apportion(tip or 0, weights)
    local payees = {}
    if till + (fee or 0) > 0 then payees[#payees + 1] = { society = bar.society, amount = till + (fee or 0) } end
    for i, who in ipairs(order) do
        local amount = cuts[i] + tips[i]
        if amount > 0 then payees[#payees + 1] = { subject = who, amount = amount } end
    end
    return { payees = payees, total = subtotal + (tip or 0) + (fee or 0), till = till, fee = fee or 0, tip = tip or 0 }
end

-- Scales a split down to what the customer actually has, paying bartenders first, then the till's
-- share, then the fee. Answers the reduced payees and the amount left unpaid (debt).
function M.partial(split, available)
    local left, payees = math.max(0, available), {}
    local order = {}
    for _, p in ipairs(split.payees) do if p.subject then order[#order + 1] = p end end
    for _, p in ipairs(split.payees) do if p.society then order[#order + 1] = p end end
    for _, p in ipairs(order) do
        local amount = math.min(left, p.amount)
        if amount > 0 then payees[#payees + 1] = { subject = p.subject, society = p.society, amount = amount } end
        left = left - amount
    end
    local paid = 0
    for _, p in ipairs(payees) do paid = paid + p.amount end
    return payees, split.total - paid, paid
end

-- The bartender's tasks for a round, in order:
--   { kind = "pour", drink, n }          one glass per cocktail, poured at a station
--   { kind = "grab", drink, qty, bulk }  one trip to the cooler per bottle line
function M.queue(lines)
    local q = {}
    for _, l in ipairs(lines) do
        if l.kind == "bottle" then
            q[#q + 1] = { kind = "grab", drink = l.drink, qty = l.qty, bulk = l.bulk }
        else
            for n = 1, l.qty do q[#q + 1] = { kind = "pour", drink = l.drink, n = n } end
        end
    end
    return q
end

function M.grabSeconds(cfg, entry)
    local g = cfg.limits.grabSeconds
    return math.min(g.max, g.base + g.perUnit * (entry.qty or 1))
end

-- What the customer gets at serve. `open`: single bottles/cans served in hand (their in-game look),
-- `bulk`: sealed into the inventory. Each { item, qty, label }.
function M.bottlesOf(cfg, lines)
    local open, bulk = {}, {}
    for _, l in ipairs(lines) do
        if l.kind == "bottle" then
            local e = { item = l.item, qty = l.qty, label = cfg.bottles[l.drink].label, drink = l.drink }
            if l.bulk then bulk[#bulk + 1] = e else open[#open + 1] = e end
        end
    end
    return open, bulk
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
    local entry = t.queue[index]   -- t is a round
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
