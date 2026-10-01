class_name ChoiceMenu
extends Control
## A small list to pick from with the D-pad and A: who to recruit, yes or
## no, the start menu. `var i := await menu.choose("Title", ["a", "b"], 1)`
## returns the index picked; B returns `cancel_index` (or does nothing if
## it's -1, when a choice must be made). Sits above the dialog box so a
## question and its answers can share the screen, or, with `corner`, in the
## top right like a handheld RPG's start menu (where Start also closes it).
##
## With --auto, menus pick --choice (default 0); corner menus close instead,
## or a scripted run would reopen the start menu forever.

signal chosen(index: int)

var _title := ""
var _options: Array[String] = []
var _cursor := 0
var _cancel := -1
var _opened_frame := 0
var _auto_at := 0
var _corner := false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func choose(title: String, options: Array, cancel_index := -1, corner := false, start_at := 0) -> int:
	_title = title
	_options.clear()
	for o: Variant in options:
		_options.append(str(o))
	_cursor = clampi(start_at, 0, _options.size() - 1)
	_cancel = cancel_index
	_corner = corner
	_opened_frame = Engine.get_process_frames()
	_auto_at = Time.get_ticks_msec() + 900
	visible = true
	queue_redraw()
	var picked: int = await chosen
	visible = false
	return picked


func _process(_delta: float) -> void:
	if visible and Game.dev_auto and Time.get_ticks_msec() > _auto_at:
		_auto_at = 1 << 62
		if _corner:
			chosen.emit(_cancel)
		else:
			chosen.emit(Game.dev_choice if Game.dev_choice < _options.size() else 0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	var d := UiKit.menu_dir(event)
	if d.y != 0:
		_cursor = wrapi(_cursor + d.y, 0, _options.size())
		queue_redraw()
	elif UiKit.accept(event):
		chosen.emit(_cursor)
	elif (event.is_action_pressed("ui_cancel") or (_corner and event.is_action_pressed("menu"))) and _cancel >= 0:
		chosen.emit(_cancel)
	else:
		return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	var w := UiKit.text_width(_title, 10) + 24
	for o in _options:
		w = maxf(w, UiKit.text_width(o, 10) + 40)
	w = minf(w, size.x - 16)
	var head := 20.0 if _title else 2.0
	var h := head + 12 + _options.size() * 16
	var box := Rect2(size.x - w - 8, size.y - 76 - h - 4, w, h)
	if _corner:
		box.position.y = 8
	UiKit.panel(self, box)
	if _title:
		UiKit.text(self, box.position + Vector2(12, 18), _title, 10, UiKit.GOLD)
	for i in _options.size():
		var y := box.position.y + head + 16 + i * 16
		var color := UiKit.TEXT if i == _cursor else UiKit.QUIET
		if i == _cursor:
			var tip := Vector2(box.position.x + 12, y - 8)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(0, 8), tip + Vector2(5, 4)]), UiKit.GOLD)
		UiKit.text(self, Vector2(box.position.x + 22, y), _options[i], 10, color)
