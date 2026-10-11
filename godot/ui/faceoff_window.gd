class_name FaceoffWindow
extends Node2D
## The face-off close-up (checkfo, L52017): the window (FaceOffMap) and the two centres
## and the referee from fofdata, at the retail screen spot (fodropx / fodropy). Pressing
## at the right moment is timed against the referee's hand.

const WINDOW_PATH := "res://assets/sprites/faceoff_window_idx.png"
## Retail draws on a 256-wide screen; the game view is 320 wide, centred.
const SCREEN_X := 32

var game: HockeyGame
var _window: Texture2D
var _home_mat: ShaderMaterial
var _away_mat: ShaderMaterial
var _parts: Array[Node2D] = []

func setup(p_game: HockeyGame) -> void:
	game = p_game
	if ResourceLoader.exists(WINDOW_PATH):
		_window = load(WINDOW_PATH)
	material = game.palette_material(false)
	# One child per close-up sprite so each can take its own palette swap.
	for i in 3:
		var n := Node2D.new()
		n.draw.connect(_draw_part.bind(n, i))
		add_child(n)
		_parts.append(n)
	game.stepped.connect(_sync)

func _sync() -> void:
	var fo := game.world.faceoff
	visible = fo.window_open and SpriteAtlas.available("faceoff") and not game.world.intermission
	if not visible:
		return
	queue_redraw()
	for i in 3:
		var away := fo.fof_attr[i] & 0x2000 != 0
		_parts[i].material = game.palette_material(away)
		_parts[i].queue_redraw()

func _draw() -> void:
	if _window:
		var fo := game.world.faceoff
		var at := Vector2(SCREEN_X + ((fo.fodrop.x - 0x2E) >> 3) * 8, ((fo.fodrop.y - 0x44) >> 3) * 8)
		draw_texture(_window, at)

func _draw_part(n: Node2D, i: int) -> void:
	var fo := game.world.faceoff
	var at := Vector2(SCREEN_X + fo.fodrop.x, fo.fodrop.y)
	SpriteAtlas.draw_frame(n, fo.fof_frame[i], at, fo.fof_attr[i] & 0x1800, "faceoff")
