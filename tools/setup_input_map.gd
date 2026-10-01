extends SceneTree
## Writes the game's input actions into project.godot. Run once after
## changing the bindings here (or edit them in Project Settings > Input Map):
##
##   godot --headless --path . -s tools/setup_input_map.gd
##
## The four signals sit on the Steam Deck's back buttons (L4 R4 L5 R5 are
## the SDL paddles 1-4) and on 1-4. Steam Input passes the back buttons
## through only if the game's controller layout maps them, so the Steam
## store config should ship a layout that does.
##
## Walking uses its own move_ actions (arrows, WASD, D-pad, left stick)
## rather than Godot's ui_ ones, so menus and the table's buttons keep their
## defaults. `menu` (Start, Tab, Esc) opens the party screen. Confirm and
## back are Godot's ui_accept (A, Enter, Space) and ui_cancel (B, Esc).
##
## Entries: an int is a key (physical keycode) if >= KEY_SPACE, else a
## joypad button; [axis, direction] is a stick direction.

const ACTIONS := {
	"signal_1": [KEY_1, JOY_BUTTON_PADDLE1],
	"signal_2": [KEY_2, JOY_BUTTON_PADDLE2],
	"signal_3": [KEY_3, JOY_BUTTON_PADDLE3],
	"signal_4": [KEY_4, JOY_BUTTON_PADDLE4],
	"raise_more": [KEY_E, JOY_BUTTON_RIGHT_SHOULDER],
	"raise_less": [KEY_Q, JOY_BUTTON_LEFT_SHOULDER],
	"move_up": [KEY_UP, KEY_W, JOY_BUTTON_DPAD_UP, [JOY_AXIS_LEFT_Y, -1.0]],
	"move_down": [KEY_DOWN, KEY_S, JOY_BUTTON_DPAD_DOWN, [JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [KEY_LEFT, KEY_A, JOY_BUTTON_DPAD_LEFT, [JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [KEY_RIGHT, KEY_D, JOY_BUTTON_DPAD_RIGHT, [JOY_AXIS_LEFT_X, 1.0]],
	"menu": [KEY_TAB, KEY_ESCAPE, JOY_BUTTON_START],
}
const DEADZONE := {"move_up": 0.5, "move_down": 0.5, "move_left": 0.5, "move_right": 0.5}


func _init() -> void:
	for action: String in ACTIONS:
		var events := []  # untyped, like the original entries, to keep project.godot diffs small
		for entry: Variant in ACTIONS[action]:
			if entry is Array:
				var axis := InputEventJoypadMotion.new()
				axis.device = -1
				axis.axis = entry[0]
				axis.axis_value = entry[1]
				events.append(axis)
			elif int(entry) >= KEY_SPACE:
				var key := InputEventKey.new()
				key.device = -1  # any device
				key.physical_keycode = entry
				events.append(key)
			else:
				var pad := InputEventJoypadButton.new()
				pad.device = -1  # any controller
				pad.button_index = entry
				events.append(pad)
		ProjectSettings.set_setting("input/" + action, {"deadzone": DEADZONE.get(action, 0.2), "events": events})
	print("saved: ", ProjectSettings.save() == OK)
	quit()
