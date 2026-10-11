class_name RinkCamera
extends Camera2D
## Follows a target with a lead toward where it is heading, clamped to the rink.
## Retail scrolling (updatescroll L51912) is not ported yet; these are tuning defaults.

@export var target: Node2D
## Seconds of target velocity to look ahead.
@export_range(0.0, 1.0, 0.01) var lead_time: float = 0.25
## Largest lead offset in px.
@export_range(0.0, 120.0, 1.0) var max_lead: float = 48.0
## Board margin shown past the rink edge, px.
@export_range(0.0, 64.0, 1.0) var margin: float = 16.0

func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	var half := Vector2(RinkBoards.SIDELINE, RinkBoards.END_BOARD) + Vector2(margin, margin)
	limit_left = int(-half.x)
	limit_right = int(half.x)
	limit_top = int(-half.y)
	limit_bottom = int(half.y)

func _physics_process(_delta: float) -> void:
	if target == null:
		return
	var lead := Vector2.ZERO
	if target is CharacterBody2D:
		lead = ((target as CharacterBody2D).velocity * lead_time).limit_length(max_lead)
	global_position = target.global_position + lead
