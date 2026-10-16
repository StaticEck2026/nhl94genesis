class_name ReplayView
extends CanvasLayer
## The pause menu's Instant Replay ($9FD0, L34505; spec docs/specs/ui_menus.md §14). It
## rewinds the buffer (ReplayRecorder) to its oldest record and plays it back onto the
## objects (SetRCords), with the button panel (A rewind, B slow, C play) at window (2,2)
## for $F0 frames. Controls, each tick:
## - C: play / stop; A held: rewind 4 records; B held: one record every other tick;
## - the d-pad: lock the camera on the nearest player that way (±1 octant), else pan the
##   free camera (clamped to x ±$88, y ±$126); A+B: drop the lock;
## - Start: the prompt (Start back to the game, B the pause menu, C reverse angle).
## The reverse angle is not ported (UNRESOLVED U2): C closes the prompt and goes on. On
## leaving, the live state saved on entry goes back (retail SetRCords the newest record).

signal finished(to_game: bool)

const PANEL_FRAMES := 0xF0
const PAN := 4
const CAM_X := 0x88
const CAM_Y := 0x126

var _game: HockeyGame
var _pad := 0
var _k := 0
var _playing := true
var _slow := 0
var _panel_frames := 0
var _prompt := false
var _locked := -1
var _free := false
var _cam := Vector2i.ZERO
var _saved: Dictionary = {}
var _panel: Sprite2D
var _prompt_img: Sprite2D

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	offset = ScreenMode.H32_OFFSET
	_panel = _sprite("replay_panel", Vector2(32 + 2 * 8, 2 * 8))
	_prompt_img = _sprite("replay_prompt", Vector2(32 + 2 * 8, 0))
	visible = false

func _sprite(name: String, at: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	var f := "res://assets/ui/menus/%s_idx.png" % name
	if ResourceLoader.exists(f):
		s.texture = load(f)
	s.position = at
	add_child(s)
	return s

func is_open() -> bool:
	return visible

func open(game: HockeyGame, pad: int) -> void:
	_game = game
	_pad = pad
	var rp := game.world.replay
	if rp.count() == 0:
		finished.emit(false)
		return
	var mat := game.palette_material(false)
	_panel.material = mat
	_prompt_img.material = mat
	_saved = rp.snapshot(0)
	_k = 0
	_playing = true
	_slow = 0
	_prompt = false
	_locked = -1
	_free = false
	_panel_frames = PANEL_FRAMES
	_panel.visible = true
	_prompt_img.visible = false
	visible = true
	_show()

func _close(to_game: bool) -> void:
	visible = false
	_game.world.replay.apply(_saved)
	_game.world.marks[3] = HockeyWorld.MARK_HIDDEN
	_game.stepped.emit()
	finished.emit(to_game)

## SetRCords for record k, the camera as the viewer has it, and a redraw of the paused
## game's views.
func _show() -> void:
	var w := _game.world
	var rp := w.replay
	var r := rp.at(_k)
	rp.apply(r)
	if _locked >= 0:
		var o := w.objects[_locked]
		_cam = Vector2i(clampi(o.x(), -CAM_X, CAM_X), clampi(o.y(), -CAM_Y, CAM_Y))
		w.marks[3] = _locked
	elif not _free:
		_cam = r.get("camera", w.camera)
	w.camera = _cam
	_game.stepped.emit()

func _process(_delta: float) -> void:
	if not visible:
		return
	var p := "p%d_" % (_pad + 1)
	if _panel_frames > 0:
		_panel_frames -= 1
		if _panel_frames == 0:
			_panel.visible = false
	if _prompt:
		if Input.is_action_just_pressed(p + "start"):
			_close(true)
		elif Input.is_action_just_pressed(p + "b"):
			_close(false)
		elif Input.is_action_just_pressed(p + "c"):
			_prompt = false
			_prompt_img.visible = false
		return
	if Input.is_action_just_pressed(p + "start"):
		_prompt = true
		_prompt_img.visible = true
		return
	var n := _game.world.replay.count()
	var a := Input.is_action_pressed(p + "a")
	var b := Input.is_action_pressed(p + "b")
	if a and b:
		_locked = -1
		_game.world.marks[3] = HockeyWorld.MARK_HIDDEN
	elif a:
		_k = maxi(_k - 4, 0)
	elif b:
		_slow ^= 1
		if _slow:
			_k = mini(_k + 1, n - 1)
	elif Input.is_action_just_pressed(p + "c"):
		_playing = not _playing
	elif _playing:
		_k = mini(_k + 1, n - 1)
	var dir := Vector2i.ZERO
	if Input.is_action_pressed(p + "up"):
		dir.y = 1
	elif Input.is_action_pressed(p + "down"):
		dir.y = -1
	if Input.is_action_pressed(p + "left"):
		dir.x = -1
	elif Input.is_action_pressed(p + "right"):
		dir.x = 1
	if dir != Vector2i.ZERO:
		_steer(dir, p)
	var r := _game.world.replay.at(_k)
	_show()
	if _playing and not a and not b and int(r.get("sfx", -1)) >= 0:
		_game.sfx.play(int(r["sfx"]))

## A new d-pad press locks onto the nearest player within an octant of it; holding pans
## the free camera when nobody is there.
func _steer(dir: Vector2i, p: String) -> void:
	var w := _game.world
	var pressed := false
	for d in ["up", "down", "left", "right"]:
		if Input.is_action_just_pressed(p + d):
			pressed = true
	if pressed:
		var from := Vector2(w.objects[_locked].pos()) if _locked >= 0 else Vector2(_cam)
		var want := Vector2(dir).normalized()
		var best := -1
		var best_d := INF
		for i in 12:
			var o := w.objects[i]
			if o.frame == 0 or i == _locked:
				continue
			var v := Vector2(o.pos()) - from
			var d2 := v.length_squared()
			if d2 < 4 or d2 > 0x100 * 0x100 or v.normalized().dot(want) < cos(PI / 4 + 0.01):
				continue
			if d2 < best_d:
				best_d = d2
				best = i
		if best >= 0:
			_locked = best
			_free = false
			return
	if _locked < 0:
		_free = true
		_cam = Vector2i(clampi(_cam.x + dir.x * PAN, -CAM_X, CAM_X), clampi(_cam.y + dir.y * PAN, -CAM_Y, CAM_Y))
