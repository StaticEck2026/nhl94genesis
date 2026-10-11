class_name SpriteAtlas
extends RefCounted
## The sprite frames exported by tools/extract/assets.py: one index atlas and, per frame,
## its rectangle, the origin pixel that sits on the object's projected position, and the
## stick hot spot. Drawing mirrors the frame about its origin for the attribute flips
## (addframe2), so a pixel column px maps to -px-1.

const ATLAS_PATH := "res://assets/sprites/atlas_idx.png"
const FRAMES_PATH := "res://assets/sprites/frames.json"

static var _texture: Texture2D
static var _frames: Dictionary = {}

static func available() -> bool:
	_load()
	return _texture != null and not _frames.is_empty()

static func _load() -> void:
	if _texture != null or not FileAccess.file_exists(FRAMES_PATH):
		return
	if not ResourceLoader.exists(ATLAS_PATH):
		return
	_texture = load(ATLAS_PATH)
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAMES_PATH))
	if d is Dictionary and d.has("frames"):
		_frames = d["frames"]

static func has_frame(f: int) -> bool:
	_load()
	return _frames.has(str(f & 0x7FF))

## Draws frame f on `ci` with its origin at `at`. flip_h / flip_v are the attribute's
## bits 11 and 12 (the frame word's own flag bits XOR in as addframe2 does).
static func draw_frame(ci: CanvasItem, f: int, at: Vector2, attribute: int) -> void:
	_load()
	var key := str(f & 0x7FF)
	if not _frames.has(key):
		return
	var e: Dictionary = _frames[key]
	var r: Array = e["rect"]
	var o: Array = e["origin"]
	var attr := attribute ^ (f & 0xF800)
	var fh := attr & SimObject.ATTR_XFLIP != 0
	var fv := attr & SimObject.ATTR_YFLIP != 0
	var w := float(r[2])
	var h := float(r[3])
	var pos := Vector2(-float(o[0]), -float(o[1]))
	if fh:
		pos.x = float(o[0]) - w
	if fv:
		pos.y = float(o[1]) - h
	# A negative size flips the texture inside the same rectangle (the renderer makes the
	# size positive and sets its flip flag).
	var size := Vector2(-w if fh else w, -h if fv else h)
	ci.draw_texture_rect_region(_texture, Rect2(at + pos, size), Rect2(r[0], r[1], r[2], r[3]))
