class_name IndicatorsView
extends Node2D
## The on-ice indicators (setffo / uppads / checksso):
## - the stars under the marked players (HockeyWorld.marks): the filled puck-carrier star
##   (392), pad 1's (390) and pad 2's (391), with the player's jersey number and position
##   letter in the font below each. setvideo lists the stars after every sort object, so
##   they draw behind all of them.
## - the off-screen arrows (384-386 pad 1, 387-389 pad 2, and with the multitap 838-840
##   pad 3, 841-843 pad 4) at the screen edge when a pad's player is out of view, in front
##   of every sort object. None on the penalty screen.
## The rules are retail's (116 across, 100 up and down, on the 256 x 224 H32 screen).
## Spec: docs/specs/indicators_and_priority.md section A.

const STAR_FRAMES := {0: 392, 1: 390, 2: 391, 4: 844, 5: 845}
## checksso: the arrow frames by star (ffo 1, 2 pads 1 and 2; ffo 4, 5 pads 3 and 4).
const ARROW_BASE := {1: 384, 2: 387, 4: 838, 5: 841}
const FONT_PATH := "res://assets/sprites/font_idx.png"
const FONT_JSON := "res://assets/sprites/font.json"
## unk_1677A: the position letter by position code (0 goalie blank, 1-2 D, 3 L, 4 C, 5 R).
const LETTERS := " DDLCRX"
const ARROW_X := 116
const ARROW_Y := 100
## jdtab by the edge bits (8 right, 4 left, 1 up, 2 down): the arrow direction.
const JDTAB := {1: 0, 9: 1, 8: 2, 10: 3, 2: 4, 6: 5, 4: 6, 5: 7}
## unk_165BC: per direction the clamped x / y (0 keeps the player's), the frame offset and
## the flips.
const ARROWS := [
	[0, 1, 0, 0], [1, 1, 1, 0], [1, 0, 2, 0], [1, -1, 1, 0x1000],
	[0, -1, 0, 0x1000], [-1, -1, 1, 0x1800], [-1, 0, 2, 0x0800], [-1, 1, 1, 0x0800]]

var game: HockeyGame
var arrows: Node2D
var _font: Texture2D
var _chars := {}
## The marked players' positions as the last setffo drew them (checksso uses those).
var _last := {}

func _ready() -> void:
	game = HockeyGame.find(self)
	if game == null:
		return
	z_index = -3990
	z_as_relative = false
	material = game.palette_material(false)
	if ResourceLoader.exists(FONT_PATH) and FileAccess.file_exists(FONT_JSON):
		_font = load(FONT_PATH)
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FONT_JSON))
		if d is Dictionary:
			for k in d["chars"]:
				_chars[int(k)] = int(d["chars"][k])
	arrows = Node2D.new()
	arrows.name = "Arrows"
	arrows.z_index = 3001
	arrows.z_as_relative = false
	arrows.material = material
	arrows.draw.connect(_draw_arrows)
	add_child(arrows)
	game.stepped.connect(_sync)

func _sync() -> void:
	visible = not game.world.intermission
	queue_redraw()
	arrows.queue_redraw()

# --- the stars --------------------------------------------------------------------------------

func _draw() -> void:
	if game == null or not SpriteAtlas.available():
		return
	var w := game.world
	var drawn := {}
	# ffo 5 first, so ffo 0 (the puck star) ends up in front.
	for k in [5, 4, 2, 1, 0]:
		var n: int = w.marks[k]
		if n > 13:
			continue
		var o := w.objects[n]
		var at := SortObjectView.project_ground(w, o)
		SpriteAtlas.draw_frame(self, STAR_FRAMES[k], at, 0)
		_draw_text(at, o)
		drawn[k] = o.pos()
	_last = drawn

## settext (sub_166E6): tens, units and the position letter, centred under the star.
func _draw_text(at: Vector2, o: SimObject) -> void:
	if _font == null:
		return
	var key := ((o.position & 0xFF) << 8) | (o.rostnum & 0xFF)
	var adj := 0
	var t := (key >> 4) & 0xF
	var c0 := 0x20
	if t == 0:
		adj -= 4
	else:
		c0 = 0x30 + t
	var u := key & 0xF
	var c1 := 0x20 if u == 0xF else 0x30 + u
	var p := 0 if game.world.shootout.display else (key >> 8) & 7
	if p == 0:
		adj += 4
	var c2 := LETTERS.unicode_at(mini(p, LETTERS.length() - 1))
	_glyph(c0, at + Vector2(-12 + adj, 11))
	_glyph(c1, at + Vector2(-4 + adj, 11))
	_glyph(c2, at + Vector2(6 + adj, 11))

func _glyph(c: int, at: Vector2) -> void:
	var t: int = _chars.get(c, 0)
	if t == 0:
		return
	draw_texture_rect_region(_font, Rect2(at, Vector2(8, 8)), Rect2((t % 16) * 8, (t / 16) * 8, 8, 8))

# --- the arrows ----------------------------------------------------------------------------------

## checksso / sub_164D6 for pads 1 and 2, then pad 3 while cont3team is set and pad 4
## while cont4team is too.
func _draw_arrows() -> void:
	if game == null or not SpriteAtlas.available():
		return
	var w := game.world
	if w.side_view():
		return
	var ks := [1, 2]
	if w.cont_team[2] != 0:
		ks.append(4)
		if w.cont_team[3] != 0:
			ks.append(5)
	for k in ks:
		if not _last.has(k):
			continue
		var pos: Vector2i = _last[k]
		if (w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT or w.ba_ps_flags & HockeyWorld.BA_LIVE) and absi(pos.x) >= 0xA6:
			continue
		var dx := pos.x - w.camera.x
		var dy := pos.y - w.camera.y
		var m := 0
		if dx >= ARROW_X:
			m |= 8
		if dx <= -ARROW_X:
			m |= 4
		if dy >= ARROW_Y:
			m |= 1
		if dy <= -ARROW_Y:
			m |= 2
		if not JDTAB.has(m):
			continue
		var a: Array = ARROWS[JDTAB[m]]
		if a[0] != 0:
			dx = a[0] * ARROW_X
		if a[1] != 0:
			dy = a[1] * ARROW_Y
		var rink := Vector2(w.camera.x + dx, w.camera.y + dy)
		SpriteAtlas.draw_frame(arrows, ARROW_BASE[k] + a[2], Vector2(rink.x, -rink.y), a[3])
