@tool
class_name Skater2D
extends CharacterBody2D
## View of one skater in the HockeyWorld. Position and velocity come from the world each
## frame; this node only draws (and later animates) what the simulation decided.
## In the editor it draws its placement so scenes can be laid out.

## Sort object index 0-11 (0-5 home, 6-11 away).
@export_range(0, 11, 1) var index: int = 0
@export var player: PlayerData
## Position role when placed: 0 goalie, 1 LD, 2 RD, 3 LW, 4 C, 5 RW.
@export_range(0, 5, 1) var role: int = SimObject.POS_C
@export var attacking_top: bool = true

var game: HockeyGame
var obj: SimObject

func _ready() -> void:
	add_to_group(&"skaters")
	if Engine.is_editor_hint():
		return
	game = _find_game()
	if game == null:
		push_error("Skater2D needs a HockeyGame ancestor")
		return
	obj = game.world.objects[index]
	if game.auto_place:
		var at := Nhl94Units.rink_to_godot(position)
		game.world.place(index, Vector2i(roundi(at.x), roundi(at.y)), role, index >= 6, attacking_top)
		if player:
			obj.load_player(player)
		else:
			obj.default_ratings()
	game.stepped.connect(_sync)

func _find_game() -> HockeyGame:
	var n := get_parent()
	while n != null and not (n is HockeyGame):
		n = n.get_parent()
	return n as HockeyGame

func _sync() -> void:
	# Sprite frame 0 draws nothing (off the ice, in the box, parked).
	visible = obj.frame != 0
	attacking_top = obj.attacking_top()
	position = Nhl94Units.rink_to_godot(obj.posf())
	velocity = Nhl94Units.rink_to_godot(Vector2(obj.vel)) * Nhl94Units.VEL_STEP * Nhl94Units.RETAIL_HZ / Nhl94Units.FIXED_ONE
	queue_redraw()

func _draw() -> void:
	var away := obj.away() if obj else index >= 6
	var color := Color(0.2, 0.35, 0.9) if away else Color(0.85, 0.2, 0.2)
	draw_circle(Vector2.ZERO, 5.0, color)
	var angle := obj.facing_angle() if obj else (0.0 if attacking_top else PI)
	draw_line(Vector2.ZERO, Vector2.UP.rotated(angle) * 10.0, Color(0.1, 0.1, 0.15), 1.0)
	if obj:
		draw_line(Vector2.ZERO, velocity * 0.1, Color(1, 1, 0, 0.8), 1.0)
