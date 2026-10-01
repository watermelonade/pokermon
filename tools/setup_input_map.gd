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

const ACTIONS := {
	"signal_1": [KEY_1, JOY_BUTTON_PADDLE1],
	"signal_2": [KEY_2, JOY_BUTTON_PADDLE2],
	"signal_3": [KEY_3, JOY_BUTTON_PADDLE3],
	"signal_4": [KEY_4, JOY_BUTTON_PADDLE4],
	"raise_more": [KEY_E, JOY_BUTTON_RIGHT_SHOULDER],
	"raise_less": [KEY_Q, JOY_BUTTON_LEFT_SHOULDER],
}


func _init() -> void:
	for action: String in ACTIONS:
		var key := InputEventKey.new()
		key.device = -1  # any device
		key.physical_keycode = ACTIONS[action][0]
		var pad := InputEventJoypadButton.new()
		pad.device = -1  # any controller
		pad.button_index = ACTIONS[action][1]
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": [key, pad]})
	print("saved: ", ProjectSettings.save() == OK)
	quit()
