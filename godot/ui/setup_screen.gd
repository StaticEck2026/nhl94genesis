extends Control
## Team select. Two OptionButtons over the TeamData resources, who controls each side,
## a line list for each team, and the main game options. Start loads the game scene.

const GAME_SCENE := "res://scenes/game.tscn"

@onready var _home: OptionButton = %HomeTeam
@onready var _away: OptionButton = %AwayTeam
@onready var _home_ctrl: OptionButton = %HomeControl
@onready var _away_ctrl: OptionButton = %AwayControl
@onready var _home_lines: ItemList = %HomeLines
@onready var _away_lines: ItemList = %AwayLines
@onready var _length: OptionButton = %PeriodLength
@onready var _penalties: CheckBox = %Penalties
@onready var _offsides: CheckBox = %Offsides
@onready var _line_changes: CheckBox = %LineChanges
@onready var _start: Button = %Start
@onready var _status: Label = %Status

var _teams: Array[TeamData] = []

func _ready() -> void:
	_teams = MatchConfig.available_teams()
	for t in _teams:
		_home.add_item(t.abbreviation if t.abbreviation != "" else t.display_name())
		_away.add_item(t.abbreviation if t.abbreviation != "" else t.display_name())
	for o in [_home_ctrl, _away_ctrl]:
		for c in MatchConfig.Driver.keys():
			o.add_item(c.capitalize())
	_home_ctrl.select(MatchConfig.Driver.PAD1)
	_away_ctrl.select(MatchConfig.Driver.CPU)
	for m in [5, 10, 20]:
		_length.add_item("%d min" % m)
	_home.item_selected.connect(func(_i: int) -> void: _fill_lines(_home, _home_lines))
	_away.item_selected.connect(func(_i: int) -> void: _fill_lines(_away, _away_lines))
	_start.pressed.connect(_on_start)
	if _teams.size() > 1:
		_away.select(1)
	_fill_lines(_home, _home_lines)
	_fill_lines(_away, _away_lines)
	_status.text = "%d teams" % _teams.size() if _teams.size() > 0 else "No teams in res://data/teams yet"
	_start.disabled = _teams.size() < 2
	_home.grab_focus()

func _fill_lines(team_pick: OptionButton, list: ItemList) -> void:
	list.clear()
	if team_pick.selected < 0 or team_pick.selected >= _teams.size():
		return
	var t := _teams[team_pick.selected]
	for line_name in t.lines:
		list.add_item(str(line_name))
	if list.item_count > 0:
		list.select(0)

func _on_start() -> void:
	var m := MatchConfig.new()
	m.home_team = _teams[_home.selected]
	m.away_team = _teams[_away.selected]
	m.home_control = _home_ctrl.selected as MatchConfig.Driver
	m.away_control = _away_ctrl.selected as MatchConfig.Driver
	m.period_minutes = [5, 10, 20][_length.selected]
	m.penalties = _penalties.button_pressed
	m.offsides = _offsides.button_pressed
	m.line_changes = _line_changes.button_pressed
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
