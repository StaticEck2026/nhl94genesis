extends CanvasLayer
## The in-game overlays as retail prints them (spec docs/specs/ui_ingame.md), on two
## WindowPlanes of 8 x 8 cells:
## - plane A (this layer, over everything, as the high-priority cells are): the score box
##   with the period, clock, EA logo or power-play banner, and the team box; the referee's
##   message under the referee; the goal, injury, penalty-shot and shootout boxes; the
##   face-off line labels; the line-change menu; the fight patch's banner; Stars of the
##   Game.
## - plane B (a child of the game at the side view's depth, so the players and the crowd
##   draw over it): the sideways penalty screen's team plates, big goals, period, clock
##   and penalty-box lists.
## The boxes come and go on retail's triggers; everything else is redrawn from the game
## state every frame. The intermission and final banners stay Labels until the menus are
## ported.

## The penalty screen's player name replaces the call after this long (UpdatePA L46537).
const NAME_DELAY := 60
## The line menu shows the pick this long after it closes.
const PICK_LINGER := 90
const ROW_KEYS := ["A ", "B ", "C "]

@onready var _label: Label = %Scoreboard
var game: HockeyGame
var _a: WindowPlane
var _b: WindowPlane
var _banner: Label
## The banner is the intermission's (cleared when the intermission ends).
var _inter_banner := false

## The referee's message: [id, text, frames since SetPA], or empty.
var _ref: Array = []
## loc_1889A / loc_1871C / Stars / fight banner / shootout winner, or empty.
var _goal := {}
var _injury: Array = []
var _stars: Array = []
var _fight: PackedStringArray = PackedStringArray()
var _so_winner := -1
## The line menu last shown per team and how long the pick lingers.
var _menu_team := -1
var _menu_linger := 0

func bind(p_game: HockeyGame) -> void:
	game = p_game
	_a = WindowPlane.new()
	_a.name = "PlaneA"
	_a.material = game.palette_material(false)
	add_child(_a)
	_b = WindowPlane.new()
	_b.name = "PlaneB"
	_b.origin = Vector2(-128, -112)
	_b.z_index = Rink2D.Z_LOGO
	_b.z_as_relative = false
	_b.material = game.palette_material(false)
	game.add_child(_b)
	_label.visible = not WindowPlane.available()
	_banner = Label.new()
	_banner.position = Vector2(0, 100)
	_banner.size = Vector2(320, 24)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_color", Color(1, 1, 0.6))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner.add_theme_constant_override("outline_size", 2)
	_banner.add_theme_font_size_override("font_size", 8)
	add_child(_banner)
	var w := game.world
	game.stepped.connect(_refresh)
	w.rules.pa_set.connect(_on_pa)
	w.rules.goal_box.connect(func(info: Dictionary) -> void: _goal = info)
	w.rules.stars.connect(func(picks: Array) -> void: _stars = picks)
	w.ref_signal.connect(func(f: int) -> void:
		if f == 0x40:
			_ref = [])
	w.rules.intermission.connect(_on_intermission)
	w.rules.game_over.connect(_on_game_over)
	w.rules.period_started.connect(func(_g: int) -> void:
		if not w.intermission:
			_banner.text = "")
	w.rules.horizontal_changed.connect(_on_horizontal)
	w.injury_message.connect(_on_injury)
	w.fight.banner.connect(func(l: PackedStringArray) -> void:
		_fight = l
		_injury = [])
	w.fight.banner_cleared.connect(func() -> void: _fight = PackedStringArray())
	w.faceoff.faceoff_set.connect(_on_faceoff_set)
	var rw := RefWindow.new()
	rw.name = "RefWindow"
	add_child(rw)
	rw.setup(game)
	var fw := FaceoffWindow.new()
	fw.name = "FaceoffWindow"
	add_child(fw)
	fw.setup(game)
	# The overlay cells sit over the referee and face-off pictures, as plane A does.
	move_child(_a, -1)

# --- triggers -------------------------------------------------------------------------------

func _on_pa(id: int) -> void:
	var w := game.world
	var text := GameRules.entry(id)[2] as String
	_ref = [id, text, 0]
	# sub_FC5AE: the shootout's decided call puts up the winner.
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT and w.f_c2fa & ShootoutLogic.C2FA_DECIDED:
		_so_winner = 0 if w.shootout_goals[0] > w.shootout_goals[1] else 1

## SetHor fills plane A; ClrHor erases it: the boxes go.
func _on_horizontal(_on: bool) -> void:
	_goal = {}
	_injury = []
	_fight = PackedStringArray()

## Port choice: the goal and injury boxes go when the next face-off is set up. Retail
## leaves them to the top line menu, the penalty screen or a pause (ui_ingame.md §5,
## UNRESOLVED 1).
func _on_faceoff_set() -> void:
	_goal = {}
	_injury = []

func _on_injury() -> void:
	var w := game.world
	var fight := w.puck().flags2 & SimObject.PF2_FIGHT != 0
	_injury = [1 if w.temp_pl_offset & 0x8000 else 0, w.temp_pl_offset & 0xFF, w.injury_game, fight]

func _on_intermission(gsp: int) -> void:
	_ref = []
	if gsp == 0 or gsp >= 4:
		return
	var names := ["", "End of the 1st", "End of the 2nd", "End of regulation"]
	_banner.text = "%s  -  Start to continue" % names[mini(gsp, 3)]
	_inter_banner = true

func _on_game_over() -> void:
	var w := game.world
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		_banner.text = "%s  %s %d  %s %d" % [w.shootout.winner_text(), _abbr(0),
			w.shootout_goals[0], _abbr(1), w.shootout_goals[1]]
		return
	_banner.text = "Final  %s %d  %s %d" % [_abbr(0), w.score(0), _abbr(1), w.score(1)]

# --- names (sub_18B26, sub_18AE8, getname, d0toascii) ---------------------------------------

func _abbr(team: int) -> String:
	var d := game.world.stats[team].data
	return d.abbreviation if d else ("HOM" if team == 0 else "AWY")

func _city(team: int) -> String:
	var d := game.world.stats[team].data
	return d.city if d else _abbr(team)

func _player(team: int, slot: int) -> PlayerData:
	var d := game.world.stats[team].data
	return d.player(slot) if d and slot >= 0 else null

## d0toascii: the jersey in two characters, a tens digit of 0 shown as a space.
static func jersey(n: int) -> String:
	return "%2d" % (n % 100)

## sub_18B26: "27 Roenick" (the text after the first space).
func short_name(team: int, slot: int) -> String:
	var p := _player(team, slot)
	if p == null:
		return "%2d" % slot
	var i := p.full_name.find(" ")
	return "%s %s" % [jersey(p.jersey_number), p.full_name.substr(i + 1) if i >= 0 else p.full_name]

## sub_18AE8: "27 J. Roenick".
func initial_name(team: int, slot: int) -> String:
	var p := _player(team, slot)
	if p == null:
		return "%2d" % slot
	var i := p.full_name.find(" ")
	if i < 0:
		return "%s %s" % [jersey(p.jersey_number), p.full_name]
	return "%s %s. %s" % [jersey(p.jersey_number), p.full_name.substr(0, 1), p.full_name.substr(i + 1)]

## getname: "27 Jeremy Roenick".
func full_name(team: int, slot: int) -> String:
	var p := _player(team, slot)
	return "%s %s" % [jersey(p.jersey_number), p.full_name] if p else "%2d" % slot

## PushTime: "[T]M:SS", the tens of minutes blank when 0.
static func push_time(s: int) -> String:
	s = maxi(s, 0)
	var m := s / 60
	return "%s%d:%02d" % [" " if m < 10 else str(m / 10), m % 10, s % 60]

# --- the frame -------------------------------------------------------------------------------

func _refresh() -> void:
	var w := game.world
	if _inter_banner and not w.intermission:
		_inter_banner = false
		_banner.text = ""
	if _ref.size() > 0:
		_ref[2] += 1
	if _label.visible:
		_label.text = "%s %d  %s %d   %d:%02d" % [_abbr(0), w.score(0), _abbr(1), w.score(1),
			w.clock_seconds() / 60, w.clock_seconds() % 60]
		return
	_a.cells.clear()
	_b.cells.clear()
	if w.intermission:
		_a.queue_redraw()
		_b.queue_redraw()
		return
	if w.sflags & HockeyWorld.SF_HOR:
		_penalty_screen()
		_ref_message()
	else:
		var menus := _line_menu()
		_score_box(menus)
		_ref_message()
		_faceoff_labels()
		_goal_box()
		_injury_box()
		_fight_banner()
	_shootout_boxes()
	_stars_box()
	_a.queue_redraw()
	_b.queue_redraw()

## PrintScores1 (L47137) and showclock (L52387): the score box at (0,23) and the team box
## at (23,23), which a line menu at the bottom covers.
func _score_box(bottom_menu: bool) -> void:
	var w := game.world
	var a := _a
	a.frame(0, 23, 9, 5)
	var attempt := w.f_c2fa & ShootoutLogic.C2FA_ATTEMPT_CLOCK != 0
	var labels: Array = WindowPlane.messages().get("period_labels_alt" if attempt else "period_labels", [])
	var gi := 4 if attempt else mini(w.gsp, 4)
	if gi < labels.size():
		a.print_at(1, 24, labels[gi]["text"])
	a.print_at(3, 24, push_time(w.shootout.ps_clock if attempt else w.clock_seconds()))
	if w.sflags2 & HockeyWorld.SF2_PWRPLAY:
		# updatepwrplay: the team on the power play, the "Pwr Play" glyphs, the time left.
		var pp := 1 if w.sflags2 & HockeyWorld.SF2_PWRTM else 0
		a.print_at(1, 25, "   " + String.chr(0x16) + String.chr(0x17) + String.chr(0x18) + String.chr(0x19))
		a.print_at(1, 25, _abbr(pp))
		a.print_at(1, 26, "  " + push_time(w.rules.calc_pen_time(w.stats[1 - pp], w.stats[pp])))
	else:
		a.bitmap(1, 25, "ea_logo", 0, 0, 7, 2)
	if bottom_menu:
		return
	a.frame(23, 23, 8, 5)
	for team in 2:
		var row := 26 if team == 0 else 24
		a.print_at(24, row, _abbr(team))
		a.print_at(28, row, "%2d" % (w.score(team) % 100))

## prefmes (L46669): the call in a box under the referee (rows 10-12); on the penalty
## screen centred on row 11, replaced after a second by the player's number and name.
func _ref_message() -> void:
	if _ref.is_empty():
		return
	var text: String = _ref[1]
	var w := game.world
	if w.sflags & HockeyWorld.SF_HOR:
		_a.print_at(5, 11, " ".repeat(22))
		var n := 2 + text.length() + (text.length() & 1)
		if _ref[2] >= NAME_DELAY:
			var t := 1 if w.temp_pl_offset & 0x8000 else 0
			var name := full_name(t, w.temp_pl_offset & 0xFF)
			_a.print_at(17 - (2 + name.length() + (name.length() & 1)) / 2, 11, name)
		elif text != "":
			_a.print_at(17 - n / 2, 11, text)
		return
	if text == "":
		return
	var l := text.length()
	var x := maxi(0, 5 - (l + (l & 1)) / 2)
	_a.frame(x, 10, l + 2, 3)
	_a.print_at(x + 1, 11, text)

## loc_1889A (L55990): the goal box at (11,2), 19 wide.
func _goal_box() -> void:
	if _goal.is_empty():
		return
	var team: int = _goal["team"]
	var assists: Array = _goal["assists"]
	var h := 5 if assists.is_empty() else (7 if assists.size() == 1 else 8)
	_a.frame(11, 2, 19, h)
	var header: String = _goal["header"]
	var hx := {"GOAL!": 15, "PP GOAL!": 13, "HAT TRICK!": 12}
	_a.print_big(hx.get(header, 12), 3, header)
	var x := _a.print_at(12, 5, short_name(team, _goal["scorer"]))
	if _goal["goals"] >= 0:
		_a.print_at(x, 5, " (%d)" % _goal["goals"])
	if assists.is_empty():
		return
	_a.print_at(14, 6, "Assist by:")
	for i in assists.size():
		var a: Array = assists[i]
		var ax := _a.print_at(12, 7 + i, short_name(team, a[0]))
		_a.print_at(ax, 7 + i, " (%d)" % a[1])

## loc_1871C (L55851): "Injury to:" at (11,3), 18 x 5.
func _injury_box() -> void:
	if _injury.is_empty():
		return
	_a.frame(11, 3, 18, 5)
	_a.print_at(12, 4, "Injury to:")
	_a.print_at(12, 6, "Out for game" if _injury[2] else "Out for period")
	_a.print_at(12, 5, initial_name(_injury[0], _injury[1]))
	if _injury[3]:
		_a.print_at(20, 6, "the game")

## The fight patch's banner: Framer W x 5 centred on column 15, names on rows 2 and 4.
func _fight_banner() -> void:
	if _fight.size() < 3:
		return
	var lens := []
	for s in [_fight[0], _fight[2]]:
		lens.append(2 + s.length() + (s.length() & 1))
	var wd: int = maxi(lens[0], lens[1])
	_a.frame(15 - wd / 2, 1, wd, 5)
	_a.print_at(16 - lens[0] / 2, 2, _fight[0])
	_a.print_at(15, 3, "vs")
	_a.print_at(16 - lens[1] / 2, 4, _fight[2])

## sub_187B8 / loc_FC320 (while the intro is up) and sub_FC5AE (the winner).
func _shootout_boxes() -> void:
	var w := game.world
	var so := w.shootout
	if w.f_c2fa & HockeyWorld.C2FA_PS_INTRO and w.ba_sktr >= 0:
		# sub_187B8 / loc_FC320 clear the referee message (prefmes -1) and the goal area.
		_ref = []
		_goal = {}
		_injury = []
		var shooter := w.objects[w.ba_sktr].pnum & 0xFF
		if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
			var gteam := 1 - w.shootout_side
			_a.frame(3, 2, 27, 12)
			_a.print_big(4, 3, "SHOOTOUT MODE")
			_a.print_at(4, 5, initial_name(so.ba_team, shooter))
			_a.print_at(10, 6, " vs.")
			_a.print_at(4, 7, initial_name(gteam, so.so_list[gteam][5]))
			_a.print_at(4, 9, _city(0))
			_a.print_at(21, 9, "%3d" % w.shootout_goals[0])
			_a.print_at(4, 10, _city(1))
			_a.print_at(21, 10, "%3d" % w.shootout_goals[1])
			_a.print_at(4, 12, "Round %2d" % so.so_round)
		else:
			_a.frame(3, 2, 27, 8)
			_a.print_big(4, 3, "PENALTY SHOT!")
			_a.print_at(4, 5, initial_name(so.ba_team, shooter))
			var x := _a.print_at(4, 7, GameRules.entry(so.ps_variant)[2])
			_a.print_at(x, 7, " by")
			_a.print_at(4, 8, initial_name(1 - so.ba_team, so.ba_checker_offset))
	if _so_winner >= 0:
		_a.frame(1, 13, 30, 6)
		_a.print_big(2, 14, "SHOOTOUT WON BY")
		_a.print_big(2, 16, _city(_so_winner))

## puckfaceoff2 loc_FB54 (L42215): with line changes on, the two lines in a 12 x 3 box
## under the close-up.
func _faceoff_labels() -> void:
	var w := game.world
	var fo := w.faceoff
	if not fo.window_open or not w.opt_line_on:
		return
	var x := (fo.fodrop.x - 0x2E) >> 3
	_a.frame(x, 13, 12, 3)
	var home := w.lines.line_name(w.stats[0].line)
	var away := w.lines.line_name(w.stats[1].line)
	var left := home if w.gmode & HockeyWorld.GM_DIR else away
	var right := away if w.gmode & HockeyWorld.GM_DIR else home
	_a.print_at(x + 1, 14, left)
	_a.print_at(x + 8, 14, right)

## sub_B92E / setlccords: the line-change menu at (22, 0) or (22, 22), 9 wide; the home
## team's at the bottom unless the teams have swapped ends. A top menu blanks the goal
## box's area (box, L56167); a bottom one covers the team box. True when a menu is at the
## bottom.
func _line_menu() -> bool:
	var w := game.world
	var open := -1
	for k in 2:
		var t := w.cont_team[k] - 1
		if t >= 0 and w.stats[t].flags30 & TeamStats.F30_LINE_MENU:
			open = t
	if open >= 0:
		_menu_team = open
		_menu_linger = PICK_LINGER
	elif _menu_linger > 0:
		_menu_linger -= 1
	if _menu_team < 0 or (open < 0 and _menu_linger <= 0):
		return false
	var team := _menu_team
	var bottom := (team == 0) != (w.gmode & HockeyWorld.GM_DIR != 0)
	var y := 22 if bottom else 0
	if not bottom:
		_goal = {}
		_injury = []
	var rows := []
	for r in 3:
		var l := w.lines.getlchoice(team, r)
		if l >= 0:
			rows.append([r, l])
	if open < 0:
		rows = rows.filter(func(e: Array) -> bool: return e[1] == w.stats[team].line)
		if rows.is_empty():
			_menu_linger = 0
			return false
	var h := 6 if rows.size() >= 3 or open < 0 else 5
	if h == 5:
		y += 1
	_a.frame(22, y, 9, h)
	_a.print_at(25, y + 1, _abbr(team))
	var row := y + h - 2
	for i in range(rows.size() - 1, -1, -1):
		var e: Array = rows[i]
		_a.print_at(23, row, ROW_KEYS[e[0]])
		_a.print_at(25, row, w.lines.line_name(e[1]))
		var fill := mini(w.lines.getlinee(team, e[1]) / 256, 15)
		_a.bitmap(28, row, "energy", 0, 15 - fill, 2, 1)
		row -= 1
	return bottom

## sub_1850A (L55666): Stars of the Game, 28 x 9 at (2,14).
func _stars_box() -> void:
	if _stars.is_empty():
		return
	_a.frame(2, 14, 28, 9)
	_a.print_at(9, 16, "Stars of the Game")
	for i in _stars.size():
		var p: Array = _stars[i]
		_a.print_at(26, 19 + i, _abbr(p[0]))
		_a.print_at(3, 19 + i, full_name(p[0], p[1]))

## sub_12DA6 (L47290) on plane B: plates, big goals, period and clock on the side view,
## and each team's box list (jersey, time left) under its "# Penalty" heading.
func _penalty_screen() -> void:
	var w := game.world
	var b := _b
	var labels: Array = WindowPlane.messages().get("period_labels_alt", [])
	var gi := 4 if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT else mini(w.gsp, 4)
	if gi < labels.size():
		var s: String = labels[gi]["text"]
		b.print_at(17 - (2 + s.length()) / 2, 2, s)
	for team in 2:
		var x0 := 23 if team == 0 else 8
		var ti := w.stats[team].team_index
		if ti >= 0:
			b.bitmap(x0 - 5, 2, "team_plates", 0, 2 * ti, 11, 2)
		var g := w.score(team)
		b.print_big(x0 - (1 if g >= 10 else 0), 4, str(g))
		_box_list(team, 20 if team == 0 else 5)
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT == 0:
		var t := w.clock_seconds()
		if t / 600 > 0:
			b.print_at(13, 5, str(t / 600))
		b.print_at(14, 5, str((t % 600) / 60))
		b.print_at(17, 5, "%02d" % (t % 60))

## sub_12DDE / sub_12E12: up to three rows from row 8, non-coincidental entries first.
func _box_list(team: int, x: int) -> void:
	var st := game.world.stats[team]
	var order := []
	for coincidental in [false, true]:
		for slot in st.box:
			if (st.tmpdst[slot] & 0x4000 != 0) == coincidental:
				order.append(slot)
	var row := 8
	for slot in order:
		if row > 10:
			break
		var p := _player(team, slot)
		_b.print_at(x, row, jersey(p.jersey_number if p else slot) + push_time(st.tmpdst[slot] & 0x7FF))
		row += 1
