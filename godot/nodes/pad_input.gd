class_name PadInput
extends RefCounted
## Reads a Genesis-style 3 button pad from the InputMap. Actions are p<port>_up, _down,
## _left, _right, _a, _b, _c, _start (see project.godot). Port 0 means no pad.

## Stick deflection under this counts as centered.
const DEADZONE := 0.3

## Stick as a retail direction 0-7 (0 is screen up, clockwise) or SkaterSteering.JOY_NONE.
## The rink is vertical, so screen up is retail +Y.
static func direction(port: int) -> int:
	if port <= 0:
		return SkaterSteering.JOY_NONE
	var p := "p%d_" % port
	var v := Input.get_vector(p + "left", p + "right", p + "up", p + "down")
	return vector_to_dir(Vector2(v.x, -v.y))

## Retail-axes vector (Y up) to 0-7, or JOY_NONE inside the deadzone.
static func vector_to_dir(v: Vector2) -> int:
	if v.length() < DEADZONE:
		return SkaterSteering.JOY_NONE
	return posmod(roundi(atan2(v.x, v.y) / (TAU / 8.0)), 8)

static func pressed(port: int, button: String) -> bool:
	return port > 0 and Input.is_action_pressed("p%d_%s" % [port, button])

static func just_pressed(port: int, button: String) -> bool:
	return port > 0 and Input.is_action_just_pressed("p%d_%s" % [port, button])
