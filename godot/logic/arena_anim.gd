class_name ArenaAnim
extends RefCounted
## The arena and bench background animations: fans in the stands, the hat-trick hats, the
## benches standing up. sub_FE510 starts one (L973950), sub_FE2C8 steps its script
## (L973463), sub_FE548 stops it (L973971); sub_FD78A draws it (ArenaView). The scripts
## (table unk_FE364) are exported offline to res://assets/arena/bganim.json.
## Spec: docs/specs/arena_animations.md section 4.

const DATA_PATH := "res://assets/arena/bganim.json"
const HAT_TRICK := 0
const BENCH_RIPPLE := 7

## Per id: {"script": [[frame, preload], ...], "loop": bool}.
static var _scripts: Array = []

var w: HockeyWorld
## word_FFD6B4: the running id, -1 none.
var id: int = -1
## dword_FFD6BA != 0: the first step after a start has loaded the script.
var loaded: bool = false
## word_FFD6B0 / word_FFD6B2: the script entry and its countdown.
var index: int = 0
var counter: int = 0
## word_FFD6AE: the frame shown.
var frame: int = 1
## byte_FFC2FC bit 0: puckfaceoff picked an id that puckfaceoff2 may start.
var pending_ok: bool = false

func _init(world: HockeyWorld) -> void:
	w = world
	_load()

static func _load() -> void:
	if not _scripts.is_empty() or not FileAccess.file_exists(DATA_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not d is Dictionary:
		return
	for e in d["ids"]:
		var s: Array = []
		for pair in e["script"]:
			s.append([int(pair[0]), int(pair[1])])
		_scripts.append({"script": s, "loop": e["end"] == "loop"})

static func script_of(n: int) -> Array:
	_load()
	return _scripts[n]["script"] if n >= 0 and n < _scripts.size() else []

## sub_FE510: a new id replaces whatever runs; it also consumes the faceoff's pending id.
func start(n: int) -> void:
	id = n
	loaded = false
	frame = 1
	index = 0
	counter = 0
	if w.faceoff:
		w.faceoff.overlay_request = -1

## sub_FE548 (also at the puck drop).
func stop() -> void:
	id = -1
	pending_ok = false

## sub_FE2C8: periodiceevents every loop (horizontal mode too) and the intermission's
## waitxsr every vblank.
func step(d7: int) -> void:
	if id < 0:
		return
	if not loaded:
		loaded = true
		index = 0
		_entry()
		return
	counter -= d7
	if counter < 0:
		index += 1
		_entry()

## sub_FE326: the script's next (frame, preload); $FF loops, $FE ends.
func _entry() -> void:
	_load()
	if id >= _scripts.size():
		stop()
		return
	var s: Array = _scripts[id]["script"]
	if index >= s.size():
		if not _scripts[id]["loop"] or s.is_empty():
			stop()
			return
		index = 0
	frame = s[index][0]
	counter = s[index][1]

## What sub_FD78A would draw: the frame, or 0 for nothing.
func shown_frame() -> int:
	if id < 0 or not loaded:
		return 0
	return frame

## The goal summary (loc_1889A): a home skater's third goal of the game throws the hats.
## Retail compares the team number with HomeTeam, so a same-franchise away scorer counts.
func hat_trick_check() -> void:
	if w.score_summary.is_empty():
		return
	var rec: Dictionary = w.score_summary[w.score_summary.size() - 1]
	var team := 1 if rec["away"] else 0
	var st := w.stats[team]
	var scorer := int(rec["scorer"])
	if not TeamStats.valid_pnum(scorer) or st.player_goals[scorer] != 3:
		return
	var goalies := st.data.goalie_count if st.data else 2
	if scorer < goalies:
		return
	if st.team_index != w.stats[0].team_index:
		return
	start(HAT_TRICK)
