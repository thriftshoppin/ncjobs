# Civilian jobs around Night City (brainstorm v1)

Legal, everyday work. Crime, NCPD, gangs and fixers come later. Places come from the TELEPORT tab
of the console command list (`o77/reference/console_commands/teleport.json`) unless marked.

## The big idea: most of these are the bar again

The bartender built a reusable core without meaning to:

| Piece | In the bar | Reused by |
|---|---|---|
| Customers at a spot (seats, queue, "ring for service") | stools | food stall, barista, restaurant, barber, tattoo, mechanic bay |
| Rounds + tab + pay now + walkout fee + debt | drinks | every service job that sells to players |
| Server-checked minigame at a station | pour / shake | wok toss, espresso, tattoo needle, engine diagnosis |
| Fetch tasks at a second spot | cooler grab | stockroom, parts shelf, fridge |
| Shift HUD + station board | bar screens | all of them, restyled |
| Part-time shifts, paid per job done, no AFK salary | clock in at the station | all of them |

**Proposal:** pull these out of `o77_bar` into a shared `o77_service` core. Each service job then
becomes a config (menu, stations, minigame steps) plus its own minigame page. The bar is the
reference consumer and keeps its 400+ checks.

Size: **S** config on the core, **M** one new mechanic, **L** its own subsystem.

## Service and hospitality (on the core)

| Job | Where | Loop | Signature mechanic | Size |
|---|---|---|---|---|
| **Bartender** | Afterlife, Lizzie's, El Coyote Cojo, Totentanz, Riot | done | pour, shake, stir | done |
| **Street food cook** | Kabuki market, Japantown, Jig-Jig Street | walk-up queue, cook, hand over; pay now only | wok toss / grill timing; food from the CONSUMABLES tab (Rammmmen, Burrito XXL, Hawt Dawg...) | S |
| **Barista** | a kiosk at Grand Imperial Mall or Corpo Plaza | order, pull a shot, steam, serve | grind and tamp pressure bar, milk-steam temperature; Matapang Coffee, Latte, Coffee with Syn-Milk are real items | S |
| **Restaurant server + cook** | Embers (Extra tab) | table seats, tabs, a cook and a server split the ticket | two-person ticket: server takes it, cook fires it | M |
| **Club DJ** | Afterlife, Totentanz, Riot, Lizzie's | play sets, read the room | crowd hype meter fed by people dancing nearby; high hype bumps every bartender's tips in the club | M |
| **Bouncer / door host** | 7th Hell, Riot, Totentanz, Dark Matter | cover charge, guest list, eject | pay-now cover at the door; a player tab can be refused at the rope if they owe debt | S |
| **Motel clerk** | No-Tell, Sunset, Sunshine motels | rent rooms by the hour or night | room keys tied to the player; a cleaning task between guests | M |

## Style and retail (on the core, player-to-player)

| Job | Where | Loop | Signature mechanic | Size |
|---|---|---|---|---|
| **Barber / stylist** | Kabuki, Japantown | customer sits in the chair, picks a look, stylist does it | live preview the customer approves before paying; uses the platform's appearance tools | M |
| **Tattoo artist** | Kabuki, Jig-Jig Street | design, place, ink | needle-steadiness minigame; a bad line costs the artist a redo | M |
| **Clothing shop clerk** | 12 clothing vendor spots | stock racks, fit, sell | fitting room preview; 1,538 real clothing records in the CLOTHING tab | M |
| **Weapon shop clerk** | 16 weapon shops | sell licensed weapons | waiting period and an ID check, later linked to NCPD records | M |
| **Junk dealer** | Frank, Christine Markov, Zhan Qiu (Junk Vendor tab) | buy scrap from players, sort it, sell components | sorting minigame; feeds the scrapyard and techie jobs | S |

## Transport and logistics

| Job | Where | Loop | Signature mechanic | Size |
|---|---|---|---|---|
| **Delamain cab driver** | Delamain's HQ | pick up a player fare, drive, drop off | meter runs on distance and time; the rider rates the ride, ratings unlock better cabs; fare is pay-now at the end, walkout fee if they bail | M |
| **Courier** | citywide | timed package routes on foot or bike | delivery windows; fragile packages that break if you fall | S |
| **Tow and impound** | Claire's Garage (NPC tab) | find flagged cars, hook, haul to the lot | owners pay to get cars back: reuses pay-now and debt | M |
| **Freight trucker** | Northside docks to Rancho Coronado | haul containers | load balance and a trailer that sways | M |

## Trades

| Job | Where | Loop | Signature mechanic | Size |
|---|---|---|---|---|
| **Mechanic** | Claire's Garage, Westbrook | player brings a car in, diagnose, quote, fix, paint | diagnosis minigame reads real damage; quote is pay-now or a tab the customer settles when they collect the car | M |
| **Grid technician** | citywide substations | city repair contracts | wiring puzzle; paid by the city (a society), not by players | S |
| **Clinic nurse** | Viktor Vektor, ripperdoc clinics (15 in the tab) | triage walk-ins, sell meds | Maxdoc and Bounce Back are real items (CONSUMABLES tab); a doctor player handles implants | M |

## Media, culture and city work

| Job | Where | Loop | Signature mechanic | Size |
|---|---|---|---|---|
| **Fortune teller** | Misty's Esoterica | tarot readings for players | 21 tarot cards with real locations in the tab: a reading can send the customer on a little tour | S |
| **Braindance editor** | a studio space (Judy's House is an NPC location) | record, cut and sell BD clips | timeline editor page | L |
| **N54 photographer** | citywide | shoot live events, sell the photos | photo mode capture judged on subject and framing | M |
| **Sanitation** | Municipal Landfill | truck routes, empty bins | route plus a compactor timing step | S |
| **Park keeper** | Reconciliation Park | upkeep tasks | light, social job for new players | S |
| **Real estate agent** | V's apartments in the tab (Japantown, Northside, Glen, Corpo Plaza) | show and lease flats to players | viewing tour, lease contract with rent; ties into `rp_housing` | M |

## Already upstream, worth reusing or rebuilding

`rp_streetfood` (grill stall), `rp_mecano` (repair, paint, impound), `rp_delamain` (taxi),
`rp_salvage` (scrapyard), `rp_techie` (workbench), `rp_chooh2` (farm and refinery), `rp_nomade`
(convoys), `rp_vigile` (security guard), `rp_medic` / `rp_ripperdoc`. Each needs the same audit the
bar got (AFK salary, money safety, client-trusted timers) before we build on it.

## Suggested order
1. Extract `o77_service` from the bar (no gameplay change; tests must stay green).
2. Street food cook and barista: smallest jobs on the core, prove it generalises.
3. Mechanic and Delamain driver: the two big player-to-player services.
4. DJ and bouncer: make the clubs feel alive around the bar.
5. Everything else by player demand.
