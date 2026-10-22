-- o77_bar: configuration shared by the server and the client.
-- Positions are world metres. Money is eddies. Durations are milliseconds unless named.
O77BarConfig = {}
local C = O77BarConfig

-- Who may work a bar: an rp_jobs job. Only membership is read; rp_jobs duty and salary are
-- NOT used (bartenders are paid per served ticket, see `split`).
C.job = "barman"

-- Customers drink on a TAB: every round is checked against what they can afford (cash + bank),
-- made and served, and the tab is paid at the kiosk when they are done. Leaving the club with
-- an unpaid tab charges it automatically, plus the bar's walkout fee.
C.tab = {
    disconnectGraceMs = 300000,   -- a dropped customer has this long to come back before the tab is charged (no fee)
    -- default walkout fee; each bar's boss can change it at the station (saved per bar)
    walkout = { mode = "percent", value = 25, min = 50 },   -- 25 % of the tab, at least 50 eddies
    feeLimits = { percentMax = 100, flatMax = 2000 },
    bossGrade = 3,                 -- rp_jobs grade that may set the fee
}

-- How a settled ticket is split. The tip always goes to the bartender in full.
C.split = {
    tillShare = 0.60,      -- of the drinks subtotal, to the bar's society (the till)
    -- the rest of the subtotal is the bartender's cut
}

C.tips = { 0, 10, 15, 20 }   -- percent, offered on the kiosk
C.defaultTip = 15

C.limits = {
    maxItems = 6,              -- drinks served open on one ticket (cocktails + single bottles/cans)
    maxQtyPerDrink = 4,        -- of one cocktail
    bulkFrom = 3,              -- this many or more of ONE bottle/can = a bulk buy: sealed, into the inventory
    maxBulk = 12,              -- of one bottle/can on one ticket
    coolerReach = 2.0,         -- bartender <-> cooler to grab bottles
    grabSeconds = { base = 1.0, perUnit = 0.4, max = 4.0 },   -- server-timed grab at the cooler
    orderTimeoutMs = 120000,   -- menu handed -> customer must order
    billTimeoutMs = 90000,     -- bill sent -> customer must pay
    serveTimeoutMs = 600000,   -- paid -> must be served, else refunded
    lockReach = 3.0,           -- bartender <-> customer for menu, bill and serve
    stationReach = 2.0,        -- bartender <-> station to pour
    zoneGrace = 4.0,           -- metres beyond a bar's zone before a bartender is clocked out
    venueGrace = 2.0,          -- metres beyond the club's venue zone before an open tab is a walkout
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
--   base           solid glass at the bottom, as a fraction of the drawing's height
local pint = { label = "Pint glass", capacityMl = 470, top = 0.62, bottom = 0.46, height = 0.92, base = 0.046 }

-- A shorter glass cut from the same shape: same foot, same taper, same base thickness. Its
-- width at the cut and its capacity follow from the new height, so the two never drift apart.
local function cutFrom(src, height, label)
    local taper = (src.top - src.bottom) / src.height           -- width gained per unit of height
    local liquid = (height - src.base) / (src.height - src.base)
    return {
        label = label, height = height, bottom = src.bottom, base = src.base,
        top = src.bottom + taper * height,
        capacityMl = math.floor(src.capacityMl * liquid + 0.5),
    }
end

C.glasses = {
    pint     = pint,
    rocks    = cutFrom(pint, 0.42, "Rocks glass"),
    highball = { label = "Highball glass", capacityMl = 350, top = 0.46, bottom = 0.44, height = 0.86, base = 0.06 },
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

-- Drinks. `item` is the base game's own consumable record (o77/reference/console_commands/
-- consumables.json): the served glass is placed on the counter as that native item, so the
-- customer gets the real icon, name and drink effect.
-- Steps are what the bartender does, in order:
--   { id, type = "pour",  label, ml, color, rate? } hold to pour to a line (rate: ml/s, a tap
--                                                   pours faster than a bottle)
--   { id, type = "count", label, verb, count }      press N times (ice, dashes, a garnish)
--   { id, type = "beat",  label, verb, beats, speed } hit the beat N times (shake, stir);
--                                                   difficulty comes from shakeByGrade
C.drinks = {
    broseph = {
        item = "Items.LowQualityAlcohol4", glass = "pint",
        label = "Broseph Lager", price = 30, alcohol = 1,
        flavour = "From the tap. Cold, cheap, honest.",
        -- from the tap, to the rim
        steps = { { id = "lager", type = "pour", label = "Broseph lager", ml = 455, rate = 90, color = "#d9a03a" } },
    },
    nicola = {
        item = "Items.LowQualityDrink10", glass = "highball",
        label = "NiCola", price = 20, alcohol = 0,
        flavour = "Poured over ice. No buzz, no hangover.",
        steps = {
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 3 },
            { id = "nicola", type = "pour", label = "NiCola", ml = 140, color = "#7a1f1a" },
        },
    },
    odickin_rocks = {
        item = "Items.MediumQualityAlcohol2", glass = "rocks",
        label = "O'Dickin on the Rocks", price = 60, alcohol = 2,
        flavour = "O'Dickin whiskey, two fingers over ice.",
        steps = {
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 2 },
            { id = "whiskey", type = "pour", label = "O'Dickin whiskey", ml = 60, color = "#b5651d" },
        },
    },
    -- The three Afterlife homages. Descriptions are the in-game item text (Cyberpunk Wiki); the
    -- game sells each for 150 eddies from Claire.
    -- In game: "A tequila old fashioned with a splash of beer and a chili garnish." Lime juice is
    -- our addition (not in the item text): keep or drop the `lime` step.
    johnny_silverhand = {
        section = "Afterlife legends",
        item = "Items.TopQualityAlcohol8", glass = "rocks",
        label = "The Johnny Silverhand", price = 150, alcohol = 3,
        flavour = "A tequila old fashioned with a splash of beer and a chili garnish. For the rockerboy who never gave up.",
        steps = {
            { id = "tequila", type = "pour", label = "Centzon Totochtin", ml = 60, color = "#e8c56a" },
            { id = "agave", type = "pour", label = "Agave syrup", ml = 10, color = "#c98a2b" },
            { id = "bitters", type = "count", label = "Bitters", verb = "Add a dash", count = 2 },
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 2 },
            { id = "stir", type = "beat", label = "Stir", verb = "Stir", beats = 3, speed = 0.9 },
            { id = "lime", type = "pour", label = "Lime juice", ml = 15, color = "#b8e05a" },
            { id = "cerveza", type = "pour", label = "Splash of cerveza", ml = 30, color = "#d9a03a" },
            { id = "chili", type = "count", label = "Chili garnish", verb = "Garnish", count = 1 },
        },
    },    -- In game: "A shot of vodka, lime juice, ginger beer and, most importantly... a splash of love."
    jackie_welles = {
        section = "Afterlife legends",
        item = "Items.TopQualityAlcohol9", glass = "highball",
        label = "The Jackie Welles", price = 150, alcohol = 3,
        flavour = "A shot of vodka, lime juice, ginger beer and, most importantly, a splash of love.",
        steps = {
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 3 },
            { id = "vodka", type = "pour", label = "Bolshevik vodka", ml = 45, color = "#dfe8ee" },
            { id = "lime", type = "pour", label = "Lime juice", ml = 15, color = "#b8e05a" },
            { id = "ginger", type = "pour", label = "Ginger beer", ml = 120, color = "#c9a25a" },
            { id = "love", type = "count", label = "A splash of love", verb = "Add a splash of love", count = 1 },
        },
    },
    -- In game: "A shot of vodka on the rocks, topped with NiCola. Aim high and go out with a bang."
    david_martinez = {
        section = "Afterlife legends",
        item = "Items.TopQualityAlcohol10", glass = "rocks",
        label = "The David Martinez", price = 150, alcohol = 3,
        flavour = "A shot of vodka on the rocks, topped with NiCola. Aim high and go out with a bang.",
        steps = {
            { id = "ice", type = "count", label = "Ice", verb = "Drop a cube", count = 2 },
            { id = "vodka", type = "pour", label = "Bolshevik vodka", ml = 45, color = "#dfe8ee" },
            { id = "nicola", type = "pour", label = "NiCola", ml = 90, color = "#7a1f1a" },
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
-- Bottles and cans: every Alcohol and Drink record from the CONSUMABLES tab of the console
-- command list (o77/reference/console_commands/consumables.json), except the three Afterlife
-- cocktails (mixed by a bartender only) and quest-only items. Ordered from the menu like a drink,
-- handed over at the counter as the native item into the customer's inventory: no pour.
-- Prices are OUR tuning by quality tier (the sheet has none): alcohol house 20 / mid 45 /
-- good 90 / top 240 / nomad 25; soft cheap 10 / regular 18 / premium 35 / nomad 12.
C.bottles = {
    matapang_coffee = { item = "Items.LowQualityDrink1", label = "Matapang Coffee", kind = "soft", tier = "Cheap", price = 10 },
    matapang_decaf = { item = "Items.LowQualityDrink2", label = "Matapang Decaf", kind = "soft", tier = "Cheap", price = 10 },
    dairing_dairy_milkshake = { item = "Items.LowQualityDrink3", label = "Dairing Dairy \"Milkshake\"", kind = "soft", tier = "Cheap", price = 10 },
    spunky_monkey = { item = "Items.LowQualityDrink4", label = "Spunky Monkey", kind = "soft", tier = "Cheap", price = 10 },
    spunky_monkey_mint = { item = "Items.LowQualityDrink5", label = "Spunky Monkey Mint", kind = "soft", tier = "Cheap", price = 10 },
    cirrus_cola_classic = { item = "Items.LowQualityDrink6", label = "Cirrus Cola Classic", kind = "soft", tier = "Cheap", price = 10 },
    cirrus_cola_corn_and_lemon = { item = "Items.LowQualityDrink7", label = "Cirrus Cola Corn and Lemon", kind = "soft", tier = "Cheap", price = 10 },
    cirrus_cola_blood_breeze = { item = "Items.LowQualityDrink8", label = "Cirrus Cola Blood Breeze", kind = "soft", tier = "Cheap", price = 10 },
    nicola_blue = { item = "Items.LowQualityDrink9", label = "NiCola Blue", kind = "soft", tier = "Cheap", price = 10 },
    nicola_can = { item = "Items.LowQualityDrink10", label = "NiCola", kind = "soft", tier = "Cheap", price = 10 },
    coffee = { item = "Items.LowQualityDrink11", label = "Coffee", kind = "soft", tier = "Cheap", price = 10 },
    coffee_with_syn_milk = { item = "Items.LowQualityDrink12", label = "Coffee with Syn-Milk", kind = "soft", tier = "Cheap", price = 10 },
    latte = { item = "Items.LowQualityDrink13", label = "Latte", kind = "soft", tier = "Cheap", price = 10 },
    nicola_fire = { item = "Items.MediumQualityDrink1", label = "NiCola Fire", kind = "soft", tier = "Regular", price = 18 },
    nicola_sakura = { item = "Items.MediumQualityDrink2", label = "NiCola Sakura", kind = "soft", tier = "Regular", price = 18 },
    real_water_still = { item = "Items.MediumQualityDrink3", label = "Real Water (Still)", kind = "soft", tier = "Regular", price = 18 },
    real_water_sparkling = { item = "Items.MediumQualityDrink4", label = "Real Water (Sparkling)", kind = "soft", tier = "Regular", price = 18 },
    naranjita_classic = { item = "Items.MediumQualityDrink5", label = "Naranjita Classic", kind = "soft", tier = "Regular", price = 18 },
    naranjita_zero = { item = "Items.MediumQualityDrink6", label = "Naranjita Zero", kind = "soft", tier = "Regular", price = 18 },
    chromanticore = { item = "Items.MediumQualityDrink7", label = "Chromanticore", kind = "soft", tier = "Regular", price = 18 },
    tiancha_kumquat = { item = "Items.MediumQualityDrink8", label = "Tiancha Kumquat", kind = "soft", tier = "Regular", price = 18 },
    tiancha_pomelo = { item = "Items.MediumQualityDrink9", label = "Tiancha Pomelo", kind = "soft", tier = "Regular", price = 18 },
    soulhiker = { item = "Items.MediumQualityDrink10", label = "Soulhiker", kind = "soft", tier = "Regular", price = 18 },
    oolong_tea = { item = "Items.MediumQualityDrink11", label = "Oolong Tea", kind = "soft", tier = "Regular", price = 18 },
    tiancha_pomegranate = { item = "Items.MediumQualityDrink12", label = "Tiancha Pomegranate", kind = "soft", tier = "Regular", price = 18 },
    tiancha = { item = "Items.MediumQualityDrink13", label = "Tiancha", kind = "soft", tier = "Regular", price = 18 },
    soop = { item = "Items.MediumQualityDrink14", label = "Soop", kind = "soft", tier = "Regular", price = 18 },
    sain_ruisseau = { item = "Items.GoodQualityDrink1", label = "Sain Ruisseau", kind = "soft", tier = "Premium", price = 35 },
    chromanticore_lime = { item = "Items.GoodQualityDrink2", label = "ChroManticore Lime", kind = "soft", tier = "Premium", price = 35 },
    vita_mine = { item = "Items.GoodQualityDrink3", label = "Vita-Mine", kind = "soft", tier = "Premium", price = 35 },
    chromanticore_carnival = { item = "Items.GoodQualityDrink4", label = "ChroManticore Carnival", kind = "soft", tier = "Premium", price = 35 },
    te_matcha = { item = "Items.GoodQualityDrink5", label = "Té Matcha", kind = "soft", tier = "Premium", price = 35 },
    te_sencha = { item = "Items.GoodQualityDrink6", label = "Té Sencha", kind = "soft", tier = "Premium", price = 35 },
    te_oolong = { item = "Items.GoodQualityDrink7", label = "Té Oolong", kind = "soft", tier = "Premium", price = 35 },
    vatnajokull_still = { item = "Items.GoodQualityDrink8", label = "Vatnajökull (Still)", kind = "soft", tier = "Premium", price = 35 },
    vatnajokull_sparkling = { item = "Items.GoodQualityDrink9", label = "Vatnajökull (Sparkling)", kind = "soft", tier = "Premium", price = 35 },
    water = { item = "Items.GoodQualityDrink10", label = "Water", kind = "soft", tier = "Premium", price = 35 },
    tomato_juice = { item = "Items.GoodQualityDrink11", label = "Tomato \"Juice\"", kind = "soft", tier = "Premium", price = 35 },
    filtered_rainwater = { item = "Items.NomadsDrink1", label = "Filtered Rainwater", kind = "soft", tier = "Nomad", price = 12 },
    cactus_juice = { item = "Items.NomadsDrink2", label = "Cactus Juice", kind = "soft", tier = "Nomad", price = 12 },
    abydos_classic = { item = "Items.LowQualityAlcohol1", label = "Abydos Classic", kind = "alcohol", tier = "House", price = 20 },
    abydos_king_size = { item = "Items.LowQualityAlcohol2", label = "Abydos King Size", kind = "alcohol", tier = "House", price = 20 },
    broseph_ale = { item = "Items.LowQualityAlcohol3", label = "Broseph Ale", kind = "alcohol", tier = "House", price = 20 },
    broseph_lager = { item = "Items.LowQualityAlcohol4", label = "Broseph Lager", kind = "alcohol", tier = "House", price = 20 },
    ["21st_stout"] = { item = "Items.LowQualityAlcohol5", label = "21st Stout", kind = "alcohol", tier = "House", price = 20 },
    bumelant = { item = "Items.LowQualityAlcohol6", label = "Bumelant", kind = "alcohol", tier = "House", price = 20 },
    chirrisco = { item = "Items.LowQualityAlcohol7", label = "Chirrisco", kind = "alcohol", tier = "House", price = 20 },
    pitorro = { item = "Items.LowQualityAlcohol8", label = "Pitorro", kind = "alcohol", tier = "House", price = 20 },
    tequila_especial = { item = "Items.LowQualityAlcohol9", label = "Tequila Especial", kind = "alcohol", tier = "House", price = 20 },
    pingo_palido = { item = "Items.MediumQualityAlcohol1", label = "Pingo Pálido", kind = "alcohol", tier = "Mid shelf", price = 45 },
    odickin_whiskey = { item = "Items.MediumQualityAlcohol2", label = "O'Dickin Whiskey", kind = "alcohol", tier = "Mid shelf", price = 45 },
    bolshevik_vodka = { item = "Items.MediumQualityAlcohol3", label = "Bolshevik Vodka", kind = "alcohol", tier = "Mid shelf", price = 45 },
    conine = { item = "Items.MediumQualityAlcohol4", label = "Conine", kind = "alcohol", tier = "Mid shelf", price = 45 },
    joe_tiels_okie_hooch = { item = "Items.MediumQualityAlcohol5", label = "Joe Tiel's Okie Hooch", kind = "alcohol", tier = "Mid shelf", price = 45 },
    papa_garcin = { item = "Items.MediumQualityAlcohol6", label = "Papa Garcin", kind = "alcohol", tier = "Mid shelf", price = 45 },
    blue_grass = { item = "Items.MediumQualityAlcohol7", label = "Blue Grass", kind = "alcohol", tier = "Mid shelf", price = 45 },
    donaghys = { item = "Items.GoodQualityAlcohol1", label = "Donaghy's", kind = "alcohol", tier = "Good", price = 90 },
    centzon_totochtin = { item = "Items.GoodQualityAlcohol2", label = "Centzon Totochtin", kind = "alcohol", tier = "Good", price = 90 },
    randver = { item = "Items.GoodQualityAlcohol3", label = "Randver", kind = "alcohol", tier = "Good", price = 90 },
    ab_synth = { item = "Items.GoodQualityAlcohol4", label = "Ab-Synth", kind = "alcohol", tier = "Good", price = 90 },
    champaradise = { item = "Items.GoodQualityAlcohol5", label = "Champaradise", kind = "alcohol", tier = "Good", price = 90 },
    la_perle_des_alpes = { item = "Items.GoodQualityAlcohol6", label = "La Perle des Alpes", kind = "alcohol", tier = "Good", price = 90 },
    calavera_feliz = { item = "Items.TopQualityAlcohol1", label = "Calavera Feliz", kind = "alcohol", tier = "Top shelf", price = 240 },
    chateau_delen_2012 = { item = "Items.TopQualityAlcohol2", label = "Chateau Delen 2012", kind = "alcohol", tier = "Top shelf", price = 240 },
    armagnac_massy = { item = "Items.TopQualityAlcohol3", label = "Armagnac Massy", kind = "alcohol", tier = "Top shelf", price = 240 },
    sake_utagawa = { item = "Items.TopQualityAlcohol4", label = "Sake Utagawa", kind = "alcohol", tier = "Top shelf", price = 240 },
    baalbek_arak = { item = "Items.TopQualityAlcohol5", label = "Baalbek Arak", kind = "alcohol", tier = "Top shelf", price = 240 },
    romvlvs_gin = { item = "Items.TopQualityAlcohol6", label = "Romvlvs Gin", kind = "alcohol", tier = "Top shelf", price = 240 },
    paul_night = { item = "Items.TopQualityAlcohol7", label = "Paul Night", kind = "alcohol", tier = "Top shelf", price = 240 },
    moonshine = { item = "Items.NomadsAlcohol1", label = "Moonshine", kind = "alcohol", tier = "Nomad", price = 25 },
    trailerbrew_beer = { item = "Items.NomadsAlcohol2", label = "Trailerbrew Beer", kind = "alcohol", tier = "Nomad", price = 25 },
    chromanticore_ultraviolet = { item = "Items.JudyDrink1", label = "ChroManticore Ultraviolet", kind = "soft", tier = "Special", price = 25 },
    kopi_kadal_coffee = { item = "Items.RiverDrink1", label = "Kopi Kadal Coffee", kind = "soft", tier = "Special", price = 25 },
    centzon_totochtin_indigo = { item = "Items.KerryAlcohol", label = "Centzon Totochtin Indigo", kind = "alcohol", tier = "Special", price = 60 },
}

-- Other bars, from the sheet's TELEPORT tab (entrances, not counters; walk the counter with
-- /pos before adding one):  Lizzie's Bar -1208.0, 1563.1, 22.9  ·  El Coyote Cojo -1260.8, -981.8, 11.6
C.bars = {
    afterlife = {
        label = "Afterlife",
        zone = { position = { x = -1453.0, y = 1016.7, z = 16.5 }, radius = 25.0 },
        -- the whole club: drinks may be carried anywhere inside; leaving it with an unpaid tab is
        -- a walkout. Matches rp_zones' `afterlife` (radius 50); the street entrance from the
        -- sheet's teleport (-1456.9, 1038.3) is 22 m from the centre, inside.
        venue = { position = { x = -1453.0, y = 1017.0, z = 16.6 }, radius = 50.0, maxHeight = 12.0 },
        society = "bar_afterlife",
        stations = {
            { position = { x = -1451.5, y = 1012.5, z = 17.8 }, label = "Afterlife - bar" },
        },
        -- where bottles and cans are grabbed. PLACEHOLDER next to the station: stand at the real
        -- cooler behind the bar and replace with /pos before going live.
        coolers = {
            { position = { x = -1454.8, y = 1010.4, z = 17.8 }, label = "Afterlife - cooler" },
        },
        stools = {},
        menu = { "broseph", "nicola", "odickin_rocks", "johnny_silverhand", "jackie_welles", "david_martinez" },
        -- bottles and cans this bar sells: "all", or { tiers = { ... } } to filter by tier, or a list of ids
        bottles = { exceptTiers = { "Nomad" } },
        color = "#FF5F58",
    },
}
