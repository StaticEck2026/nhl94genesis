extends Node2D
## Retail's Matchups screen (sub_FCC76 L969615; spec docs/specs/ui_frontend.md §5), between
## Game Setup and the game: Ron Barr's commentary typed a word at a time, and seven pages
## comparing the two teams (Overall, then the starting line's centre, wingers,
## defencemen and goalie), with the ratings, the advantage arrows and the HOT / COLD
## starters. The game's form table is made here (Create_HotCold_Table for both teams),
## so the ratings already include it.
## Controls: C next page, A previous, Start begins (with A + C held: 30-second periods);
## a page turns by itself after 270 idle frames. In a demo the screen leaves 480 frames
## after the script ends.

const DIR := "res://assets/ui/frontend/"
const MENUS := "res://assets/ui/menus/"
const GAME_SCENE := "res://scenes/game.tscn"
const PAGES := 7
const PAGE_FRAMES := 0x10E
const END_FRAMES := 0x1E0
const WORD_FRAMES := 10
const STOP_FRAMES := 40
const ARROW_FRAMES := 7
## The commentary window: x 9, rows 4-10, 29 wide.
const TEXT_X := 9
const TEXT_Y := 4
const TEXT_ROWS := 7
const TEXT_W := 29

var _fe: Dictionary = {}
var _pal: Dictionary = {}
var _photos: Dictionary = {}
var _m: MatchConfig
var _b: WindowPlane
var _a: WindowPlane
var _pal_img: Image
var _pal_tex: ImageTexture
## [home, visitor] TeamData, ROM ids and the form tables.
var _team: Array[TeamData] = []
var _id: Array[int] = []
var _form: Array = []
## Per team: the starting line's six roster slots (G LD RD LW C RW) and the hot and
## cold starters.
var _line: Array = []
var _hot: Array[int] = []
var _cold: Array[int] = []

var _page := 0
var _page_timer := PAGE_FRAMES
var _arrow := 0
var _arrow_timer := ARROW_FRAMES
## The typewriter: the words still to type ("\n" breaks a line), the text rows, the
## cursor column and the delay.
var _words: Array = []
var _rows: Array[String] = []
var _col := 0
var _delay := 0
var _end_timer := -1

func _ready() -> void:
	ScreenMode.restore(get_tree())
	_m = Sim.match
	for e in [[DIR + "frontend.json", "_fe"], [MENUS + "palettes.json", "_pal"], [MENUS + "photos.json", "_photos"]]:
		if FileAccess.file_exists(e[0]):
			set(e[1], JSON.parse_string(FileAccess.get_file_as_string(e[0])))
	if _fe.is_empty() or _m.home_team == null or _m.away_team == null:
		_begin()
		return
	WindowPlane.register("mu_font1", DIR + "font_matchups_alt_idx.png", WindowPlane.stats_chars())
	WindowPlane.register("mu_framer", DIR + "framer_matchups_idx.png")
	for k in ["ron_barr", "matchups_title", "hot", "cold"]:
		WindowPlane.register(k, DIR + k + "_idx.png")
	WindowPlane.register("stats_bg", MENUS + "stats_bg_idx.png")
	WindowPlane.register("team_logos", MENUS + "team_logos_idx.png")
	WindowPlane.register("photos", MENUS + "photos_idx.png")
	_team = [_m.home_team, _m.away_team]
	_id = [_m.home_team.team_index, _m.away_team.team_index]
	# sub_FCC76: the game's form, both teams (the port seeds its RNG here as retail seeds
	# from the HV counter at Start).
	_form = RosterLogic.make_form(RetailRng.new(randi()))
	_m.form = _form
	for t in 2:
		var ln: PackedInt32Array = _team[t].line(0)
		var slots := []
		for k in 6:
			slots.append(ln[k] - 1)
		_line.append(slots)
		_hot_cold(t)
	_pal_img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	var back := ColorRect.new()
	back.size = Vector2(320, 224)
	add_child(back)
	_b = WindowPlane.new()
	_b.origin = Vector2.ZERO
	_b.material = PaletteBank.material(_pal_tex, false, true)
	add_child(_b)
	_a = WindowPlane.new()
	_a.origin = Vector2.ZERO
	_a.material = PaletteBank.material(_pal_tex, false, true)
	add_child(_a)
	_backdrop = back
	_plane_b()
	_script()
	_draw_page()
	if Sim.menu_sfx:
		Sim.menu_sfx.play_song(0x7A)

var _backdrop: ColorRect

# --- the data ------------------------------------------------------------------------------

## sub_F71F0: a starter's form, the sum of his bytes 3-15 without 9 and 13.
func _form_score(t: int, slot: int) -> int:
	var s := 0
	if slot < 0:
		return 0
	for j in range(3, 16):
		if j == 9 or j == 13:
			continue
		s += _form[t][slot * 16 + j]
	return s

## sub_F71A2: the starters sorted by form, highest first: the first is hot, the last cold.
func _hot_cold(t: int) -> void:
	var order: Array = _line[t].duplicate()
	order.sort_custom(func(x: int, y: int) -> bool: return _form_score(t, x) > _form_score(t, y))
	_hot.append(order[0])
	_cold.append(order[order.size() - 1])

func _player(t: int, slot: int) -> PlayerData:
	return _team[t].player(slot) if slot >= 0 else null

## A page's slot for a team (unk_FD4B8: 0 4 3 5 1 2 0 of the starting line).
func _slot(t: int) -> int:
	var b: int = _fe["matchups"]["pages"]["slot_byte"][_page]
	return _line[t][b]

## sub_FE172 (page 0) or the player's Overall with this game's form (sub_FD1FE).
func _rating(t: int) -> int:
	if _page == 0:
		return int(_fe["teams"][_id[t]]["rating"])
	var s := _slot(t)
	var p := _player(t, s)
	if p == null:
		return 0
	return p.overall(_form[t].slice(s * 16, s * 16 + 16))

# --- drawing -------------------------------------------------------------------------------

func _plane_b() -> void:
	_b.bitmap(0, 0, "stats_bg", 0, 0, 40, 28)
	# The frames are on plane B too: their see-through edges show the backdrop.
	for f in [[6, 3, 33, 9], [1, 14, 8, 8], [31, 14, 8, 8]]:
		_b.erase(f[0], f[1], f[2], f[3])
		_b.frame(f[0], f[1], f[2], f[3], "mu_framer", 3)

## CRAM: line 0 of the SPORTS background, line 1 the home logo's palette (page 0) or the
## photos', line 2 the visitor logo's, line 3 Ron Barr's.
func _palette() -> void:
	var stats: Array = _pal["stats"]
	var logos: Array = _pal["team_logos"]
	var barr: Array = _fe["images"]["ron_barr_idx.png"]["palette"][3]
	var lines := [stats[0], logos[_id[0]] if _page == 0 else _pal["photo"], logos[_id[1]], barr]
	for y in 4:
		for x in 16:
			_pal_img.set_pixel(x, y, PaletteBank.cram(int(lines[y][x])))
	_pal_tex.update(_pal_img)
	_backdrop.color = PaletteBank.cram(int(stats[0][0]))

func _draw_page() -> void:
	_palette()
	_a.clear()
	_a.bitmap(1, 1, "ron_barr", 0, 0, 8, 9)
	_a.bitmap(12, 13, "matchups_title", 0, 0, 16, 2, 3)
	_a.print_at(16, 17, "ADVANTAGE:", 0, "stats0")
	var labels: Dictionary = _fe["matchups"]["pages"]["label_strings"]
	var label: String = labels["page0_list"][9] if _page == 0 else labels["positions"][_page - 1]
	_a.print_at(13, 19, label, 0, "mu_font1")
	# The pictures: visitor (t 1) left, home (t 0) right.
	for t in 2:
		var x := 32 if t == 0 else 2
		if _page == 0:
			_a.bitmap(x, 15, "team_logos", (_id[t] % 4) * 6, (_id[t] / 4) * 6, 6, 6, 1 if t == 0 else 2)
		else:
			var idx := _photo(t, _slot(t))
			var per: int = _photos.get("per_row", 16)
			_a.bitmap(x, 15, "photos", (idx % per) * 6, (idx / per) * 6, 6, 6, 1)
	var rv := _rating(1)
	var rh := _rating(0)
	_a.print_at(4, 22, "%2d" % rv, 0, "mu_font1")
	_a.print_at(34, 22, "%2d" % rh, 0, "mu_font1")
	_draw_arrows()
	# sub_FD89A: the names, visitor at x 0, home ending by column 39.
	if _page > 0:
		for t in 2:
			var p := _player(t, _slot(t))
			if p == null:
				continue
			var i := p.full_name.find(" ")
			var name := "%s %s" % [Hud.jersey(p.jersey_number), p.full_name.substr(i + 1) if i >= 0 else p.full_name]
			_a.print_at(0 if t == 1 else mini(35, 40 - name.length()), 23, name, 0, "stats0")
		# sub_FF8DE: HOT / COLD under a page's player.
		for t in 2:
			var x := 32 if t == 0 else 2
			var s := _slot(t)
			if s == _hot[t]:
				_a.bitmap(x, 25, "hot", 0, 0, 6, 2)
			elif s == _cold[t]:
				_a.bitmap(x, 25, "cold", 0, 0, 6, 3)
	_draw_text()

## sub_FAE26: the slot's photo, or a generic one.
func _photo(t: int, slot: int) -> int:
	var teams: Array = _photos.get("teams", [])
	if _id[t] < teams.size():
		for e in teams[_id[t]]:
			if int(e["slot"]) == slot:
				return int(e["photo"])
	return 3 if _team[t] and slot < _team[t].goalie_count else 0

## sub_FD4CA: 0-3 arrows towards the better side, one more every 7 frames.
func _draw_arrows() -> void:
	var ar: Dictionary = _fe["matchups"]["arrows"]
	var rv := _rating(1)
	var rh := _rating(0)
	var s: String = ar["even"]
	if rh > rv:
		s = ar["home_higher"][_arrow]
	elif rv > rh:
		s = ar["visitor_higher"][_arrow]
	_a.print_at(19, 22, s, 0, "mu_font1")

func _draw_text() -> void:
	for i in TEXT_ROWS:
		var row: String = _rows[i] if i < _rows.size() else ""
		_a.print_at(TEXT_X, TEXT_Y + i, row + " ".repeat(TEXT_W - row.length()), 0, "stats0")

# --- the commentary ------------------------------------------------------------------------

## sub_17718: the script, its tokens filled in.
func _script() -> void:
	var sc: Dictionary = _fe["matchups"]["script"]
	var msgs: Dictionary = sc["messages"]
	var order := ["1B", "1D", "1A", "1D"]
	# $F7318: who has been playing well lately.
	var d := 0
	for k in 6:
		d += _form_score(1, _line[1][k]) - _form_score(0, _line[0][k])
	var better := 0 if d < 0 else 1
	if absi(d) >= 0xBD:
		order += ["23", "1D"]
	elif absi(d) >= 0x5E:
		order += ["22", "1D"]
	order += ["1E", "1D"]
	if _id[0] != _id[1]:
		order += ["1F", "1D"]
	order += ["20", "1D", "21"]
	for id in order:
		if id == "1D":
			_words.append("\n")
			continue
		var text: String = msgs[id]
		# The "For <team>" opening of the hot / cold lines stands on its own row.
		if id == "1E" or id == "1F":
			text = text.substr(0, 5) + "\n" + text.substr(6)
		_words.append_array(_expand(text, better))
		if id != order[order.size() - 1]:
			_words.append("\n")

## The words of a message. A token's text is one word (a name never breaks).
func _expand(text: String, better: int) -> Array:
	var out := []
	var word := ""
	for ch in text:
		if ch == " ":
			out.append(word)
			word = ""
		elif ch == "\n":
			out.append(word)
			out.append("\n")
			word = ""
		else:
			word += _token(ch, better)
	out.append(word)
	return out

func _token(ch: String, better: int) -> String:
	match ch:
		"^":
			return _team[0].arena_name
		";":
			return _team[1].arena_name
		"_", "{":
			return _team[0].city
		"+", "}":
			return _team[1].city
		"=":
			return _team[0].team_name if _team[0].team_name != "" else "Home"
		"*":
			return _team[1].team_name if _team[1].team_name != "" else "Visitors"
		"#", "%":
			return ""
		"<":
			return _full(0, _hot[0])
		">":
			return _full(1, _hot[1])
		"|":
			return _full(0, _cold[0])
		"\\":
			return _full(1, _cold[1])
		"@":
			return "%d" % 80
		"$":
			return _team[better].city
	return ch

func _full(t: int, slot: int) -> String:
	var p := _player(t, slot)
	return p.full_name if p else ""

## One word every 10 frames, 40 more after a ',' or '.'; held down skips the delays.
func _type_step() -> void:
	if _words.is_empty():
		return
	if _delay > 0 and not _held("down"):
		_delay -= 1
		return
	var w: String = _words.pop_front()
	if _rows.is_empty():
		_rows.append("")
	if w == "\n":
		_new_row()
	else:
		var cur: String = _rows[_rows.size() - 1]
		var need := w.length() + (1 if _col > 0 else 0)
		if _col + need > TEXT_W:
			_new_row()
			cur = ""
			need = w.length()
		_rows[_rows.size() - 1] = cur + (" " if _col > 0 else "") + w
		_col += need
		_delay = WORD_FRAMES + (STOP_FRAMES if w.ends_with(",") or w.ends_with(".") else 0)
	if _words.is_empty():
		_end_timer = END_FRAMES
	_draw_text()

## sub_179D2: the next row, scrolling the window up when it is full.
func _new_row() -> void:
	_rows.append("")
	_col = 0
	if _rows.size() > TEXT_ROWS:
		_rows.pop_front()

# --- input ---------------------------------------------------------------------------------

func _held(b: String) -> bool:
	for k in 4:
		if Input.is_action_pressed("p%d_%s" % [k + 1, b]):
			return true
	return false

func _pressed(b: String) -> bool:
	for k in 4:
		if Input.is_action_just_pressed("p%d_%s" % [k + 1, b]):
			return true
	return false

func _physics_process(_delta: float) -> void:
	if _a == null:
		return
	_type_step()
	_arrow_timer -= 1
	if _arrow_timer <= 0:
		_arrow_timer = ARROW_FRAMES
		if _arrow < 5:
			_arrow += 1
			_draw_arrows()
	if _pressed("start"):
		# StartGame L29756: A + C held with Start, 30-second periods.
		if _held("a") and _held("c"):
			_m.perlen = 3
		_begin()
		return
	if _pressed("c"):
		_turn(1)
	elif _pressed("a"):
		_turn(-1)
	else:
		_page_timer -= 1
		if _page_timer <= 0:
			_turn(1)
	if _end_timer > 0:
		_end_timer -= 1
		if _end_timer == 0 and _m.players == 0:
			_begin()

func _turn(d: int) -> void:
	_page = posmod(_page + d, PAGES)
	_page_timer = PAGE_FRAMES
	_arrow = 0
	_arrow_timer = ARROW_FRAMES
	_draw_page()

func _begin() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
