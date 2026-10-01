extends TestCase
## The controls work on a plain Xbox-style pad (no back buttons), and the
## on-screen names (PadControls) match what's really bound.

## Every action the game reads, and Godot's ui_ ones it uses.
const GAME_ACTIONS := [
	"ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down",
	"move_up", "move_down", "move_left", "move_right", "menu", "help",
	"raise_more", "raise_less", "signal_1", "signal_2", "signal_3", "signal_4",
]
## The hint names of the pad's buttons.
const PAD_BUTTONS := {"X": JOY_BUTTON_X, "Y": JOY_BUTTON_Y}
const PAD_TRIGGERS := {"LT": JOY_AXIS_TRIGGER_LEFT, "RT": JOY_AXIS_TRIGGER_RIGHT}
const BACK_BUTTONS := {"L4": JOY_BUTTON_PADDLE1, "R4": JOY_BUTTON_PADDLE2, "L5": JOY_BUTTON_PADDLE3, "R5": JOY_BUTTON_PADDLE4}


func _buttons(action: String) -> Array[int]:
	var out: Array[int] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append(e.button_index)
	return out


func _keys(action: String) -> Array[int]:
	var out: Array[int] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append(e.physical_keycode)
	return out


func _pad_reaches(action: String) -> bool:
	for b in _buttons(action):
		if b < JOY_BUTTON_MISC1:  # A..D-pad: every Xbox-style pad has them; paddles and Share it may not
			return true
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion and not TriggerButtons.BINDINGS.has(e.axis):
			return true
	return TriggerButtons.BINDINGS.values().has(action)


func test_every_action_works_on_a_pad_without_back_buttons() -> void:
	for action: String in GAME_ACTIONS:
		check(InputMap.has_action(action), "%s exists" % action)
		check(_pad_reaches(action), "%s has a button on an Xbox pad" % action)


func test_signal_names_match_the_input_map() -> void:
	for k in 4:
		var action := "signal_%d" % (k + 1)
		var pad: String = PadControls.SIGNAL_PAD[k]
		if PAD_BUTTONS.has(pad):
			check(_buttons(action).has(PAD_BUTTONS[pad]), "%s is on %s" % [action, pad])
		else:
			check_eq(TriggerButtons.BINDINGS.get(PAD_TRIGGERS[pad], ""), action, "%s is on %s" % [action, pad])
		check(_buttons(action).has(BACK_BUTTONS[PadControls.SIGNAL_BACK[k]]), "%s is on %s" % [action, PadControls.SIGNAL_BACK[k]])
		check(_keys(action).has(OS.find_keycode_from_string(PadControls.SIGNAL_KEYS[k])), "%s is on key %s" % [action, PadControls.SIGNAL_KEYS[k]])


func test_trigger_axes_stay_out_of_the_input_map() -> void:
	# Bound there, one pull presses the action once per motion event (see
	# TriggerButtons): seven signals and seven lots of Heat.
	for action: String in GAME_ACTIONS:
		for e in InputMap.action_get_events(action):
			check(not (e is InputEventJoypadMotion and TriggerButtons.BINDINGS.has(e.axis)), "%s binds a trigger axis" % action)


func test_signal_buttons_do_nothing_else() -> void:
	for k in 4:
		for b in _buttons("signal_%d" % (k + 1)):
			for action: String in GAME_ACTIONS:
				if not action.begins_with("signal_"):
					check(not _buttons(action).has(b), "signal_%d's button %d is also %s" % [k + 1, b, action])


func _motion(axis: JoyAxis, value: float, device := 0) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	return e


## [action, pressed] for each event TriggerButtons sends while the axis
## moves through `values`.
func _feed(t: TriggerButtons, values: Array, axis := JOY_AXIS_TRIGGER_RIGHT, device := 0) -> Array:
	var out := []
	for v: float in values:
		for a in t.feed(_motion(axis, v, device)):
			out.append([String(a.action), a.pressed])
	return out


func test_one_pull_is_one_press() -> void:
	var t := TriggerButtons.new()
	check_eq(_feed(t, [0.1, 0.3, 0.55, 0.7, 0.9, 1.0, 0.95, 1.0, 0.6, 0.2, 0.0]),
			[["signal_4", true], ["signal_4", false]])
	check_eq(_feed(t, [0.8, 0.0]), [["signal_4", true], ["signal_4", false]], "and the next pull is another")
	t.free()


func test_a_trigger_hovering_at_the_line_presses_once() -> void:
	var t := TriggerButtons.new()
	check_eq(_feed(t, [0.58, 0.61, 0.59, 0.62, 0.45, 0.65, 0.35], JOY_AXIS_TRIGGER_LEFT),
			[["signal_3", true]], "pressed until it comes back under the release line")
	check_eq(_feed(t, [0.29], JOY_AXIS_TRIGGER_LEFT), [["signal_3", false]])
	t.free()


func test_each_pad_and_trigger_counts_separately() -> void:
	var t := TriggerButtons.new()
	check_eq(_feed(t, [1.0], JOY_AXIS_TRIGGER_RIGHT, 0), [["signal_4", true]])
	check_eq(_feed(t, [1.0], JOY_AXIS_TRIGGER_RIGHT, 1), [["signal_4", true]], "a second pad")
	check_eq(_feed(t, [1.0], JOY_AXIS_TRIGGER_LEFT, 0), [["signal_3", true]], "the other trigger")
	check_eq(_feed(t, [1.0, -1.0, 0.0], JOY_AXIS_LEFT_X), [], "the stick isn't a trigger")
	t.free()


func test_an_unplugged_pad_lets_go() -> void:
	var t := TriggerButtons.new()
	_feed(t, [1.0])
	t.forget(0)
	check_eq(_feed(t, [1.0]), [["signal_4", true]], "plugged back in and pulled: a new press")
	t.free()


func test_lb_held_makes_a_trigger_signal_a_fake() -> void:
	var t := TriggerButtons.new()
	var press: InputEventAction = t.feed(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))[0]
	check(not InterceptOverlay.is_fake_press(press), "a plain pull is a real signal")
	Input.action_press("raise_less")
	check(InterceptOverlay.is_fake_press(press), "with LB held it's a fake")
	Input.action_release("raise_less")
	t.free()
