# Night City as a campaign (design v2)

The server plays like a tabletop campaign: one character, played for a long time, with a story of
their own. Mistakes stick and nobody is handed anything. **There are no living legends in this
city**, only characters who earned it.

Where tabletop rules help, we borrow from **Cyberpunk RED** (R. Talsorian's tabletop game, the
canon setting 2077 grew out of) rather than inventing our own.

## Why: make players care, keep them connected
When respawning is free, nobody cares and RP turns casual and reckless. The fix is not permadeath
from a stray bullet (that punishes bad luck and drives people away). It's two things together:
- **Going down is expensive and it sticks.** Bills, lost gear, time out, and a setback on your
  character's story. People negotiate, back off, pay for Trauma Team and hire a Solo because
  flatlining costs them something real.
- **Prestige is the long goal.** Every character has a story to finish. Finish it and they become a
  legend; then the player can retire them as a legend and start again with an edge. That keeps
  players invested in one character for weeks, and connected to the city across characters.

**Rule for every feature we add: going down must never be worth it.** No reward, payout or reset
should ever be easier to get by flatlining than by staying alive.

## 1. How a character ends
A character only ends in two ways:
- **Prestige:** a legend's player chooses to retire them (section 4).
- **Staff character death:** for breaking the rules (section 6).

Getting shot is never the end of a character. It's a bad night with a long tail.

## 2. Going down: down fast, not dead fast
**Damage is realistic.** Fights are short and ugly: a few hits put you on the ground. Everyone who
goes down gets a **bleedout timer**, so medics, the Trauma Team and support chrome always matter.
No dice: the clock is the clock.

| How you went down | Bleedout timer |
|---|---|
| Body or limbs | 90 s |
| Gut wound | 60 s |
| Head wound | 30 s |

(Tuning numbers; the point is that where you were hit matters.)

**Downed means neutralized.** A downed character **can't be targeted**: the game treats them as out
of the fight, so nobody can finish anyone off. They **can** still be restrained, carried, searched
and kidnapped: that's roleplay (snatch contracts, robbery), not violence.

**Stabilised stops the clock:** a Trauma Team medic, a medic player, a ripperdoc, or a bystander with
a Bounce Back / MaxDoc (real items, CONSUMABLES tab) who buys time rather than a full stabilise.
Stabilised characters are patched up where they lie and avoid most of the costs below.

### Your chrome decides how long you have
Support cyberware changes the timer (real items, CYBERWARE tab). That makes survival chrome a better
investment than combat chrome.

| Implant (tiers) | Effect while downed |
|---|---|
| **No support chrome** | the wound's timer, nothing else |
| **Blood Pump** (2 to 5++) | adds seconds to the timer, more per tier |
| **Biomonitor** (1 to 5++) | calls for help the moment you go down: pings on-duty medics and your Trauma Team plan with your location; higher tiers add a little time too |
| **Second Heart** (4 to 5++) | once per long cooldown (a real-time day or more), freezes the timer for a while; the most valuable implant in the city |
| **Adrenaline Booster** | lets you crawl to cover while downed |
| **Heal-On-Kill, Gorilla Arms, combat chrome** | nothing. Combat chrome helps you win fights, not survive losing them |

Implants are **server-owned** on Open//77 (the ripperdoc job records each install), so these bonuses
can't be faked. They compete for cyberware capacity, and they make the ripperdoc the job people
save up for.

## 3. Flatlining: what it costs
When the timer runs out, the character **flatlines** and **wakes up in a clinic**. What they wake up
with depends on their **coverage**:

| Coverage | You wake up... |
|---|---|
| **Trauma Team Platinum / Gold** | at a good clinic, chrome intact, the bill mostly or fully covered |
| **Trauma Team Silver** | at a clinic, part of the bill covered; the rest is yours |
| **No plan** | at whatever ripper someone dropped you at, with the whole bill |

**If you can't pay, the ripper takes it out of you**, in this order, until the bill is covered:
1. Your cash and bank.
2. **Your weapons** (whatever you were carrying, then your stash).
3. **Your cyberware:** removed, or swapped for cheap junk chrome. You can wake up missing an implant
   or with a worse one in its place.
4. **Your apartment:** the lease goes to cover the debt and the flat goes back on El Capitan's listings.

**Mercs get time to pay.** A vetted merc wakes up with the bill as a **debt with a deadline**
instead of losing their gear on the spot: their fixer's name is good enough for the ripper. Miss the
deadline and the ripper collects the same way, and the fixer remembers that you made them look bad.

**Also:**
- **Time out.** A **recovery period** (real minutes, longer for a head wound): lower max health, no
  fixer contracts, no gang work. Civilian jobs are fine.
- **No memory of it.** You don't remember the fight that put you down: who shot you comes from
  witnesses and fixers, not your own head (stops revenge without roleplay).
- **A setback on your story.** The step of your character's quest line you were on fails or slips back.
- **It compounds.** Several flatlines in a short time mean bigger bills and longer recovery.
- **Open tabs, deals and contracts** carry on: you still owe the bar, and a contract still fails if
  you can't finish it in time.
- This makes **coverage worth buying** (Trauma Team plans), **support chrome worth installing**, and
  **ripperdocs a real power in the city**: they hold people's chrome and leases.

## 4. Becoming a legend, and prestige
The Afterlife names drinks after legends: that's how the Johnny Silverhand, the Jackie Welles and the
David Martinez got there. Players earn the same **by completing their character's story**:
- Every character has an **in-city quest line** shaped by their lifepath and role: their origin's
  loose ends, their enemy, their fixers' biggest jobs, a name for themselves in Night City.
- **Finishing it makes them a legend.** Rogue knows the name. The character is at the peak.
- **Then the player chooses:**
  - **Keep playing** as a legend, for the roleplay.
  - **Prestige: die a legend.** The character goes out on their own terms in a scene the player
    helps write. Their name goes on the Afterlife's wall, their drink goes on the menu, and a new
    character starts the prologue.
- **Debts first:** a character can't prestige while owing anyone. Legends settle up.

**What a legend leaves the player**
- **Legacy experience** carries to the next character as **more starting skill**.
- **Legend status is the only source of extra starting skill.** Nothing else ever grants it: not
  money, not donations, not events, not staff.
- **A player badge** on the account, one per legend, shown on the profile and the Afterlife wall.
- Nothing else carries over: no money, gear, standing or property. Those belonged to the character.

**The legend's drink.** When a legend prestiges, the player gets the **legend's recipe screen before
character creation opens**:
- Name: always "The <character name>", like the canon three.
- Glass: pint, rocks or highball (the bar's glasses).
- Steps: 3 to 8, built from the bar's own pours, counts and beats, so the drink is pourable the
  moment it's approved.
- One line of flavour text, like the canon item descriptions.
- Price: 150 eddies, the same as the other Afterlife homages.

Staff approve it (in character: Rogue), then it's on every Afterlife bartender's menu. The player can
skip it and come back later; it never blocks making the new character.

## 5. Making a character (lifepath)
RED has characters pick a **Lifepath**: where they're from, family, a friend, an enemy, what drives
them. We use it at creation, and it seeds the character's quest line:
- **Origin:** Street Kid, Corpo, Nomad (the 2077 lifepaths) fixes where you start and who knows you.
- **Role** (RED's roles) leans you toward jobs:

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

## 5b. The prologue
Every new character, first or tenth, plays **the prologue**, and **the city doesn't open up until it
ends with you waking up on a ripperdoc's chair**, the way V wakes up at Vik's.

**Act 1: Origin (solo).** Street Kid in Watson, Corpo at Arasaka, Nomad in the Badlands, each with a
few variations so repeat players don't replay the same story.

**Act 2: The crew (2-4 new characters).** New characters who start around the same time are put
together by a starter fixer from their origin (Regina for Watson, Dakota for the Badlands, Wakako for
Japantown...). Everyone in it is new, so **you meet people you don't already know.**
- The matcher **mixes crews**: it avoids putting players who shared a crew before together again, so
  cliques don't just re-form with every new character.
- Nobody else starting? After a wait, an NPC partner fills in (the Jackie role).

**Act 3: Something goes wrong, and you wake up at a ripper.** Shot on the job, a wreck in the getaway,
bad chrome from a back-alley install, a dose that hit wrong, left for dead by the crew. Where you wake
up, and in what shape, depends on how the crew played it:
- **Shortcuts:** a clean job means a good ripper (Vik), little debt, and a fixer who knows your name.
- **Setbacks:** a botched job means a back-alley ripper, a bill from the first minute, a gang that
  remembers your face.
- **Betrayal** keeps the take but every fixer hears about it.

**After the ripper** the city opens: open jobs, a gang if you want the street's road (most mercs
start there, see FIXERS.md), then the fixers' auditions. Rogue and the Afterlife come only after
working with at least two other fixers (see JOBS.md).

The prologue can't be skipped, by anyone, however many characters they've had.

## 5c. Corpo or street
At the end of the Corpo origin a character chooses: **stay with the company**, or fall out of it and
end up on the street (the canon Corpo path, where V gets cut loose).

**Staying corpo** means power and funding, but **no cred**:
- **Merc safe zones are closed to you:** the Afterlife, Lizzie's, El Coyote Cojo, the Dogtown market,
  the nomad camps. The door is refused; pushing in makes you a hostile there.
- **No fixer licences**, and Rogue will never vet a corpo.
- **What you get instead:** well-paid corporate work, company housing, cars and gear, and corporate
  spaces the street can't walk into (Corpo Plaza offices, Arasaka Tower floors, Konpeki Plaza).
- **Hiring the street:** only through a fixer, never face to face in a merc bar.

**Corpo looks like easy mode. It isn't.** Corporate work is a target:
- **Their jobs are the street's jobs.** Fixers sell contracts on corpo jobs (FIXERS.md): intercept the
  package, hit the convoy, snatch the exec. Mercs get a district and a time window, never a live location.
- **Robbery, kidnapping, ransom.** Mercs can mug a corpo, tie them up and ransom them back to the
  company, paid through a fixer and held in escrow until the hostage is released.
- **It still has to be roleplay:** a contract, a demand, a ransom call.
- **Protection costs money:** Solo bodyguards through a fixer, gang muscle hired directly, corporate
  security, armoured cars, Trauma Team Platinum.
- **Failure costs:** a lost package or a ransomed exec means docked pay or a demotion, on top of the
  usual cost of flatlining.

**Leaving the company** is possible and **one way**: the corp takes back the flat, the car and the
gear. You start on the street with what's in your pockets and no cred.

## 6. Staying in character
- **Breaking character** (out-of-character talk in the world, metagaming) and **violence without
  roleplay** (attacking with no in-character lead-up, revenge for something your character never saw
  or doesn't remember) **result in character death**, applied by staff after reviewing the logs.
  No legend status, no legacy experience: the character simply ends.
- **Repeat offences result in a ban.**
- Fighting that comes out of roleplay is part of the city: a deal gone bad, Rogue's crew holding the
  Afterlife, a gang defending its turf, a contract.
- One out-of-character channel (reports and help), so nobody has to break character in the world.
- **Combat logging** (disconnecting while downed or mid-fight) counts as flatlining.
- **Platform bugs** (falling through the map, desync, a crash) are undone by staff from the logs.
  Every flatline keeps a record: who, where, the wound, the timer.

## 7. Rogue's rule
On the Afterlife clock you fight for the house. Run, hide or sit it out during an incident and Rogue
**zeroes you**: you flatline on the spot (it skips the timer), your vetting is revoked, and you're
barred from the Afterlife until she says otherwise. It's the hardest licence in the city to hold.

## Open questions
1. **Timer numbers:** 90 / 60 / 30 s by wound, and how much each chrome tier adds.
2. **Flatline costs:** how long is recovery, how long a merc's deadline runs, and how far back a
   flatline sets your quest line.
3. **Legacy experience:** how much starting skill one legend is worth, and does it stack (with a cap)?
4. **Rogue zeroing you:** a flatline plus a ban from the Afterlife (as written), or the one in-world
   thing that ends a character?
5. **Starting kit:** does each role get RED's starting gear, or does everyone start with nothing?
6. **Crews:** 2-4 players? How long before an NPC partner joins?
7. **Prologue length:** about an hour, one evening, or spread over a few sessions?
