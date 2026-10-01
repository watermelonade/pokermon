class_name TriggerButtons
extends Node
## Makes the triggers (LT, RT) act like buttons for the actions bound to
## them, one press per pull. Autoloaded as `Triggers` (project.godot).
##
## Why not bind the trigger axes in the input map like the stick: a trigger
## is an axis, and Godot sends a motion event for every change in how far
## it's pulled. `event.is_action_pressed()` is true for each one past the
## deadzone, so one pull read as a signal 7 times when measured (4.7.2,
## eleven motion events from rest to full and back), and each of those
## would cost Heat. The table reads signals from events, as it reads every
## other button, so instead this node watches the raw trigger motion and
## sends one InputEventAction when a trigger goes down and one when it comes
## back up. The table then can't tell a trigger from a button.
##
## Two thresholds (press past PRESS, release under RELEASE) so a trigger
## resting halfway, or a worn one that jitters, doesn't press twice.

const BINDINGS := {
	JOY_AXIS_TRIGGER_LEFT: "signal_3",
	JOY_AXIS_TRIGGER_RIGHT: "signal_4",
}
const PRESS := 0.6
const RELEASE := 0.3

var _down := {}  ## Vector2i(device, axis) -> true while that trigger is held


func _ready() -> void:
	Input.joy_connection_changed.connect(func(device: int, _connected: bool) -> void: forget(device))


func _input(event: InputEvent) -> void:
	for action in feed(event):
		Input.parse_input_event(action)


## The action presses and releases this event makes, if any (none for
## anything but trigger motion). Separate from _input so tests can drive it.
func feed(event: InputEvent) -> Array[InputEventAction]:
	var out: Array[InputEventAction] = []
	var motion := event as InputEventJoypadMotion
	if motion == null or not BINDINGS.has(motion.axis):
		return out
	var key := Vector2i(motion.device, motion.axis)
	var held: bool = _down.get(key, false)
	if not held and motion.axis_value >= PRESS:
		_down[key] = true
		out.append(_action(BINDINGS[motion.axis], true))
	elif held and motion.axis_value <= RELEASE:
		_down.erase(key)
		out.append(_action(BINDINGS[motion.axis], false))
	return out


## A controller came or went: whatever it was holding is let go, so a pad
## unplugged mid-pull doesn't leave a trigger stuck down.
func forget(device: int) -> void:
	for key: Vector2i in _down.keys():
		if key.x == device:
			_down.erase(key)


static func _action(action: String, pressed: bool) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	return e
