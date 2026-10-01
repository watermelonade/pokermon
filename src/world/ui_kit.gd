class_name UiKit
extends RefCounted
## Shared look and input for the overworld's screens (dialog, menus, party,
## title), so they match the table's placeholder palette and read the same
## inputs. Everything is drawn with _draw() at the 640x400 base resolution,
## like the table, rather than with Godot's themed Buttons: menus here are
## steered by the D-pad and A/B only, and custom drawing keeps the pixel look
## consistent until a real UI skin exists.

const BG := Color("1d1a24")
const PANEL := Color("2a2433")
const EDGE := Color("e8c35a")
const TEXT := Color("f4ecd8")
const QUIET := Color("a89f8c")
const GOLD := Color("e8c35a")
const HOT := Color("d9603b")
const TEAL := Color("2f6f6a")
const RUST := Color("7a3b2e")


static func font() -> Font:
	return ThemeDB.fallback_font


static func panel(ci: CanvasItem, rect: Rect2, edge := EDGE) -> void:
	ci.draw_rect(rect, PANEL)
	ci.draw_rect(rect.grow(-1), edge, false)
	ci.draw_rect(rect.grow(-3), edge.darkened(0.5), false)


## `align`: 0 left, 1 centred on pos.x, 2 right-aligned to pos.x.
static func text(ci: CanvasItem, pos: Vector2, s: String, size := 10, color := TEXT, align := 0) -> void:
	var f := font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if align == 1:
		pos.x -= w / 2
	elif align == 2:
		pos.x -= w
	ci.draw_string(f, pos.floor(), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func wrapped(ci: CanvasItem, pos: Vector2, s: String, width: float, size := 10, color := TEXT, max_lines := -1) -> void:
	ci.draw_multiline_string(font(), pos.floor(), s, HORIZONTAL_ALIGNMENT_LEFT, width, size, max_lines, color)


static func text_width(s: String, size := 10) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Up/down/left/right from either the movement actions (stick, D-pad,
## WASD, arrows) or Godot's ui_ actions, for menus.
static func menu_dir(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("move_up", true) or event.is_action_pressed("ui_up", true):
		return Vector2i.UP
	if event.is_action_pressed("move_down", true) or event.is_action_pressed("ui_down", true):
		return Vector2i.DOWN
	if event.is_action_pressed("move_left", true) or event.is_action_pressed("ui_left", true):
		return Vector2i.LEFT
	if event.is_action_pressed("move_right", true) or event.is_action_pressed("ui_right", true):
		return Vector2i.RIGHT
	return Vector2i.ZERO


static func accept(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept")


static func cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")
