class_name WindowPlane
extends Node2D
## The window plane as retail's print routines use it: a 32 x 28 grid of 8 x 8 cells,
## each a font glyph or a frame tile with its own palette line. The 256-pixel screen sits
## centred in the port's 320-pixel view, so cell (c, r) is at (32 + 8c, 8r). Text uses the
## ROM font ($AAC52, assets/sprites/font_idx.png); frame tiles come from
## assets/ui (tools/extract/ui_overlay.py) when exported.

const COLS := 32
const ROWS := 28
const X0 := 32
const FONT_PATH := "res://assets/sprites/font_idx.png"
const FONT_JSON := "res://assets/sprites/font.json"

## Cell -> [texture key, tile index, palette line, flags (bit 0 h-flip, bit 1 v-flip)].
var cells := {}
var _tex := {}
## Texture key -> tile index -> atlas rect.
var _tiles := {}
var _chars := {}
## Shared across planes.
static var _font_cache: Array = []

func _init() -> void:
	_load_font()

func _load_font() -> void:
	if _font_cache.is_empty():
		var tex: Texture2D = null
		var chars := {}
		if ResourceLoader.exists(FONT_PATH) and FileAccess.file_exists(FONT_JSON):
			tex = load(FONT_PATH)
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FONT_JSON))
			if d is Dictionary:
				for k in d["chars"]:
					chars[int(k)] = int(d["chars"][k])
		_font_cache = [tex, chars]
	_tex["font"] = _font_cache[0]
	_chars = _font_cache[1]

## Another tile set (a texture of 8 x 8 tiles, `per_row` to a row) under `key`.
func add_tileset(key: String, tex: Texture2D, per_row: int) -> void:
	_tex[key] = tex
	_tiles[key] = per_row

func has_tileset(key: String) -> bool:
	return _tex.get(key) != null

func clear() -> void:
	cells.clear()
	_boxes.clear()
	queue_redraw()

## eraser: blank a rectangle of cells.
func erase(col: int, row: int, w: int, h: int) -> void:
	for y in range(row, row + h):
		for x in range(col, col + w):
			cells.erase(Vector2i(x, y))
	var r := Rect2i(col, row, w, h)
	_boxes = _boxes.filter(func(b: Rect2i) -> bool: return not r.encloses(b))
	queue_redraw()

## print / printz: text from (col, row) in palette line `line`; '\n' starts the next row
## back at `col`. Characters the font lacks are left blank.
func print_at(col: int, row: int, text: String, line: int = 0) -> void:
	var x := col
	var y := row
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 10:
			x = col
			y += 1
			continue
		var t: int = _chars.get(c, 0)
		if c == 32 or t == 0:
			cells.erase(Vector2i(x, y))
		else:
			cells[Vector2i(x, y)] = ["font", t, line, 0]
		x += 1
	queue_redraw()

## Centred on a row (in cells), as retail's centring prints do (printx -= len / 2).
func print_centered(row: int, text: String, line: int = 0, center_col: int = 16) -> void:
	print_at(center_col - text.length() / 2, row, text, line)

## One tile of a tile set.
func put_tile(col: int, row: int, key: String, tile: int, line: int, flags: int = 0) -> void:
	cells[Vector2i(col, row)] = [key, tile, line, flags]
	queue_redraw()

## Framer: a w x h box (cells) with its border, interior blank (solid colour 0 of
## `fill_line` when `fill`).
func frame(col: int, row: int, w: int, h: int, line: int = 0, fill: bool = true) -> void:
	for y in range(row, row + h):
		for x in range(col, col + w):
			cells[Vector2i(x, y)] = ["fill", 0, line, 0] if fill else null
			if not fill:
				cells.erase(Vector2i(x, y))
	_frame_border(col, row, w, h, line)
	queue_redraw()

## The border tiles: the exported Framer set when there is one, else a drawn line.
func _frame_border(col: int, row: int, w: int, h: int, line: int) -> void:
	if has_tileset("frame"):
		var t: Array = _frame_tiles
		cells[Vector2i(col, row)] = ["frame", t[0], line, 0]
		cells[Vector2i(col + w - 1, row)] = ["frame", t[2], line, 0]
		cells[Vector2i(col, row + h - 1)] = ["frame", t[6], line, 0]
		cells[Vector2i(col + w - 1, row + h - 1)] = ["frame", t[8], line, 0]
		for x in range(col + 1, col + w - 1):
			cells[Vector2i(x, row)] = ["frame", t[1], line, 0]
			cells[Vector2i(x, row + h - 1)] = ["frame", t[7], line, 0]
		for y in range(row + 1, row + h - 1):
			cells[Vector2i(col, y)] = ["frame", t[3], line, 0]
			cells[Vector2i(col + w - 1, y)] = ["frame", t[5], line, 0]
	else:
		_boxes.append(Rect2i(col, row, w, h))

## The Framer's nine tiles (corners, edges, centre) in the "frame" tile set.
var _frame_tiles: Array = [0, 1, 2, 3, 4, 5, 6, 7, 8]
var _boxes: Array[Rect2i] = []

func set_frame_tiles(tiles: Array) -> void:
	_frame_tiles = tiles

func _draw() -> void:
	for b in _boxes:
		var r := Rect2(X0 + b.position.x * 8 + 2, b.position.y * 8 + 2, b.size.x * 8 - 4, b.size.y * 8 - 4)
		draw_rect(r, Color(1, 1, 1), false, 1.0)
	for k in cells:
		var cell: Variant = cells[k]
		if cell == null:
			continue
		var at := Vector2(X0 + k.x * 8, k.y * 8)
		var mod := Color(1, cell[2] / 3.0, 0, 1)
		if cell[0] == "fill":
			# Colour 0 of the line: the font's (0,0) texel is index 0 when the tile is blank.
			draw_rect(Rect2(at, Vector2(8, 8)), Color(0, 0, 0, 0.85))
			continue
		var tex: Texture2D = _tex.get(cell[0])
		if tex == null:
			continue
		var per_row: int = 16 if cell[0] == "font" else _tiles.get(cell[0], 16)
		var t: int = cell[1]
		var src := Rect2((t % per_row) * 8, (t / per_row) * 8, 8, 8)
		var size := Vector2(-8 if cell[3] & 1 else 8, -8 if cell[3] & 2 else 8)
		draw_texture_rect_region(tex, Rect2(at, size), src, mod)
