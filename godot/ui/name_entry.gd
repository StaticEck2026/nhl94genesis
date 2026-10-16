extends Node2D
## Name Entry (sub_FBB88 L967859 → loc_FB018 L966782; spec docs/specs/playoffs_records.md
## §8.4), with User Records On: pad 1, then pad 2 when it plays the other team, picks one
## of the seven named users the records are kept for. The layout is measured from the
## emulator's screens (the routine itself is UNRESOLVED P2):
## - "NAME ENTRY" in a box, the Name Log (7 rows, arrows on the cursor row), the team's
##   city and logo, and a help box;
## - B edits the name under the arrows: a 12-character field and a letter grid with a box
##   cursor (5 rows of 6, the last cell a space). Measured on the ROM in Genesis Plus GX:
##   the letter under the box is written at the current position as the box moves, and
##   the position is underlined. C moves to the next position (the 12th is the last),
##   whose letter the box jumps to when it has one. A goes back a position the same way.
##   The d-pad stops at the grid's edges. B cancels. Start keeps the name, picks it and
##   leaves (sub_FBB88), like Start on the list.
## The choices go to MatchConfig.users ($D042 home, $D044 away).

const MENUS := "res://assets/ui/menus/"
const GRID := ["ABCDEF", "GHIJKL", "MNOPQR", "STUVWX", "YZ.12 "]
const HELP_SELECT := ["D-Pad up/down to", "move arrows.", "Press START to", "select name.", "Press B to edit."]
const HELP_EDIT := ["D-Pad to a letter.", "C to select letter.", "A to go back.", "B to cancel.", "START when done."]
const NAME_LEN := 12

var _pal: Dictionary = {}
var _a: WindowPlane
## The boxes, on the plane under the text (the font's see-through cells show the box).
var _f: WindowPlane
var _pal_img: Image
var _pal_tex: ImageTexture
## [pad index, side 0 home / 1 away] for each screen still to show.
var _queue: Array = []
var _pad := 0
var _side := 0
var _row := 0
var _edit := false
## The name being edited, 12 bytes (0 = empty, shown as a dash), and the position.
var _buf := PackedByteArray()
var _pos := 0
var _gx := 0
var _gy := 0
var _armed := false
var _bar: ColorRect
## The grid's box cursor: the frame tiles on their own plane, whose palette has the
## frame's black (line 1 colour 7) see-through. In the ROM the box is open: the
## background shows inside it.
var _box: WindowPlane
var _box_img: Image
var _box_tex: ImageTexture

func _ready() -> void:
	ScreenMode.restore(get_tree())
	if FileAccess.file_exists(MENUS + "palettes.json"):
		_pal = JSON.parse_string(FileAccess.get_file_as_string(MENUS + "palettes.json"))
	var m: MatchConfig = Sim.match
	m.users = [0, 0]
	var pads := m.pad_teams()
	if pads[0] != 0:
		_queue.append([0, pads[0] - 1])
	if pads[1] != 0 and pads[1] != pads[0]:
		_queue.append([1, pads[1] - 1])
	if _queue.is_empty() or _pal.is_empty():
		_leave()
		return
	WindowPlane.register("stats_bg", MENUS + "stats_bg_idx.png")
	WindowPlane.register("team_logos", MENUS + "team_logos_idx.png")
	_pal_img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	var back := ColorRect.new()
	back.size = Vector2(320, 224)
	back.color = PaletteBank.cram(int(_pal["stats"][0][0]))
	add_child(back)
	var b := WindowPlane.new()
	b.origin = Vector2.ZERO
	b.material = PaletteBank.material(_pal_tex, false, true)
	b.bitmap(0, 0, "stats_bg", 0, 0, 40, 28)
	add_child(b)
	_f = WindowPlane.new()
	_f.origin = Vector2.ZERO
	_f.material = PaletteBank.material(_pal_tex, false, true)
	add_child(_f)
	_a = WindowPlane.new()
	_a.origin = Vector2.ZERO
	_a.material = PaletteBank.material(_pal_tex, false, true)
	add_child(_a)
	# The edit field's bar, with the font's one-pixel black shadow down and right.
	_bar = ColorRect.new()
	_bar.size = Vector2(7, 2)
	_bar.color = PaletteBank.cram(int(_pal["stats"][0][1]))
	_bar.visible = false
	var shadow := ColorRect.new()
	shadow.size = Vector2(7, 2)
	shadow.position = Vector2(1, 1)
	shadow.color = Color.BLACK
	shadow.show_behind_parent = true
	_bar.add_child(shadow)
	add_child(_bar)
	_box_img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	_box_tex = ImageTexture.create_from_image(_box_img)
	_box = WindowPlane.new()
	_box.origin = Vector2.ZERO
	_box.material = PaletteBank.material(_box_tex, false, true)
	add_child(_box)
	move_child(_box, _a.get_index())
	_next()

func _next() -> void:
	if _queue.is_empty():
		_leave()
		return
	var e: Array = _queue.pop_front()
	_pad = e[0]
	_side = e[1]
	_row = 0
	_edit = false
	_armed = false
	_draw()

func _team() -> TeamData:
	return Sim.match.home_team if _side == 0 else Sim.match.away_team

## CRAM: the SPORTS background's lines, line 2 the team's logo.
func _palette() -> void:
	var lines: Array = (_pal["stats"] as Array).duplicate()
	var t := _team()
	if t and t.team_index >= 0:
		lines[2] = _pal["team_logos"][t.team_index]
	for y in 4:
		for x in 16:
			_pal_img.set_pixel(x, y, PaletteBank.cram(int(lines[y][x])))
			_box_img.set_pixel(x, y, Color(0, 0, 0, 0) if y == 1 and x == 7 else PaletteBank.cram(int(lines[y][x])))
	_pal_tex.update(_pal_img)
	_box_tex.update(_box_img)

func _draw() -> void:
	_palette()
	_a.clear()
	_f.clear()
	_box.clear()
	_f.frame(2, 0, 36, 6, "framer_stats", 1)
	_a.print_big(10, 2, "NAME  ENTRY", 1)
	_a.print_at(7, 6, "Name Log", 0, "stats0")
	for i in 7:
		var name := Sim.sram.user_name(i + 1)
		var shown := name if name != "" else "-".repeat(NAME_LEN)
		_a.print_at(5, 8 + i, shown + " ".repeat(NAME_LEN - shown.length()), 0, "stats0")
	_a.print_at(3, 8 + _row, "]", 0, "stats0")
	_a.print_at(18, 8 + _row, "[", 0, "stats0")
	var t := _team()
	if t:
		_a.print_at(31 - t.city.length() / 2, 6, t.city, 0, "stats0")
		_f.frame(27, 7, 8, 8, "framer_stats", 1)
		var ti := t.team_index
		_a.bitmap(28, 8, "team_logos", (ti % 4) * 6, (ti / 4) * 6, 6, 6, 2)
	_f.frame(1, 20, 22, 7, "framer_stats", 1)
	var help: Array = HELP_EDIT if _edit else HELP_SELECT
	for i in help.size():
		_a.print_at(2, 21 + i, help[i], 0, "stats0")
	if _edit:
		_a.print_at(4, 16, "Enter new name:", 0, "stats0")
		var field := ""
		for c in _buf:
			field += char(c) if c != 0 else "-"
		_a.print_at(5, 18, field, 0, "stats0")
		# The bar under the current position: 7 x 2 pixels in the text colour, 2 pixels
		# below the field's row (not a font glyph; measured on the ROM).
		_bar.position = Vector2(8 * (5 + _pos), 8 * 19 + 1)
		for y in GRID.size():
			var row: String = GRID[y]
			for x in row.length():
				var col := 25 + 2 * x
				var r := 17 + 2 * y
				if x == _gx and y == _gy:
					_box.frame(col - 1, r - 1, 3, 3, "framer_stats", 1, false)
				_a.print_at(col, r, row[x], 0, "stats0")
	_bar.visible = _edit

func _physics_process(_delta: float) -> void:
	if _a == null:
		return
	# setvram: the screen is frozen while it fades to black.
	if CramFade.busy(get_tree()):
		return
	var p := "p%d_" % (_pad + 1)
	if not _armed:
		_armed = not Input.is_action_pressed(p + "start")
		return
	var just := func(a: String) -> bool: return Input.is_action_just_pressed(p + a)
	if _edit:
		if just.call("start"):
			Sim.sram.set_user_name(_row + 1, _name())
			_edit = false
			Sim.match.users[_side] = _row + 1
			_next()
			return
		elif just.call("b"):
			_edit = false
		elif just.call("a"):
			if _pos > 0:
				_go_to(_pos - 1)
		elif just.call("c"):
			if _pos < NAME_LEN - 1:
				_go_to(_pos + 1)
		elif just.call("up") or just.call("down"):
			_gy = clampi(_gy + (1 if just.call("down") else -1), 0, GRID.size() - 1)
			_put()
		elif just.call("left") or just.call("right"):
			_gx = clampi(_gx + (1 if just.call("right") else -1), 0, GRID[0].length() - 1)
			_put()
		else:
			return
		_draw()
		return
	if just.call("start"):
		Sim.match.users[_side] = _row + 1
		_next()
		return
	if just.call("b"):
		_edit = true
		_buf = PackedByteArray()
		_buf.resize(NAME_LEN)
		var old := Sim.sram.user_name(_row + 1).to_ascii_buffer()
		for i in mini(old.size(), NAME_LEN):
			_buf[i] = old[i]
		_gx = 0
		_gy = 0
		_go_to(0)
	elif just.call("up"):
		_row = posmod(_row - 1, 7)
	elif just.call("down"):
		_row = posmod(_row + 1, 7)
	else:
		return
	_draw()

## The letter under the box goes in at the current position.
func _put() -> void:
	_buf[_pos] = GRID[_gy].unicode_at(_gx)

## A new position: the box jumps to the letter there, or that letter becomes the box's.
func _go_to(pos: int) -> void:
	_pos = pos
	var c := _buf[_pos]
	if c != 0:
		for y in GRID.size():
			var x: int = (GRID[y] as String).find(char(c))
			if x >= 0:
				_gx = x
				_gy = y
				return
	_put()

## The name as saved: the bytes up to the last one used.
func _name() -> String:
	var out := ""
	for c in _buf:
		if c == 0:
			break
		out += char(c)
	return out

func _leave() -> void:
	CramFade.change_scene(get_tree(), Sim.after_name_entry)
