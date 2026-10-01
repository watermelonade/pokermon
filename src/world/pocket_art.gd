class_name PocketArt
extends RefCounted
## Small pieces of pixel art the Binder and the crew screen share: bond
## hearts, portraits in three looks (full colour, greyed for "seen", a flat
## silhouette for "unseen"), and the dogs' silhouette.
##
## The greyed and silhouette portraits are made from the portrait PNGs at
## runtime (and cached) rather than drawn as extra files: a redrawn
## portrait then updates all three looks, and Godot's draw modulate can
## only tint, not desaturate or flatten. There's no dog art yet (dogs are
## a post-finale species), so its silhouette is a pixel grid here.

enum Look { FULL, GREY, SHADOW }

const HEARTS := 5  ## bond 0..1 in fifths; half hearts show the 0.1 steps
const HEART := [".xx.xx.", "xxxxxxx", "xxxxxxx", ".xxxxx.", "..xxx..", "...x..."]
const HEART_FULL := Color("e43b44")
const HEART_EMPTY := Color("3a4466")
const SHADOW := Color("3a4466")

## A dog sitting side-on, facing left: snout, a floppy ear, a front leg,
## the haunch and a tail. 16x16, like the species sprites.
const DOG := [
	"......kk........",
	".....kkkk.......",
	"...kkkkkkk......",
	"kkkkkkkkkkk.....",
	"kkkkkkkkkkkk....",
	".kkkkkkk.kkk....",
	"...kkkkk..kk....",
	"...kkkkkk.......",
	"...kkkkkkkk.....",
	"...kkkkkkkkk....",
	"...kkk.kkkkkk...",
	"...kkk.kkkkkk...",
	"...kkk.kkkkkkk..",
	"...kkk.kkkkkkk.k",
	"..kkkk.kkkkkkkkk",
	"..kkkk.kkkkkkk..",
]

static var _cache := {}


## Bond as five pixel hearts from `pos` (top left), `s` screen pixels per
## art pixel. Each heart is 0.2 of bond; a half-filled heart is 0.1.
static func hearts(ci: CanvasItem, pos: Vector2, bond: float, s := 1.0) -> void:
	var halves := roundi(clampf(bond, 0.0, 1.0) * HEARTS * 2)
	for h in HEARTS:
		var filled := clampi(halves - h * 2, 0, 2)  # 0 empty, 1 half, 2 full
		var at := pos + Vector2(h * 8 * s, 0)
		for y in HEART.size():
			var row: String = HEART[y]
			for x in row.length():
				if row[x] != "x":
					continue
				var full := filled == 2 or (filled == 1 and x < 4)
				ci.draw_rect(Rect2(at + Vector2(x, y) * s, Vector2(s, s)), HEART_FULL if full else HEART_EMPTY)


static func hearts_width(s := 1.0) -> float:
	return (HEARTS * 8 - 1) * s


## A species' portrait in `rect` (32x32 art, scaled to fit). Falls back to
## the walk sprite's code placeholder when there's no portrait.
static func portrait(ci: CanvasItem, species_id: StringName, rect: Rect2, look := Look.FULL) -> void:
	var tex := _portrait(species_id, look)
	if tex:
		ci.draw_texture_rect(tex, rect, false)
	else:
		Critter.paint(ci, String(species_id), Vector2i.DOWN, rect.position, rect.size.x / 16.0)


static func dog(ci: CanvasItem, rect: Rect2, color := SHADOW) -> void:
	var s := rect.size.x / 16.0
	for y in DOG.size():
		var row: String = DOG[y]
		for x in row.length():
			if row[x] == "k":
				ci.draw_rect(Rect2(rect.position + Vector2(x, y) * s, Vector2(s, s)), color)


static func _portrait(species_id: StringName, look: Look) -> Texture2D:
	var key := "%s/%d" % [species_id, look]
	if _cache.has(key):
		return _cache[key]
	var tex := Sprites.portrait(species_id)
	if tex and look != Look.FULL:
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				if look == Look.SHADOW:
					img.set_pixel(x, y, Color(SHADOW, c.a))
				else:
					# Greyscale, pulled toward the panel colour so it reads as
					# "not yours yet" next to the full-colour cards.
					var v := c.get_luminance()
					img.set_pixel(x, y, Color(v, v, v, c.a).lerp(Color("2a2433"), 0.35))
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
