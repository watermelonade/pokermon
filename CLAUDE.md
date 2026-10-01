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

## Running and testing

```
godot --headless --path . --import                # after adding or renaming a class_name script
godot --headless --path . -s tests/run_tests.gd   # all tests, ~2s
godot --headless --path . -s tools/simulate.gd -- 40 7   # play-style balance
```

- New `class_name` scripts aren't visible to other scripts until the import
  above refreshes the class cache: "Identifier not declared" usually means
  that, not a typo.
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
- **Can't verify:** feel and timing, real controllers, the Steam Deck's back
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
- **The rules engine stays headless.** `src/poker/` and `src/match/` never
  touch nodes or drawing, so tests and simulations run thousands of hands.
- **Code style:** module docstrings explain *why* something is built the way
  it is, including what was tried and measured. Update them, don't delete.
- **README.md** is updated alongside features, including measured results.
- **Commits:** small and descriptive, ending with a `Co-Authored-By:` line for Claude.
