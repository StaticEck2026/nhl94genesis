class_name ReplayRecorder
extends RefCounted
## The instant-replay buffer (updatereplay L35236, SetRCords L35038). Every loop, after
## checkwindow, DoGameFrame stores a record: the 16 sort objects' positions, frames and
## flips, the skaters' roster slots and positions, the puck's height, the sound played
## that loop, the markers, the crowd frame, the gloves, the penalty-box counts and the
## camera. Retail packs a record into $62 bytes of a ring at $FFFF0000-$FFFFAF54, so it
## holds RECORDS loops (about 7.6 seconds) and wraps; the port keeps the same count with
## full values. While sflags2 bit 2 (SF2_NOREC) is set the newest record is overwritten
## in place, except for a grace count (word_FFDEF0, 10 after a penalty-shot goal).

const RECORDS := 0xAF54 / 0x62
const OBJECTS := 16

var w: HockeyWorld
var buf: Array = []
## The newest record (recbpr) and whether the ring has wrapped (sflags bit 4).
var head := 0
var full := false
## word_FFDEF0.
var grace := 0
## lastsfx: the latest sound since the last record, -1 none (bit 7 "already stored").
var _sfx := -1

func _init(world: HockeyWorld) -> void:
	w = world
	reset()

## StartGame (L29878): an empty buffer.
func reset() -> void:
	buf.clear()
	buf.resize(RECORDS)
	head = 0
	full = false
	grace = 0
	_sfx = -1

func on_sound(id: int) -> void:
	_sfx = id

## updatereplay.
func record(d7: int) -> void:
	if w.gmode & HockeyWorld.GM_HL:
		return
	var advance := true
	if w.sflags2 & GameRules.SF2_NOREC:
		advance = false
		if grace != 0:
			grace -= 1
			advance = true
	if advance and buf[head] != null:
		head += 1
		if head >= RECORDS:
			head = 0
			full = true
	buf[head] = snapshot(d7)
	_sfx = -1

## How many records the buffer holds.
func count() -> int:
	if full:
		return RECORDS
	return head + 1 if buf[head] != null else 0

## The k-th oldest record (0 = the oldest).
func at(k: int) -> Dictionary:
	var n := count()
	if n == 0:
		return {}
	k = clampi(k, 0, n - 1)
	var i := (head + 1 + k) % RECORDS if full else k
	return buf[i]

func snapshot(d7: int) -> Dictionary:
	var objs := []
	for i in OBJECTS:
		var o := w.objects[i]
		objs.append([o.pos_fx, o.z_fx, o.frame, o.attribute, o.pnum, o.position])
	return {"objs": objs, "sfx": _sfx, "d7": d7,
		"marks": w.marks.duplicate(), "crowd": [w.rules.crowd_frame, w.rules.crowd_flash],
		"gloves": [w.fight.glove_x, w.fight.glove_y], "pbnum": w.lines.pbnum.duplicate(),
		"camera": w.camera}

## SetRCords: the record's state onto the objects (display state only).
func apply(r: Dictionary) -> void:
	if r.is_empty():
		return
	for i in OBJECTS:
		var e: Array = r["objs"][i]
		var o := w.objects[i]
		o.pos_fx = e[0]
		o.z_fx = e[1]
		o.frame = e[2]
		o.attribute = e[3]
		o.pnum = e[4]
		o.position = e[5]
	w.marks = r["marks"].duplicate()
	w.rules.crowd_frame = r["crowd"][0]
	w.rules.crowd_flash = r["crowd"][1]
	w.fight.glove_x = r["gloves"][0]
	w.fight.glove_y = r["gloves"][1]
	w.lines.pbnum = r["pbnum"].duplicate()
	w.camera = r["camera"]
