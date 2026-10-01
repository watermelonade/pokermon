class_name CardArt
extends RefCounted
## Placeholder card art drawn from code: a cream card, the rank in the
## corner and a 7x7 pixel suit. Suits are drawn as pixels rather than font
## glyphs because the default font has no ♠♥♦♣ and the Deck has no system
## font to fall back on. Swap for Aseprite art when it exists.

const CREAM := Color("f4ecd8")
const EDGE := Color("c9bfa5")
const RED := Color("b13e3e")
const INK := Color("2a2633")
const BACK := Color("3a4f8a")
const BACK_PATTERN := Color("5a72b8")

const SUITS := [
	# clubs
	["..XXX..", "..XXX..", "XXXXXXX", "XXXXXXX", "XX.X.XX", "...X...", "..XXX.."],
	# diamonds
	["...X...", "..XXX..", ".XXXXX.", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."],
	# hearts
	[".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X...", "......."],
	# spades
	["...X...", "..XXX..", ".XXXXX.", "XXXXXXX", "XXXXXXX", "...X...", "..XXX.."],
]


static func draw_card(canvas: CanvasItem, pos: Vector2, card: int, face_up: bool, size := Vector2(22, 30)) -> void:
	pos = pos.floor()
	canvas.draw_rect(Rect2(pos, size), EDGE)
	canvas.draw_rect(Rect2(pos + Vector2(1, 1), size - Vector2(2, 2)), CREAM if face_up else BACK)
	if not face_up:
		for y in range(3, int(size.y) - 3, 3):
			for x in range(3 + (1 if y % 6 >= 3 else 0), int(size.x) - 3, 3):
				canvas.draw_rect(Rect2(pos + Vector2(x, y), Vector2(1, 1)), BACK_PATTERN)
		return
	var color := RED if Card.is_red(card) else INK
	var font := ThemeDB.fallback_font
	var font_size := 10 if size.y < 36 else 12
	canvas.draw_string(font, pos + Vector2(3, font_size), Card.rank_label(card), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_suit(canvas, pos + Vector2(size.x - 9, size.y - 9), Card.suit(card), color)


static func draw_suit(canvas: CanvasItem, pos: Vector2, suit: int, color: Color) -> void:
	var rows: Array = SUITS[suit]
	for y in 7:
		var row: String = rows[y]
		for x in 7:
			if row[x] == "X":
				canvas.draw_rect(Rect2(pos + Vector2(x, y), Vector2(1, 1)), color)
