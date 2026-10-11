class_name LineLogic
extends RefCounted
## Lines and personnel: SetPersonel, SetPlList, findAvailablePlayer, ResetBench,
## CompLine, getlinee, the line-change menu (SetLCmode, getlchoice, lineinput, lcfound)
## and the trips to and from the bench and the box (assbench $0B, assben $09,
## asspenalty $0C, assdopen $0D, assepen $0A).
## Spec: docs/specs/input_linechanges.md sections 6-7, faceoffs_offsides.md (CompLine).

const ASS_BEN := 0x09
const ASS_EPEN := 0x0A
const ASS_BENCH := 0x0B
const ASS_PENALTY := 0x0C
const ASS_DOPEN := 0x0D

const SPA_HOP_ON := 0xF6E   ## board hop (assben, asspenalty)
const SPA_HOP_OFF := 0xFAC  ## board hop (assbench, assepen)

## priolist (L57829): positions in order of importance.
const PRIOLIST: Array[int] = [0, 1, 2, 4, 3, 5, 6, 0xFF]
## sublist (ROM $1921C): start offset per position code into SUBLIST, then the runs of
## line-table bytes (8 * line + position). Runs are not terminated individually.
const SUBLIST_START: Array[int] = [0x0E, 0x0E, 0x1C, 0x2A, 0x54, 0x3F, 0x54]
const SUBLIST_BASE := 0x0E
const SUBLIST: Array[int] = [
	0x01, 0x09, 0x11, 0x19, 0x21, 0x29, 0x31,
	0x02, 0x0A, 0x12, 0x1A, 0x22, 0x2A, 0x32,
	0x02, 0x0A, 0x12, 0x1A, 0x22, 0x2A, 0x32,
	0x01, 0x09, 0x11, 0x19, 0x21, 0x29, 0x31,
	0x03, 0x0B, 0x13, 0x1B, 0x23, 0x2B, 0x33,
	0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35,
	0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34,
	0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35,
	0x03, 0x0B, 0x13, 0x1B, 0x23, 0x2B, 0x33,
	0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34,
	0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34,
	0x03, 0x0B, 0x13, 0x1B, 0x23, 0x2B, 0x33,
	0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35,
	0xFF,
]
## CompLine _hl1 (home reacts to the away line), rows normal / leading / trailing in the 3rd.
const HL1: Array = [[0, 1, 2, 0, 1, 0, 1], [2, 0, 1, 2, 0, 2, 0], [0, 1, 0, 0, 1, 0, 1]]
## CompLine _al1 candidates.
const AL1: Array = [[0, 1, 2], [0, 2, 1], [0, 1, 0]]
## getlchoice _tab: menu rows A/B/C to a line, by strength (even, PP, PK) and current line.
const LCHOICE: Array = [
	[[0, 1, 2], [1, 2, 0], [2, 0, 1], [0, 1, 2], [0, 1, 2], [0, 1, 2], [0, 1, 2]],
	[[3, 4, -1], [3, 4, -1], [3, 4, -1], [3, 4, -1], [4, 3, -1], [3, 4, -1], [3, 4, -1]],
	[[5, 6, -1], [5, 6, -1], [5, 6, -1], [5, 6, -1], [5, 6, -1], [5, 6, -1], [6, 5, -1]],
]

var w: HockeyWorld
## PlList: 0-5 one-based roster slots wanted on the ice, 6-11 their positions.
var pl_list: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## PBnum: players in the box per team (home high nibble, away low nibble in retail).
var pbnum: PackedInt32Array = PackedInt32Array([0, 0])

## The line menu opened, changed or closed for a team (UI only).
signal menu_changed(team: int)

func _init(world: HockeyWorld) -> void:
	w = world

func register(t: Dictionary) -> void:
	t[ASS_BEN] = func(o: SimObject, d7: int) -> void: assben(o, d7)
	t[ASS_EPEN] = func(o: SimObject, d7: int) -> void: assepen(o, d7)
	t[ASS_BENCH] = func(o: SimObject, d7: int) -> void: assbench(o, d7)
	t[ASS_PENALTY] = func(o: SimObject, d7: int) -> void: asspenalty(o, d7)
	t[ASS_DOPEN] = func(o: SimObject, d7: int) -> void: assdopen(o, d7)

func _objs(team: int) -> Array[SimObject]:
	var first := w.stats[team].first_object
	var out: Array[SimObject] = []
	for i in 6:
		out.append(w.objects[first + i])
	return out

## The current line's 8 slots from the RAM lines (zeros without team data).
func _line(team: int, line: int) -> PackedInt32Array:
	var rl := w.stats[team].ram_lines
	if rl.size() < (line + 1) * 8:
		return PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	return rl.slice(line * 8, line * 8 + 8)

func _status(team: int, v: int) -> int:
	# v is one-based; 0 reads the word before the status table (the last energy word).
	if v == 0:
		return w.stats[team].energy[TeamStats.ROSTER - 1]
	if v < 1 or v > TeamStats.ROSTER:
		return TeamStats.TMPDST_INJURED_GAME
	return w.stats[team].tmpdst[v - 1]

static func _unavailable(s: int) -> bool:
	return s > 0 or s == TeamStats.TMPDST_INJURED_PERIOD or s == TeamStats.TMPDST_INJURED_GAME

# --- who goes on ---------------------------------------------------------------------

## SetPersonel (L51236): tag the team's six objects with newpos / newpnum for the
## players the current line wants on. Players already out stay in their object.
func set_personel(team: int) -> void:
	var objs := _objs(team)
	if w.stats[team].data == null:
		# No roster (sandbox, tests): whoever is out stays out.
		for o in objs:
			o.newpos = o.position if o.position >= 0 else -1
			o.newpnum = o.pnum & 0xFF if o.position >= 0 else -1
		return
	for o in objs:
		o.newpos = -1
		o.newpnum = -1
	set_pl_list(team)
	for i in range(5, -1, -1):
		var s := pl_list[i]
		if s == 0:
			continue
		s -= 1
		for o in objs:
			if (o.pnum & 0xFF) == s:
				o.newpos = pl_list[6 + i]
				o.newpnum = s
				pl_list[i] = 0
				break
	var a0: SimObject = null
	for i in range(5, -1, -1):
		var s := pl_list[i]
		if s == 0:
			continue
		s -= 1
		# A free object (no newpnum), preferring one on the ice; the last free one seen
		# otherwise (retail's runaway past the six objects is not reproduced).
		var d3 := 5
		var k := 0
		while k < 6:
			var o := objs[k]
			k += 1
			if o.newpnum >= 0:
				d3 -= 1
				if d3 != -1:
					continue
				break
			a0 = o
			if o.position >= 0:
				break
			d3 -= 1
			if d3 == -1:
				break
		if a0 != null:
			a0.newpos = pl_list[6 + i]
			a0.newpnum = s
		pl_list[i] = 0

## SetPlList (L51300): PlList from the current line, with substitutes for anyone hurt
## or in the box.
func set_pl_list(team: int) -> void:
	var st := w.stats[team]
	for i in 6:
		pl_list[i] = 0
	var off := 1 if w.goalie.goalie_pulled(team) else 0
	var line := _line(team, st.line)
	for i in range(st.on_ice - 1, -1, -1):
		var p := PRIOLIST[i + off]
		pl_list[i] = line[p] if p < 8 else 0
		pl_list[6 + i] = p
		if p == 0:
			pl_list[i] = 1 + (st.goalie_pnum & 0xFF)
	for i in range(5, -1, -1):
		var v := pl_list[i]
		if v == 0 or not _unavailable(_status(team, v)):
			continue
		var found := false
		var pos := pl_list[6 + i]
		if pos >= 0 and pos < SUBLIST_START.size():
			var j := SUBLIST_START[pos] - SUBLIST_BASE
			while j < SUBLIST.size() and SUBLIST[j] != 0xFF:
				var b := SUBLIST[j]
				j += 1
				var slot := st.ram_lines[b] if b < st.ram_lines.size() else 0
				if find_available(team, slot, i):
					found = true
					break
		if found:
			continue
		var n := st.data.players.size() if st.data else 0
		for v2 in range(n, 0, -1):
			if find_available(team, v2, i):
				break

## findAvailablePlayer (L51375): slot d0 (one-based) into PlList[i] when it is free and
## not already listed.
func find_available(team: int, d0: int, i: int) -> bool:
	if _unavailable(_status(team, d0)):
		return false
	for k in 6:
		if pl_list[k] == d0:
			return false
	pl_list[i] = d0
	return d0 != 0

## ResetBench (L51490): everyone not in the box (or hurt) goes to the bench; recount
## the box.
func reset_bench() -> void:
	for team in 2:
		pbnum[team] = 0
		var st := w.stats[team]
		for j in range(TeamStats.ROSTER - 1, -1, -1):
			var v := st.tmpdst[j]
			if v <= 0:
				if v != TeamStats.TMPDST_INJURED_PERIOD and v != TeamStats.TMPDST_INJURED_GAME:
					st.tmpdst[j] = TeamStats.TMPDST_BENCH
				continue
			if v & 0x1000 and v & 0x7FF == 0:
				continue
			pbnum[team] += 1

# --- the CPU's line choice -----------------------------------------------------------------

## getlinee (L47394): average energy of a line's skaters (always the with-goalie order).
func getlinee(team: int, line: int) -> int:
	var st := w.stats[team]
	var ln := _line(team, line)
	var total := 0
	var n := 0
	for i in range(st.on_ice - 1, -1, -1):
		var p := PRIOLIST[i]
		if p == 0:
			continue
		var v := ln[p] if p < 8 else 0
		total += st.energy[v - 1] if v >= 1 and v <= TeamStats.ROSTER else 0
		n += 1
	return (total / n) & 0xFFFF if n > 0 else 0

## CompLine (L41923): special-teams pairs by energy; at even strength the home team
## reacts to the away line, the away team takes the first rested candidate.
func comp_line(team: int) -> void:
	var st := w.stats[team]
	var opp := w.stats[1 - team]
	var diff := st.on_ice - opp.on_ice
	if diff != 0:
		var l := 3 if diff > 0 else 5
		st.line = l if getlinee(team, l) >= getlinee(team, l + 1) else l + 1
		return
	var row := 0
	if w.gsp == 2 and st.goals != opp.goals:
		row = 1 if st.goals > opp.goals else 2
	if team == 0:
		var cand: int = HL1[row][clampi(opp.line, 0, 6)]
		if getlinee(team, cand) > 0xC00:
			st.line = cand
			return
	var pick := 0
	for i in 3:
		pick = AL1[row][i]
		if getlinee(team, pick) > 0xC00:
			break
	st.line = pick

# --- the line menu ------------------------------------------------------------------------

## getlchoice (L36661): menu row 0-2 to a line, or -1.
func getlchoice(team: int, row: int) -> int:
	var st := w.stats[team]
	var diff := w.stats[1 - team].on_ice - st.on_ice
	var base := 0 if diff == 0 else (1 if diff < 0 else 2)
	return LCHOICE[base][clampi(st.line, 0, 6)][clampi(row, 0, 2)]

## SetLCmode (L36566): open the line menu for the pad player o.
func set_lc_mode(o: SimObject) -> void:
	if not w.opt_line_on or w.no_fatigue:
		return
	var st := w.stats[o.team()]
	if st.flags30 & TeamStats.F30_LINE_MENU:
		return
	st.flags30 |= TeamStats.F30_LINE_MENU
	if w.f_c2f6 & HockeyWorld.C2F6_FLIP == 0:
		w.sflags &= ~HockeyWorld.SF_PASSDIR
	w.sflags &= ~HockeyWorld.SF_SHOTDIR
	o.flags2 |= SimObject.PF2_LCMENU
	menu_changed.emit(o.team())

## lineinput (L36756): while the menu is open, A / B / C pick rows A / B / C.
func lineinput(o: SimObject, d0: int, d1: int, d2: int, d7: int) -> void:
	if w.f_c2f6 & HockeyWorld.C2F6_FLIP:
		w.shooting.passmode(o, d0, d2)
	var team := o.team()
	var st := w.stats[team]
	if st.flags30 & TeamStats.F30_LINE_REDRAW:
		st.flags30 &= ~TeamStats.F30_LINE_REDRAW
		menu_changed.emit(team)
	if d1 & PadState.A:
		lcfound(o, 0)
		return
	if d1 & PadState.B:
		lcfound(o, 1)
		return
	if d1 & PadState.C:
		lcfound(o, 2)
		return
	if o.joypad() and not o.locked() and not o.fighting():
		w.skate(o, d0 & 0xF, d7)

## lcfound (L36797): take the line on a row; the menu stays open on an empty row.
func lcfound(o: SimObject, row: int) -> void:
	var team := o.team()
	var st := w.stats[team]
	st.menu_row = row
	var line := getlchoice(team, row)
	if line < 0:
		return
	o.flags2 &= ~SimObject.PF2_LCMENU
	o.flags |= SimObject.PF_JOYCON
	st.flags30 &= ~TeamStats.F30_LINE_MENU
	st.line = line
	set_personel(team)
	menu_changed.emit(team)
	# lcfound2 erases the box and redraws the scores (PrintScores1).
	w.rules.print_scores1()

# --- trips to the bench and the box ---------------------------------------------------------------

## assbench ($0B, L37886): skate to the bench gate and hop off; the incoming player then
## takes this object.
func assbench(o: SimObject, d7: int) -> void:
	if o.locked():
		return
	if o.temp[0] == 0x64:
		_bench_done(o)
		return
	if w.ai.check4bench(o):
		return
	if o.flags2 & SimObject.PF2_PEN:
		w.assexit(o)
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[1] = 8
		o.temp[3] = 0x50 if o.away() else -0x50
		o.temp[2] = -0x88 - 8
		o.temp[0] = 0
	if (o.newpnum & 0xFF) == (o.pnum & 0xFF):
		o.flags2 &= ~SimObject.PF2_UNAV
		_bench_place(o)
		return
	o.temp[0] = HockeyWorld.s16(o.temp[0] - d7)
	if o.temp[0] < 0:
		o.temp[0] += 8
		var tx := HockeyWorld.s16(o.temp[2])
		var ty := HockeyWorld.s16(o.temp[3])
		if absi(o.y() - ty) <= 0x28 and o.x() - tx <= 0x20:
			o.set_spa(Spa.GLIDE if o.position != SimObject.POS_GOALIE else GoalieLogic.SPA_READY)
			o.flags |= SimObject.PF_NC
			var f := o.facing()
			if f != 4:
				_set_facing(o, (f + 1) & 7)
			o.vel = Vector2i(-0x800, 0)
			if o.x() - tx > 0x10:
				return
			o.vel.x = 0
			if o.facing() != 4:
				return
			o.vel.x = -0x800
			_set_facing(o, 2)
			o.set_spa(SPA_HOP_OFF)
			o.flags |= SimObject.PF_ALOCK
			o.temp[0] = 0x64
			return
	if o.flags & SimObject.PF_NC:
		return
	w.ai.skateto(o, HockeyWorld.s16(o.temp[2]), HockeyWorld.s16(o.temp[3]), Callable(w.ai.evade_pc), d7)

## assbench _done: the player is off; his slot goes to the bench and the new one loads.
func _bench_done(o: SimObject) -> void:
	o.frame = 0
	if TeamStats.valid_pnum(o.pnum):
		w.stats[o.team()].tmpdst[o.pnum] = TeamStats.TMPDST_BENCH
	_bench_place(o)

## _nobench2: position from newpos, Setplass, then setplayer for the incoming slot.
func _bench_place(o: SimObject) -> void:
	var d3 := o.newpnum & 0xFF
	o.position = o.newpos if o.newpos >= 0 else SimObject.POS_OFF_ICE
	w.setplass(o)
	o.newpnum = -1
	o.newpos = -1
	w.setplayer(o, d3)

## assben ($09, L37993): hop over the boards from the bench.
func assben(o: SimObject, _d7: int) -> void:
	if o.locked():
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.vel = Vector2i.ZERO
		var d0 := o.index - 6
		if d0 >= 0:
			d0 += 1
		_set_word_y(o, d0 * 0xE)
		_set_word_x(o, -0x88)
		_set_facing(o, 2)
		o.flags |= SimObject.PF_ALOCK
		o.set_spa(SPA_HOP_ON)
		return
	_set_facing(o, 4)
	o.flags &= ~SimObject.PF_NC
	o.flags2 &= ~(SimObject.PF2_NOCOLL | SimObject.PF2_UNAV)
	o.spa = 0
	o.vel.x = 0x1000
	w.assexit(o)

## asspenalty ($0C, L38026): skate to the box and hop in.
func asspenalty(o: SimObject, d7: int) -> void:
	if o.locked():
		return
	var team := o.team()
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.flags2 |= SimObject.PF2_UNAV
		# "so graphics know who it is": the filled star follows him to the box.
		w.marks[0] = o.index
		if o.joypad():
			var k := 0 if o.index == w.c_player[0] else 1
			w.input.changeplayer(o, k)
		o.temp[1] = 8
		var n := mini(pbnum[team] & 0xF, 2) + 3
		o.temp[3] = (0xB if o.away() else -0xB) * n
		o.temp[2] = 0x88
		o.temp[0] = 0
		o.flags2 |= SimObject.PF2_NOCOLL
		o.wall = Vector2i.ZERO
	var ty := HockeyWorld.s16(o.temp[3])
	var tx := HockeyWorld.s16(o.temp[2])
	var dy := o.y() - ty
	var dx := o.x() - tx
	if dy > 0xC or dy < -0xC or dx < -0x18:
		w.ai.skateto(o, tx, ty, Callable(), d7)
		return
	o.temp[0] = HockeyWorld.s16(o.temp[0] - d7)
	if o.temp[0] >= 0:
		return
	o.temp[0] += 8
	o.flags |= SimObject.PF_NC
	o.set_spa(Spa.GLIDE)
	var d2 := 6 if o.handed == 0 else 2
	if o.facing() != d2:
		_set_facing(o, (o.facing() + 1) & 7)
	o.vel = Vector2i(0x1000, 0)
	if dx < -8:
		return
	o.vel.x = 0
	if o.facing() != d2:
		return
	o.flags |= SimObject.PF_ALOCK
	_set_facing(o, 2)
	o.set_spa(SPA_HOP_ON)
	o.flags2 &= ~SimObject.PF2_PEN
	w.assreplace(o, ASS_DOPEN)

## assdopen ($0D, L38119): in the box. st $34 makes the position negative ($FFxx).
func assdopen(o: SimObject, _d7: int) -> void:
	if o.locked():
		return
	pbnum[o.team()] += 1
	o.position = -0x100 | (o.position & 0xFF)
	o.frame = 0

## assepen ($0A, L38135): out of the box door and back into play.
func assepen(o: SimObject, _d7: int) -> void:
	if o.locked():
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.flags |= SimObject.PF_NC
		o.flags2 |= SimObject.PF2_UNAV
		pbnum[o.team()] -= 1
		_set_word_y(o, 60 if o.away() else -60)
		o.vel = Vector2i.ZERO
		_set_word_x(o, 0x86)
		_set_facing(o, 2)
		o.flags |= SimObject.PF_ALOCK
		o.set_spa(SPA_HOP_OFF)
		w.collisions.sort_all()
		return
	_set_facing(o, 4)
	o.newpnum = -1
	o.newpos = -1
	o.flags &= ~(SimObject.PF_JOYCON | SimObject.PF_NC)
	o.flags2 &= ~(SimObject.PF2_NOCOLL | SimObject.PF2_UNAV)
	o.vel.x = -0x1000
	w.assexit(o)

static func _set_facing(o: SimObject, d: int) -> void:
	o.facing_fx = (d << 16) | (o.facing_fx & 0xFFFF)

## Word stores to the pixel part of a position (the fraction stays).
static func _set_word_x(o: SimObject, v: int) -> void:
	o.pos_fx.x = (v << 16) | (o.pos_fx.x & 0xFFFF)

static func _set_word_y(o: SimObject, v: int) -> void:
	o.pos_fx.y = (v << 16) | (o.pos_fx.y & 0xFFFF)
