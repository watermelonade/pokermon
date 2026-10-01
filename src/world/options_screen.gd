class_name OptionsScreen
extends Control
## Options, from the start menu: up/down picks a row, left/right changes it,
## B (or A on "Done") saves and closes. Small on purpose: text speed and
## volume are what a handheld player reaches for; everything else can wait
## for a real settings pass.

signal closed

const ROWS := ["Text speed", "Volume", "Done"]

var settings: Settings
var _cursor := 0
var _opened_frame := 0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(s: Settings) -> void:
	settings = s
	_cursor = 0
	_opened_frame = Engine.get_process_frames()
	visible = true
	queue_redraw()
	await closed
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	var d := UiKit.menu_dir(event)
	if d.y != 0:
		_cursor = wrapi(_cursor + d.y, 0, ROWS.size())
	elif d.x != 0:
		match _cursor:
			0:
				settings.text_speed = clampi(settings.text_speed + d.x, 0, Settings.TEXT_SPEEDS.size() - 1)
			1:
				settings.volume = clampi(settings.volume + d.x, 0, 10)
				settings.apply()
	elif UiKit.cancel(event) or (UiKit.accept(event) and _cursor == ROWS.size() - 1):
		settings.save_to()
		closed.emit()
	else:
		return
	queue_redraw()
	get_viewport().set_input_as_handled()


func _draw() -> void:
	var box := Rect2(size.x / 2 - 150, 90, 300, 150)
	UiKit.panel(self, box)
	UiKit.text(self, box.position + Vector2(16, 24), "Options", 16, UiKit.GOLD)
	var values := [Settings.TEXT_SPEEDS[settings.text_speed], "%d" % settings.volume, ""]
	for i in ROWS.size():
		var y := box.position.y + 58 + i * 26
		var on := i == _cursor
		if on:
			var tip := Vector2(box.position.x + 16, y - 8)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(0, 8), tip + Vector2(5, 4)]), UiKit.GOLD)
		UiKit.text(self, Vector2(box.position.x + 28, y), ROWS[i], 10, UiKit.TEXT if on else UiKit.QUIET)
		if values[i] != "":
			UiKit.text(self, Vector2(box.end.x - 70, y), "< %s >" % values[i], 10, UiKit.TEXT if on else UiKit.QUIET, 1)
		if i == 1:  # a volume bar
			var bar := Rect2(box.position.x + 110, y - 6, 60, 5)
			draw_rect(bar, UiKit.BG)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * settings.volume / 10.0, bar.size.y)), UiKit.GOLD)
	UiKit.text(self, Vector2(box.position.x + box.size.x / 2, box.end.y - 10), "Left / right to change, B to close", 8, UiKit.QUIET, 1)
