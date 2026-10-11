extends Control
## The title screen (newTitleScreen, $FF042): the photo, the NHL shield, the NHLPA logo
## and the "NHL HOCKEY 94" title fade in, the logos slide in on plane B's line scroll,
## and the credits scroll up under the photo, a block at a time. A new Start press, or
## the end of the credits, goes on to the menus (the setup screen). The edition picks the
## art: retail, or the fight patch's (title_patch.asm, credits_patch.asm).
##
## The screen is H32, 256x224, centred in the 320x224 view. Every frame replays the
## VBlank handler (loc_FF348: latch the scroll values, cramfade, the line-scroll step
## sub_FF3F8) and then the routine's own loop. Assets: tools/extract/title.py. Spec:
## docs/specs/title_screen.md.

const DIRS := {MatchConfig.Edition.RETAIL: "res://assets/title/retail/",
	MatchConfig.Edition.FIGHT: "res://assets/title/fight/"}
const NEXT_SCENE := "res://ui/setup_screen.tscn"
const W := 256
const H := 224
## The window plane covers lines 0-183; plane A (the credits) shows below it.
const WIN_LINES := 0x17 * 8
## Title song (song $78), started on frame 1; it plays on into the menus.
const SONG_TITLE := 0x78

var _screen: Control
var _pal_img: Image
var _pal_tex: ImageTexture
var _tex := {}
var _meta: Dictionary = {}
var _font_line := 1
var _glyphs := {}
var _blocks: Array = []
var _sfx: SfxBank

## palfadenew (the target), the CRAM, and cramfade's counter.
var _target: Array = []
var _cram: Array = []
var _palcount := 0x20
## Plane B's line scroll table (RAM) and the copy the VBlank latched (VRAM), the slide's
## start delay (word_FFBF14) and speed (Hscroll).
var _hs := PackedInt32Array()
var _vram_hs := PackedInt32Array()
var _hs_timer := 0x50
var _hs_speed := 0x14
## Plane A: 32 rows x 32 columns of font tiles (-1 blank), Vscroll and the latched VSRAM.
var _pa: Array = []
var _vscroll := 0
var _vsram := 0
## The routine's loop: 0 the first block's hold (word_FFB8B2), 1 the pause after it,
## 2 a block scrolling in, 3 its hold; 4 leaving (fade to black).
var _phase := 0
var _count := 0
var _b8b2 := 0x104
var _block := 0
var _frame := 0

func _ready() -> void:
	var ed: int = Sim.match.edition if Sim.match else MatchConfig.Edition.FIGHT
	var dir: String = DIRS[ed]
	if not FileAccess.file_exists(dir + "title.json"):
		dir = DIRS[MatchConfig.Edition.RETAIL]
	if not FileAccess.file_exists(dir + "title.json"):
		get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
		return
	_meta = JSON.parse_string(FileAccess.get_file_as_string(dir + "title.json"))
	for k in ["win_lo", "win_hi", "b_lo", "b_hi", "font"]:
		_tex[k] = load(dir + k + "_idx.png")
	_target = _meta["cram"]
	_font_line = int(_meta["font"]["line"])
	for k in _meta["font"]["glyphs"]:
		_glyphs[int(k)] = int(_meta["font"]["glyphs"][k])
	_blocks = _meta["credits_loop"]
	for y in 4:
		_cram.append([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	_hs.resize(H)
	_vram_hs.resize(H)
	for y in H:
		_hs[y] = int(_meta["hscroll_b"][y]) & 0xFFFF
	for r in 32:
		var row := PackedInt32Array()
		row.resize(32)
		row.fill(-1)
		_pa.append(row)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.position = Vector2((320 - W) / 2, 0)
	_screen.size = Vector2(W, H)
	_screen.clip_contents = true
	_pal_img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	_screen.material = PaletteBank.material(_pal_tex)
	_screen.draw.connect(_draw_screen)
	add_child(_screen)
	_sfx = SfxBank.new()
	add_child(_sfx)
	# Before the interrupts: the first block (©, licence) at Vscroll 0, then +$20.
	_print_block(_meta["credits_first"])
	_vscroll = 0x20
	_sfx.play_song(SONG_TITLE)

func _physics_process(_delta: float) -> void:
	if _meta.is_empty():
		return
	_frame += 1
	_vblank()
	if _phase == 4:
		_fade_out()
	else:
		_main_step()
	_screen.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	# sub_FF318: only a new Start press leaves.
	if _phase != 4 and (event.is_action_pressed("p1_start") or event.is_action_pressed("p2_start")):
		get_viewport().set_input_as_handled()
		_leave()

# --- loc_FF348 -----------------------------------------------------------------------------

func _vblank() -> void:
	_vram_hs = _hs.duplicate()
	_vsram = _vscroll
	_cramfade()
	_slide()

## cramfade (L44101): toward palfadenew one component a frame (R, B, G in turn), for 25
## frames once palcount drops to $18.
func _cramfade() -> void:
	if _palcount & 0x8000:
		return
	_palcount = (_palcount - 1) & 0xFFFF
	if _palcount & 0x8000 or _palcount > 0x18:
		return
	_step_toward(_target, _palcount)

func _step_toward(target: Array, count: int) -> void:
	var sh := (count % 3) * 4
	var step := 2 << sh
	var mask := 0xE << sh
	for k in 4:
		for i in 16:
			var cur: int = _cram[k][i]
			var c := cur & mask
			var t: int = int(target[k][i]) & mask
			if c == t:
				continue
			c = c + step if c < t else c - step
			_cram[k][i] = (cur & ~mask & 0xFFFF) | c
	_upload_palette()

func _upload_palette() -> void:
	for k in 4:
		for i in 16:
			_pal_img.set_pixel(i, k, PaletteBank.cram(_cram[k][i]))
	_pal_tex.update(_pal_img)

## sub_FF3F8: after the delay, the upper lines (shield, NHLPA logo) come in from the left
## and the title's lines from the right, 20 px a frame.
func _slide() -> void:
	_hs_timer -= 1
	if _hs_timer >= 0:
		return
	_hs_timer = 0
	for line in H:
		var d0 := 0xDF - line
		if d0 <= 0x28:
			continue
		var v := _hs[line]
		if d0 >= 0x8F:
			if v == 0:
				continue
			v = (v + _hs_speed) & 0xFFFF
			if v & 0xFC00 != 0xFC00:
				v = 0
		else:
			v = (v - _hs_speed) & 0xFFFF
			if v & 0x8000:
				v = 0
		_hs[line] = v

# --- the routine's loop -----------------------------------------------------------------------

func _main_step() -> void:
	match _phase:
		0:
			_b8b2 = maxi(_b8b2 - 2, 0)
			if _b8b2 == 0:
				_phase = 1
				_count = 0x3C + 1
		1:
			_count -= 1
			if _count == 0:
				_start_block()
		2:
			# 40 px, one every second frame.
			_count += 1
			if _count % 2 == 0:
				_vscroll = (_vscroll + 1) & 0xFFFF
			if _count == 0x28 * 2:
				_phase = 3
				_count = 0x78 + 1
		3:
			_count -= 1
			if _count == 0:
				_block += 1
				if _block >= _blocks.size():
					_leave()
				else:
					_start_block()

func _start_block() -> void:
	_print_block(_blocks[_block])
	_phase = 2
	_count = 0

## sub_FF2C8: six rows below the visible text are erased, then the block's lines go in,
## each from column $11 - length / 2. '^' skips a column, '@' is blank.
func _print_block(lines: Array) -> void:
	var printy := ((HockeyWorld.s16(_vscroll) >> 3) + 0x1C) & 0x1F
	for r in 6:
		_pa[(printy + r) & 31].fill(-1)
	for ln in lines:
		var x: int = int(ln[0])
		var text: String = ln[1]
		for i in text.length():
			var ch := text.unicode_at(i)
			if ch == 0x5E:
				x += 1
				continue
			var t: int = -1 if ch == 0x40 else _glyphs.get(ch, -1)
			if x >= 0 and x < 32:
				_pa[printy][x] = t
			x += 1
		printy = (printy + 1) & 0x1F

## Leaving: the next screen's setvram fades the frozen title to black in 25 frames.
func _leave() -> void:
	_phase = 4
	_count = 0x18
	_target = []
	for k in 4:
		_target.append([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	_palcount = 0xFFFF

func _fade_out() -> void:
	if _count < 0:
		get_tree().change_scene_to_file(NEXT_SCENE)
		return
	_step_toward(_target, _count)
	_count -= 1

# --- drawing ----------------------------------------------------------------------------------

## Back to front: plane B low, the window low, plane A (the credits, below the window),
## plane B high (the logos), the window high.
func _draw_screen() -> void:
	_draw_plane_b(_tex["b_lo"])
	_screen.draw_texture_rect_region(_tex["win_lo"], Rect2(0, 0, W, WIN_LINES), Rect2(0, 0, W, WIN_LINES))
	_draw_credits()
	_draw_plane_b(_tex["b_hi"])
	_screen.draw_texture_rect_region(_tex["win_hi"], Rect2(0, 0, W, WIN_LINES), Rect2(0, 0, W, WIN_LINES))

## Plane B is 1024 px wide and blank past its first 256; each line moves by its scroll.
func _draw_plane_b(tex: Texture2D) -> void:
	for y in H:
		var x0 := posmod(HockeyWorld.s16(_vram_hs[y]), 1024)
		if x0 < W:
			_screen.draw_texture_rect_region(tex, Rect2(x0, y, W, 1), Rect2(0, y, W, 1))
		if x0 > 1024 - W:
			_screen.draw_texture_rect_region(tex, Rect2(x0 - 1024, y, W, 1), Rect2(0, y, W, 1))

func _draw_credits() -> void:
	var font: Texture2D = _tex["font"]
	var y := WIN_LINES
	while y < H:
		var py := (y + _vsram) & 255
		var row := py >> 3
		var off := py & 7
		var h := mini(8 - off, H - y)
		for col in 32:
			var t: int = _pa[row][col]
			if t < 0:
				continue
			_screen.draw_texture_rect_region(font, Rect2(col * 8, y, 8, h),
					Rect2((t % 16) * 8, (t / 16) * 8 + off, 8, h))
		y += h
