extends Node2D
## Retail's Game Setup (GameSetUp L960187; spec docs/specs/ui_frontend.md §2): one H40
## menu over the ice, with the two teams' plates and logos above it.
## - Nine option rows at $FFD048 (Sim.options). Six of them show at a time, with the
##   `{` `}` arrows and the 23 x 3 cursor box. Up / down move, skipping the rows that do
##   not apply; left / right cycle the value with wrap-around. Every pad drives it, with
##   auto-repeat (16 frames, then every 5).
## - Shootout forces User Records, Penalties and Line Changes off, and puts them back on
##   leaving. Players = Demo forces User Records off and Auto goalies.
## - After 180 idle frames the player showcase replaces the logos with photo cards.
##   After six idle minutes a demo game starts.
## - Start: Matchups, or the game straight away in Shootout.
## Art and tables: tools/extract/ui_frontend.py (assets/ui/frontend).
## Port-only: B opens a box with the edition (retail '94 or the fight patch) and the
## patch's Fighting option. Retail does nothing with B.
## Playoffs (spec docs/specs/playoffs_records.md §2): New Playoffs draws a bracket for
## Team 1 (NewPO) on entering the menu and on every Play Mode or Team 1 change; Team 2
## is then the first opponent. Continue Playoffs (only with a saved playoff) decodes the
## save RAM and skips the team rows. The Players row offers Two - Head to Head,
## Two - Teammates and One.

const DIR := "res://assets/ui/frontend/"
const MENUS := "res://assets/ui/menus/"
const GAME_SCENE := "res://scenes/game.tscn"
const MATCHUPS_SCENE := "res://ui/matchups.tscn"
const PLAYOFF_SCENE := "res://ui/playoff_screen.tscn"

## The rows (d7 / 2).
enum { PLAY_MODE, PLAYERS, TEAM1, TEAM2, PER_LENGTH, GOALIES, USER_RECORDS, PENALTIES, LINES }
const ROWS := 9
const VISIBLE := 6
const TOP_MAX := 3
const MODE_REGULAR := 0
const MODE_CONTINUE := 1
const MODE_NEW := 2
const MODE_NEW7 := 3
const MODE_SHOOTOUT := 4
const NOP_DEMO := 0
const NOP_TEAMMATES := 3
## Value counts (unk_F7930, the 4 Way Play list: pads 3 and 4 always exist in the port).
const COUNTS := [5, 7, 28, 28, 3, 2, 2, 3, 3]
## GameSetUp_2: no press for $5460 frames starts the demo.
const DEMO_IDLE := 0x5460
## The showcase runs for $E10 frames after the last press ($5460 - $4650).
const SHOWCASE_WINDOW := 0x5460 - 0x4650
const SHOWCASE_DELAY := 0xB4
const CARD_FRAMES := 0xAA
const CARD_FRAMES_FAST := 0x53
const REPEAT_FIRST := 16
const REPEAT_NEXT := 5

var _fe: Dictionary = {}
var _logo_pal: Array = []
var _photo_pal: Array = []
var _photos: Dictionary = {}
var _teams: Array[TeamData] = []
var _bg: Sprite2D
var _a: WindowPlane
var _pal_img: Image
var _pal_tex: ImageTexture
var _labels: Array = []
var _values: Dictionary = {}

var _row := 0
var _top := 0
var _idle := 0
var _repeat := {}
## The showcase (word_FFD42E bit 0 card up, bit 1 side; word_FFD440 delay; word_FFD43E
## player; word_FFD43C card interval).
var _card_up := false
var _card_home := false
var _card_delay := SHOWCASE_DELAY
var _card_timer := 0
var _card_player := 0
var _card_frames := CARD_FRAMES
## The port's options box (B).
var _port_box := false
var _port_row := 0

func _ready() -> void:
	ScreenMode.restore(get_tree())
	var f := DIR + "frontend.json"
	if FileAccess.file_exists(f):
		_fe = JSON.parse_string(FileAccess.get_file_as_string(f))
	var pj := MENUS + "palettes.json"
	if FileAccess.file_exists(pj):
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pj))
		_logo_pal = p.get("team_logos", [])
		_photo_pal = p.get("photo", [])
	var ph := MENUS + "photos.json"
	if FileAccess.file_exists(ph):
		_photos = JSON.parse_string(FileAccess.get_file_as_string(ph))
	if _fe.is_empty():
		return
	var chars: Dictionary = _fe["fonts"]["setup"]["chars"]
	WindowPlane.register("setup_font", DIR + "font_setup_idx.png", chars)
	for k in ["setup_header", "setup_panel", "setup_framer", "logo_frame_home", "logo_frame_visitor",
			"team_plates_home", "team_plates_visitor"]:
		WindowPlane.register(k, DIR + k + "_idx.png")
	WindowPlane.register("team_logos", MENUS + "team_logos_idx.png")
	WindowPlane.register("photos", MENUS + "photos_idx.png")
	var setup: Dictionary = _fe["setup"]
	for r in setup["rows"]:
		_labels.append(String(r["label"]))
	_values = setup["value_lists"]
	_pal_img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	_bg = Sprite2D.new()
	_bg.centered = false
	_bg.texture = load(DIR + "setup_bg_idx.png")
	_bg.material = PaletteBank.material(_pal_tex)
	add_child(_bg)
	_a = WindowPlane.new()
	_a.origin = Vector2.ZERO
	_a.material = PaletteBank.material(_pal_tex, false, true)
	add_child(_a)
	# GameSetUp L960190-960209: back from a demo the teams are re-rolled.
	_load_teams()
	if Sim.demo_played:
		Sim.demo_played = false
		Sim.options[TEAM1] = randi() % 28
		Sim.options[TEAM2] = randi() % 28
	# L960210-960221: a new bracket on every visit, or the saved one decoded.
	Sim.league.set_teams(MatchConfig.available_teams(Sim.match.edition))
	if _new_playoffs():
		_new_po()
	elif _opt(PLAY_MODE) == MODE_CONTINUE and not _continue():
		Sim.options[PLAY_MODE] = MODE_REGULAR
	_clamp_all()
	_redraw()
	if Sim.menu_sfx and not Sim.menu_sfx.get("_music").playing:
		Sim.menu_sfx.play_song(0x78)

func _load_teams() -> void:
	_teams.clear()
	_teams.resize(28)
	for t in MatchConfig.available_teams(Sim.match.edition):
		if t.team_index >= 0 and t.team_index < 28:
			_teams[t.team_index] = t

# --- values ------------------------------------------------------------------------------

func _opt(r: int) -> int:
	return Sim.options[r]

func _shootout() -> bool:
	return _opt(PLAY_MODE) == MODE_SHOOTOUT

func _demo_players() -> bool:
	return _opt(PLAYERS) == NOP_DEMO

func _playoffs() -> bool:
	return _opt(PLAY_MODE) >= MODE_CONTINUE and _opt(PLAY_MODE) <= MODE_NEW7

func _new_playoffs() -> bool:
	return _opt(PLAY_MODE) == MODE_NEW or _opt(PLAY_MODE) == MODE_NEW7

## NewPO for Team 1, then FigureJoy's opponent in Team 2.
func _new_po() -> void:
	Sim.league.new_po(Sim.menu_rng, _opt(TEAM1), _opt(PLAY_MODE))
	_playoff_teams()

## sub_17CA0: the saved playoff, its user's team and opponent, and OptNOP = 7 - pojoy.
func _continue() -> bool:
	if not Sim.league.continue_from(Sim.sram.playoff_state()):
		return false
	Sim.options[PLAYERS] = 7 - Sim.league.pojoy
	_playoff_teams()
	return true

func _playoff_teams() -> void:
	var fj := Sim.league.figure_joy()
	Sim.options[TEAM1] = Sim.league.user_team()
	if not fj.is_empty():
		Sim.options[TEAM2] = fj["opponent"]

## A saved playoff to continue (sub_17CA0 on a copy).
func _can_continue() -> bool:
	return League.new().continue_from(Sim.sram.playoff_state())

## The plates' and logos' teams: HomeTeam and VisTeam (FigureJoy's in the playoffs).
func _home_team() -> int:
	if _playoffs():
		var fj := Sim.league.figure_joy()
		if not fj.is_empty():
			return fj["home"]
	return _opt(TEAM1)

func _vis_team() -> int:
	if _playoffs():
		var fj := Sim.league.figure_joy()
		if not fj.is_empty():
			return fj["visitor"]
	return _opt(TEAM2)

## The value range d5 <= v < d4 for a row (GameSetUp_3, sub_F7B0A).
func _range(r: int) -> Vector2i:
	match r:
		PLAYERS:
			if _playoffs():
				return Vector2i(5, 8)
			return Vector2i(0, 5) if _shootout() else Vector2i(0, COUNTS[PLAYERS])
		TEAM1:
			return Vector2i(0, 26) if _new_playoffs() else Vector2i(0, 28)
		_:
			return Vector2i(0, COUNTS[r])

## Values the cursor jumps over: Two - Teammates in Shootout (L960871); the playoff modes,
## which the port does not have yet.
func _skip_value(r: int, v: int) -> bool:
	if r == PLAY_MODE:
		return v == MODE_CONTINUE and not _can_continue()
	if r == PLAYERS and _shootout():
		return v == NOP_TEAMMATES
	return false

## GameSetUp_3: step a value by d (wrapping), or clamp it into range with d = 0.
func _change(r: int, d: int) -> void:
	var rg := _range(r)
	var v := _opt(r)
	if r == PLAY_MODE and d != 0:
		var was := _shootout()
		v = _wrap(v + d, rg)
		while _skip_value(r, v):
			v = _wrap(v + d, rg)
		Sim.options[r] = v
		var now := _shootout()
		if now and not was:
			Sim.shootout_saved = PackedInt32Array([_opt(USER_RECORDS), _opt(PENALTIES), _opt(LINES)])
		elif was and not now and Sim.shootout_saved.size() == 3:
			Sim.options[USER_RECORDS] = Sim.shootout_saved[0]
			Sim.options[PENALTIES] = Sim.shootout_saved[1]
			Sim.options[LINES] = Sim.shootout_saved[2]
		if v == MODE_CONTINUE:
			_continue()
		elif _new_playoffs():
			_change(TEAM1, 0)
			_new_po()
		return
	# sub_F7B0A: out of range at either end wraps to the other.
	v = _wrap(v + d, rg)
	while _skip_value(r, v):
		v = _wrap(v + (d if d != 0 else 1), rg)
	Sim.options[r] = v
	if r == TEAM1 and d != 0 and _new_playoffs():
		_new_po()

static func _wrap(v: int, rg: Vector2i) -> int:
	if v < rg.x:
		return rg.y - 1
	if v >= rg.y:
		return rg.x
	return v

## sub_F78A2's forced values, then every row clamped (sub_F7B20).
func _clamp_all() -> void:
	if _shootout():
		Sim.options[USER_RECORDS] = 1
		Sim.options[LINES] = 1
		Sim.options[PENALTIES] = 0
	for r in ROWS:
		_change(r, 0)
	if _demo_players():
		Sim.options[USER_RECORDS] = 1
		Sim.options[GOALIES] = 1

func _value_text(r: int) -> String:
	var v := _opt(r)
	match r:
		PLAY_MODE:
			return _values["play_mode"][v]
		PLAYERS:
			return _values["players"][v] if _playoffs() else _values["players_4way"][v]
		TEAM1, TEAM2:
			if v == 13:
				return _fe["setup"]["special_strings"]["ny_islanders"]
			if v == 14:
				return _fe["setup"]["special_strings"]["ny_rangers"]
			var t: TeamData = _teams[v]
			return t.city if t else "Team %d" % v
		PER_LENGTH:
			return _fe["setup"]["special_strings"]["na"] if _shootout() else _values["period_length"][v]
		GOALIES:
			return _values["goalies"][v]
		USER_RECORDS:
			return _values["user_records"][v]
		PENALTIES:
			return _values["penalties"][v]
		_:
			return _values["line_changes"][v]

# --- the cursor ----------------------------------------------------------------------------

## sub_F76D4 with the skip rules (L960249-960345): the next row from `r` going `d` (+1 / -1),
## or `r` when the cursor cannot move.
func _next_row(r: int, d: int) -> int:
	var n := _next_row_rules(r, d)
	# Continue Playoffs skips Players, Team 1 and Team 2; New Playoffs skips Team 2.
	while n != r and _row_skipped(n):
		var m := _next_row_rules(n, d)
		if m == n:
			return r
		n = m
	return n

func _row_skipped(n: int) -> bool:
	if _opt(PLAY_MODE) == MODE_CONTINUE:
		return n >= PLAYERS and n <= TEAM2
	return _new_playoffs() and n == TEAM2

func _next_row_rules(r: int, d: int) -> int:
	var n := r + d
	if d > 0:
		if r == TEAM2 and _shootout():
			return r if _demo_players() else GOALIES
		if r == PER_LENGTH and _demo_players():
			n = USER_RECORDS if _shootout() else PENALTIES
		if r == GOALIES and _shootout():
			return r
	else:
		if r == GOALIES and _shootout():
			n = TEAM2
		if r == PENALTIES and _demo_players() and not _shootout():
			n = PER_LENGTH
		if r == USER_RECORDS and _demo_players():
			n = PER_LENGTH
	if n < 0 or n >= ROWS:
		return r
	return n

func _move(d: int) -> void:
	_row = _next_row(_row, d)
	if _row < _top:
		_top = _row
	elif _row - _top > VISIBLE - 1:
		_top = _row - (VISIBLE - 1)
	_top = clampi(_top, 0, TOP_MAX)

# --- drawing -------------------------------------------------------------------------------

func _redraw() -> void:
	_palette()
	_a.clear()
	_a.bitmap(0, 0, "setup_header", 0, 0, 40, 4)
	# sub_17AF4: the plates, visitor at (7,1), home at (22,1).
	_a.bitmap(7, 1, "team_plates_visitor", 0, 2 * _vis_team(), 11, 2)
	_a.bitmap(22, 1, "team_plates_home", 0, 2 * _home_team(), 11, 2)
	if _card_up:
		_draw_card()
	else:
		_a.bitmap(8, 5, "logo_frame_visitor", 0, 0, 8, 8)
		_a.bitmap(24, 5, "logo_frame_home", 0, 0, 8, 8)
		_logo(9, 6, _vis_team(), 2)
		_logo(25, 6, _home_team(), 1)
	_a.bitmap(1, 14, "setup_panel", 0, 0, 38, 13)
	# sub_F8070: the labels at x 3, rows 15 + 2 (row - top).
	for r in ROWS:
		var y := 15 + 2 * (r - _top)
		if y >= 15 and y <= 25:
			_a.print_at(3, y, _labels[r], 0, "setup_font")
	# sub_F7864: the cursor box, then GameSetUp_4's values over its middle row.
	var by := 14 + 2 * (_row - _top)
	# The box covers Team 1 and Team 2 in New Playoffs (the bracket fixes Team 2).
	_a.frame(16, by, 23, 5 if _new_playoffs() and _row == TEAM1 else 3, "setup_framer", 0)
	for r in ROWS:
		var y := 15 + 2 * (r - _top)
		if y < 15 or y > 25:
			continue
		var text := _value_text(r)
		_a.print_at(17, y, text + " ".repeat(maxi(20 - text.length(), 0)), 0, "setup_font")
	# The box's last centre cell (x 37) shows the panel (the value is 20 wide).
	_a.bitmap(37, by + 1, "setup_panel", 36, by + 1 - 14, 1, 1)
	# sub_F7BFA: the scroll arrows.
	_a.print_at(2, 15, "{" if _top > 0 else " ", 0, "setup_font")
	_a.print_at(2, 25, "}" if _top < TOP_MAX and not _shootout() else " ", 0, "setup_font")
	if _port_box:
		_draw_port_box()

func _logo(x: int, y: int, team: int, line: int) -> void:
	_a.bitmap(x, y, "team_logos", (team % 4) * 6, (team / 4) * 6, 6, 6, line)

## CRAM: lines 0 and 3 of the background, line 1 the home logo's palette with the plate
## colours in 1-5 (sub_17AF4), line 2 the visitor logo's. A card's photo palette goes to
## line 1 with the same plate colours kept.
func _palette() -> void:
	var bg: Array = _fe["setup"]["palette"]["bg"]
	var home := _home_team()
	var vis := _vis_team()
	var l1: Array = (_photo_pal if _card_up and not _photo_pal.is_empty() else _logo_pal[home]).duplicate()
	var hc: Array = _fe["teams"][home]["colours"][0]
	var vc: Array = _fe["teams"][vis]["colours"][1]
	l1[1] = hc[1]
	l1[2] = hc[2]
	l1[3] = vc[3]
	l1[4] = vc[4]
	l1[5] = 0xEEE
	var lines := [bg[0], l1, _logo_pal[vis], bg[3]]
	for y in 4:
		for x in 16:
			_pal_img.set_pixel(x, y, PaletteBank.cram(int(lines[y][x])))
	_pal_tex.update(_pal_img)

# --- the showcase --------------------------------------------------------------------------

## sub_F87EA: the logos give way to cards, the visitor's first, then home and visitor
## in turn; each visitor card moves on to the next player (word_FFD43E, 1-5 then 0).
func _showcase_step() -> void:
	if not _card_up:
		_card_delay -= 1
		if _card_delay > 0:
			return
		_card_up = true
		_card_home = true
		_card_timer = 0
	_card_timer -= 1
	if _card_timer > 0:
		return
	_card_timer = _card_frames
	_card_home = not _card_home
	if not _card_home:
		_card_player = (_card_player + 1) % 6
	_redraw()

## A card: the logo frame with the player's photo, a box, "NN First Last".
func _draw_card() -> void:
	var team := _home_team() if _card_home else _vis_team()
	var c: Dictionary = _fe["setup"]["showcase"]["home_card" if _card_home else "visitor_card"]
	var fr: Array = c["frame"]
	var ph: Array = c["photo"]
	var bx: Array = c["box"]
	var nm: Array = c["name"]
	_a.bitmap(fr[0], fr[1], "logo_frame_home" if _card_home else "logo_frame_visitor", 0, 0, 8, 8)
	var entry := _photo_entry(team, _card_player)
	var idx: int = entry[0]
	var per: int = _photos.get("per_row", 16)
	_a.bitmap(ph[0], ph[1], "photos", (idx % per) * 6, (idx / per) * 6, 6, 6, 1)
	_a.frame(bx[0], bx[1], 25, 8, "setup_framer", 0)
	var t: TeamData = _teams[team]
	var p: PlayerData = t.player(entry[1]) if t else null
	if p:
		_a.print_at(nm[0], nm[1], "%s %s" % [Hud.jersey(p.jersey_number), p.full_name], 0, "setup_font")

## photos.json teams[team][k]: [photo, roster slot].
func _photo_entry(team: int, k: int) -> Array:
	var teams: Array = _photos.get("teams", [])
	if team < teams.size() and k < teams[team].size():
		var e: Dictionary = teams[team][k]
		return [int(e["photo"]), int(e["slot"])]
	return [0, 0]

## sub_F84FC: a team change ends the showcase and brings the logos back.
func _end_showcase() -> void:
	_card_up = false
	_card_home = false
	_card_delay = SHOWCASE_DELAY
	_card_frames = CARD_FRAMES

# --- the port's options box ------------------------------------------------------------------

const PORT_ROWS := ["Edition", "Fighting"]

func _draw_port_box() -> void:
	_a.erase(3, 4, 34, 9)
	_a.frame(3, 4, 34, 9, "setup_framer", 0)
	_a.print_at(5, 5, "Port options", 0, "setup_font")
	var vals := [
		"NHL Hockey '94" if Sim.match.edition == MatchConfig.Edition.RETAIL else "'94-Fight patch",
		["Off", "On", "On - Arcade Mode"][Sim.match.fighting] if Sim.match.edition == MatchConfig.Edition.FIGHT else "N/A"]
	for i in PORT_ROWS.size():
		var y := 7 + 2 * i
		_a.print_at(5, y, ("]" if i == _port_row else " ") + PORT_ROWS[i], 0, "setup_font")
		_a.print_at(16, y, vals[i], 0, "setup_font")

func _port_input(step: Vector2i) -> void:
	if step.y != 0:
		_port_row = clampi(_port_row + step.y, 0, PORT_ROWS.size() - 1)
	elif step.x != 0:
		if _port_row == 0:
			Sim.match.edition = MatchConfig.Edition.FIGHT if Sim.match.edition == MatchConfig.Edition.RETAIL \
				else MatchConfig.Edition.RETAIL
			_load_teams()
		elif Sim.match.edition == MatchConfig.Edition.FIGHT:
			Sim.match.fighting = posmod(Sim.match.fighting + step.x, 3) as MatchConfig.Fighting
	_redraw()

# --- input ---------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _fe.is_empty():
		return
	var pressed := _read_pads()
	if pressed.is_empty():
		_idle += 1
		if _idle >= DEMO_IDLE:
			_demo()
			return
		if not _port_box and (_idle < SHOWCASE_WINDOW or _card_up):
			_showcase_step()
		return
	_idle = 0
	var k: String = pressed[0]
	if k == "c":
		# word_FFD43C: C hurries the showcase.
		_card_frames = CARD_FRAMES_FAST
		return
	if k == "b":
		_port_box = not _port_box
		_redraw()
		return
	if k == "start":
		if _port_box:
			_port_box = false
			_redraw()
			return
		_start()
		return
	if k == "a":
		return
	var step := Vector2i(1 if k == "right" else (-1 if k == "left" else 0), 1 if k == "down" else (-1 if k == "up" else 0))
	if _port_box:
		_port_input(step)
		return
	if step.y != 0:
		_move(step.y)
	else:
		var t1 := _opt(TEAM1)
		var t2 := _opt(TEAM2)
		_change(_row, step.x)
		_clamp_all()
		if _opt(TEAM1) != t1 or _opt(TEAM2) != t2:
			_end_showcase()
	_redraw()

## sub_11318 on pads 1-4: the first pad with a new press (or a repeat) wins.
func _read_pads() -> Array:
	for pad in 4:
		var p := "p%d_" % (pad + 1)
		for b in ["start", "up", "down", "left", "right", "a", "b", "c"]:
			var key: String = p + b
			if Input.is_action_just_pressed(key):
				_repeat[key] = REPEAT_FIRST
				return [b]
			if Input.is_action_pressed(key) and b in ["up", "down", "left", "right"]:
				_repeat[key] = _repeat.get(key, REPEAT_FIRST) - 1
				if _repeat[key] <= 0:
					_repeat[key] = REPEAT_NEXT
					return [b]
	return []

# --- leaving -------------------------------------------------------------------------------

## loc_F843E: the options into a MatchConfig; Matchups next, or the game in Shootout.
func _start() -> void:
	var m := MatchConfig.new()
	m.edition = Sim.match.edition
	m.fighting = Sim.match.fighting
	m.home_team = _teams[_opt(TEAM1)]
	m.away_team = _teams[_opt(TEAM2)]
	m.players = _opt(PLAYERS)
	m.perlen = _opt(PER_LENGTH)
	m.auto_goalie = _opt(GOALIES) == 1
	m.penalties = _opt(PENALTIES) != 0
	m.offsides = _opt(PENALTIES) == 1
	m.line_changes = _opt(LINES) != 1
	m.auto_lines = _opt(LINES) == 2
	m.shootout = _shootout()
	if _playoffs():
		# sub_17AC8: pojoy = 7 - OptNOP for a new playoff; FigureJoy's teams and pads.
		if _new_playoffs():
			Sim.league.pojoy = 7 - _opt(PLAYERS)
		var fj := Sim.league.figure_joy()
		if not fj.is_empty():
			m.home_team = _teams[fj["home"]]
			m.away_team = _teams[fj["visitor"]]
			m.pads = fj["pads"]
		m.play_mode = _opt(PLAY_MODE)
	Sim.match = m
	if m.shootout:
		get_tree().change_scene_to_file(GAME_SCENE)
	elif _playoffs():
		Sim.bracket_next_matchups = true
		get_tree().change_scene_to_file(PLAYOFF_SCENE)
	else:
		get_tree().change_scene_to_file(MATCHUPS_SCENE)

## loc_F8418: the demo, CPU against CPU with the teams on screen, penalties and line
## changes on, a regular game.
func _demo() -> void:
	Sim.options[PLAY_MODE] = MODE_REGULAR
	Sim.options[PLAYERS] = NOP_DEMO
	Sim.options[LINES] = 0
	Sim.options[PENALTIES] = 1
	Sim.demo_played = true
	_clamp_all()
	_start()
