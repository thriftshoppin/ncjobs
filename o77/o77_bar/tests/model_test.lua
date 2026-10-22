-- Run from the resource folder: lua5.4 tests/model_test.lua
dofile("shared/config.lua")
local M = dofile("server/model.lua")
local C = O77BarConfig
local bar = C.bars.afterlife
local fails, runs = 0, 0
local function check(name, cond, detail)
    runs = runs + 1
    if not cond then fails = fails + 1; print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "")) end
end

-- pricing
local lines, sub = M.priceOrder(C, bar, { { drink = "johnny_silverhand", qty = 1 }, { drink = "broseph", qty = 2 } })
check("price lines", lines and #lines == 2)
check("subtotal", sub == 210, sub)
local merged = M.priceOrder(C, bar, { { drink = "broseph", qty = 1 }, { drink = "broseph", qty = 2 } })
check("duplicates merge", merged and #merged == 1 and merged[1].qty == 3)
check("not on menu", select(2, M.priceOrder(C, bar, { { drink = "nope", qty = 1 } })) == "not_on_menu")
check("zero qty", select(2, M.priceOrder(C, bar, { { drink = "broseph", qty = 0 } })) == "invalid_quantity")
check("float qty", select(2, M.priceOrder(C, bar, { { drink = "broseph", qty = 1.5 } })) == "invalid_quantity")
check("too many of one", select(2, M.priceOrder(C, bar, { { drink = "broseph", qty = 5 } })) == "too_many_of_one")
check("too many items", select(2, M.priceOrder(C, bar, {
    { drink = "broseph", qty = 4 }, { drink = "nicola", qty = 3 } })) == "too_many_items")
check("empty", select(2, M.priceOrder(C, bar, {})) == "empty_order")

-- tip and split always sum to the total
check("tip 15% of 180", M.tipFor(C, 180, 15) == 27)
check("legend drinks cost 150", C.drinks.jackie_welles.price == 150 and C.drinks.david_martinez.price == 150)
check("odd tip rejected", select(2, M.tipFor(C, 180, 13)) == "invalid_tip")
for _, subtotal in ipairs({ 0, 1, 20, 30, 179, 180, 999 }) do
    for _, pct in ipairs(C.tips) do
        local tip = M.tipFor(C, subtotal, pct)
        local s = M.split(C, subtotal, tip)
        check(("split sums %d/%d"):format(subtotal, pct), s.till + s.bartender == s.total and s.total == subtotal + tip)
        check(("split non-negative %d/%d"):format(subtotal, pct), s.till >= 0 and s.bartender >= 0)
    end
end

-- queue: one glass per unit
local q = M.queue(lines)
check("queue size", #q == 3)

-- difficulty by grade
check("recruit hardest", M.beatFor(C, 0).speed > M.beatFor(C, 3).speed)
check("boss widest", M.beatFor(C, 3).good > M.beatFor(C, 0).good)
check("unknown grade clamps", M.beatFor(C, 9) == C.shakeByGrade[3] and M.beatFor(C, -2) == C.shakeByGrade[0])

-- pour scoring
local sh = C.drinks.johnny_silverhand
local perfect = {
    { id = "tequila", ml = 60 }, { id = "agave", ml = 10 }, { id = "bitters", count = 2 }, { id = "ice", count = 2 },
    { id = "stir", hits = { "perfect", "perfect", "perfect" } }, { id = "lime", ml = 15 }, { id = "cerveza", ml = 30 },
    { id = "chili", count = 1 },
}
check("perfect = 100", M.scorePour(C, sh, perfect) == 100, M.scorePour(C, sh, perfect))
local sloppy = {}
for i, v in ipairs(perfect) do sloppy[i] = v end
sloppy[1] = { id = "tequila", ml = 75 }
check("sloppy < 100", (M.scorePour(C, sh, sloppy) or 100) < 100)
local huge = {}
for i, v in ipairs(perfect) do huge[i] = v end
huge[1] = { id = "tequila", ml = 1e9 }
check("huge clamps, still scores", M.scorePour(C, sh, huge) ~= nil)
check("nan refused", select(2, M.scorePour(C, sh, { { id = "tequila", ml = 0 / 0 } })) == "steps_mismatch")
local nan = {}
for i, v in ipairs(perfect) do nan[i] = v end
nan[1] = { id = "tequila", ml = 0 / 0 }
check("nan ml refused", select(2, M.scorePour(C, sh, nan)) == "invalid_pour")
local swapped = {}
for i, v in ipairs(perfect) do swapped[i] = v end
swapped[1], swapped[2] = perfect[2], perfect[1]
check("order matters", select(2, M.scorePour(C, sh, swapped)) == "steps_mismatch")
local wrongCount = {}
for i, v in ipairs(perfect) do wrongCount[i] = v end
wrongCount[3] = { id = "bitters", count = 9 }
check("count must match", select(2, M.scorePour(C, sh, wrongCount)) == "invalid_pour")
local badHit = {}
for i, v in ipairs(perfect) do badHit[i] = v end
badHit[5] = { id = "stir", hits = { "perfect", "great", "perfect" } }
check("unknown hit refused", select(2, M.scorePour(C, sh, badHit)) == "invalid_pour")

-- minimum time: Silverhand pours 115 ml, 3 presses, 3 beats
local min = M.minSeconds(C, sh)
check("min seconds plausible", min > 3 and min < 8, min)
check("beer min", M.minSeconds(C, C.drinks.broseph) > 3.5, M.minSeconds(C, C.drinks.broseph))

-- pour order carries glass and difficulty, no price
local t = { id = "T1", stool = "s1", customer = { name = "V" }, queue = q }
local o = M.pourOrder(C, t, 1, 2)
check("pour order glass", o.glass and o.glass.capacityMl == C.glasses.rocks.capacityMl)
local pint, rocks = C.glasses.pint, C.glasses.rocks
check("rocks shares the pint's foot", rocks.bottom == pint.bottom and rocks.base == pint.base)
check("rocks shares the pint's taper", math.abs((rocks.top - rocks.bottom) / rocks.height - (pint.top - pint.bottom) / pint.height) < 1e-9)
check("rocks holds less", rocks.capacityMl < pint.capacityMl)
check("beer fills the pint", C.drinks.broseph.steps[1].ml >= pint.capacityMl * 0.95)
check("pour order beat", o.beat == C.shakeByGrade[2])
check("pour order has no price", o.price == nil)

-- op ids are stable and distinct
local tk = { id = "abc", attempt = 1 }
check("op ids distinct", M.payOp(tk) ~= M.settleOp(tk) and M.settleOp(tk) ~= M.refundOp(tk))

-- every drink is a real base-game consumable
local known = {}
local f = io.open("../reference/console_commands/consumables.json")
if f then
    for rec in f:read("a"):gmatch('"record": "([^"]+)"') do known[rec] = true end
    f:close()
    for id, d in pairs(C.drinks) do check("native item " .. id, d.item and known[d.item], d.item) end
end
print(("model: %d checks, %d failed"):format(runs, fails))
os.exit(fails == 0 and 0 or 1)
