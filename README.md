# ncjobs

A jobs system for Night City on [OPEN//77](https://open2077.net), the Cyberpunk 2077 multiplayer
platform, built on a patched fork of the official
[Open2077/open77-resources](https://github.com/Open2077/open77-resources).

## What's here

| Path | What it is |
|---|---|
| `o77/` | **Our work.** New resources (prefix `o77_`), design notes, audits and reference data. |
| `o77/o77_bar/` | The bartender job: seat a customer, hand the menu, take payment at a kiosk, pour and mix, serve. |
| `o77/AUDIT.md` | What we found in the upstream job resources and why we rebuilt parts of them. |
| `o77/BARTENDER.md` | The bartender design: ticket states, escrow, pour checks, held drinks, bottles. |
| `o77/reference/console_commands/` | Base-game item, vehicle and teleport records as JSON, from the console command list. |
| everything else | The upstream resources, imported from `Open2077/open77-resources` @ `633bb55`. |

## The bartender (`o77/o77_bar`)

- **Players only, part-time.** Clock in at the bar's station, out by walking away. No salary:
  bartenders earn their cut and tips per served ticket.
- **The loop.** A customer sits; the bartender looks at them and presses E to hand the menu;
  the customer orders; the bartender sends the bill; the customer pays at a kiosk; the
  bartender pours cocktails at the station and grabs bottles from the cooler; then serves.
- **Money never half-moves.** Payment goes into escrow in one operation. Serving pays the till,
  the bartender's cut and the tip in one more. Standing up, the bartender leaving, a timeout or
  a server restart refunds the customer in full. Every operation has an id, so retries never
  charge or pay twice.
- **Canon drinks.** The Johnny Silverhand, The Jackie Welles and The David Martinez use the
  game's own item text and records. 74 base-game bottles and cans are on the menu too.
- **Pour and mix.** Hold to pour to a line, drop ice, shake or stir on the beat. The beat gets
  easier with the bartender's title. The server re-scores every pour and refuses one made faster
  than a person could.
- **Served drinks are held, not stored.** Cocktails and single bottles go on the counter to pick
  up, carry, sip or slam. Three or more of one bottle go into the inventory sealed.

Preview the screens in a browser: open `o77/o77_bar/web/bar.html`.

### Tests

```sh
cd o77/o77_bar
lua5.4 tests/model_test.lua     # pricing, splits, pour scoring, glasses, native item ids
lua5.4 tests/service_test.lua   # 20 ticket scenarios: escrow always ends at zero
```

### Status

The ticket logic and the screens are done and tested offline. Still to do before it runs in game:
the platform wiring (seats, economy, database, notifications), the client script, the counter
props, and walking the real cooler and stool positions.

## Licenses

- Upstream resources: MIT, Copyright (c) 2026 Open2077 contributors. See `LICENSE` and `NOTICE.md`.
- `system/open77_shell/web/audio/lobby.mp3` is **not included**: it is not covered by the MIT
  license (see `NOTICE.md`). Put your own track at that path if you want lobby music.
- `o77/reference/console_commands/` comes from a community console command list. Check its terms
  before making this repository public.
- OPEN//77 is an unofficial community project, not affiliated with CD PROJEKT RED. Cyberpunk 2077
  is a trademark of CD PROJEKT S.A. This repository contains no game files.

The upstream project's own README is kept as `README.upstream.md`.
