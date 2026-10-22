# Fixers: the contract engine (design v1)

**The loop:** a corpo takes a job; a fixer catches wind of it and puts a contract out; mercs take
the contract and go after the job. Corporate money creates the work, fixers sell it, the street does it.

## Where contracts come from
1. **Corpo player jobs.** When a corpo player takes a valuable job (see CAMPAIGN.md 5d), it becomes
   a target. A fixer in that district may post a contract against it after a short delay.
2. **NPC corporate activity.** Arasaka, Militech, Biotechnica and Kang Tao run their own NPC
   shipments, meetings and facilities, so there's work even when no corpo players are online.
3. **Clients who hire through a fixer.** Anyone, corpos included, can pay a fixer to put a contract
   out. The client never meets the mercs; the fixer is the middleman.

## Contract types

| Type | Objective | Done when |
|---|---|---|
| **Retrieval** | take a package, prototype, vehicle or data shard and bring it to the fixer's drop | the item is handed over at the drop |
| **Hit** | take out a target: an NPC exec, a guard captain, a rival crew leader | the target's death is credited to the crew |
| **Intel** | photograph a meeting, plant a bug, pull data from a terminal, tail a convoy | the intel reaches the fixer |
| **Sabotage** | blow up a shipment, a server rack, a generator; disable a convoy | the target is destroyed |
| **Snatch** | kidnap someone and deliver them alive, or hold them for ransom | the hostage is delivered, or the ransom is paid and they're released alive |

## How you're allowed to do it
Each contract says how, and that changes the pay and what counts as failing:

| Approach | Rules | Fails if |
|---|---|---|
| **Ghost** | nobody sees you | an alarm goes off, or anyone is killed who wasn't the target |
| **Quiet** | stealth preferred, force allowed | the target is warned before you get there |
| **Loud** | anything goes; explosives welcome | only if the objective isn't done |

Ghost pays most and costs reputation if you blow it. Loud pays least and brings the most heat later
(NCPD, the corp's security, the target's friends).

## What mercs know
- A contract shows the **district and a time window**, never a live position. Finding the target is
  part of the work.
- **Better intel costs money:** a fixer sells extra detail (route, guard count, the vehicle) for a
  share of the pay. An Intel contract done earlier can feed it.

## Money
- **Who pays:** the client (a rival corp, an NPC buyer or a player who hired the fixer). Rewards
  sit in escrow from the moment a contract is posted, so a finished contract is always paid.
  That's how upstream `rp_fixer` does it, and the bar's escrow works the same way.
- **The fixer's cut** comes off the top. The crew splits the rest.
- **Paid on done, refunded on fail.** Failed or expired contracts go back to the client.

## The corpo side
- A corpo whose job is hit **loses something real**: the package, docked pay, a demotion, a
  ransomed colleague.
- They can **protect a job:** hire Solos through a fixer, bring corporate security (other corpo
  players), take an armoured car, change the route.
- They sometimes **get a warning in character:** a contact whispers there's heat on the shipment.
  How often depends on their standing in the company. It gives them a chance, not a guarantee.

## Becoming a merc
**Merc is a status a fixer gives you, not a job you pick.** Fixers only send vetted mercs on contracts.
- **The usual road is through a gang.** A gang takes new blood after the prologue: initiation, small
  jobs on its turf, gang work for corpos (below). It's where most street characters learn the trade
  and build a name.
- **Vetting.** A fixer vets a merc after an audition contract, standing earned in gang work or open
  jobs, and no record of betraying a crew or a client. Vetting is per fixer, like all standing.
- **Exceptions** (a straight road to a fixer, no gang): nomads Dakota already knows, a prologue crew
  that came through clean (the fixer already has your name), or a vetted merc vouching for you.
- **You can be both.** A merc can stay in their gang. When a contract points at their own gang or its
  client, they choose, and the choice is remembered on both sides.
- **Not everyone fights.** Civilian work (the bar, the cooks, the mechanics, El Capitan's dealers)
  never needs a gang or a fixer's vetting beyond its own licences.

## Gangs: the cheap option
Mercs are professionals and only work through a fixer. **Lower-tier gangs** (Tyger Claws, Valentinos,
6th Street, Animals, Maelstrom, Moxes...) are muscle a corpo can **hire directly**, no fixer needed:
cheaper, faster to arrange, less reliable.

| Gang job for a corpo | What it is | Pays out |
|---|---|---|
| **Protection** | escort a corpo job (a courier run, a shipment, an exec) through their turf | a fee up front, a bonus if the job arrives intact |
| **Hired hustle** | intimidation, collections, leaning on a witness, shaking down a rival's people | on completion |
| **Dirty work** | the corpo's own sabotage or retrievals against a rival corp | on completion |

- **It's how contracts collide.** A corpo hires a gang to protect a shipment; a fixer has already sold
  a contract on that shipment to a merc crew. Gangs and mercs meet in the middle.
- **Turf matters.** A gang protects best on its own turf; outside it, it's just more targets.
- **Paid through escrow,** like everything else: the corpo's money is held when the deal is made and
  released when the job is done, so neither side can stiff the other.
- **Gangs can betray the client.** A gang that sells its own client to a fixer keeps both payments,
  but no corpo will hire that gang again for a long time.
- **Gang standing with corps** works like merc standing with fixers: reliable crews get better offers.

## Reputation
Every finished contract builds standing **with that fixer** (see JOBS.md: licences, auditions,
Rogue only after two other fixers). Failing, betraying a crew or breaking a contract's rules costs
standing, and a fixer who stops trusting you stops calling.

## Rules
- A contract is the story, so the violence it involves is roleplay, not random. Doing more than the
  contract asks (killing bystanders on a Ghost job, hitting someone who isn't the target) is not.
- Everything is permadeath on both sides. Mercs die on contracts too.
- **Hits on player characters** are the heaviest thing in the system: see the open question below.

## How it maps to the platform
- Retrieval: carrying (open77_actions carry), containers and drops (open77_transactions).
- Hit: kill credit, the way upstream `rp_fixer` credits cyberpsycho bounties.
- Intel: hacking (open77_hacking), photo capture (screenshots), terminals.
- Sabotage: world props, effects and explosions.
- Snatch: restraints and carrying (rp_ncpd's cuffs, open77_player_interactions), escrowed ransom.
- Stealth: NPC awareness and alarms. This needs checking against what the platform exposes.

## Open questions
1. **Hits on player characters:** allowed at all? If yes: only from top-tier fixers, a few a day,
   and the target always gets a warning? Or are player characters only ever robbed and kidnapped,
   with hits reserved for NPCs?
2. **Who funds NPC-sourced contracts:** the server (money created, capped per hour like upstream's
   mint rules), or only real player money?
3. **Crew size:** solo contracts, or always 2+ to keep people playing together?
