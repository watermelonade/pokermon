extends SceneTree
## Regenerates every placeholder PNG under assets/ from the text sources in
## assets/src/, so the art is reproducible and tweakable in any text editor:
##
##   godot --headless --path . -s tools/make_art.gd
##   godot --headless --path . --import          # then refresh Godot's import cache
##
## Dev flag (after `--`): --sheet=/path/sheet.png [--scale=4] [--only=cat]
## also writes a contact sheet of everything (or of the outputs whose path
## contains the --only text), scaled up with nearest-neighbour, so the art can
## be checked without opening the editor.
##
## Why text grids: the owner has little art experience and will redraw the
## art in Aseprite later. Until then, a pixel is one letter in a grid
## (`r` rust, `k` black... see PALETTE), so changing an eye or a colour is a
## one-character edit, a diff shows exactly which pixels moved, and nothing
## needs an image editor. card_art.gd's suits work the same way. A Python
## writer was the alternative, but Godot is already installed everywhere the
## project is, and PIL isn't.
##
## Source format (assets/src/**/*.txt):
##   # comment
##   outline = k            option for every grid below it in the file
##   [name opt=value ...]   starts a grid; options here override the file's
##   ....kk....             one row per line, `.` is transparent
##
## Options:
##   outline=<key>  draw a 1px outline in that colour around the silhouette
##                  (4-neighbour, so corners stay round). Characters and
##                  portraits are drawn as fills and outlined here: one
##                  consistent outline everywhere, and a sprite can be edited
##                  without redrawing its border by hand.
##   feet=<n>       (characters) how many bottom rows the walk frames replace
##   bob=<n>        (characters) push the body down n px in the step frames
##                  (a little squash on each footfall)
##
## What gets made:
##   assets/src/characters/<id>.txt -> sprites/<id>.png (facing down) and
##       sprites/<id>_walk.png: 4 columns (stand, step A, stand, step B) by
##       4 rows (down, left, right, up). The file has grids `down`, `up` and
##       `right` (left is right mirrored), plus optional `step_down`,
##       `step_up`, `step_right` and `step_right_b`: just the bottom `feet`
##       rows of a step. Step B mirrors step A for down/up, and reuses step
##       A sideways unless `step_right_b` exists.
##   assets/src/portraits/<id>.txt  -> portraits/<id>.png (grid `portrait`)
##   assets/src/tiles/*.txt         -> tiles/<grid name>.png, any size
##   PALETTE                        -> palette.gpl (GIMP/Aseprite), palette.png

const SRC := "res://assets/src/"
const OUT := "res://assets/"

## Endesga 32 by ENDESGA (lospec.com/palette-list/endesga-32): warm, saturated
## and with enough browns, greens and skin tones for small-town Americana,
## which suits an EarthBound-ish look better than a muted palette. Each colour
## has one letter for the grids, picked to be guessable (r rust, G green,
## k black); lower/upper case are usually the light/dark pair.
const PALETTE := [
	["r", "be4a2f", "rust"],
	["o", "d77643", "copper"],
	["c", "ead4aa", "cream"],
	["t", "e4a672", "tan"],
	["b", "b86f50", "light brown"],
	["B", "733e39", "brown"],
	["D", "3e2731", "dark brown"],
	["R", "a22633", "dark red"],
	["e", "e43b44", "red"],
	["O", "f77622", "orange"],
	["y", "feae34", "gold"],
	["Y", "fee761", "yellow"],
	["g", "63c74d", "light green"],
	["G", "3e8948", "green"],
	["h", "265c42", "dark green"],
	["H", "193c3e", "deep teal"],
	["u", "124e89", "blue"],
	["U", "0099db", "sky blue"],
	["i", "2ce8f5", "cyan"],
	["w", "ffffff", "white"],
	["l", "c0cbdc", "light grey"],
	["L", "8b9bb4", "grey"],
	["s", "5a6988", "slate"],
	["S", "3a4466", "dark slate"],
	["n", "262b44", "navy"],
	["k", "181425", "black"],
	["x", "ff0044", "hot red"],
	["p", "68386c", "purple"],
	["m", "b55088", "magenta"],
	["P", "f6757a", "pink"],
	["f", "e8b796", "skin"],
	["F", "c28569", "skin shade"],
]
const DIRECTIONS := ["down", "left", "right", "up"]

var _colors := {}  ## palette letter -> Color
var _errors := 0
var _made: Array[Image] = []  ## everything written, for the contact sheet
var _made_paths: Array[String] = []


func _init() -> void:
	for entry: Array in PALETTE:
		_colors[entry[0]] = Color(entry[1])
	for dir in ["sprites", "portraits", "tiles"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + dir))
	_write_palette()
	for file in _sources("characters"):
		_character(file)
	for file in _sources("portraits"):
		var grids := _parse(SRC + "portraits/" + file)
		if grids.has("portrait"):
			_save(_render(grids["portrait"], file), "portraits/" + file.get_basename() + ".png")
		else:
			_error("%s has no [portrait] grid" % file)
	for file in _sources("tiles"):
		var grids := _parse(SRC + "tiles/" + file)
		for name: String in grids:
			_save(_render(grids[name], "%s:%s" % [file, name]), "tiles/" + name + ".png")
	var scale := 4
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scale="):
			scale = int(arg.get_slice("=", 1))
		elif arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sheet="):
			_contact_sheet(arg.get_slice("=", 1), scale, only)
	print("make_art: %d images, %d errors" % [_made.size(), _errors])
	quit(1 if _errors else 0)


func _sources(folder: String) -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(SRC + folder):
		if file.ends_with(".txt"):
			files.append(file)
	files.sort()
	return files


func _error(message: String) -> void:
	_errors += 1
	printerr("make_art: ", message)


## Returns {grid name: {"rows": PackedStringArray, "opts": Dictionary}} in
## file order. See the format in the docstring above.
func _parse(path: String) -> Dictionary:
	var grids := {}
	var defaults := {}
	var current := ""
	var line_no := 0
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		line_no += 1
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("["):
			var words := line.trim_prefix("[").trim_suffix("]").split(" ", false)
			current = words[0]
			var opts := defaults.duplicate()
			for i in range(1, words.size()):
				opts[words[i].get_slice("=", 0)] = words[i].get_slice("=", 1)
			grids[current] = {"rows": PackedStringArray(), "opts": opts}
		elif "=" in line:
			defaults[line.get_slice("=", 0).strip_edges()] = line.get_slice("=", 1).strip_edges()
		elif current == "":
			_error("%s:%d: pixels before any [grid]" % [path, line_no])
		else:
			grids[current]["rows"].append(line)
	return grids


## A grid of palette letters -> an RGBA image, outlined if the grid asks.
func _render(grid: Dictionary, where: String) -> Image:
	var img := _pixels(grid["rows"], where)
	var outline: String = grid["opts"].get("outline", "")
	if outline != "":
		img = _outlined(img, _colors.get(outline, Color.MAGENTA))
	return img


func _pixels(rows: PackedStringArray, where: String) -> Image:
	if rows.is_empty():
		_error("%s is empty" % where)
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var w := rows[0].length()
	var img := Image.create_empty(w, rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row := rows[y]
		if row.length() != w:
			_error("%s row %d is %d wide, expected %d" % [where, y, row.length(), w])
		for x in mini(w, row.length()):
			var key := row[x]
			if key == ".":
				continue
			if not _colors.has(key):
				_error("%s row %d: '%s' isn't a palette letter" % [where, y, key])
				continue
			img.set_pixel(x, y, _colors[key])
	return img


## Every transparent pixel touching an opaque one (up, down, left, right)
## becomes the outline colour.
func _outlined(img: Image, color: Color) -> Image:
	var out := img.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var p := Vector2i(x, y) + d
				if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and img.get_pixelv(p).a > 0.0:
					out.set_pixel(x, y, color)
					break
	return out


func _character(file: String) -> void:
	var id := file.get_basename()
	var grids := _parse(SRC + "characters/" + file)
	for needed in ["down", "up", "right"]:
		if not grids.has(needed):
			_error("%s has no [%s] grid" % [file, needed])
			return
	var w: int = grids["down"]["rows"][0].length()
	var h: int = grids["down"]["rows"].size()
	# Check every grid's width up front: the walk frames splice rows
	# together, and a short row would index past its end.
	for name: String in grids:
		var rows: PackedStringArray = grids[name]["rows"]
		var tall := h if not name.begins_with("step_") else rows.size()
		var bad := rows.size() != tall
		for row in rows:
			bad = bad or row.length() != w
		if bad:
			_error("%s: [%s] must be %dx%d like [down]; skipping %s" % [file, name, w, tall, id])
			return
	var sheet := Image.create_empty(w * 4, h * 4, false, Image.FORMAT_RGBA8)
	for row in 4:
		for col in 4:
			var frame := _walk_frame(grids, DIRECTIONS[row], col, "%s:%s" % [file, DIRECTIONS[row]])
			if frame.get_size() != Vector2i(w, h):
				_error("%s: every grid must be %dx%d like [down]" % [file, w, h])
				return
			sheet.blit_rect(frame, Rect2i(0, 0, w, h), Vector2i(col * w, row * h))
	_save(_walk_frame(grids, "down", 0, file + ":down"), "sprites/%s.png" % id)
	_save(sheet, "sprites/%s_walk.png" % id)


## One walk frame: phase 0 and 2 stand, 1 and 3 step (see the docstring).
func _walk_frame(grids: Dictionary, dir: String, phase: int, where: String) -> Image:
	var source := "right" if dir == "left" else dir
	var grid: Dictionary = grids[source]
	var rows: PackedStringArray = grid["rows"]
	if phase % 2 == 1:
		rows = _step_rows(grids, source, phase, where)
	var img := _render({"rows": rows, "opts": grid["opts"]}, where)
	if dir == "left":
		img.flip_x()
	return img


func _step_rows(grids: Dictionary, source: String, phase: int, where: String) -> PackedStringArray:
	var stand: PackedStringArray = grids[source]["rows"]
	var opts: Dictionary = grids[source]["opts"]
	var feet := int(opts.get("feet", "2"))
	var bob := int(opts.get("bob", "0"))
	var h := stand.size()
	var w := stand[0].length()
	var step := PackedStringArray()
	var name := "step_" + source
	if phase == 3 and grids.has(name + "_b"):
		step = grids[name + "_b"]["rows"]
	elif grids.has(name):
		step = grids[name]["rows"]
		if phase == 3 and source != "right":
			var mirrored := PackedStringArray()
			for row in step:
				mirrored.append(row.reverse())
			step = mirrored
	else:
		step = stand.slice(h - feet)
	if step.size() != feet:
		_error("%s: [%s] must have feet=%d rows" % [where, name, feet])
		return stand
	# Feet first, then the body (shifted down by `bob`) drawn over them.
	var out := PackedStringArray()
	for y in h:
		out.append(step[y - (h - feet)] if y >= h - feet else ".".repeat(w))
	for y in range(h - feet - 1, -1, -1):
		var to := y + bob
		if to >= h:
			continue
		var merged := out[to]
		for x in w:
			if stand[y][x] != ".":
				merged[x] = stand[y][x]
		out[to] = merged
	return out


func _save(img: Image, path: String) -> void:
	var err := img.save_png(OUT + path)
	if err != OK:
		_error("couldn't write %s (%s)" % [path, error_string(err)])
	_made.append(img)
	_made_paths.append(path)


func _write_palette() -> void:
	var gpl := "GIMP Palette\nName: Endesga 32\nColumns: 8\n#\n"
	var swatch := Image.create_empty(8 * 16, 4 * 16, false, Image.FORMAT_RGBA8)
	for i in PALETTE.size():
		var entry: Array = PALETTE[i]
		var c := Color(entry[1])
		gpl += "%3d %3d %3d\t%s (%s)\n" % [c.r8, c.g8, c.b8, entry[2], entry[0]]
		swatch.fill_rect(Rect2i((i % 8) * 16, (i / 8) * 16, 16, 16), c)
	var file := FileAccess.open(OUT + "palette.gpl", FileAccess.WRITE)
	file.store_string(gpl)
	file.close()
	_save(swatch, "palette.png")


## Everything made, left to right in rows, on a two-tone green checker (so
## transparent pixels show), scaled up for looking at.
func _contact_sheet(path: String, scale: int, only: String) -> void:
	var images: Array[Image] = []
	for i in _made.size():
		if only == "" or _made_paths[i].contains(only):
			images.append(_made[i])
	var width := 4
	for img in images:
		width += img.get_width() + 3
	width = clampi(width, 64, 320)
	var x := 2
	var y := 2
	var row_h := 0
	var spots: Array[Vector2i] = []
	for img in images:
		if x + img.get_width() > width - 2 and x > 2:
			x = 2
			y += row_h + 3
			row_h = 0
		spots.append(Vector2i(x, y))
		x += img.get_width() + 3
		row_h = maxi(row_h, img.get_height())
	var sheet := Image.create_empty(width, y + row_h + 2, false, Image.FORMAT_RGBA8)
	for cy in sheet.get_height():
		for cx in width:
			sheet.set_pixel(cx, cy, _colors["G"] if (cx / 8 + cy / 8) % 2 == 0 else _colors["g"].darkened(0.15))
	for i in images.size():
		var img := images[i]
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), spots[i])
	sheet.resize(sheet.get_width() * scale, sheet.get_height() * scale, Image.INTERPOLATE_NEAREST)
	sheet.save_png(path)
	print("contact sheet: ", path)
