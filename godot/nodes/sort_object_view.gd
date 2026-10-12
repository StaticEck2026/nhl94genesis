class_name SortObjectView
extends Node2D
## Draws one sort object (nets, puck, shadow; Skater2D does the players) from the sprite
## atlas at its find3d position. Hidden while its height is negative (addframe) or its
## frame is 0. Retail draws smaller rink Y in front; z_index follows screen Y.

@export_range(0, 15, 1) var index: int = HockeyWorld.PUCK

var game: HockeyGame
var obj: SimObject

func _ready() -> void:
	game = HockeyGame.find(self)
	if game == null:
		return
	obj = game.world.objects[index]
	material = game.palette_material(false)
	game.stepped.connect(_sync)

func _sync() -> void:
	var on := obj.z() >= 0 and obj.frame != 0 and SpriteAtlas.available() and not game.world.intermission
	visible = on
	if not on:
		return
	position = project_ground(game.world, obj)
	z_index = z_for(obj, position)
	queue_redraw()

func _draw() -> void:
	if obj == null:
		return
	SpriteAtlas.draw_frame(self, obj.frame, Vector2(0, -lift(obj)), obj.attribute)

## Sprites sort by screen Y. A sprite with the priority bit (attribute $8000: the puck
## leaving over the near glass, the bottom goal light) draws over the rink's
## high-priority cells; the others go under them.
static func z_for(o: SimObject, at: Vector2) -> int:
	if o.attribute & SimObject.ATTR_PRIORITY:
		return Rink2D.Z_PRIORITY + clampi(roundi(at.y) >> 3, -40, 40)
	return clampi(roundi(at.y), -3000, 3000)

## find3d without the height: where the object stands, in Godot axes (Y down). The
## sideways penalty view swaps the axes: (x, y) -> (-y, $C5 - x).
static func project_ground(w: HockeyWorld, o: SimObject) -> Vector2:
	if w.side_view():
		return Vector2(-o.y(), 0xC5 - o.x())
	return Vector2(o.x(), -o.y())

## find3d's height: the sprite rises 1.5 px per unit of z.
static func lift(o: SimObject) -> float:
	var z := maxi(o.z(), 0)
	return float(z + (z >> 1))
