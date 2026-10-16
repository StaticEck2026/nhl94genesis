class_name ScreenMode
extends RefCounted
## The Genesis screen modes. In play (and on the penalty, pause and intermission
## screens) retail runs H32: 256 x 224. The stats pages switch to H40: 320 x 224 (sub_9BD8
## / $9CD8). A TV shows both across the same width, so the viewport is stretched to the
## window (an H32 pixel is 1.25 times as wide as an H40 one). The rest of the port (title,
## setup) keeps the project's 320 x 224 with its aspect.

const H32 := Vector2i(256, 224)
const H40 := Vector2i(320, 224)
## The overlays are laid out for a 320-wide screen with the 256 one centred in it; in H32
## their CanvasLayers shift back by this much.
const H32_OFFSET := Vector2(-32, 0)

static func set_h32(tree: SceneTree, h32: bool) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_size = H32 if h32 else H40
	tree.root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE

## Back to the project's own setting (the title and setup screens).
static func restore(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_size = H40
	tree.root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
