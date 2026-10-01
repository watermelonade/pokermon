# A Friend in Need

A whimsical pixel-art RPG where you train the animals you meet to play team
Texas hold'em, travel from town to town winning tournaments, and finally sit
down inside the painting *Dogs Playing Poker*. Built in Godot 4 for the
Steam Deck first. The full design is in the
[design doc](https://claude.ai/code/artifact/c284c9ac-3915-4b60-9293-ad0b666dede4)
(summary in [docs/DESIGN.md](docs/DESIGN.md)).

This is the starter project: the poker rules, the hand evaluator, the AI play
styles, team signals and a playable placeholder 3v3 table. No overworld or
art yet; the first goal is to find out whether one table is fun.

## Running it

Install [Godot 4.7](https://godotengine.org/download) (the standard build;
the .NET one isn't needed), open `project.godot` in it, and press F5.

| Input | Keyboard | Controller / Steam Deck |
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

## Tests

```
godot --headless --path . --import            # once, and after adding a class_name script
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tests/run_tests.gd -- side_pot   # only matching tests
```

24 tests, about 2 seconds. They cover hand ranking, equity against known odds
(AA vs a random hand ~85%), blinds and action order (including heads-up),
side pots, split pots and odd chips, busted seats, a 600-hand random-play run
that checks no chip is ever created or lost, full bot matches, soft play
between teammates, and signals. The runner fails any test that logs a script
error (GDScript has no exceptions, so a crashing test would otherwise pass).
CI runs the same thing on every push (`.github/workflows/tests.yml`).

## Tools

```
godot --headless --path . -s tools/verify_evaluator.gd        # all 2,598,960 five-card hands
godot --headless --path . -s tools/simulate.gd -- 40 7        # style-vs-style balance, 40 matches a pairing, seed 7
godot --headless --path . -s tools/setup_input_map.gd         # rewrite the input actions in project.godot
```

Taking a screenshot without a display (how the screenshots in development
were made): `xvfb-run godot --path . --rendering-driver opengl3 -- --autoplay
--screenshot=out.png --shot-after=5`.

## Measured so far

**Hand evaluator:** all 2,598,960 five-card hands land in the textbook
category counts (40 straight flushes, 624 quads, ... 1,302,540 high cards),
in 20.7s, so about 8µs per hand. The test suite also compares it with a
brute-force reference on 3,000 random seven-card hands.

**Type chart, first run** (`tools/simulate.gd -- 40 7`: crews of three same-style
bots, 40 matches per pairing, both seatings): the design wants a cycle where
every style beats the next one. Three of the five links hold; two don't yet.

| Intended | Win rate |
| --- | --- |
| Bluffer beats Rock | 33% (no) |
| Rock beats Maniac | 58% |
| Maniac beats Shark | 48% (no, about even) |
| Shark beats Calling Station | 80% |
| Calling Station beats Bluffer | 60% |

The Shark is the strongest style overall: it wins every one of its pairings
(53-85%). Tuning the numbers in `src/crew/play_style.gd` until the
cycle holds is the next balance job, and this tool is how to measure it.
About 0.4s per match, 25 hands per match on average.

**The table on screen:** checked with screenshots under a virtual display:
the preflop decision, a showdown (the right hand wins, the busted seat greys
out). Not checked: how it feels to play, on a real Steam Deck, or with a real
controller.

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | 640x400 base resolution, integer-scaled x2 to the Deck's 1280x800, nearest-neighbour filtering, GL Compatibility renderer, input actions |
| `src/poker/card.gd` | Cards as ints 0-51, parsing and labels |
| `src/poker/deck.gd` | Seeded shuffles (replayable), stacked decks for tests |
| `src/poker/hand_evaluator.gd` | Best five of up to seven cards, as one comparable int |
| `src/poker/equity.gd` | Monte Carlo win chance against N random hands |
| `src/poker/holdem_table.gd` | The rules: blinds, betting rounds, side pots, showdown. No nodes, so it runs headless |
| `src/crew/play_style.gd` | The five styles (Rock, Maniac, Shark, Calling Station, Bluffer) as numbers |
| `src/crew/table_talk.gd` | Signals between teammates, and misreads when the bond is weak |
| `src/ai/poker_bot.gd` | An AI seat: equity + style, soft play, reacts to signals |
| `src/match/team_match.gd` | Crew vs crew: rising blinds, who's out, who won |
| `src/ui/table_view.gd` | The placeholder table scene (everything drawn from code) |
| `src/ui/card_art.gd` | Placeholder cards with pixel suits |
| `scenes/table.tscn` | Main scene |
| `tests/` | Test runner and tests |
| `tools/` | Evaluator check, balance simulator, input-map writer |
| `scripts/cloud_setup.sh` | Installs Godot in Claude Code cloud sessions |

## Next steps

1. Play it. Is setting up a teammate fun? Do the signals matter?
2. Tune the play styles until `tools/simulate.gd` shows the full cycle.
3. Heat: signals add suspicion, and the dealer warns, penalises, ejects.
4. Real art: an Aseprite palette, the Aseprite Wizard plugin, animal sprites at the seats.
5. Export presets for Linux (native on the Deck) and Windows, then GodotSteam.
