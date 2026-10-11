class_name RinkCamera
extends Camera2D
## Shows the rink around the retail camera: HockeyWorld.camera (Hpos/Vpos, the screen
## centre in rink coordinates), which checkwindow moves toward the puck or its carrier.
## With follow_world off (or no HockeyGame ancestor) it follows `target` instead, with a
## lead toward where the target is heading.

## Use the simulation's camera (retail scrolling).
@export var follow_world: bool = true
@export var target: Node2D
## Seconds of target velocity to look ahead (target mode).
@export_range(0.0, 1.0, 0.01) var lead_time: float = 0.25
## Largest lead offset in px (target mode).
@export_range(0.0, 120.0, 1.0) var max_lead: float = 48.0
## Board margin shown past the rink edge, px (target mode).
@export_range(0.0, 64.0, 1.0) var margin: float = 16.0

var _game: HockeyGame

func _ready() -> void:
	var n := get_parent()
	while n != null and not (n is HockeyGame):
		n = n.get_parent()
	_game = n as HockeyGame
	if _use_world():
		# checkwindow already eases and clamps (Hpos -60..60, Vpos -200..256).
		position_smoothing_enabled = false
		return
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	var half := Vector2(RinkBoards.SIDELINE, RinkBoards.END_BOARD) + Vector2(margin, margin)
	limit_left = int(-half.x)
	limit_right = int(half.x)
	limit_top = int(-half.y)
	limit_bottom = int(half.y)

func _use_world() -> bool:
	return follow_world and _game != null and _game.world != null

func _physics_process(_delta: float) -> void:
	if _use_world():
		# The sideways penalty screen does not scroll (find3d ignores Hpos/Vpos there).
		if _game.world.side_view():
			global_position = Vector2.ZERO
		else:
			global_position = Nhl94Units.rink_to_godot(Vector2(_game.world.camera))
		return
	if target == null:
		return
	var lead := Vector2.ZERO
	if target is CharacterBody2D:
		lead = ((target as CharacterBody2D).velocity * lead_time).limit_length(max_lead)
	global_position = target.global_position + lead
