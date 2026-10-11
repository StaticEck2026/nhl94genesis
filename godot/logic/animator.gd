class_name Animator
extends RefCounted
## updateanim (L35703): steps each object's SPA animation and sets its sprite frame.
## Animation data is SPAList exported offline to res://data/spalist.json
## (tools/extract/spalist.py). Spec: docs/specs/animation_assets.md section 1.

const DATA_PATH := "res://data/spalist.json"
## The fight patch's nine animations ($1B96-$1CD6), tools/extract/fight_patch.py.
const FIGHT_PATH := "res://data/spalist_fight.json"

## id -> {"loop": bool, "dirs": [[[frame, time], ...] x 8]}
var anims: Dictionary = {}

func _init() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("Animator: %s missing; run tools/extract/spalist.py" % DATA_PATH)
		return
	for path in [DATA_PATH, FIGHT_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and data.has("anims"):
			for k in data["anims"]:
				anims[int(k)] = data["anims"][k]

func loaded() -> bool:
	return not anims.is_empty()

## The frame list updateanim uses for an object's facing (mirrored when x-flipped).
func frame_list(o: SimObject, horizontal: bool) -> Array:
	var e: Dictionary = anims[o.spa]
	var dir := o.facing() & 7
	if horizontal and o.index < 12:
		dir = (dir - 2) & 7
	if o.x_flip():
		dir = (8 - dir) & 7
	return e["dirs"][dir]

## One updateanim call.
func update(o: SimObject, d7: int, horizontal: bool) -> void:
	if o.spa == 0 or not anims.has(o.spa):
		o.flags &= ~SimObject.PF_ALOCK
		o.flags2 &= ~SimObject.PF2_AIP
		return
	var e: Dictionary = anims[o.spa]
	var list := frame_list(o, horizontal)
	var idx := mini(o.spa_num >> 2, list.size() - 1)
	# The frame shown this loop is read before any advance (one-loop lag).
	var d2: int = list[idx][0]
	if o.spa_cnt >= 0:
		o.spa_cnt -= d7
		if o.spa_cnt >= 0:
			_cframe(o, d2, d7)
			return
		o.spa_num += 4
		idx += 1
		var finished: bool = idx >= list.size() or int(list[idx - 1][1]) < 0
		if finished:
			idx = 0
			o.spa_num = 0
			o.flags &= ~SimObject.PF_ALOCK
			o.flags2 &= ~SimObject.PF2_AIP
			o.flags3 &= ~SimObject.PF3_FALLING
			if not e["loop"]:
				o.spa = 0
	o.spa_cnt = absi(int(list[idx][1]))
	_cframe(o, d2, d7)

## CFRAME: frame changes are held back for 4 loops after a change (de-glitch).
static func _cframe(o: SimObject, d2: int, d7: int) -> void:
	o.glitch = (o.glitch - d7) & 0xFF
	if o.glitch < 0x80:
		return
	o.glitch = 0
	if o.frame == d2:
		return
	o.frame = d2
	o.glitch = 4
