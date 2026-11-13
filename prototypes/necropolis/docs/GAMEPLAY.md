# Necropolis: gameplay

What the game is, what the player does, and why it's fun. Systems and formulas are in `MECHANICS.md`,
numbers and pacing in `BALANCE.md`, and the look in `VISUAL-LANGUAGE.md`.

## The ask (Shawn, 2026-11-13, verbatim excerpts)
> "the player should feel like they are building an autonomous collective of constantly streaming
> resources. they shouldn't worry about having certain quantities of undead, they should [worry]
> about the streaming quantities of undead coming in versus being removed."

> "I need to feel like the economies feed off each other, that Relish has a real risk of failure if
> she isn't prepared and dies, that she has a reason to go into dungeons to gather materials, that
> there is a tradeoff between taking in undead or leaving them to work vs sending them to Vei."

> "I need the fight with Vei to exist as a final test. Relish can use her backups to not die, but
> beating her beats the game."

Precedence when sources disagree: Shawn's vision > settled Realm BRIEF decisions > older Necropolis
notes > the Obsidian design doc. Every deviation is listed in `MECHANICS.md` §0.

---

## 1. The fiction in one paragraph
Relish was dead once, and she is not going back. Vei, She Who Weaves the End, is not death but the
passage: she ferries every soul onward, one step down the endless stair, no lingering. To Vei,
undeath is spiritual hoarding, cutting the queue. Relish's answer is a necropolis that never stops
moving: a town of tireless undead who work, haul, trade with the living and march. Every corpse the
realm produces is either Relish's material or Vei's next recruit. The war is a contest between two
currents. Vei recycles the dead back into the living; Relish keeps them walking. Pour more undeath
at Vei's gates than she can digest, and the queue clogs. Then she can be faced.

## 2. Pillars
1. **Streams, not stockpiles.** Every resource is a rate. The question is never "how many undead do I
   have?" but "how fast are they coming in, and how fast are they leaving?" The HUD answers with
   signed rates first.
2. **An autonomous collective.** The necropolis runs without you. Your job is to shape it (valves,
   policies, buildings, where Relish stands), then watch it stream. Commands are optimisation, never
   maintenance.
3. **Three scales, three feels, one language.**
   - **Macro** (the realm map): tidal and strategic.
   - **Economic** (Covington): rhythmic and constructive.
   - **Micro** (dungeons): tactile and immediate; your hand draws the circle.

   All three look like the same performance piece.
4. **Relish is the conduit.** She never attacks. Her army is her weapon, her shield and her health
   bar. Where she stands is the decision that matters most, because she can only be in one place.
5. **Preparation beats reflexes.** Death is real and costs time, loot and momentum. Backups buy it
   off, and you build them before you need them.
6. **Every control points at the current need.** Lists sort by what the next warden or front needs.
   Lanes say why they changed ("−1.2/s: Relish left"). Fort cards show the threat before you commit.
7. **Every scale feeds the others.** Nothing in one scene is self-contained. Loot builds the town,
   the town shapes the streams, the streams decide the war, and the war produces the corpses.

## 3. The three scenes

### 3a. The Realm (macro)
A pannable, zoomable map:
- Covington at the bottom right;
- Vei's domain at the top;
- twelve fortresses of the living between them, four tiers of three;
- villages scattered across the ground.

Everything you see is a flow. Green lanes carry your undead out from Covington. Orange lanes carry
the living Vei ships back to the forts. Matte grey gutters carry the corpses the garrisons ship to
her. The ground itself streams like a current toward Vei wherever the realm is losing matter.

**What you do here:**
- **Set the valve.** Covington's minted stream splits three ways, and the split is yours:
  - **WORK** goes home into the town's workforce, which grows the economy;
  - **WAR** marches on the fortresses, killing the living and making corpses;
  - **FLOOD** pours straight at Vei's gates, raising her backlog directly but feeding her the most.

  This is the core tradeoff of "taking in undead or leaving them to work vs sending them to Vei".
- **Move Relish to change the tide.** Click a fortress, then MOVE. Relish travels the map visibly.
  Where she stands:
  - Covington's war stream leans toward her;
  - **she redirects the dead shipment**: the corpses that fortress would ship to Vei are raised in
    place into undead instead, and those undead cost Vei far more to digest;
  - the dead near her catch her violet light.

  A fortress under Relish turns from Vei's supply depot into your recruiting ground.
- **Defend what you take.** Vei pushes back. Every few minutes she sends a **tithe wave**, a surge of
  the living into one fortress. It's telegraphed on the map well ahead, and it targets your held
  forts first. Relish standing there, or a big undead placed as a siege, blunts it. Her waves come
  faster as her queue clogs, so the closer you are to winning, the harder she fights.
- **Read the war at a glance.** Vei's domain shows three numbers: the backlog (a countable stack at
  her gates), the sustained differential (▲ or ▼, in/s), and the drain time. Her odds grow as the
  backlog grows.
- **Descend.** When Relish stands at a fortress, you can dive into it: its dungeon.
- **Bounce home.** Click Covington to dive into the town. One click, a short dive, and the routes
  become streets.

### 3b. Covington (economic)
A medieval fantasy town drawn in neon line, built up over the game from a crypt and a few huts into
a walled city with a market, an inn, a forge, a chapel of vats, an ossuary tower and a guildhall.

**What you see:** undead workers walking their loops, the living wandering between the market and
the inn, a stall where a living buyer and an undead seller trade, carts hauling bodies to the
charnel house, the forge sparking, and the crypt slab pulsing at the heart of it all.

**What you do here:**
- **Build.** Place buildings on open lots. Each costs gold, bone and relics (relics come only from
  dungeons). Each adds rates (more gold, faster minting, better quality, longer-lived workers,
  stronger backups) and new jobs.
- **Set how the undead behave on their own.**
  - **The job ladder:** drag jobs into the order the undead fill them (haul, mill, stalls, forge,
    pits, vats, build).
  - **Stances:** toggle named behaviours:
    - *Vigil*: tend the vats while Relish is away;
    - *Harvest*: haul when bodies run low;
    - *Thrift*: idle costly buildings when gold runs short;
    - *Muster*: send idle hands to war;
    - *Hearth*: keep the living happy.

    Each stance shows what it will do to your rates before you turn it on. You start with 2 stance
    slots and earn more.
- **Raise big undead at the crypt slab.** Only while Relish is home. Lay a husk on the slab, slot in
  remnants from dungeons, watch it take shape, hold to raise, name it. Big undead are the few you
  count by name. They lead dungeon parties, run a building as foreman, or break a fortress as a
  siege.
- **Build backups.**
  - **Clone vats** grow spare bodies for Relish, but only while staffed.
  - **A phylactery** lets her get back up once inside a fight.
  - **Simulacra** are limited-charge copies of her that raise the dead out on the map.

### 3c. Dungeons (micro)
Every fortress is a dungeon, seeded by its state on the map: as many living as it holds, as many
corpses as lie there, and your undead already fighting at its walls.

**What you do here:**
- **Guide Relish through the rooms.** Your undead advance and fight on their own, and the living
  fight back.
- **Draw circles.** Hold to enter trance: time slows and the essence ignites. Trace a circle around
  the essence motes. The fitted ring flashes over your trace with its score.
  - **The more perfect the circle, the better the undead.**
  - A big sloppy circle gives many weak chaff.
  - A small perfect circle gives a few strong ones.
- **Collect essence.** It drops from everything that falls, theirs and yours. Your fallen undead
  leave essence behind too, so a bloody room is a rich room.
- **Face the warden.** The last room holds the fortress's warden. It has its own mechanic, never just
  more HP:
  - telegraphed attacks that land on the tempo;
  - phases;
  - weak points your big undead can exploit;
  - a hunt for Relish herself.

  Before the door there's a last-chance beat: a free trance with every essence in the room lit.
- **Take the loot home:** relics, blueprints, husks and remnants for the slab, and essence.
  Beating the warden flips the fortress to your side on the map. You can also leave early with what
  you have.

### 3d. Vei (the final test)
Vei can be faced any time from her domain. The dialog shows your odds, the sign, the drain time and
each front's "have / need", so you choose the moment:
- Your backlog pours in as the horde, and your big undead lead it.
- Vei fights on **fronts** that each need a different strength: giants, swarms, carvers and raw
  power. Mass alone clears one; a balanced composition clears enough.
- Then the break. Vei is a ferry, and her ferry rate drains your horde. Relish raises at anchor
  points with her circles until your raise rate beats Vei's ferry rate for long enough, and she
  breaks.
- She hunts Relish. Every backup Relish spends shows as a cracked violet ring that doesn't come
  back.

**Win and you beat the game.** Lose and the queue drains: Vei digests about two-thirds of the
backlog. Relish's last death follows the usual rules: a clone if one is ready, otherwise she is
unmade for a while. The war goes on. Nothing ever resets.

## 4. How the economies feed each other

```
        WORK ──► Covington workforce ──► gold, bone, quality, backups, mint rate ─┐
 mint ──┼ WAR ──► fortresses ──► living die ──► corpses (yours) ──► haulers ──► bodies ─┤
 (slabs)│                     └► your undead die ──► corpses (shipped to Vei) ──┐  │
        └ FLOOD ──► Vei's gates ◄── undead drain ◄──────────────────────────────┤  │
                       │  Vei digests (corpses cheap, undead cost q) ──► living ships back
                       └► backlog = the win meter                                   │
 dungeons ◄── Relish descends ──► relics, blueprints, husks, essence ──► town ◄────┘
       └──► warden beaten ──► fortress flips ──► the tide turns on the map
```

- **Town → macro:** buildings raise the mint rate, worker lifetime, quality (which costs Vei more to
  digest) and the haulers' throughput. Policies change the split.
- **Macro → town:** WORK fills the workforce. Hauled corpses become bodies for the mint and bone for
  building. Held villages send living migrants who trade for gold.
- **Dungeon → town:** relics and blueprints are the only way to build the higher buildings. Husks and
  remnants are the only way to raise big undead.
- **Dungeon → macro:** a beaten warden flips the fortress. Raised undead join the stream at that
  fortress.
- **Town → dungeon:** big undead, quality, backups.
- **Everything → Vei:** the backlog.

## 5. The decisions the player keeps making
1. **Where is Relish?** In a dungeon she earns loot and flips a fort. On the map she turns the tide
   and redirects the dead. At home she raises big undead and runs the crypt. She can't do all three.
2. **How is the stream split?** WORK builds the future. WAR makes corpses and pressure but feeds Vei
   with every garrison kill. FLOOD raises the backlog now, but cheaply for her if quality is low.
3. **What do I build next?** Every building is a rate tradeoff, and the best ones need dungeon loot.
4. **Which dungeon?** Each fortress card hints at its loot. Your town's weakness points at the
   dungeon that fixes it.
5. **Am I ready to risk her?** Every fort card shows the warden, its tell, the loot hint and the
   death risk *before* you descend. A death without a staffed vat costs a long respawn and unbanked
   loot, and the town's morale wavers.
6. **Which fort do I defend?** Tithe waves are telegraphed. Relish or a big undead can blunt one, but
   not every one.
7. **When do I face Vei?** The odds, the sign and the drain time are on screen. Your composition
   decides the fronts.

## 6. The opening (the first 10 minutes)
1. **0:00, the map.** One line at the top: *"Clog Vei's queue until she can be faced."*
   - The valve glyph at Covington pulses.
   - Drag it, and within 5 s the lanes brighten.
   - The workers' steady-state number shows where WORK is heading.
2. **0:30.** The nearest fortress, Old Sluice (tier 1), pulses as **"your first dungeon"**. Its card
   already shows the warden (a Bellringer), its tell, the loot hint and the risk ("low").
3. **1:00.** Click it, then MOVE. Relish travels; time controls (1×/2×/4×) are in the corner. While
   she walks, click Covington to dive into the town.
4. **1:30, the town.** Already built: the crypt, one raising pit, a charnel house and a small market.
   Ten living, a dozen workers walking. A starter stock of gold and bone buys the first house or bone
   mill right away.
5. **3:00, the descent.** A guaranteed starter party. The first trance is taught in-world: the
   essence glows, and a ghost ring shows where to draw. The Bellringer's slams are slow. The chest
   holds the first blueprint and **a husk**.
6. **8:00, home.** The slab lights up: raise your first big undead and name it. The first flip shows
   on the map, then the first tithe warning, 4 minutes out, at your new fort.

**The first death is taught, not sprung.** The first dungeon is "low" risk, and the descend
dialog says what a death would cost right now.

## 7. The arc of a game (about 3–4 hours of active play)
- **0–20 min, the crypt and a trickle.** One slab, a handful of workers, the first WAR stream, the
  first corpses hauled home. Build the charnel house and a market. The first dungeon is the nearest,
  weakest fort, where you learn the circle.
- **20–60 min, the town wakes.** The living arrive and trade. Your first policies. A first clone vat.
  The first warden beaten, the first fort flipped. The first big undead from the slab.
- **1–2 h, the realm leans.** The necrosis creeps across the ground. You juggle WORK and WAR. A
  forge pushes quality up, so each undead costs Vei more. Relish's tide pulls fortresses over one
  by one. Higher buildings, gated by relics, change what the town can do.
- **2–3 h, the queue clogs.** FLOOD opens. The backlog climbs and the differential holds ▲. The
  drain time shows how long it would last if you stopped. You build backups and assemble a
  composition for the fronts.
- **3–4 h, the final test.** Vei. Win, and the game is beaten. Lose, and you rebuild the backlog,
  wiser.

## 8. Feel targets (what the reviewers check)
- Within 2 minutes you have set the valve, watched a stream respond, and seen the town move.
- Leaving the game alone never wins, but the collective visibly keeps working.
- At any moment the player can say whether they're winning (the ▲/▼ beside the odds) and why (which
  stream changed).
- Each scene has its own verb:
  - macro: commit and redirect;
  - economic: build and set rules;
  - micro: draw.

  No scene borrows another's verb.
- Death stings and is never arbitrary: the risk shows before the descent (the warden's tells, the
  party's strength, the backups ready).
- Nothing piles up meaninglessly. Every resource has a sink that matters (rule: no stock grows
  without bound in a 4-hour run).
