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
the town's tournament. The first goal is to find out whether one table is fun.

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
and the demo-complete screen. Start (or Tab) opens the menu: Crew (pick
which two animals sit with you), Save, Options (text speed, volume).

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

| Overworld | Keyboard | Controller / Steam Deck |
| --- | --- | --- |
| Walk | arrows or WASD | D-pad or left stick |
| Talk, read, confirm | Enter / Space | A |
| Back | Esc | B |
| Menu (Crew, Save, Options) | Tab / Esc | Start |

| Table | Keyboard | Controller / Steam Deck |
| --- | --- | --- |
| Move the cursor in the command menu (Call, Raise, Fold, Help) | arrow keys | D-pad or left stick |
| Choose | Enter / Space | A |
| Back (close the raise picker or help) | Escape | B |
| Raise size: min, half pot, pot, 2x pot, all-in | Q / E | LB / RB |
| In the raise picker: one big blind more / less | up / down | D-pad up / down |
| Signal your teammates | 1 2 3 4 | back buttons L4 R4 L5 R5 |
| Help card (controls, signals, Heat) | H or F1 | Select |
| Next hand (it also moves on by itself) | Enter | A |
| Tutorial: next line / skip the lesson | Enter / Tab | A / Start |

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

### The tutorial

A new game ends its intro with Rosie (from the diner) offering to show you
how the tables work; after that it's on her menu at the diner ("A table
lesson"), as often as you like. It's five set-up hands at her back table,
about five minutes, one lesson each, taught by doing:

1. **The table**: your cards and the gold words saying what you hold, the
   command menu; you raise a pair of Kings, your teammate folds out of your
   way (soft play), and three Kings win.
2. **A teammate's signal**: Bandit touches his nose ("I'm strong") and
   raises; you step aside with a good hand and the chips stay in the crew.
3. **Your signal**: two Aces; Rosie asks you to touch your nose (1 / L4),
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

```
godot --headless --path . --import            # once, and after adding a class_name script
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tests/run_tests.gd -- side_pot   # only matching tests
```

119 tests, about 15 seconds. They cover hand ranking, equity against known odds
(AA vs a random hand ~85%), blinds and action order (including heads-up and
going heads-up), side pots, split pots and odd chips, uncalled bets, busted
seats, fines as dead money (in the main pot), full bot matches, soft play
between teammates, signals, and Heat: what signals cost, cooling, one
warning per episode, fines, ejections, bought dealers, catching a boss, and
careful animals going quiet. For the overworld: every
map is rectangular and closed, everyone stands somewhere they can stand,
doors lead somewhere free, line of sight (straight ahead, stopped by walls
and bodies), the walk-up path, that two crews can't be snuck past and two
can, and that beaten crews don't block the road; and for the run: seating
for the table, the party, recruiting (each individual once), win money,
blackouts (half your money, the odd coin kept), and a save round trip,
including damaged and missing saves (and saves from before the tutorial);
the tutorial: each lesson deals its cards from the right button, following
Rosie produces its situation (your teammate folds to your raise; Bandit
signals and wins; both teammates fold to your signal; Scraps raises the
river with a hand that is its bluffing tell, and calling wins; two signals
under the strict dealer warn but don't fine), five other ways of playing
every hand (always fold, call, shove...) still finish all five lessons with
no chips made or lost, no fine and no ejection, signals that would reach a
fine are refused, skipping, and every line fits the text box; and that missing art falls back to
placeholders and a sprite sheet is cut into walk frames and facings.

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
`--show=start`, `--show=options`, `--show=demo_complete`, `--recruit=cat:1`, `--beaten=all` and
`--money=` jump to a state; any dev flag also prints what happens
(encounters, results, saves) to the terminal.

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

**The overworld:** checked with scripted runs under a virtual display
(`--walk`, `--auto`) and screenshots of each step: the title, the town with
the intro, a crew's "!" and walk-up, its dialogue, the recruit menu after a
win (the save then has the money, the crew beaten and the recruit), a
blackout waking at the diner with half the money, the party screen, the
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

## Layout

| Path | What it is |
| --- | --- |
| `project.godot` | 640x400 base resolution, integer-scaled x2 to the Deck's 1280x800, nearest-neighbour filtering, GL Compatibility renderer, input actions, the Game autoload, saves in a custom user dir (`AFriendInNeed`) |
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
| `src/ui/table_view.gd` | The table scene: layout, flow, input, drawing (placeholder art drawn from code) |
| `src/ui/card_art.gd` | Placeholder cards with pixel suits |
| `src/audio/sfx.gd` | The `Sfx` autoload: plays sounds by name from a pool, with per-play pitch/volume variation; no-op without an audio device |
| `assets/audio/` | Placeholder sound effects and a lounge loop, generated by `tools/make_sfx.py`; its README lists every sound and where to trigger it |
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
| `src/world/dialog_box.gd`, `choice_menu.gd`, `party_screen.gd`, `options_screen.gd`, `demo_complete.gd`, `ui_kit.gd` | The overworld's screens (text box, Start menu, crew, options, the end) and their shared look |
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
| `tests/` | Test runner and tests |
| `tools/` | Evaluator check, balance simulator, chip-flow analysis, Heat report, rules soak, input-map writer, `make_sfx.py` (synthesizes and measures the placeholder audio) |
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
