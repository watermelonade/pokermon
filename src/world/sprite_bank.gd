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
##                                   A wider image is read as a strip of
##                                   16-wide frames: the first is used.
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


## The part of a character texture to draw: the whole thing, or the first
## frame of a horizontal strip.
static func character_region(tex: Texture2D) -> Rect2:
	var w := tex.get_width()
	if w > 24:
		w = FRAME_WIDTH
	return Rect2(0, 0, w, mini(tex.get_height(), 32))


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		_cache[path] = tex
	return _cache[path]
