class_name PaletteBank
extends RefCounted
## CRAM palettes from res://assets/palettes.json (tools/extract/assets.py) as 16 x 4
## textures for res://shaders/palette.gdshader: the two rink lines (or the side view's)
## and the home and away teams' uniforms (SetTeamColors).

const DATA_PATH := "res://assets/palettes.json"
const SHADER := preload("res://shaders/palette.gdshader")

static var _data: Dictionary = {}

static func available() -> bool:
	_load()
	return not _data.is_empty()

static func _load() -> void:
	if not _data.is_empty() or not FileAccess.file_exists(DATA_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if d is Dictionary:
		_data = d

## A CRAM word (----BBB-GGG-RRR-) to a colour, 3 bits per channel.
static func cram(w: int) -> Color:
	return Color(((w >> 1) & 7) / 7.0, ((w >> 5) & 7) / 7.0, ((w >> 9) & 7) / 7.0)

## The game's CRAM: lines 0-1 from `base` ("rink", "rink_reverse" or "side"), line 2 the
## home team's home uniform, line 3 the away team's away uniform (team numbers 0-27).
static func texture(home_team: int, away_team: int, base: String = "rink") -> ImageTexture:
	_load()
	var img := Image.create(16, 4, false, Image.FORMAT_RGBA8)
	if _data.is_empty():
		return ImageTexture.create_from_image(img)
	var lines: Array = _data[base]
	var teams: Array = _data["teams"]
	var rows: Array = [lines[0], lines[1],
		teams[clampi(home_team, 0, 27)]["home"], teams[clampi(away_team, 0, 27)]["away"]]
	for y in 4:
		for x in 16:
			img.set_pixel(x, y, cram(int(rows[y][x])))
	return ImageTexture.create_from_image(img)

## A ShaderMaterial for index textures with this palette.
static func material(pal: Texture2D, away: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("palette", pal)
	m.set_shader_parameter("away", away)
	return m
