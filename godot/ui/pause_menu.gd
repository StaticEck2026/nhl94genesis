extends CanvasLayer
## Retail's menu engine (sub_7E36 / sub_7E46 / sub_7EF2 / sub_7E88, spec
## docs/specs/ui_menus.md §2) for the pause screen (PauseMode L30217) and every
## intermission (L47614). The tables come from assets/ui/menus/menus.json. The screen is
## the side view with its scoreboard (sub_7DCE: SetHor); the menu is a 22 x 6 Framer at
## (5,12) with four visible rows from (7,13), the cursor row in line 0 and the others in
## line 1, '{' / '}' arrows at (6,13) / (6,16) when more rows are above / below. Up and
## down repeat after 16 frames, then every 5; C runs the row's handler; Start or row 0
## closes. The pause menu answers only the pad that paused; at an intermission any pad
## drives it, and the team of the pad that last pressed owns Change Goalie and Edit
## Lines (sub_7E0E). Playoff Stats is left out (no playoffs); "Quit to setup" is the
## port's own last row on the pause menu.

signal quit_requested
## The intermission menu closed through row 0 or Start.
signal intermission_closed

const MENUS := "res://assets/ui/menus/menus.json"
const BOX := Rect2i(5, 12, 22, 6)
const ROWS_X := 7
const ROWS_Y := 13
const VISIBLE := 4
## Handler ids the port leaves out.
const DROPPED := ["playoff_stats"]
## How long the Timeout box stays up (waitx $78).
const TIMEOUT_FRAMES := 0x78

var _plane: WindowPlane
var _pages: StatsPages
var _replay: ReplayView
var _menus := {}
## "" closed, "pause" or "intermission".
var _mode := ""
var _table := ""
var _items: Array = []
var _cursor := 0
var _top := 0
## The pad whose team owns the menu (0 or 1).
var _pad := 0
## "" the menu, "change_goalie", "timeout".
var _sub := ""
var _sub_cursor := 0
var _sub_frames := 0
var _repeat := [0, 0]
## The intermission ticker (NewTicker2 / NewTicker3pt2): the other game shown and the
## frames left of its 150-frame showing and the 60 blank ones after it.
var _ticker := -1
var _ticker_frames := 0
const TICKER_SHOW := 150
const TICKER_GAP := 60

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	offset = ScreenMode.H32_OFFSET
	if FileAccess.file_exists(MENUS):
		_menus = JSON.parse_string(FileAccess.get_file_as_string(MENUS))
	_plane = WindowPlane.new()
	_plane.name = "MenuPlane"
	add_child(_plane)
	_pages = StatsPages.new()
	_pages.name = "Pages"
	add_child(_pages)
	_pages.closed.connect(_on_page_closed)
	_replay = ReplayView.new()
	_replay.name = "Replay"
	add_child(_replay)
	_replay.finished.connect(_on_replay_finished)
	visible = false

func _game() -> HockeyGame:
	return get_parent() as HockeyGame

func is_open() -> bool:
	return _mode != ""

# --- opening and closing ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var game := _game()
	if game == null or _mode != "" or game.hold:
		return
	for k in 2:
		if event.is_action_pressed("p%d_start" % (k + 1)):
			get_viewport().set_input_as_handled()
			open_pause(k)
			return

## PauseMode: the pausing pad's team picks the table.
func open_pause(pad: int) -> void:
	var game := _game()
	if game == null:
		return
	var w := game.world
	_pad = pad
	var table := "pause"
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		table = "pause_shootout"
	elif w.stats[team()].flags30 & TeamStats.F30_TIMEOUT:
		table = "pause_timeout_used"
	get_tree().paused = true
	w.pause_screen = true
	_open("pause", table)

## Intermission: the table by gsp (unk_131CC), the shootout's in shootout mode.
func open_intermission(gsp: int, final: bool = false) -> void:
	var game := _game()
	if game == null:
		return
	var w := game.world
	var tables: Array = _menus.get("intermission_index", {}).get("tables", [])
	var table := "intermission_final"
	if final:
		table = "intermission_final"
	elif w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		table = "intermission_shootout"
	elif gsp < tables.size():
		table = tables[gsp]
	_pad = 0 if w.cont_team[0] != 0 or w.cont_team[1] == 0 else 1
	_open("intermission", table)

func _open(mode: String, table: String) -> void:
	_mode = mode
	_sub = ""
	_cursor = 0
	_top = 0
	_set_table(table)
	_ticker = 0 if mode == "intermission" else -1
	_ticker_frames = TICKER_SHOW + TICKER_GAP
	visible = true
	_redraw_game()
	_draw()

func _set_table(table: String) -> void:
	_table = table
	_items = []
	for it in _menus.get("tables", {}).get(table, {}).get("items", []):
		if not it["id"] in DROPPED:
			_items.append(it)
	if _mode == "pause":
		_items.append({"id": "quit", "raw": "  Quit to setup   "})

## Closing the pause menu resumes play (PrintScores1 on the way out); closing the
## intermission menu lets the game go on.
func close() -> void:
	var game := _game()
	var mode := _mode
	_mode = ""
	visible = false
	_pages.hide_page()
	if game == null:
		return
	if mode == "pause":
		game.world.pause_screen = false
		get_tree().paused = false
		game.world.rules.print_scores1()
		_redraw_game()
	elif mode == "intermission":
		intermission_closed.emit()

## The game holds (paused tree): refresh its views by hand.
func _redraw_game() -> void:
	var game := _game()
	if game:
		game.stepped.emit()

## The team whose menu this is (sub_7E0E).
func team() -> int:
	var game := _game()
	return game.world.pause_team(_pad) if game else 0

# --- input --------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _mode == "" or _pages.is_open() or _replay.is_open():
		return
	if _mode == "intermission" and _sub == "":
		_step_ticker()
	if _sub == "timeout":
		_sub_frames -= 1
		if _sub_frames <= 0:
			_sub = ""
			_draw()
		return
	var pads := [_pad] if _mode == "pause" else [0, 1]
	for k in pads:
		var p := "p%d_" % (k + 1)
		var step := _repeat_step(k, p)
		if Input.is_action_just_pressed(p + "start"):
			if _mode == "intermission":
				_pad = k
			_on_start()
			return
		if step != 0:
			if _mode == "intermission":
				_pad = k
			_move(step)
			return
		if Input.is_action_just_pressed(p + "c"):
			if _mode == "intermission":
				_pad = k
			_choose()
			return

## sub_11318: a press acts at once; held, it repeats after 16 frames, then every 5.
func _repeat_step(k: int, p: String) -> int:
	var dir := 0
	if Input.is_action_pressed(p + "down"):
		dir = 1
	elif Input.is_action_pressed(p + "up"):
		dir = -1
	if dir == 0:
		_repeat[k] = 0
		return 0
	if Input.is_action_just_pressed(p + ("down" if dir > 0 else "up")):
		_repeat[k] = 0xF
		return dir
	_repeat[k] -= 1
	if _repeat[k] < 0:
		_repeat[k] = 4
		return dir
	return 0

func _move(step: int) -> void:
	if _sub == "change_goalie":
		_sub_cursor = clampi(_sub_cursor + step, 0, _goalie_count())
	else:
		_cursor = clampi(_cursor + step, 0, maxi(_items.size() - 1, 0))
	_draw()

func _on_start() -> void:
	if _sub == "change_goalie":
		_pick_goalie()
		return
	close()

## sub_7E88 C: run the row's handler; row 0 closes.
func _choose() -> void:
	if _sub == "change_goalie":
		_pick_goalie()
		return
	if _items.is_empty():
		return
	var id: String = _items[_cursor]["id"]
	var game := _game()
	match id:
		"close":
			close()
			return
		"quit":
			_mode = ""
			visible = false
			game.world.pause_screen = false
			get_tree().paused = false
			quit_requested.emit()
			return
		"change_goalie":
			_sub = "change_goalie"
			_sub_cursor = game.world.goalie.goalie_row(team())
		"timeout":
			# $9D7A: the timeout is used; the menu loses the row, the cursor moves up.
			if game.world.timeout(team()):
				_set_table("pause_timeout_used")
				_cursor = maxi(_cursor - 1, 0)
				_top = maxi(_top - 1, 0)
				_sub = "timeout"
				_sub_frames = TIMEOUT_FRAMES
		"goalie_control_toggle":
			game.world.toggle_goalie_control(_pad)
		"instant_replay":
			_plane.clear()
			game.world.pause_screen = false
			_replay.open(game, _pad)
			return
		_:
			_plane.clear()
			_pages.open_page(id, game, team(), _pad)
			return
	_draw()

func _on_page_closed() -> void:
	_draw()

## The replay's prompt: Start goes straight back to the game (cursor 0, doshot bit 1),
## B back to the pause menu.
func _on_replay_finished(to_game: bool) -> void:
	var game := _game()
	if to_game and _mode == "pause":
		_cursor = 0
		close()
		return
	game.world.pause_screen = _mode == "pause"
	_redraw_game()
	_draw()

# --- drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	var game := _game()
	if game == null:
		return
	_plane.material = game.palette_material(false)
	_plane.clear()
	match _sub:
		"change_goalie":
			_draw_change_goalie()
		"timeout":
			_draw_timeout()
		_:
			_draw_menu()
			_draw_ticker()

## sub_7E46 / sub_7EF2.
func _draw_menu() -> void:
	var game := _game()
	_cursor = clampi(_cursor, 0, maxi(_items.size() - 1, 0))
	if _cursor < _top:
		_top = _cursor
	if _cursor - (VISIBLE - 1) > _top:
		_top = _cursor - (VISIBLE - 1)
	_plane.frame(BOX.position.x, BOX.position.y, BOX.size.x, BOX.size.y)
	if _top > 0:
		_plane.print_at(BOX.position.x + 1, ROWS_Y, "{", 1)
	for i in VISIBLE:
		var row := _top + i
		if row >= _items.size():
			break
		var it: Dictionary = _items[row]
		var text: String = it["raw"]
		if it["id"] == "goalie_control_toggle":
			var auto: bool = game.world.auto_goalie[_pad]
			var g: Dictionary = _menus.get("goalie_toggle", {})
			text = g.get("auto" if auto else "manual", {}).get("text", "Auto Goalie" if auto else "Manual Goalie")
		_plane.print_at(ROWS_X, ROWS_Y + i, text, 0 if row == _cursor else 1)
	if _top + VISIBLE < _items.size():
		_plane.print_at(BOX.position.x + 1, ROWS_Y + VISIBLE - 1, "}", 1)

func _step_ticker() -> void:
	var games: Array = _game().world.rules.other_games
	if _ticker < 0 or games.is_empty():
		return
	_ticker_frames -= 1
	if _ticker_frames == TICKER_GAP or _ticker_frames <= 0:
		if _ticker_frames <= 0:
			_ticker = (_ticker + 1) % games.size()
			_ticker_frames = TICKER_SHOW + TICKER_GAP
		_draw()

## sub_134E4 / NewTicker3pt2 (ui_ingame.md §8.1): Framer 26 x 5 at (3,23), the heading and
## the period on row 24 in line 1, the two cities and scores on rows 25 and 26.
func _draw_ticker() -> void:
	var games: Array = _game().world.rules.other_games
	if _mode != "intermission" or _ticker < 0 or games.is_empty() or _ticker_frames <= TICKER_GAP:
		return
	var g: Dictionary = games[_ticker % games.size()]
	_plane.frame(3, 23, 26, 5)
	_plane.print_at(4, 24, " ".repeat(24), 1)
	_plane.print_at(4, 24, "EA Hockey Night", 1)
	var labels := ["1\u0012", "2\u0013", "3\u0014", "OT", " F"]
	var per: int = g["per"]
	var lab: String = labels[4] if per >= 3 else labels[maxi(per, 1) - 1]
	_plane.print_at(4 + 0x17 - lab.length() / 2, 24, lab, 1)
	for k in 2:
		var t: TeamData = g["teams"][k]
		_plane.print_at(4, 25 + k, t.city)
		_plane.print_at(25, 25 + k, "%2d" % g["score"][k])

## $9DE6: Framer 24 x (3 + goalies) at (4,12); row 0 "no goalie", then each goalie.
func _draw_change_goalie() -> void:
	var game := _game()
	var n := _goalie_count()
	_plane.frame(4, 12, 24, 3 + n)
	var data: TeamData = game.world.stats[team()].data
	for row in n + 1:
		var line := 0 if row == _sub_cursor else 1
		_plane.print_at(5, 13 + row, " ".repeat(22), line)
		if row == 0:
			_plane.print_at(11, 13, "no goalie", line)
			continue
		var p := data.player(row - 1) if data else null
		if p:
			_plane.print_at(5, 13 + row, "%2d" % (p.jersey_number % 100), line)
			_plane.print_at(8, 13 + row, p.full_name, line)

func _goalie_count() -> int:
	var game := _game()
	var data: TeamData = game.world.stats[team()].data
	return data.goalie_count if data else 2

func _pick_goalie() -> void:
	var game := _game()
	game.world.goalie.change_goalie(team(), _sub_cursor)
	_sub = ""
	_redraw_game()
	_draw()

## $9D7A: "Timeout" and the team's city in the menu box.
func _draw_timeout() -> void:
	var game := _game()
	_plane.frame(BOX.position.x, BOX.position.y, BOX.size.x, BOX.size.y)
	_plane.print_at(12, 14, "Timeout")
	var d: TeamData = game.world.stats[team()].data
	var city := d.city if d else ""
	_plane.print_at(17 - city.length() / 2, 15, city)
