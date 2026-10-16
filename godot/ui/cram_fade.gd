class_name CramFade
extends CanvasLayer
## The palette fades between screens (cramfade L44101, forcefade L44081, setvram L44784,
## forceblack L44039), over everything on screen.
## - Leaving a screen, retail's setvram / forceblack sets every target colour to black
##   with palcount = $18 and waits (forcefade): 25 VBlanks with the picture frozen.
## - The next screen is drawn while the CRAM is black, then sets palcount = $18 (or $20,
##   which waits 7 VBlanks first): the colours come in over 24 VBlanks while the screen
##   already runs.
## Each VBlank palcount drops by one; at $18 and below it moves one component of every
## colour one level toward its target, component palcount % 3 (0 red, 1 green, 2 blue).
## So a component takes 8 steps in all, and 0-7 levels cover every CRAM value.
##
## One node under the root, kept across scene changes: `out()` darkens the current screen
## and then runs a callback (the scene change); a new scene comes in by itself. Screens
## that need another start call `come_in()`.

const NAME := "CramFade"
const SHADER := preload("res://shaders/cram_fade.gdshader")
const FULL := 0x18

var _rect: ColorRect
var _mat: ShaderMaterial
## palcount; negative when idle.
var _count := -1
var _in := Vector3(8, 8, 8)
var _out := Vector3.ZERO
var _fading_out := false
var _done: Callable
var _in_done: Callable
var _scene: Node
static var _inst: CramFade

## The fade node (made on first use). Null outside a scene tree.
static func get_in(tree: SceneTree) -> CramFade:
	if tree == null or tree.root == null:
		return null
	if not is_instance_valid(_inst):
		_inst = CramFade.new()
		_inst.name = NAME
		tree.root.add_child.call_deferred(_inst)
	return _inst

## setvram / forceblack: darken the screen over 25 VBlanks, then call `done`.
static func out(tree: SceneTree, done: Callable) -> void:
	var f := get_in(tree)
	if f == null:
		done.call()
		return
	f._start_out(tree, done)

## setvram, then the next screen: fade out, change scene, and the new scene fades in.
static func change_scene(tree: SceneTree, path: String) -> void:
	if tree == null:
		return
	out(tree, func() -> void: tree.change_scene_to_file(path))

## The new screen's palcount (FULL, or $20 for a late start). `done` runs when the colours
## are in (retail waits for that before play resumes after the pause menu).
static func come_in(tree: SceneTree, palcount: int = FULL, done: Callable = Callable()) -> void:
	var f := get_in(tree)
	if f:
		f._start_in(palcount)
		f._in_done = done
	elif done.is_valid():
		done.call()

## True when no fade runs and the screen shows its own colours.
static func idle(tree: SceneTree) -> bool:
	if tree == null or not is_instance_valid(_inst):
		return true
	return _inst._count < 0 and not _inst._fading_out

## True while a fade to black is running or holds the screen black (ignore input then).
static func busy(tree: SceneTree) -> bool:
	if tree == null or not is_instance_valid(_inst):
		return false
	return _inst._fading_out

func _init() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)

func _start_out(tree: SceneTree, done: Callable) -> void:
	if _fading_out and _count < 0:
		# Already black (a screen that leaves at once, like an empty Name Entry).
		_scene = tree.current_scene
		done.call_deferred()
		return
	_scene = tree.current_scene
	_done = done
	_fading_out = true
	_out = Vector3.ZERO
	_count = FULL
	_apply()

func _start_in(palcount: int) -> void:
	_fading_out = false
	_out = Vector3.ZERO
	_in = Vector3.ZERO
	_count = palcount
	_apply()

func _physics_process(_delta: float) -> void:
	# A new scene after a fade out comes in by itself.
	if _fading_out and _count < 0 and get_tree().current_scene != _scene:
		_start_in(FULL)
		return
	if _count < 0:
		return
	_count -= 1
	if _count < 0:
		var cb := _done if _fading_out else _in_done
		if _fading_out:
			_done = Callable()
		else:
			_in_done = Callable()
		_apply()
		if cb.is_valid():
			cb.call()
		return
	if _count <= FULL:
		var c := _count % 3
		if _fading_out:
			_out[c] += 1
		else:
			_in[c] += 1
	_apply()

func _apply() -> void:
	var idle := not _fading_out and _in.x >= 8 and _in.y >= 8 and _in.z >= 8
	_rect.visible = not idle
	_mat.set_shader_parameter("steps_in", _in)
	_mat.set_shader_parameter("steps_out", _out)
