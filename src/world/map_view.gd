class_name MapView
extends Node2D
## Paints a WorldMap's tiles: the art from assets/tiles/ where it exists,
## a placeholder drawn from rectangles where it doesn't (so half-finished
## tile sets work too). Building names are written on their roofs until real
## signage exists.
##
## One _draw() for the whole map rather than a TileMapLayer: the map is
## text (WorldMap), there's no tileset resource to keep in sync with it, and
## Godot caches the draw commands, so the 2,500 tiles of Ridge Road are
## painted once per map change, not per frame. Revisit if maps get big
## enough to need culling.

const GRASS := Color("5f9a48")
const GRASS_DARK := Color("4f8a3c")
const PATH := Color("c9a86a")
const PATH_DARK := Color("b8965a")
const TREE := Color("2f6a3a")
const TREE_DARK := Color("214f2b")
const TRUNK := Color("6b4a2c")
const WATER := Color("3b6fa8")
const ROOF := Color("a8483a")
const WALL := Color("e0cfa8")
const WOOD := Color("8a5a34")
const FLOOR := Color("b48a5a")
const INNER := Color("4a3424")
const FELT := Color("2b5b3a")
const TEXT := Color("f4ecd8")

var map: WorldMap


func show_map(m: WorldMap) -> void:
	map = m
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var at := Vector2(cell * WorldMap.TILE)
			var tex := SpriteBank.tile(map.tile_name(cell))
			if tex:
				draw_texture(tex, at)
			else:
				_paint(map.char_at(cell), cell, at)
	var font := ThemeDB.fallback_font
	for label: Dictionary in map.labels:
		var r: Rect2i = label["rect"]
		var text: String = label["text"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var center := Vector2(r.position * WorldMap.TILE) + Vector2(r.size * WorldMap.TILE) / 2
		var box := Rect2(center - Vector2(w / 2 + 3, 6), Vector2(w + 6, 11))
		draw_rect(box, Color("2a1e18"))
		draw_string(font, Vector2(box.position.x + 3, box.position.y + 9).floor(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, TEXT)


## Per-cell variation that's the same every time the map is drawn.
func _speck(cell: Vector2i, salt: int) -> int:
	return hash(cell.x * 7919 + cell.y * 104729 + salt) % 16


func _paint(ch: String, cell: Vector2i, at: Vector2) -> void:
	var t := float(WorldMap.TILE)
	match ch:
		".", ",", ";":
			draw_rect(Rect2(at, Vector2(t, t)), GRASS)
			for k in 2:
				var s := _speck(cell, k)
				draw_rect(Rect2(at + Vector2(s, (s * 5 + k * 7) % 15), Vector2(1, 2)), GRASS_DARK)
			if ch == ",":
				var colors := [Color("e8c35a"), Color("e86a8a"), Color("f4ecd8")]
				for k in 3:
					var s := _speck(cell, 10 + k)
					draw_rect(Rect2(at + Vector2(2 + (s * 3) % 12, 2 + (s * 7 + k * 5) % 12), Vector2(2, 2)), colors[(s + k) % 3])
			elif ch == ";":
				for k in 4:
					var x := 1.0 + k * 4
					draw_rect(Rect2(at + Vector2(x, 6), Vector2(1, 9)), GRASS_DARK.darkened(0.2))
					draw_rect(Rect2(at + Vector2(x + 2, 3), Vector2(1, 11)), GRASS_DARK)
		"=":
			draw_rect(Rect2(at, Vector2(t, t)), PATH)
			var s := _speck(cell, 3)
			draw_rect(Rect2(at + Vector2(s % 14, (s * 3) % 14), Vector2(2, 1)), PATH_DARK)
		"T":
			draw_rect(Rect2(at, Vector2(t, t)), GRASS_DARK)
			draw_rect(Rect2(at + Vector2(7, 11), Vector2(2, 5)), TRUNK)
			draw_circle(at + Vector2(8, 7), 7, TREE_DARK)
			draw_circle(at + Vector2(7, 6), 5, TREE)
		"~":
			draw_rect(Rect2(at, Vector2(t, t)), WATER)
			draw_rect(Rect2(at + Vector2(3 + _speck(cell, 4) % 6, 5), Vector2(4, 1)), WATER.lightened(0.3))
			draw_rect(Rect2(at + Vector2(1 + _speck(cell, 5) % 8, 11), Vector2(4, 1)), WATER.lightened(0.2))
		"F":
			draw_rect(Rect2(at, Vector2(t, t)), GRASS)
			draw_rect(Rect2(at + Vector2(0, 5), Vector2(t, 2)), WOOD)
			draw_rect(Rect2(at + Vector2(0, 10), Vector2(t, 2)), WOOD)
			draw_rect(Rect2(at + Vector2(2, 3), Vector2(2, 11)), WOOD.darkened(0.2))
			draw_rect(Rect2(at + Vector2(11, 3), Vector2(2, 11)), WOOD.darkened(0.2))
		"R":
			draw_rect(Rect2(at, Vector2(t, t)), ROOF)
			draw_rect(Rect2(at + Vector2(0, 7), Vector2(t, 1)), ROOF.darkened(0.25))
			draw_rect(Rect2(at + Vector2(0, 15), Vector2(t, 1)), ROOF.darkened(0.25))
		"#", "w", "d":
			draw_rect(Rect2(at, Vector2(t, t)), WALL)
			draw_rect(Rect2(at, Vector2(t, 2)), WALL.darkened(0.3))
			if ch == "w":
				draw_rect(Rect2(at + Vector2(3, 4), Vector2(10, 8)), Color("3b5f80"))
				draw_rect(Rect2(at + Vector2(7.5, 4), Vector2(1, 8)), WALL)
			elif ch == "d":
				draw_rect(Rect2(at + Vector2(3, 3), Vector2(10, 13)), WOOD.darkened(0.3))
				draw_rect(Rect2(at + Vector2(4, 8), Vector2(8, 1)), Color("1d1a24"))
		"D":
			draw_rect(Rect2(at, Vector2(t, t)), WALL)
			draw_rect(Rect2(at + Vector2(3, 3), Vector2(10, 13)), WOOD)
			draw_rect(Rect2(at + Vector2(10, 9), Vector2(1, 2)), Color("e8c35a"))
		"S":
			draw_rect(Rect2(at, Vector2(t, t)), GRASS)
			draw_rect(Rect2(at + Vector2(7, 9), Vector2(2, 7)), TRUNK)
			draw_rect(Rect2(at + Vector2(2, 2), Vector2(12, 8)), WOOD)
			draw_rect(Rect2(at + Vector2(4, 4), Vector2(8, 1)), WALL)
			draw_rect(Rect2(at + Vector2(4, 6), Vector2(6, 1)), WALL)
		"_", "X":
			draw_rect(Rect2(at, Vector2(t, t)), FLOOR)
			draw_rect(Rect2(at + Vector2(0, (cell.x % 2) * 8), Vector2(t, 1)), FLOOR.darkened(0.15))
			if ch == "X":
				draw_rect(Rect2(at + Vector2(1, 3), Vector2(14, 10)), Color("7a3b2e"))
				draw_rect(Rect2(at + Vector2(3, 5), Vector2(10, 6)), Color("a8483a"))
		"W":
			draw_rect(Rect2(at, Vector2(t, t)), INNER)
			draw_rect(Rect2(at + Vector2(0, 13), Vector2(t, 3)), INNER.darkened(0.3))
		"C":
			draw_rect(Rect2(at, Vector2(t, t)), FLOOR)
			draw_rect(Rect2(at + Vector2(0, 2), Vector2(t, 12)), WOOD)
			draw_rect(Rect2(at + Vector2(0, 2), Vector2(t, 3)), WOOD.lightened(0.25))
		"t":
			draw_rect(Rect2(at, Vector2(t, t)), FELT)
			draw_rect(Rect2(at + Vector2(0, 14), Vector2(t, 2)), Color("4a3424"))
		"b":
			draw_rect(Rect2(at, Vector2(t, t)), FLOOR)
			draw_rect(Rect2(at + Vector2(1, 1), Vector2(14, 15)), Color("3b5f80"))
			draw_rect(Rect2(at + Vector2(1, 1), Vector2(14, 4)), TEXT)
		"p":
			draw_rect(Rect2(at, Vector2(t, t)), FLOOR)
			draw_rect(Rect2(at + Vector2(4, 10), Vector2(8, 6)), Color("a8483a"))
			draw_circle(at + Vector2(8, 7), 5, TREE)
		_:
			draw_rect(Rect2(at, Vector2(t, t)), Color.MAGENTA)
