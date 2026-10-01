extends Node2D
## Dev preview of the placeholder art in assets/, loaded through Sprites the
## way game code will load it. Four pages (left/right or A to flip):
##
## - crew: every character at 2x, standing and walking in all four
##   directions, then the six portraits at 2x.
## - tiles: every 16x16 tile at 2x.
## - buildings: the diner and tournament hall facades at 2x, and the palette.
## - town: a small town laid out from the tiles at 1x, the game's real
##   scale (the Deck shows it at 2x), with a few characters walking about.
##   This is the page to judge the art on: things that read at 2x can
##   turn to mush at 1x.
##
##   godot --path . res://scenes/dev/art_preview.tscn
##
## Dev flags (after `--`): --page=crew|tiles|buildings|town picks the first page,
## --screenshot=path.png saves the screen (scaled x2 like the Deck) after
## --shot-after=seconds and quits.

const PAGES := ["crew", "tiles", "buildings", "town"]
const VIEW := Vector2(640, 400)
const CHARACTERS: Array[StringName] = [&"player", &"npc", &"npc_cook", &"owl", &"raccoon",
	&"goose", &"cat", &"squirrel", &"possum", &"npc_kid", &"npc_dealer", &"npc_badger"]
const INK := Color("181425")
const CREAM := Color("ead4aa")

var _page := 0
var _root: Node2D


func _ready() -> void:
	var shot_path := ""
	var shot_after := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--page="):
			_page = maxi(0, PAGES.find(arg.get_slice("=", 1)))
		elif arg.begins_with("--screenshot="):
			shot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-after="):
			shot_after = float(arg.get_slice("=", 1))
	_show(_page)
	if shot_path:
		_take_screenshot(shot_path, shot_after)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		_show(_page + 1)
	elif event.is_action_pressed("ui_left"):
		_show(_page - 1)


func _show(page: int) -> void:
	_page = wrapi(page, 0, PAGES.size())
	if _root:
		_root.queue_free()
	_root = Node2D.new()
	add_child(_root)
	match PAGES[_page]:
		"crew":
			_crew_page()
		"tiles":
			_tiles_page()
		"buildings":
			_buildings_page()
		"town":
			_town_page()
	_label("%s  (%d/%d, left/right to flip)" % [PAGES[_page], _page + 1, PAGES.size()],
		Vector2(VIEW.x - 150, VIEW.y - 14), _root)


# --- pages ----------------------------------------------------------------

func _crew_page() -> void:
	_grass(2)
	var zoom := _zoomed(2)
	for i in CHARACTERS.size():
		var id := CHARACTERS[i]
		var origin := Vector2(8 + (i % 3) * 213, 4 + (i / 3) * 64)
		var title := String(id)
		if Species.CATALOG.has(id):
			var info := Species.get_info(id)
			title = "%s (%s)" % [info["display"], PlayStyle.Kind.keys()[info["style"]].capitalize()]
		_label(title, origin, _root)
		var y := origin.y + 12 + (48 - Sprites.frame_size(id).y * 2)
		_sprite(Sprites.character(id), Vector2(origin.x, y) / 2, zoom)
		for facing in 4:
			var walker := AnimatedSprite2D.new()
			walker.sprite_frames = Sprites.walk_frames(id)
			walker.centered = false
			walker.position = Vector2(origin.x + 40 + facing * 36, y) / 2
			walker.play("walk_" + Sprites.FACING_NAMES[facing])
			zoom.add_child(walker)
	for i in Species.ids().size():
		var id: StringName = Species.ids()[i]
		var pos := Vector2(8 + i * 104, 262)
		_label(Species.get_info(id)["display"], pos, _root)
		_sprite(Sprites.portrait(id), (pos + Vector2(0, 12)) / 2, zoom)


func _tiles_page() -> void:
	_grass(2)
	var zoom := _zoomed(2)
	var i := 0
	for tile_name in Sprites.tile_names():
		if tile_name in ["diner", "tournament_hall"]:
			continue
		var pos := Vector2(8 + (i % 6) * 106, 4 + (i / 6) * 50)
		_label(tile_name, pos, _root)
		_frame(Rect2((pos + Vector2(-2, 10)) / 2, Vector2(18, 18)), zoom)
		_sprite(Sprites.tile(tile_name), (pos + Vector2(0, 12)) / 2, zoom)
		i += 1


## The whole-building facades at 2x, and the palette.
func _buildings_page() -> void:
	_grass(2)
	var zoom := _zoomed(2)
	_label("diner (64x48)", Vector2(8, 6), _root)
	_sprite(Sprites.tile("diner"), Vector2(8, 18) / 2, zoom)
	_label("tournament_hall (80x64)", Vector2(160, 6), _root)
	_sprite(Sprites.tile("tournament_hall"), Vector2(160, 18) / 2, zoom)
	_label("palette: Endesga 32", Vector2(340, 6), _root)
	var swatch := Sprite2D.new()
	swatch.texture = load("res://assets/palette.png")
	swatch.centered = false
	swatch.position = Vector2(340, 18)
	_root.add_child(swatch)


## A 40x25-tile town at 1x, laid out the GBA way: buildings face the
## viewer with their doors on a path, a road across the middle, a ledge,
## tall grass and a pond below it, trees around the edge.
func _town_page() -> void:
	var cols := 40
	var rows := 25
	var ground := {}
	for y in rows:
		for x in cols:
			ground[Vector2i(x, y)] = "flowers" if (x * 7 + y * 13) % 23 == 0 else "grass"
	for x in cols:
		ground[Vector2i(x, 12)] = "path"
		ground[Vector2i(x, 13)] = "path"
	for y in range(5, 12):
		for x in [3, 20, 30, 35]:
			ground[Vector2i(x, y)] = "path"
	for x in range(1, 21):
		ground[Vector2i(x, 16)] = "ledge"
	for y in range(18, 23):
		for x in range(11, 19):
			ground[Vector2i(x, y)] = "tall_grass"
	for y in range(17, 23):
		for x in range(27, 37):
			ground[Vector2i(x, y)] = "water_edge" if y == 17 else "water"
	for cell: Vector2i in ground:
		_sprite(Sprites.tile(ground[cell]), Vector2(cell * 16), _root)
	# Houses: roof, eave, then a wall with windows and a door.
	for house: Array in [[Vector2i(1, 2), 4, 3, ""], [Vector2i(28, 2), 4, 30, "_blue"],
			[Vector2i(34, 2), 3, 35, "_green"]]:
		var corner: Vector2i = house[0]
		var width: int = house[1]
		for x in width:
			var at := corner + Vector2i(x, 0)
			_sprite(Sprites.tile("roof" + house[3]), Vector2(at) * 16, _root)
			_sprite(Sprites.tile("roof_edge" + house[3]), Vector2(at + Vector2i(0, 1)) * 16, _root)
			var piece := "door" if at.x == house[2] else "window"
			_sprite(Sprites.tile(piece), Vector2(at + Vector2i(0, 2)) * 16, _root)
	_sprite(Sprites.tile("tournament_hall"), Vector2(18, 1) * 16, _root)
	_sprite(Sprites.tile("diner"), Vector2(8, 9) * 16, _root)
	for x in [1, 2, 4, 5, 6, 7, 26, 27, 28, 29, 31, 32, 33, 34, 36, 37, 38]:
		_sprite(Sprites.tile("fence"), Vector2(x, 6) * 16, _root)
	for cell: Vector2i in [Vector2i(21, 6), Vector2i(4, 9), Vector2i(26, 15)]:
		_sprite(Sprites.tile("sign"), Vector2(cell * 16), _root)
	for cell: Vector2i in [Vector2i(13, 8), Vector2i(15, 3), Vector2i(24, 15), Vector2i(38, 15),
			Vector2i(12, 4), Vector2i(23, 8)]:
		_sprite(Sprites.tile("bush"), Vector2(cell * 16), _root)
	for x in cols:
		for y in [0, rows - 1]:
			_sprite(Sprites.tile("tree"), Vector2(x, y) * 16, _root)
	for y in range(1, rows - 1):
		for x in [0, cols - 1]:
			_sprite(Sprites.tile("tree"), Vector2(x, y) * 16, _root)
	for cell: Vector2i in [Vector2i(16, 7), Vector2i(21, 20), Vector2i(22, 21), Vector2i(3, 20),
			Vector2i(4, 21), Vector2i(25, 9), Vector2i(37, 9), Vector2i(8, 19)]:
		_sprite(Sprites.tile("tree"), Vector2(cell * 16), _root)
	# Who's about: some walk the road and paths, the rest stand around.
	_walker(&"player", Vector2(40, 196), Vector2(300, 196), 5.0)
	_walker(&"goose", Vector2(440, 252), Vector2(560, 252), 3.0)
	_walker(&"npc", Vector2(320, 88), Vector2(320, 176), 4.0)
	_walker(&"squirrel", Vector2(600, 204), Vector2(460, 204), 3.5)
	_stand(&"owl", Vector2(352, 84), Sprites.Facing.DOWN)
	_stand(&"cat", Vector2(196, 176), Sprites.Facing.DOWN)
	_stand(&"raccoon", Vector2(110, 290), Sprites.Facing.RIGHT)
	_stand(&"possum", Vector2(240, 296), Sprites.Facing.LEFT)
	_stand(&"npc_kid", Vector2(160, 200), Sprites.Facing.UP)
	_stand(&"npc_badger", Vector2(470, 150), Sprites.Facing.DOWN)
	_walker(&"npc_cook", Vector2(130, 184), Vector2(130, 120), 3.0)


# --- helpers --------------------------------------------------------------

## The page background: grass tiles at `scale`.
func _grass(scale: int) -> void:
	var grass := TextureRect.new()
	grass.texture = Sprites.tile("grass")
	grass.stretch_mode = TextureRect.STRETCH_TILE
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grass.size = VIEW / scale
	grass.scale = Vector2(scale, scale)
	_root.add_child(grass)


## A dark 1px frame, so tiles that match the background still show.
func _frame(rect: Rect2, parent: Node) -> void:
	var frame := ColorRect.new()
	frame.color = INK
	frame.position = rect.position
	frame.size = rect.size
	parent.add_child(frame)


func _zoomed(scale: int) -> Node2D:
	var zoom := Node2D.new()
	zoom.scale = Vector2(scale, scale)
	_root.add_child(zoom)
	return zoom


func _sprite(texture: Texture2D, pos: Vector2, parent: Node) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = pos
	parent.add_child(sprite)
	return sprite


func _label(text: String, pos: Vector2, parent: Node) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	var settings := LabelSettings.new()
	settings.font_size = 8
	settings.font_color = CREAM
	settings.outline_size = 3
	settings.outline_color = INK
	label.label_settings = settings
	parent.add_child(label)


func _stand(id: StringName, pos: Vector2, facing: int) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Sprites.walk_frames(id)
	sprite.centered = false
	sprite.position = pos
	sprite.play("idle_" + Sprites.FACING_NAMES[facing])
	_root.add_child(sprite)


## Walks back and forth between two points, facing the way it's going.
func _walker(id: StringName, from: Vector2, to: Vector2, seconds: float) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Sprites.walk_frames(id)
	sprite.centered = false
	sprite.position = from
	_root.add_child(sprite)
	var there := _facing_name(to - from)
	var back := _facing_name(from - to)
	var tween := sprite.create_tween().set_loops()
	tween.tween_callback(sprite.play.bind("walk_" + there))
	tween.tween_property(sprite, "position", to, seconds)
	tween.tween_callback(sprite.play.bind("walk_" + back))
	tween.tween_property(sprite, "position", from, seconds)


func _facing_name(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "right" if direction.x > 0 else "left"
	return "down" if direction.y > 0 else "up"


func _take_screenshot(path: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() < 1280:
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("screenshot saved: ", path)
	get_tree().quit()
