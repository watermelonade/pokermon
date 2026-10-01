class_name AnimalArt
extends RefCounted
## An animal's picture at its seat: the real pixel art when it exists,
## else a placeholder drawn from code (a coloured blob with eyes and the
## species' initial), so the table never waits on art.
##
## Lookup, per species id: assets/portraits/<id>.png (32x32, preferred: it's
## made for this box), then assets/sprites/<id>.png (16x16 or 16x24, drawn at
## the largest whole scale that fits). An imported PNG loads as a resource;
## a PNG that's on disk but not imported yet (the art lands while the
## project is open elsewhere) is read raw with FileAccess, which doesn't
## warn the way Image.load_from_file on a res:// path does. Results are
## cached per species, including "no art".
##
## The placeholder bobs and blinks so the table looks alive; `still` stops
## that (the Possum's tell is going perfectly still).

const BOX := 32
const PORTRAITS := "res://assets/portraits/%s.png"
const SPRITES := "res://assets/sprites/%s.png"

const COLORS := {
	&"owl": Color("8a6a4a"),
	&"raccoon": Color("7d7f8a"),
	&"goose": Color("e8e4d8"),
	&"cat": Color("d98a3b"),
	&"squirrel": Color("b5562e"),
	&"possum": Color("c9bcc8"),
}
const INK := Color("2a2633")
const EYE := Color("f4ecd8")

static var _cache := {}  ## species -> Texture2D, or false for none


static func texture(species: StringName) -> Texture2D:
	if not _cache.has(species):
		var tex: Texture2D = null
		for pattern in [PORTRAITS, SPRITES]:
			tex = _load_png(pattern % species)
			if tex:
				break
		_cache[species] = tex if tex else false
	var hit: Variant = _cache[species]
	return hit if hit is Texture2D else null


static func _load_png(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


static func color(species: StringName) -> Color:
	if COLORS.has(species):
		return COLORS[species]
	return Color.from_hsv(float(hash(species) % 360) / 360.0, 0.45, 0.75)


static func display_name(species: StringName) -> String:
	return Species.CATALOG[species]["display"] if Species.CATALOG.has(species) else String(species).capitalize()


## Draws the animal in the BOX x BOX square at `pos`. `t` is seconds (for the
## idle bob and blink), `phase` offsets it per seat so they don't bob in step,
## `wiggle` (0..1, fading) shakes it sideways for a tell, `dim` greys it out.
static func draw(canvas: CanvasItem, pos: Vector2, species: StringName, t: float, phase: float, still := false, wiggle := 0.0, dim := false) -> void:
	var bob := 0.0 if still else (1.0 if fmod(t * 1.6 + phase, 2.0) < 1.0 else 0.0)
	var shake := roundf(sin(t * 50.0) * 2.0 * wiggle)
	var at := (pos + Vector2(shake, -bob)).floor()
	var mod := Color(0.45, 0.45, 0.5) if dim else Color.WHITE
	var tex := texture(species)
	if tex:
		var tsize := tex.get_size()
		var scale := maxf(1.0, floorf(minf(BOX / tsize.x, BOX / tsize.y)))
		var drawn := tsize * scale
		var origin := at + Vector2(floorf((BOX - drawn.x) / 2), BOX - drawn.y)  # feet on the bottom edge
		canvas.draw_texture_rect(tex, Rect2(origin, drawn), false, mod)
		return
	_draw_placeholder(canvas, at, species, t, phase, still, mod)


static func _draw_placeholder(canvas: CanvasItem, at: Vector2, species: StringName, t: float, phase: float, still: bool, mod: Color) -> void:
	var body := color(species) * mod
	var outline := body.darkened(0.45)
	var c := at + Vector2(16, 19)
	# Ears, then the body over them: reads as "an animal", not a ball.
	canvas.draw_rect(Rect2(c + Vector2(-10, -14), Vector2(5, 6)), outline)
	canvas.draw_rect(Rect2(c + Vector2(5, -14), Vector2(5, 6)), outline)
	_blob(canvas, c, Vector2(13, 12), outline)
	_blob(canvas, c, Vector2(12, 11), body)
	var blink := not still and fmod(t + phase * 1.7, 3.7) < 0.12
	for side in [-1, 1]:
		var eye := c + Vector2(side * 5 - 2, -6)
		if blink:
			canvas.draw_rect(Rect2(eye + Vector2(0, 2), Vector2(4, 1)), INK)
		else:
			canvas.draw_rect(Rect2(eye, Vector2(4, 4)), EYE * mod)
			canvas.draw_rect(Rect2(eye + Vector2(1, 1), Vector2(2, 2)), INK)
	var font := UiFont.large()
	var initial := display_name(species).left(1)
	var w := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.LARGE_SIZE).x
	canvas.draw_string(font, (c + Vector2(-w / 2, 8)).floor(), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.LARGE_SIZE, outline)


static func _blob(canvas: CanvasItem, center: Vector2, radii: Vector2, col: Color) -> void:
	var points := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	canvas.draw_colored_polygon(points, col)
