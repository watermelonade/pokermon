# A Friend in Need

A whimsical pixel-art RPG where you train the animals you meet to play team
Texas hold'em, travel from town to town winning tournaments, and finally sit
down inside the painting *Dogs Playing Poker*. Built in Godot 4 for the
Steam Deck first. The full design is in the
[design doc](https://claude.ai/code/artifact/c284c9ac-3915-4b60-9293-ad0b666dede4)
(summary in [docs/DESIGN.md](docs/DESIGN.md)).

This is the starter project: the poker rules, the hand evaluator, the AI play
styles, team signals, a playable placeholder 3v3 table, and a demo loop
around it: a title screen, the starter town of Mossbank and Ridge Road, four
rival crews who spot you and deal you in, recruiting, blackouts, saving, and
the town's tournament. No art yet (everything is drawn from code); the first
goal is to find out whether one table is fun.

## Running it

Install [Godot 4.7](https://godotengine.org/download) (the standard build;
the .NET one isn't needed), open `project.godot` in it, and press F5. That
starts the title screen; to play just the table, open `scenes/table.tscn`
and press F6 (or `godot --path . scenes/table.tscn`).

### The demo

You start outside your house in Mossbank with Sage the Owl (Rock) and
Bandit the Raccoon (Bluffer) following you. The Mossbank Open is at the
Tournament Hall at the east end of Ridge Road. Along the road, four rival
crews stand watching: walk into one's line of sight and a "!" pops up, it
walks over, has its say, and you're at the table (no dealer on the road, so
signal freely). Win and they pay up, and you can ask one of them to join
you; lose and you wake up at Rosie's Diner with half your money, and the
crew will deal you in again. Two of the crews block the road; the other
two can be walked around. In the hall, talk to the Mossbank Regulars to
play the Open (the dealer's asleep); winning gives you the first bracelet
and the demo-complete screen. Start (or Tab) opens your crew: pick which
two animals sit with you.

The game saves itself after every match, at every door, and when the
window loses focus; Continue on the title picks up from there. Saves are
JSON in `user://save.json`, which with the custom user dir set in
project.godot is `~/.local/share/AFriendInNeed/` on Linux and the Deck,
`%APPDATA%\AFriendInNeed\` on Windows.

| Overworld | Keyboard | Controller / Steam Deck |
| --- | --- | --- |
| Walk | arrows or WASD | D-pad or left stick |
| Talk, read, confirm | Enter / Space | A |
| Back | Esc | B |
| Your crew (party screen) | Tab / Esc | Start |

| Table | Keyboard | Controller / Steam Deck |
| --- | --- | --- |
| Choose Fold / Call / Raise | arrow keys | D-pad or left stick |
| Confirm | Enter / Space | A |
| Raise size down / up | Q / E | LB / RB |
| Signal your teammates | 1 2 3 4 | back buttons L4 R4 L5 R5 |
| Next hand | Enter | A |

You are seat "You". Your crew (teal) is the Owl (Rock) and the Raccoon
(Bluffer); the rivals (rust) are the Goose (Maniac), Cat (Shark) and Squirrel
(Calling Station). Your teammates' signals pop up over their heads. The rival
crew signals too, but you can't see theirs yet.

A watchful dealer runs the table. Both crews' Heat shows top right, and the
bottom left says what your next signal would cost. At 40 Heat the dealer
warns your crew, at 70 it fines each of you a dead big blind, and at 100 the
signaller is thrown out after the hand; if that's you, your crew forfeits.
Try another dealer with `godot --path . -- --dealer=STRICT` (or STREET,
ASLEEP, RELAXED, BOUGHT).

## Tests

```
godot --headless --path . --import            # once, and after adding a class_name script
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tests/run_tests.gd -- side_pot   # only matching tests
```

61 tests, about 8 seconds. They cover hand ranking, equity against known odds
(AA vs a random hand ~85%), blinds and action order (including heads-up),
side pots, split pots and odd chips, busted seats, a 600-hand random-play run
that checks no chip is ever created or lost, full bot matches, soft play
between teammates, signals, and Heat: what signals cost, cooling, one
warning per episode, fines as dead money, ejections, bought dealers,
catching a boss, and careful animals going quiet. For the overworld: every
map is rectangular and closed, everyone stands somewhere they can stand,
doors lead somewhere free, line of sight (straight ahead, stopped by walls
and bodies), the walk-up path, that two crews can't be snuck past and two
can, and that beaten crews don't block the road; and for the run: seating
for the table, the party, recruiting (each individual once), win money,
blackouts (half your money, the odd coin kept), and a save round trip,
including damaged and missing saves. The runner fails any test that logs a script
error (GDScript has no exceptions, so a crashing test would otherwise pass).
CI runs the same thing on every push (`.github/workflows/tests.yml`).

## Tools

```
godot --headless --path . -s tools/verify_evaluator.gd        # all 2,598,960 five-card hands
godot --headless --path . -s tools/simulate.gd -- 40 7        # style-vs-style balance, 40 matches a pairing, seed 7
godot --headless --path . -s tools/simulate.gd -- 80 7 --cycle # only the five type-chart links (also --pairs=, --styles=, --iterations=)
godot --headless --path . -s tools/chip_flow.gd -- MANIAC SHARK 40   # why a matchup goes the way it does
godot --headless --path . -s tools/heat_report.gd -- 30 1 STRICT     # how often a dealer warns, fines, ejects each style
godot --headless --path . -s tools/setup_input_map.gd         # rewrite the input actions in project.godot
```

Taking a screenshot without a display (how the screenshots in development
were made): `xvfb-run godot --path . --rendering-driver opengl3
scenes/table.tscn -- --autoplay --screenshot=out.png --shot-after=5` for the
table. The overworld has dev flags for scripted runs (all listed in
`src/game/game.gd`); for example, a fresh game walking into the first crew,
with the match skipped as a win, everything clicked through, into a
throwaway save:

```
xvfb-run godot --path . --rendering-driver opengl3 -- --save-slot=dev --new --skip-intro \
    --at=town,40,11 --walk=R4 --auto --match-result=win --screenshot=/tmp/win.png --shot-after=7
```

Drop `--match-result` and add `--autoplay --chips=60` to play the real
table with a bot in your seat (a few minutes). `--show=party`,
`--show=demo_complete`, `--recruit=cat:1`, `--beaten=all` and
`--money=` jump to a state; any dev flag also prints what happens
(encounters, results, saves) to the terminal.

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
identical), so the type chart above is unchanged. Not measured yet: how the
type chart shifts under each dealer.

**The table on screen:** checked with screenshots under a virtual display:
the preflop decision, a showdown (the right hand wins, the busted seat greys
out). Not checked: how it feels to play, on a real Steam Deck, or with a real
controller.

**The overworld:** checked with scripted runs under a virtual display
(`--walk`, `--auto`) and screenshots of each step: the title, the town with
the intro, a crew's "!" and walk-up, its dialogue, the recruit menu after a
win (the save then has the money, the crew beaten and the recruit), a
blackout waking at the diner with half the money, the party screen, the
tournament hall, the Open at the embedded table with the asleep dealer, and
the demo-complete screen. One run played a real match at the embedded table
end to end (a bot in your seat, 60 chips): it lost, emitted `finished`, and
the run woke at the diner and saved. The table still runs on its own. Found
along the way: Godot 4.7's default `ui_accept` and `ui_cancel` have no
controller buttons, so A did nothing on a pad, at the table too; project.godot
now adds A and B. Not checked: walking feel and step timing, a real
controller or the Deck, and whether a Deck suspend loses anything (the
process is frozen without notice, so the protection is saving often).

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | 640x400 base resolution, integer-scaled x2 to the Deck's 1280x800, nearest-neighbour filtering, GL Compatibility renderer, input actions, the Game autoload, saves in a custom user dir (`AFriendInNeed`) |
| `src/poker/card.gd` | Cards as ints 0-51, parsing and labels |
| `src/poker/deck.gd` | Seeded shuffles (replayable), stacked decks for tests |
| `src/poker/hand_evaluator.gd` | Best five of up to seven cards, as one comparable int |
| `src/poker/equity.gd` | Monte Carlo win chance against N random hands |
| `src/poker/holdem_table.gd` | The rules: blinds, betting rounds, side pots, showdown. No nodes, so it runs headless |
| `src/crew/play_style.gd` | The five styles (Rock, Maniac, Shark, Calling Station, Bluffer) as numbers |
| `src/crew/table_talk.gd` | Signals between teammates, and misreads when the bond is weak |
| `src/crew/table_reads.gd` | What a watchful player learns: who re-raises when bet into |
| `src/ai/poker_bot.gd` | An AI seat: equity + style, soft play, reacts to signals |
| `src/match/team_match.gd` | Crew vs crew: rising blinds, fines and ejections, who's out, who won |
| `src/match/dealer.gd` | Who's watching: street (nobody), asleep, relaxed, watchful, strict, bought |
| `src/match/heat.gd` | Each crew's Heat: warnings, fines, ejections |
| `src/ui/table_view.gd` | The placeholder table scene (everything drawn from code) |
| `src/ui/card_art.gd` | Placeholder cards with pixel suits |
| `scenes/table.tscn` | The table; embeddable (`setup`, `dealer_kind`, `starting_chips`, `embedded`, `finished(won)`) and still runnable on its own |
| `scenes/title.tscn`, `src/game/title_screen.gd` | Main scene: Continue / New game |
| `src/game/game.gd` | The `Game` autoload: the run's state, saving, scene changes, dev flags |
| `src/game/game_state.gd` | The run: roster, party, money, bracelets, beaten crews, position; what wins, blackouts and recruits do |
| `src/game/save_file.gd` | GameState to user:// JSON, written atomically |
| `scenes/world/overworld.tscn`, `src/world/overworld.gd` | Walking, talking, encounters, handing over to the table and back |
| `src/world/world_map.gd` | The maps as text, with their crews, townsfolk, signs and doors; line of sight |
| `src/world/map_view.gd` | Paints a map: tile art if present, placeholders if not |
| `src/world/critter.gd` | Anyone walking around; placeholder animals drawn from rectangles |
| `src/world/sprite_bank.gd` | Finds `assets/sprites/<id>.png` and `assets/tiles/<name>.png` if they exist |
| `src/world/dialog_box.gd`, `choice_menu.gd`, `party_screen.gd`, `demo_complete.gd`, `ui_kit.gd` | The overworld's screens and their shared look |
| `tests/` | Test runner and tests |
| `tools/` | Evaluator check, balance simulator, chip-flow analysis, Heat report, input-map writer |
| `scripts/cloud_setup.sh` | Installs Godot in Claude Code cloud sessions |

## Next steps

1. Play it. Is setting up a teammate fun? Do the signals matter? Is a road
   match the right length (500 chips each now), and the road the right
   number of matches before the Open?
2. Recheck the type chart (`tools/simulate.gd --cycle` on fresh seeds) after any change to the bot or the styles.
3. Play against each dealer: is Heat a choice you weigh, or just a tax?
4. Real art: an Aseprite palette, the Aseprite Wizard plugin, animal sprites at the seats.
5. Export presets for Linux (native on the Deck) and Windows, then GodotSteam.
