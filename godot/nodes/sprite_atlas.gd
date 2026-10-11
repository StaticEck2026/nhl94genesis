class_name SpriteAtlas
extends RefCounted
## Sprite frames exported by tools/extract/assets.py: an index atlas and, per frame, its
## rectangle, the origin pixel that sits on the object's projected position, and the
## stick hot spot. Sets: "main" (frameSprData, 845 frames) and "faceoff" (the face-off
## close-up, frames 1-10). Drawing mirrors a frame about its origin for the attribute
## flips (addframe2), so a pixel column px maps to -px-1.

const SETS := {
	"main": ["res://assets/sprites/atlas_idx.png", "res://assets/sprites/frames.json"],
	"faceoff": ["res://assets/sprites/faceoff_idx.png", "res://assets/sprites/faceoff.json"],
}

## set name -> [Texture2D, frames Dictionary]
static var _sets: Dictionary = {}

static func _get_set(name: String) -> Array:
	if _sets.has(name):
		return _sets[name]
	var out: Array = [null, {}]
	var paths: Array = SETS.get(name, ["", ""])
	if FileAccess.file_exists(paths[1]) and ResourceLoader.exists(paths[0]):
		out[0] = load(paths[0])
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(paths[1]))
		if d is Dictionary and d.has("frames"):
			out[1] = d["frames"]
	_sets[name] = out
	return out

static func available(set_name: String = "main") -> bool:
	var s := _get_set(set_name)
	return s[0] != null and not (s[1] as Dictionary).is_empty()

static func has_frame(f: int, set_name: String = "main") -> bool:
	return (_get_set(set_name)[1] as Dictionary).has(str(f & 0x7FF))

## Draws frame f on `ci` with its origin at `at`. The attribute's bits 11 and 12 flip it
## (the frame word's own flag bits XOR in, as addframe2 does).
static func draw_frame(ci: CanvasItem, f: int, at: Vector2, attribute: int, set_name: String = "main") -> void:
	var s := _get_set(set_name)
	var frames: Dictionary = s[1]
	var key := str(f & 0x7FF)
	if s[0] == null or not frames.has(key):
		return
	var e: Dictionary = frames[key]
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
	ci.draw_texture_rect_region(s[0], Rect2(at + pos, size), Rect2(r[0], r[1], r[2], r[3]))
