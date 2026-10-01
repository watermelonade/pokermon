class_name SpriteBank
extends RefCounted
## Finds art if it exists, so the overworld switches from placeholders to
## real sprites the moment they're dropped in, with no code change:
##
##   res://assets/sprites/<id>.png   characters: "player", a species id
##                                   ("owl", "goose", ...) or a townsperson
##                                   ("npc_cook", "npc_badger", "npc_kid",
##                                   "npc_dealer"). 16x16 or 16x24, drawn
##                                   standing on the bottom of their tile.
##                                   A sheet works too: columns of 16-wide
##                                   frames (the first standing, the rest a
##                                   walk cycle) and, if it's four frames
##                                   tall, rows facing down, up, left, right.
##   res://assets/tiles/<name>.png   16x16, one per tile name in
##                                   WorldMap.TILES ("grass", "path", ...).
##
## Missing files return null and the caller draws its placeholder. Lookups
## are cached, including misses, so drawing a 100x25 map doesn't hit the
## filesystem 2,500 times.

const SPRITE_DIR := "res://assets/sprites/"
const TILE_DIR := "res://assets/tiles/"
const FRAME_WIDTH := 16

static var _cache := {}


static func character(sprite_id: String) -> Texture2D:
	return _load(SPRITE_DIR + sprite_id + ".png")


static func tile(tile_name: String) -> Texture2D:
	return _load(TILE_DIR + tile_name + ".png")


## The part of a character texture to draw standing still, facing down.
static func character_region(tex: Texture2D) -> Rect2:
	return frame_region(tex, Vector2i.DOWN, 0)


## How many frames across a character sheet has (1 for a single image).
static func frame_count(tex: Texture2D) -> int:
	return maxi(1, tex.get_width() / FRAME_WIDTH) if tex.get_width() > 24 else 1


## Frame `frame` (0 standing, 1+ walking) facing `facing`. A sheet four
## frames tall (each 16, 24 or 32) has a row per facing; anything else is
## one row and faces wherever it was drawn facing.
static func frame_region(tex: Texture2D, facing: Vector2i, frame: int) -> Rect2:
	var w := tex.get_width() if tex.get_width() <= 24 else FRAME_WIDTH
	var h := tex.get_height()
	var row := 0
	if h % 4 == 0 and h / 4 in [16, 24, 32]:
		h /= 4
		row = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT].find(facing)
		row = maxi(row, 0)
	h = mini(h, 32)
	return Rect2((frame % frame_count(tex)) * w, row * h, w, h)


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		_cache[path] = tex
	return _cache[path]
