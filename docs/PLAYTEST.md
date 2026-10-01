# The playtester

`tools/playtest.gd` plays the demo the way a restless player would, from the
title screen, and checks the run on every frame. `tools/playtest.sh` runs it
in batches: hundreds of runs with skipped matches, a few with real matches,
kill -9 at random moments, and every kind of damaged save. It exists to find
the bugs that only show up in the full loop (since demo 2: the intro, the
dog alone in Sootbridge finding the four Aces, the gate, the Mill Road,
Mossbank's open table and the crew that joins there; then walk, encounter,
table, recruit, blackout, save, quit, continue) before a person does.

```
tools/playtest.sh runs 200 1        # 200 runs, seeds 1-200, matches skipped (~25 s each; every 10th from a pre-demo save)
tools/playtest.sh real 12 1001      # 12 runs with real matches (a few minutes each)
tools/playtest.sh kill 150 1        # kill -9 mid-play and mid-save, then Continue, 150 times
tools/playtest.sh damaged           # one run per kind of damaged save (list below)
tools/playtest.sh summary           # failures with seeds and replay commands, and stats
```

Set `GODOT` to the binary (default `godot`), `JOBS` to how many Godot
processes may run at once (default 2) and `OUT` to where results go
(default `/tmp/playtest`). Each run gets its own `XDG_DATA_HOME`, so it never
touches a real save or the settings file.

One run by hand (a failure prints exactly this as its replay command):

```
XDG_DATA_HOME=$(mktemp -d) godot --headless --fixed-fps 60 --path . \
    -s tools/playtest.gd -- --pt-seed=7 --pt-verbose
```

## How it plays

It's a SceneTree script (`-s`), not a mode in the game: it opens the title
scene and drives the real scenes with real input, `Input.parse_input_event`
for presses and held actions for walking, as a controller would. It reads a
few of the scenes' private fields to know what's on screen (always through
`get()`, so a rename blinds it rather than crashing it). The game needed no
hooks.

- **Title**: Continue, or New game (sometimes it looks at New game when
  there's a save, and says No to starting over). A new game plays the
  intro: its dialogs get A (sometimes B), and the window may close in the
  middle of it.
- **The opening** (docs/DEMO_SPEC.md): in Sootbridge the progress goal is
  the Aces: walk onto a card still lying about (the gutter, the coal yard's
  dead end, inside the washhouse), talk to Mags for hers, then out through
  the gate and along the Mill Road to Mossbank. Besides that, at random:
  walk into the gate whatever the deck holds (short of Aces it must say no
  and keep you on the town side), step on a card's spot again after it's
  taken (nothing must happen), talk to everyone. In Mossbank, with no crew,
  the goal is the open table: talk to one of its players and the seat offer
  ("Sit in?") gets yes 70% of the time, Not now or B otherwise; later it
  goes back now and then for another session. Before the crew it also walks
  into Ridge Road crews' sight (they must leave a dog alone).
- **Open-table sessions**: 70% with a bot in your seat that gets up after
  1-4 hands (TableView's `autoplay` and the `cash-hands` dev flag, set in
  `Game.dev_args` as the table is added), A skipping the pause between
  hands; 30% by random presses on your turn (`--pt-cash-human`), with Start
  or B between hands (and Start mid-hand) opening "Leave the table?",
  answered with leave, Stay or B until 1-4 hands are played (`--pt-cash-hands`),
  then leave. Busting or cleaning the table out ends it on A. A few hands at
  a few hundred frames each keeps a fast run at about 25 s.
- **Walking**, picked at random each time it's free to walk: walk (shortest
  path, around walls and anyone standing, never through a door it didn't
  mean to take) to the hall door or into the hall to talk to the Regulars,
  into a crew's line of sight, to a door, to a random cell; talk to a
  townsperson, a crew member (beaten or not) or a sign, facing them and
  pressing A (across the diner's counter for Rosie); wander a few steps in a
  random direction; bump into a wall for a moment; press A at nothing; open
  the start menu; stand where someone stood when the map loaded (a recruit's
  spot, a crew's home after it walked over) and quit; quit and continue.
  One step at a time: the next step is chosen when the last one lands.
- **Menus and screens**: dialogs are advanced with A (sometimes B); the start
  menu picks any option or backs out with B or Start; questions (recruit,
  rest at the diner) get a random answer or B; the party screen gets random
  up / down / A / B presses until it closes; options get random changes.
- **Matches**: skipped with a random result (`--pt-win`, 0.6 by default),
  set through the same `match-result` dev flag the game reads, decided each
  time you're free to walk again; or, with `--pt-real`, played at the real
  table: a bot plays your seat (autoplay), or with `--pt-human` the driver
  presses random buttons on the table's menu (moves, A, B, raise sizes,
  signals, help). Between hands it presses A to skip the pause.
- **Quitting**: quit and continue through the title, with or without saving
  first (a window close saves, a crash doesn't); close the window at a random
  moment outside walking (mid-dialog, mid-encounter, mid-fade, on the party
  screen, rarely mid-match), which saves through the game's own close
  handler; lose focus at random moments (which saves).

Headless with `--fixed-fps 60`, every frame is exactly 1/60 s of game time
however fast it runs, so the overworld runs at 20-25x real speed (a run of
20 game minutes takes about a minute) and a run with skipped matches
replays exactly from its seed (checked: same seed,
same frames, same final save). Tables too: the table's clock is the frame
delta now (the hook proposed in "Speeding up real matches" below went in),
and the playtester gives each table a seed of its own from the run's
(`Game.dev_args["seed"]`, which TableView reads), so open-table sessions and
real matches replay as well; only a run cut short by the wall-clock budget
(`--pt-seconds`) can end differently.

## What it checks

A failure ends the run (unless `--pt-keep-going`) and reports its kind, the
last 60 things the driver did, and the replay command.

| Kind | Check |
| --- | --- |
| `script_error` | Any error logged (a Logger, as tests/run_tests.gd installs) |
| `softlock` | Nothing on screen changes for 30 game seconds (mode, map, every actor's position and facing, the fade, every dialog, menu and screen's state, the party) |
| `softlock_table`, `match_too_long` | A real table unchanged for 90 game seconds, or a match over 15 game minutes |
| `position_desync`, `in_wall`, `out_of_bounds`, `on_someone` | Whenever you're free to walk: you're where the save state says, on a walkable cell, on the map, and not on anyone |
| `trapped` | No door reachable from where you stand (every 30 frames) |
| `followers` | Your followers match the party, seat by seat |
| `save_unreadable`, `save_roundtrip`, `save_leftover`, `save_failed` | Every save reads back identical to the state just saved, with no `.part` left |
| `continue_mismatch` | After quitting, Continue brings back exactly the last save (moving you off a cell someone now stands on is allowed) |
| `money_negative` | Money is never below 0 |
| `party_size`, `party_index`, `party_duplicate` | While walking: nobody seated while the roster is empty (the dog alone), else two (as many as the roster allows), real roster entries, nobody twice |
| `roster_duplicate`, `roster_stranger` | Nobody in the roster twice; nobody but Sage and Bandit (the open table's two) and animals from crews you beat |
| `crew_early`, `crew_missing`, `crew_join` | Nobody in the roster before the open table (a new game's run); Sage and Bandit in it once you've sat there, and right after the first session |
| `spotted_alone` | A crew dealt in a dog with an empty party (spotting, or talking to one) |
| `deck_size`, `deck_cards`, `deck_pickups`, `deck_shrank`, `deck_pickup`, `pickup_unknown` | 48 to 52 cards, only Aces missing, each Ace held exactly when its pickup (or Mags's gift) is taken, so 52 iff all four; the deck never shrinks, and each pickup adds exactly one card (a pre-demo save's run: all 52) |
| `pickup_reappeared`, `pickup_hidden` | While walking, the cards drawn on the ground are exactly the ones still waiting |
| `gate_bypassed`, `gate_refused` | With Aces missing you're never anywhere that can't be reached from the start with the gates shut (the Mill Road, Mossbank, past the gate cells); the gate never refuses a full deck |
| `cash_buy_in`, `cash_money`, `cash_seats` | Sitting down takes exactly the buy-in; getting up: money = before - buy-in + the chips you left with, which are the stack the table showed; you (the dog) at seat 0, each seat its own team, nobody from your crew at the table |
| `joined_still_standing` | Sage and Bandit stop standing at the table once they've joined |
| `old_save_load` | `--pt-start=old`: a pre-demo save loads with all 52 cards, opening_done, its roster, party, map and cell |
| `bracelet`, `beaten_unknown` | The bracelet exactly when the Regulars are beaten; beaten crews exist |
| `match_outcome` | A win pays the crew's reward and marks it beaten (and the Open gives the bracelet); a loss wakes you at the diner with half your money |
| `progress_lost`, `save_lost` | Kill torture: the save left by a kill always loads, and no crew beaten, animal recruited, card taken or pickup recorded in an earlier save is gone |
| `crash_or_timeout` | The run didn't report at all (killed by the batch timeout or crashed) |

Notes (not failures) record what's worth knowing: `blackout_skipped`,
`recruit_skipped`, `bracelet_pending` (the window closed between a match's
end and its outcome being saved), `short_party_saved`, `cash_forfeited`
(the window closed at the open table: the buy-in is gone, by design),
`crew_join_pending` (a save between getting up from the first sit and Sage
and Bandit joining: see "What it found"), `stranded` (a dog alone with
less than the buy-in: see "What it found"). The batch for damaged
saves is lenient about `roster_stranger` and `beaten_unknown`, which a
damaged save can legitimately cause.

## Flags

All after `--`, prefixed `--pt-`: `seed`, `frames` (game frames, not counting
real tables; default 30 game minutes), `seconds` (wall clock, default 900),
`cash-human` (chance an open-table session is played by random presses,
default 0.3), `cash-hands` (a session gets up after 1 to this many hands,
default 4),
`after` (decisions to keep playing after the demo-complete screen, default
300), `real` and `human` (chance a match is played, and played by random
presses rather than a bot), `win`, `reload` (chance per decision to quit and
continue), `close` and `focus` (chance per frame), `chips` (starting chips at
real crew tables), `start` (`new`; `continue`; `old`, a pre-demo save
written first, as damage `pre_demo`; `mix`, old on every 10th seed and new
otherwise, which `playtest.sh runs` uses), `slot` (save slot name, default
`playtest`), `damage=KIND`, `save-spam=N` (N extra saves every frame, for the
kill torture), `lenient=kind,kind`, `keep-going`, `verbose`, `out=FILE`
(appends the result as one JSON line).

Damaged save kinds (`--pt-damage`), each written over a mid-game save (the
four Aces, the open table sat at with Sage and Bandit along, one crew
beaten, a goose recruited): `ok truncated empty garbage array minimal
no_version future_version unknown_species all_unknown_species roster_dict
roster_one roster_dupes party_oob party_negative party_dup party_one
party_three party_strings money_negative money_string money_huge cell_wall
cell_oob cell_string cell_crew_home cell_recruit_home cell_door map_unknown
heal_wall heal_oob heal_map_unknown beaten_unknown beaten_regulars_no_bracelet
bracelet_only facing_zero facing_weird bond_weird unbeaten_member_in_roster
seen_intro_false part_only part_newer_main_truncated`, and since demo 2
`pre_demo` (no deck fields: must load past the opening), `pre_demo_alone`,
`deck_short_in_town`, `deck_garbage`, `deck_dupes`, `deck_oob`,
`taken_unknown`, `alone_met_table` (sat, nobody joined) and
`alone_before_table`. The damaged batch is also lenient about the deck and
gate checks, which a damaged deck legitimately breaks.

## Runs so far (2026-10-01, on the fixes below)

- **200 runs with skipped matches** (seeds 1-200, `--pt-after=120`): 37 min
  at 2 processes, 22 s a run on average. 197 passed; the 3 failures were
  the driver's own (fixed, and those seeds pass now). The demo was
  completed in 198 of 200 runs (median 117 game seconds to the bracelet,
  longest 430). In all: 533,121 steps, 2,020 encounters (981 won, 611 lost,
  the rest cut short by a quit), 448 recruits, 6,683 talks, 6,323 doors,
  1,485 start menus, 2,271 quit-and-continues, 1,675 window closes, 13,831
  focus-loss saves and 31,213 saves read back.
- **12 runs with real matches** (seeds 1001-1012, chips 200, a quarter of
  the matches played by random presses, the rest by a bot in your seat):
  all passed and all completed the demo, in 19-42 minutes each (6 hours of
  wall clock in all). 143 real matches: median 149 s, longest 382 s (the
  Open). These runs also took the title's New game detour 143 times, which
  is what found the Start over? bug below.
- **Kill torture**: 300 kills at random moments (0.3-6.3 s into a run, a
  third of them while saving 100 or 2,000 extra times a frame), each
  followed by a run that loads what was left. 17 kills landed mid-save
  (a `.part` left behind, from 0 bytes to complete); the save always
  loaded, passed the state checks, and never lost a beaten crew or a
  recruit an earlier save had. On Linux the rename is atomic and this is
  what it promises; the `.part` fallback (below) covers platforms where it
  isn't.
- **Damaged saves**: every kind, twice (before and after the fixes): all
  load without a script error and play on, except a roster holding an
  unbeaten crew's leader (reported below).

- **With the Open's final as a 3v4 boss table** (2026-10-01): 20 runs
  with skipped matches (seeds 12001-12020) all passed and all completed
  the demo (median 129 game seconds to the bracelet); one run with real
  matches (seed 13001, chips 200) passed, played 10 real matches and won
  the 3v4 Open at the 7-seat table, 1,476 s of wall clock in all.

## What it found

Fixed (each with a test in `tests/test_save_safety.gd` where it's logic):

1. **A script error on every start from the title** (Continue or New
   game): the scene change takes the title out of the tree at once, and
   `get_viewport()` was null after it. (`src/game/title_screen.gd`)
2. **The "Start over?" question never showed**: a typed/untyped ternary
   in the title's `_draw` errored every frame of it, so New game over a save
   looked like nothing happened. (`src/game/title_screen.gd`)
3. **Continue sent you home** when you'd saved on a spot the map counts as
   taken: where a recruit stood, or a crew's home after it walked over to
   you. Found on 2 of the first 5 seeds. Now you continue on the nearest
   open cell (`WorldMap.open_cell_near`, `standing_cells`).
4. **A short party stayed short**: a party saved with one seat filled
   (the window closed, or focus lost, while re-seating on the party screen:
   93 times in 200 runs) loaded that way and the next match was two
   against three. Loading fills the empty seats; party seats also follow
   their animals past dropped roster entries, and an animal saved twice
   loads once.
5. **The Open could become unwinnable**: closing the window during "You
   beat the Regulars!" saves them beaten (the win is recorded before the
   dialog) without the bracelet (given after it), and they never play again
   (53 times in 200 runs). Loading gives a beaten tournament its bracelet.
6. Damaged saves: a roster that lost its animals gets the starters back; a
   blackout cell in a wall (or off the map) falls back to the diner's
   booth; a complete `.part` is read when the save itself is missing or
   unreadable (a crash between removing the old save and renaming, where
   the platform won't rename over a file).

Reported, not fixed (in code other work owns this round):

- **Closing during the blackout dialog skips the blackout** (64 times in
  200 runs): the last save is from before the match, so Continue puts you
  back on the road with all your money. `_blackout` could apply
  `state.blackout()` and save before its first line.
- **Closing during the win dialogs loses the recruit offer** (136 in 200):
  the crew is saved beaten, and the offer only comes after the dialog.
- **A crew whose leader is in your roster crashes the encounter**
  (`_encounter`: the leader node is null), then softlocks. Only through a
  damaged save or the `--recruit` dev flag, since every individual is in
  one crew only. Repro: `godot --headless --path . -- --save-slot=dev --new
  --skip-intro --recruit=cat:0 --at=town,50,9 --walk=U2 --auto
  --match-result=win` (overworld.gd `_encounter`, `leader.alert` on null).
- After the bracelet is repaired on load (5 above), the demo-complete
  screen was never shown for that run.

## What it can't check

How anything looks or feels (it runs headless, so nothing is drawn), real
controllers (it presses input actions; `tests/pad_check.tscn` covers the
pad's buttons and triggers reaching them), sound, the exported build, Steam. Real matches play at real
speed, so there are few of them. A kill on Linux can't test a power cut: the
data is in the page cache once written, so a missing fsync can't show up
(Godot's FileAccess has no fsync).

## Speeding up real matches (a proposal for table_view.gd)

The table measures every beat (deals, flips, chip slides, bot thinking, the
2.6 s pause between hands) on `_now()`, which is the wall clock
(`Time.get_ticks_msec()`). Engine.time_scale and `--fixed-fps` don't touch
it, so a real road match takes minutes even in a headless run that does
everything else at 20x or more. The hook:

1. `var _clock := 0.0`, set to `Time.get_ticks_msec() / 1000.0` in `_ready()`;
   `_now()` returns `_clock`; the first line of `_process(delta)` is
   `_clock += delta`. Process delta already honours `Engine.time_scale`
   and `--fixed-fps`, so no new flag is needed: in a normal game delta is
   real time and nothing changes; under the playtester a match runs as fast
   as the CPU allows.
2. The three other wall-clock reads move to the same clock: `_alert_until`
   (`_dealer_says`, `_process`, `_draw_text_box`) and the bubbles' expiry
   (`_show_new_signals`, `_process`), e.g. `_now() * 1000.0` instead of
   `Time.get_ticks_msec()`.
3. For replays, a `seed` the embedding scene can set (embedded, the table
   ignores `--seed`, and seeds from `Time.get_ticks_usec()` and the Unix
   time otherwise): `_rng`, `TeamMatch.new()` and the bot seeds would use it.

TableMotion takes times from its callers, so it needs nothing.

Measured, with steps 1 and 2 applied in a scratch copy (not committed;
table_view.gd is someone else's this round) and the playtester's 15 ms
sleep at tables turned off: seed 1001 with real matches (chips 200, a
quarter of them played by random presses) played the whole demo, 10 real
matches, in 139 s, against 1,512 s for the same flags without the hook
(road matches 3-18 s instead of 28-165 s; the Open 23 s instead of 314 s),
with no failures. With the hook a dozen real-match runs would take minutes
instead of hours, and real matches could join the regular batches.
