class_name StatsPages
extends CanvasLayer
## The menus' full-screen pages (spec docs/specs/ui_menus.md §4-§15), on the H40 screen
## (40 x 28 cells, the port's whole 320 x 224 view). As sub_9BD8 builds them:
## - the "SPORTS" background (stats_bg, palette $54E24) under everything;
## - plane B, the page's live text, clipped to rows d0..d1-1 (outside them the background
##   has priority) and scrolled through VSRAM (a base row plus the page's scroll);
## - the window on top: the framed big title, the team plates, the column headers.
## Fixed text comes from pages.json's decoded print ops (`_run`), the rest from the game.
## Start leaves a page (back to the menu at the same row).

signal closed

const DIR := "res://assets/ui/menus/"
const STRENGTH := ["SH2", "SH", "", "PP", "PP2"]
const PERIODS := [" 1", " 2", " 3", "OT"]
const POS_NAMES := ["LD", "RD", "LW", "C", "RW"]
## Team Roster: the rating columns by header, as PlayerData fields.
const RATING_FIELDS := {"Agility": "agility", "Speed": "speed", "Off. Awareness": "offensive_awareness",
	"Def. Awareness": "defensive_awareness", "Shot Power": "shot_power", "Shot  Accuracy": "shot_accuracy",
	"Pass  Accuracy": "pass_accuracy", "Stick Handling": "stick_handling", "Endurance": "endurance",
	"Aggressiveness": "aggressiveness", "Checking": "checking", "Puck Control": "puck_control",
	"Stick  Right": "stick_right", "Stick Left": "stick_left", "Glove  Right": "glove_right",
	"Glove Left": "glove_left"}
## Line Editor: the lines on each page (Sc1+Sc2+Chk / PP1+PP2 / PK1+PK2) and their columns
## ($879E: header x, slots).
const EDIT_PAGES := [[0, 1, 2], [3, 4], [5, 6]]
const EDIT_COLS := [[4, 5], [16, 5], [28, 5], [4, 5], [16, 5], [4, 4], [16, 4]]

## Save Team Line ($FFD076): one saved set for the session, [team index, ram lines].
static var saved_lines: Array = []

var _pages := {}
var _pal := {}
var _menus := {}
var _photos := {}
var _game: HockeyGame
var _team := 0
var _pad := 0
var _id := ""

var _bg: Sprite2D
var _clip: Control
var _b: WindowPlane
var _bimg: Node2D
var _wimg: Node2D
var _w: WindowPlane
var _stats_mat: ShaderMaterial
var _d0 := 0
var _base := 0
var _scroll := 0
var _target := 0
var _max := 0
var _step := 16

## Page state: a category / attribute column, a line or card, a mode, the Line Editor's
## slot and list.
var _col := 0
var _sel := 0
var _mode := 0
var _list: Array = []
var _list_cursor := 0
var _menu_items: Array = []
var _menu_cursor := 0
## The pad's Start must be let go after the page opens (the press that opened it).
var _armed := false

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	for e in [["pages.json", "_pages"], ["palettes.json", "_pal"], ["menus.json", "_menus"], ["photos.json", "_photos"]]:
		if FileAccess.file_exists(DIR + e[0]):
			set(e[1], JSON.parse_string(FileAccess.get_file_as_string(DIR + e[0])))
	_bg = Sprite2D.new()
	_bg.centered = false
	add_child(_bg)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_b = WindowPlane.new()
	_b.origin = Vector2.ZERO
	_clip.add_child(_b)
	_bimg = Node2D.new()
	_b.add_child(_bimg)
	_wimg = Node2D.new()
	add_child(_wimg)
	_w = WindowPlane.new()
	_w.origin = Vector2.ZERO
	add_child(_w)
	visible = false

func is_open() -> bool:
	return _id != ""

func hide_page() -> void:
	if _id != "":
		ScreenMode.set_h32(get_tree(), true)
	_id = ""
	visible = false

# --- palettes and images -------------------------------------------------------------------

static func _pal_tex(lines: Array) -> ImageTexture:
	var img := Image.create(16, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		var row: Array = lines[mini(y, lines.size() - 1)] if lines[0] is Array else lines
		for x in 16:
			img.set_pixel(x, y, PaletteBank.cram(int(row[x])))
	return ImageTexture.create_from_image(img)

## Player Cards' CRAM: line 0 and 3 of the page, line 1 the team's logo palette
## (sub_FA66E), line 2 the photo palette.
func _cards_lines() -> Array:
	var c: Dictionary = _pal["cards"]
	var ti := _game.world.stats[_team].team_index
	var logo: Array = _pal["team_logos"][ti] if ti >= 0 else c["cards_bg"][1]
	return [c["line0"], logo, _pal["photo"], c["line3"]]

func _material(lines: Array) -> ShaderMaterial:
	return PaletteBank.material(_pal_tex(lines))

func _tex(name: String) -> Texture2D:
	var f := DIR + name + "_idx.png"
	return load(f) if ResourceLoader.exists(f) else null

## An image at cell (x, y) of plane B or the window, with its own palette.
func _image(name: String, at: Vector2i, plane: String, region := Rect2(), lines: Array = []) -> void:
	# The cards background is the page's background (_setup), under plane B.
	if name == "cards_bg":
		return
	var tex := _tex(name)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.centered = false
	s.texture = tex
	if region.size != Vector2.ZERO:
		s.region_enabled = true
		s.region_rect = region
	var pal: Variant = _pal.get(name, null)
	s.material = _material(lines if not lines.is_empty() else (pal if pal is Array else _pal["stats"]))
	s.position = Vector2(at) * 8
	(_bimg if plane == "B" else _wimg).add_child(s)

func _team_logo(team: int, at: Vector2i, plane: String) -> void:
	var t := _game.world.stats[team].team_index
	if t < 0:
		return
	_image("team_logos", at, plane, Rect2((t % 4) * 48, (t / 4) * 48, 48, 48), _pal["team_logos"][t])

# --- opening -------------------------------------------------------------------------------------

func open_page(id: String, game: HockeyGame, team: int, pad: int) -> void:
	_game = game
	_team = team
	_pad = pad
	_id = id
	_armed = false
	_col = 0
	_sel = 0
	_mode = 0
	_list = []
	_menu_items = []
	_scroll = 0
	_target = 0
	_max = 0
	if not _pages.get("pages", {}).has(id) and not id in ["edit_lines", "playoff_stats"]:
		_id = ""
		closed.emit()
		return
	visible = true
	# sub_9BD8: the stats pages are H40.
	ScreenMode.set_h32(get_tree(), false)
	if id == "team_roster":
		_sel = _game.world.stats[team].line + 1
	_build()

func _close() -> void:
	# $9CD8: back to H32.
	ScreenMode.set_h32(get_tree(), true)
	_id = ""
	visible = false
	closed.emit()

## sub_9BD8(d0, d1): the background, plane B clipped to rows d0..d1-1 with plane row 0 at
## screen row `base`.
func _setup(d0: int, d1: int, base: int, bg := "stats_bg") -> void:
	for n in [_bimg, _wimg]:
		for c in n.get_children():
			c.queue_free()
	_b.clear()
	_w.clear()
	if _stats_mat == null:
		_stats_mat = _material(_pal["stats"])
	var mat := _stats_mat if bg == "stats_bg" else _material(_cards_lines())
	_b.material = mat
	_w.material = mat
	_bg.texture = _tex(bg)
	_bg.material = mat
	_d0 = d0
	_clip.position = Vector2(0, d0 * 8)
	_clip.size = Vector2(320, (d1 - d0) * 8)
	_base = base
	_apply_scroll()

func _apply_scroll() -> void:
	_b.position = Vector2(0, (_base - _d0) * 8 - _scroll)

## The decoded print ops of a page's fixed text; entries whose note holds one of `skip`
## are left to the page's own code.
func _run(entries: Array, skip: Array = []) -> void:
	var x := 0
	var y := 0
	var plane := "W"
	var attr := 0x8000
	var font := 0
	for e in entries:
		var note: String = e.get("note", "")
		var skipped := false
		for s in skip:
			if note.contains(s):
				skipped = true
		if skipped:
			continue
		if e.has("op"):
			var at: Vector2i = Vector2i(e["at"][0], e["at"][1]) if e.has("at") else Vector2i(x, y)
			var pl := _b if plane == "B" else _w
			match String(e["op"]):
				"framer":
					# Port choice: every stats box in line 1 (the dark fill retail shows);
					# map line 1 + attribute would give $C000 boxes line 3's grey fill.
					pl.frame(at.x, at.y, e["w"], e["h"], "framer_stats", 1)
				"plate":
					var t := _plate_team(String(e["team"]))
					var ti := _game.world.stats[t].team_index
					if ti >= 0:
						pl.bitmap(at.x, at.y, "team_plates", 0, 2 * ti, 11, 2)
				"image":
					_image(String(e["name"]), at, plane)
				"team_logo":
					_team_logo(_plate_team(String(e["team"])), at, plane)
			continue
		var big: bool = e.get("kind", "") == "printbig"
		for op in e.get("ops", []):
			if op.has("at"):
				x = op["at"][0]
				y = op["at"][1]
				plane = op["plane"]
				attr = op["attr"]
			if op.has("plane") and not op.has("at"):
				plane = op["plane"]
			if op.has("attr") and not op.has("at"):
				attr = op["attr"]
			if op.has("font"):
				font = op["font"]
			if op.has("x"):
				x = op["x"]
			if op.has("y"):
				y = op["y"]
			if op.has("dx"):
				x += int(op["dx"])
			if op.has("dy"):
				y += int(op["dy"])
			if op.has("text"):
				var pl2 := _b if plane == "B" else _w
				var line := (attr >> 13) & 3
				if big:
					x = pl2.print_big(x, y, op["text"], (1 + line) & 3)
				else:
					x = pl2.print_at(x, y, op["text"], line, "stats%d" % font)

func _plate_team(which: String) -> int:
	match which:
		"home":
			return 0
		"away":
			return 1
	return _team

func _page(id: String) -> Dictionary:
	return _pages.get("pages", {}).get(id, {})

# --- text helpers ----------------------------------------------------------------------------

## Attribute $8000 / $A000 / $C000 / $E000 -> palette line 0-3.
func _t(pl: WindowPlane, x: int, y: int, text: String, line: int = 0, font: int = 0) -> int:
	return pl.print_at(x, y, text, line, "stats%d" % font)

## printx -= len / 2 with len the string's length word (characters + 2, even).
static func center_x(c: int, text: String) -> int:
	var l := text.length()
	return c - (2 + l + (l & 1)) / 2

func _player(team: int, slot: int) -> PlayerData:
	var d := _game.world.stats[team].data
	return d.player(slot) if d and slot >= 0 else null

func _abbr(team: int) -> String:
	var d := _game.world.stats[team].data
	return d.abbreviation if d else ""

func _last(team: int, slot: int) -> String:
	var p := _player(team, slot)
	if p == null:
		return ""
	var i := p.full_name.find(" ")
	return p.full_name.substr(i + 1) if i >= 0 else p.full_name

## sub_18B26 "27 Roenick" / sub_18AE8 "27 J. Roenick".
func _short(team: int, slot: int) -> String:
	var p := _player(team, slot)
	return "%2d %s" % [p.jersey_number % 100, _last(team, slot)] if p else ""

func _initial(team: int, slot: int) -> String:
	var p := _player(team, slot)
	if p == null:
		return ""
	return "%2d %s. %s" % [p.jersey_number % 100, p.full_name.substr(0, 1), _last(team, slot)]

func _arrows(x: int, y_up: int, y_down: int, line := 0, font := 1) -> void:
	if _scroll > 0:
		_t(_w, x, y_up, "{", line, font)
	if _scroll < _max:
		_t(_w, x, y_down, "}", line, font)

# --- building ------------------------------------------------------------------------------------

func _build() -> void:
	match _id:
		"game_stats":
			_game_stats()
		"player_stats", "playoff_stats":
			_player_stats()
		"scoring_summary":
			_scoring_summary()
		"penalty_summary":
			_penalty_summary()
		"team_roster":
			_team_roster()
		"crowd_meter":
			_crowd_meter()
		"period_stats":
			_period_stats()
		"other_scores":
			_other_scores()
		"record_holders":
			_record_holders()
		"player_cards":
			_player_cards()
		"edit_lines":
			_edit_lines()
		"shootout_setup":
			_shootout_setup()

## $FDC5A (§5): away values centred on column 9, home on 34, the label on 21; a row every
## two plane rows from screen row 10.
func _game_stats() -> void:
	_setup(9, 26, 10)
	var pg := _page("game_stats")
	_run(pg.get("static", []))
	var pen := _game.world.opt_pen
	var rows: Array = pg.get("rows_with_penalties" if pen else "rows_without_penalties", [])
	_max = 0x70 if pen else 0x30
	_step = 16
	for i in rows.size():
		var r: Dictionary = rows[i]
		var label: String = r["label"]
		_t(_b, int(r.get("label_x", center_x(21, label))), 2 * i, label)
		for team in 2:
			var v := _game_stat(r, _game.world.stats[team])
			_t(_b, center_x(34 if team == 0 else 9, v), 2 * i, v)
	_arrows(38, 8, 26, 0, 1)

func _game_stat(r: Dictionary, st: TeamStats) -> String:
	var f: String = r["format"]
	var names: Array = r.get("port", [])
	if f.begins_with("goals*100"):
		return "%d%%" % (st.goals * 100 / st.shots if st.shots > 0 else 0)
	var a := int(st.get(names[0])) if names.size() > 0 and st.get(names[0]) != null else 0
	var b := int(st.get(names[1])) if names.size() > 1 and st.get(names[1]) != null else 0
	if f.begins_with("PushTime"):
		return Hud.push_time(a).strip_edges()
	if f.begins_with("n/m ("):
		return "%d/%d (%d%%)" % [a, b, a * 100 / b if b > 0 else 0]
	if f.begins_with("n/m"):
		return "%d/%d" % [a, b]
	return str(a)

## $945A (§6): a category box, the team's players sorted by it. Playoff Stats (sub_9428,
## playoffs_records.md §4) is the same body over the user's playoff totals, titled
## "Playoff  Stats" at (7,4), without the team switch.
func _player_stats() -> void:
	_setup(13, 22, 13)
	var pg := _page("player_stats")
	var playoffs := _id == "playoff_stats"
	var ops: Array = pg.get("static", [])
	if playoffs:
		ops = []
		for e in pg.get("static", []):
			var note := String(e.get("note", ""))
			if note.begins_with("'A - Switch Teams'"):
				continue
			if note == "big title":
				e = e.duplicate(true)
				e["ops"][0]["at"] = [7, 4]
				e["ops"][1]["text"] = "Playoff  Stats"
			ops.append(e)
	_run(ops, ["category text"])
	var cat := _col
	var cats: Array = pg.get("categories", [])
	if cat + 1 < cats.size():
		_w.print_at(10, 8, cats[cat + 1]["ops"][0]["text"], 3, "stats0")
	if cat < 0:
		_t(_w, 17, 11, "Saves Shots Save %", 2, 1)
	else:
		var heads := ["   G", "   A", " Pts", " SOG", " PIM"]
		for c in 5:
			_t(_w, 17 + 4 * c, 11, heads[c], 2 if c == cat else 0, 1)
	var st := _game.world.stats[_team]
	var data := st.data
	var goalies := data.goalie_count if data else 2
	var n := data.players.size() if data else 0
	# The arrays: this game's, or $FFCD96's playoff totals (goals, assists, SOG, PIM).
	var goals := st.player_goals
	var assists := st.player_assists
	var shots_arr := st.player_shots
	var pim := st.player_pim
	if playoffs:
		var po: PackedInt32Array = _game.world.rules.league.po_stats
		goals = po.slice(0, 26)
		assists = po.slice(26, 52)
		shots_arr = po.slice(52, 78)
		pim = po.slice(78, 104)
	var order := []
	for slot in n:
		if cat < 0 and slot >= goalies:
			continue
		var p := data.player(slot)
		var g := slot < goalies
		var vals := [0 if g else goals[slot], assists[slot], 0, 0 if g else shots_arr[slot], pim[slot]]
		vals[2] = vals[0] + vals[1]
		var key := 0
		if cat < 0:
			key = maxi(shots_arr[slot] - goals[slot], 0)
		else:
			key = vals[cat]
		order.append([key * 256 + (255 - (p.jersey_number if p else 0)), slot, vals])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in order.size():
		var slot: int = order[i][1]
		var row := 2 * i
		_t(_b, 1, row, "%2d" % (i + 1), 3)
		_t(_b, 4, row, _short(_team, slot), 0)
		if cat < 0:
			var shots := shots_arr[slot]
			var saves := maxi(shots - goals[slot], 0)
			_t(_b, 17, row, "%5d %5d %3d%%" % [saves, shots, saves * 100 / shots if shots > 0 else 0], 2)
		else:
			for c in 5:
				_t(_b, 17 + 4 * c, row, "%4d" % order[i][2][c], 2 if c == cat else 0)
	_max = maxi(order.size() - 6, 0) * 16
	_step = 16
	_arrows(2, 11, 23, 2, 0)

## $8EB0 (§7): four rows an entry; it opens on the newest.
func _scoring_summary() -> void:
	_setup(10, 26, 10)
	_run(_page("scoring_summary").get("static", []))
	var recs: Array = _game.world.score_summary
	for e in recs.size():
		var r: Dictionary = recs[e]
		var row := 4 * e
		var team := 1 if r["away"] else 0
		var t := int(r["time"])
		_t(_b, 1, row, PERIODS[clampi(t >> 14, 0, 3)])
		_t(_b, 5, row, Hud.push_time(t & 0x3FFF))
		_t(_b, 12, row, _abbr(team))
		_t(_b, 16, row, _initial(team, int(r["scorer"])))
		_t(_b, 35, row, STRENGTH[clampi(int(r["strength"]), 0, 4)])
		for k in 2:
			var a := int(r["assist%d" % (k + 1)])
			if a >= 0:
				_t(_b, 18, row + 1 + k, _initial(team, a), 3)
	_open_at_newest(recs.size() * 32, 0x80, 32)
	_arrows(4, 9, 25, 2, 0)

func _open_at_newest(total: int, view: int, step: int) -> void:
	_max = maxi(total - view, 0)
	_step = step
	if _list.is_empty():
		# The page opens at the newest entries, sliding in from the top (d5ae -> d5b2).
		_list = [true]
		_scroll = total
		_target = _max
	_apply_scroll()

## $9142 (§8): three rows an entry.
func _penalty_summary() -> void:
	_setup(10, 25, 10)
	_run(_page("penalty_summary").get("static", []))
	var recs: Array = _game.world.rules.pen_sum
	for e in recs.size():
		var r: Dictionary = recs[e]
		var row := 3 * e
		var id := int(r["id"])
		var team := 1 if id & 0x80 else 0
		id &= 0x7F
		var t := int(r["time"])
		_t(_b, 1, row, PERIODS[clampi(t >> 14, 0, 3)])
		_t(_b, 5, row, Hud.push_time(t & 0x3FFF))
		_t(_b, 12, row, _abbr(team))
		_t(_b, 16, row, _initial(team, int(r["pnum"])))
		_t(_b, 35, row, "%2d" % GameRules.minutes(id))
		_t(_b, 19, row + 1, String(GameRules.entry(id)[2]), 3)
	_open_at_newest(recs.size() * 24, 0x78, 24)

## $89AC (§9): a line at a time (the goalies, then the seven RAM lines) with one attribute
## column; the page scrolls $80 px a line.
func _team_roster() -> void:
	_setup(13, 23, 14)
	var pg := _page("team_roster")
	_run(pg.get("static", []))
	var names: Array = pg.get("line_names", [])
	if _sel < names.size():
		_t(_w, 2, 9, names[_sel]["ops"][0]["text"], 3, 1)
	var cols: Array = pg.get("goalie_columns" if _sel == 0 else "skater_columns", [])
	_col = clampi(_col, 0, cols.size() - 1)
	_t(_w, 22, 9, cols[_col]["ops"][0]["text"], 3, 1)
	var st := _game.world.stats[_team]
	var data := st.data
	for l in 8:
		var row := 16 * l
		var entries := []
		if l == 0:
			for g in (data.goalie_count if data else 0):
				entries.append(["G", g])
		elif st.ram_lines.size() >= l * 8:
			var c := 4 if l >= 6 else 5
			for k in c:
				var v := st.ram_lines[(l - 1) * 8 + 1 + k]
				if v > 0:
					entries.append([POS_NAMES[k], v - 1])
		var lcols: Array = pg.get("goalie_columns" if l == 0 else "skater_columns", [])
		var col: Dictionary = lcols[clampi(_col, 0, lcols.size() - 1)]
		for i in entries.size():
			var slot: int = entries[i][1]
			var p := _player(_team, slot)
			_t(_b, 2, row + 2 * i, entries[i][0])
			if p:
				_t(_b, 6, row + 2 * i, "%2d %s" % [p.jersey_number % 100, p.full_name])
			_t(_b, 30, row + 2 * i, _roster_value(col, slot, p), 0)
	_max = 0x380
	_step = 0x80
	_target = _sel * 0x80
	if _list.is_empty():
		_list = [true]
		_scroll = _target
	_apply_scroll()

func _roster_value(col: Dictionary, slot: int, p: PlayerData) -> String:
	var st := _game.world.stats[_team]
	var head := String(col["ops"][0]["text"]).replace("[", "").replace("]", "").strip_edges()
	match String(col["kind"]):
		"status":
			var t := st.tmpdst[slot]
			match t:
				TeamStats.TMPDST_ON_ICE:
					return "Ice"
				TeamStats.TMPDST_BENCH:
					return "Bench"
				TeamStats.TMPDST_INJURED_PERIOD:
					return "Injury P"
				TeamStats.TMPDST_INJURED_GAME:
					return "Injury G"
			if t & 0x1000:
				return "Injury G"
			return Hud.push_time(t & 0x7FF).strip_edges() + (" C" if t & 0x4000 else "")
		"energy":
			return str(mini(st.energy[slot] / 0x28, 100))
		"handed":
			if p == null:
				return ""
			return "Righty" if p.handedness == PlayerData.Hand.RIGHT else "Lefty"
	if p == null:
		return ""
	if head.begins_with("Overall"):
		return str(p.overall())
	if head.begins_with("Weight"):
		return "%d lb" % roundi(p.weight_lbs)
	var f: String = RATING_FIELDS.get(head, "")
	return str(roundi(float(p.get(f)))) if f != "" else ""

## $9A2A (§10.1): the excitement levels in dB; the two record rows show the 80 dB a fresh
## battery save holds.
func _crowd_meter() -> void:
	_setup(9, 28, 0)
	_run(_page("crowd_meter").get("static", []), ["unit after"])
	var r := _game.world.rules
	var w := _game.world
	var avg := r.sum_excite / r.num_excite if r.num_excite > 0 else 0
	var vals := [w.crowd_excite, avg, r.max_excite]
	for i in 5:
		var v := r.crowd_record_value
		if i < 3:
			v = RinkBoards.sroot(maxi(vals[i], 0) * 4) + 0x41
		_t(_b, 28, 12 + 2 * i, "%3d dB" % v)

## $FD90C (§10.2): goals or shots by period for both teams, beside their logos.
func _period_stats() -> void:
	_setup(0, 28, 0)
	_run(_page("period_stats").get("static", []))
	var w := _game.world
	var ot := w.gsp >= 3
	var heads := [[12, "1"], [17, "2"], [22, "3"]]
	if ot:
		heads.append([26, "OT"])
	heads.append([32, "Total"])
	for h in heads:
		_t(_b, h[0], 9, h[1])
		_t(_b, h[0], 10, "<".repeat(String(h[1]).length()))
	_t(_b, 18, 7, "Shots" if _mode else "Goals")
	_t(_b, 15, 26, "[ For Goals" if _mode else "For Shots ]")
	for team in 2:
		var st := w.stats[team]
		var arr := st.period_shots if _mode else st.period_goals
		var y := 14 if team == 1 else 22
		var total := 0
		for k in 4:
			if k == 3 and not ot:
				break
			if w.gsp <= k and not (k == 3 and ot):
				continue
			total += arr[k]
			_t(_b, 11 + 5 * k, y, ("%3d" if arr[k] >= 100 else "%2d") % arr[k], 1)
		_t(_b, 33, y, "%2d" % total, 1)

## $80D4 (§11): the other games of the night, three rows a game.
func _other_scores() -> void:
	_setup(6, 26, 6)
	_run(_page("other_scores").get("static", []))
	var rules := _game.world.rules
	var games: Array = rules.other_games
	for i in games.size():
		var g: Dictionary = games[i]
		var row := 3 * i
		# The visitor (team2) first.
		for k in 2:
			var t := rules.league.team(g["team2" if k == 0 else "team1"])
			_t(_b, 6, row + k, t.city if t else "")
			_t(_b, 24, row + k, "%2d" % g["score2" if k == 0 else "score1"])
		_t(_b, 28, row + 1, PauseMenu.period_label(g["gsper"]))
	_max = maxi(3 * games.size() - 0x15, 0) * 8
	_step = 24
	if _scroll > 0:
		_t(_w, 4, 6, "{", 0, 1)
	if _scroll < _max:
		_t(_w, 4, 25, "}", 0, 1)

## $FBC14 (§15.2): the three record pages, empty as with a fresh battery save.
func _record_holders() -> void:
	_setup(0, 26, 0)
	var pg := _page("record_holders")
	_run(pg.get("static", []))
	var pages: Array = pg.get("pages", [])
	_sel = clampi(_sel, 0, pages.size() - 1)
	if not pages.is_empty():
		_run([pages[_sel]])

## $FA07E (§15.1): the team card, then a card a player (photo, number and position,
## Overall Rating, This Game); the battery-saved Records stay empty.
func _player_cards() -> void:
	_setup(0, 28, 0, "cards_bg")
	_run(_page("player_cards").get("static", []))
	var st := _game.world.stats[_team]
	var data := st.data
	var n := data.players.size() if data else 0
	_sel = wrapi(_sel, 0, n + 1)
	if data:
		_c(20 - data.city.length() / 2, 8, data.city)
		_c(20 - data.team_name.length() / 2, 9, data.team_name)
	_team_logo(_team, Vector2i(33, 8), "B")
	_c(22, 11, "  Records")
	_c(21, 12, "-----------")
	if _sel == 0:
		_team_logo(_team, Vector2i(1, 8), "B")
		var ti := st.team_index
		var ratings: Array = _page("player_cards").get("team_rating", {}).get("values", [])
		_c(8, 10, "Team")
		_c(8, 11, "Rating  %d" % (ratings[ti] if ti >= 0 and ti < ratings.size() else 0))
		_c(3, 14, "Starting Line")
		var first := st.ram_lines.slice(0, 8) if st.ram_lines.size() >= 8 else PackedInt32Array()
		var pos := ["G", "LD", "RD", "LW", "C", "RW"]
		for k in 6:
			_c(3, 16 + k, pos[k])
			if k < first.size() and first[k] > 0:
				_c(7, 16 + k, _last(_team, first[k] - 1))
		return
	var slot := _sel - 1
	var p := data.player(slot)
	_image("photos", Vector2i(1, 8), "B", _photo_rect(slot), _pal["photo"])
	var i := p.full_name.find(" ")
	_c(8, 10, p.full_name.substr(0, i) if i >= 0 else "")
	_c(8, 11, p.full_name.substr(i + 1) if i >= 0 else p.full_name)
	var goalie := slot < data.goalie_count
	var kind := " Goalie" if goalie else (" Defenseman" if p.position == PlayerData.Position.DEFENSE else " Forward")
	_c(3, 14, "%2d%s" % [p.jersey_number % 100, kind])
	_c(3, 16, "Overall")
	_c(3, 17, "Rating   %d" % p.overall())
	_c(21, 18, " This Game ")
	_c(21, 19, "-----------")
	if goalie:
		var shots := st.player_shots[slot]
		var saves := maxi(shots - st.player_goals[slot], 0)
		_c(22, 20, "Saves    %d" % saves)
		_c(22, 21, "Save %%   %d" % (saves * 100 / shots if shots > 0 else 0))
	else:
		_c(22, 20, "Goals    %d" % st.player_goals[slot])
		_c(22, 21, "Assists  %d" % st.player_assists[slot])

## Player Cards text: the cards font (remap 05 23 41..) in line 0.
func _c(x: int, y: int, text: String) -> int:
	return _b.print_at(x, y, text, 0, "cards0")

## sub_FAE26: the slot's photo, or a generic silhouette.
func _photo_rect(slot: int) -> Rect2:
	var t := _game.world.stats[_team].team_index
	var idx := -1
	var teams: Array = _photos.get("teams", [])
	if t >= 0 and t < teams.size():
		for e in teams[t]:
			if int(e["slot"]) == slot:
				idx = int(e["photo"])
	if idx < 0:
		var data := _game.world.stats[_team].data
		idx = 3 if data and slot < data.goalie_count else 0
	var per: int = _photos.get("per_row", 16)
	return Rect2((idx % per) * 48, (idx / per) * 48, 48, 48)

## $82DA (§13): the Line Editor. _sel is d5b8 (line * 8 + slot, slot 1-5).
func _edit_lines() -> void:
	_setup(0, 28, 0)
	var pg := _page("edit_lines")
	var st := _game.world.stats[_team]
	if _sel == 0:
		_sel = 1
	var line := _sel >> 3
	var slot := _sel & 7
	if _list.is_empty():
		_run(pg.get("static", []), ["position labels", "LD RD LW", "' Line'", "selected player"])
	else:
		_select_list_draw()
	var page := 0 if line <= 2 else (1 if line <= 4 else 2)
	for k in 5:
		_t(_b, 1, 14 + 2 * k, POS_NAMES[k], 0)
	for l in EDIT_PAGES[page]:
		var cx: int = EDIT_COLS[l][0]
		_t(_b, cx + 1, 12, _game.world.lines.line_name(l) + " Line", 0)
		for k in EDIT_COLS[l][1]:
			var v := st.ram_lines[l * 8 + 1 + k] if st.ram_lines.size() > l * 8 + 1 + k else 0
			var name := _last(_team, v - 1) if v > 0 else ""
			var cur: bool = l == line and k + 1 == slot
			_t(_b, cx, 14 + 2 * k, name, 3 if cur else 2, 1 if cur else 0)
	if _list.is_empty():
		var v := st.ram_lines[line * 8 + slot] if st.ram_lines.size() > line * 8 + slot else 0
		var p := _player(_team, v - 1)
		if p:
			var s := "%d %s" % [p.jersey_number, p.full_name]
			_t(_b, center_x(21, s), 8, s, 0, 1)
	if not _menu_items.is_empty():
		_draw_exit_menu()

## Select Player: the defensemen for LD/RD, the forwards for LW/C/RW (roster order
## goalies, forwards, defense), six rows with an attribute column.
func _select_list_draw() -> void:
	_b.frame(1, 0, 18, 3, "framer_stats", 1)
	_t(_b, 2, 1, "{Select Player}", 0)
	_b.frame(21, 0, 18, 3, "framer_stats", 1)
	var cols: Array = _page("team_roster").get("skater_columns", [])
	_t(_b, 22, 1, cols[clampi(_col, 0, cols.size() - 1)]["ops"][0]["text"], 0)
	var top := clampi(_list_cursor - 5, 0, maxi(_list.size() - 6, 0))
	for i in mini(6, _list.size()):
		var slot: int = _list[top + i]
		var p := _player(_team, slot)
		var cur: bool = top + i == _list_cursor
		var col: Dictionary = cols[clampi(_col, 0, cols.size() - 1)]
		_t(_b, 2, 2 + i, "%2d %s" % [p.jersey_number % 100, p.full_name] if p else "", 2 if cur else 0, 0)
		_t(_b, 30, 2 + i, _roster_value(col, slot, p), 2 if cur else 0)

func _select_candidates() -> Array:
	var data := _game.world.stats[_team].data
	var out := []
	if data == null:
		return out
	var defense := (_sel & 7) <= 2
	var f0 := data.goalie_count
	var d0 := f0 + data.forward_count
	var r := range(d0, data.players.size()) if defense else range(f0, d0)
	for slot in r:
		out.append(slot)
	return out

func _draw_exit_menu() -> void:
	_w.frame(9, 12, 22, 6, "framer_stats", 1)
	for i in _menu_items.size():
		_t(_w, 11, 13 + i, _menu_items[i]["raw"], 0 if i == _menu_cursor else 2, 1)

## $FC620 (§13.3): five shooters and the goalie of the shootout lists.
func _shootout_setup() -> void:
	_setup(0, 28, 0)
	var pg := _page("shootout_setup")
	var so := _game.world.shootout
	if _list.is_empty():
		_run(pg.get("static", []), ["Select Player"])
		var ti := _game.world.stats[_team].team_index
		if ti >= 0:
			_b.bitmap(15, 1, "team_plates", 0, 2 * ti, 11, 2)
	else:
		_select_list_draw()
	if so.so_list.size() <= _team:
		return
	var lst: Array = so.so_list[_team]
	for k in 5:
		_t(_b, 7, 14 + 2 * k, _last(_team, lst[k]), 2, 1 if _sel == k else 0)
	_t(_b, 26, 14, _last(_team, lst[5]), 2, 1 if _sel == 5 else 0)
	if _list.is_empty():
		var p := _player(_team, lst[_sel])
		if p:
			var s := "%d %s" % [p.jersey_number, p.full_name]
			_t(_b, center_x(21, s), 8, s, 0, 1)

# --- input ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _id == "":
		return
	if _scroll != _target:
		_scroll += 2 if _target > _scroll else -2
		_apply_scroll()
		if _id in ["game_stats", "player_stats", "playoff_stats", "other_scores", "scoring_summary", "penalty_summary"]:
			_build_arrows_only()
	var p := "p%d_" % (_pad + 1)
	if not _armed:
		_armed = not Input.is_action_pressed(p + "start")
		return
	var just := func(a: String) -> bool: return Input.is_action_just_pressed(p + a)
	var held := func(a: String) -> bool: return Input.is_action_pressed(p + a)
	if _id == "edit_lines" or _id == "shootout_setup":
		_editor_input(just)
		return
	if just.call("start"):
		_close()
		return
	match _id:
		"player_stats", "playoff_stats":
			if just.call("a") and _id == "player_stats":
				_team = 1 - _team
				_scroll = 0
				_target = 0
				_build()
			elif just.call("left") or just.call("right"):
				_col = clampi(_col + (1 if just.call("right") else -1), -1, 4)
				_scroll = 0
				_target = 0
				_build()
		"team_roster":
			if just.call("a"):
				_team = 1 - _team
				_build()
			elif just.call("left") or just.call("right"):
				_col += 1 if just.call("right") else -1
				_build()
			elif just.call("up") or just.call("down"):
				_sel = clampi(_sel + (1 if just.call("down") else -1), 0, 7)
				_build()
		"period_stats":
			if just.call("right") or just.call("left"):
				_mode = 1 if just.call("right") else 0
				_build()
		"record_holders":
			if just.call("right") or just.call("left"):
				_sel += 1 if just.call("right") else -1
				_build()
		"player_cards":
			if just.call("right") or just.call("c"):
				_sel += 1
				_build()
			elif just.call("left"):
				_sel -= 1
				_build()
			elif just.call("a"):
				_team = 1 - _team
				_sel = 0
				_build()
	if _id in ["game_stats", "player_stats", "playoff_stats", "other_scores", "scoring_summary", "penalty_summary"] \
			and _scroll == _target:
		if held.call("down") and _target < _max:
			_target = mini(_target + _step, _max)
		elif held.call("up") and _target > 0:
			_target = maxi(_target - _step, 0)

func _build_arrows_only() -> void:
	_build()

## The Line Editor and Shootout SetUp: move between slots, C opens the player list (C
## again assigns), Start opens the exit menu (Line Editor) or goes back.
func _editor_input(just: Callable) -> void:
	var editor := _id == "edit_lines"
	if not _menu_items.is_empty():
		if just.call("down") or just.call("up"):
			_menu_cursor = clampi(_menu_cursor + (1 if just.call("down") else -1), 0, _menu_items.size() - 1)
			_build()
		elif just.call("c") or just.call("start"):
			_exit_menu_choose()
		return
	if not _list.is_empty():
		if just.call("down") or just.call("up"):
			_list_cursor = clampi(_list_cursor + (1 if just.call("down") else -1), 0, _list.size() - 1)
			_build()
		elif just.call("left") or just.call("right"):
			_col = maxi(_col + (1 if just.call("right") else -1), 0)
			_build()
		elif just.call("c"):
			var slot: int = _list[_list_cursor]
			if editor:
				_game.world.lines.edit_line(_team, _sel >> 3, _sel & 7, slot)
			else:
				_game.world.shootout.so_list[_team][_sel] = slot
			_list = []
			_build()
		elif just.call("start"):
			_list = []
			_build()
		return
	if just.call("start"):
		if editor:
			var t: String = "line_editor_exit" if not saved_lines.is_empty() else "line_editor_exit_nosave"
			_menu_items = _menus.get("tables", {}).get(t, {}).get("items", [])
			_menu_cursor = 0
			_build()
		else:
			_close()
		return
	if just.call("c"):
		if editor:
			_list = _select_candidates()
		else:
			var data := _game.world.stats[_team].data
			_list = []
			if _sel == 5:
				for g in (data.goalie_count if data else 0):
					_list.append(g)
			else:
				for s in range(data.goalie_count if data else 0, data.players.size() if data else 0):
					_list.append(s)
		_list_cursor = 0
		_col = 0
		_build()
		return
	if editor:
		var line := _sel >> 3
		var slot := _sel & 7
		var page := 0 if line <= 2 else (1 if line <= 4 else 2)
		if just.call("down") or just.call("up"):
			var c: int = EDIT_COLS[line][1]
			slot = clampi(slot + (1 if just.call("down") else -1), 1, c)
		elif just.call("left") or just.call("right"):
			var lines: Array = EDIT_PAGES[page]
			var i := lines.find(line) + (1 if just.call("right") else -1)
			if i < 0 and page > 0:
				line = EDIT_PAGES[page - 1][-1]
			elif i >= lines.size() and page < 2:
				line = EDIT_PAGES[page + 1][0]
			elif i >= 0 and i < lines.size():
				line = lines[i]
			slot = mini(slot, EDIT_COLS[line][1])
		_sel = line * 8 + slot
		_build()
	else:
		if just.call("down") or just.call("up"):
			_sel = clampi(_sel + (1 if just.call("down") else -1), 0, 5)
			_build()
		elif just.call("left"):
			_sel = 0
			_build()
		elif just.call("right"):
			_sel = 5
			_build()

## $8812: Exit, Set Original lines (sub_171CE), Save / Load Team Line.
func _exit_menu_choose() -> void:
	var id: String = _menu_items[_menu_cursor]["id"]
	var st := _game.world.stats[_team]
	match id:
		"close":
			_menu_items = []
			_close()
			return
		"lines_set_original":
			_game.world.roster.copy_lines(_team)
		"lines_save_team":
			saved_lines = [st.team_index, st.ram_lines.duplicate()]
		"lines_load_team":
			if not saved_lines.is_empty() and saved_lines[0] == st.team_index:
				st.ram_lines = (saved_lines[1] as PackedInt32Array).duplicate()
	_menu_items = []
	_build()
