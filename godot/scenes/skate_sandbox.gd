extends HockeyGame
## Skating sandbox. P1: arrows, P2: WASD (or pads 1 and 2). The readout shows the retail
## values for P1 so they can be checked against the listing.

@onready var _p1: Skater2D = $Skater1
@onready var _readout: Label = %Readout

func _ready() -> void:
	pad_ports = {_p1.index: 1, ($Skater2 as Skater2D).index: 2}
	add_object_views()

func _process(_delta: float) -> void:
	var o := _p1.obj
	if o == null:
		return
	_readout.text = "vel %d,%d rvu  %.0f px/s\nfacing %.2f  %s%s" % [
		o.vel.x, o.vel.y, _p1.velocity.length(),
		float(o.facing_fx) / 65536.0, Spa.name_of(o.spa),
		"  (back)" if o.reverse() else "",
	]
