extends Control
## Team select. Two OptionButtons over the TeamData resources, who controls each side,
## a line list for each team, and the main game options. Start loads the game scene.
## The edition picks retail '94 or the fight patch ("NHL Hockey '94-Fight": its rosters
## and the Fighting option, Off / On / On - Arcade Mode, default On); the patch's Fgt
## column shows in each line's tooltip.

const GAME_SCENE := "res://scenes/game.tscn"
## GameSetUp_2 (L962366): with no new press on any pad for $5460 vblanks (six minutes)
## the menu gives up and a demo game starts (loc_F8418, GameSetUp L960200).
const DEMO_IDLE := 0x5460

@onready var _home: OptionButton = %HomeTeam
@onready var _away: OptionButton = %AwayTeam
@onready var _home_ctrl: OptionButton = %HomeControl
@onready var _away_ctrl: OptionButton = %AwayControl
@onready var _home_lines: ItemList = %HomeLines
@onready var _away_lines: ItemList = %AwayLines
@onready var _length: OptionButton = %PeriodLength
@onready var _penalties: CheckBox = %Penalties
@onready var _offsides: CheckBox = %Offsides
## OptLine: On, Off, Auto. OptGoalie: Manual or Auto Control.
@onready var _line_changes: OptionButton = %LineChanges
@onready var _goalie_ctrl: OptionButton = %GoalieControl
## Play mode: Regular Game, or Shootout (OptPlayMode 4).
@onready var _play_mode: OptionButton = %PlayMode
@onready var _edition: OptionButton = %Edition
@onready var _fighting: OptionButton = %Fighting
@onready var _title: Label = $Margin/Rows/Title
@onready var _start: Button = %Start
@onready var _status: Label = %Status

var _teams: Array[TeamData] = []
var _idle := 0
var _sfx: SfxBank

func _ready() -> void:
	_edition.add_item("Retail '94")
	_edition.add_item("'94-Fight patch")
	_edition.select(Sim.match.edition if Sim.match else MatchConfig.Edition.FIGHT)
	for t in ["Line changes: On", "Line changes: Off", "Line changes: Auto"]:
		_line_changes.add_item(t)
	for t in ["Goalie: Manual Control", "Goalie: Auto Control"]:
		_goalie_ctrl.add_item(t)
	_goalie_ctrl.select(1)
	for t in ["Regular Game", "Shootout"]:
		_play_mode.add_item(t)
	_play_mode.select(0)
	for f in ["Fighting: Off", "Fighting: On", "Fighting: On - Arcade Mode"]:
		_fighting.add_item(f)
	_fighting.select(MatchConfig.Fighting.ON)
	_edition.item_selected.connect(func(_i: int) -> void: _load_teams())
	for o in [_home_ctrl, _away_ctrl]:
		for c in MatchConfig.Driver.values():
			o.add_item(MatchConfig.DRIVER_NAMES[c], c)
	_home_ctrl.select(MatchConfig.Driver.PAD1)
	_away_ctrl.select(MatchConfig.Driver.CPU)
	for m in [5, 10, 20]:
		_length.add_item("%d min" % m)
	_home.item_selected.connect(func(_i: int) -> void: _fill_lines(_home, _home_lines))
	_away.item_selected.connect(func(_i: int) -> void: _fill_lines(_away, _away_lines))
	_start.pressed.connect(_on_start)
	_load_teams()
	_home.grab_focus()
	# The menus' song ($78: the title's, again after a game, loc_172E4).
	_sfx = SfxBank.new()
	add_child(_sfx)
	_sfx.play_song(0x78)

func _fight_edition() -> bool:
	return _edition.selected == MatchConfig.Edition.FIGHT

## The edition's rosters, keeping the teams picked so far; the patch renames the ROM
## "NHL Hockey '94-Fight" (chg_header).
func _load_teams() -> void:
	var keep := [_abbr_at(_home), _abbr_at(_away)]
	_teams = MatchConfig.available_teams(_edition.selected as MatchConfig.Edition)
	for o in [_home, _away]:
		o.clear()
		for t in _teams:
			o.add_item(t.abbreviation if t.abbreviation != "" else t.display_name())
	_select_abbr(_home, keep[0], 0)
	_select_abbr(_away, keep[1], 1)
	_fighting.disabled = not _fight_edition()
	_title.text = "NHL Hockey '94-Fight  -  Exhibition" if _fight_edition() else "NHL 94  -  Exhibition"
	get_window().title = "NHL Hockey '94-Fight" if _fight_edition() else "NHL Hockey '94"
	_fill_lines(_home, _home_lines)
	_fill_lines(_away, _away_lines)
	_status.text = "%d teams" % _teams.size() if _teams.size() > 0 else "No teams in res://data/teams yet"
	_start.disabled = _teams.size() < 2

func _abbr_at(o: OptionButton) -> String:
	return _teams[o.selected].abbreviation if o.selected >= 0 and o.selected < _teams.size() else ""

func _select_abbr(o: OptionButton, abbr: String, fallback: int) -> void:
	for i in _teams.size():
		if _teams[i].abbreviation == abbr and abbr != "":
			o.select(i)
			return
	if _teams.size() > fallback:
		o.select(fallback)

func _fill_lines(team_pick: OptionButton, list: ItemList) -> void:
	list.clear()
	if team_pick.selected < 0 or team_pick.selected >= _teams.size():
		return
	var t := _teams[team_pick.selected]
	# The seven RAM lines with line changes on (data lines 1-7): forwards LW-C-RW.
	for k in range(1, 8):
		var ln := t.line(k)
		var names := []
		for pos in [3, 4, 5]:
			var p := t.player(ln[pos] - 1)
			names.append(p.full_name.get_slice(" ", p.full_name.get_slice_count(" ") - 1) if p else "-")
		list.add_item("%s  %s" % [TeamData.LINE_NAMES[k], " - ".join(names)])
		list.set_item_tooltip(list.item_count - 1, _line_tooltip(t, ln))
	if list.item_count > 0:
		list.select(0)

## The line's six players; the fight patch adds its Fgt column (fgtdisp, 0-100).
func _line_tooltip(t: TeamData, ln: PackedInt32Array) -> String:
	var rows := []
	for pos in [0, 1, 2, 3, 4, 5]:
		var p := t.player(ln[pos] - 1)
		if p == null:
			continue
		var row := "%s  #%d %s" % [["G", "LD", "RD", "LW", "C", "RW"][pos], p.jersey_number, p.full_name]
		if _fight_edition() and not p.is_goalie():
			row += "  Fgt %d" % PlayerData.fight_display(PlayerData.fight_nibble_of(p.fighting))
		rows.append(row)
	return "\n".join(rows)

func _input(event: InputEvent) -> void:
	if event.is_pressed():
		_idle = 0

func _physics_process(_delta: float) -> void:
	_idle += 1
	if _idle >= DEMO_IDLE:
		_idle = 0
		_demo()

## The demo: random teams (randomd0 $1C for each, so both can be the same team), CPU
## against CPU (OptNOP 0), a regular game (OptPlayMode 0), the other options as they are.
func _demo() -> void:
	if _teams.is_empty():
		return
	_home.select(randi() % _teams.size())
	_away.select(randi() % _teams.size())
	_home_ctrl.select(MatchConfig.Driver.CPU)
	_away_ctrl.select(MatchConfig.Driver.CPU)
	_play_mode.select(0)
	_fill_lines(_home, _home_lines)
	_fill_lines(_away, _away_lines)
	_on_start()

func _on_start() -> void:
	var m := MatchConfig.new()
	m.home_team = _teams[_home.selected]
	m.away_team = _teams[_away.selected]
	m.home_control = _home_ctrl.get_selected_id() as MatchConfig.Driver
	m.away_control = _away_ctrl.get_selected_id() as MatchConfig.Driver
	m.period_minutes = [5, 10, 20][_length.selected]
	m.penalties = _penalties.button_pressed
	m.offsides = _offsides.button_pressed
	m.line_changes = _line_changes.selected != 1
	m.auto_lines = _line_changes.selected == 2
	m.auto_goalie = _goalie_ctrl.selected == 1
	m.shootout = _play_mode.selected == 1
	m.edition = _edition.selected as MatchConfig.Edition
	m.fighting = _fighting.selected as MatchConfig.Fighting
	var hs := _home_lines.get_selected_items()
	var aws := _away_lines.get_selected_items()
	m.home_line = hs[0] if hs.size() > 0 else 0
	m.away_line = aws[0] if aws.size() > 0 else 0
	var sim := get_node_or_null("/root/Sim")
	if sim:
		sim.set("match", m)
	if ResourceLoader.exists(GAME_SCENE):
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		_status.text = "Game scene not built yet"
