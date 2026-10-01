class_name CoachBox
extends RefCounted
## How the coach's lines look at the table: the same bottom text box the
## table's play-by-play uses (so the screen keeps one place to read), with
## the coach's little figure at its left, her name on a tab over the top
## border and a gold frame, so it's clear this is someone talking to you and
## not the table's "Honk raises to 60!". Lines wrap to the box's two rows;
## TutorialScript keeps every line short enough (tests/test_tutorial.gd
## checks).
##
## Drawing only: the queue and what A does are TableTutorial's.

const FRAME := Color("e8c35a")  ## gold: the coach, not the table
const TEXT_X := 34.0  ## room for the figure at the left
const LINE_GAP := 14.0


## Splits `text` into rows that fit `width` in the large font, breaking at
## spaces.
static func wrap_rows(text: String, width: float) -> PackedStringArray:
	var font := UiFont.large()
	var rows := PackedStringArray()
	var row := ""
	for word in text.split(" "):
		var candidate := word if row == "" else row + " " + word
		if row != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.LARGE_SIZE).x > width:
			rows.append(row)
			row = word
		else:
			row = candidate
	if row != "":
		rows.append(row)
	return rows


## The width text gets inside a box of width `box_width`.
static func text_width(box_width: float) -> float:
	return box_width - TEXT_X - 18.0


## Draws the box `r` with `shown` characters of `text` typed out, and the
## speaker's walk sheet's standing frame (`sprite`, may be null). `hint`
## goes on a tab over the right end of the top border (what to press when
## A alone isn't the answer); `arrow` blinks the "press A" arrow.
static func draw(canvas: CanvasItem, r: Rect2, speaker: String, sprite: Texture2D, text: String, shown: int, hint: String, arrow: bool) -> void:
	PixelFrame.panel(canvas, r, PixelFrame.CREAM, FRAME, 3)
	var small := UiFont.small()
	# The name tab, over the top-left border.
	if speaker:
		var w := small.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.SMALL_SIZE).x + 10
		var tab := Rect2(r.position + Vector2(8, -9), Vector2(w, 12))
		PixelFrame.panel(canvas, tab, FRAME, PixelFrame.INK, 1)
		canvas.draw_string(small, (tab.position + Vector2(5, 9)).floor(), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.SMALL_SIZE, PixelFrame.INK)
	if hint:
		var w := small.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.SMALL_SIZE).x + 10
		var tab := Rect2(Vector2(r.end.x - w - 8, r.position.y - 9), Vector2(w, 12))
		PixelFrame.panel(canvas, tab, PixelFrame.CREAM, FRAME, 1)
		canvas.draw_string(small, (tab.position + Vector2(5, 9)).floor(), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.SMALL_SIZE, PixelFrame.INK)
	if sprite:
		# The standing frame (column 0, facing down) of the walk sheet. The
		# caller holds `sprite`: one loaded inside _draw and let go is freed
		# before the frame renders, and draws as a white block.
		var frame := Vector2(sprite.get_width() / Sprites.WALK_FRAMES, sprite.get_height() / Sprites.FACING_NAMES.size())
		var at := Vector2(r.position.x + 9, r.position.y + floorf((r.size.y - frame.y) / 2))
		canvas.draw_texture_rect_region(sprite, Rect2(at.floor(), frame), Rect2(Vector2.ZERO, frame))
	var rows := wrap_rows(text, text_width(r.size.x))
	var left := shown
	var y := r.position.y + 21 if rows.size() > 1 else r.position.y + 29
	for row in rows.slice(0, 2):
		if left <= 0:
			break
		var part := row.left(left)
		left -= row.length() + 1
		canvas.draw_string(UiFont.large(), Vector2(r.position.x + TEXT_X, y).floor(), part, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.LARGE_SIZE, PixelFrame.INK)
		y += LINE_GAP
	if arrow:
		PixelFrame.down_arrow(canvas, r.end - Vector2(17, 11), PixelFrame.INK)
