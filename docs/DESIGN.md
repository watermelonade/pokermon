# Design summary

The full design doc, kept up to date, is here:
https://claude.ai/code/artifact/c284c9ac-3915-4b60-9293-ad0b666dede4

This is the short version, for code that needs to know the rules it's
implementing.

- **Pitch:** train the animals you meet to play team Texas hold'em, win a
  tournament in each of eight cities, and finish inside Cassius Coolidge's
  *A Friend in Need* (1903), the "Dogs Playing Poker" painting where a
  bulldog passes an ace under the table.
- **Story (2026-10-01; the opening built in demo 2):** you are a dog. Your owner, a bad
  poker player who took his losses out on you, falls drunk down a manhole
  and leaves his cards; a few went down with him. Recovering them is the
  first town's quest and the tutorial for the whole loop (simple card games
  with the cards you have, then poker once the deck is whole). Demo 2
  builds the first part (docs/DEMO_SPEC.md): the intro, Sootbridge with
  the four Aces to find (pickups only, no simple card games yet), a gate
  that won't let you leave without them, the Mill Road to Mossbank, and
  no crew until Mossbank's open table, where Sage and Bandit join you.
  Demo 2.1 adds the first piece of the safety net (below): a street game
  in Sootbridge, for a dog with less than the open table's buy-in, where
  the players stake you and you keep what's above the stake. Then low
  stakes tables to afford the next city, and so on up to the penthouse.
  Crew members each have their own reasons to stay (like Paper Mario's
  party). Tone: starts heavy, gets lighter, ends heavy (friendship, duty,
  community, what wealth does to people).
- **Money is health (not built yet; the demo still has the blackout):**
  your bank account is your only life bar. Going broke means "dying": you
  restart at your last save, losing everything since. Cash tables can be
  left any time; tournaments and winner-takes-all games can't.
  Winner-takes-all is how you recruit: the loser is wiped out and joins
  you (later, owes you instead). A coin toss decides whose deck is used,
  worth a small edge to its owner (to be measured). Recruits play with your
  money until they win their own. Wealth markers gate areas; once rich,
  purchases set save flags that the world reacts to in written ways, a
  light Sims touch, not a simulation.
- **Survival and hidden meters (not built yet):** money is the only
  number shown. Hunger, thirst, health, rest and tilt (which replaces
  Nerve) are hidden and nudge odds softly, never by thresholds; they show
  in the world (a slower walk, shaky paws on a tell). Food, water and
  shelter cost money daily (needs an in-game clock); shelter runs from
  alley to penthouse. A safety net (street games, odd jobs, a soup kitchen)
  gets you from nothing back to a few days' upkeep in about 10-15 minutes.
  (Built so far: Sootbridge's street game, demo 2.1, tuned to about that
  from $0 back to the open table's buy-in; README "Measured so far".)
  On the streets your crew stays, still indebted, and can work real jobs
  for you.
- **Discovery (not built yet):** one honest, hard path up, completable with
  no secrets; everything else is found, never taught: side routes with
  later in-world consequences (cutting corners, stealing, wholesome work)
  and trinkets that hook into existing systems (a dog whistle only dogs
  hear, a lucky coin for the coin toss). Built as data (item, hooks,
  effect, story flags), each with a test.
- **Jail (not built yet):** caught stealing means arrest and confiscation.
  Inside, money is worthless (commissary and favours), the sentence is
  worked off, there are prison card games, inmates and contacts found
  nowhere else. Out by serving, good behaviour, a bribe, your crew's bail,
  or a secret escape (you leave wanted).
- **Combat:** your crew of 3 against theirs at a 6-seat table, seats
  alternating. You play only your own seat and can't see teammates' cards.
  A crew is out when all its seats are busted. Bosses bring bigger crews
  (3v4, 3v5, up to 3v6 at a 9-seat table); later regions require a crew
  of 4.
- **Boss tables** (src/match/boss_table.gd): the boss crew brings the same
  total chips as yours over more seats (the leader two shares, each goon
  one), rigs the seat draw so its members sit either side of you and your
  teammates are split up, and has
  a leader: bust it and the goons stop signalling and play scared; get it
  thrown out and you win.
- **City 1's tournament (the Mossbank Open):** the early rounds are 3v3;
  the final is a 3v4 boss table against the Mossbank Regulars, led by
  Graves, with Lou the dealer asleep. It's the first taste of the uneven
  tables the regional boss tables build on (3v5, 3v6, bought dealers).
  (The full design doc's first version had city 1's tournament as a 3v3
  freezeout; the owner confirmed the 3v4 final.)
- **Team play:** soft play (no fighting teammates for chips), whipsaws,
  chip dumps, and secret signals on X, Y and the triggers (or the Steam
  Deck's back buttons). Bond
  decides how reliably teammates read signals.
- **Heat:** every signal raises the dealer's suspicion of the crew (more for
  each extra signal the crew makes in the same hand). 40: warning. 70: the
  crew is fined a dead big blind each. 100: the signaller is thrown out.
  Heat cools each hand. Street games have no dealer; a bought dealer barely
  sees the boss crew; getting a boss crew's leader thrown out wins. Careful
  animals stay under their comfort line; careless ones get caught.
- **Interception:** the crews watch each other's signals. Each gesture can
  be noticed by the other crew (watchful species like owls and cats see
  more; a crew's second and third signal in a hand are two and three times
  as easy to catch, so chatty and bigger crews leak more). Every crew has
  its own code, so a noticed gesture means nothing until a showdown shows
  what it meant; learned codes are kept for good (saved). A fake signal
  (held modifier) is ignored by your teammates and believed by rivals who
  have cracked that gesture. Bots use what they read: they respect a bettor
  who said "strong" a bit more and bluff into one who said "weak". It's a
  match setting: on at the player's tables, off for the type chart's
  bot-vs-bot balance.
- **Play styles form a cycle:** Bluffer > Rock > Maniac > Shark > Calling
  Station > Bluffer. `tools/simulate.gd` measures how close the bots are.
- **The Binder:** 25 species, 4+ recruitable individuals each, so a crew of
  one species is possible. Dogs only join after the finale, enough of them
  to recreate the painting.
- **Look and feel (decided 2026-10-02):** simple, old-school Pokemon
  style, Game Boy Advance era: 16x16 tiles, outlined 3/4 top-down
  characters, trainer-style "!" encounters, bottom-of-screen text boxes, a
  battle-menu-style table. Inspired by, never copied. The point: look
  simple, reveal unexpected depth at every turn. "Alive" comes from
  schedules, idle animation, day/night palette shifts and reactions, not
  from 3D. A Paper Mario-style 3D diorama look was mocked up and kept for
  later (mockups in the design doc), not the target.
- **Pillars added 2026-10-02:** Pokemon's structure with a real world's
  logic (actions, gestures and ignorance matter; the world lives on its
  own; fun from minute one, no tutorials), and simple on the surface,
  deep underneath.
- **Not built yet, from the 2026-10-02 brainstorm (details in the design
  doc):** poker is never explained in text; Sootbridge becomes a
  house-games town (high-low cards, matching, liar's dice, wheel, slots)
  that teaches poker's pieces, poker starts in Mossbank. Badges as pins on
  your collar (collar size = the budget): table badges give information
  or social edges, never better cards (Card Sense shows your hand's name,
  the newcomer's aid); world badges change house-game luck, hunger,
  prices; a badge economy (traded, won, counterfeit, cursed, worn by
  NPCs). A silent dog that answers with gestures (bark, wag, growl, sit);
  rule-matched dialogue lines that fit the moment and don't repeat. NPCs
  with money, jobs and habits on a daily tick, their fortunes shown
  through authored states (thriving to on the street).
- **Steam Deck:** 640x400 base resolution, integer-scaled to 1280x800,
  controller only, save between hands.
