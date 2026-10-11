extends SceneTree
## Writes the default pad and keyboard actions into project.godot. Re-run after changing
## the tables below:
##   godot --headless --path . --script res://tools/setup_input_map.gd
## Genesis A, B, C map to the X, A, B face buttons (left to right on most pads).

const KEYS := {
	1: {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"a": KEY_Z, "b": KEY_X, "c": KEY_C, "start": KEY_ENTER},
	2: {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"a": KEY_G, "b": KEY_H, "c": KEY_J, "start": KEY_SPACE},
}
const BUTTONS := {
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT,
	"right": JOY_BUTTON_DPAD_RIGHT, "a": JOY_BUTTON_X, "b": JOY_BUTTON_A, "c": JOY_BUTTON_B,
	"start": JOY_BUTTON_START,
}
const AXES := {
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
}

func _initialize() -> void:
	for port in KEYS:
		for action in KEYS[port]:
			var events: Array[InputEvent] = []
			var key := InputEventKey.new()
			key.device = -1
			key.physical_keycode = KEYS[port][action]
			events.append(key)
			var button := InputEventJoypadButton.new()
			button.device = port - 1
			button.button_index = BUTTONS[action]
			events.append(button)
			if AXES.has(action):
				var motion := InputEventJoypadMotion.new()
				motion.device = port - 1
				motion.axis = AXES[action][0]
				motion.axis_value = AXES[action][1]
				events.append(motion)
			ProjectSettings.set_setting("input/p%d_%s" % [port, action], {"deadzone": 0.3, "events": events})
	var err := ProjectSettings.save()
	print("input map saved: ", error_string(err))
	quit(err)
