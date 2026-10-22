-- o77_bar: configuration shared by the server and the client.
-- Positions are world metres. Money is eddies. Durations are milliseconds unless named.
O77BarConfig = {}
local C = O77BarConfig

-- Who may work a bar: an rp_jobs job. Only membership is read; rp_jobs duty and salary are
-- NOT used (bartenders are paid per served ticket, see `split`).
C.job = "barman"

-- Where customer money waits between the kiosk and the hand-over (an rp_economy society).
-- Nobody withdraws from it; its balance should equal the totals of the live paid tickets
-- (`o77bar.status` prints both).
C.escrowSociety = "o77bar_escrow"

-- How a settled ticket is split. The tip always goes to the bartender in full.
C.split = {
    tillShare = 0.60,      -- of the drinks subtotal, to the bar's society (the till)
    -- the rest of the subtotal is the bartender's cut
}

C.tips = { 0, 10, 15, 20 }   -- percent, offered on the kiosk
C.defaultTip = 15

C.limits = {
    maxItems = 6,              -- drinks on one ticket (sum of quantities)
    maxQtyPerDrink = 4,
    orderTimeoutMs = 120000,   -- menu handed -> customer must order
    billTimeoutMs = 90000,     -- bill sent -> customer must pay
    serveTimeoutMs = 600000,   -- paid -> must be served, else refunded
    lockReach = 3.0,           -- bartender <-> customer for menu, bill and serve
    stationReach = 2.0,        -- bartender <-> station to pour
    zoneGrace = 4.0,           -- metres beyond a bar's zone before a bartender is clocked out
    ringCooldownMs = 45000,    -- a customer may ring for service this often
}

C.retryMs = 15000            -- settle / refund retried this often until the economy answers

-- Pour checks. The client plays the minigame; the server re-scores the amounts it sends and
-- refuses a drink finished faster than a person could pour it.
C.pour = {
    rateMlPerSec = 32,        -- must match the page's POUR_RATE
    perfectMl = 3, goodMl = 8,
    minSecondsPerIce = 0.25,
    minSecondsPerBeat = 0.6,
    speedSlack = 0.80,         -- a submission may arrive at 80 % of the computed minimum
    tooFastStrikes = 3,        -- this many too-fast submissions in a shift ends the shift
}

-- Glasses. The page draws the shape; capacity sets how a pour fills it.
--   top / bottom   rim and foot width, as a fraction of the drawing's width
--   height         glass height, as a fraction of the drawing's height
--   base           solid glass at the bottom, as a fraction of the glass height
C.glasses = {
    pint     = { label = "Pint glass",     capacityMl = 470, top = 0.62, bottom = 0.46, height = 0.92, base = 0.05 },
    rocks    = { label = "Rocks glass",    capacityMl = 300, top = 0.58, bottom = 0.54, height = 0.58, base = 0.16 },
    highball = { label = "Highball glass", capacityMl = 350, top = 0.46, bottom = 0.44, height = 0.86, base = 0.08 },
}

-- Shake/stir difficulty by rp_jobs grade: the better your title, the easier the beat.
--   speed     needle sweeps per second (a recipe's own `speed` multiplies this)
--   perfect   half-width of the perfect zone, in % of the meter
--   good      half-width of the good zone, in % of the meter
C.shakeByGrade = {
    [0] = { title = "Recruit",  speed = 1.45, perfect = 3, good = 9 },
    [1] = { title = "Employee", speed = 1.20, perfect = 4, good = 12 },
    [2] = { title = "Senior",   speed = 1.00, perfect = 6, good = 15 },
    [3] = { title = "Boss",     speed = 0.85, perfect = 8, good = 18 },
}

-- Drinks. Steps are what the bartender does, in order:
--   { id, type = "pour",  label, ml, color }        hold to pour to a line
--   { id, type = "count", label, verb, count }      press N times (ice, dashes, a garnish)
--   { id, type = "beat",  label, verb, beats, speed } hit the beat N times (shake, stir);
--                                                   difficulty comes from shakeByGrade
C.drinks = {
    broseph = {
        glass = "pint",
        label = "Broseph Lager", price = 30, alcohol = 1,
        flavour = "From the tap. Cold, cheap, honest.",
        steps = { { id = "lager", type = "pour", label = "Broseph lager", ml = 160, color = "#d9a03a" } },
    },
    synth_soda = {
        glass = "highball",
        label = "Synth Soda", price = 20, alcohol = 0,
        flavour = "Sweet, fizzy, zero eddies of regret.",
        steps = {
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 3 },
            { id = "soda", type = "pour", label = "Soda", ml = 140, color = "#c94b6a" },
        },
    },
    whiskey_rocks = {
        glass = "rocks",
        label = "Whiskey on the Rocks", price = 60, alcohol = 2,
        flavour = "Two fingers over ice. Nobody asks which bottle.",
        steps = {
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 2 },
            { id = "whiskey", type = "pour", label = "Whiskey", ml = 60, color = "#b5651d" },
        },
    },
    -- Canon: a tequila old fashioned with a splash of cerveza, lime juice and a chili garnish.
    johnny_silverhand = {
        glass = "rocks",
        label = "Johnny Silverhand", price = 120, alcohol = 3,
        flavour = "Tequila old fashioned, a splash of cerveza, lime, chili. Wake up, samurai.",
        steps = {
            { id = "tequila", type = "pour", label = "Centzon tequila", ml = 60, color = "#e8c56a" },
            { id = "agave", type = "pour", label = "Agave syrup", ml = 10, color = "#c98a2b" },
            { id = "bitters", type = "count", label = "Bitters", verb = "Add a dash", count = 2 },
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 2 },
            { id = "stir", type = "beat", label = "Stir", verb = "Stir", beats = 3, speed = 0.9 },
            { id = "lime", type = "pour", label = "Lime juice", ml = 15, color = "#b8e05a" },
            { id = "cerveza", type = "pour", label = "Splash of cerveza", ml = 30, color = "#d9a03a" },
            { id = "chili", type = "count", label = "Chili garnish", verb = "Garnish", count = 1 },
        },
    },
}

-- Bars. Each is data: add Lizzie's or El Coyote here, no code.
--   zone      sphere the bar lives in; bartenders are clocked out beyond radius + zoneGrace
--   society   the till (rp_economy society); created on first credit
--   stations  where drinks are poured (clock in/out happens here too)
--   stools    open77_furniture ids that count as this bar's seats. Empty = any seat inside the
--             zone counts (fine for a first test; list the real stools before going live:
--             stand at the bar and run `seating.near` in the server console)
--   menu      drink ids on this bar's card, in order
C.bars = {
    afterlife = {
        label = "Afterlife",
        zone = { position = { x = -1453.0, y = 1016.7, z = 16.5 }, radius = 25.0 },
        society = "bar_afterlife",
        stations = {
            { position = { x = -1451.5, y = 1012.5, z = 17.8 }, label = "Afterlife - bar" },
        },
        stools = {},
        menu = { "broseph", "synth_soda", "whiskey_rocks", "johnny_silverhand" },
        color = "#FF5F58",
    },
}
