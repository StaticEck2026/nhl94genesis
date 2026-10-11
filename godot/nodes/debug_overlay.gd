@tool
class_name DebugOverlay
extends Node2D
## Debug drawing over the rink, in the editor and in game. In game it reads the
## HockeyWorld; in the editor it reads the Skater2D nodes placed in the scene, so the
## grid, cones and lanes can be checked while laying out a scene.
## Toggles live in SimSettings (Overlay group) and update live from the dock.

## Net mouth half-width in px (net wall radius X from defaultsprites2 minus the post).
## Net geometry beyond the wall radius comes with checkgoal (Phase 3).
const NET_HALF_WIDTH := 12.0
const NET_Y := 268.0

var _settings: SimSettings
var _game: HockeyGame

func _ready() -> void:
	# Over the sprites and the rink's front layer.
	z_index = Rink2D.Z_FRONT + 1
	z_as_relative = false
	_settings = SimSettings.shared(self) if not Engine.is_editor_hint() else _editor_settings()
	if _settings and not _settings.changed.is_connected(queue_redraw):
		_settings.changed.connect(queue_redraw)
	var n := get_parent()
	while n != null and not (n is HockeyGame):
		n = n.get_parent()
	_game = n as HockeyGame
	if _game and not Engine.is_editor_hint():
		_game.stepped.connect(queue_redraw)

func _editor_settings() -> SimSettings:
	if ResourceLoader.exists("res://core/sim_settings.tres"):
		return load("res://core/sim_settings.tres") as SimSettings
	return SimSettings.new()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

## Skaters as (godot position, team, is_goalie, attacking_top).
func _skaters() -> Array:
	var out := []
	if _game and not Engine.is_editor_hint():
		for o in _game.world.objects:
			if o.index < 12 and o.on_ice():
				out.append([Nhl94Units.rink_to_godot(o.posf()), o.team(), o.is_goalie(), o.attacking_top()])
		return out
	for n in get_tree().get_nodes_in_group(&"skaters") if is_inside_tree() else []:
		var sk := n as Skater2D
		if sk:
			out.append([sk.position, 1 if sk.index >= 6 else 0, sk.role == SimObject.POS_GOALIE, sk.attacking_top])
	return out

func _puck_pos() -> Vector2:
	if _game and not Engine.is_editor_hint():
		return Nhl94Units.rink_to_godot(_game.world.puck().posf())
	return Vector2.ZERO

func _carrier() -> int:
	if _game and not Engine.is_editor_hint():
		return _game.world.puckc
	return -1

func _draw() -> void:
	if _settings == null:
		return
	if not Engine.is_editor_hint():
		if not _settings.show_in_game:
			return
		if _game and _game.world.sflags & HockeyWorld.SF_HOR:
			return
	if _settings.show_grid:
		_draw_grid()
	var skaters := _skaters()
	if _settings.show_goalie_cones:
		_draw_cones(skaters)
	if _settings.show_pass_lanes:
		_draw_lanes(skaters)

func _draw_grid() -> void:
	var w := float(RinkBoards.SIDELINE) * 2.0
	var h := float(RinkBoards.END_BOARD) * 2.0
	var cols := _settings.grid_columns
	var rows := _settings.grid_rows
	var c := Color(0.2, 0.7, 0.3, 0.35)
	for i in cols + 1:
		var x := -w * 0.5 + w * float(i) / float(cols)
		draw_line(Vector2(x, -h * 0.5), Vector2(x, h * 0.5), c, 1.0)
	for j in rows + 1:
		var y := -h * 0.5 + h * float(j) / float(rows)
		draw_line(Vector2(-w * 0.5, y), Vector2(w * 0.5, y), c, 1.0)

## Puck to both posts of each net, plus a line from each goalie to the puck.
func _draw_cones(skaters: Array) -> void:
	var puck := _puck_pos()
	for s in [-1.0, 1.0]:
		var net_y: float = -s * NET_Y
		var left := Vector2(-NET_HALF_WIDTH, net_y)
		var right := Vector2(NET_HALF_WIDTH, net_y)
		draw_colored_polygon(PackedVector2Array([puck, left, right]), Color(1.0, 0.6, 0.1, 0.12))
		draw_line(puck, left, Color(1.0, 0.6, 0.1, 0.6), 1.0)
		draw_line(puck, right, Color(1.0, 0.6, 0.1, 0.6), 1.0)
	for s in skaters:
		if s[2]:
			draw_line(s[0], puck, Color(1.0, 0.3, 0.1, 0.8), 1.0)

## Lanes from the carrier to each teammate; opponents near a lane get a radius ring.
func _draw_lanes(skaters: Array) -> void:
	var carrier_index := _carrier()
	var from := _puck_pos()
	var team := -1
	if carrier_index >= 0 and _game:
		team = _game.world.objects[carrier_index].team()
	elif skaters.size() > 0:
		team = 0
	if team < 0:
		return
	var r := _settings.interception_radius
	for s in skaters:
		if s[1] != team or s[2]:
			continue
		var blocked := false
		for o in skaters:
			if o[1] == team:
				continue
			var d := Geometry2D.get_closest_point_to_segment(o[0], from, s[0]).distance_to(o[0])
			if d < r:
				blocked = true
				draw_arc(o[0], r, 0.0, TAU, 16, Color(0.9, 0.1, 0.1, 0.6), 1.0)
		draw_line(from, s[0], Color(0.9, 0.1, 0.1, 0.5) if blocked else Color(0.1, 0.6, 1.0, 0.6), 1.0)
