# Night City as a campaign (design v1)

The server plays like a tabletop campaign. One character, one life. Mistakes stick. Nobody is
handed anything. **There are no living legends in this city: only the strong survive, and you
only become a legend once you're dead.**

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
- **Debts they owed:** die with them. Bars eat the loss.
- **Apartments:** the lease ends; the flat goes back to El Capitan's listings.
- **Cars:** go to impound, then back on the market.
- **Businesses they ran:** the fixer appoints someone else.

## 4. Becoming a legend
The Afterlife names drinks after dead legends: that's how the Johnny Silverhand, the Jackie Welles
and the David Martinez got there. We do the same for players:
- A character who dies having done enough (fixer reputation, notable contracts, a long life) can
  be **named a legend by Rogue**. Their name goes on the Afterlife's wall and a drink is named after them.
- The player who played them writes the recipe, from the bar's ingredient list, and Rogue approves it.
  It goes on the menu for good.

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
