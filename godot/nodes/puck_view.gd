class_name PuckView
extends Node2D
## Draws the puck and its shadow from the world's puck object. Height lifts the puck
## sprite up the screen; the shadow stays on the ice.

var game: HockeyGame

func _ready() -> void:
	var n := get_parent()
	while n != null and not (n is HockeyGame):
		n = n.get_parent()
	game = n as HockeyGame
	if game:
		game.stepped.connect(queue_redraw)
	z_index = 2

func _draw() -> void:
	if game == null:
		return
	var p := game.world.puck()
	var at := Nhl94Units.rink_to_godot(p.posf())
	var h := float(p.z())
	draw_circle(at, 2.0, Color(0, 0, 0, 0.25))
	draw_circle(at + Vector2(0, -h), 2.0, Color(0.05, 0.05, 0.05))
