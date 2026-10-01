extends TestCase
## The placeholder art: every species has its sheet and portrait at the
## documented sizes, the overworld finds every tile and character it asks
## for, the loaders return null (without logging an error) for missing art,
## and every pixel is from the palette.

## What the overworld loads (WorldMap.TILES and its townsfolk, on the
## overworld branch). Missing files fall back to placeholders there, so a
## renamed file would fail silently in the game: this catches it.
const OVERWORLD_TILES := ["grass", "flowers", "tall_grass", "path", "tree", "water", "fence",
	"roof", "wall", "window", "door", "door_shut", "sign", "floor", "inner_wall", "counter",
	"felt", "bed", "plant", "mat"]
const PEOPLE := [&"player", &"npc", &"npc_cook", &"npc_kid", &"npc_dealer"]


func test_every_species_has_art() -> void:
	for id: StringName in Species.ids():
		var sprite := Sprites.species(id)
		if check(sprite != null, "%s has a sprite" % id):
			check_eq(sprite.get_size(), Vector2(16, 16), "%s sprite size" % id)
		var sheet := Sprites.sheet(id)
		if check(sheet != null, "%s has a walk sheet" % id):
			check_eq(sheet.get_size(), Vector2(80, 64), "%s sheet: 5 frames x 4 facings" % id)
		var face := Sprites.portrait(id)
		if check(face != null, "%s has a portrait" % id):
			check_eq(face.get_size(), Vector2(32, 32), "%s portrait size" % id)


func test_people_are_a_head_taller() -> void:
	for id: StringName in PEOPLE:
		var sprite := Sprites.character(id)
		if check(sprite != null, "%s has a sprite" % id):
			check_eq(sprite.get_size(), Vector2(16, 24), "%s sprite size" % id)
		check_eq(Sprites.frame_size(id), Vector2i(16, 24), "%s walk frame" % id)
	check(Sprites.player() != null and Sprites.npc() != null, "shortcuts load")
	check_eq(Sprites.frame_size(&"npc_badger"), Vector2i(16, 16), "the badger is an animal")


## SpriteBank's rules: frames 16 wide, and a sheet four frames tall (each
## 16, 24 or 32) has a row per facing.
func test_sheets_fit_the_overworld() -> void:
	for id: StringName in Species.ids() + PEOPLE + [&"npc_badger"]:
		var sheet := Sprites.sheet(id)
		if not check(sheet != null, "%s has a sheet" % id):
			continue
		check_eq(int(sheet.get_width()), 16 * Sprites.WALK_FRAMES, "%s: 16-wide frames" % id)
		check(int(sheet.get_height()) / 4 in [16, 24, 32] and int(sheet.get_height()) % 4 == 0,
			"%s: four rows of facings" % id)


func test_missing_art_is_null() -> void:
	check(Sprites.species(&"dodo") == null, "no dodo sprite")
	check(Sprites.portrait(&"dodo") == null, "no dodo portrait")
	check(Sprites.tile("lava") == null, "no lava tile")
	check(Sprites.walk_frames(&"dodo") == null, "no dodo animations")
	check(Sprites.walk_frame(&"dodo", Sprites.Facing.UP, 1) == null, "no dodo frame")
	check(Sprites.sheet(&"dodo") == null, "no dodo sheet")
	check_eq(Sprites.frame_size(&"dodo"), Vector2i.ZERO)


func test_tiles_the_overworld_needs() -> void:
	var names := Sprites.tile_names()
	for tile_name: String in OVERWORLD_TILES:
		check(names.has(tile_name), "tile list has %s" % tile_name)
		var tex := Sprites.tile(tile_name)
		if check(tex != null, "%s loads" % tile_name):
			check_eq(tex.get_size(), Vector2(16, 16), "%s is one tile" % tile_name)
	for facade in ["diner", "tournament_hall"]:
		var tex := Sprites.tile(facade)
		if check(tex != null, "%s loads" % facade):
			check(int(tex.get_width()) % 16 == 0 and int(tex.get_height()) % 16 == 0,
				"%s lines up with the tile grid" % facade)


func test_walk_animations() -> void:
	var frames := Sprites.walk_frames(&"goose")
	if not check(frames != null, "goose animations"):
		return
	for dir in ["down", "left", "right", "up"]:
		check_eq(frames.get_frame_count("walk_" + dir), 4, "walk_%s: frames 1-4" % dir)
		check_eq(frames.get_frame_count("idle_" + dir), 1, "idle_%s frames" % dir)
		check(frames.get_animation_loop("walk_" + dir), "walk_%s loops" % dir)
	check_eq(frames.get_frame_count("default"), 1)
	var right_step := Sprites.walk_frame(&"goose", Sprites.Facing.RIGHT, 1)
	check_eq(right_step.region, Rect2(16, 48, 16, 16), "row = facing (down, up, left, right), column = frame")
	var standing: AtlasTexture = frames.get_frame_texture("idle_up", 0)
	check_eq(standing.region, Rect2(0, 16, 16, 16), "idle is frame 0")


## Read straight from the PNGs (not the imported textures) and check every
## pixel is transparent or one of the palette's 32 colours, with the
## palette itself read from assets/palette.gpl.
func test_only_palette_colours() -> void:
	var palette := {}
	for line in FileAccess.get_file_as_string("res://assets/palette.gpl").split("\n"):
		var parts := line.replace("\t", " ").split(" ", false)
		if parts.size() >= 3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int():
			palette[Color8(int(parts[0]), int(parts[1]), int(parts[2])).to_rgba32()] = true
	check_eq(palette.size(), 32, "Endesga 32 has 32 colours")
	var checked := 0
	for folder in ["sprites", "portraits", "tiles"]:
		var dir := "res://assets/%s/" % folder
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".png"):
				continue
			var img := Image.load_from_file(ProjectSettings.globalize_path(dir + file))
			var stray := 0
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.a > 0.0 and (c.a < 1.0 or not palette.has(c.to_rgba32())):
						stray += 1
			check_eq(stray, 0, "%s%s: off-palette pixels" % [folder, file])
			checked += 1
	check(checked >= 30, "checked %d images" % checked)
