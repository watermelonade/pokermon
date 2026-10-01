extends Node
## Plays the real table with a pretend Xbox pad and exits non-zero unless
## every signal arrives as one signal:
##
##   godot --headless --path . res://tests/pad_check.tscn
##
## A scene, like compile_check, because the triggers go through the
## `Triggers` autoload (TriggerButtons), which the test runner doesn't have.
## The events go in through Input.parse_input_event, the way a controller's
## do, so this checks the whole path: the input map, the autoload and the
## table's own input handling. What it can't check is a real controller's
## SDL mapping (which pad reports which button): that's the hand checklist
## in docs/PLAYTEST.md.

var _failures: Array[String] = []


func _ready() -> void:
	var table: Control = load("res://scenes/table.tscn").instantiate()
	table.embedded = true
	table.dealer_kind = Dealer.Kind.STREET  # no Heat, so four signals in a hand are fine
	add_child(table)
	await _frames(5)
	var talk: TableTalk = table.match_.talk
	_check(not table.match_.table.hand_over, "a hand is being played")

	await _button(JOY_BUTTON_X)
	_expect(talk, [[0, false]], "X: signal 1")
	await _button(JOY_BUTTON_Y)
	_expect(talk, [[0, false], [1, false]], "Y: signal 2")
	# One full pull of RT, as a pad reports it: many small steps there and back.
	await _pull(JOY_AXIS_TRIGGER_RIGHT, [0.1, 0.3, 0.55, 0.7, 0.9, 1.0, 0.95, 1.0, 0.6, 0.2, 0.0])
	_expect(talk, [[0, false], [1, false], [3, false]], "RT: signal 4, once")
	# LB held marks a fake; LT resting near the line and jittering is still one press.
	Input.parse_input_event(_pad_button(JOY_BUTTON_LEFT_SHOULDER, true))
	await _frames(1)
	await _pull(JOY_AXIS_TRIGGER_LEFT, [0.5, 0.65, 0.55, 0.62, 0.4, 0.7, 0.1])
	Input.parse_input_event(_pad_button(JOY_BUTTON_LEFT_SHOULDER, false))
	await _frames(1)
	_expect(talk, [[0, false], [1, false], [3, false], [2, true]], "LB + LT: a fake signal 3, once")

	table.queue_free()  # before quitting, so the exit doesn't report it leaked
	await _frames(2)
	for f in _failures:
		printerr("FAIL ", f)
	print("pad check: %s" % ("ok" if _failures.is_empty() else "%d failures" % _failures.size()))
	get_tree().quit(1 if _failures else 0)


func _expect(talk: TableTalk, want: Array, what: String) -> void:
	var got := []
	for s: Dictionary in talk.sent:
		if s["from"] == 0:
			got.append([s["sig"], s["fake"]])
	_check(got == want, "%s: sent %s, expected %s" % [what, got, want])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _button(index: JoyButton) -> void:
	Input.parse_input_event(_pad_button(index, true))
	await _frames(1)
	Input.parse_input_event(_pad_button(index, false))
	await _frames(1)


func _pull(axis: JoyAxis, values: Array) -> void:
	for v: float in values:
		var e := InputEventJoypadMotion.new()
		e.device = 0
		e.axis = axis
		e.axis_value = v
		Input.parse_input_event(e)
		await _frames(1)


static func _pad_button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = index
	e.pressed = pressed
	return e


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
