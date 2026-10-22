# Jobs stack audit (upstream Open2077/open77-resources @ 633bb55, 2026-10-13)

License: MIT (Open2077 contributors). Forking and releasing patched versions is allowed;
keep `LICENSE` and the copyright line in every copy. Exceptions in `NOTICE.md`: PolyZone (MIT),
Lucide icons (ISC), ArchiveXL/TweakXL (MIT), and `system/open77_shell/web/audio/lobby.mp3`
(Suno-generated, NOT MIT: do not redistribute it in our release).

## Size
- 777 Lua files, ~478k lines across system/, rp/, gamemodes/, libraries/, standalone/, examples/.
- Job-relevant: rp_jobs 2.1k, rp_bar 1.9k, rp_economy 2.5k, rp_inventory 5.7k, rp_bank 1.3k,
  open77_actions 7.0k, open77_transactions 5.3k, open77_interactions 5.8k, open77_uikit 2.3k.

## Platform layer (system/) - keep, build on
- `open77_transactions`: one atomic SQL op per id, receipts, idempotent retries, mint caps.
  This is the right money/item primitive. Use it for every job payout.
- `open77_actions`: server-clocked timed work with validate/reserve/commit/cancel hooks,
  spot claims, re-checks distance before paying. The right primitive for stations.
- `open77_interactions` / `open77_worldui` / `open77_zones` / `open77_uikit`: presentation.
  Fine as-is for the tiered panel.

## RP job layer (rp/) - problems found

### rp_bar (the bartender)
1. **Sale settlement is not atomic.** `settleSale` (server/main.lua:1063) makes five separate
   calls: customer cash remove -> barman pocket remove -> customer pocket add -> till add ->
   barman tip add, with hand-written refunds between them. A timeout or restart mid-way can
   take the customer's money without the drink, or duplicate a drink. Refunds can themselves
   fail silently. No operation id, so no safe retry.
   Fix: one `open77_transactions` op, all lines (cash, drink, till share, tip) under one id.
2. **Mixing time is decided by the client.** `craft` waits on the UI-kit progress bar, whose
   `ok` comes back from the client. A modded client can answer instantly.
   Fix: run mixing as an `open77_actions` action (server clock).
3. **Mixing and restock are also multi-call** with manual put-backs (same class as #1).
4. **One hard-coded counter.** Adding Lizzie's or El Coyote means copying code.
   Fix: counters become a list in config.
5. **Customers see nothing.** The counter POI is shown only to the on-duty barman; customers
   use `/bar` in chat. This is the opposite of the hovering lock-in panel we want.
6. **No NPC customers.** A bartender earns only from other players being online; otherwise
   only salary. Needs an NPC order queue to be a real job.

### rp_jobs (employment)
7. **Payroll pays AFK players.** Every 10 min, anyone on duty is paid from the society.
   No activity check: clock in and stand still = free money.
   Fix: pay per completed task, or require N task commits per payroll window.
8. **Payroll is two calls** (society remove, then wallet add, then refund on failure). Same
   atomicity issue. Fix: one transactions op with an id per (player, window).
9. One job per player, fixed 4 grades: acceptable for now; revisit for multi-job.

### Pattern across rp/
- 14 rp resources already use `open77_transactions` (fixer, salvage, streetfood, techie,
  nomade...). rp_bar and rp_jobs payroll are the outliers still doing raw economy calls.
  `rp_salvage/server/ledger.lua` is the reference shape to copy.

## Plan
- Fork lives on branch `o77-jobs`. Our code goes in `o77/` (new resources, prefix `o77_`),
  patches to upstream resources stay in place so diffs against upstream are clean.
- Phase 1: `o77_jobs` core (registry, duty, task engine, activity-based pay, tiered panel)
  + bartender rebuilt on actions/transactions with NPC customers and multiple counters.
- Patch upstream rp_jobs payroll (#7, #8) only if we keep rp_jobs; otherwise replace.
