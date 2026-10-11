extends CanvasLayer
## Scoreboard (teams, score, period, clock, power play), the referee's call, and the
## intermission / final banner.

## How long a referee call stays up, in frames.
const CALL_FRAMES := 150

@onready var _label: Label = %Scoreboard
var game: HockeyGame
var _call: Label
var _banner: Label
var _call_frames := 0

func bind(p_game: HockeyGame) -> void:
	game = p_game
	game.stepped.connect(_refresh)
	_call = _make_label(Vector2(4, 16), HORIZONTAL_ALIGNMENT_LEFT)
	_banner = _make_label(Vector2(0, 100), HORIZONTAL_ALIGNMENT_CENTER)
	_banner.size = Vector2(320, 24)
	game.world.rules.ref_message.connect(_on_call)
	game.world.rules.penalty_assessed.connect(_on_penalty)
	game.world.rules.intermission.connect(_on_intermission)
	game.world.rules.game_over.connect(_on_game_over)
	game.world.rules.period_started.connect(func(_g: int) -> void: _banner.text = "")
	var rw := RefWindow.new()
	rw.name = "RefWindow"
	add_child(rw)
	rw.setup(game)
	var fw := FaceoffWindow.new()
	fw.name = "FaceoffWindow"
	add_child(fw)
	fw.setup(game)

func _make_label(at: Vector2, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = at
	l.size = Vector2(312, 12)
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", Color(1, 1, 0.6))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_font_size_override("font_size", 8)
	add_child(l)
	return l

func _team_abbr(team: int) -> String:
	var st := game.world.stats[team]
	if st.data:
		return st.data.abbreviation
	return "HOME" if team == 0 else "AWAY"

func _refresh() -> void:
	var w := game.world
	var secs := w.clock_seconds()
	var period := "OT" if w.gsp >= 3 else "P%d" % (w.gsp + 1)
	var pp := ""
	if w.sflags2 & HockeyWorld.SF2_PWRPLAY:
		pp = "  PP %s" % _team_abbr(1 if w.sflags2 & HockeyWorld.SF2_PWRTM else 0)
	_label.text = "%s %d  %s %d   %s  %d:%02d%s" % [_team_abbr(0), w.score(0), _team_abbr(1),
		w.score(1), period, secs / 60, secs % 60, pp]
	if _call_frames > 0:
		_call_frames -= 1
		if _call_frames == 0:
			_call.text = ""

func _on_call(text: String) -> void:
	if text == "":
		return
	_call.text = text
	_call_frames = CALL_FRAMES

func _on_penalty(team: int, pnum: int, id: int, minutes: int) -> void:
	var st := game.world.stats[team]
	var who := "#%d" % pnum
	if st.data and st.data.player(pnum):
		who = st.data.player(pnum).full_name
	_call.text = "%s  %s  %s  %d min" % [_team_abbr(team), who, GameRules.entry(id)[2], minutes]
	_call_frames = CALL_FRAMES * 2

func _on_intermission(gsp: int) -> void:
	if gsp == 0 or gsp >= 4:
		return
	var names := ["", "End of the 1st", "End of the 2nd", "End of regulation"]
	_banner.text = "%s  -  Start to continue" % names[mini(gsp, 3)]

func _on_game_over() -> void:
	var w := game.world
	_banner.text = "Final  %s %d  %s %d" % [_team_abbr(0), w.score(0), _team_abbr(1), w.score(1)]
