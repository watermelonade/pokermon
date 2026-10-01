class_name DialogBox
extends Control
## The text box along the bottom of the screen: one line at a time, typed
## out, A to finish the line or go on. `await dialog.say([...])` returns when
## the last line is dismissed, so encounter scripts read top to bottom.
##
## Input arriving in the same frame the box opens is ignored: the A press
## that started a conversation would otherwise also skip its first line.
## With Game.dev_auto (the --auto dev flag) lines advance by themselves, for
## scripted screenshot runs.

signal line_done

const CHARS_PER_SECOND := 60.0
const HEIGHT := 70.0

var _lines: Array[String] = []
var _speaker := ""
var _shown := 0.0
var _opened_frame := 0
var _auto_at := 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func is_open() -> bool:
	return visible


func say(lines: Array, speaker := "") -> void:
	_lines.clear()
	for l: Variant in lines:
		_lines.append(str(l))
	_speaker = speaker
	visible = true
	while _lines:
		_shown = 0.0
		_opened_frame = Engine.get_process_frames()
		_auto_at = Time.get_ticks_msec() + 700
		queue_redraw()
		await line_done
		_lines.pop_front()
	visible = false


func _current() -> String:
	return _lines[0] if _lines else ""


func _process(delta: float) -> void:
	if not visible:
		return
	if _shown < _current().length():
		_shown = minf(_current().length(), _shown + delta * CHARS_PER_SECOND)
		queue_redraw()
	elif Game.dev_auto and Time.get_ticks_msec() > _auto_at:
		line_done.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if UiKit.accept(event) or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _shown < _current().length():
			_shown = _current().length()
			queue_redraw()
		else:
			line_done.emit()


func _draw() -> void:
	var box := Rect2(8, size.y - HEIGHT - 6, size.x - 16, HEIGHT)
	UiKit.panel(self, box)
	var y := box.position.y + 18
	if _speaker:
		UiKit.text(self, Vector2(box.position.x + 12, y), _speaker, 10, UiKit.GOLD)
		y += 14
	var text := _current().substr(0, int(_shown))
	UiKit.wrapped(self, Vector2(box.position.x + 12, y), text, box.size.x - 30, 10, UiKit.TEXT, 3)
	if _shown >= _current().length() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		var tip := box.end - Vector2(16, 12)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(6, 0), tip + Vector2(3, 4)]), UiKit.GOLD)
	if _shown >= _current().length():
		queue_redraw()  # keep the arrow blinking
