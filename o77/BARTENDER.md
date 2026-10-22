# o77_bar: bartender service loop (design v0)

Player-to-player table service at a bar. Replaces upstream `rp_bar`.

## Decisions (2026-10-22)
- **Players only.** No NPC customers.
- **Bartending is part-time.** Players drift between the bar, gigs and other city work, so:
  - Clocking in/out is instant and free, and only works inside the bar zone. Leaving the zone
    clocks you out (open tickets refund, see exit edges).
  - **No salary.** Pay comes only from served tickets (cut + tip). Fixes upstream AFK payroll.
  - Employment must not block gigs: gigs are open to anyone and live in a separate system,
    so holding the bartender job never stops someone taking a gig.
  - A customer who sits with no bartender on duty gets a **Ring for service** button, which
    pings employed bartenders who are online (on duty or not) with the bar name and distance.

## The loop

| # | State | Trigger | Customer sees | Bartender sees |
|---|---|---|---|---|
| 1 | `seated` | `open77_seating:seated` on a stool registered to a bar | small "Waiting for service" chip | blip on their tab rail: "Stool 3 - new customer" |
| 2 | `menu_open` | Bartender locks on the customer (look + E within 2.5 m) and picks **Hand menu** | Menu panel: the card, prices, descriptions; pick 1+ drinks | "Menu out" |
| 3 | `ordered` | Customer submits | "Order sent" | Ticket appears: drinks, stool, customer name |
| 4 | `awaiting_payment` | Bartender confirms ticket -> server sends bill | **Kiosk widget**: total, tip selector (0/10/15/20%), Pay cash / Pay bank | "Waiting on payment" |
| 5 | `paid` | Customer taps Pay -> server reserves the money (escrow) | "Paid. Your drink is being made." | Ticket turns green, "Make it" unlocked |
| 6 | `making` | Bartender at a station runs the pour/mix minigame, one drink at a time | (optional) sees bartender's animation | Pour/mix minigame |
| 7 | `served` | Bartender hands drink over (synchronized give) | Drink in hand / inventory | Ticket closes |
| 8 | `settled` | Server commits the escrow: till share, bartender cut, tip | receipt | earnings toast |

Exit edges, all refund in full from escrow and close the ticket:
- customer stands up (`open77_seating:stood`) before `served`
- bartender clocks off, leaves the bar zone, or disconnects
- order not started within N min of payment (config)
- either side cancels before `paid` (nothing held, nothing to refund)

## Money: one escrow per ticket (open77_transactions)
- `reserve` at step 5: lines = customer cash|bank -> `sys:o77_bar:<barId>` hold, total + tip.
- `commit` at step 8: hold -> till (society), hold -> bartender cut, hold -> bartender tip.
  All lines under one `opId = "o77bar:<ticketId>"`. Retry-safe: same id never pays twice.
- `cancel` on every exit edge before 8. In-doubt results are resolved by `status` before
  anything else moves (pattern from build-a-job docs / rp_salvage ledger).
- Ingredients are consumed in the same commit (bartender's station stock -> sys).

## Pour/mix minigame: client plays, server decides
Rule from the platform docs: a minigame may choose between outcomes the server allows, but
the client's answer is never the reason money appears. Money is already escrowed before
the minigame starts; the minigame only affects quality.

- Server issues a `pour ticket`: recipe steps (e.g. 45 ml spirits, 30 ml mixer, ice, shake 3 s),
  a random seed, and opens an `open77_actions` action with `durationMs` = the minimum
  realistic time. The server clock decides when it can finish.
- Client page: hold to pour (fill line on a glass, overshoot = waste), pick bottles in order,
  shake/stir timing bar. Sends back measured amounts per step.
- Server clamps and scores 0-100 against the recipe. Quality goes on the drink item metadata
  -> affects buzz strength/duration and the customer's default tip suggestion next time.
  A garbage score still produces a (bad) drink; the bartender can remake at ingredient cost.
- Reject submissions that arrive before the action's server-side end, or for a ticket not
  in `making`.

## UI surfaces (one WebUI page per side, our own, not the UI kit)
UI kit cannot do the minigame or a kiosk look (no custom CSS). We own focus, so we copy
the kit's release rules: focus released on Escape, death, disconnect, resource stop,
timeout, and a watchdog that drops focus if no panel is open.

- Bartender page: tab rail (stools + tickets), pour/mix minigame.
- Customer page: menu panel, kiosk payment widget, waiting chip.
- World layer (no focus): the tiered lock-in card from `open77_interactions` on each stool
  occupant, only for on-duty staff.

## Bars and stools are data
```lua
Bars.afterlife = {
  zone = { pos = vec(-1453.0, 1016.7, 16.5), radius = 25 },
  job = "bartender", society = "bar_afterlife",
  stools = { "furniture:<id>", ... },   -- from open77_furniture catalogue, verify in game
  stations = { { pos = vec(-1451.5, 1012.5, 17.8), yaw = 90 } },
  menu = "afterlife_card",
}
```
Open question: which Afterlife bar stools exist in `open77_furniture`'s catalogue
(`seating.near` at the bar will tell us). Unlisted stools need catalogue entries.

## Served drinks: held, not inventory (2026-10-22)
- **Mixed drinks never enter an inventory.** The bartender's finished glass is set on the counter in
  front of the customer's stool. The customer looks at it and presses E to pick it up.
- **In hand:** `Open77.animations.play(pid, "hold_item_walk", { item = drink.item })` with the drink's
  native record (`Items.TopQualityAlcohol8` for a Silverhand). Walk around holding it.
- **Sip:** `drink_walk` (or `bottle_walk`) with the same `item`, then back to `hold_item_walk`. Same
  record keeps the same prop, so the glass doesn't flicker. Each sip adds buzz; N sips empties it.
- **Slam it:** one long `drink_walk` that finishes the glass in a single go: all remaining buzz at
  once, and the glass is gone when the animation completes.
- **Put it down / drop it:** stop the animation (removes the animation-owned item). Death,
  disconnect and punching already clean it up (platform behaviour).
- **Only the customer it was made for** can pick it up (server checks the ticket).
- **Bottles are different:** a sealed bottle ordered off the menu IS an inventory item (the native
  consumable), handed over through the inventory system. Cocktails only come from a bartender.

Open item: placing the glass ON the counter. `Open77.props.create` takes curated aliases or a raw
`.mesh` depot path, not `Items.*` records. Need the drink models' mesh paths (find in game via the
RTTI tools, docs/rtti-testing) or a curated alias added for each glass.
