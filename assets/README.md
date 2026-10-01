# Art

Placeholder pixel art, in the look of the Game Boy Advance top-down RPGs
(bright, clean colours, soft shading, a dark outline on characters and
objects). All original designs. Every PNG here is **generated** from the
text grids in `assets/src/` by `tools/make_art.gd`, so it can be changed in
a text editor and regenerated. It's meant to be redrawn in Aseprite; see
"Replacing it with Aseprite art" below.

```
godot --headless --path . -s tools/make_art.gd     # rewrites every PNG below
godot --headless --path . --import                 # then refresh Godot's import cache
godot --path . res://scenes/dev/art_preview.tscn   # look at it all (left/right flips pages)
```

Game code loads the art by name through `Sprites` (`src/ui/sprites.gd`):
`Sprites.species(&"owl")`, `Sprites.portrait(&"owl")`, `Sprites.tile("grass")`,
`Sprites.walk_frames(&"player")` for an AnimatedSprite2D. The overworld
(`SpriteBank`) and the table (`AnimalArt`) load the same paths directly. Every
loader returns null for a missing file, and each caller draws a code
placeholder instead. `tests/test_sprites.gd` checks the files are all there at
the right sizes, and that every pixel is from the palette.

## Palette

[Endesga 32](https://lospec.com/palette-list/endesga-32) by ENDESGA:
`palette.gpl` (GIMP palette, which Aseprite loads) and `palette.png` (a
swatch). It's bright and saturated with soft ramps, which suits the GBA look,
and it has enough greens, browns and skin tones for a small town. Use only
these 32 colours; the test fails on anything else. In the grids each colour
is one letter:

| Letter | Colour | | Letter | Colour | | Letter | Colour | | Letter | Colour |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `r` | be4a2f rust | | `e` | e43b44 red | | `u` | 124e89 blue | | `n` | 262b44 navy |
| `o` | d77643 copper | | `O` | f77622 orange | | `U` | 0099db sky blue | | `k` | 181425 black (outlines) |
| `c` | ead4aa cream | | `y` | feae34 gold | | `i` | 2ce8f5 cyan | | `x` | ff0044 hot red |
| `t` | e4a672 tan | | `Y` | fee761 yellow | | `w` | ffffff white | | `p` | 68386c purple |
| `b` | b86f50 light brown | | `g` | 63c74d light green | | `l` | c0cbdc light grey | | `m` | b55088 magenta |
| `B` | 733e39 brown | | `G` | 3e8948 green | | `L` | 8b9bb4 grey | | `P` | f6757a pink |
| `D` | 3e2731 dark brown | | `h` | 265c42 dark green | | `s` | 5a6988 slate | | `f` | e8b796 skin |
| `R` | a22633 dark red | | `H` | 193c3e deep teal | | `S` | 3a4466 dark slate | | `F` | c28569 skin shade |

`.` is transparent. Light comes from the top left.

## Files

### Characters: `sprites/<id>.png`

Each is a **walk sheet**: 5 frames across, 4 rows down.

```
          col 0   col 1    col 2   col 3    col 4
row 0     stand   step A   stand   step B   stand     facing down
row 1     ...                                         facing up
row 2     ...                                         facing left
row 3     ...                                         facing right
```

Frame 0 is the standing pose; frames 1-4 loop as the walk (step, stand,
step, stand). The overworld plays `1 + phase % 4`, so the sheet ends on a
stand: with four columns it would skip a stand every other step. People
squash 1px on each step.

| id | Frame | Sheet | Who |
| --- | --- | --- | --- |
| `owl` | 16x16 | 80x64 | Rock. Big eyes under stern brows |
| `raccoon` | 16x16 | 80x64 | Bluffer. Bandit mask, a smirk, ringed tail |
| `goose` | 16x16 | 80x64 | Maniac. Mid-honk, one wing up, a feather astray |
| `cat` | 16x16 | 80x64 | Shark. Tuxedo cat in a red bow tie, smug side-eye, tail always showing (its tell) |
| `squirrel` | 16x16 | 80x64 | Calling Station. Clutching a poker chip like an acorn |
| `possum` | 16x16 | 80x64 | Rock. Beady eyes, pink nose and bald pink tail |
| `player` | 16x24 | 80x96 | A kid in a red cap with a yellow backpack |
| `npc` | 16x24 | 80x96 | A generic rival handler: pompadour, shades, rust jacket with a spade on the back |
| `npc_cook` | 16x24 | 80x96 | Rosie, the diner's cook |
| `npc_kid` | 16x24 | 80x96 | Juniper, age 9 (drawn a head shorter inside the same frame) |
| `npc_dealer` | 16x24 | 80x96 | Lou, the dealer: green eyeshade, moustache, bow tie |
| `npc_badger` | 16x16 | 80x64 | Old Bertram, a badger in a flat cap |

Characters stand on the bottom row of their frame (feet at row 14 of 16, or
22 of 24, with the outline below).

### Portraits: `portraits/<id>.png`

32x32 head-and-shoulders for each species (`owl raccoon goose cat squirrel
possum`), on transparency, cut off flat at the bottom. Used by the Binder and
the seat badges at the table.

### Tiles: `tiles/<name>.png`

All 16x16 and opaque unless noted. Objects (tree, fence, sign, bush, bed,
plant) are drawn on transparency in the source and saved composited onto
grass or floor (`under=` in the grid), because the overworld draws one
texture per cell with nothing beneath it.

| Name | What | Tiles seamlessly |
| --- | --- | --- |
| `grass`, `flowers`, `tall_grass` | bright grass with tufts; with 4-petal flowers; tall grass clumps | yes |
| `path` | sandy path | yes |
| `water`, `water_edge` | water; a shore with grass along the top | yes / across |
| `ledge` | grass with a one-way drop along the bottom | across |
| `tree`, `bush`, `fence`, `sign` | on grass | fence across |
| `roof`, `roof_blue`, `roof_green` | shingles; stack as many rows as the roof is tall | yes |
| `roof_edge`, `roof_edge_blue`, `roof_edge_green` | optional last roof row, with the eave's shadow | across |
| `wall`, `window`, `door`, `door_shut` | siding; with a window; an open doorway (walkable); a closed door | across |
| `floor`, `inner_wall`, `counter`, `mat` | interiors: wood floor, papered wall with wainscot, diner counter, doormat | yes |
| `bed`, `plant` | on the floor | |
| `felt`, `table_rim`, `diner_floor` | poker-table felt and its wooden rim, a checkerboard floor | yes |
| `diner` | **64x48** facade: a red and white barrel roof with a DINER sign | (transparent corners) |
| `tournament_hall` | **80x64** facade: a blue hip roof with a gold spade, a POKER marquee, pillars | (transparent corners) |

A house is roof rows, then a wall row: for example a 4-wide house is
`roof x4`, `roof x4`, `roof_edge x4`, then `window door window window`.
The two facades are optional whole buildings for maps that want a landmark
instead of building them from tiles; place them at a tile corner over the
ground.

## How the sources work

`assets/src/characters/<id>.txt`, `assets/src/portraits/<id>.txt` and
`assets/src/tiles/*.txt` hold the grids. A grid is a `[name]` line and then
one row of letters per pixel row. `key = value` lines set options for the
grids below them, and `[name key=value]` sets them for one grid:

- `outline=k`: draw a 1px outline in that colour around the silhouette.
  Characters, portraits and objects are drawn as fills and outlined by the
  generator, so the outline is the same everywhere and a sprite can be
  edited without redrawing its border.
- `feet=N`, `bob=N` (characters): the walk frames replace the bottom N rows
  with the `[step_down]`, `[step_up]`, `[step_right]` (and optional
  `[step_right_b]`) rows, and push the body down `bob` px. Left is right
  mirrored; down/up step B mirrors step A.
- `under=<tile>` (tiles): composite onto a tile made earlier.

A character file needs `[down]`, `[up]` and `[right]`. Grids are checked:
a row of the wrong width or a letter that isn't in the palette stops that
image with an error naming the file and row. To look at the result
quickly without opening Godot:

```
godot --headless --path . -s tools/make_art.gd -- --sheet=/tmp/sheet.png --scale=6 --only=owl
```

The portraits and the tiles were roughed out from simple shapes (circles,
polygons) and then kept as grids. The grids are the source now: edit them
directly.

## Replacing it with Aseprite art

1. In Aseprite, load `assets/palette.gpl` (Palette menu > Load Palette), so
   new art stays in the same 32 colours. To start from a placeholder, open
   its PNG: Aseprite reads it as a sprite you can paint over.
2. Draw at the same size. For a character, either export a sheet with
   File > Export Sprite Sheet (By Rows, 5 frames per row, rows in the order
   down, up, left, right, no padding) or lay the frames out on one canvas.
3. Save the PNG over the generated one (same name), **and delete its grid**
   from `assets/src/` (the `.txt` file for a character or portrait, the
   `[name]` block for a tile). Otherwise the next `make_art.gd` run
   overwrites your drawing.
4. Run `godot --headless --path . --import` (or just open the editor) and
   `godot --headless --path . -s tests/run_tests.gd -- sprites`, which checks
   sizes and that every pixel is in the palette.

Later, the [Aseprite Wizard](https://github.com/viniciusgerevini/godot-aseprite-wizard)
plugin can import `.aseprite` files straight into SpriteFrames (with tags
for the walk animations), so the PNG export step goes away. If you switch to
it, keep the tag names `walk_down`, `idle_down`... that `Sprites.walk_frames`
uses, and change that one function to load the imported SpriteFrames.
Nothing else needs to change.
