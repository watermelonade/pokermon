class_name PixelFrame
extends RefCounted
## The table's UI frames, in the handheld-RPG battle-screen style the demo
## is going for: a cream panel, a chunky coloured border, a dark outline and
## notched (one-pixel-cut) corners, plus the menu cursor and the "press A"
## arrow. Original pixel shapes drawn from code; nothing is taken from any
## game's art.
##
## Everything snaps to whole pixels: at 640x400 scaled x2, a half-pixel
## edge turns into a blurry seam on the Deck.

const CREAM := Color("f8f2e2")
const INK := Color("2a2633")
const INK_SOFT := Color("6a6072")
const BLUE := Color("4f86c6")
const SHADOW := Color(0, 0, 0, 0.35)


## A framed panel: 1px dark outline, `border_width` of `border`, `fill`
## inside, a 1px drop shadow under it so it lifts off the felt.
static func panel(canvas: CanvasItem, r: Rect2, fill := CREAM, border := BLUE, border_width := 2) -> void:
	r = Rect2(r.position.floor(), r.size.floor())
	notched(canvas, Rect2(r.position + Vector2(1, 1), r.size), SHADOW)
	notched(canvas, r, INK)
	notched(canvas, r.grow(-1), border)
	notched(canvas, r.grow(-1 - border_width), fill)


## A rectangle with its four corner pixels cut off.
static func notched(canvas: CanvasItem, r: Rect2, color: Color) -> void:
	if r.size.x < 3 or r.size.y < 3:
		canvas.draw_rect(r, color)
		return
	canvas.draw_rect(Rect2(r.position + Vector2(1, 0), r.size - Vector2(2, 0)), color)
	canvas.draw_rect(Rect2(r.position + Vector2(0, 1), r.size - Vector2(0, 2)), color)


## The menu cursor: a 4x7 right-pointing triangle with its tip at `tip`.
static func cursor(canvas: CanvasItem, tip: Vector2, color := INK) -> void:
	tip = tip.floor()
	for k in 4:
		canvas.draw_rect(Rect2(tip + Vector2(-3 + k, -3 + k), Vector2(1, 7 - 2 * k)), color)


## The "more to read / press A" arrow: a 7x4 down-pointing triangle.
static func down_arrow(canvas: CanvasItem, top_left: Vector2, color := INK) -> void:
	top_left = top_left.floor()
	for k in 4:
		canvas.draw_rect(Rect2(top_left + Vector2(k, k), Vector2(7 - 2 * k, 1)), color)


## Up/down arrows either side of a number, for amount pickers.
static func up_arrow(canvas: CanvasItem, top_left: Vector2, color := INK) -> void:
	top_left = top_left.floor()
	for k in 4:
		canvas.draw_rect(Rect2(top_left + Vector2(3 - k, k), Vector2(1 + 2 * k, 1)), color)
