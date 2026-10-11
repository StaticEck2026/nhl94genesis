@tool
class_name Rink2D
extends Node2D
## Placeholder rink drawn from listing constants until the tile pass (Rinktiles L305524,
## icerinkmap L723306) produces PNGs for a TileMapLayer. Origin is center ice.
## Boards also get a StaticBody2D so other physics bodies can stand on them; skaters use
## the retail RinkBoards logic.

## ChkOffsides puck line ($54).
const BLUE_LINE := 84
## Top goal line ($108).
const GOAL_LINE := 264
## Net center Y from defaultsprites2 ($10C) and its wall radius (20, 6).
const NET_Y := 268
const NET_RADIUS := Vector2(20, 6)

@export var build_colliders: bool = true

func _ready() -> void:
	if build_colliders and not Engine.is_editor_hint():
		var body := StaticBody2D.new()
		body.name = "Boards"
		var shape := CollisionPolygon2D.new()
		shape.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		var pts := _godot_outline()
		pts.append(pts[0])
		shape.polygon = pts
		body.add_child(shape)
		add_child(body)

func _godot_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in RinkBoards.outline():
		out.append(Nhl94Units.rink_to_godot(p))
	return out

func _draw() -> void:
	var pts := _godot_outline()
	draw_colored_polygon(pts, Color(0.92, 0.95, 1.0))
	var x := float(RinkBoards.SIDELINE)
	draw_line(Vector2(-x, 0), Vector2(x, 0), Color(0.85, 0.1, 0.1), 2.0)
	for s in [-1.0, 1.0]:
		draw_line(Vector2(-x, s * BLUE_LINE), Vector2(x, s * BLUE_LINE), Color(0.1, 0.2, 0.85), 3.0)
		draw_line(Vector2(-x + 20, s * GOAL_LINE), Vector2(x - 20, s * GOAL_LINE), Color(0.85, 0.1, 0.1), 1.0)
		draw_rect(Rect2(Vector2(-NET_RADIUS.x, s * NET_Y - NET_RADIUS.y), NET_RADIUS * 2.0), Color(0.3, 0.3, 0.3), false, 1.0)
	draw_circle(Vector2.ZERO, 22.0, Color(0.1, 0.2, 0.85), false, 1.0)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.55, 0.4, 0.2), 2.0)
