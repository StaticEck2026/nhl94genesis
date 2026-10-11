extends CanvasLayer
## Scoreboard (teams, score, period, clock, power play), the referee's call, the
## intermission / final banner, the penalty shot / shootout intro box, the injury message
## (loc_1871C) and the fight patch's banner. Retail draws these boxes on the 256-wide
## screen; here tile column c sits at x = 32 + 8c.

## How long a referee call stays up, in frames.
const CALL_FRAMES := 150

@onready var _label: Label = %Scoreboard
var game: HockeyGame
var _call: Label
var _banner: Label
var _call_frames := 0
var _intro: PanelContainer
var _intro_text: Label
var _fight_box: PanelContainer
var _fight_text: Label
var _injury_box: PanelContainer
var _injury_text: Label

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
	game.world.shootout.intro.connect(_on_intro)
	_make_intro()
	var fb := _make_box("FightBanner")
	_fight_box = fb[0]
	_fight_text = fb[1]
	var ib := _make_box("Injury")
	_injury_box = ib[0]
	_injury_text = ib[1]
	game.world.fight.banner.connect(_on_fight_banner)
	game.world.fight.banner_cleared.connect(func() -> void: _fight_box.visible = false)
	game.world.injury_message.connect(_on_injury)
	game.world.rules.horizontal_changed.connect(_on_horizontal)
	game.world.faceoff.faceoff_dropped.connect(func(_h: bool) -> void: _hide_overlays())
	var rw := RefWindow.new()
	rw.name = "RefWindow"
	add_child(rw)
	rw.setup(game)
	var lm := LineMenu.new()
	lm.name = "LineMenu"
	add_child(lm)
	lm.setup(game)
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

## The framed intro box (sub_187B8 / loc_FC320), centred on the screen.
func _make_intro() -> void:
	_intro = PanelContainer.new()
	_intro.name = "Intro"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0.25, 0.9)
	sb.border_color = Color(1, 1, 1)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	_intro.add_theme_stylebox_override("panel", sb)
	_intro_text = Label.new()
	_intro_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_text.add_theme_font_size_override("font_size", 8)
	_intro_text.add_theme_color_override("font_color", Color(1, 1, 1))
	_intro.add_child(_intro_text)
	_intro.visible = false
	add_child(_intro)

## A Framer box with centred lines (overlay map, high priority).
func _make_box(n: String) -> Array:
	var box := PanelContainer.new()
	box.name = n
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.border_color = Color(1, 1, 1)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	box.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	box.add_child(l)
	box.visible = false
	add_child(box)
	return [box, l]

## The fight banner: a box over tile rows 1-5, centred on column 15/16.
func _on_fight_banner(lines: PackedStringArray) -> void:
	_fight_text.text = "\n".join(lines)
	# box (sub_18A56) blanks the injury box's area first.
	_injury_box.visible = false
	_fight_box.visible = true
	_fight_box.reset_size()
	_fight_box.position = Vector2(160 - _fight_box.get_combined_minimum_size().x * 0.5, 8)

## loc_1871C: "Injury to:", the player, "Out for game" / "Out for period"; while the
## puck's fight bit is set "the game" overprints the end: "Out for the game". Framer 18x5
## at tile (11, 3).
func _on_injury() -> void:
	var w := game.world
	var team := 1 if w.temp_pl_offset & 0x8000 else 0
	var slot := w.temp_pl_offset & 0xFF
	var who := "#%d" % slot
	var d := w.stats[team].data
	if d and d.player(slot):
		who = "%d %s" % [d.player(slot).jersey_number, d.player(slot).full_name]
	var out := "Out for game" if w.injury_game else "Out for period"
	if w.puck().flags2 & SimObject.PF2_FIGHT:
		out = "Out for the game"
	_injury_text.text = "Injury to:\n%s\n%s" % [who, out]
	_injury_box.visible = true
	_injury_box.reset_size()
	_injury_box.position = Vector2(32 + 11 * 8, 3 * 8)

## The sideways penalty screen rebuilds the overlay map.
func _on_horizontal(on: bool) -> void:
	if on:
		_hide_overlays()

func _hide_overlays() -> void:
	_fight_box.visible = false
	_injury_box.visible = false

func _on_intro(lines: PackedStringArray) -> void:
	_intro_text.text = "\n".join(lines)
	_intro.visible = true
	_intro.reset_size()
	_intro.position = (Vector2(320, 224) - _intro.get_combined_minimum_size()) * 0.5 - Vector2(0, 24)

func _team_abbr(team: int) -> String:
	var st := game.world.stats[team]
	if st.data:
		return st.data.abbreviation
	return "HOME" if team == 0 else "AWAY"

func _refresh() -> void:
	var w := game.world
	var secs := w.clock_seconds()
	var period := "OT" if w.gsp >= 3 else "P%d" % (w.gsp + 1)
	if w.f_c2fa & ShootoutLogic.C2FA_ATTEMPT_CLOCK:
		# showclock: the attempt clock, with a blank period label (PrintScores1).
		secs = w.shootout.ps_clock
		period = "SO" if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT else "  "
	if _intro.visible and w.f_c2fa & HockeyWorld.C2FA_PS_INTRO == 0:
		_intro.visible = false
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
	_intro.visible = false
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		_banner.text = "%s  %s %d  %s %d" % [w.shootout.winner_text(), _team_abbr(0),
			w.shootout_goals[0], _team_abbr(1), w.shootout_goals[1]]
		return
	_banner.text = "Final  %s %d  %s %d" % [_team_abbr(0), w.score(0), _team_abbr(1), w.score(1)]
