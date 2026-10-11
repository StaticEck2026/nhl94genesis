extends Node2D
## Skating sandbox. P1: arrows, P2: WASD (or pads 1 and 2). The readout shows the retail
## values for P1 so they can be checked against the listing.

@onready var _p1: Skater2D = $Skater1
@onready var _readout: Label = %Readout

func _process(_delta: float) -> void:
	var v := _p1.vel
	var px_s := _p1.velocity.length()
	_readout.text = "vel %d,%d rvu  %.0f px/s\nfacing %.2f  %s%s\nstate %s" % [
		v.x, v.y, px_s,
		float(_p1.steer_state.facing_fx) / 65536.0,
		SkaterSteering.Anim.keys()[_p1.steer_state.anim],
		"  (back)" if _p1.steer_state.reverse else "",
		PlayerFSM.State.keys()[_p1.fsm.state],
	]
