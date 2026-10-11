extends CanvasLayer
## Pause menu (PauseMode, L30217). Start (p1_start / p2_start) toggles it; the game tree
## pauses underneath. The menu belongs to the pausing pad's team (sub_7E0E) and follows
## retail's three tables: unk_19700 normally, unk_1988C once that team has called its
## timeout (no Timeout row), unk_19664 in a shootout (no Change Goalie, Edit Lines or
## Timeout). The stats pages and the instant replay are not ported; Quit is the port's own
## row.

@onready var _panel: Control = %Panel
@onready var _rows: VBoxContainer = %Rows
@onready var _scroll: ScrollContainer = %Scroll

signal quit_requested

const TIMEOUT_TEXT := "Timeout called"

## The tallest the list gets before it scrolls (the screen is 224 high).
const MAX_HEIGHT := 200.0
const TITLES := {"main": "Paused", "goalie": "Change Goalie", "lines": "Edit Lines"}

## The pad that paused (0 or 1) and the menu showing: "main", "goalie", "lines", "slots"
## or "players".
var _pad := 0
var _page := "main"
var _note := ""
## Edit Lines: the RAM line and the slot (0 G .. 6 X) being edited.
var _edit_line := 0
var _edit_slot := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false

func _game() -> HockeyGame:
	return get_parent() as HockeyGame

func _unhandled_input(event: InputEvent) -> void:
	# During an intermission Start belongs to the game (it resumes play).
	var game := _game()
	if game and game.hold and not _panel.visible:
		return
	for k in 2:
		if event.is_action_pressed("p%d_start" % (k + 1)):
			if not _panel.visible:
				_pad = k
			toggle()
			get_viewport().set_input_as_handled()
			return

func toggle() -> void:
	_panel.visible = not _panel.visible
	get_tree().paused = _panel.visible
	if _panel.visible:
		_note = ""
		_show("main")
	else:
		# PauseMode's exit: PrintScores1 quiets the crowd meter.
		var game := _game()
		if game:
			game.world.rules.print_scores1()

## The team whose menu this is.
func team() -> int:
	var game := _game()
	return game.world.pause_team(_pad) if game else 0

## The rows of the current table as [label, callable] pairs.
func rows() -> Array:
	var game := _game()
	var out: Array = [["Resume Game", toggle]]
	if game == null:
		return out
	var w := game.world
	var shootout := w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT != 0
	if not shootout:
		out.append(["Change Goalie", _show.bind("goalie")])
		out.append(["Edit Lines", _show.bind("lines")])
	if not shootout and w.stats[team()].flags30 & TeamStats.F30_TIMEOUT == 0:
		out.append(["Timeout", _on_timeout])
	out.append([("Auto Goalie" if w.auto_goalie[_pad] else "Manual Goalie"), _on_goalie_control])
	out.append(["Quit to setup", _on_quit])
	return out

## The Change Goalie list ($9DE6): "No Goalie", then the team's goalies.
func goalie_rows() -> Array:
	var game := _game()
	var out: Array = []
	if game == null:
		return out
	var t := team()
	out.append(["No Goalie", _on_goalie_pick.bind(0)])
	var data: TeamData = game.world.stats[t].data
	var n := data.goalie_count if data else 2
	for i in n:
		var p := data.player(i) if data else null
		out.append([p.full_name if p else "Goalie %d" % (i + 1), _on_goalie_pick.bind(i + 1)])
	return out

## Edit Lines: the team's seven lines.
func line_rows() -> Array:
	var out: Array = []
	var game := _game()
	if game == null or game.world.stats[team()].ram_lines.size() < 56:
		return [["Back", _show.bind("main")]]
	for k in 7:
		out.append([game.world.lines.line_name(k), _on_line_pick.bind(k)])
	out.append(["Back", _show.bind("main")])
	return out

## The line's slots with the players in them.
func slot_rows() -> Array:
	var out: Array = []
	var game := _game()
	var st := game.world.stats[team()]
	for i in 7:
		var v := st.ram_lines[_edit_line * 8 + i]
		out.append(["%s  %s" % [TeamData.LINE_SLOTS[i], _player_name(v - 1)], _on_slot_pick.bind(i)])
	out.append(["Back", _show.bind("lines")])
	return out

## The roster for the slot: goalies for G, skaters for the rest.
func player_rows() -> Array:
	var out: Array = []
	var game := _game()
	var data: TeamData = game.world.stats[team()].data
	if data:
		for i in data.players.size():
			var goalie := i < data.goalie_count
			if goalie != (_edit_slot == 0):
				continue
			out.append([_player_name(i), _on_player_pick.bind(i)])
	out.append(["Back", _show.bind("slots")])
	return out

func _player_name(slot: int) -> String:
	var game := _game()
	var data: TeamData = game.world.stats[team()].data if game else null
	var p := data.player(slot) if data and slot >= 0 else null
	return "#%d %s" % [p.jersey_number, p.full_name] if p else "-"

func _on_line_pick(k: int) -> void:
	_edit_line = k
	_show("slots")

func _on_slot_pick(i: int) -> void:
	_edit_slot = i
	_show("players")

func _on_player_pick(slot: int) -> void:
	var game := _game()
	if game:
		game.world.lines.edit_line(team(), _edit_line, _edit_slot, slot)
	_show("slots")

func _show(page: String) -> void:
	_page = page
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var game := _game()
	var abbr := ""
	if game and game.world.stats[team()].data:
		abbr = game.world.stats[team()].data.abbreviation + " "
	var head: String = TITLES.get(page, "")
	if page == "slots" or page == "players":
		head = game.world.lines.line_name(_edit_line) if game else ""
		if page == "players":
			head += " " + TeamData.LINE_SLOTS[_edit_slot]
	title.text = abbr + head
	_rows.add_child(title)
	if _note != "" and page == "main":
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 8)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.text = _note
		_rows.add_child(note)
	var list: Array
	match page:
		"goalie": list = goalie_rows()
		"lines": list = line_rows()
		"slots": list = slot_rows()
		"players": list = player_rows()
		_: list = rows()
	var focus := 0
	if page == "goalie" and game:
		focus = game.world.goalie.goalie_row(team())
	var first: Button = null
	for i in list.size():
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 8)
		b.text = list[i][0]
		b.pressed.connect(list[i][1])
		_rows.add_child(b)
		if i == focus or first == null:
			first = b
	var need := _rows.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(need.x, minf(need.y, MAX_HEIGHT))
	_scroll.scroll_vertical = 0
	_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(320, 224)
	_panel.position = ((vp - _panel.size) / 2).floor()
	if first and is_inside_tree():
		first.grab_focus.call_deferred()

func _on_timeout() -> void:
	var game := _game()
	if game and game.world.timeout(team()):
		_note = TIMEOUT_TEXT
	_show("main")

func _on_goalie_control() -> void:
	var game := _game()
	if game:
		game.world.toggle_goalie_control(_pad)
	_show("main")

func _on_goalie_pick(row: int) -> void:
	var game := _game()
	if game:
		game.world.goalie.change_goalie(team(), row)
	_show("main")

func _on_quit() -> void:
	get_tree().paused = false
	quit_requested.emit()
