class_name WindowPlane
extends Node2D
## A screen plane as retail's print routines use it (print / printz, printbig, Framer,
## eraser, dobitmap): a 32 x 28 grid of 8 x 8 cells, each a tile with its own palette
## line. The 256-pixel screen sits centred in the port's 320-pixel view, so cell (c, r)
## is at (32 + 8c, 8r) of the overlay (`origin` moves it, e.g. onto the side view).
## Art from tools/extract/ui_overlay.py (assets/ui, spec docs/specs/ui_ingame.md):
## the in-game font (opaque black cells, grey text), the printbig font, the Framer
## tiles, the EA logo, the team plates and the energy bars. Colours come from the
## material's palette (the rink CRAM: retail's overlays use lines 0 and 1).

const COLS := 32
const ROWS := 28
const DIR := "res://assets/ui/"

## Top-left of cell (0, 0) in this node's space.
var origin := Vector2(32, 0)
## Cell -> [texture key, source rect, palette line (-1: the art's own), flags].
var cells := {}

static var _data := {}
static var _tex := {}

func _init() -> void:
	_load()

static func _load() -> void:
	if not _data.is_empty():
		return
	var path := DIR + "ui.json"
	if not FileAccess.file_exists(path):
		_data = {"missing": true}
		return
	_data = JSON.parse_string(FileAccess.get_file_as_string(path))
	for k in ["font", "bigfont", "framer", "ea_logo", "team_plates", "energy"]:
		var f := DIR + String(_data[k]["file"])
		if ResourceLoader.exists(f):
			_tex[k] = load(f)
	# The stats pages' fonts and Framer (tools/extract/ui_menus.py): font 0 raw (colour 0
	# transparent), font 1 with an opaque background, the dark-filled Framer.
	for e in [["stats0", "font_stats_idx.png"], ["stats1", "font_stats_alt_idx.png"],
			["framer_stats", "framer_stats_idx.png"], ["cards0", "font_cards_idx.png"]]:
		var f := DIR + "menus/" + String(e[1])
		if ResourceLoader.exists(f):
			_tex[e[0]] = load(f)
	var fj := DIR + "menus/font.json"
	if FileAccess.file_exists(fj):
		_data["stats_chars"] = JSON.parse_string(FileAccess.get_file_as_string(fj))["chars"]
	var m := DIR + "messages.json"
	if FileAccess.file_exists(m):
		_data["messages"] = JSON.parse_string(FileAccess.get_file_as_string(m))

static func available() -> bool:
	_load()
	return _tex.has("font")

## messages.json (penalty list texts, period labels, line names...).
static func messages() -> Dictionary:
	_load()
	return _data.get("messages", {})

func clear() -> void:
	cells.clear()
	queue_redraw()

## eraser: blank (transparent) cells.
func erase(col: int, row: int, w: int, h: int) -> void:
	for y in range(row, row + h):
		for x in range(col, col + w):
			cells.erase(Vector2i(x, y))
	queue_redraw()

func _tile_rect(key: String, tile: int, per_row: int) -> Rect2:
	return Rect2((tile % per_row) * 8, (tile / per_row) * 8, 8, 8)

## print: text from (col, row). '\n' goes to the next row at `col`; '@' writes a
## transparent cell, '^' skips one. Returns the column after the text.
func print_at(col: int, row: int, text: String, line: int = -1, font: String = "font") -> int:
	if not available() or not _tex.has(font):
		return col
	var chars: Dictionary = _data["font"]["chars"] if font == "font" else _data["stats_chars"]
	var x := col
	var y := row
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 10:
			x = col
			y += 1
			continue
		if c == 0x5E:
			x += 1
			continue
		if c == 0x40:
			cells.erase(Vector2i(x, y))
		else:
			var t: int = chars.get(str(c), chars.get("32", 0))
			cells[Vector2i(x, y)] = [font, _tile_rect(font, t, 16), line, 0]
		x += 1
	queue_redraw()
	return x

## Centred on column `center` (printx -= len / 2).
func print_centered(center: int, row: int, text: String, line: int = -1, font: String = "font") -> void:
	print_at(center - text.length() / 2, row, text, line, font)

## printbig: the 2-cell-tall font, letters upper-cased. Returns the column after it.
func print_big(col: int, row: int, text: String, line: int = -1) -> int:
	if not _tex.has("bigfont"):
		return print_at(col, row, text)
	var glyphs: Dictionary = _data["bigfont"]["glyphs"]
	var x := col
	for ch in text.to_upper():
		var g: Dictionary = glyphs.get(str(ch.unicode_at(0)), glyphs["65"])
		for half in 2:
			var parts: Array = g["top" if half == 0 else "bottom"]
			for k in parts.size():
				var p: Array = parts[k]
				cells[Vector2i(x + k, row + half)] = ["bigfont", _tile_rect("bigfont", int(p[0]), 16), line, int(p[1]) & 3]
		x += int(g["w"])
	queue_redraw()
	return x

## Framer: a w x h box of the bevelled border and an opaque black centre.
func frame(col: int, row: int, w: int, h: int, key: String = "framer", line: int = -1) -> void:
	if not _tex.has(key):
		return
	for y in h:
		for x in w:
			var i := (0 if y == 0 else (6 if y == h - 1 else 3)) + (0 if x == 0 else (2 if x == w - 1 else 1))
			cells[Vector2i(col + x, row + y)] = [key, _tile_rect(key, i, 3), line, 0]
	queue_redraw()

## dobitmap of an exported picture: a w x h cell block starting at cell (sx, sy) of `key`.
func bitmap(col: int, row: int, key: String, sx: int, sy: int, w: int, h: int, line: int = -1) -> void:
	if not _tex.has(key):
		return
	for y in h:
		for x in w:
			cells[Vector2i(col + x, row + y)] = [key, Rect2((sx + x) * 8, (sy + y) * 8, 8, 8), line, 0]
	queue_redraw()

func _draw() -> void:
	for k in cells:
		var cell: Array = cells[k]
		var tex: Texture2D = _tex.get(cell[0])
		if tex == null:
			continue
		var at := origin + Vector2(k.x * 8, k.y * 8)
		var f: int = cell[3]
		var size := Vector2(-8 if f & 1 else 8, -8 if f & 2 else 8)
		var mod := Color(1, 1, 1, 1) if cell[2] < 0 else Color(1, cell[2] / 3.0, 0, 1)
		draw_texture_rect_region(tex, Rect2(at, size), cell[1], mod)
