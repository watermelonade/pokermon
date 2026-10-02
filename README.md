# A Friend in Need

A whimsical pixel-art RPG where you train the animals you meet to play team
Texas hold'em, travel from town to town winning tournaments, and finally sit
down inside the painting *Dogs Playing Poker*. Built in Godot 4 for the
Steam Deck first. The full design is in the
[design doc](https://claude.ai/code/artifact/c284c9ac-3915-4b60-9293-ad0b666dede4)
(summary in [docs/DESIGN.md](docs/DESIGN.md)).

This is the starter project: the poker rules, the hand evaluator, the AI play
styles, team signals, a playable placeholder 3v3 table, and a demo loop
around it: a title screen, an opening (you are a dog whose owner fell down a
manhole; find the four Aces of his deck in Sootbridge, walk the Mill Road),
the town of Mossbank and its open table, Ridge Road, four rival crews who
spot you and deal you in, recruiting, blackouts, saving, and the town's
tournament. The first goal is to find out whether one table is fun.

**Art:** placeholder pixel art in a GBA-era top-down style (Endesga 32
palette): the six species, the player and townsfolk as 4-direction walk
sheets, portraits, and overworld and interior tiles. It's generated from text
grids by `tools/make_art.gd`, so it can be tweaked in a text editor until it's
redrawn in Aseprite; see [assets/README.md](assets/README.md). To look at it
all: `godot --path . res://scenes/dev/art_preview.tscn`.

## Running it

Install [Godot 4.7](https://godotengine.org/download) (the standard build;
the .NET one isn't needed), open `project.godot` in it, and press F5. That
starts the title screen; to play just the table, open `scenes/table.tscn`
and press F6 (or `godot --path . scenes/table.tscn`).

### The demo

A new game opens on the night it happened: your owner, a bad poker player
who takes his losses out on you, staggers home from the Lamp and falls down
an open manhole, and the four Aces of his deck go with him. You wake in the
morning as the dog, alone, by the manhole in Sootbridge, with his wallet
($200) and a deck of 48. The Aces turned up around town: one in the gutter
a few steps away, one up the washhouse's floor drain, one at the dead end
of the coal yard's alley (behind the crates), and Mags the drain possum
found the fourth (talk to her). Step on a card to take it; a line says
which and how many are still missing. The gate east says "Not without the
Aces" until you have all four, then lets you onto the Mill Road, which
comes into Mossbank on its west side. A few townsfolk along the way have
a line or two (some of them hints).

A dog alone is nobody a crew deals in: no crew spots you, and the
Regulars send you off ("Come back with a crew"). In Mossbank, by the pond,
a street table is running (the open table): talk to a player to sit in for
a $100 buy-in, a cash game, every seat for itself, leave after any hand
with your stack. After your first sit, win or lose, Sage the Owl (Rock)
and Bandit the Raccoon (Bluffer) join you and follow you (the cash game is
the open-table work in `src/match/cash_match.gd` and
`src/world/open_table.gd`). Lose your wallet there before they join
(quitting while seated forfeits the buy-in) and you're a dog alone that
can't afford the table: back in Sootbridge, outside the Lamp, three
townsfolk play for pennies on a crate, and they'll stake a broke dog (the
street game, below). From there the demo is as before. The Mossbank Open is at the
Tournament Hall at the east end of Ridge Road. Along the road, four rival
crews stand watching: walk into one's line of sight and a "!" pops up, it
walks over, has its say, and you're at the table (no dealer on the road, so
signal freely). Win and they pay up, and you can ask one of them to join
you; lose and you wake up at Rosie's Diner with half your money, and the
crew will deal you in again. Two of the crews block the road; the other
two can be walked around. In the hall, talk to the Mossbank Regulars to
play the Open's final (the dealer's asleep): a 3v4 boss table, four
Regulars against your three, Graves leading on a big stack with the seat
draw rigged around you (see "Boss tables" below); winning gives you the
first bracelet and the demo-complete screen. Start (or Tab) opens the menu: Crew (pick
which two animals sit with you), Binder, Save, Options (text speed, volume).

The Binder is the collection: 25 card pockets on one page (the demo's six
species, 18 locked "???" slots for the full game, and a dog silhouette that
"won't sit at your table... yet"). A species you've only sat across from
shows greyed, with its style, where you met it and which of its four named
animals you've met (with each one's bio); once one joins, the card is in colour and its back
fills in (tell, favourite snack, your animals' bond). The counter is
species recruited of 25. Bond grows each match an animal sits with you
(+0.05, or +0.1 for a win, capped at 1.0; "Sage's bond grew!" after the
match), and bond is how often it reads your signals right: 60% at a
recruit's 0.2, every time at 1.0.

The look and feel is a handheld RPG of the Game Boy Advance era: grid
steps with a walk cycle, a "!" when a crew spots you, a bordered text box
along the bottom, a diner for a healing centre (talk to Rosie and rest your
crew in a booth; there's nothing to heal yet, so it's ritual and a save), a
Start menu in the corner.
Inspired by, never copied: every name, map and drawing here is original.

The game saves itself after every match, at every door, and when the
window loses focus; Continue on the title picks up from there. Saves are
JSON in `user://save.json`, which with the custom user dir set in
project.godot is `~/.local/share/AFriendInNeed/` on Linux and the Deck,
`%APPDATA%\AFriendInNeed\` on Windows.

| Overworld | Keyboard | Controller (Xbox-style) / Steam Deck |
| --- | --- | --- |
| Walk | arrows or WASD | D-pad or left stick |
| Talk, read, confirm | Enter / Space | A |
| Back | Esc | B |
| Menu (Crew, Binder, Save, Options) | Tab / Esc | Start |

| Table | Keyboard | Controller (Xbox-style) / Steam Deck |
| --- | --- | --- |
| Move the cursor in the command menu (Call, Raise, Fold, Help) | arrow keys | D-pad or left stick |
| Choose | Enter / Space | A |
| Back (close the raise picker or help) | Escape | B |
| Raise size: min, half pot, pot, 2x pot, all-in | Q / E | LB / RB |
| In the raise picker: one big blind more / less | up / down | D-pad up / down |
| Signal your teammates | 1 2 3 4 | X Y LT RT (on a Deck also the back buttons L4 R4 L5 R5, once mapped) |
| Fake a signal (for rival eyes; your teammates ignore it) | Shift + 1-4 | hold LB + a signal button |
| Help card (controls, signals, Heat) | H or F1 | Select |
| Open table: leave (after a hand) | Tab / Esc, then Enter | Start or B, then A |
| Next hand (it also moves on by itself) | Enter | A |
| Tutorial: next line / skip the lesson | Enter / Tab | A / Start |

You are seat "You". Your crew (teal) is the Owl (Rock) and the Raccoon
(Bluffer); the rivals (rust) are the Goose (Maniac), Cat (Shark) and Squirrel
(Calling Station). Your teammates' signals pop up over their heads. The rival
crew signals too, in its own code: when your crew catches one, it pops up
over the rival with an eye ("ear ?"), and once a showdown has shown what
that gesture meant, with its meaning ("ear: weak"). The panel top left is
what you've cracked of their code, and which of your gestures they've
cracked (a fake only fools a crew that knows the gesture).

A watchful dealer runs the table. Both crews' Heat shows top right, and the
bottom left says what your next signal would cost. At 40 Heat the dealer
warns your crew, at 70 it fines each of you a dead big blind, and at 100 the
signaller is thrown out after the hand; if that's you, your crew forfeits.
Try another dealer with `godot --path . -- --dealer=STRICT` (or STREET,
ASLEEP, RELAXED, BOUGHT).

### Boss tables

Bosses bring bigger crews: 3v4, 3v5, up to 3v6 at a 9-seat table
(`src/match/boss_table.gd`). The boss crew brings the same chips as your
crew, spread over more seats: its leader two shares, each goon one (3v4
at 1000: Graves on 1200, three goons on 600). The boss rigs the seat
draw: its leader sits right after you (acting behind you every hand), a
goon right before you, and your teammates are split up with Regulars
between them. The table opens on the seating for a moment and says so,
and who holds what. The leader wears a crown on its name plate.

While the leader plays, the boss crew plays as one ("our signals are older
than you": each member knows its teammates' cards and steps aside for a
better hand). **Bust the leader** and the crew is leaderless: no more
signals, no more playing as one, and the goons play scared (tighter, half
the bluffs and loose calls); the text box says so. **Get the leader thrown
out** (Heat) and you win on the spot. Bigger crews signal more, and a
crew's second and third signals in a hand are easier to catch, so boss
crews leak more to interception (about 47 boss signals a match against
about 30 from a road crew, measured below).

The Mossbank Open's final is one: the Regulars (Graves, Tom, Bramble and
Dusty) at 3v4, with Lou asleep. To play boss tables on their own:
`godot --path . scenes/table.tscn -- --boss=4` (3v4; `--boss=5`, `--boss=6`
for 3v5 and 3v6; the table's default dealer is watchful, `--dealer=ASLEEP`
for the Open's), and `-- --boss-test` for a 3v5 boss table with a bought
dealer (the floor in the boss's pocket: a quarter of the Heat for the boss
crew).

### The open table

Mossbank's street table (by the pond, west of the diner) is a cash game,
not a crew match: talk to any of its players and you're offered a seat
for the buy-in ($100; if you can't cover it they say so and that's that).
Everyone at it plays for themselves (`src/match/cash_match.gd`: a
TeamMatch underneath with one team per seat, so nobody has teammates,
signals or soft play), at fixed blinds of 1/2: the buy-in is 50 big
blinds, and the blinds never go up (`CashMatch.blinds_for`). There's no
"match won": after any hand, Start or B asks "Leave the table?" (leaving
is under the cursor; the next hand waits for your answer), and Start
mid-hand asks as soon as the hand is over. You leave with your stack and
it goes back in your money (money after = money before - buy-in + stack,
exact). Bust and you're out the buy-in; clean the table out and A cashes
you out. A rival who busts gets up ("left" on its plate). The top right
shows your chips against your buy-in (+/-), the bottom left how to leave;
your seat shows the dog. The buy-in is saved the moment you sit down (so
quitting at the table can't undo a bad session) and the cash-out the
moment you get up.

After your first sit, win or lose, Sage the Owl and Bandit the Raccoon
ask to come along and join your crew (`src/world/open_table.gd`). They
join, and are saved, the moment you get up, in the same save as your
cash-out (demo 2.1): the lines after only tell you so, and quitting
during them loses nothing. The cash-out itself happens inside the table's
`left` signal, so there's no frame where you've left and your stack isn't
banked.

**The street game** (demo 2.1, Sootbridge): Pip the Owl (Rock), Scraps the
Raccoon (Bluffer) and Gander the Goose (Maniac) play round an upturned
crate outside the Lamp, before the gate. It's the same cash table with
other money: there's no buy-in, they front you a stake of 60 chips at blinds of 3/6,
and when you get up you keep what's above it; below it (or bust) you owe
nothing, so a session never costs money (`CashMatch.sit_staked` and
`cash_out_staked`, `WorldMap.STREET_GAME`). Only a dog with less than the
open table's buy-in may sit ("This game's for empty pockets."): it's a
safety net, not a second income. It's what gets a dog that lost its
wallet at the open table before its crew joined back on its feet: no
crew plays a dog alone, so without it the demo couldn't be finished. The
pace from $0 back to the $100 buy-in is measured below ("Measured so
far"). To play
a cash table on its own: `godot --path . scenes/table.tscn -- --cash`
(you and four animals at $100); in a scripted overworld run
`--autoplay --cash-hands=3` has the bot in your seat get up after three
hands.

### The tutorial

The first time you walk into Rosie's diner she offers to show you how the
tables work (until demo 2 it was the end of the intro, now the night in
Sootbridge); after that it's on her menu at the diner ("A table
lesson"), as often as you like. It's five set-up hands at her back table,
about five minutes, one lesson each, taught by doing:

1. **The table**: your cards and the gold words saying what you hold, the
   command menu; you raise a pair of Kings, your teammate folds out of your
   way (soft play), and three Kings win.
2. **A teammate's signal**: Bandit touches his nose ("I'm strong") and
   raises; you step aside with a good hand and the chips stay in the crew.
3. **Your signal**: two Aces; Rosie asks you to touch your nose (X / 1),
   and both teammates fold hands they'd have played.
4. **Tells**: Scraps the Raccoon raises the river and rubs its paws (the
   raccoon's bluffing tell); your pair of 9s calls and wins.
5. **Heat**: a strict dealer sits down; you signal twice in one hand (20,
   then +40), the dealer warns your crew, and Rosie explains fines (70) and
   ejection (100). A third signal would cost +60, so it's refused with an
   explanation: the tutorial never fines or throws you out.

Rosie talks in the table's text box, and the table waits for A while she
does (bots don't act, your menu doesn't open). The menu cursor starts on
what she suggests, but you can play anything: every scripted animal copes,
and her lines change with what you did. Start (or Tab) offers to skip.
Nothing is won or lost; the save remembers that you were offered it and
whether you finished. To play it on its own: `godot --path .
scenes/table.tscn -- --tutorial` (`--lesson=3` jumps to a lesson,
`--coach-auto=1` moves Rosie on by herself; `--autoplay` plays your seat
the way she suggests). In a scripted overworld run, `--tutorial` takes the
offer (`--auto` runs skip it otherwise) and `--show=tutorial` opens it at
once.

## Tests

`tools/test.sh` runs every tier and ends with a pass/fail table (exit 1 if
any failed; `GODOT=path/to/godot`, default `godot`):

```
tools/test.sh quick          # unit + compile: the pre-commit check, ~20s
tools/test.sh full           # unit + compile + pad + scene + chart: a demo is done when this passes, ~1 min
tools/test.sh soak           # the playtester: 20 fast runs, 1 real, 10 kills (JOBS=2, OUT=/tmp/playtest-soak)
tools/test.sh unit           # or compile, pad, scene, journey, chart: one tier
tools/test.sh unit scene -k S_DECK   # a name fragment for the unit and scene runners
```

| Tier | What | Runs |
| --- | --- | --- |
| unit | rules, maps, the run's state: `tests/test_*.gd` (no autoloads) | `godot --headless --path . -s tests/run_tests.gd [-- fragment]` |
| compile | every script under src/ compiles with the autoloads | `godot --headless --path . res://tests/compile_check.tscn` |
| pad | a pretend Xbox pad signals at the real table | `godot --headless --path . res://tests/pad_check.tscn` |
| scene | the real game from the title, driven by pad events: `tests/scene/test_*.gd` | `godot --headless --fixed-fps 60 --path . res://tests/scene_tests.tscn [-- fragment]` |
| journey | the scene tests in `tests/scene/test_journey.gd` (J-LOOP: title to a crew in Mossbank and back; J-STRANDED: a broke dog alone back to the open table through the street game) | `tools/test.sh journey` |
| chart | R-CHART: bot 3v3 matches unchanged, `tools/simulate.gd -- 8 123 --cycle` against `tests/baselines/cycle_8_123.txt` | `tools/test.sh chart` |
| soak | R-PLAY: `tools/playtest.sh runs 20`, `real 1`, `kill 10`, judged | `tools/test.sh soak` |

`godot --headless --path . --import` refreshes the class cache after a new
`class_name` script (tools/test.sh does it first). Tests are named after
the outcome they check where there is one (`test_S_DECK_...` for S-DECK in
docs/DEMO_SPEC.md), so `-k S_DECK` runs one outcome.

**Expected red.** Demo 2 and demo 2.1 (docs/DEMO_SPEC.md) are built test
first: their tests were written before the code and fail until it's built. They're
listed in `tests/expected_red.txt`, one test name per line. Both runners
print a listed test that fails on a check as `red` (with its first
failure in the summary) and don't fail the run for it; a listed test that
passes fails the run ("delete its line"), and so does one that breaks
instead of failing (a script error, a timeout: that isn't red, it's
broken). So whoever turns a test green deletes its line in the same
commit, and CI's unit step stays strict. (CI runs the scene tier with
`continue-on-error` until demo 2 lands.)

**Scene tests** (`tests/scene_tests.tscn`, `tests/scene_runner.gd`) play
the real title, overworld and table with the autoloads, which the unit
runner can't have. Each test starts clean: its own save
(`user://scene_test.json`, erased before and after, never `save.json`), no
run loaded, no dev flags, no scene; tools/test.sh also gives it a throwaway
XDG_DATA_HOME. A Logger fails a test on any script error, a per-test
timeout (`timeout_s`, game seconds, default 120) fails a hung one. With
`--fixed-fps 60` every frame is 1/60 s of game time however fast it runs,
so the whole tier takes seconds. To add one, write `tests/scene/test_*.gd`
extending `SceneTestCase` (`tests/scene_test_case.gd`, whose top lists the
rules) with `test_*` methods that await its helpers:

```gdscript
extends SceneTestCase

func test_G_EXAMPLE_bertram_talks() -> void:
	if not check(await start_new_game() and await advance(60.0, "cancel"), "walking: " + last_stop):
		return
	check(await talk_to("bertram", "town"), "talk to Bertram: " + last_stop)  # walks there, faces him, A
	await advance()
	check(heard_line("Ridge Road"), "he mentions the road; heard %s" % [heard])
```

The helpers: `start_new_game`, `continue_game`, `continue_from(state)`,
`save_quit_continue`; `press`/`hold`/`release` (pad events through
Input.parse_input_event); `advance` (A through dialogs, stopping at or
cancelling menus), `choose`/`choose_index`; `walk_to(cell, map)` (one step
at a time along a BFS path around walls, anyone standing and a shut gate,
through warps), `talk_to(npc_id, map)`, `face`, `step`; `frames`,
`seconds`, `wait_until(condition, seconds, what)`; `table()`,
`wait_for_hand_done(n)`, `leave_table()`; and `heard`/`menus`, every dialog
line and menu shown. Set dev flags a test needs in `game.dev_args`
(`"autoplay"`, `"seed"`, `"match-result"`). Only await through the helpers,
and guard (`if not check(...): return`) before using something a feature
may not have yet. `tests/scene/test_harness.gd` checks the helpers on
today's game.

The unit tests: 207, about 23 seconds (demo 2's and demo 2.1's among them). They cover hand ranking, equity against known odds
(AA vs a random hand ~85%), blinds and action order (including heads-up and
going heads-up), side pots, split pots and odd chips, uncalled bets, busted
seats, fines as dead money (in the main pot), full bot matches, soft play
between teammates, signals, and Heat: what signals cost, cooling, one
warning per episode, fines, ejections, bought dealers, catching a boss, and
careful animals going quiet; and interception: noticing odds against the
formula, crew codes, learning at a showdown (not from a fold or a fake),
fakes, bots reacting to what they read, the code book through JSON, and a
golden action log showing bot matches unchanged with it off. For the overworld: every
map is rectangular and closed, everyone stands somewhere they can stand,
doors lead somewhere free, line of sight (straight ahead, stopped by walls
and bodies), the walk-up path, that two crews can't be snuck past and two
can, and that beaten crews don't block the road; and for the run: seating
for the table, the party, recruiting (each individual once), win money,
blackouts (half your money, the odd coin kept), and a save round trip,
including damaged and missing saves (and the repairs the playtester's
findings called for: a recruit's old spot, a short party, a won Open
without its bracelet, a save left only as its .part, and since demo 2.1 a damaged deck, repaired on load); the Binder's record (who you've met
and recruited, per individual, where you first met each species), a save
from before the Binder existed loading with it rebuilt from the roster and
beaten crews, the Binder's slots and completion count, and bond growth
(seated animals only, more for a win, capped, read by the bots); and that missing art falls back to
placeholders and a sprite sheet is cut into walk frames and facings.

Boss tables (`tests/test_boss_table.gd`, `tests/test_seat_layout.gd`):
the boss crew's stacks (the same total as yours, leader-heavy), the rigged
seat draw (the leader right after you, a goon right before, nobody on your
crew beside another) and a fair one, the setup the table gets, the leader
rule on a stacked deck (the leader busts, its crew goes leaderless, once),
a leaderless goon going quiet and scared, a led crew playing its best
hand, whole 3v4-3v6 bot matches keeping every chip, the Open as a 3v4
boss table, and a save from before boss tables loading with its cracked
codes; and the table's layout: 6 seats or fewer exactly where they always
were, and at 6-9 seats nothing at one seat (name plate, portrait, cards
face down and at showdown, bet, button, crown, bubbles, an intercepted
signal, a tell, the dealer's glance; each at its worst case) overlapping
another seat or the HUD; a cash table's 3-6 seats on the 6-seat ring's
places, clockwise.

The tutorial (`tests/test_tutorial.gd`, 13 tests): each lesson deals its
cards from the right button; following Rosie produces each lesson's
situation (your teammate folds to your raise; Bandit signals and wins; both
teammates fold to your signal; Scraps raises the river with a hand that is
its bluffing tell, and calling wins; two signals under the strict dealer
warn but don't fine); five other ways of playing every hand (always fold,
call, shove...) still finish all five lessons with no chips made or lost,
no fine and no ejection; signals that would reach a fine are refused;
skipping; every line fits the text box; and saves from before the tutorial
load as already offered.

Then the randomized ones (`tests/test_table_fuzz.gd`). `tests/table_fuzzer.gd`
plays 6,000 hands at random tables (2-9 seats, stacks from 1 chip up, legal
and illegal actions, dead money and ejections) and checks after every action
that no chip is made or lost, the right seat is to act, and the action did
what `act()` promises; after every hand it settles the hand again with an
independent model (blind positions, uncalled bet, main and side pots, winners
by a brute-force evaluator, odd chips, every stack). Run on the engine as it
was, it fails on the bugs fixed on the way (fines refunded through side
pots, blinds after a bust, decisions with nobody left to bet against, and
unknown action ids passing, which it found by itself), and it catches 11 of 12 deliberate one-line breakages of the engine (the
twelfth changes nothing). Also 150 random crew matches (uneven crews, random
fines, ejections, leaders; chips, blind levels and who wins) and Heat under
random signals against a model of its rules. The runner fails any test that
logs a script error (GDScript has no exceptions, so a crashing test would
otherwise pass); a test that misuses the API on purpose declares the errors
it expects.
CI runs the same thing on every push (`.github/workflows/tests.yml`).

## Tools

```
godot --headless --path . -s tools/verify_evaluator.gd        # all 2,598,960 five-card hands
godot --headless --path . -s tools/soak_rules.gd -- 50000 1 --bots=60   # rules fuzzing soak, plus bot matches under a strict dealer
godot --headless --path . -s tools/simulate.gd -- 40 7        # style-vs-style balance, 40 matches a pairing, seed 7
godot --headless --path . -s tools/simulate.gd -- 80 7 --cycle # only the five type-chart links (also --pairs=, --styles=, --iterations=, --interception)
godot --headless --path . -s tools/chip_flow.gd -- MANIAC SHARK 40   # why a matchup goes the way it does
godot --headless --path . -s tools/boss_sim.gd -- 200 50001 --crews=all  # boss tables: your crews vs the Open's Regulars (also --vs=road, --boss=5, --dealer=BOUGHT, --fair)
godot --headless --path . -s tools/cash_sim.gd -- 200 20 1   # the open table: what a 20-hand session is worth (also --buy-in=, --players=, --you=)
godot --headless --path . -s tools/cash_sim.gd -- --street 200 8 1   # the street game: sessions and hands from $0 to the buy-in (also --stake=, --blinds=, --leave=)
godot --headless --path . -s tools/heat_report.gd -- 30 1 STRICT     # how often a dealer warns, fines, ejects each style
godot --headless --path . -s tools/setup_input_map.gd         # rewrite the input actions in project.godot
python3 tools/make_sfx.py --music                             # rebuild the placeholder sounds (assets/audio/README.md)
```

Taking a screenshot without a display (how the screenshots in development
were made): `xvfb-run godot --path . --rendering-driver opengl3
scenes/table.tscn -- --autoplay --screenshot=out.png --shot-after=5` for the
table. The overworld has dev flags for scripted runs (all listed in
`src/game/game.gd`); for example, a fresh game with Sage and Bandit along
(a dog alone is never spotted, so `--recruit` gives it the crew the open
table would) walking into the first crew, with the match skipped as a win,
everything clicked through, into a throwaway save:

```
xvfb-run godot --path . --rendering-driver opengl3 -- --save-slot=dev --new --skip-intro \
    --recruit=owl:0,raccoon:0 --at=town,40,11 --walk=R4 --auto --match-result=win \
    --screenshot=/tmp/win.png --shot-after=7
```

The opening: `-- --save-slot=dev --new --auto --screenshot=/tmp/intro.png
--shot-after=8` catches the night scene, and `--new --skip-intro
--at=sootbridge,31,5 --walk=R3 --shot-after=2.5` the gate's line.

Drop `--match-result` and add `--autoplay --chips=60` to play the real
table with a bot in your seat (a few minutes). `--show=party`,
`--show=start`, `--show=binder` (with `--binder-at=N`), `--show=options`, `--show=demo_complete`, `--recruit=cat:1`, `--beaten=all` and
`--money=` jump to a state; any dev flag also prints what happens
(encounters, results, saves) to the terminal.

The playtester plays the whole demo by itself, from the title, the way a
restless player would (walking everywhere, talking to everyone, opening
every menu, recruiting or not, quitting and continuing, closing the window
mid-dialog), and checks every frame: script errors, softlocks, where you
stand, every save's round trip, Continue, the party, money, each match's
outcome. Headless, so a run takes seconds; docs/PLAYTEST.md has what it
does, what it checks and what it found.

```
tools/playtest.sh runs 200 1     # 200 runs with matches skipped (GODOT=path/to/godot, JOBS=2)
tools/playtest.sh real 12        # with real matches, a bot or random presses in your seat
tools/playtest.sh kill 150       # kill -9 mid-play and mid-save, then Continue
tools/playtest.sh damaged        # every kind of damaged save
tools/playtest.sh summary        # failures, with seeds and a replay command each
```

## Building

```
scripts/export.sh            # Linux and Windows release builds, ~15s
scripts/export.sh linux      # just one (also: windows, --debug)
```

| Build | Files | Size |
| --- | --- | --- |
| Linux x86_64 (native on the Steam Deck) | `build/linux/AFriendInNeed.x86_64` + `.pck` | 71 MB + 61 KB |
| Windows x86_64 (Proton fallback on the Deck) | `build/windows/AFriendInNeed.exe` + `.pck` | 105 MB + 61 KB |

The script needs Godot (`$GODOT`, else `godot` on PATH) and the export
templates of the same version, unzipped from
`Godot_v4.7.2-stable_export_templates.tpz` (GitHub releases) into
`~/.local/share/godot/export_templates/4.7.2.stable/` (Windows:
`%APPDATA%\Godot\export_templates\4.7.2.stable\`), or installed from the
editor's Editor > Manage Export Templates. It checks both, imports the
project, exports, and fails unless every expected file came out. CI does
the same on pushes to main and on tags (`.github/workflows/build.yml`) and
uploads both builds as workflow artifacts (the Linux one as a tarball, which
keeps the executable bit).

How the presets (`export_presets.cfg`) are set up, and why:

- **The .pck isn't embedded.** Each build is Godot's official template,
  byte-identical from build to build, plus the game's .pck. Steam patches
  only the changed file, nothing rewrites an executable (nothing for virus
  scanners or code signing to trip on), and a crash report names a stock
  Godot binary. The .pck must stay next to the executable.
- **`tests/` and `tools/` are excluded**: they're dev-only. Checked: the
  .pck's file table lists only `src/`, `scenes/`, the icon and Godot's own
  metadata. Almost all of each build is the engine; the game is 61 KB.
- **Desktop texture compression only** (S3TC/BPTC). Pixel-art sprites,
  when they exist, should be imported Lossless with filtering off (the
  project already defaults canvas textures to nearest).
- Editing the presets in the Godot editor rewrites the file and drops its
  comments; this list is the lasting copy.

**Checked:** the exported Linux build, run under a virtual display
(`xvfb-run -a -s "-screen 0 1280x800x24" build/linux/AFriendInNeed.x86_64
--rendering-driver opengl3 -- --autoplay --screenshot=out.png
--shot-after=5`), renders the table, fills the 1280x800 screen at x2 and
quits cleanly. The CI workflow's steps were run locally with only the
templates it caches. **Not checked:** the Windows build running (it exports
and its executable looks right), the workflow on GitHub, a real Deck, a
Steam upload. What Steam and Deck Verified need (the back buttons and Steam
Input, text size, suspend, Steam Cloud, SteamPipe uploads, the store page) is
in [docs/STEAM_DECK.md](docs/STEAM_DECK.md).

## Measured so far

**Hand evaluator:** all 2,598,960 five-card hands land in the textbook
category counts (40 straight flushes, 624 quads, ... 1,302,540 high cards),
in 20.7s, so about 8µs per hand. The test suite also compares it with a
brute-force reference on 3,000 random seven-card hands.

**Type chart: the cycle holds.** Crews of three same-style bots, at the
game's settings, on seeds never used for tuning (`tools/simulate.gd -- 80
90001 --cycle` and seeds 90002-90004, 95001-95004): 640 matches per link.

| Link | Before tuning | Now |
| --- | --- | --- |
| Bluffer beats Rock | 24% | 59.1% |
| Rock beats Maniac | 62% | 61.9% |
| Maniac beats Shark | 37% | 57.9% |
| Shark beats Calling Station | 75% | 65.5% |
| Calling Station beats Bluffer | 58% | 57.6% |

At 640 matches the standard error is about 2 points, so the weakest link is
nearly 4 standard errors above a coin flip. The "before" column is the
first presets, measured the same way (200 matches per link).

How it got there (details in `src/crew/play_style.gd`'s docstring):

- **Tuning numbers alone didn't work.** With only tightness, aggression,
  bluffing and stickiness, every change just moved the losses between
  links. Each fix came from `tools/chip_flow.gd` showing where the losing
  crew's chips went, then adding the behaviour that was missing: `respect`,
  `doubt`, `persistence`, `reads` (src/crew/table_reads.gd) and `bluff_risk`.
- **The seeds were correlated.** Godot's RandomNumberGenerator gives
  similar streams for similar seeds, and matches were seeded 1, 2, 3...: one
  matchup measured anywhere from 48% to 78% depending on the base seed. Seeds
  are now hashed (PokerBot, TeamMatch), and the spread dropped to sampling
  noise.
- **Overfitting is real here.** Twice a setting looked good on the tuning
  seeds (around 60%) and came in at 49-52% on fresh ones. Final numbers are
  only ever from seeds the tuning never saw, at the game's 120 equity
  samples per decision (tuning used 60 for speed and then 120).

Rules fixes since (the big blind moving forward after a bust, no decision
or raise when everyone else is all-in) change some hands the bots play.
`tools/simulate.gd -- 60 90001 --cycle`, before / after: Bluffer > Rock
65% / 58%, Rock > Maniac 68% / 57%, Maniac > Shark 50% / 63%, Shark >
Station 62% / 73%, Station > Bluffer 43% / 57%; 45 / 43 hands a match. At
60 matches a link that's +-6.5 points of noise, so no link moved
measurably, but the 640-a-link table above predates the fixes.

Off-cycle pairings (Rock vs Shark and so on) aren't part of the type chart
and weren't tuned. Each match takes about 0.9s at the game's settings.
**Heat.** How often each dealer costs a crew a seat (the share of matches in
which the floor threw one of its animals out), from `tools/heat_report.gd --
30 31`, same-style crews, 60 crews per cell:

| Crew | Asleep | Relaxed | Watchful | Strict |
| --- | --- | --- | --- | --- |
| Rock | 0% | 0% | 2% | 8% |
| Shark | 0% | 0% | 0% | 3% |
| Bluffer | 0% | 0% | 0% | 17% |
| Calling Station | 5% | 27% | 52% | 65% |
| Maniac | 0% | 3% | 20% | 35% |

Careful styles go quiet instead: a Rock crew makes 0.73 signals a hand with
an asleep dealer and 0.16 with a strict one. So a strict dealer either takes
a crew's signals away or takes its animals; either costs it. Warnings come
about once per crew per match at every dealer.

Getting there took two fixes, both found with that report. First, careful
animals scaled down how often they signalled as Heat rose: the strict dealer
threw out 90% of Rock crews and 20% of Maniac crews, because who got caught
depended on how long their hands ran, not on caution. Now each animal has a
comfort line it won't push the crew's Heat past (careful: the warning,
careless: near ejection) and careless ones sometimes forget it. Second,
repeat signals got more expensive per seat, which let short-handed styles
signal freely; they now get more expensive per crew. Warnings also fired up
to 16 times a match for a crew hovering at the line; each now fires once
until the crew cools off.

The Calling Station is caught most: it plays long hands, so it has more to
say, and a caution of 0.4 lets it say it. With no dealer, the bots draw the
same random numbers as before Heat existed (the simulator's output is
identical), so the type chart above is unchanged.

**The type chart under each dealer** (`tools/simulate.gd -- 60 110001
--cycle --dealer=...` and seeds 110002-110004: 240 matches per link):

| Link | No dealer | Asleep | Relaxed | Watchful | Strict |
| --- | --- | --- | --- | --- | --- |
| Bluffer beats Rock | 59.8% | 57.2% | 61.5% | 57.5% | 52.2% |
| Rock beats Maniac | 59.8% | 63.0% | 67.0% | 75.2% | 82.5% |
| Maniac beats Shark | 57.2% | 57.0% | 44.0% | 34.8% | 24.5% |
| Shark beats Calling Station | 63.8% | 63.0% | 69.5% | 72.2% | 83.8% |
| Calling Station beats Bluffer | 56.0% | 55.5% | 51.8% | 42.5% | 39.0% |

The cycle holds with no dealer and with a sleepy one. From a relaxed dealer
up, the careless styles (Maniac, Calling Station) lose ground: they keep
signalling and get fined and thrown out. Open design question: is that the
point (a strict city favours careful crews, like weather in Pokemon), or
should careless styles get something back under a watchful dealer?

**Interception** (reading the other crew's signals; `src/crew/interception.gd`
has the rules and why). Each gesture gets one roll per animal on the other
crew: attentiveness (owl 0.8, cat 0.75, raccoon 0.55, possum 0.5, squirrel
0.3, goose 0.2, you 0.4) x 0.25 x n, where n is the crew's nth signal this
hand. Each crew signals in its own code, so a noticed gesture means
nothing until the sender's cards are shown at a showdown; then it's learned
for good (kept in a CodeBook for the save). Fakes (Shift or LB held) are
ignored by your teammates and believed by rivals who have cracked that
gesture. Bots facing a bet from a seat read as strong / weak move their
equity 15% down / up, and bluff 15% more often into a pot where an
opponent said weak.

At the demo table (you, Owl, Raccoon vs Goose, Cat, Squirrel; a Shark bot
in your seat; 40 road matches of 20 hands, scratch measurement):

| Dealer | Rival signals a match | You notice | Gestures you learn a match | Your crew's signals | Rivals notice | Gestures they learn |
| --- | --- | --- | --- | --- | --- | --- |
| Street (none) | 18.2 | 45% | 1.15 | 19.1 | 37% | 0.62 |
| Watchful | 10.2 | 45% | 0.93 | 8.5 | 28% | 0.20 |
| Strict | 6.6 | 37% | 0.62 | 4.8 | 27% | 0.05 |

So under the watchful dealer you see about four of the rivals' signals in
a road match and crack one gesture in three matches out of four (the first,
when it comes, at a median of hand 6). Bots only ever say "strong" and
"weak", so two gestures per crew is all there is to learn from them. LOOK
was 0.15 at first: 25% noticed and 0.6 gestures learned a match, which
looked too little to play with (a judgement from the numbers, not from
playing). The rivals watch worse than your crew
(a goose and a squirrel) and rarely crack your code inside one match, so a
fake mostly pays off in a rematch, once the CodeBook carries over: an open
design question is whether that's the right pace.

**Off, nothing changes.** `tools/simulate.gd -- 8 123 --cycle` prints the
same output before and after interception existed, and
`tests/test_interception.gd` checks two full bot matches (one under a
watchful dealer) against action logs recorded before it: every action,
amount and signal identical. Interception keeps its own RNG and draws
nothing while off.

**On, the cycle** (`tools/simulate.gd -- 60 <seed> --cycle --interception`,
seeds 70001-70004, against the same seeds with it off: 240 matches a link):

| Link | Off | On |
| --- | --- | --- |
| Bluffer beats Rock | 57.0% | 52.8% |
| Rock beats Maniac | 56.3% | 56.8% |
| Maniac beats Shark | 58.5% | 57.8% |
| Shark beats Calling Station | 62.5% | 63.0% |
| Calling Station beats Bluffer | 59.5% | 58.0% |

38% of bot signals were noticed and both crews cracked each other's two
gestures in almost every match (2.0 learned a match: bot matches run 44
hands). Every link still holds; only Bluffer > Rock moved more than a
point, and at 240 matches a link (about 3 points of noise each, 4.5 for a
difference) that isn't measurable yet. A bigger run of that link (`-- 200 70005
--pairs=BLUFFER-ROCK`, 200 matches each way) gave 57% off and 49% on, so
across both, 57% and 51%: likely real, about 2 standard errors. Where it
comes from (a scratch tally over 60 matches): the Bluffer tells its crew
"I'm weak" and then bluffs, and in the 68 hands where a Rock faced a bet
from a Bluffer it had overheard saying "weak", the Rock crew came out
+189 chips a hand. The reverse barely happens (the Rock rarely signals
weak and then bets). That's the mechanic doing what it says, a bluffer
who tells its crew it's weak gets called, but it does weaken the type
chart's thinnest link when both crews intercept. If interception is ever
on in bot-vs-bot play (rival crews among themselves, say), the Bluffer
wants a reason to stay quiet when bluffing (a fake "strong", or caution).

**The open table, bot vs bot** (`tools/cash_sim.gd`): what a session at
Mossbank's open table is worth, with a Shark bot in your seat (what
`--autoplay` plays) against Sage (Rock), Bandit (Bluffer) and Waddles
(Maniac), all at the $100 buy-in and 1/2 blinds, up to 20 hands, leaving
then (or on a bust). 200 sessions a seed:

| Seed | Your average cash-out | Busted | Sage | Bandit | Waddles |
| --- | --- | --- | --- | --- | --- |
| 1 | $100.1 (+-5.2) | 27 | $115.7 | $94.4 | $89.7 |
| 2 | $97.2 (+-4.3) | 25 | $112.1 | $99.6 | $91.1 |

So a session about breaks even for a decent player, with one in eight
going bust within 20 hands; the Rock takes the money off the Maniac. No
target yet: it's the starting point for the money-as-health economy
(docs/DESIGN.md).

**The street game's pace** (`tools/cash_sim.gd --street`, demo 2.1):
how long a broke dog takes from $0 back to the open table's $100 buy-in
at Sootbridge's street game, with a Shark bot in your seat (what
`--autoplay` plays) against Pip (Rock), Scraps (Bluffer) and Gander
(Maniac). Each session it gets up after the first hand that leaves it
above the stake, when it busts, or after 8 hands (the policy J-STRANDED
uses); it keeps what's above the stake. Minutes are hands times about 20 s
a hand, an estimate of a person's pace at the table, not measured. The
target is docs/DESIGN.md's 10-15 minutes. 60 runs a row on seed 1 while
tuning:

| Stake, blinds (depth) | Hands to $100: median (10th-90th percentile) | About | Sessions (median) | Busted |
| --- | --- | --- | --- | --- |
| 50 at 1/2 (25 bb) | 74 (36-131) | 25 min | 13 | 9% |
| 100 at 1/2 (50 bb, the open table's depth) | 56 (16-124) | 19 min | 9 | 5% |
| 200 at 2/4 (50 bb) | 41 (7-85) | 14 min | 6 | 4% |
| 50 at 2/4 (12 bb) | 46 (21-123) | 15 min | 9 | 14% |
| **60 at 3/6 (10 bb)** | **37 (14-77)** | **12 min** | **7** | **20%** |
| 50 at 4/8 (6 bb) | 28 (10-58) | 9 min | 6 | 27% |
| 50 at 5/10 (5 bb) | 25 (10-51) | 8 min | 7 | 37% |

The game's: **60 at 3/6** (`WorldMap.STREET_GAME`). On seeds the tuning
never saw (200 runs each): seed 2, median 39 hands (13-76), 13 minutes
(4-25), 8 sessions; seed 3, median 39 (15-77), 13 minutes (5-26), 7
sessions; a bot that plays every session to 8 hands instead of getting up
when ahead (seed 4) takes a median 46 (16-105), 15 minutes. About $15 is
kept a session and one in five busts (which costs nothing). Shallow is
what works: below the stake you owe nothing, so every all-in is a free
roll, and at 10 big blinds the pennies come in often and small; at the
open table's depth it took twice as long, and a bigger stake got there
only in a few big lumps (a tenth of runs at 200 done in 7 hands). The
spread is wide either way (4-26 minutes for the middle 80%): that's cards.
In the game, J-STRANDED (seed 7 on) took 10 sessions and 60 hands. The
street players' styles weren't changed: the stake and blinds were enough.

**The street game on screen** (demo 2.1): checked with screenshots under
a virtual display, driven like a scene test: the crate and its three
players outside the Lamp, the offer ("Sit in? They'll stake you 60
chips."), the table mid-hand (the HUD: "Staked 60 (theirs; you keep the
rest)", blinds 3/6), the leave offer ("You'd owe nothing, and keep
nothing." below the stake; it said "Down 1 on your 50 buy-in" until the
screenshots caught it), the line after getting up, and a dog with $200
turned away ("This game's for empty pockets."). Not checked: how it feels
to play, or whether 20 s a hand is a person's pace.

**Boss tables, bot vs bot** (`tools/boss_sim.gd`; how each match is set
up is how the game sets up yours: the rigged draw, leader-heavy stacks,
interception on, 1000 chips). Your side is a Shark bot in your seat (what
`--autoplay` plays) with two animals, in five mixes: the starters (Owl,
Raccoon), Cat + Goose, Possum + Squirrel, Raccoon + Goose, Owl + Cat; 40
matches each, 200 a number, all on seeds the tuning never saw:

| Table (seed) | Your crews win | Boss leader busted | ...first of its crew | Boss signals a match (you notice) |
| --- | --- | --- | --- | --- |
| The Open: 3v4, asleep dealer (50011) | 48.0% | 57.5% | 4.0% | 46.7 (37%) |
| ...with a fair, random seat draw (50011) | 48.0% | 59.5% | 8.0% | 45.7 (38%) |
| ...with a bought dealer (50011) | 47.0% | 55.5% | 7.0% | 51.9 (39%) |
| ...without the boss crew playing as one (50011) | 54.0% | 69.0% | 8.0% | 46.7 (37%) |
| 3v5, asleep (50015) | 54.0% | 65.0% | 4.5% | 48.9 (36%) |
| 3v5, bought dealer (50015) | 48.5% | 67.5% | 6.5% | 54.0 (38%) |
| Road crews, 3v3 at the same chips, no hand cap (50003) | 46.0% | - | - | 29.6 (40%) |

And the starters alone (the crew a new game sits down with), 200 matches
each: 43.5% against the Open (50012), 49.0% against the four road crews
at the same chips (50013).

At 200 matches a number is +-3.5 points (one standard error), +-5 for a
difference. What that says:

- **The Open lands at the top of the aim (35-50% for a bot crew) but is
  not harder than a road crew** for the five mixes on average (48.0% against
  46.0%); for the starters it is (43.5% against 49.0%: 5.5 points, about 1.6 standard errors). A person
  with signals and reads should do better than the Shark bot in your seat,
  and the boxing-in (the leader acting right after you) works on a person,
  not a bot. Unchecked: nobody has played it.
- **The leader is rarely busted first** (4-8%): its goons, on half its
  stack, go first, as designed ("picking goons off early swings the
  numbers"). When it does bust the match is usually nearly over: 6-9
  leaderless hands of about 62.
- **Playing as one is the boss's real edge**: without it your crews won
  54.0% on the same deals (6 points, about 1.7 standard errors).
- **The bought dealer** costs your crew 1 point at 3v4 and 5.5 at 3v5 (the
  same deals each way; 6.5 at 3v4 on seed 50001), mostly by throwing out
  your careless animals (Goose, Squirrel: 0.14-0.27 of your seats a match)
  while it never catches the boss crew (a quarter of the Heat).
- **Bigger crews leak more:** a boss crew makes about 47 signals a match
  against 30 for a road crew (more seats, longer matches), and you notice
  the same share of them.
- **Tried, and moved nothing measurable** (150 matches each, exploration
  seeds 2-10, most of them before the boss crew played as one): the seat draw (rigged as now, the boss crew in the nearest
  seats with your crew together, or random: 48-55% every way), the Regulars'
  bond (1.0: their signals always read right), the leader calling "raise
  behind me" so the goons either side of you squeeze (52.7% against 50.7%),
  the fourth Regular's species (cat, owl, possum, goose: 52-56%), Tom
  leading instead of Graves (45% against 47%). Chips move it some: the
  leader holding one share (even stacks) 49%, four shares 58% (seed 5); and the boss
  crew bringing more chips than yours (`BossTable.CHIP_EDGE`, 1.0 as
  designed): 1.4x gave 48.0% against 51.0% (seed 50001), 1.5x 37% against
  51% (seed 10). In this bot ecosystem who's playing (the type chart)
  moves a match more than seats or chips. If the Open should be harder,
  CHIP_EDGE is the one-line knob; it's left at the design's same total.

**The table on screen:** checked with screenshots under a virtual display:
the preflop decision, a showdown (the right hand wins, the busted seat greys
out). Not checked: how it feels to play, on a real Steam Deck, or with a real
controller.

**The overworld:** checked with scripted runs under a virtual display
(`--walk`, `--auto`) and screenshots of each step: the title, the town with
the intro, a crew's "!" and walk-up, its dialogue, the recruit menu after a
win (the save then has the money, the crew beaten and the recruit), a
blackout waking at the diner with half the money, the party screen, the
Binder (recruited, seen, unseen, locked and dog slots; after a scripted
road game the save has the crew's animals seen, "Ridge Road, with the Pond
Hecklers" as where, and both seated animals' bond at 0.6 from 0.5, with
"Sage and Bandit's bonds grew!" on screen), the
tournament hall, the Open at the embedded table with the asleep dealer, and
the demo-complete screen. Two runs played real matches at the embedded
table end to end (a bot in your seat, 60 chips each, each under three
minutes): one lost and woke at the diner with $100 of $200; one won, came
back to the same spot on the road with $320, recruited Honk and saved. The
first of those found a bug, now fixed: the table, freed at the end of the
frame, reported the match again on a second A press in that frame. The table still runs on its own. Found
along the way: Godot 4.7's default `ui_accept` and `ui_cancel` have no
controller buttons, so A did nothing on a pad, at the table too; project.godot
now adds A and B. Not checked: walking feel and step timing, a real
controller or the Deck, and whether a Deck suspend loses anything (the
process is frozen without notice, so the protection is saving often).

**Together (the merged demo):** checked with scripted runs on the merged
branches: a new game, spotted by the Pond Hecklers on Ridge Road, a real
match at the animated table (a bot in your seat) to the end, and a blackout
at the diner with half the money; and the Mossbank Open won through to the
bracelet in the save. Road games are capped at 20 hands (the bigger stack
wins): with the table's real-time animations a full bust-out ran past three
minutes even at 60 chips. Tournaments play to the end. The sounds are wired
at the table (on the animation beats) and in the overworld, unheard.

**The table:** the table's look is a handheld-RPG battle screen (original art, drawn from
code): cream panels with chunky coloured frames (`src/ui/pixel_frame.gd`),
a text box along the bottom that types out what just happened ("Honk
raises to 60!", `src/ui/table_feed.gd`) with a blinking arrow when A moves
things on, and on your turn "What will you do?" with a 2x2 command menu
and a cursor (`src/ui/command_menu.gd`). Raise opens an amount picker, so
raising is two presses and a stray A never shoves chips in. Every animal
sits at its seat (`src/ui/animal_art.gd`: assets/portraits/<species>.png,
else assets/sprites/<species>.png, else a placeholder blob with eyes and
its initial) and bobs and blinks. Text is in two OFL pixel fonts drawn at
their native sizes (`src/ui/ui_font.gd`, assets/fonts/): Godot's default
font came out grey and blurry at 8-10px.

Motion (`src/ui/table_motion.gd`): cards slide from the shoe, board cards
flip (an all-in run-out plays card by card with a pause between streets),
chips slide to the bet spot, into the pot and to the winner, whose stack
and a "+274" update when the chips land; the seat to act hops. Each beat is
0.1-0.35s, and only the next actor waits for it. Bots decide when their
turn starts and think 0.35-1.25s depending on the choice. Readability: your
hand in words beside your cards (`src/ui/hand_readout.gd`: "Two pair, Kings
and 7s", draws on the flop and turn when your cards are in them), showdown
hands grow to board size, and raise sizes jump by pot fractions
(`src/ui/raise_sizes.gd`). Tells (`src/ui/animal_tells.gd`): each animal
shows its species' tell about half the time it applies, judged on what its
hole cards add to the board (a puff over its picture and a line in the text
box). Heat: when anyone signals, the dealer's eyes flash over that seat and
in the Heat panel, and the bar climbs to its new level.

Boss tables at 7, 8 and 9 seats (`--boss=4/5/6`, `--boss-test`) were
checked by screenshots too (in /tmp/claude-0/agents3/boss/ when they were
made): the seating and the rigged-draw lines before the first deal, the
deal, bets, a signal bubble from your crew, an intercepted rival signal
with the dealer's eyes over it, a tell's puff in the 48 px between two
side seats at 9, showdowns with the cards turned over beside the badges,
the leader's crown, and the Open from the hall (four Regulars in a row,
Graves's lines, the embedded 7-seat table). 6 seats are unchanged (a
before/after screenshot differs only in the animals' idle animation).
Checked by screenshots at 640x400 (and zoomed x2-x3, as on the Deck): the
deal in flight, a flop mid-flip, chips to the pot, a showdown and the pot
going to the winner, the command menu, the raise picker after LB/RB and
up (driven with simulated input), the help card, a tell puff, the dealer's
glance, the match-over text, and an embedded match freed the moment
`finished` fires. The new logic has tests (`tests/test_table_ui.gd`).
Still not checked: how the pacing feels in real time, a real controller,
the Deck's screen.

**The tutorial:** checked with screenshots under a virtual display (in
/tmp/claude-0/agents2/tutorial/ when they were made): Rosie's intro over the
first deal, the menu opening on her suggestion (RAISE 40), Bandit's "touch
nose" bubble with her explanation, the "press 1 / L4" prompt and your own
bubble after it, Scraps' paw-rub puff on the river and her line about it,
the dealer's warning in the box before her "Hear that?", the help card's
skip row, and the offer at the end of a new game's intro. One scripted run
went from a new game through the offer and all five lessons (a bot in your
seat following her advice, her lines moving on 1.2s after typing out) back
to town in 2 min 47 s, with the save showing the tutorial done and the
money unchanged. She says about 45 lines; read at a person's pace (4-5s
each) plus deciding, that's an estimated five to seven minutes, not timed.
Screenshots found three things, now fixed: the coach's figure drew as a
white block (a texture loaded inside `_draw` is freed before the frame
renders: the table now holds it), your own signal bubble and the dealer's
glance at you covered your cards, and her next line covered the dealer's
warning (she now waits 1.6s after a signal). Not checked: how the pacing
feels to someone reading at their own speed, a real controller or the
Deck's back buttons (A on a signal prompt has Rosie do it, so an unmapped
Deck can't get stuck), and pressing Start mid-lesson on a real device (the
skip is tested headless only).

**Xbox controllers:** the signals used to be only on the Deck's back
buttons, which an Xbox pad doesn't have (and which a Deck only passes on
with a custom Steam Input layout). Now they're on X, Y, LT and RT as well
(`src/input/pad_controls.gd` says why those four: everything else was
taken), so a plain Xbox-style pad, or a Deck on Steam's default layout,
plays everything. The triggers needed care: bound in the input map like the
stick, one pull of RT read as a signal 7 times (measured: eleven motion
events from rest to full and back, seven past the deadzone), each costing
Heat. `TriggerButtons` (the `Triggers` autoload) turns each pull into one
press, with a press line at 0.6 and a release line at 0.3 so a trigger
hovering halfway presses once. `tests/pad_check.tscn` plays the real table
with pretend pad events (X, Y, a full RT pull, LB held with a jittery LT
pull) and checks exactly four signals arrive, the last a fake; with the
autoload removed it fails on both triggers. `tests/test_controls.gd` checks
every action has a button on an Xbox pad and that the on-screen names match
the input map. The legend, the help card and Rosie's lines name the pad
buttons; screenshots checked they fit. Not checked: a real Xbox pad (that
SDL reports its buttons as Godot's X, Y and trigger axes is Godot's mapping,
not tested here), how LB + LT feels for a fake, and the Deck.

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | 640x400 base resolution, integer-scaled x2 to the Deck's 1280x800, nearest-neighbour filtering, GL Compatibility renderer, input actions, the Game, Sfx and Triggers autoloads, saves in a custom user dir (`AFriendInNeed`) |
| `src/poker/card.gd` | Cards as ints 0-51, parsing and labels |
| `src/poker/deck.gd` | Seeded shuffles (replayable), stacked decks for tests |
| `src/poker/hand_evaluator.gd` | Best five of up to seven cards, as one comparable int |
| `src/poker/equity.gd` | Monte Carlo win chance against N random hands |
| `src/poker/holdem_table.gd` | The rules: blinds, betting rounds, side pots, uncalled bets, dead money, showdown. No nodes, so it runs headless |
| `src/crew/play_style.gd` | The five styles (Rock, Maniac, Shark, Calling Station, Bluffer) as numbers |
| `src/crew/table_talk.gd` | Signals between teammates, and misreads when the bond is weak |
| `src/crew/table_reads.gd` | What a watchful player learns: who re-raises when bet into |
| `src/crew/interception.gd` | Reading the other crew's signals: noticing, learning codes at showdowns, fakes; off unless a match turns it on |
| `src/crew/crew_code.gd` | Each crew's private code (gesture for each meaning), derived from its id |
| `src/crew/code_book.gd` | What each crew has learned of other crews' codes; JSON-safe for the save |
| `src/input/pad_controls.gd` | The controls' names for on-screen hints (X Y LT RT, L4 R4 L5 R5, 1-4), and why the signals sit where they do |
| `src/input/trigger_buttons.gd` | The `Triggers` autoload: LT and RT as buttons, one signal per pull |
| `src/ui/intercept_overlay.gd` | Draws intercepted signals, the code panel and fakes over the table |
| `src/ai/poker_bot.gd` | An AI seat: equity + style, soft play, reacts to signals |
| `src/match/team_match.gd` | Crew vs crew: rising blinds, fines and ejections, who's out, who won |
| `src/match/dealer.gd` | Who's watching: street (nobody), asleep, relaxed, watchful, strict, bought |
| `src/match/heat.gd` | Each crew's Heat: warnings, fines, ejections |
| `src/match/boss_table.gd` | Boss tables: the rigged seat draw (and a fair one), the leader-heavy stacks, the table's setup |
| `src/match/cash_match.gd` | The open table's cash game: every seat its own team, fixed blinds from the buy-in, leaving between hands, busted rivals leave, sitting down and cashing out (money), and the street game's staked seats |
| `src/ui/seat_layout.gd` | Where everything at a seat goes, for 2-9 seats (the ellipse up to 6, two columns for 7-9; a cash table's 3-6 on the 6-seat ring's places) |
| `src/ui/table_view.gd` | The table scene: layout, flow, input, drawing (placeholder art drawn from code) |
| `src/ui/card_art.gd` | Placeholder cards with pixel suits |
| `src/audio/sfx.gd` | The `Sfx` autoload: plays sounds by name from a pool, with per-play pitch/volume variation; no-op without an audio device |
| `assets/audio/` | Placeholder sound effects and a lounge loop, generated by `tools/make_sfx.py`; its README lists every sound and where to trigger it |
| `scenes/table.tscn` | The table; embeddable (`setup`, `dealer_kind`, `starting_chips`, `embedded`, `finished(won)`; in cash mode `cash_game`, `buy_in`, `left(chips)`) and still runnable on its own |
| `scenes/title.tscn`, `src/game/title_screen.gd` | Main scene: Continue / New game |
| `src/game/game.gd` | The `Game` autoload: the run's state, saving, scene changes, dev flags |
| `src/game/game_state.gd` | The run: roster, party, money, bracelets, beaten crews, position, the deck and the pickups taken; what wins, blackouts, recruits and the open table's crew do; old saves load past the opening, and every load repairs the deck |
| `src/game/save_file.gd` | GameState to user:// JSON, written atomically |
| `scenes/world/overworld.tscn`, `src/world/overworld.gd` | The intro, walking, talking, picking up cards, the gate, encounters, handing over to the table and back |
| `src/world/world_map.gd` | The maps as text (Sootbridge and its washhouse, the Mill Road, Mossbank and Ridge Road, three interiors), with their crews, townsfolk, signs, doors, cards lying about, the gate, the open table and Sootbridge's street game; line of sight |
| `src/world/map_view.gd` | Paints a map: tile art if present, placeholders if not |
| `src/world/critter.gd` | Anyone walking around; placeholder animals drawn from rectangles |
| `src/world/sprite_bank.gd` | Finds `assets/sprites/<id>.png` and `assets/tiles/<name>.png` if they exist |
| `src/world/dialog_box.gd`, `choice_menu.gd`, `party_screen.gd`, `options_screen.gd`, `demo_complete.gd`, `ui_kit.gd` | The overworld's screens (text box, Start menu, crew, options, the end) and their shared look |
| `src/world/binder.gd`, `binder_screen.gd`, `pocket_art.gd` | The Binder: what each slot shows and the completion count (headless), the screen, and the hearts and greyed/silhouette portraits it shares with the crew screen |
| `src/game/settings.gd` | Text speed and volume, in `user://settings.cfg`, apart from the save |
| `src/ui/sprites.gd` | Loads the art by name (species, portraits, tiles, walk animations); null when a file is missing |
| `assets/` | Placeholder art and its palette, generated from the text grids in `assets/src/` (see assets/README.md) |
| `tools/make_art.gd` | Regenerates every PNG in assets/ from the grids |
| `scenes/dev/art_preview.tscn` | Shows all the art: characters walking, tiles, buildings, a small town at 1x |
| `src/ui/table_motion.gd` | The animation timeline: beats booked one after another |
| `src/ui/command_menu.gd` | Your turn's 2x2 command menu (cursor state) |
| `src/ui/table_feed.gd` | The text box's lines, each typed out when its moment comes |
| `src/ui/pixel_frame.gd` | Framed panels, menu cursor and arrows |
| `src/ui/hand_readout.gd` | Your hand in words |
| `src/ui/raise_sizes.gd` | Raise sizes for the bumpers |
| `src/ui/animal_tells.gd` | When each species' tell shows |
| `src/ui/animal_art.gd` | An animal's picture at its seat, or a placeholder |
| `src/ui/ui_font.gd` | The two pixel fonts, at their crisp sizes |
| `src/tutorial/tutorial_script.gd` | Rosie's five lessons as data: each one's button, cards, board, how every seat plays, and her lines |
| `src/tutorial/table_tutorial.gd` | Runs the lessons at the table: deals them, keeps the coach's lines, refuses signals that would overheat you, skipping |
| `src/tutorial/scripted_bot.gd` | A seat that plays a short policy per street, so a lesson's moment happens every time |
| `src/tutorial/coach_box.gd` | The coach's text box at the table |
| `assets/fonts/` | Tiny5 and Departure Mono (SIL OFL 1.1, licenses alongside) |
| `tests/` | The unit runner (`run_tests.gd`) and tests, the compile and pad checks, `expected_red.txt` (tests written ahead of their feature), `world_paths.gd` (reachability over the maps, for tests) |
| `tests/scene_tests.tscn`, `tests/scene_runner.gd`, `tests/scene_test_case.gd`, `tests/scene/` | Scene tests: the real game from the title, driven by pad events (README "Tests") |
| `tools/test.sh` | Every test tier from one command, with a pass/fail table |
| `src/world/open_table.gd` | Mossbank's open table and Sootbridge's street game from the overworld: the seat offer, the buy-in (or the stake), the cash table, the cash-out, Sage and Bandit joining |
| `tools/` | Evaluator check, balance simulator, boss-table simulator (`boss_sim.gd`), open-table sessions and the street game's pace (`cash_sim.gd`), chip-flow analysis, Heat report, rules soak, input-map writer, `make_sfx.py` (synthesizes and measures the placeholder audio), the playtester (`playtest.gd`, `playtest.sh`, docs/PLAYTEST.md) |
| `scripts/cloud_setup.sh` | Installs Godot in Claude Code cloud sessions |
| `export_presets.cfg` | Linux and Windows x86_64 release exports (README "Building") |
| `scripts/export.sh` | Exports both presets headless into `build/` |
| `.github/workflows/build.yml` | CI: exports both builds on main and tags, uploads them as artifacts |
| `steam/` | SteamPipe upload scripts and a Steam Input action manifest, as templates with placeholder IDs |
| `docs/STEAM_DECK.md` | What Steam and Deck Verified need, verified vs from the docs |

## Next steps

1. Play it. Is setting up a teammate fun? Do the signals matter? Is a road
   match the right length (500 chips each now), and the road the right
   number of matches before the Open?
2. Recheck the type chart (`tools/simulate.gd --cycle` on fresh seeds) after any change to the bot or the styles.
3. Play against each dealer: is Heat a choice you weigh, or just a tax?
4. Real art: redraw the placeholders in Aseprite with assets/palette.gpl (assets/README.md says how), maybe via the Aseprite Wizard plugin.
5. GodotSteam, then a default Steam Input configuration so the back buttons reach the game (docs/STEAM_DECK.md section 2).
