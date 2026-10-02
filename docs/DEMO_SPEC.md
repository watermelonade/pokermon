# Demo 2 spec: wake up as a dog, find the Aces, walk to Mossbank, play poker

The outcomes this demo must reach, written before the code (test-driven).
Each outcome has an ID; every ID is checked by at least one test, named in
the last column of its table. Work is done when `tools/test.sh full` passes.
Changing an outcome means changing this file first, then its tests, then
the code.

Placeholder writing throughout: the owner is bringing in writers. Keep lines
inside docs/WRITING.md's limits (tests/test_writing.gd checks them) and the
tone of docs/DESIGN.md's Story section: this opening is the heavy part.

## The loop

1. **The night (intro).** A new game opens on the night your owner, a bad
   poker player who takes his losses out on you, staggers home drunk and
   falls down an open manhole. His cards scatter; the four Aces go down
   with him. A few dialog lines over a dark screen and the street; no
   graphic detail.
2. **Morning in Sootbridge.** You wake as the dog in Sootbridge, a small
   soot-stained town, next to the manhole. Your deck (his deck) is missing
   the four Aces. No crew, some money (his dropped wallet).
3. **Find the Aces.** Four pickups around Sootbridge, each found a
   different way (see S-ACES). The deck is complete when all four are back.
4. **The road.** Sootbridge's way out is closed to you until the deck is
   complete ("Not without the Aces."). Then a short road, with a few
   townsfolk on it, leads to Mossbank.
5. **Mossbank's open table.** In Mossbank a street table is running. Talk
   to the players and you can sit in: a cash game, you against each of them
   (every seat for itself), a fixed buy-in from your money, leave after any
   hand, cash out what's in front of you.
6. **A crew.** After your first sit at the open table, win or lose, two of
   its players, Sage the Owl and Bandit the Raccoon, ask to come along: they
   join your crew. From there the existing demo carries on unchanged: Ridge
   Road's crews, Rosie's diner and lessons, the Mossbank Open.

## Decisions taken for this demo (the owner can change them)

- Town 1 is new: **Sootbridge**. The road is new: **the Mill Road**. Town 2
  is the existing **Mossbank**, entered from its west side.
- The missing cards are **the four Aces** (the painting's ace under the
  table). No simple card games yet: pickups only.
- **The dog has no crew until Mossbank.** While the party is empty, rival
  crews never spot you and the Regulars won't play ("Come back with a crew").
- Sage and Bandit, today's starters, become the two who join at the open
  table. A new game no longer starts with them.
- Rosie's lessons are offered the first time you walk into her diner, not
  at the end of the intro.
- Money, losing to crews (the diner wake-up) and everything after the
  open table work as today. Money as health, survival meters and the coin
  toss are later work (docs/DESIGN.md).
- Saves from before this demo load as runs that are past the opening: full
  deck, starters kept, standing where they saved.
- Quitting the game while seated at the open table loses the chips on the
  table: the buy-in is saved the moment you sit down, so quitting can't undo
  a bad session (the owner confirmed, 2026-10-01).

## Outcomes

### S: state and rules (unit tests, `tests/run_tests.gd`)

| ID | Outcome | Test |
| --- | --- | --- |
| S-NEW | `GameState.fresh()`: map `sootbridge` at its start cell, empty roster and party, money `STARTING_MONEY`, deck = 48 cards (all but the four Aces), `opening_done` false. | test_demo_state |
| S-DECK | `collect_card(card)` adds a missing card once (true), refuses a card already held (false); `has_full_deck()` true exactly when all 52 are held; `missing_cards()` lists what's missing. | test_demo_state |
| S-PICK | Each pickup has an id; `take_pickup(id)` gives its card once and records the id; taking it again gives nothing. | test_demo_state |
| S-SAVE | The deck, taken pickups, `opening_done` and `met_open_table` survive a save round trip exactly. | test_demo_state |
| S-OLD | A save written before this demo (no deck fields) loads with a full deck, `opening_done` true, its roster and party kept. | test_demo_state |
| S-PARTY | With an empty party, `WorldMap.spotter()` is never asked (or returns nothing) for crews: an empty-party dog walking into a crew's line of sight is not spotted. | test_demo_world |
| S-JOIN | `join_open_table_crew()` (after the first sit) adds Sage (owl) and Bandit (raccoon) to the roster and party once; calling it again adds nobody. | test_demo_state |
| S-CASH | A cash match (`CashMatch`, or TeamMatch in cash mode) seats you and 2-5 others each on their own team; every hand conserves chips; you can leave only between hands; leaving returns your stack; a busted rival leaves the table; the match ends when you bust, leave, or are the last one with chips. | test_cash_match |
| S-BUYIN | Sitting down takes the buy-in from your money (or refuses if you can't cover it); leaving adds your stack back. Money after = money before - buy-in + stack at leaving, exactly, over many seeded sessions. | test_cash_match |

### W: the world (unit tests on map data, `tests/run_tests.gd`)

| ID | Outcome | Test |
| --- | --- | --- |
| W-MAPS | Maps `sootbridge` and `mill_road` exist, pass the existing map checks (rows the same width, everything standing where it can stand), and every map's warps lead to a walkable cell on a map that exists. | test_demo_world (and test_world_map) |
| W-LINK | From Sootbridge's start cell, Mossbank (`town`) can be reached through warps and walkable cells when the gate is open; with the gate closed, it can't. | test_demo_world |
| W-ACES | The four Aces are all in Sootbridge: three as `pickups`, one as a townsperson's `gives_card`; each reachable from the start cell without passing the gate. One lies in plain sight within 10 steps of the start; one is given by a townsperson (talk to them); one is somewhere you have to go into (a building or a fenced yard); one is off the obvious path (behind something, at a dead end). | test_demo_world |
| W-GATE | Sootbridge's exit has a gate: blocked with fewer than 52 cards (with a line saying why), open with 52. | test_demo_world |
| W-NPCS | At least 4 townsfolk in Sootbridge (counting the one who gives an Ace), at least 2 on the Mill Road, at least 2 new ones in Mossbank; each has at least one line; none stands on a path cell that every route needs (removing any one NPC's cell from the walkable set never disconnects start from Mossbank). | test_demo_world |
| W-TABLE | Mossbank has an open table: a map entry with `open_table` (id, buy-in, players as species and individual, dealer kind), its players standing around a table, reachable from where the Mill Road enters. | test_demo_world |

### G: the game, scene tests (real scenes with autoloads, `tests/scene_tests.tscn`)

| ID | Outcome | Test |
| --- | --- | --- |
| G-INTRO | New game from the title: the intro plays (dialog advances with A), then you're walking in Sootbridge at the start cell, the player sprite is the dog, nobody follows you. | scene/test_opening |
| G-ACE | Stepping onto a ground Ace takes it: a line names the card and how many are left, the deck grows by one, the pickup is gone from the map, and it stays gone after save and continue. Talking to the Ace-giver gives theirs once. | scene/test_opening |
| G-GATE | Walking into the gate with Aces missing: a line, and you're still on the Sootbridge side. With all four: you walk through onto the Mill Road. | scene/test_opening |
| G-ROAD | Walking the Mill Road east arrives in Mossbank (map `town`) on its west side. | scene/test_opening |
| G-SIT | Talking to the open table's players offers a seat (yes / no); yes takes the buy-in and opens the table in cash mode with you (the dog's art) and the table's players. | scene/test_open_table |
| G-LEAVE | At the table, after a hand, Start (or B) offers to leave; leaving closes the table and adds your stack to your money; you're back where you stood. | scene/test_open_table |
| G-CREW | After the first sit (win or lose), Sage and Bandit join: they follow you, the party screen lists them, and Ridge Road's first crew now spots you. | scene/test_open_table |
| G-ROSIE | Rosie offers her lessons the first time you walk into the diner (not in the intro). | scene/test_open_table |

### J: the journey (end to end, `tests/scene_tests.tscn`, test_journey)

| ID | Outcome | Test |
| --- | --- | --- |
| J-LOOP | From the title, with no save: new game, intro, collect all four Aces (walking there and pressing buttons, as a player would), through the gate, along the Mill Road to Mossbank, sit at the open table, play at least 3 real hands (a bot in your seat), leave, Sage and Bandit join, save, quit to the title, Continue: everything as it was. No script errors anywhere. | scene/test_journey |
| J-OLD | The existing demo after the open table still works: a skipped Ridge Road match (`--match-result` style) pays and recruits as before. | scene/test_journey |

### R: regression (must stay green)

| ID | Outcome | Test |
| --- | --- | --- |
| R-UNIT | Every existing test in `tests/` still passes (changed only where this spec changes the rule it checks, and then in the same commit as the change). | tests/run_tests.gd |
| R-COMPILE | Every script compiles with the autoloads. | tests/compile_check.tscn |
| R-PAD | A pretend Xbox pad signals at the real table. | tests/pad_check.tscn |
| R-CHART | Bot-only 3v3 matches are unchanged: `tools/simulate.gd -- 8 123 --cycle` gives the same output as before this demo. | tools/test.sh full |
| R-PLAY | The playtester (taught the new opening) passes 20 fast runs and 1 real run, and its kill test. | tools/test.sh soak |

## Interfaces fixed up front

So the two build agents can work at the same time, these names are fixed
(stubs exist from the test commit; the agents fill them in).

- `GameState`: `deck: Array[int]`, `taken_pickups: Dictionary` (id -> true),
  `opening_done: bool`, `met_open_table: bool`; `collect_card(card: int) ->
  bool`, `has_full_deck() -> bool`, `missing_cards() -> Array[int]`,
  `take_pickup(id: String) -> int` (the card given, or -1),
  `join_open_table_crew() -> Array[Animal]` (who joined; empty if nobody).
  `const OPENING_MISSING := ["As", "Ah", "Ad", "Ac"]` (Card.parse format).
- `WorldMap`: maps `"sootbridge"`, `"mill_road"`; map keys `"pickups"`
  (`{"id", "cell", "card"}`; an Ace given by a townsperson is instead the
  npc entry's `"gives_card": {"id", "card"}`), `"gates"` (`{"cells":
  [Vector2i...], "requires": "full_deck", "text"}`), and npc entries with
  `"open_table": {"id", "buy_in", "players": [[species, individual], ...],
  "dealer"}`. Queries: `pickups()`, `gate_at(cell) -> Dictionary`,
  `open_tables() -> Array`.
- `CashMatch` (`src/match/cash_match.gd`): `add_player(name, chips, bot)`
  (each its own team), `start_hand()`, `play_bots()`, `can_leave()`,
  `leave() -> int` (your chips), `is_over()`, `seat_left(seat)`.
- `OpenTable` (`src/world/open_table.gd`): `static func play(overworld:
  Node, npc: Dictionary) -> void` (async: offers the seat, takes the
  buy-in, runs the table in cash mode, adds the cash-out, then calls
  `state.join_open_table_crew()` the first time and shows who joined).
  The overworld calls it from `_interact()` for an npc with `open_table`.
- `TableView`: `cash_game: bool` (set before adding the scene) and signal
  `left(chips: int)` (emitted once when you leave or the match ends);
  `seat_art` for seat 0 comes from `setup[0]["animal"]`, which for the dog
  is an Animal of species `&"dog"`.
- Tests can't pass command-line flags per test, so the dev flags a scene
  test needs are read from `Game.dev_args` as well as the command line:
  the table honors `Game.dev_args.has("autoplay")` (a bot plays your seat),
  and `match-result` already goes through `Game.dev()`.

## Test decisions

Where the outcomes above left something open that a test had to pin
down, the tests (written first) decided the smallest reasonable thing.
Changing one means changing it here, then the test.

Interfaces added or narrowed:

- **S-PARTY** can't check "never asked" from a unit test, so `spotter`
  takes the party's size: `WorldMap.spotter(cell, beaten, party_size :=
  GameState.PARTY_SIZE)`, and returns `{}` for 0. The overworld passes
  `state.party.size()`. (The default keeps every caller as it is today.)
- **S-NEW**: `WorldMap.START_MAP` is `"sootbridge"` and `START_CELL` its
  start cell.
- **S-CASH**: `CashMatch.new(seed := 0)`, and like TeamMatch it exposes
  `table: HoldemTable`, `bots` and `start_hand(stacked: Array[int] = [])`.
  You are seat 0, the first player added (with a null bot); each seat is on
  its own team. The first hand's button is HoldemTable's own (seat 0), so a
  stacked deck deals from seat 1. The blinds are CashMatch's to pick (the
  tests read them from the table), under 40 for the first hand. Rivals with
  a ScriptedBot are played by play_bots() like any bot. `leave()` mid-hand
  refuses: -1, nothing changes. After leaving, `is_over()` and
  `seat_left(0)` are true and `can_leave()` false; leaving after a bust
  returns 0.
- **S-BUYIN**: the money arithmetic is headless, in CashMatch:
  `static sit_down(state, buy_in) -> bool` (takes it, or refuses and takes
  nothing) and `static cash_out(state, chips)`. OpenTable uses them.
- **Pickups**: `pickups()` returns every pickup on the map, taken or not
  (the run knows which are taken). Pickup ids are unique across all maps,
  gifts' ids included; `take_pickup` works for both.
- **Gates**: gate cells are walkable tiles; the overworld refuses the step
  onto one while the deck is short and shows the gate's `text`, and lets you
  walk over it with 52. `gate_at(cell)` returns the gate's own dictionary.
- **Open table**: `open_tables()` returns the npc entries carrying an
  `open_table`, one entry per player (each with the same `open_table`
  dictionary), each standing beside a felt tile (`t`, 4-neighbour). Talking
  to any of them offers the seat. Its `players` include Sage (`[&"owl",
  0]`) and Bandit (`[&"raccoon", 0]`); `buy_in` is an int above 0, `dealer`
  a `Dealer.Kind`.
- **The table** honours `Game.dev_args["seed"]` as it does `--seed`, so a
  scene test's deal and bots are the same every run (G-LEAVE, G-CREW and
  J-LOOP use seed 7). J-LOOP needs the dog not to bust in its first three
  hands with that seed; if it does, change the seed here and in the test.

What the tests count as what:

- **"In Sootbridge"** is every map you can walk to from the start with the
  gate shut (its buildings included). **"New" townsfolk in Mossbank** are
  npc entries on `town` other than Bertram and Juniper and not the open
  table's players. W-NPCS removes one townsperson's cell at a time with
  nobody else standing, and the gate open.
- **W-ACES**, each of the three ground Aces a different one of: *in plain
  sight*, within 10 steps of the start on the start map (walking, around
  everyone standing); *somewhere you go into*, on an indoor map, or in a
  fenced yard: one cell (its way in) cuts it off from the start, and the
  part cut off is at least 4 cells with a fence (`F`) beside one of them;
  *off the obvious path*, on the start map at a dead end (one open
  neighbour) or where the walk is at least 6 steps longer than the
  straight-line (Manhattan) distance.
- **G-ROAD**: the Mill Road's warp to `town` is in its east half, and you
  arrive in Mossbank's western quarter (x < width / 4).
- **G-INTRO**: the player is the Critter with sprite id `"dog"`; a new game
  holds 48 cards.
- **G-ACE**: the line names the card as "<Rank> of <Suit>" ("Ace of
  Spades", any case) and the number still missing as a digit ("3"). "Gone
  from the map" is checked by behaviour: stepping off and back on says
  nothing and gives nothing, before and after save and Continue.
- **G-SIT**: the seat offer is the overworld's ChoiceMenu with two
  options, yes first. The table is the overworld's `table`, its `setup`
  holding the dog (seat 0, `animal.species == &"dog"`) and the table's
  players by name.
- **G-LEAVE**: once a hand is over, Start opens the offer to leave and A
  takes it (leaving is its first option, under the cursor). `left(chips)`
  fires once; your money is then money before - buy-in + chips; you stand
  where you stood when you talked to the player.
- **G-CREW**: you're told who joined (lines naming Sage and Bandit), the
  two follow you as `owl` and `raccoon` Critters, and "Ridge Road's first
  crew" is the Pond Hecklers.
- **G-ROSIE**: her offer is a menu whose title or options say "lesson";
  `tutorial_offered` stays false through the intro; entering the diner a
  second time asks nothing.
- **Starting a scene test part-way** (G-ROAD, G-SIT and on, J-OLD): the test
  writes a save from `GameState.fresh()` plus the four Aces
  (`collect_card`), `opening_done` and `seen_intro`, standing where it
  starts, and continues it from the title. So a new-format save with an
  empty roster must load with an empty roster (today's from_dict gives
  back the starting pair when the roster is short: that's for old saves).
- **J-OLD** recruits Honk from the Pond Hecklers; with Sage and Bandit
  seated, Honk joins the roster and waits on the bench (party stays 2).

## Who builds what

| Agent | Owns (only these files change on its branch) | Turns green |
| --- | --- | --- |
| Tests (first, alone) | `tests/` (harness, new tests), `tools/test.sh`, stubs for the interfaces above, CI | none: everything new is red, everything old green |
| World and opening | `src/world/` except open_table.gd, `src/game/`, maps, intro, assets for the dog, Sootbridge and the road, `tests/test_world_map.gd` and `tests/test_game_state.gd` where the rules change | S-NEW S-DECK S-PICK S-SAVE S-OLD S-PARTY S-JOIN W-* G-INTRO G-ACE G-GATE G-ROAD G-ROSIE |
| Open table | `src/match/cash_match.gd`, `src/world/open_table.gd`, `src/ui/` (cash mode, dog art at seat 0), `src/ai/` if needed | S-CASH S-BUYIN G-SIT G-LEAVE G-CREW |
| Integration (lead) | merges, `tools/playtest.gd` taught the new opening, docs | J-* R-* |

Neither build agent edits a test to make it pass. If a test is wrong, it
says so in its report and the lead decides (spec first, then test).

## Demo 2.1: the street game, and three fixes (2026-10-02)

The playtester found that the demo could become impossible to finish:
quit twice while seated before your first full session and the dog has $0,
no crew, a table it can't afford, and crews that won't play a dog alone.
The owner chose a street game in Sootbridge as the way back up (a first
piece of docs/DESIGN.md's safety net), and asked for the playtester's
other three findings to be fixed.

### The street game

- **Where:** Sootbridge, by the Lamp, before the gate (reachable from the
  start without a full deck). A few townsfolk play for pennies on an
  upturned crate.
- **Who can sit:** only a dog whose money is under the Mossbank open
  table's buy-in ("This game's for empty pockets."). It's a safety net,
  not a second income.
- **The stake:** no buy-in. The players front you a stake of chips that
  isn't yours. When you leave you keep what's above the stake; if you're
  below it, you owe nothing. So a session never costs money, and a good
  one pays a little.
- **Same table as the open table:** a cash game (CashMatch, TableView's
  cash mode), every seat for itself, leave after any hand.
- **Pace target:** about 10-15 minutes of play from $0 back to the open
  table's buy-in (docs/DESIGN.md, the safety net). Measured with a bot in
  your seat; reported, not a test gate.

### Outcomes

| ID | Outcome | Test |
| --- | --- | --- |
| S-STREET | A staked session: money after = money before + max(0, stack at leaving - stake), exactly, over many seeded sessions; money never goes down. Sitting is refused (nothing changes) when money is at or above the open table's buy-in. | test_cash_match (or a new unit file) |
| W-STREET | Sootbridge has a street table: an npc entry with `open_table` carrying `"stake"` (chips fronted) and `"max_money"` (sit only below it, = the Mossbank buy-in), its players standing round a crate or table, reachable from the start cell with the gate shut, none of them in the way (W-NPCS still holds). | test_demo_world |
| G-STREET | In the game: a dog with $0 in Sootbridge talks to the street game's players, sits without paying, plays (a bot in your seat), leaves, and its money grows by exactly the chips above the stake (or stays the same). A dog with money at or above the buy-in is turned away with a line, and nothing changes. | scene/test_street_game |
| J-STRANDED | The playtester's stranded case: a dog with $0 and no crew in Mossbank walks back to Sootbridge, plays street games until it can afford the open table, walks back, sits, and gets its crew. Run with a fixed seed and a bot in your seat; checks the demo can always be finished. | scene/test_journey |
| B-JOINSAVE | Fix 1: after the first open-table session, the save on disk already has Sage and Bandit in the roster with the Binder's "Mossbank, at the open table", in the same save as the cash-out (no save between the cash-out and the join). Quitting during the cash-out or the pair's lines and continuing loses nothing. | scene/test_open_table |
| B-CASHOUT | Fix 2: no frame exists where you've left the table but your stack isn't in your money and the save. Quitting on the very first frame after leaving and continuing keeps the stack. | scene/test_open_table |
| B-DECKFIX | Fix 3: loading a save repairs its deck: duplicates and invalid cards dropped; any card other than an Ace that's missing is put back; an Ace is held exactly when its pickup (or Mags's gift) is recorded as taken. A run then never gets stuck at the gate through a damaged file. | test_save_safety (or test_demo_state) |

R-* still holds: everything green, R-CHART unchanged, the soak green
with the playtester taught the street game (its `stranded` note becomes
a check: a stranded dog must be able to get back to the street game).

### Test decisions (2.1)

As for demo 2, where the outcomes left something open the tests (written
first) decided the smallest reasonable thing:

- **S-STREET**: the money arithmetic is headless, in CashMatch, beside
  sit_down and cash_out: `static sit_staked(state, max_money) -> bool`
  (true when money is under `max_money`; it takes nothing either way) and
  `static cash_out_staked(state, chips, stake) -> int` (adds
  max(0, chips - stake), returns what it added). The stake is your stack
  when you sit; the rivals sit with the same.
- **W-STREET**: the street table is found by its `open_table` carrying
  `"stake"` (the Mossbank table has none). Its players are npc entries on
  a map in Sootbridge (reachable from the start with the gate shut), one
  entry per player, each beside a crate (`x`) or felt (`t`), 4-neighbour.
  `max_money` equals the Mossbank open table's `buy_in`. With everyone
  standing and the gate open, Mossbank stays reachable.
- **G-STREET**: the offer is the overworld's ChoiceMenu, two options, yes
  first; sitting leaves money as it was; the table's setup gives seat 0
  (the dog) the stake. Turned away means: a line containing "empty
  pockets", no menu, no table, the run unchanged. The broke dog stands in
  Sootbridge past the opening (full deck, $0, no crew), a bot in its seat
  (seed 7).
- **J-STRANDED** starts as the playtester's stranded dog: past the
  opening, $0, no crew, never sat at the open table, at Mossbank's way in.
  Mossbank's table won't seat it (no menu). Each street session has its
  own seed (7, 8, 9, ...) and the bot in your seat gets up after the first
  hand that ends with its stack above the stake, when it busts, or after 8
  hands; at most 60 sessions. Then the open table: one hand, leave, and
  Sage and Bandit are in the roster.
- **B-JOINSAVE** reads the save on disk (`Game.save_path`) on the frame
  the cash-out line shows, and on the frame Sage's line shows; every save
  written after the table's `left` must already hold the pair. "Quitting"
  is going to the title without saving (a crash or a kill), then Continue.
- **B-CASHOUT**: the save on disk and the money are checked on the first
  frame after the table's `left(chips)` fires; then quit without saving and
  Continue.
- **B-DECKFIX**: a run past the opening (`opening_done`, which the gate
  sets only with all 52, and which a pre-demo save loads with) holds all
  four Aces, so loading it records all four pickups as taken; otherwise
  the taken pickups decide which Aces are held. Either way, after a load
  each Ace is held exactly when its pickup is taken, and every other card
  is held once. S-SAVE's odd deck (cards that aren't the rule's) becomes a
  legal one in the same commit.
