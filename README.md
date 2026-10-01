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

51 tests, about 13 seconds. They cover hand ranking, equity against known odds
(AA vs a random hand ~85%), blinds and action order (including heads-up and
going heads-up), side pots, split pots and odd chips, uncalled bets, busted
seats, fines as dead money (in the main pot), full bot matches, soft play
between teammates, signals, and Heat: what signals cost, cooling, one
warning per episode, fines, ejections, bought dealers, catching a boss, and
careful animals going quiet.

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
godot --headless --path . -s tools/simulate.gd -- 80 7 --cycle # only the five type-chart links (also --pairs=, --styles=, --iterations=)
godot --headless --path . -s tools/chip_flow.gd -- MANIAC SHARK 40   # why a matchup goes the way it does
godot --headless --path . -s tools/heat_report.gd -- 30 1 STRICT     # how often a dealer warns, fines, ejects each style
godot --headless --path . -s tools/setup_input_map.gd         # rewrite the input actions in project.godot
python3 tools/make_sfx.py --music                             # rebuild the placeholder sounds (assets/audio/README.md)
```

Taking a screenshot without a display (how the screenshots in development
were made): `xvfb-run godot --path . --rendering-driver opengl3 -- --autoplay
--screenshot=out.png --shot-after=5`.

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
| `src/poker/holdem_table.gd` | The rules: blinds, betting rounds, side pots, uncalled bets, dead money, showdown. No nodes, so it runs headless |
| `src/crew/play_style.gd` | The five styles (Rock, Maniac, Shark, Calling Station, Bluffer) as numbers |
| `src/crew/table_talk.gd` | Signals between teammates, and misreads when the bond is weak |
| `src/crew/table_reads.gd` | What a watchful player learns: who re-raises when bet into |
| `src/ai/poker_bot.gd` | An AI seat: equity + style, soft play, reacts to signals |
| `src/match/team_match.gd` | Crew vs crew: rising blinds, fines and ejections, who's out, who won |
| `src/match/dealer.gd` | Who's watching: street (nobody), asleep, relaxed, watchful, strict, bought |
| `src/match/heat.gd` | Each crew's Heat: warnings, fines, ejections |
| `src/ui/table_view.gd` | The placeholder table scene (everything drawn from code) |
| `src/ui/card_art.gd` | Placeholder cards with pixel suits |
| `src/audio/sfx.gd` | The `Sfx` autoload: plays sounds by name from a pool, with per-play pitch/volume variation; no-op without an audio device |
| `assets/audio/` | Placeholder sound effects and a lounge loop, generated by `tools/make_sfx.py`; its README lists every sound and where to trigger it |
| `scenes/table.tscn` | Main scene |
| `tests/` | Test runner and tests |
| `tools/` | Evaluator check, balance simulator, chip-flow analysis, Heat report, rules soak, input-map writer, `make_sfx.py` (synthesizes and measures the placeholder audio) |
| `scripts/cloud_setup.sh` | Installs Godot in Claude Code cloud sessions |
| `export_presets.cfg` | Linux and Windows x86_64 release exports (README "Building") |
| `scripts/export.sh` | Exports both presets headless into `build/` |
| `.github/workflows/build.yml` | CI: exports both builds on main and tags, uploads them as artifacts |
| `steam/` | SteamPipe upload scripts and a Steam Input action manifest, as templates with placeholder IDs |
| `docs/STEAM_DECK.md` | What Steam and Deck Verified need, verified vs from the docs |

## Next steps

1. Play it. Is setting up a teammate fun? Do the signals matter?
2. Recheck the type chart (`tools/simulate.gd --cycle` on fresh seeds) after any change to the bot or the styles.
3. Play against each dealer: is Heat a choice you weigh, or just a tax?
4. Real art: an Aseprite palette, the Aseprite Wizard plugin, animal sprites at the seats.
5. GodotSteam, then a default Steam Input configuration so the back buttons reach the game (docs/STEAM_DECK.md section 2).
