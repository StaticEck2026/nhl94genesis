class_name PuckPhysics
extends RefCounted
## Puck motion. Port in progress; see GODOT_TODO Phase 3.
##
## Done: carrier follow from pucknorm (L42526).

var settings: SimSettings

func _init(p_settings: SimSettings = null) -> void:
	settings = p_settings if p_settings != null else SimSettings.new()

## pucknorm: the puck closes a fraction of the gap to the carrier hot spot each loop
## (retail asr #2 = 1/4) and takes the carrier velocity. Positions are px, velocity any unit.
## Returns [new_position, new_velocity].
func follow_carrier(puck_pos: Vector2, hot_spot: Vector2, carrier_vel: Vector2) -> Array:
	var pos := puck_pos + (hot_spot - puck_pos) * settings.carrier_bungee
	return [pos, carrier_vel]

## Loose puck drag per loop. Retail uses the pfdoff shift (>> 9) for a normal puck.
func loose_drag(vel: Vector2i) -> Vector2i:
	if not settings.enable_puck_friction:
		return vel
	var shift := settings.glide_drag_shift
	return Vector2i(SkaterMotion.drag_axis(vel.x, shift), SkaterMotion.drag_axis(vel.y, shift))
