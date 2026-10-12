class_name ArenaView
extends Node2D
## The arena's own sprites, setvideo layers 6-8 (L51875): the intermission zamboni
## (showzam), the background animation (sub_FD78A, ArenaAnim), the penalty-box figures,
## the camera flashes and the crowd (showcrowd). They are low-priority sprites: over the
## rink and the centre logo, under the near boards and glass (RinkFront) and under every
## sort object. They carry their own palette lines, with no away swap. The side view
## (penalty screen, intermission) uses the crowd's horizontal frames (+$1F) in screen
## pixels; the background animation is not drawn there.
## The sheets hold assembled figures: tools/extract/arena.py composites the hardware
## pieces offline, so nothing is put together from tiles here.
## Spec: docs/specs/arena_animations.md. Assets: tools/extract/arena.py.

const DIR := "res://assets/arena/"
## Map pixel -> HockeyGame-local (rink/map.json origin_px); side-view screen pixel -> local.
const MAP_ORIGIN := Vector2(192, 368)
const SIDE_ORIGIN := Vector2(128, 112)
## The zamboni's origin is at side-view screen ((zamx >> 2) - 128, $12A - 128).
const ZAM_Y := 0x12A - 128
## The side view's 256x224 screen: the port's wider view would otherwise show the
## zamboni and the edge figures over the margins beside the art.
const SIDE_CLIP := Rect2(-128, -112, 256, 224)
const BOX_AWAY := 0x1A
const BOX_HOME := 0x1D

var game: HockeyGame
## Per sheet: {"tex": Texture2D, "sprites": Array[Rect2] (assembled figures), "frames":
## {key: {"parts": [[x, y, sprite id], ...]}}}.
var _crowd := {}
var _zam := {}
## The background animation's frames by id.
var _bg := {}
var _bg_ids: Array = []
var _hor_offset := 0x1F
var _wave: Array = []
var _side := false
var _mat_rink: ShaderMaterial
var _mat_side: ShaderMaterial

func _ready() -> void:
	game = HockeyGame.find(self)
	if game == null:
		return
	z_index = Rink2D.Z_LOGO + 1
	z_as_relative = false
	_mat_rink = PaletteBank.material(game.palette_texture(false))
	_mat_side = PaletteBank.material(game.palette_texture(true))
	material = _mat_rink
	var c: Variant = _sheet("crowd")
	if c is Dictionary:
		_crowd = c
		_hor_offset = int(_crowd["json"].get("horizontal_offset", 0x1F))
	var z: Variant = _sheet("zamboni")
	if z is Dictionary:
		_zam = z
		for f in _zam["json"]["wave"]:
			_wave.append(int(f))
	var b: Variant = _sheet("bganim")
	if b is Dictionary:
		_bg = b
		var files: Dictionary = _bg["json"]["files"]
		for e in _bg["json"]["ids"]:
			_bg_ids.append(files[e["file"]]["frames"])
	game.stepped.connect(_sync)

## One atlas and its JSON, or null when the export is missing.
func _sheet(n: String) -> Variant:
	var png := DIR + n + "_idx.png"
	var js := DIR + n + ".json"
	if not ResourceLoader.exists(png) or not FileAccess.file_exists(js):
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(js))
	if not d is Dictionary:
		return null
	var sprites: Array = []
	for e in d["sprites"]:
		var r: Array = e["rect"]
		sprites.append(Rect2(r[0], r[1], r[2], r[3]))
	return {"tex": load(png), "sprites": sprites, "frames": d.get("frames", {}), "json": d}

func _sync() -> void:
	var side := game.world.side_view()
	if side != _side:
		_side = side
		material = _mat_side if side else _mat_rink
	queue_redraw()

func _draw() -> void:
	if game == null:
		return
	var w := game.world
	if not _crowd.is_empty():
		# showcrowd, back to front: the crowd, the flash, the home box, the away box.
		_crowd_frame(w.rules.crowd_frame)
		_crowd_frame(w.rules.crowd_flash)
		_box(w.lines.pbnum[0], BOX_HOME)
		_box(w.lines.pbnum[1], BOX_AWAY)
	if not _side and not _bg.is_empty():
		var f := w.arena.shown_frame()
		if f > 0 and w.arena.id < _bg_ids.size():
			var frames: Dictionary = _bg_ids[w.arena.id]
			_parts(_bg, frames.get(str(f), {}), -MAP_ORIGIN)
	if w.zamx >= 0 and not _zam.is_empty():
		_zamboni(w)

## box (sub_16226): n = min(nibble, 3) seated figures, base + n - 1 in front.
func _box(n: int, base: int) -> void:
	for k in mini(n & 0xF, 3):
		_crowd_frame(base + k)

func _crowd_frame(f: int) -> void:
	if f <= 0:
		return
	if _side:
		_parts(_crowd, _crowd["frames"].get(str(f + _hor_offset), {}), -SIDE_ORIGIN)
	else:
		_parts(_crowd, _crowd["frames"].get(str(f), {}), -MAP_ORIGIN)

## showzam: the driver (waving when the home team leads), the wheels, then the body in
## front.
func _zamboni(w: HockeyWorld) -> void:
	var x := w.zamx >> 2
	var origin := Vector2(x - 128, ZAM_Y) - SIDE_ORIGIN
	var j: Dictionary = _zam["json"]
	var driver := 5
	if w.stats[0].goals > w.stats[1].goals and not _wave.is_empty():
		var k := maxi(x - 0xDA, 0) >> 2
		driver = _wave[mini(k, _wave.size() - 1)]
	var wheels: Array = j["wheels"]
	var wheel: int = wheels[(x >> 1) % wheels.size()]
	for f in [driver, wheel, int(j["body"])]:
		_parts(_zam, _zam["frames"].get(str(f), {}), origin)

## A frame's assembled figures (they never overlap, so any order).
func _parts(sheet: Dictionary, frame: Dictionary, origin: Vector2) -> void:
	var parts: Array = frame.get("parts", [])
	var tex: Texture2D = sheet["tex"]
	var sprites: Array = sheet["sprites"]
	for part in parts:
		var s: Array = part
		var src: Rect2 = sprites[int(s[2])]
		var dst := Rect2(origin + Vector2(s[0], s[1]), src.size)
		if _side:
			var c := dst.intersection(SIDE_CLIP)
			if c.size.x <= 0 or c.size.y <= 0:
				continue
			src = Rect2(src.position + (c.position - dst.position), c.size)
			dst = c
		draw_texture_rect_region(tex, dst, src)
