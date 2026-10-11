class_name RefWindow
extends Node2D
## The referee window (PushRef / showref): a 7 x 8 tile picture from the referee script
## (GameRules.set_pa, checkob's delayed-offside signal). Frame $40 clears it. On the rink
## it sits at tile (2, 2); on the sideways penalty screen at (13, 15), with its own frames.

const PATHS := ["res://assets/sprites/ref_idx.png", "res://assets/sprites/ref_side_idx.png"]
const FRAME_SIZE := Vector2(56, 64)
## Retail draws on a 256-wide screen; the game view is 320 wide, centred.
const SCREEN_X := 32

var game: HockeyGame
var _tex: Array[Texture2D] = [null, null]
var _frame := -1

func setup(p_game: HockeyGame) -> void:
	game = p_game
	for i in 2:
		if ResourceLoader.exists(PATHS[i]):
			_tex[i] = load(PATHS[i])
	material = game.palette_material(false)
	game.world.ref_signal.connect(_on_ref)
	visible = false

func _on_ref(frame: int) -> void:
	_frame = -1 if frame == 0x40 else frame
	visible = _frame >= 0
	queue_redraw()

func _draw() -> void:
	if _frame < 0 or game.world.intermission:
		return
	var hor := game.world.sflags & HockeyWorld.SF_HOR != 0
	var tex := _tex[1 if hor else 0]
	if tex == null:
		return
	var count := int(tex.get_width() / FRAME_SIZE.x)
	if _frame >= count:
		return
	var at := Vector2(SCREEN_X + (13 if hor else 2) * 8, (15 if hor else 2) * 8)
	draw_texture_rect_region(tex, Rect2(at, FRAME_SIZE), Rect2(Vector2(_frame * FRAME_SIZE.x, 0), FRAME_SIZE))
