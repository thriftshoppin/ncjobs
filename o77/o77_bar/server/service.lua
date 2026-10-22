-- o77_bar service: shifts, seats, rounds and tabs. Every outside call goes through `P` (ports), so
-- the whole flow runs under tests/service_test.lua with fakes. Methods that touch the economy or
-- the store may yield; the caller runs them in a thread.
--
-- Money model: customers drink on a TAB. A round is only taken if the customer can afford their
-- whole tab plus the round (cash + bank). Nothing is charged until the tab is closed at the kiosk,
-- or the customer leaves the club with it open (walkout: tab + the bar's fee), or disconnects and
-- does not come back (tab only). Each charge is one operation with a derived id: it never runs twice.
local S = {}
S.__index = S

function S.new(cfg, M, P)
    local self = setmetatable({}, S)
    self.cfg, self.M, self.P = cfg, M, P
    self.rounds = {}         -- round id -> round
    self.roundOf = {}        -- customer pid -> live round id
    self.tabs = {}           -- tab id -> tab
    self.tabOf = {}          -- customer subject -> tab id (one open tab per customer, at one bar)
    self.seats = {}          -- customer pid -> { bar, stool, position }
    self.shifts = {}         -- bartender pid -> { bar, strikes, since, served, earned, pouring?, grabbing? }
    self.stationUser = {}    -- "bar:index" -> bartender pid
    self.lastRing = {}       -- customer pid -> ms
    self.nextTry = {}        -- tab id -> ms (charge retries)
    self.away = {}           -- customer subject -> ms they dropped (disconnect grace)
    self.fees = {}           -- bar id -> walkout fee setting (loaded from the store, else config)
    self.seq = 0
    self.bootId = tostring(P.bootId())
    return self
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function inside(pos, zone, grace)
    if not pos then return true end   -- unknown position is never treated as leaving
    local dz = math.abs(pos.z - zone.position.z)
    if zone.maxHeight and dz > zone.maxHeight then return false end
    local dx, dy = pos.x - zone.position.x, pos.y - zone.position.y
    return math.sqrt(dx * dx + dy * dy) <= zone.radius + (grace or 0)
end

function S:log(fmt, ...) self.P.log(fmt:format(...)) end
function S:newId(kind) self.seq = self.seq + 1 return ("%s-%s%d"):format(self.bootId, kind, self.seq) end

function S:barAt(position)
    if not position then return nil end
    for id, bar in pairs(self.cfg.bars) do
        if dist(position, bar.zone.position) <= bar.zone.radius then return id, bar end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Walkout fee: per bar, set by its boss, saved in the store.
-- ---------------------------------------------------------------------------------------------
function S:feeSetting(barId)
    return self.fees[barId] or self.cfg.tab.walkout
end

function S:setWalkoutFee(pid, mode, value)
    local sh = self.shifts[pid]
    if not sh then return nil, "not_on_shift" end
    if (self.P.grade(pid) or 0) < self.cfg.tab.bossGrade then return nil, "not_the_boss" end
    value = self.M.int(value)
    local lim = self.cfg.tab.feeLimits
    if mode == "percent" then
        if not value or value < 0 or value > lim.percentMax then return nil, "invalid_fee" end
    elseif mode == "flat" then
        if not value or value < 0 or value > lim.flatMax then return nil, "invalid_fee" end
    else
        return nil, "invalid_fee"
    end
    local setting = { mode = mode, value = value, min = mode == "percent" and self.cfg.tab.walkout.min or nil }
    self.fees[sh.bar] = setting
    self.P.store.saveSetting(sh.bar, "walkout", setting)
    self:log("player %d set the %s walkout fee to %s %d", pid, sh.bar, mode, value)
    return setting
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
    self.shifts[pid] = { bar = barId, strikes = 0, since = self.P.now(), served = 0, earned = 0 }
    self:log("player %d clocked in at %s", pid, barId)
    self:pushBar(barId)
    return barId
end

-- Ends a shift. Rounds this bartender had not served yet are cancelled (nothing was charged for
-- them); drinks they already served stay on their customers' tabs and still pay them.
function S:clockOut(pid, reason)
    local sh = self.shifts[pid]
    if not sh then return nil, "not_on_shift" end
    for _, r in pairs(self.rounds) do
        if r.bartender.pid == pid then self:cancelRound(r, "bartender_" .. reason) end
    end
    for key, user in pairs(self.stationUser) do if user == pid then self.stationUser[key] = nil end end
    self.shifts[pid] = nil
    self.P.ui(pid, "close")
    self.P.toBartender(pid, "hud", { onShift = false })
    self:log("player %d clocked out of %s (%s)", pid, sh.bar, reason)
    self:pushBar(sh.bar)
    return true
end

function S:onShiftAt(barId)
    local out = {}
    for pid, sh in pairs(self.shifts) do if sh.bar == barId then out[#out + 1] = pid end end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Seats. Sitting gets a bartender's attention; standing up does NOT end anything: customers may
-- carry their drinks anywhere in the club. Only an order still being picked is dropped.
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
    self.seats[pid] = { bar = barId, stool = tostring(furnitureId), position = pos, since = self.P.now() }
    local staff = self:onShiftAt(barId)
    self.P.toCustomer(pid, "seated", { bar = bar.label, staffed = #staff > 0 })
    for _, b in ipairs(staff) do self.P.notify(b, self.P.name(pid) .. " sat down at the bar.") end
    self:pushBar(barId)
end

function S:onStood(pid)
    local seat = self.seats[pid]
    if not seat then return end
    self.seats[pid] = nil
    local r = self:roundOfCustomer(pid)
    if r and r.state == "ordering" then self:cancelRound(r, "customer_left_seat") end
    self.P.toCustomer(pid, "stood", {})
    self:pushBar(seat.bar)
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
-- Tabs
-- ---------------------------------------------------------------------------------------------
function S:tabOfSubject(subject)
    local id = subject and self.tabOf[subject]
    return id and self.tabs[id] or nil
end

function S:tabOfPlayer(pid) return self:tabOfSubject(self.P.subject(pid)) end

function S:openTab(pid, barId)
    local subject = self.P.subject(pid)
    if not subject then return nil, "subject_unavailable" end
    local tab = self:tabOfSubject(subject)
    if tab then
        if tab.bar ~= barId then return nil, "tab_open_elsewhere" end
        tab.customer.pid = pid
        return tab
    end
    local now = self.P.now()
    tab = { id = self:newId("T"), bar = barId, customer = { pid = pid, subject = subject, name = self.P.name(pid) },
        state = "open", served = {}, attempt = 1, createdAt = now, updatedAt = now }
    self.tabs[tab.id] = tab
    self.tabOf[subject] = tab.id
    return tab
end

function S:saveTab(tab)
    tab.updatedAt = self.P.now()
    local ok, why = self.P.store.saveTab(tab)
    if not ok then self:log("tab %s not saved (%s)", tab.id, tostring(why)) end
end

function S:finishTab(tab, how)
    tab.state = "settled"
    tab.how = how
    self:saveTab(tab)
    self.tabs[tab.id] = nil
    if self.tabOf[tab.customer.subject] == tab.id then self.tabOf[tab.customer.subject] = nil end
    self.nextTry[tab.id] = nil
    self.P.event("o77_bar:tab", tab.id, how, tab.customer.pid)
    self:pushBar(tab.bar)
end

-- What a customer could still order: cash + bank, minus the open tab and rounds not yet served.
function S:headroom(pid, tab)
    local b = self.P.balances(pid)
    if not b then return nil, "wallet_unavailable" end
    local committed = tab and self.M.owed(tab) or 0
    for _, r in pairs(self.rounds) do
        if r.customer.pid == pid and r.subtotal then committed = committed + r.subtotal end
    end
    return (b.cash or 0) + (b.bank or 0) - committed
end

-- ---------------------------------------------------------------------------------------------
-- Lock-on: a bartender looks at a customer in the club and picks an action.
--   "menu"  hand the menu (a new round)       "serve"  hand over a ready round
--   "bill"  open the kiosk to close the tab   (no choice = the obvious next step)
-- ---------------------------------------------------------------------------------------------
function S:within(a, b, reach)
    local pa, pb = self.P.position(a), self.P.position(b)
    if not pa or not pb then return false end
    return dist(pa, pb) <= reach
end

function S:roundOfCustomer(pid)
    local id = self.roundOf[pid]
    return id and self.rounds[id] or nil
end

function S:lockOn(bartender, customer, choice)
    local sh = self.shifts[bartender]
    if not sh then return nil, "not_on_shift" end
    if bartender == customer then return nil, "self_service" end
    local seat = self.seats[customer]
    local tab = self:tabOfPlayer(customer)
    local here = (seat and seat.bar == sh.bar) or (tab and tab.bar == sh.bar)
    if not here then return nil, "not_a_customer_here" end
    if not self:within(bartender, customer, self.cfg.limits.lockReach) then return nil, "too_far" end
    local r = self:roundOfCustomer(customer)
    if r and r.bartender.pid ~= bartender and choice ~= "bill" then return nil, "another_bartender" end
    if not choice then
        if r and r.state == "ready" then choice = "serve"
        elseif r then return nil, "wait_" .. r.state
        else choice = "menu" end
    end
    if choice == "serve" then
        if not r or r.state ~= "ready" then return nil, "nothing_ready" end
        return self:serve(r)
    elseif choice == "menu" then
        if r then return nil, "round_in_progress" end
        return self:handMenu(bartender, customer, sh.bar, seat)
    elseif choice == "bill" then
        return self:sendBill(customer)
    end
    return nil, "unknown_choice"
end

function S:handMenu(bartender, customer, barId, seat)
    if self.P.store.debtOf(self.P.subject(customer)) > 0 then return nil, "customer_owes" end
    local tab, why = self:openTab(customer, barId)
    if not tab then return nil, why end
    local room = self:headroom(customer, tab)
    if not room then return nil, "wallet_unavailable" end
    local now = self.P.now()
    local r = { id = self:newId("R"), tab = tab.id, bar = barId, stool = seat and seat.stool or "-",
        customer = { pid = customer, subject = tab.customer.subject, name = tab.customer.name },
        bartender = { pid = bartender, subject = self.P.subject(bartender), name = self.P.name(bartender) },
        state = "ordering", createdAt = now, updatedAt = now }
    self.rounds[r.id] = r
    self.roundOf[customer] = r.id
    local bar = self.cfg.bars[barId]
    local menu = {}
    for _, id in ipairs(bar.menu) do
        local d = self.cfg.drinks[id]
        menu[#menu + 1] = { drink = id, label = d.label, price = d.price, flavour = d.flavour,
            glass = (self.cfg.glasses[d.glass] or {}).label, section = d.section or "From the bar" }
    end
    for _, id in ipairs(self.M.barBottles(self.cfg, bar)) do
        local b = self.cfg.bottles[id]
        menu[#menu + 1] = { drink = id, label = b.label, price = b.price, tier = b.tier, bottle = true,
            section = b.kind == "alcohol" and "Bottles" or "Soft drinks" }
    end
    self.P.ui(customer, "menu", { ticketId = r.id, bar = bar.label, bartender = r.bartender.name, menu = menu,
        maxItems = self.cfg.limits.maxItems, maxQty = self.cfg.limits.maxQtyPerDrink,
        bulkFrom = self.cfg.limits.bulkFrom, maxBulk = self.cfg.limits.maxBulk,
        canSpend = room, tabSoFar = self.M.owed(tab) })
    self:pushBar(barId)
    return "menu"
end

-- The customer sends their pick. It is refused unless the whole tab, other open rounds and this
-- round fit in what they have right now.
function S:menuSubmit(customer, roundId, items)
    local r = self.rounds[roundId]
    if not r or r.customer.pid ~= customer or r.state ~= "ordering" then return nil, "ticket_gone" end
    local lines, subtotal = self.M.priceOrder(self.cfg, self.cfg.bars[r.bar], items)
    if not lines then return nil, subtotal end
    local room = self:headroom(customer, self.tabs[r.tab])
    if not room then return nil, "wallet_unavailable" end
    if subtotal > room then return nil, "cannot_afford", { canSpend = math.max(0, room), costs = subtotal } end
    r.lines, r.subtotal, r.queue = lines, subtotal, self.M.queue(lines)
    r.state, r.updatedAt = "making", self.P.now()
    self.P.notify(r.bartender.pid, ("%s ordered %d item(s) on their tab."):format(r.customer.name, #r.queue))
    self:pushBar(r.bar)
    return true
end

function S:menuCancel(customer, roundId)
    local r = self.rounds[roundId]
    if not r or r.customer.pid ~= customer or r.state ~= "ordering" then return nil, "ticket_gone" end
    self:cancelRound(r, "customer_cancelled")
    return true
end

function S:cancelRound(r, reason)
    if not self.M.ROUND_LIVE[r.state] then return end
    r.state, r.reason = "cancelled", reason
    self.rounds[r.id] = nil
    if self.roundOf[r.customer.pid] == r.id then self.roundOf[r.customer.pid] = nil end
    for key, pid in pairs(self.stationUser) do
        local sh = self.shifts[pid]
        if sh and sh.pouring and sh.pouring.ticket == r.id then sh.pouring = nil; self.stationUser[key] = nil; self.P.ui(pid, "close") end
    end
    for _, sh in pairs(self.shifts) do if sh.grabbing and sh.grabbing.ticket == r.id then sh.grabbing = nil end end
    self.P.ui(r.customer.pid, "close")
    self:log("round %s cancelled (%s)", r.id, reason)
    self:pushBar(r.bar)
end

-- ---------------------------------------------------------------------------------------------
-- The station (pour) and the cooler (grab). A round is ready when every task is done.
-- ---------------------------------------------------------------------------------------------
function S:stationQueue(bartender)
    local sh = self.shifts[bartender]
    if not sh then return nil, "not_on_shift" end
    local out = {}
    for _, r in pairs(self.rounds) do
        if r.bartender.pid == bartender and r.state == "making" then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return a.updatedAt < b.updatedAt end)
    return out
end

function S:startPour(bartender, roundId, index)
    local sh = self.shifts[bartender]
    if not sh then return nil, "not_on_shift" end
    local r = self.rounds[roundId]
    if not r or r.bartender.pid ~= bartender or r.state ~= "making" then return nil, "ticket_gone" end
    local entry = r.queue[index]
    if not entry or entry.made then return nil, "already_made" end
    if entry.kind ~= "pour" then return nil, "grab_at_cooler" end
    local barId, stationIdx = self:stationNear(bartender)
    if barId ~= sh.bar then return nil, "not_at_station" end
    local key = barId .. ":" .. stationIdx
    local user = self.stationUser[key]
    if user and user ~= bartender then return nil, "station_busy" end
    self.stationUser[key] = bartender
    sh.pouring = { ticket = r.id, index = index, startedAt = self.P.now(), station = key }
    self.P.ui(bartender, "pour", self.M.pourOrder(self.cfg, r, index, self.P.grade(bartender)))
    return true
end

function S:releaseStation(sh)
    if sh.pouring and sh.pouring.station then self.stationUser[sh.pouring.station] = nil end
    sh.pouring = nil
end

function S:pourSubmit(bartender, roundId, item, steps)
    local sh = self.shifts[bartender]
    if not sh or not sh.pouring then return nil, "not_pouring" end
    local p = sh.pouring
    local index = (self.M.int(item) or -1) + 1
    if p.ticket ~= roundId or p.index ~= index then return nil, "not_pouring" end
    local r = self.rounds[roundId]
    self:releaseStation(sh)
    if not r or r.state ~= "making" then return nil, "ticket_gone" end
    local drink = self.cfg.drinks[r.queue[index].drink]
    local elapsed = (self.P.now() - p.startedAt) / 1000
    if elapsed < self.M.minSeconds(self.cfg, drink) then
        sh.strikes = sh.strikes + 1
        self:log("player %d poured %s in %.1fs (strike %d)", bartender, drink.label, elapsed, sh.strikes)
        if sh.strikes >= self.cfg.pour.tooFastStrikes then self:clockOut(bartender, "too_fast") end
        return nil, "too_fast"
    end
    local score, why = self.M.scorePour(self.cfg, drink, steps)
    if not score then return nil, why end
    if self:stationNear(bartender) ~= sh.bar then return nil, "not_at_station" end
    r.queue[index].quality = score
    return score, self:markMade(r, index)
end

function S:pourCancel(bartender)
    local sh = self.shifts[bartender]
    if sh then self:releaseStation(sh) end
    return true
end

function S:markMade(r, index)
    r.queue[index].made = true
    local left = 0
    for _, q in ipairs(r.queue) do if not q.made then left = left + 1 end end
    if left == 0 then r.state, r.updatedAt = "ready", self.P.now() end
    self:pushBar(r.bar)
    return left
end

function S:coolerNear(pid, barId)
    local pos = self.P.position(pid)
    if not pos then return false end
    for _, c in ipairs(self.cfg.bars[barId].coolers or {}) do
        if dist(pos, c.position) <= self.cfg.limits.coolerReach then return true end
    end
    return false
end

function S:startGrab(bartender, roundId, index)
    local sh = self.shifts[bartender]
    if not sh then return nil, "not_on_shift" end
    if sh.pouring or sh.grabbing then return nil, "busy" end
    local r = self.rounds[roundId]
    if not r or r.bartender.pid ~= bartender or r.state ~= "making" then return nil, "ticket_gone" end
    local entry = r.queue[index]
    if not entry or entry.made then return nil, "already_made" end
    if entry.kind ~= "grab" then return nil, "pour_at_station" end
    if not self:coolerNear(bartender, sh.bar) then return nil, "not_at_cooler" end
    local seconds = self.M.grabSeconds(self.cfg, entry)
    sh.grabbing = { ticket = r.id, index = index, startedAt = self.P.now(), ms = math.floor(seconds * 1000) }
    self.P.progress(bartender, ("Grabbing %d x %s"):format(entry.qty, self.cfg.bottles[entry.drink].label), sh.grabbing.ms)
    return seconds
end

function S:finishGrab(bartender)
    local sh = self.shifts[bartender]
    if not sh or not sh.grabbing then return nil, "not_grabbing" end
    local g = sh.grabbing
    sh.grabbing = nil
    if self.P.now() - g.startedAt < g.ms * 0.9 then return nil, "too_fast" end
    if not self:coolerNear(bartender, sh.bar) then return nil, "not_at_cooler" end
    local r = self.rounds[g.ticket]
    if not r or r.state ~= "making" then return nil, "ticket_gone" end
    return true, self:markMade(r, g.index)
end

function S:cancelGrab(bartender)
    local sh = self.shifts[bartender]
    if sh then sh.grabbing = nil end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Serve: the round's items land on the counter / in the bag, and on the tab with who served them.
-- ---------------------------------------------------------------------------------------------
function S:serve(r)
    local tab = self.tabs[r.tab]
    if not tab or tab.state ~= "open" then self:cancelRound(r, "tab_closed") return nil, "tab_closed" end
    r.state = "served"
    self.rounds[r.id] = nil
    if self.roundOf[r.customer.pid] == r.id then self.roundOf[r.customer.pid] = nil end
    for _, l in ipairs(r.lines) do
        local def = l.kind == "bottle" and self.cfg.bottles[l.drink] or self.cfg.drinks[l.drink]
        tab.served[#tab.served + 1] = { drink = l.drink, label = def.label, qty = l.qty, price = l.price,
            bulk = l.bulk, bartender = r.bartender.subject, bartenderName = r.bartender.name, round = r.id }
    end
    self:saveTab(tab)
    self.P.handover(r.bartender.pid, r.customer.pid)
    for _, q in ipairs(r.queue) do
        if q.kind == "pour" then
            local d = self.cfg.drinks[q.drink]
            self.P.event("o77_bar:served", r.customer.pid, q.drink, d.item, q.quality or 0, d.alcohol or 0)
        end
    end
    local open, bulk = self.M.bottlesOf(self.cfg, r.lines)
    for _, b in ipairs(open) do self.P.event("o77_bar:servedBottle", r.customer.pid, b.drink, b.item, b.qty) end
    if #bulk > 0 then self.P.giveBottles(r.customer.pid, bulk, r.id) end
    local sh = self.shifts[r.bartender.pid]
    if sh then sh.served = sh.served + 1 end
    self.P.notify(r.customer.pid, ("On your tab: %d. Pay at the kiosk before you leave the club."):format(self.M.owed(tab)))
    self:pushBar(r.bar)
    return "served"
end

-- ---------------------------------------------------------------------------------------------
-- Closing a tab at the kiosk: the customer picks a tip and a wallet; one charge pays everyone.
-- ---------------------------------------------------------------------------------------------
function S:sendBill(customer)
    local tab = self:tabOfPlayer(customer)
    if not tab or tab.state ~= "open" then return nil, "no_tab" end
    if #tab.served == 0 then return nil, "nothing_served" end
    local balances = self.P.balances(customer)
    if not balances then return nil, "wallet_unavailable" end
    local items = {}
    for _, l in ipairs(tab.served) do
        items[#items + 1] = { label = l.label, qty = l.qty, price = l.price,
            flavour = l.bulk and "To go, sealed" or ("Served by " .. tostring(l.bartenderName)) }
    end
    local names = {}
    for _, l in ipairs(tab.served) do names[l.bartenderName] = true end
    local list = {}
    for n in pairs(names) do list[#list + 1] = n end
    table.sort(list)
    self.P.ui(customer, "kiosk", { id = tab.id, bar = self.cfg.bars[tab.bar].label, stool = "tab",
        bartender = table.concat(list, ", "), defaultTip = self.cfg.defaultTip, tips = self.cfg.tips,
        balances = balances, items = items })
    return "bill"
end

function S:kioskPay(customer, tabId, tipPct, method)
    local tab = self.tabs[tabId]
    if not tab or tab.customer.pid ~= customer or tab.state ~= "open" then return nil, "ticket_gone" end
    if method ~= "cash" and method ~= "bank" then return nil, "invalid_method" end
    local owed = self.M.owed(tab)
    local tip, why = self.M.tipFor(self.cfg, owed, tipPct)
    if not tip then return nil, why end
    local split = self.M.tabSplit(self.cfg, self.cfg.bars[tab.bar], tab, tip, 0)
    tab.state, tab.method, tab.tip, tab.split = "closing", method, tip, split
    self:saveTab(tab)
    local receipt, reason, info = self.P.economy.charge({
        opId = self.M.closeOp(tab), from = { subject = tab.customer.subject, wallet = method },
        amount = split.total, instrument = method, payees = split.payees,
    })
    if receipt then return self:paid(tab, "closed") end
    if reason == "in_doubt" or (type(info) == "table" and info.retryable) then
        self:retryLater(tab, info)
        return nil, reason
    end
    tab.state, tab.split = "open", nil       -- refused (not enough on that wallet): still open
    self:saveTab(tab)
    return nil, reason
end

function S:paid(tab, how)
    for _, p in ipairs(tab.split.payees) do
        if p.subject then
            for pid, sh in pairs(self.shifts) do
                if self.P.subject(pid) == p.subject then sh.earned = sh.earned + p.amount end
            end
        end
    end
    if how == "closed" then
        self.P.notify(tab.customer.pid, ("Tab closed: %d paid. Thanks for drinking at the %s."):format(tab.split.total, self.cfg.bars[tab.bar].label))
    end
    self:finishTab(tab, how)
    return true
end

function S:retryLater(tab, info)
    if type(info) == "table" and info.state == "aborted" then
        tab.attempt = (tab.attempt or 1) + 1
        self:saveTab(tab)
    end
    self.nextTry[tab.id] = self.P.now() + self.cfg.retryMs
end

-- ---------------------------------------------------------------------------------------------
-- Leaving with an open tab.
--   walkout   left the club: tab + the bar's walkout fee, cash first then bank
--   leave     disconnected and did not come back, or the server restarted: tab only
-- If they cannot cover it, they pay what they have and the rest is recorded as debt; a customer
-- with debt cannot start a tab at any bar until it is paid.
-- ---------------------------------------------------------------------------------------------
function S:chargeOnExit(tab, how)
    local owed = self.M.owed(tab)
    if owed <= 0 then self:finishTab(tab, "empty") return true end
    for _, r in pairs(self.rounds) do if r.tab == tab.id then self:cancelRound(r, "customer_" .. how) end end
    if tab.state == "open" then
        local fee = how == "walkout" and self.M.walkoutFee(self:feeSetting(tab.bar), owed) or 0
        tab.split = self.M.tabSplit(self.cfg, self.cfg.bars[tab.bar], tab, 0, fee)
        tab.state, tab.method = (how == "walkout" and "walking" or "leaving"), "cash_then_bank"
        self:saveTab(tab)
        self:log("tab %s %s: owes %d, fee %d", tab.id, how, owed, fee)
    end
    return self:tryExitCharge(tab)
end

function S:tryExitCharge(tab)
    local opId = tab.state == "walking" and self.M.walkOp(tab) or self.M.leaveOp(tab)
    local spec = { opId = opId, from = { subject = tab.customer.subject }, instrument = "cash_then_bank",
        amount = tab.split.total, payees = tab.split.payees }
    if tab.partial then spec.amount, spec.payees = tab.partial.paid, tab.partial.payees end
    local receipt, reason, info = self.P.economy.charge(spec)
    if receipt then
        if tab.partial and tab.partial.debt > 0 then
            self.P.store.addDebt(tab.customer.subject, tab.bar, tab.partial.debt, tab.id)
        end
        if tab.state == "walking" then
            self.P.notify(tab.customer.pid, ("You left the %s without paying. Charged %d, including a %d walkout fee%s."):format(
                self.cfg.bars[tab.bar].label, spec.amount, tab.split.fee,
                (tab.partial and tab.partial.debt > 0) and (" (" .. tab.partial.debt .. " still owed)") or ""))
            for _, b in ipairs(self:onShiftAt(tab.bar)) do
                self.P.notify(b, ("%s walked out on a %d tab. Charged automatically."):format(tab.customer.name, self.M.owed(tab)))
            end
        end
        if tab.partial then tab.split.payees = tab.partial.payees end
        return self:paid(tab, tab.state == "walking" and "walkout" or "leave")
    end
    if reason == "insufficient_funds" and not tab.partial then
        -- take what they have; the rest becomes debt
        local bal = self.P.balances(tab.customer.pid) or self.P.balancesOf(tab.customer.subject) or { cash = 0, bank = 0 }
        local available = (bal.cash or 0) + (bal.bank or 0)
        local payees, debt, paid = self.M.partial(tab.split, available)
        tab.partial = { payees = payees, debt = debt, paid = paid }
        tab.attempt = (tab.attempt or 1) + 1   -- a different charge: a new id
        self:saveTab(tab)
        if paid <= 0 then
            self.P.store.addDebt(tab.customer.subject, tab.bar, debt, tab.id)
            tab.split.payees = {}
            return self:paid(tab, tab.state == "walking" and "walkout" or "leave")
        end
        return self:tryExitCharge(tab)
    end
    self:retryLater(tab, info)
    self:log("tab %s exit charge not done (%s): retried", tab.id, tostring(reason))
    return nil, reason
end

-- ---------------------------------------------------------------------------------------------
-- Tick: zones, timeouts, disconnect grace, retries. Runs every second or so.
-- ---------------------------------------------------------------------------------------------
function S:tick()
    local now, L = self.P.now(), self.cfg.limits
    for pid, sh in pairs(self.shifts) do
        local bar = self.cfg.bars[sh.bar]
        local pos = self.P.position(pid)
        if pos and dist(pos, bar.zone.position) > bar.zone.radius + L.zoneGrace then self:clockOut(pid, "left_bar") end
    end
    for _, r in pairs(self.rounds) do
        if r.state == "ordering" and now - r.updatedAt > L.orderTimeoutMs then self:cancelRound(r, "order_timeout") end
    end
    for id, tab in pairs(self.tabs) do
        local bar = self.cfg.bars[tab.bar]
        if tab.state == "open" then
            local away = self.away[tab.customer.subject]
            if away then
                if now - away >= self.cfg.tab.disconnectGraceMs then self.away[tab.customer.subject] = nil; self:chargeOnExit(tab, "leave") end
            elseif tab.customer.pid > 0 and not inside(self.P.position(tab.customer.pid), bar.venue, L.venueGrace) then
                if #tab.served > 0 then self:chargeOnExit(tab, "walkout") else self:finishTab(tab, "empty") end
            end
        elseif (self.nextTry[id] or math.huge) <= now then
            self.nextTry[id] = nil
            if tab.state == "closing" then self:resolveClose(tab)
            else self:tryExitCharge(tab) end
        end
    end
end

-- A close charge with no answer: ask what happened, then finish or reopen.
function S:resolveClose(tab)
    local st = self.P.economy.status(self.M.closeOp(tab))
    local state = type(st) == "table" and st.state or nil
    if state == "committed" then return self:paid(tab, "closed") end
    if state == "in_doubt" or state == "committing" or state == nil then
        self.nextTry[tab.id] = self.P.now() + self.cfg.retryMs
        return
    end
    tab.state, tab.split = "open", nil
    tab.attempt = (tab.attempt or 1) + 1
    self:saveTab(tab)
end

-- ---------------------------------------------------------------------------------------------
-- Players coming and going, and the boot after a restart.
-- ---------------------------------------------------------------------------------------------
function S:onDropped(pid)
    if self.shifts[pid] then self:clockOut(pid, "disconnected") end
    if self.seats[pid] then self:onStood(pid) end
    local r = self:roundOfCustomer(pid)
    if r then self:cancelRound(r, "customer_disconnected") end
    local tab = self:tabOfPlayer(pid)
    if tab and tab.state == "open" then
        self.away[tab.customer.subject] = self.P.now()
        tab.customer.pid = -1
    end
    self.lastRing[pid] = nil
end

-- A customer reconnected: their open tab is theirs again.
function S:onJoined(pid)
    local subject = self.P.subject(pid)
    local tab = self:tabOfSubject(subject)
    if tab and tab.state == "open" then
        tab.customer.pid = pid
        self.away[subject] = nil
        self.P.notify(pid, ("Your %s tab is still open: %d. Pay before you leave the club."):format(self.cfg.bars[tab.bar].label, self.M.owed(tab)))
    end
end

function S:loadSettings(rows)
    for _, row in ipairs(rows or {}) do
        if row.key == "walkout" and type(row.value) == "table" then self.fees[row.bar] = row.value end
    end
end

-- Tabs that were open when the server stopped. Nobody can be in the club yet: each customer gets
-- the disconnect grace to come back and pay; after it, the tab is charged without a fee.
function S:recover(rows)
    local n = 0
    for _, tab in ipairs(rows) do
        if tab.state ~= "settled" then
            n = n + 1
            tab.customer.pid = -1
            self.tabs[tab.id] = tab
            self.tabOf[tab.customer.subject] = tab.id
            if tab.state == "open" then
                self.away[tab.customer.subject] = self.P.now()
            elseif tab.state == "closing" then
                self:resolveClose(tab)
            else
                self:tryExitCharge(tab)
            end
        end
    end
    return n
end

-- ---------------------------------------------------------------------------------------------
-- What each bartender's HUD shows: everyone at the bar or on a tab here, by what they need.
-- ---------------------------------------------------------------------------------------------
function S:pushBar(barId)
    local now, rows, seen = self.P.now(), {}, {}
    local function add(pid, seat)
        if seen[pid] then return end
        seen[pid] = true
        local r = self:roundOfCustomer(pid)
        local tab = self:tabOfPlayer(pid)
        local state, detail = "none", seat and "Just sat down: hand the menu" or "Walking around"
        if r then
            state = r.state == "making" and "paid" or r.state
            if r.queue then
                local made = 0
                for _, q in ipairs(r.queue) do if q.made then made = made + 1 end end
                detail = ("%d of %d made"):format(made, #r.queue)
            else
                detail = "Reading the menu"
            end
        elseif tab and #tab.served > 0 then
            state, detail = "tab", ("Tab open: %d"):format(self.M.owed(tab))
        end
        rows[#rows + 1] = { customer = pid, name = self.P.name(pid), stool = seat and seat.stool or "-",
            state = state, detail = detail, waitedMs = now - ((r and r.updatedAt) or (seat and seat.since) or now),
            mine = r and r.bartender.pid or nil, position = seat and seat.position or nil }
    end
    for pid, seat in pairs(self.seats) do if seat.bar == barId then add(pid, seat) end end
    for _, tab in pairs(self.tabs) do
        if tab.bar == barId and tab.state == "open" and tab.customer.pid > 0 then add(tab.customer.pid, self.seats[tab.customer.pid]) end
    end
    for _, b in ipairs(self:onShiftAt(barId)) do
        local sh = self.shifts[b]
        self.P.toBartender(b, "hud", { bar = self.cfg.bars[barId].label, onShift = true, shiftMs = now - sh.since,
            served = sh.served, earned = sh.earned, stools = rows })
    end
end

return S
