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
| 1 | Content out of code into `content/`, zero change in play | done (2026-10-02) |
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

### Phase 1: done

Built test first on branch `editor/content`: the C-SAME snapshot
(`tests/fixtures/world_before_content.json`, by `tools/snapshot_world.tscn`)
and `tests/test_content.gd` were committed red before anything moved, and
each test went green in the commit that built its part. README "Content"
has the layout and how to add a line or a map by hand.

| ID | Test | Result |
| --- | --- | --- |
| C-SAME | `test_C_SAME_the_world_is_the_snapshot` | Every map through `WorldMap` (types included: Vector2i, StringName, int not float) equals the snapshot; the area name on every cell of every map equals what the old `_area_name()` gave; every string literal the old overworld.gd and open_table.gd had is still in the code or now in content/, the intro line for line |
| C-ROUND | `test_C_ROUND_every_file_saves_to_the_same_bytes`, `..._maps_keep_their_rows_one_per_line` | All 17 files: parse and format gives the same bytes, also from compact JSON and with keys reordered |
| C-SCHEMA | `test_C_SCHEMA_the_content_is_valid`, `..._problems_name_the_file_and_the_field` | The content is valid; 15 kinds of breakage each give a message naming the file and the field |
| C-NOCODE | `test_C_NOCODE_no_overworld_text_left_in_the_code` | No string literal in world_map.gd, overworld.gd or open_table.gd is a content line or a line the snapshot had on the maps |
| C-CHECKS | `test_C_CHECKS_the_world_passes_the_editor_checks`, `..._find_each_kind_of_problem` | `src/content/content_checks.gd` finds nothing wrong with the world, and each kind of problem on a made-up yard; tests/world_paths.gd (the W-* and scene tests' walking) and test_writing's measure call it |
| C-EXPORT | `test_C_EXPORT_presets_pack_content_and_leave_out_the_editor` | Both presets: `include_filter="content/*"`, `src/editor/*` excluded. Also exported for real (`--export-pack`): all content in the PCK, a stand-in src/editor/ file not, and the game run from the PCK draws Sootbridge and Mossbank pixel-identical to main |
| R-ALL | `tools/test.sh full`, `soak`, `tools/playtest.sh damaged` | full: unit 217 (0 red), compile, pad, scene 18, R-CHART unchanged. soak: 21 runs (20 fast, 1 real), 0 failed, kill torture 0 failed checks (2 runs from pre-demo saves). damaged: 51 saves, all ok. A save made by main's code continues pixel-identical; README "Content" lists the screenshots compared |

### Phase 1 decisions

- **Placed things name a speaker, not line ids.** An npc, crew, sign or
  gate has `"dialogue": "<speaker>"`; the dialogue file holds that
  speaker's lines. A writer adds, removes or reorders lines without
  touching the map, and an id is a label, not a position.
- **A speaker has sets of lines:** `lines` (townsfolk, signs, gates),
  `before` and `after` (crews), `after` (a townsperson who has given you
  their card), and sets the code asks for by name: Rosie's `offer`,
  `declined`, `rest`, `champ`, `lesson_done`, `lesson_skipped`,
  `blackout`; Sage's and Bandit's `joins`; the Regulars' `won`
  (`Content.CODE_LINES`, which the schema checks). The code reads a set
  (`Content.say(file, speaker, set)`), not single line ids, so a line a
  writer adds is said without a code change.
- **Line ids** are `<file>.<speaker>.<n>` (`<file>` is the map, or the
  script: `intro.night.1`), numbered down the file at the move; a new line
  takes the next unused n, and ids are never renumbered.
- **Scripts have the dialogue files' shape.** The intro's beats are its
  speakers (night, manhole, fall, morning, dawn), so they stay in order;
  `content/script/overworld.json` holds the narration the overworld says
  itself (all four Aces back, a crew sending a dog alone away, the
  blackout).
- **What moved, what stayed:** everything a character says, every sign,
  the gate, the intro and the story narration moved. What the game says
  about what just happened (cards found, money, who joined, "Saved!"), the
  open table's seat prompts and refusals, and the menus stayed in code as
  system text. A line with a value has `{name}` placeholders (`{lost}`,
  `{crew}`), filled with String.format.
- **Names stay with the map.** An npc's or crew's display name and the
  roof labels are in the map file (they're the thing's identity, and the
  labels are part of the map's look), not in dialogue. Writers renaming
  characters is a phase 4 question.
- **Signs, the gate and a crew's `after` are one line each**, as the game
  shows them (one box); the schema says so. Phase 4 can lift it.
- **Areas are places, not maps.** An area has a `map` and, if it's only
  part of one, a `rect`: Mossbank's map (id `town`, kept because saves
  name it) holds three areas, the town, Ridge Road and the hall's plaza,
  which is what the overworld's banner always showed. Area ids may differ
  from map ids; the schema checks every area's map exists and every map
  has an area.
- **Map, crew and pickup ids are unchanged:** saves record them.
- **Open tables are map records** (`open_tables`), their players' npc
  entries naming one by id; in the game each player still carries the
  table's dictionary, as before.
- **Values by name:** facings `"up"`, dealers `"STREET"`, species
  `"owl"`, cards `"As"`; an individual animal stays an index (0-3), as
  `Species.individual` takes it.
- **Every map file has every key** (empty lists included), so an editor
  never adds a key, and an unknown key is an error, not ignored (a typo
  like `"facnig"` fails).
- **The game sees the old shape.** `Content` builds each map in exactly
  the shape the MAPS const had, so `WorldMap`, GameState, the table and
  the tools didn't change; `WorldMap.MAPS`, `OPEN_TABLE` and
  `STREET_GAME` are now read-only static accessors over the loader.
- **The game doesn't validate content at runtime.** The schema and the
  checks run in the tests and in `tools/format_content.gd` (format after a
  hand edit, then check); the editor should run them before it saves.
- **What the checks mean:** townsfolk are obstacles, crews aren't (two
  crews are meant to block the road until beaten); "nobody in the way"
  lifts out one townsperson at a time with everyone else, gate shut and
  open; a card the gate needs must be reachable with the gate shut.

### For phase 2

- **C-SAME pins today's world.** The first edit the owner means to keep
  will fail it, and so will tests that pin today's layout (the Pond
  Hecklers' line of sight at (44, 9)-(44, 14), W-NPCS naming Bertram and
  Juniper, scene tests walking to fixed cells). Decide before the editor
  saves anything which tests are rules (keep them) and which describe
  today's maps (retire them or remake their fixtures with the edit,
  reviewed: `tools/snapshot_world.tscn` remakes the snapshot).
- **Ids are save data.** Map, crew and pickup ids are what a save records
  (where you are, who you beat, which cards you took): the editor should
  not rename them, or must migrate saves.
- **Reloading:** `WorldMap.reload()` (and `Content.reload()`) drop the
  caches; the overworld then has to rebuild the map it's on
  (`_load_map`). The runtime dictionaries are shared: the editor edits the
  files' data (`Content.docs()` / `map_doc`), never the game's copies, and
  saves with `ContentFormat.stringify`.
- **Live checks are about 0.35 s** for the whole world (mostly the
  nobody-in-the-way walk): fine on save, too slow for every brush stroke;
  check the edited map, or after a pause.
- `res://` is read-only in exported builds, which suits the spec (the
  editor runs from source only).

## Open questions

- Getting edits back: a "Save & send" button that commits and pushes the
  owner's edits to their own branch, or the owner using git directly?
- How much of the poker table's text (and Rosie's lessons) becomes editable
  content, and when?
