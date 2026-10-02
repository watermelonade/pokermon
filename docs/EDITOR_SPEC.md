# The editor: spec (test-first)

The owner builds the game by spending time in it: an edit mode in the
running game where maps, characters, items, signs and dialogue are changed
in place, and those changes ARE the game from then on (Claude builds on
them, never recreates them). Writers come in later and work on the words
without touching maps. Built test-first like docs/DEMO_SPEC.md: outcomes
first, each with the test that checks it; done when `tools/test.sh full`
passes.

## Decisions (2026-10-02, the owner)

- **Portable:** PC first (Steam), mobile later (Android, iOS), so the game
  stays pure Godot with plain data files: no native plugins, no
  platform-only code. Touch controls come when mobile is targeted.
- **The editor is a developer tool,** used on a PC with mouse and keyboard,
  in source runs only. It is never exported to players.
- **Content is data:** everything the editor touches lives in `content/`,
  loaded by the game and saved by the editor. Files stay diff-readable
  (maps keep their rows of characters) so every change can be read in git.
- **Organised by area,** with an atlas of how areas connect.
- **Staged for writers:** text lives apart from placement, and every line
  has an id and a status (placeholder, draft, final).

## Phases

| Phase | What | Status |
| --- | --- | --- |
| 1 | Content out of code into `content/`, zero change in play | specified below |
| 2 | Edit mode core: toggle, free camera, atlas view, tile painting, save, undo, play from here | outline |
| 3 | Placing and editing things: NPCs, crews, items, signs, doors, open tables; an inspector (what an NPC gives) | outline |
| 4 | Words in place: type into dialog boxes, dialog choices (the dog's gestures), line status | outline |
| 5 | Notes for Claude pinned in the world; getting edits back (e.g. "Save & send") | outline |

Phases 2-5 get their outcome tables (and tests) before each is built.

## Phase 1: content out of code

### The format

- `content/atlas.json`: every area: `id`, `name` (shown on entering),
  `region` (e.g. "Sootbridge", "Mossbank"), `kind` (town, route,
  interior), `status` (blockout, draft, final), `notes`. Connections are
  NOT stored here: they are derived from the maps' doors (warps), so they
  can't drift.
- `content/maps/<id>.json`: one per map: `outdoor`, `rows` (the text grid,
  one string per row, the existing tile legend), `labels`, and placed
  things: `warps`, `signs`, `npcs`, `crews`, `pickups`, `gates`, with
  their mechanics (cells, facing, sight, members, rewards, dealer, chips,
  what they give, open-table setups). No dialogue text: placed things
  refer to their lines by id.
- `content/dialogue/<id>.json`: the words for that map's speakers and
  signs: for each speaker or sign, its lines in order, each line
  `{"id", "text", "status"}`. Crews' "before" and "after" lines, npc
  lines, sign text, open-table players' lines.
- `content/script/intro.json` (and similar): narration that belongs to no
  map: the intro night.
- Cells are `[x, y]` arrays; enum values (facing, dealer kind, species)
  are names (`"down"`, `"STREET"`, `"owl"`), never numbers, so files stay
  readable and survive enum reordering.
- **Canonical form:** one formatter writes every content file (fixed key
  order, 2-space indent, rows one per line, trailing newline). Loading a
  file and saving it again gives the same bytes, so an editor save only
  changes what was changed.
- Line ids are stable and unique across the whole game
  (`<map>.<speaker>.<n>`, e.g. `sootbridge.mags.1`); a renamed speaker keeps
  its old ids. Existing lines start as `placeholder`.

### Outcomes

| ID | Outcome | Test |
| --- | --- | --- |
| C-SAME | The game's world is identical before and after the move: a snapshot of every map, npc, crew, sign, pickup, gate, warp, label and line, taken from today's code BEFORE the move and committed as a fixture, equals what the content loader gives. | test_content (golden) |
| C-ROUND | Every content file, loaded and saved by the canonical formatter, is byte-identical to itself. | test_content |
| C-SCHEMA | Every content file is valid: required keys, known tiles, cells inside the map, known enum names, warps to maps that exist and land on walkable cells, every placed speaker or sign has its lines, every line id is unique, every status is placeholder/draft/final, every atlas area has a map and every map an atlas entry. Invalid content fails with a message naming the file and the field. | test_content |
| C-NOCODE | No dialogue or sign text is left in `src/` for overworld content (a test scans `world_map.gd`, `overworld.gd`, `open_table.gd` for the old lines). System text (menus, "You found the Ace of Spades!") may stay in code. | test_content |
| C-CHECKS | The checks the editor will run live exist as a library (`src/content/content_checks.gd`) the tests also use: reachable doors, nobody blocking the only path, every pickup reachable, lines fitting the dialog box (docs/WRITING.md). The demo's W-* tests call it instead of their own copies where they overlap. | test_content, test_demo_world |
| C-EXPORT | An exported build includes `content/` and excludes editor-only code (`src/editor/`, once it exists): checked on the export preset's include/exclude filters. | test_content |
| R-ALL | Everything else unchanged: unit, compile, pad, scene, R-CHART, and the soak (fast, real, kill, damaged saves) all pass. Saves from before the move load. | tools/test.sh full, soak |

### Who builds it

One agent, on branch `editor/content`. The C-SAME fixture is generated and
committed first, before any data moves (that commit is the red-to-green
baseline). Existing tests that read `WorldMap.MAPS` change to the loader
in the same commit as the move.

## Open questions

- Getting edits back: a "Save & send" button that commits and pushes the
  owner's edits to their own branch, or the owner using git directly?
- How much of the poker table's text (and Rosie's lessons) becomes editable
  content, and when?
