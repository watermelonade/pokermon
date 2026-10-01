class_name UiFont
extends RefCounted
## The table's two pixel fonts, at the only sizes they render crisply.
##
## Godot's default font is a smooth outline font: at the 8-10px the table
## needs at 640x400 it came out as grey, blurry text, and the Deck's x2
## integer scale only doubled the blur. A pixel font drawn at exactly its
## design size (or a whole multiple of it) lands every stroke on a pixel.
## Compared side by side at 640x400 (Silkscreen, Tiny5, Micro 5, Jersey 10,
## Pixelify Sans, VT323, Bytesized, Departure Mono): these two were the
## clearest with lowercase, and both are SIL OFL 1.1 (licenses next to the
## font files in assets/fonts/):
##
##   SMALL  Tiny5 (Stefan Schmidt), 8px: 5px capitals, proportional, for the
##          log, the legend, statuses and small cards.
##   LARGE  Departure Mono (Helena Zhang), 11px: 7px capitals, for what the
##          player reads mid-hand: names, stacks, the pot, buttons, ranks.
##
## Their .import files turn antialiasing, hinting and subpixel positioning
## off; with any of those on the strokes smear again. Only ever draw them at
## SMALL_SIZE / LARGE_SIZE (or x2): in between they're uneven.

const SMALL_PATH := "res://assets/fonts/Tiny5-Regular.ttf"
const LARGE_PATH := "res://assets/fonts/DepartureMono-Regular.otf"
const SMALL_SIZE := 8
const LARGE_SIZE := 11

static var _small: Font
static var _large: Font


static func small() -> Font:
	if _small == null:
		_small = _load(SMALL_PATH)
	return _small


static func large() -> Font:
	if _large == null:
		_large = _load(LARGE_PATH)
	return _large


static func _load(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font
