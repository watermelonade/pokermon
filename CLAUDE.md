# CLAUDE.md

Guidance for Claude Code sessions on this repo, including cloud sessions.
README.md has how to run it, what's been measured, and a map of every file.
The game design lives in the design doc linked from docs/DESIGN.md.

## Project

**A Friend in Need**: a whimsical pixel-art RPG where you train animals to
play team Texas hold'em (your crew of 3 vs theirs, secret signals between
teammates), built in Godot 4.7 with GDScript, Steam Deck first, for release
on Steam. The owner has limited art experience and uses pixel-art tools
(Aseprite); everything visual is placeholder, drawn from code, until real
art exists.

## Talking with the owner: audio sessions

The owner sometimes dictates by voice and sends several short messages to
get a thought out. When they say **"start audio session"**:

- Confirm once, then answer every following message with only "…": no
  work, no tool calls, no answers, no reports from background agents (hold
  those until the trigger).
- **"go ahead Claude"** (or close to it, e.g. "Claude, go ahead and
  respond") is the trigger: read everything since the session started as
  one message, respond in full, and the audio session ends. The next
  message gets a normal reply unless they start a new session.
- **"end audio session"** goes back to normal without a full response.

## Running and testing

```
tools/test.sh quick                               # unit + compile: before every commit (~20s)
tools/test.sh full                                # + pad, scene tests, the type chart: "done" (~1 min)
tools/test.sh unit scene -k S_DECK                # one outcome's tests (also: pad, journey, chart, soak)
godot --headless --path . --import                # after adding or renaming a class_name script
godot --headless --path . -s tests/run_tests.gd   # the unit tests alone
godot --headless --path . -s tools/simulate.gd -- 40 7   # play-style balance
```

`tools/test.sh` (GODOT=path, default `godot`) lists every tier at its top;
README.md "Tests" has them all, the scene tests (the real game from the
title, driven by pad events: `tests/scene/`, `tests/scene_test_case.gd`)
and `tests/expected_red.txt`: tests written before their feature
(docs/DEMO_SPEC.md) report "red" without failing the run, and fail it once
they pass, so whoever makes one pass deletes its line.

- New `class_name` scripts aren't visible to other scripts until the import
  above refreshes the class cache: "Identifier not declared" usually means
  that, not a typo.
- The test runner can't see scene scripts that use the `Game`/`Sfx`
  autoloads (it runs as a SceneTree script, without autoloads), so also run
  `godot --headless --path . res://tests/compile_check.tscn`: it compiles
  every script under src/ (a broken overworld.gd once passed all the tests),
  and `res://tests/pad_check.tscn`: a pretend Xbox pad's buttons and
  triggers signalling at the real table (the triggers go through the
  `Triggers` autoload).
- GDScript has no exceptions. A script error inside a test returns null and
  carries on; `tests/run_tests.gd` catches these with a Logger and fails the
  test. Keep it that way.
- Typed GDScript: `var x := dict["key"]` doesn't compile (the type can't be
  inferred). Write `var x: int = dict["key"]`.

## Cloud sessions

`scripts/cloud_setup.sh` (SessionStart hook in `.claude/settings.json`)
downloads Godot 4.7.2 from GitHub releases and puts it on PATH as `godot`.
Log: `/tmp/cloud_setup.log`.

- **Can verify:** all rules and AI logic through `tests/`; the table scene
  through screenshots: `xvfb-run godot --path . --rendering-driver opengl3
  scenes/table.tscn -- --autoplay --screenshot=out.png --shot-after=5`, and
  the overworld through scripted runs (`--walk=`, `--auto`; flags listed in
  src/game/game.gd, examples in README.md) (Xvfb and Mesa are
  installed in the sandbox).
- **Can't verify:** feel and timing, real controllers
  (`tests/pad_check.tscn` drives the table with pretend Xbox pad events, but
  not a real pad's button mapping), the Steam Deck's back
  buttons (Steam Input only passes them through when the controller layout
  maps them), Steam integration, exported builds. Say so plainly.

## How work is done here

- **Measure, don't assume.** Rules changes get a test with a stacked deck
  (`Deck.stacked`) and an exact expected result; AI and balance changes get
  a `tools/simulate.gd` run before and after, with the numbers in the
  commit message or README.
- **Balance numbers need big samples and fresh seeds.** A matchup at 40
  matches is +-8 points of noise; decide on 240+ per link. Settings picked on
  some seeds regress on others, so report results from seeds the tuning never
  saw, at the game's equity samples (not `--iterations=60`). When a matchup
  is wrong, `tools/chip_flow.gd` shows where the chips go: that found every
  real fix; parameter sweeps found none.
- **The world is data.** Maps, townsfolk, crews, signs and every line
  they say live in `content/` (README "Content", docs/EDITOR_SPEC.md), not
  in code: edit the JSON, then run
  `godot --headless --path . -s tools/format_content.gd` (canonical form,
  then the schema and playability checks). Text the game says about what
  just happened stays in code.
- **The rules engine stays headless.** `src/poker/` and `src/match/` never
  touch nodes or drawing, so tests and simulations run thousands of hands.
- **Code style:** module docstrings explain *why* something is built the way
  it is, including what was tried and measured. Update them, don't delete.
- **README.md** is updated alongside features, including measured results.
- **Commits:** small and descriptive, ending with a `Co-Authored-By:` line for Claude.
