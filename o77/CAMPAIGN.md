# Night City as a campaign (design v1)

The server plays like a tabletop campaign. One character, one life. Mistakes stick. Nobody is
handed anything. **There are no living legends in this city: only the strong survive, and you
only become a legend once you're dead.**

## Why: this rule exists to keep characters ALIVE
Permadeath is not a death mechanic, it's a **life** mechanic. When respawning is free, nobody cares
and RP turns casual and reckless. When one death ends a character, everyone in Night City changes
how they go about their business: they negotiate, back off, pay for Trauma Team, hire a Solo, think
twice before drawing on someone, and value the medic who keeps them breathing.

**Rule for every feature we add: dying must never be worth it.** No reward, honour, payout or
reset should ever be easier to get by dying than by living. Check new features against this.

Where tabletop rules help, we borrow from **Cyberpunk RED** (R. Talsorian's tabletop game, the
canon setting 2077 grew out of) rather than inventing our own.

## 1. One life
- A character who **flatlines** (dies and is not saved in time) is **dead for good**. The player
  starts a new character from scratch.
- Nothing in-character carries over: money, items, cars, apartments, reputation with fixers,
  licences, vetting with Rogue, job grades. All of it dies with them.
- The player's account remains (bans, admin notes, playtime), but the city has never heard of the
  new character.
- A dead character's name can't be reused for a new one.

## 2. Going down: Death Saves (from Cyberpunk RED)
In RED, a mortally wounded character makes a **Death Save** each round: roll a d10 and stay under
their BODY, with the target getting harder every roll. Fail once and they're dead. We do the same,
on a timer:
- **Downed** at 0 health: on the ground, can't fight, can talk and call for help.
- Every **N seconds** the server rolls a Death Save. Each roll is a bit harder than the last
  (RED's growing penalty). Fail, and the character flatlines.
- **Stabilised** stops the rolls: a Trauma Team medic, a medic player, a ripperdoc, or a bystander
  with a Bounce Back / MaxDoc (real items, CONSUMABLES tab) at a worse chance.
- A Trauma Team plan (upstream `rp_trauma`: Silver, Gold, Platinum) gets you a faster response,
  not immunity. The Trauma Team can arrive too late.
- The server rolls, never the client, and every roll is logged.

Upstream `rp_trauma` already does the downed state, stabilise, evacuate and Trauma Team plans. Its
`/respawn` (wake up at Vik's after a countdown) is what we replace with Death Saves and a real end.

## 3. What happens to a dead character's things
- **Their body can be looted** where they fell (open77_loot): what they carried is up for grabs.
- **Open tab at a bar:** charged from their accounts on the spot, no walkout fee (they didn't walk out).
- **Paid-now rounds:** refunded to their accounts as usual, then everything goes with them.
- **Debts they owed:** do NOT disappear. They stay recorded against the player's account, so dying
  is never a way out of debt. The new character doesn't pay them, but bars that were burned won't
  give that account a tab until the new character has been around for a while (cash and pay-now only).
- **Apartments:** the lease ends; the flat goes back to El Capitan's listings.
- **Cars:** go to impound, then back on the market.
- **Businesses they ran:** the fixer appoints someone else.

## 4. Becoming a legend
The Afterlife names drinks after dead legends: that's how the Johnny Silverhand, the Jackie Welles
and the David Martinez got there. Players can earn the same, but **for how they lived, not how they died**:
- Only a character who **survived a long time** (a real-time threshold, weeks not hours) AND built
  real standing (fixer reputation, notable contracts) can be named a legend by Rogue when they die.
  Dying early, recklessly or on purpose never qualifies, however famous the character was.
- Their name goes on the Afterlife's wall and their drink goes on the menu for good.

**The last thing a legend does: choose their drink.** When a qualifying character flatlines, the
player gets the **legend's recipe screen before character creation opens**:
- Name: always "The <character name>", like the canon three.
- Glass: pint, rocks or highball (the bar's glasses).
- Steps: 3 to 8, built from the bar's own pours, counts and beats (spirits, mixers, ice, a stir or
  shake, a garnish). The same pieces the bartender's minigame already plays, so the new drink is
  pourable the moment it's approved.
- One line of flavour text, like the canon item descriptions.
- Price: 150 eddies, the same as the other Afterlife homages.

It goes to staff (in character: Rogue) for approval, then onto every Afterlife bartender's menu.
The player can skip it and come back to it later; it never blocks making the new character.

## 5. Making a character (lifepath)
RED has characters roll or pick a **Lifepath**: where they're from, family, a friend, an enemy,
what drives them. We use it at character creation:
- **Origin:** Street Kid, Corpo, Nomad (the 2077 lifepaths) fixes where you start and who knows you.
- **Role** (RED's roles) maps to the jobs you can work:

| RED role | Jobs it leans into |
|---|---|
| Rockerboy | DJ, club acts, Rogue's door |
| Solo | security, bouncer, contracts for fixers |
| Netrunner | breach jobs, security contractor |
| Tech | mechanic, grid technician, weaponsmith |
| Medtech | clinic nurse, Trauma Team, street medic |
| Media | N54 photographer, braindance editor |
| Exec | El Capitan's car dealer and apartment agent, corporate courier |
| Lawman | NCPD (later) |
| Fixer | auditions with the NPC fixers, then brokering contracts |
| Nomad | trucking, convoys, Dakota's freight |

Role is a lean, not a lock: anyone can pour drinks.

## 5b. Starting again: the prologue
A new character doesn't waltz back into the Afterlife. Everyone, on their first character or their
tenth, plays **the prologue**: a short story with several paths that ends when the city notices them.
The canon game does the same: V and Jackie earn their way into the Afterlife through the heist.

**Act 1: Origin (solo, ~20 min).** Picked by lifepath: Street Kid in Watson, Corpo at Arasaka,
Nomad in the Badlands. Each has 2-3 variations so repeat players don't replay the same thing.

**Act 2: The crew (2-4 new characters).** New characters who start around the same time are put
together into a crew by a starter fixer from their origin (Regina for Watson, Dakota for the
Badlands, Wakako for Japantown...). The crew takes small gigs together: everyone in it is new to
the city, so **you meet people you don't already know.**
- The matcher **mixes crews**: it avoids putting players who were in the same crew in their last
  lives together again, so cliques can't just re-form after a death.
- Nobody else starting? After a wait, the crew fills with an NPC partner (the Jackie role) so no
  one is stuck.

**Act 3: The job.** One bigger gig for the crew, with branches:
- **Shortcuts:** a clean job gets the crew noticed: Rogue lets them through the Afterlife door, a
  fixer offers an early audition, a little starting standing.
- **Setbacks:** a botched job means owing the fixer (a debt to work off), the door stays shut until
  you do another job, or a gang remembers your face.
- **Betrayal is possible.** Bail on the crew or sell them out and you keep the take, but every fixer
  hears about it.

**After the prologue** the city opens up: the Afterlife door, the fixers' auditions, Rogue's vetting.
Players who knew each other in past lives can of course find each other again; they just meet
someone new first.

**Prologue rules**
- Deaths in the prologue are real (it's the same city), but its threats are tuned so careful play survives.
- The prologue can't be skipped, by anyone, however many characters they've had.
- Open jobs (Lizzie's, couriers, sanitation) work during the prologue, so new characters can earn
  their first eddies honestly.

## 6. Keeping permadeath fair
Permadeath only works if death is earned, so:
- **Combat logging is death.** Disconnecting while downed, or within a short window after taking or
  dealing damage, counts as failing every remaining Death Save.
- **Platform bugs are not death.** Falling through the map, desync deaths, a server crash: admins
  can restore a character from the logs. Every death keeps a record (who, what, where, the saves
  rolled) so a restore is a decision, not a guess.
- **Random killing has consequences.** Rogue bars people who shoot her staff (see JOBS.md). Later:
  NCPD, bounties, fixers refusing to work with known killers. Killing someone in this city should be
  expensive in reputation even when it's free in eddies.
- **No reward for dying.** A new character never starts with more than the last one would have:
  no fresh-start bonus, no inheritance, no faster unlocks.
- **Safe spots** where a player can't be attacked (character creation, the first few minutes in the
  city) are short and few.

## 7. Rogue's rule, now with real stakes
On the Afterlife clock you fight for the house or Rogue zeroes you, and zeroed now means **dead**.
That makes it the hardest licence in the city to hold, which is right.

## Open questions
1. **How long between Death Saves**, and how many before it's certain? (RED: every round; we need seconds.)
2. **Who rolls RED stats?** We could give characters a BODY stat at creation (affects Death Saves)
   or keep everyone equal and let cyberware and plans do the work.
3. **Restores:** admin-only, or a player appeal flow with logs attached?
4. **Starting money and gear:** RED gives each role a starting kit. Do we?
5. **Crews:** 2-4 players? How long should someone wait for a crew before an NPC partner joins?
6. **Prologue length:** about an hour, one evening, or spread over a few sessions?
