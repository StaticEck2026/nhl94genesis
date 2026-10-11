class_name LineMenu
extends Control
## The line-change box (SetLCmode / sub_B92E): rows A, B, C name the line each button
## sends (getlchoice) with an energy bar of up to 15 blocks (getlinee / 256). It opens
## for a pad's team while the menu is up and shows the pick briefly after.

const ROW_KEYS := ["A", "B", "C"]
const SHOW_AFTER := 90

var game: HockeyGame
var _label: Label
var _team := -1
var _linger := 0

func setup(p_game: HockeyGame) -> void:
	game = p_game
	position = Vector2(32 + 22 * 8 - 40, 150)
	size = Vector2(120, 40)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 2)
	add_child(_label)
	game.world.lines.menu_changed.connect(_on_changed)
	game.stepped.connect(_sync)
	visible = false

func _on_changed(team: int) -> void:
	_team = team
	_linger = SHOW_AFTER

func _sync() -> void:
	var w := game.world
	var open := -1
	for k in 2:
		var t := w.cont_team[k] - 1
		if t >= 0 and w.stats[t].flags30 & TeamStats.F30_LINE_MENU:
			open = t
	if open >= 0:
		_team = open
		_linger = SHOW_AFTER
	elif _linger > 0:
		_linger -= 1
	visible = _team >= 0 and (open >= 0 or _linger > 0)
	if not visible:
		return
	var lines := w.lines
	var st := w.stats[_team]
	var text := ""
	if open >= 0:
		for row in 3:
			var l := lines.getlchoice(_team, row)
			if l < 0:
				continue
			var bars := mini(lines.getlinee(_team, l) / 256, 15)
			text += "%s %s %s\n" % [ROW_KEYS[row], TeamData.LINE_NAMES[l + 1], "|".repeat(bars)]
	else:
		text = "%s  %s" % [st.data.abbreviation if st.data else "", TeamData.LINE_NAMES[st.line + 1]]
	_label.text = text
