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

## Who builds what

| Agent | Owns (only these files change on its branch) | Turns green |
| --- | --- | --- |
| Tests (first, alone) | `tests/` (harness, new tests), `tools/test.sh`, stubs for the interfaces above, CI | none: everything new is red, everything old green |
| World and opening | `src/world/` except open_table.gd, `src/game/`, maps, intro, assets for the dog, Sootbridge and the road, `tests/test_world_map.gd` and `tests/test_game_state.gd` where the rules change | S-NEW S-DECK S-PICK S-SAVE S-OLD S-PARTY S-JOIN W-* G-INTRO G-ACE G-GATE G-ROAD G-ROSIE |
| Open table | `src/match/cash_match.gd`, `src/world/open_table.gd`, `src/ui/` (cash mode, dog art at seat 0), `src/ai/` if needed | S-CASH S-BUYIN G-SIT G-LEAVE G-CREW |
| Integration (lead) | merges, `tools/playtest.gd` taught the new opening, docs | J-* R-* |

Neither build agent edits a test to make it pass. If a test is wrong, it
says so in its report and the lead decides (spec first, then test).
