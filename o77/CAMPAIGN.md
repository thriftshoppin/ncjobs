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

## 2. Going down: down fast, not dead fast
**Damage is realistic.** Fights are short and ugly: a few hits put you on the ground. But damage
puts you **down**, it doesn't kill you outright. Everyone who goes down gets a **bleedout timer**,
so medics, the Trauma Team and support chrome always matter. No dice: the clock is the clock, so
everyone knows exactly how long they have.

**Wounds set the timer.**

| How you went down | Bleedout timer |
|---|---|
| Body or limbs | 90 s |
| Gut wound | 60 s |
| Head wound | 30 s |

(Tuning numbers; the point is that where you were hit matters.)

**Downed means neutralized.** A downed character **can't be targeted**: not "damage doesn't land",
the game treats them as out of the fight. Nobody can finish them off. The only way a downed
character dies is the timer running out.
- They **can** still be restrained, carried, searched and kidnapped: that's roleplay (snatch
  contracts, robbery), not violence.
- The few deaths that skip the timer are applied by the system, never by another player's weapon:
  a fatal fall, standing on a point-blank explosion, being zeroed by Rogue, a staff character death.

**Stabilised stops the clock:** a Trauma Team medic, a medic player, a ripperdoc, or a bystander
with a Bounce Back / MaxDoc (real items, CONSUMABLES tab) who buys a bit of time rather than a full
stabilise. A Trauma Team plan (upstream `rp_trauma`: Silver, Gold, Platinum) gets help to you
faster, not immunity: they can still arrive too late.

### Your chrome decides how long you have
Support cyberware changes the timer (real items, CYBERWARE tab). That makes survival chrome a better
investment than combat chrome: killing faster doesn't keep you alive, staying alive does.

| Implant (tiers) | Effect while downed |
|---|---|
| **No support chrome** | the wound's timer, nothing else |
| **Blood Pump** (2 to 5++) | adds seconds to the timer, more per tier |
| **Biomonitor** (1 to 5++) | calls for help the moment you go down: pings on-duty medics and your Trauma Team plan with your location; higher tiers add a little time too |
| **Second Heart** (4 to 5++) | once per long cooldown (a real-time day or more), freezes the timer for a while when you go down; the rarest and most valuable implant in the city |
| **Adrenaline Booster** | lets you crawl to cover while downed |
| **Heal-On-Kill, Gorilla Arms, combat chrome** | nothing. Combat chrome helps you win fights, not survive losing them |

- Implants are **server-owned** on Open//77 (the server decides what a player has installed; the
  ripperdoc job records each install), so these bonuses can't be faked from the client.
- It competes for **cyberware capacity**: every slot spent on a Second Heart is one not spent on a
  mantis blade. That's the choice we want players to make.
- It feeds the **ripperdoc job**: support chrome becomes what people save up for.
- The timer runs on the server and every second of it is logged, so a death is a fact staff can check.

Upstream `rp_trauma` already does the downed state, stabilise, evacuate and Trauma Team plans. Its
`/respawn` (wake up at Vik's after a countdown) is what we replace with the bleedout timer and a real end.

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
The Afterlife names drinks after legends: that's how the Johnny Silverhand, the Jackie Welles and the
David Martinez got there. Players earn the same **by completing their character's story**, not by
dying and not just by surviving a long time:
- Every character has an **in-city quest line** shaped by their lifepath and role: their origin's
  loose ends, their enemy, their fixers' biggest jobs, a name for themselves in Night City.
- **Finishing it makes them a legend.** Rogue knows the name. The character is at the peak.
- **Then the player chooses:**
  - **Keep playing** as a legend, for the roleplay. Permadeath still applies.
  - **Die a legend and prestige.** The character goes out on their own terms in a scene the player
    helps write; they go on the Afterlife's wall and their drink goes on the menu. Then a new
    character starts the prologue.
- A legend who dies by any other means (the timer, a bad night) still gets the wall and the drink:
  they earned it while alive.
- A character who never finished their story is never a legend, however long they lived.

**The last thing a legend does: choose their drink.** When a legend dies or prestiges, the player
gets the **legend's recipe screen before character creation opens**:
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
tenth, plays **the prologue**, and **the city doesn't open up until it ends with you waking up on a
ripperdoc's chair**, the way V wakes up at Vik's.

**Act 1: Origin (solo).** Picked by lifepath: Street Kid in Watson, Corpo at Arasaka, Nomad in the
Badlands, each with a few variations so repeat players don't replay the same story.

**Act 2: The crew (2-4 new characters).** New characters who start around the same time are put
together by a starter fixer from their origin (Regina for Watson, Dakota for the Badlands, Wakako for
Japantown...). Everyone in it is new to the city, so **you meet people you don't already know.**
- The matcher **mixes crews**: it avoids putting players who shared a crew in a past life together
  again, so cliques can't just re-form after a death.
- Nobody else starting? After a wait, an NPC partner fills in (the Jackie role).

**Act 3: Something goes wrong, and you wake up at a ripper.** Every path ends with an incident that
puts the character in a ripperdoc's chair, and there are many ways it can go down: shot on the job,
a car wreck in the getaway, bad chrome from a back-alley install, a dose that hit wrong, left for
dead by the crew. Which ripper you wake up at, and in what shape, depends on how the crew played it:
- **Shortcuts:** a clean job with the crew intact means a good ripper (Vik), little debt, and a
  fixer who already knows your name.
- **Setbacks:** a botched job means a back-alley ripper, a bill you owe from the first minute, a
  gang that remembers your face.
- **Betrayal** keeps the take but every fixer hears about it.

**After the ripper**, the city opens: open jobs, a gang if you want the street's road (most mercs
start there, see FIXERS.md "Becoming a merc"), then **the fixers' auditions**. Rogue and the
Afterlife are NOT part of the prologue: you earn your way there by **working with the other fixers
first** (standing with at least two of them, see JOBS.md), and only then does Rogue agree to meet
you, vet you, and let you through the door.

**Prologue rules**
- Deaths in the prologue are real, but its threats are tuned so careful play survives.
- The prologue can't be skipped, by anyone, however many characters they've had.

## 5d. Corpo or street
At the end of the Corpo origin a character chooses: **stay with the company**, or fall out of it and
end up on the street like everyone else (the canon Corpo path, where V gets cut loose).

**Staying corpo** means power and funding, but **no cred**:
- **Merc safe zones are closed to you.** The Afterlife, Lizzie's, El Coyote Cojo, the Dogtown market,
  the nomad camps and the other places the street calls its own won't let a corpo in. The door is
  refused, and pushing your way in makes you a hostile there (in the Afterlife, Rogue's crew answers).
- **No fixer licences.** Fixers don't contract their businesses to corporate employees, and Rogue
  will never vet one.
- **What you get instead:** corporate work that pays well per job (security, exec errands, corporate
  courier, research), company housing, company cars and gear, and corporate spaces the street can't
  walk into (Corpo Plaza offices, Arasaka Tower floors, Konpeki Plaza).
- **Hiring the street.** Corpos can't walk into the Afterlife, but they can pay a fixer to put a
  contract out. Mercs take corporate money through a fixer, never face to face in a merc bar.

**Corpo looks like easy mode. It isn't.** The money is good because corporate work is a target:
- **Their jobs are the street's jobs.** When a corpo takes a valuable job (couriering a prototype,
  escorting an exec, moving company money), a fixer can put a contract out on it: intercept the
  package, hit the convoy, snatch the exec. Mercs get the district and a time window, never a live
  location, so it's a hunt, not a free kill.
- **Robbery, kidnapping, ransom.** Mercs can mug a corpo, tie them up, take them somewhere quiet and
  ransom them back to the company. Ransoms are paid through a fixer and held in escrow until the
  hostage is released alive, like the bar's pay-now (the same machinery, so nobody gets paid for a
  hostage who doesn't come home).
- **It still has to be roleplay.** A fixer's contract, a demand, a ransom call: that's the story the
  conduct rule asks for. Gunning down a corpo for no reason is still violence without roleplay.
- **And it's still permadeath.** A corpo who gets zeroed is gone like anyone else, company perks and all.
- **How corpos protect themselves:** hire Solos as bodyguards (through a fixer), corporate security
  run by other corpo players, armoured company cars, Trauma Team Platinum. What they can't do is hide
  in a merc bar.
- **Failure costs.** A lost package or a ransomed exec docks the corpo's pay or gets them demoted,
  so they can't just shrug it off.

**Leaving the company** is possible and **one way**: the corporation takes back its housing, cars and
gear, and the character starts on the street with what's in their pockets and no cred. Some fixers
will want to know why before they trust an ex-corpo. There is no going back to the company.

## 5c. Staying in character
The whole server only works if everyone stays in character, so the rules are blunt:
- **Breaking character** (talking out of character in the world, metagaming what your character
  couldn't know) and **violence without roleplay** (attacking someone with no in-character lead-up:
  random killing, revenge for something your character never saw) **result in character death**,
  applied by staff after reviewing the logs.
- **Repeat offences result in a ban.**
- Fighting that comes out of roleplay is part of the city: a deal gone bad, Rogue's crew holding the
  Afterlife, a gang defending its turf. The rule is about violence with no story behind it.
- Players get a single out-of-character channel (reports and help) so nobody has to break character
  in the world to deal with a problem.

## 6. Keeping permadeath fair
Permadeath only works if death is earned, so:
- **Combat logging is death.** Disconnecting while downed, or within a short window after taking or
  dealing damage, counts as the timer running out.
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
On the Afterlife clock you fight for the house or Rogue zeroes you, and zeroed now means **dead**
(a system death: it's the one kind that doesn't wait for a timer).
That makes it the hardest licence in the city to hold, which is right.

## Open questions
1. **Timer numbers:** 90 / 60 / 30 s by wound, and how much each chrome tier adds.
2. **Prestige:** does dying a legend give the player anything beyond the wall and the drink (an
   account badge, a title)? It must never give the next character a head start.
3. **Restores:** admin-only, or a player appeal flow with logs attached?
4. **Starting money and gear:** RED gives each role a starting kit. Do we?
5. **Crews:** 2-4 players? How long should someone wait for a crew before an NPC partner joins?
6. **Prologue length:** about an hour, one evening, or spread over a few sessions?
