class_name Highlights
extends CanvasLayer
## sub_1351C / sub_1354C (L48160-48330; spec docs/specs/playoffs_records.md §5.3): at an
## intermission, each close game of the night (gsstruct flag bit 1) is shown:
## 1. "Highlight from game:" over its ticker for $B4 frames; a press skips this and every
##    later highlight, and each is settled at once (sub_1381E: a tie goes to a random
##    side);
## 2. the game played live (HighlightGame), and again in overtime while it is tied;
## 3. its final ticker for $B4 frames.
## The intermission's own game waits; its sound stops, and $79 comes back afterwards.

signal done

const HIGHLIGHT_SCENE := preload("res://scenes/highlight.tscn")
const SHOW_FRAMES := 0xB4

var _game: HockeyGame
var _queue: Array = []
var _g: Dictionary = {}
var _phase := ""
var _frames := 0
var _skip := false
var _plane: WindowPlane
var _view: SubViewportContainer
var _clip: HighlightGame

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	offset = ScreenMode.H32_OFFSET
	_plane = WindowPlane.new()
	add_child(_plane)

## Starts the highlights of the round's flagged games; false when there are none.
func start(game: HockeyGame) -> bool:
	_game = game
	var lg := game.world.rules.league
	_queue.clear()
	for i in range(lg.shifter().x, -1, -1):
		var g: Dictionary = lg.gs[i]
		if g["flags"] & League.F_OVER == 0 and g["flags"] & League.F_HILITE:
			g["flags"] &= ~League.F_HILITE
			_queue.append(g)
	if _queue.is_empty():
		return false
	_plane.material = game.palette_material(false)
	_next()
	return true

func busy() -> bool:
	return _phase != ""

func _next() -> void:
	_plane.clear()
	if _queue.is_empty():
		_phase = ""
		_game.sfx.play_song(GameRules.SONG_INTERMISSION)
		done.emit()
		return
	_g = _queue.pop_front()
	if _skip:
		League.settle(_g, _game.world.vcount)
		_next()
		return
	_phase = "caption"
	_frames = SHOW_FRAMES
	_plane.frame(4, 18, 24, 3)
	_plane.print_at(5, 19, "Highlight from game:")
	_ticker()

## NewTicker3pt2: the game's box, visitor first.
func _ticker() -> void:
	var rules := _game.world.rules
	var lg := rules.league
	_plane.frame(3, 23, 26, 5)
	_plane.print_at(4, 24, " ".repeat(24), 1)
	var heads := ["EA Hockey Night", "Stanley Cup Qualifier", "Quarterfinal", "Stanley Cup Semifinal"]
	_plane.print_at(4, 24, heads[clampi(1 + rules.gamelevel, 0, 3) if rules.opt_play_mode else 0], 1)
	var lab := PauseMenu.period_label(_g["gsper"])
	_plane.print_at(4 + 0x17 - lab.length() / 2, 24, lab, 1)
	for k in 2:
		var t := lg.team(_g["team2" if k == 0 else "team1"])
		_plane.print_at(4, 25 + k, t.city if t else "")
		_plane.print_at(25, 25 + k, "%2d" % _g["score2" if k == 0 else "score1"])

func _pressed() -> bool:
	for k in 4:
		for b in ["start", "a", "b", "c"]:
			if Input.is_action_just_pressed("p%d_%s" % [k + 1, b]):
				return true
	return false

func _process(_delta: float) -> void:
	match _phase:
		"caption":
			_frames -= 1
			if _pressed():
				# The rest of the intermission's highlights are skipped too (sflags3 bit 3).
				_skip = true
				League.settle(_g, _game.world.vcount)
				_phase = ""
				_next()
			elif _frames <= 0:
				_play()
		"final":
			_frames -= 1
			if _frames <= 0 or _pressed():
				_phase = ""
				_next()

## The live clip, in its own viewport over the held game.
func _play() -> void:
	_phase = "live"
	_plane.clear()
	_game.sfx.stop_all()
	_clip = HIGHLIGHT_SCENE.instantiate()
	_clip.team1 = _game.world.rules.league.team(_g["team1"])
	_clip.team2 = _game.world.rules.league.team(_g["team2"])
	_clip.period = _g["gsper"] - 1
	_clip.score = [_g["score1"], _g["score2"]]
	_clip.clock = 60 + _game.world.rng.range_(120)
	_clip.seed = _game.world.rng.range_(0x10000) << 8
	_clip.finished.connect(_on_clip)
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.size = Vector2(ScreenMode.H32)
	_view.position = -offset
	var vp := SubViewport.new()
	vp.size = ScreenMode.H32
	vp.add_child(_clip)
	_view.add_child(vp)
	add_child(_view)

func _on_clip(s1: int, s2: int) -> void:
	_g["score1"] = s1
	_g["score2"] = s2
	_view.queue_free()
	_view = null
	_g["gsper"] = 4
	if s1 == s2:
		# Still tied: an overtime highlight.
		_phase = ""
		_play()
		return
	_g["gsper"] = League.GSPER_FINAL
	_phase = "final"
	_frames = SHOW_FRAMES
	_ticker()
