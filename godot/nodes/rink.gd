@tool
class_name Rink2D
extends Node2D
## The rink. With the extracted art (tools/extract/assets.py) it is two TileMapLayers
## built from rink/map.json: the base layer under every sprite and the priority cells
## (near end boards and glass, bench and box doors) over them, plus the home team's
## centre-ice logo. The sideways penalty screen (SetHor) swaps in the side view. Without
## the art it draws a placeholder from the listing constants. Origin is centre ice.
## Boards also get a StaticBody2D; skaters use the retail RinkBoards logic.

const MAP_PATH := "res://assets/rink/map.json"
const TILES_PATH := "res://assets/rink/tiles_idx.png"
const LOGOS_PATH := "res://assets/rink/logos_idx.png"
const SIDE_PATH := "res://assets/rink/side_idx.png"
## ChkOffsides puck line ($54).
const BLUE_LINE := 84
## Top goal line ($108).
const GOAL_LINE := 264
## Net center Y from defaultsprites2 ($10C) and its wall radius (20, 6).
const NET_Y := 268
const NET_RADIUS := Vector2(20, 6)
## z for the layers: sprites sort between them by screen Y.
const Z_BASE := -4000
const Z_LOGO := -3999
const Z_FRONT := 4000
## Priority sprites (attribute $8000) sit around this, over the front layer.
const Z_PRIORITY := 4040

@export var build_colliders: bool = true
## Team numbers for the editor preview (the game uses its own).
@export_range(0, 27, 1) var preview_home: int = 1
@export_range(0, 27, 1) var preview_away: int = 11

var game: HockeyGame
var base_layer: TileMapLayer
var front_layer: TileMapLayer
var logo: Sprite2D
var side: Sprite2D
var _tiled := false

func _ready() -> void:
	if not Engine.is_editor_hint():
		game = HockeyGame.find(self)
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
	_tiled = _build_tiles()
	if game:
		game.stepped.connect(_sync)

func _teams() -> Vector2i:
	if game:
		return game.palette_teams()
	return Vector2i(preview_home, preview_away)

func _palette(side_view: bool) -> Texture2D:
	if game:
		return game.palette_texture(side_view)
	var t := _teams()
	return PaletteBank.texture(t.x, t.y, "side" if side_view else "rink")

## The TileSet and the two layers from map.json.
func _build_tiles() -> bool:
	if not FileAccess.file_exists(MAP_PATH) or not ResourceLoader.exists(TILES_PATH):
		return false
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if not m is Dictionary:
		return false
	var tex: Texture2D = load(TILES_PATH)
	var per_row: int = m["tiles_per_row"]
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(8, 8)
	var count: int = (m["atlas_keys"] as Array).size()
	for i in count:
		src.create_tile(Vector2i(i % per_row, i / per_row))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(8, 8)
	ts.add_source(src, 0)
	var mat := PaletteBank.material(_palette(false))
	base_layer = _layer("RinkBase", ts, Z_BASE, mat)
	# High-priority cells cover the sprites only with their non-zero pixels.
	front_layer = _layer("RinkFront", ts, Z_FRONT, PaletteBank.material(_palette(false), false, true))
	var w: int = m["w"]
	var origin: Array = m["origin_px"]
	var cells: Array = m["tilemap"]
	for i in cells.size():
		var c: Array = cells[i]
		var at := Vector2i(i % w, i / w)
		var idx: int = c[0]
		var flags: int = c[1]
		var alt := 0
		if flags & 1:
			alt |= TileSetAtlasSource.TRANSFORM_FLIP_H
		if flags & 2:
			alt |= TileSetAtlasSource.TRANSFORM_FLIP_V
		var tile := Vector2i(idx % per_row, idx / per_row)
		# Plane B has one pixel per position: where a priority cell's pixel is colour 0
		# the backdrop shows ($0EE8, which is also every line's colour 0), so the cell is
		# drawn opaque under the sprites as well, and again over them with colour 0 clear.
		base_layer.set_cell(at, 0, tile, alt)
		if flags & 4:
			front_layer.set_cell(at, 0, tile, alt)
	for l in [base_layer, front_layer]:
		l.position = Vector2(-float(origin[0]), -float(origin[1]))
	# The centre-ice logo: the home team's, over rink tiles 430-453 (sub_FEA52).
	if ResourceLoader.exists(LOGOS_PATH):
		var t := _teams()
		logo = Sprite2D.new()
		logo.name = "Logo"
		logo.texture = load(LOGOS_PATH)
		logo.centered = false
		logo.region_enabled = true
		logo.region_rect = Rect2((t.x % 4) * 48, (t.x / 4) * 32, 48, 32)
		var lp: Array = m["logo_px"]
		logo.position = Vector2(float(lp[0]) - float(origin[0]), float(lp[1]) - float(origin[1]))
		logo.z_index = Z_LOGO
		logo.z_as_relative = false
		logo.material = mat
		add_child(logo)
	if ResourceLoader.exists(SIDE_PATH):
		side = Sprite2D.new()
		side.name = "SideView"
		side.texture = load(SIDE_PATH)
		side.z_index = Z_BASE
		side.z_as_relative = false
		side.material = PaletteBank.material(_palette(true))
		side.visible = false
		add_child(side)
	queue_redraw()
	return true

func _layer(n: String, ts: TileSet, z: int, mat: Material) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = n
	l.tile_set = ts
	l.z_index = z
	l.z_as_relative = false
	l.material = mat
	add_child(l)
	return l

## SetHor / ClrHor: the sideways penalty screen replaces the rink.
func _sync() -> void:
	if not _tiled:
		return
	var hor := game.world.sflags & HockeyWorld.SF_HOR != 0
	if side:
		side.visible = hor
	base_layer.visible = not hor
	front_layer.visible = not hor
	if logo:
		logo.visible = not hor

func _godot_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in RinkBoards.outline():
		out.append(Nhl94Units.rink_to_godot(p))
	return out

func _draw() -> void:
	if _tiled:
		return
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
