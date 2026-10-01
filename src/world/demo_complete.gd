class_name DemoComplete
extends Control
## The end of the demo: shown after winning the Mossbank Open. Sums up the
## run (bracelet, crews beaten, who joined) and hands you back to the
## overworld, so you can keep walking around rather than being thrown to the
## title. The save already has the bracelet by the time this shows.

signal closed

var state: GameState
var crews_total := 0
var _opened_frame := 0
var _auto_at := 0
var _t := 0.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(s: GameState, total_crews: int) -> void:
	state = s
	crews_total = total_crews
	_opened_frame = Engine.get_process_frames()
	_auto_at = Time.get_ticks_msec() + 2500
	visible = true
	queue_redraw()
	await closed
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()
	if Game.dev_auto and Time.get_ticks_msec() > _auto_at:
		_auto_at = 1 << 62
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and Engine.get_process_frames() != _opened_frame and UiKit.accept(event):
		get_viewport().set_input_as_handled()
		closed.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	var cx := size.x / 2
	UiKit.text(self, Vector2(cx, 64), "Demo complete!", 24, UiKit.GOLD, 1)
	UiKit.text(self, Vector2(cx, 88), "You won the Mossbank Open and its bracelet.", 10, UiKit.TEXT, 1)
	# The bracelet: a gold ring with a felt-green stone, turning slowly.
	var c := Vector2(cx, 150)
	var squash := 0.55 + 0.25 * sin(_t * 1.5)
	var ring := PackedVector2Array()
	for k in 33:
		var a := TAU * k / 32.0
		ring.append(c + Vector2(cos(a) * 34, sin(a) * 34 * squash))
	draw_polyline(ring, UiKit.GOLD, 5)
	draw_rect(Rect2(c + Vector2(-6, 34 * squash - 6), Vector2(12, 12)), Color("2b5b3a"))
	draw_rect(Rect2(c + Vector2(-6, 34 * squash - 6), Vector2(12, 12)), UiKit.TEXT, false)
	var beaten := 0
	for id: String in state.beaten:
		if id != "mossbank_regulars":
			beaten += 1
	var lines := [
		"Rival crews beaten on Ridge Road: %d of %d" % [beaten, crews_total],
		"Animals in your crew: %d" % state.roster.size(),
		"Money: $%d" % state.money,
	]
	for i in lines.size():
		UiKit.text(self, Vector2(cx, 222 + i * 16), lines[i], 10, UiKit.TEXT, 1)
	var names: Array[String] = []
	for a in state.roster:
		names.append(a.name)
	UiKit.text(self, Vector2(cx, 278), ", ".join(names), 8, UiKit.QUIET, 1)
	# Your crew, standing in a row.
	var n := state.roster.size()
	for i in n:
		var at := Vector2(cx - n * 20 + i * 40 + 4, 296)
		Critter.paint(self, String(state.roster[i].species), Vector2i.DOWN, at, 2.0)
	UiKit.text(self, Vector2(cx, size.y - 30), "Thanks for playing. The next town is still being built.", 8, UiKit.QUIET, 1)
	UiKit.text(self, Vector2(cx, size.y - 16), "Press A to keep exploring", 10, UiKit.GOLD if int(_t * 2) % 2 == 0 else UiKit.TEXT, 1)
