extends Node2D
## PlayoffScreen (L53890; spec docs/specs/playoffs_records.md §7): the bracket before
## every playoff game and after it. H40, the SPORTS background on plane B and the
## bracket on a 128-cell plane A that pages left and right (112 px a press, 2 px a
## frame, as far as the rounds played). The plates show the tree (MakeTree); the user's
## blink (line 2 colour 1 ^ $0EE every 24 frames). The series scores ("w-w") show in
## best of seven, under the round's name. The Stanley Cup is a sprite that moves with
## the plane. Start leaves. Song $79. Art: tools/extract/playoffs.py.

const DIR := "res://assets/ui/playoffs/"
const MENUS := "res://assets/ui/menus/"
const SETUP_SCENE := "res://ui/game_setup.tscn"
const MATCHUPS_SCENE := "res://ui/matchups.tscn"
const VIEW_COL := 44
const PAGE := 0x70
const FLASH_FRAMES := 24
const ROUNDS := ["Playoffs", "Quarterfinals", "Semifinals", "Finals", "Champions"]

var _po: Dictionary = {}
var _pal: Dictionary = {}
var _lg: League
var _b: WindowPlane
var _clip: Control
var _a: WindowPlane
var _win: WindowPlane
var _cup: Sprite2D
var _pal_img: Image
var _pal_tex: ImageTexture
var _bg_img: Image
var _bg_tex: ImageTexture
var _lines: Array = []
## DispAttribCtr (the plane's scroll) and PlayerScrollCtr (its step).
var _scroll := 0
var _step := 0
var _flash := FLASH_FRAMES
## The press that brought the screen up must be let go first.
var _armed := false

func _ready() -> void:
	ScreenMode.restore(get_tree())
	_lg = Sim.league
	for e in [[DIR + "playoffs.json", "_po"], [MENUS + "palettes.json", "_pal"]]:
		if FileAccess.file_exists(e[0]):
			set(e[1], JSON.parse_string(FileAccess.get_file_as_string(e[0])))
	if _po.is_empty():
		_leave()
		return
	WindowPlane.register("stats_bg", MENUS + "stats_bg_idx.png")
	WindowPlane.register("bracket", DIR + "bracket_idx.png")
	var cram: Dictionary = _po["screen"]["cram"]
	_lines = [cram["line0"], cram["line1"], (cram["line2"] as Array).duplicate(), cram["line3"]]
	_pal_img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	_bg_img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	_bg_tex = ImageTexture.create_from_image(_bg_img)
	_palette()
	var back := ColorRect.new()
	back.size = Vector2(320, 224)
	back.color = PaletteBank.cram(int(_lines[3][0]))
	add_child(back)
	# Plane B: the background printed with $6000, so its lines 0 and 1 show CRAM lines
	# 3 and 2.
	_b = _plane(self)
	_b.material = PaletteBank.material(_bg_tex, false, true)
	_b.bitmap(0, 0, "stats_bg", 0, 0, 40, 28)
	# The window covers rows 0-1; plane A shows below it.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = Vector2(0, 16)
	_clip.size = Vector2(320, 208)
	add_child(_clip)
	_a = _plane(_clip)
	_win = _plane(self)
	_cup = Sprite2D.new()
	_cup.centered = false
	_cup.texture = load(DIR + "cup_idx.png")
	_cup.material = PaletteBank.material(_pal_tex, false, true)
	add_child(_cup)
	_draw_bracket()
	_place()
	if Sim.menu_sfx:
		Sim.menu_sfx.play_song(0x79)

func _plane(parent: Node) -> WindowPlane:
	var p := WindowPlane.new()
	p.origin = Vector2.ZERO
	p.material = PaletteBank.material(_pal_tex, false, true)
	parent.add_child(p)
	return p

func _palette() -> void:
	var bg := [_lines[3], _lines[2], _lines[1], _lines[0]]
	for y in 4:
		for x in 16:
			_pal_img.set_pixel(x, y, PaletteBank.cram(int(_lines[y][x])))
			_bg_img.set_pixel(x, y, PaletteBank.cram(int(bg[y][x])))
	_pal_tex.update(_pal_img)
	_bg_tex.update(_bg_img)

## The level's plates (tree bytes 0..n-1), strips, scores and the round's name.
func _draw_bracket() -> void:
	var level := clampi(_lg.gamelevel, 0, 4)
	var lay: Dictionary = _po["screen"]["levels"][level]
	var user := _lg.user_team()
	var plates: Array = lay["plates"]
	for i in plates.size():
		var at: Array = plates[i]
		var t := _lg.tree[i]
		_a.bitmap(at[0], at[1] - 2, "team_plates", 0, 2 * t, 11, 2, 2 if t == user else 1)
	for s in lay["strips"]:
		_a.bitmap(int(s["x"]), 0, "bracket", int(s["src_col"]), 0, 2, 23, 1)
	# sub_175FC: "w-w" of each series, first-listed team first; none for single games.
	if _lg.bosgames != League.SINGLE:
		var spots: Array = lay["series_scores"]
		for i in spots.size():
			var g: Dictionary = _lg.gs[i]
			_a.print_at(spots[i][0], spots[i][1] - 2, "%d-%d" % [g["wins"][0], g["wins"][1]], 1, "stats0")
	var label: String = ROUNDS[level]
	# Centred on column 65 the way the emulator shows it (64 - len / 2).
	_a.print_at(64 - label.length() / 2, 24, label, 1, "stats0")
	if _lg.gamelevel != 0:
		_win.print_at(10, 1, "Press [ or ] to page", 3, "stats0")

## Hscroll A = $FEA0 + DispAttribCtr; the cup at sprite x $100 + DispAttribCtr.
func _place() -> void:
	_a.position = Vector2(-VIEW_COL * 8 + _scroll, 0)
	var sx := 0x100 + _scroll
	_cup.visible = sx >= 0x40 and sx <= 0x200
	_cup.position = Vector2(sx - 128, 0xA0 - 128)

func _physics_process(_delta: float) -> void:
	if _a == null:
		return
	# sub_175D8: the user's plates blink.
	_flash -= 1
	if _flash <= 0:
		_flash = FLASH_FRAMES
		_lines[2][1] = int(_lines[2][1]) ^ 0x0EE
		_palette()
	if not _armed:
		_armed = not Input.is_action_pressed("p1_start") and not Input.is_action_pressed("p2_start")
		return
	for k in 2:
		var p := "p%d_" % (k + 1)
		if Input.is_action_just_pressed(p + "start"):
			_leave()
			return
		if Input.is_action_just_pressed(p + "right"):
			_step = -2
		elif Input.is_action_just_pressed(p + "left"):
			_step = 2
	# sub_17572: 2 px a frame to the next 112-px page, within the rounds played.
	if _step != 0:
		var d0 := _scroll + _step
		if absi(d0) <= PAGE * mini(_lg.gamelevel, 3):
			_scroll = d0
			if d0 % PAGE == 0:
				_step = 0
		else:
			_step = 0
		_place()

func _leave() -> void:
	get_tree().change_scene_to_file(MATCHUPS_SCENE if Sim.bracket_next_matchups else SETUP_SCENE)
