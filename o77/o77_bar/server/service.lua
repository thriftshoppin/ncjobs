-- o77_bar service: tickets, shifts and seats. Every outside call goes through `P` (ports), so
-- the whole flow runs under tests/service_test.lua with fakes. Methods that touch the economy or
-- the store may yield; the caller runs them in a thread.
local S = {}
S.__index = S

-- ports: see server/ports.lua for the real ones and tests/service_test.lua for the fakes.
function S.new(cfg, M, P)
    local self = setmetatable({}, S)
    self.cfg, self.M, self.P = cfg, M, P
    self.tickets = {}        -- id -> ticket
    self.ticketOf = {}       -- customer pid -> ticket id (one live ticket per customer)
    self.seats = {}          -- customer pid -> { bar, stool, position }
    self.shifts = {}         -- bartender pid -> { bar, strikes, pouring = { ticket, index, startedAt } | nil }
    self.stationUser = {}    -- "bar:index" -> bartender pid
    self.lastRing = {}       -- customer pid -> ms
    self.nextTry = {}        -- ticket id -> ms (settle / refund retries)
    self.seq = 0
    self.bootId = tostring(P.bootId())
    return self
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function S:log(fmt, ...) self.P.log(fmt:format(...)) end

function S:barAt(position)
    if not position then return nil end
    for id, bar in pairs(self.cfg.bars) do
        if dist(position, bar.zone.position) <= bar.zone.radius then return id, bar end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Persistence: a ticket is written whenever it holds money, and marked final once it stops.
-- ---------------------------------------------------------------------------------------------
function S:save(t)
    if self.M.HOLDS_MONEY[t.state] or self.M.FINAL[t.state] then
        local ok, why = self.P.store.save(t)
        if not ok then self:log("ticket %s not saved (%s)", t.id, tostring(why)) end
    end
end

function S:setState(t, state)
    t.state = state
    t.updatedAt = self.P.now()
    self:save(t)
    if self.M.FINAL[state] then
        if self.ticketOf[t.customer.pid] == t.id then self.ticketOf[t.customer.pid] = nil end
        self.tickets[t.id] = nil
        self.nextTry[t.id] = nil
        for key, pid in pairs(self.stationUser) do
            local sh = self.shifts[pid]
            if sh and sh.pouring and sh.pouring.ticket == t.id then
                sh.pouring = nil
                self.stationUser[key] = nil
                self.P.ui(pid, "close")
            end
        end
    end
    self.P.event("o77_bar:ticket", t.id, state, t.customer.pid, t.bartender and t.bartender.pid)
end

-- ---------------------------------------------------------------------------------------------
-- Shifts. Clocking in is free and only works at a station; leaving the zone ends the shift.
-- ---------------------------------------------------------------------------------------------
function S:stationNear(pid)
    local pos = self.P.position(pid)
    if not pos then return nil, "position_unavailable" end
    for barId, bar in pairs(self.cfg.bars) do
        for i, st in ipairs(bar.stations) do
            if dist(pos, st.position) <= self.cfg.limits.stationReach then return barId, i end
        end
    end
    return nil, "not_at_station"
end

function S:clockIn(pid)
    if self.shifts[pid] then return nil, "already_on_shift" end
    if not self.P.hasJob(pid, self.cfg.job) then return nil, "not_a_bartender" end
    local barId, why = self:stationNear(pid)
    if not barId then return nil, why end
    self.shifts[pid] = { bar = barId, strikes = 0, since = self.P.now() }
    self:log("player %d clocked in at %s", pid, barId)
    self:pushStools(barId)
    return barId
end

-- Ends a shift. Every ticket this bartender holds is refunded or cancelled: a customer is never
-- left paid with nobody to serve them.
function S:clockOut(pid, reason)
    local sh = self.shifts[pid]
    if not sh then return nil, "not_on_shift" end
    for _, t in pairs(self:ticketsOfBartender(pid)) do self:abandon(t, "bartender_" .. reason) end
    for key, user in pairs(self.stationUser) do if user == pid then self.stationUser[key] = nil end end
    self.shifts[pid] = nil
    self.P.ui(pid, "close")
    self.P.toBartender(pid, "shift", { onShift = false })
    self:log("player %d clocked out of %s (%s)", pid, sh.bar, reason)
    return true
end

function S:ticketsOfBartender(pid)
    local out = {}
    for id, t in pairs(self.tickets) do
        if t.bartender and t.bartender.pid == pid then out[id] = t end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Seats
-- ---------------------------------------------------------------------------------------------
function S:onSeated(pid, furnitureId)
    local pos = self.P.position(pid)
    local barId, bar = self:barAt(pos)
    if not barId then return end
    if #bar.stools > 0 then
        local listed = false
        for _, id in ipairs(bar.stools) do if id == furnitureId then listed = true end end
        if not listed then return end
    end
    self.seats[pid] = { bar = barId, stool = tostring(furnitureId), position = pos }
    self:pushStools(barId)
    local staff = self:onShiftAt(barId)
    if #staff == 0 then
        self.P.toCustomer(pid, "seated", { bar = bar.label, staffed = false })
    else
        self.P.toCustomer(pid, "seated", { bar = bar.label, staffed = true })
        for _, b in ipairs(staff) do self.P.notify(b, "New customer at the bar.") end
    end
end

function S:onStood(pid)
    local seat = self.seats[pid]
    if not seat then return end
    self.seats[pid] = nil
    local t = self:ticketOfCustomer(pid)
    if t then self:abandon(t, "customer_left") end
    self.P.toCustomer(pid, "stood", {})
    self:pushStools(seat.bar)
end

function S:onShiftAt(barId)
    local out = {}
    for pid, sh in pairs(self.shifts) do if sh.bar == barId then out[#out + 1] = pid end end
    table.sort(out)
    return out
end

-- What on-shift bartenders draw over each seated customer: who, where, and the next step.
local NEXT = {
    none = "Hand the menu", ordering = "Ordering...", ordered = "Send the bill", billed = "Paying...",
    paying = "Paying...", paid = "Make it at the station", ready = "Serve", settling = "Serving...",
    refunding = "Refunding...",
}
function S:pushStools(barId)
    local list = {}
    for pid, seat in pairs(self.seats) do
        if seat.bar == barId then
            local t = self:ticketOfCustomer(pid)
            local state = t and t.state or "none"
            list[#list + 1] = {
                customer = pid, name = self.P.name(pid), position = seat.position, state = state,
                next = NEXT[state] or state, mine = t and t.bartender and t.bartender.pid or nil,
            }
        end
    end
    for _, b in ipairs(self:onShiftAt(barId)) do self.P.toBartender(b, "stools", { bar = barId, stools = list, onShift = true }) end
end

function S:ticketOfCustomer(pid)
    local id = self.ticketOf[pid]
    return id and self.tickets[id] or nil
end

function S:ring(pid)
    local seat = self.seats[pid]
    if not seat then return nil, "not_seated" end
    local now = self.P.now()
    if self.lastRing[pid] and now - self.lastRing[pid] < self.cfg.limits.ringCooldownMs then return nil, "ring_cooldown" end
    self.lastRing[pid] = now
    local bar = self.cfg.bars[seat.bar]
    local n = 0
    for _, b in ipairs(self.P.employed(self.cfg.job)) do
        if b ~= pid then
            local where = self.P.position(b)
            local d = where and math.floor(dist(where, bar.zone.position)) or nil
            self.P.notify(b, ("%s is waiting at the %s bar%s."):format(self.P.name(pid), bar.label,
                d and (" (" .. d .. " m away)") or ""))
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------------------------------------
-- The bartender locks on a seated customer and presses E: the next step happens.
-- ---------------------------------------------------------------------------------------------
function S:within(a, b, reach)
    local pa, pb = self.P.position(a), self.P.position(b)
    if not pa or not pb then return false end
    return dist(pa, pb) <= reach
end

function S:lockOn(bartender, customer)
    local sh = self.shifts[bartender]
    if not sh then return nil, "not_on_shift" end
    local seat = self.seats[customer]
    if not seat or seat.bar ~= sh.bar then return nil, "not_seated_here" end
    if bartender == customer then return nil, "self_service" end
    if not self:within(bartender, customer, self.cfg.limits.lockReach) then return nil, "too_far" end
    local t = self:ticketOfCustomer(customer)
    if t and t.bartender.pid ~= bartender then return nil, "another_bartender" end
    if not t then return self:handMenu(bartender, customer, seat) end
    if t.state == "ordered" then return self:sendBill(t) end
    if t.state == "ready" then return self:serve(t) end
    return nil, "wait_" .. t.state
end

function S:handMenu(bartender, customer, seat)
    self.seq = self.seq + 1
    local now = self.P.now()
    local t = {
        id = ("%s-%d"):format(self.bootId, self.seq), bar = seat.bar, stool = seat.stool,
        customer = { pid = customer, subject = self.P.subject(customer), name = self.P.name(customer) },
        bartender = { pid = bartender, subject = self.P.subject(bartender), name = self.P.name(bartender) },
        state = "ordering", createdAt = now, updatedAt = now, attempt = 1,
    }
    if not t.customer.subject or not t.bartender.subject then return nil, "subject_unavailable" end
    self.tickets[t.id] = t
    self.ticketOf[customer] = t.id
    local bar = self.cfg.bars[seat.bar]
    local menu = {}
    for _, id in ipairs(bar.menu) do
        local d = self.cfg.drinks[id]
        menu[#menu + 1] = { drink = id, label = d.label, price = d.price, flavour = d.flavour, glass = d.glass }
    end
    self.P.ui(customer, "menu", { ticketId = t.id, bar = bar.label, bartender = t.bartender.name,
        menu = menu, maxItems = self.cfg.limits.maxItems, maxQty = self.cfg.limits.maxQtyPerDrink })
    self:pushStools(seat.bar)
    return "menu"
end

function S:menuSubmit(customer, ticketId, items)
    local t = self.tickets[ticketId]
    if not t or t.customer.pid ~= customer or t.state ~= "ordering" then return nil, "ticket_gone" end
    local lines, subtotal = self.M.priceOrder(self.cfg, self.cfg.bars[t.bar], items)
    if not lines then return nil, subtotal end
    t.lines, t.subtotal, t.queue = lines, subtotal, self.M.queue(lines)
    self:setState(t, "ordered")
    self.P.notify(t.bartender.pid, ("%s ordered %d drink(s). Send the bill."):format(t.customer.name, #t.queue))
    self:pushStools(t.bar)
    return true
end

function S:sendBill(t)
    local balances = self.P.balances(t.customer.pid)
    if not balances then return nil, "wallet_unavailable" end
    self:setState(t, "billed")
    local items = {}
    for _, l in ipairs(t.lines) do
        local d = self.cfg.drinks[l.drink]
        items[#items + 1] = { label = d.label, qty = l.qty, price = l.price, flavour = d.flavour }
    end
    self.P.ui(t.customer.pid, "kiosk", { id = t.id, bar = self.cfg.bars[t.bar].label, stool = t.stool,
        bartender = t.bartender.name, defaultTip = self.cfg.defaultTip, tips = self.cfg.tips,
        balances = balances, items = items })
    self:pushStools(t.bar)
    return "bill"
end

-- Customer taps Pay. The whole total moves into escrow in one operation whose id is derived from
-- the ticket, so a double tap or a retry never charges twice.
function S:kioskPay(customer, ticketId, tipPct, method)
    local t = self.tickets[ticketId]
    if not t or t.customer.pid ~= customer or t.state ~= "billed" then return nil, "ticket_gone" end
    if method ~= "cash" and method ~= "bank" then return nil, "invalid_method" end
    local tip, why = self.M.tipFor(self.cfg, t.subtotal, tipPct)
    if not tip then return nil, why end
    t.tip, t.method = tip, method
    t.split = self.M.split(self.cfg, t.subtotal, tip)
    self:setState(t, "paying")
    local receipt, reason = self.P.economy.charge({
        opId = self.M.payOp(t), from = { subject = t.customer.subject, wallet = method },
        amount = t.split.total, instrument = method, to = { society = self.cfg.escrowSociety },
    })
    if t.state ~= "paying" then
        -- abandoned while the charge was in flight: abandon() left it to us
        if receipt then return self:startRefund(t) end
        return nil, "ticket_gone"
    end
    if receipt then
        t.paidAt = self.P.now()
        self:setState(t, "paid")
        self.P.notify(t.bartender.pid, ("%s paid %d. Make the drinks at the station."):format(t.customer.name, t.split.total))
        self:pushStools(t.bar)
        return true
    end
    if reason == "in_doubt" then
        -- the money may or may not have moved: tick() asks status() until it knows
        self.nextTry[t.id] = self.P.now() + self.cfg.retryMs
        return nil, "in_doubt"
    end
    self:setState(t, "billed")
    return nil, reason
end

function S:kioskCancel(customer, ticketId)
    local t = self.tickets[ticketId]
    if not t or t.customer.pid ~= customer then return nil, "ticket_gone" end
    if not self.M.PRE_PAY[t.state] then return nil, "already_paid" end
    self:setState(t, "cancelled")
    self.P.notify(t.bartender.pid, t.customer.name .. " closed the tab.")
    self:pushStools(t.bar)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- The station: pick a paid glass, pour it, submit.
-- ---------------------------------------------------------------------------------------------
function S:stationQueue(bartender)
    local sh = self.shifts[bartender]
    if not sh then return nil, "not_on_shift" end
    local out = {}
    for _, t in pairs(self:ticketsOfBartender(bartender)) do
        if t.state == "paid" then
            for i, q in ipairs(t.queue) do
                if not q.made then
                    out[#out + 1] = { ticketId = t.id, item = i, customer = t.customer.name,
                        label = self.cfg.drinks[q.drink].label, stool = t.stool, paidAt = t.paidAt }
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.paidAt ~= b.paidAt then return a.paidAt < b.paidAt end return a.item < b.item end)
    return out
end

function S:startPour(bartender, ticketId, index)
    local sh = self.shifts[bartender]
    if not sh then return nil, "not_on_shift" end
    local t = self.tickets[ticketId]
    if not t or t.bartender.pid ~= bartender or t.state ~= "paid" then return nil, "ticket_gone" end
    local entry = t.queue[index]
    if not entry or entry.made then return nil, "already_made" end
    local barId, stationIdx = self:stationNear(bartender)
    if barId ~= sh.bar then return nil, "not_at_station" end
    local key = barId .. ":" .. stationIdx
    local user = self.stationUser[key]
    if user and user ~= bartender then return nil, "station_busy" end
    self.stationUser[key] = bartender
    sh.pouring = { ticket = t.id, index = index, startedAt = self.P.now(), station = key }
    self.P.ui(bartender, "pour", self.M.pourOrder(self.cfg, t, index, self.P.grade(bartender)))
    return true
end

function S:releaseStation(sh)
    if sh.pouring and sh.pouring.station then self.stationUser[sh.pouring.station] = nil end
    sh.pouring = nil
end

function S:pourSubmit(bartender, ticketId, item, steps)
    local sh = self.shifts[bartender]
    if not sh or not sh.pouring then return nil, "not_pouring" end
    local p = sh.pouring
    local index = (self.M.int(item) or -1) + 1
    if p.ticket ~= ticketId or p.index ~= index then return nil, "not_pouring" end
    local t = self.tickets[ticketId]
    self:releaseStation(sh)
    if not t or t.state ~= "paid" then return nil, "ticket_gone" end
    local drink = self.cfg.drinks[t.queue[index].drink]
    local elapsed = (self.P.now() - p.startedAt) / 1000
    if elapsed < self.M.minSeconds(self.cfg, drink) then
        sh.strikes = sh.strikes + 1
        self:log("player %d poured %s in %.1fs (strike %d)", bartender, drink.label, elapsed, sh.strikes)
        if sh.strikes >= self.cfg.pour.tooFastStrikes then self:clockOut(bartender, "too_fast") end
        return nil, "too_fast"
    end
    local score, why = self.M.scorePour(self.cfg, drink, steps)
    if not score then return nil, why end
    if not self:stationNearOk(bartender, sh.bar) then return nil, "not_at_station" end
    t.queue[index].made = true
    t.queue[index].quality = score
    local left = 0
    for _, q in ipairs(t.queue) do if not q.made then left = left + 1 end end
    if left == 0 then
        self:setState(t, "ready")
        self:pushStools(t.bar)
    else
        self:save(t)
    end
    return score, left
end

function S:stationNearOk(pid, barId)
    local b = self:stationNear(pid)
    return b == barId
end

function S:pourCancel(bartender)
    local sh = self.shifts[bartender]
    if sh then self:releaseStation(sh) end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Serve and settle. The payout is one operation from escrow: till share to the bar's society,
-- cut + tip to the bartender. Retried with the same id until the economy answers.
-- ---------------------------------------------------------------------------------------------
function S:serve(t)
    if t.state ~= "ready" then return nil, "not_ready" end
    self:setState(t, "settling")
    self.P.handover(t.bartender.pid, t.customer.pid)
    for _, q in ipairs(t.queue) do
        local d = self.cfg.drinks[q.drink]
        self.P.event("o77_bar:served", t.customer.pid, q.drink, q.quality or 0, d.alcohol or 0)
    end
    self:trySettle(t)
    return "served"
end

function S:trySettle(t)
    local bar = self.cfg.bars[t.bar]
    local payees = {}
    if t.split.till > 0 then payees[#payees + 1] = { society = bar.society, amount = t.split.till } end
    if t.split.bartender > 0 then payees[#payees + 1] = { subject = t.bartender.subject, amount = t.split.bartender } end
    if #payees == 0 then self:setState(t, "settled") return true end
    local receipt, why, info = self.P.economy.pay({
        opId = self.M.settleOp(t), from = { society = self.cfg.escrowSociety }, payees = payees,
    })
    if receipt then
        self:setState(t, "settled")
        self.P.notify(t.bartender.pid, ("Served %s. You made %d (tip %d)."):format(t.customer.name, t.split.bartender, t.tip))
        self.P.notify(t.customer.pid, "Enjoy. Your tab is closed.")
        self:pushStools(t.bar)
        return true
    end
    self:retryLater(t, info)
    self:log("ticket %s settle not done (%s): retried", t.id, tostring(why))
    return nil, why
end

-- A fenced id (`info.state == "aborted"`) can never commit: the next attempt gets a new id.
function S:retryLater(t, info)
    if type(info) == "table" and info.state == "aborted" then
        t.attempt = (t.attempt or 1) + 1
        self:save(t)
    end
    self.nextTry[t.id] = self.P.now() + self.cfg.retryMs
end

-- ---------------------------------------------------------------------------------------------
-- Leaving: whatever the reason, a ticket that holds money is refunded in full.
-- ---------------------------------------------------------------------------------------------
function S:abandon(t, reason)
    t.reason = reason
    if self.M.PRE_PAY[t.state] or t.state == "ordering" then
        self:setState(t, "cancelled")
        self.P.ui(t.customer.pid, "close")
        self:pushStools(t.bar)
        return
    end
    if t.state == "paying" then
        -- the charge is in flight: mark it, kioskPay() refunds when the answer lands
        t.state = "abandoning"
        self:save(t)
        return
    end
    if t.state == "paid" or t.state == "ready" then
        for _, sh in pairs(self.shifts) do
            if sh.pouring and sh.pouring.ticket == t.id then self:releaseStation(sh) end
        end
        self:startRefund(t)
    end
    -- settling / refunding: already on their way, never interrupted
end

function S:startRefund(t)
    self:setState(t, "refunding")
    return self:tryRefund(t)
end

function S:tryRefund(t)
    local receipt, why, info = self.P.economy.pay({
        opId = self.M.refundOp(t), from = { society = self.cfg.escrowSociety },
        to = { subject = t.customer.subject, wallet = t.method }, amount = t.split.total,
    })
    if receipt then
        self:setState(t, "refunded")
        self.P.notify(t.customer.pid, ("Your tab was refunded: %d back on your %s."):format(t.split.total, t.method))
        if t.bartender then self.P.notify(t.bartender.pid, ("Ticket for %s refunded (%s)."):format(t.customer.name, tostring(t.reason))) end
        self:pushStools(t.bar)
        return true
    end
    self:retryLater(t, info)
    self:log("ticket %s refund not done (%s): retried", t.id, tostring(why))
    return nil, why
end

-- ---------------------------------------------------------------------------------------------
-- Tick: timeouts, the zone sweep, retries, in-doubt charges.
-- ---------------------------------------------------------------------------------------------
function S:tick()
    local now, L = self.P.now(), self.cfg.limits
    -- bartenders who walked out of their bar
    for pid, sh in pairs(self.shifts) do
        local pos = self.P.position(pid)
        local bar = self.cfg.bars[sh.bar]
        if pos and dist(pos, bar.zone.position) > bar.zone.radius + L.zoneGrace then self:clockOut(pid, "left_bar") end
    end
    for id, t in pairs(self.tickets) do
        local age = now - (t.updatedAt or now)
        if t.state == "ordering" and age > L.orderTimeoutMs then self:abandon(t, "order_timeout")
        elseif t.state == "billed" and age > L.billTimeoutMs then self:abandon(t, "bill_timeout")
        elseif (t.state == "paid" or t.state == "ready") and now - (t.paidAt or now) > L.serveTimeoutMs then self:abandon(t, "serve_timeout")
        elseif (self.nextTry[id] or math.huge) <= now then
            self.nextTry[id] = nil
            if t.state == "settling" then self:trySettle(t)
            elseif t.state == "refunding" then self:tryRefund(t)
            elseif t.state == "paying" or t.state == "abandoning" then self:resolveCharge(t)
            end
        end
    end
end

-- A charge whose answer never came: ask the economy what happened, then refund or carry on.
function S:resolveCharge(t)
    local st = self.P.economy.status(self.M.payOp(t))
    local state = type(st) == "table" and st.state or nil
    if state == "committed" then
        if t.state == "abandoning" or not self.seats[t.customer.pid] then return self:startRefund(t) end
        t.paidAt = self.P.now()
        self:setState(t, "paid")
        self:pushStools(t.bar)
    elseif state == "in_doubt" or state == "committing" or state == nil then
        self.nextTry[t.id] = self.P.now() + self.cfg.retryMs
    else
        -- failed / aborted / unknown: no money moved
        if t.state == "abandoning" then self:setState(t, "cancelled") else self:setState(t, "billed") end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Players leaving the server, and the boot after a restart.
-- ---------------------------------------------------------------------------------------------
function S:onDropped(pid)
    if self.shifts[pid] then self:clockOut(pid, "disconnected") end
    if self.seats[pid] then self:onStood(pid) end
    local t = self:ticketOfCustomer(pid)
    if t then self:abandon(t, "customer_disconnected") end
    self.lastRing[pid] = nil
end

-- Tickets that held money when the server stopped. Nobody is seated or on shift any more, so
-- every one is settled (if the hand-over had happened) or refunded.
function S:recover(rows)
    local n = 0
    for _, t in ipairs(rows) do
        n = n + 1
        self.tickets[t.id] = t
        t.customer.pid, t.bartender.pid = -1, -1
        if t.state == "settling" then self:trySettle(t)
        elseif t.state == "refunding" then self:tryRefund(t)
        elseif t.state == "paying" or t.state == "abandoning" then t.state = "abandoning"; self:resolveCharge(t)
        elseif t.state == "paid" or t.state == "ready" then t.reason = "server_restart"; self:startRefund(t)
        end
    end
    return n
end

return S
