class_name RosterLogic
extends RefCounted
## Teams and roster slots in play: team setup (sub_17190 / sub_171BE), per-game form
## (Create_HotCold_Table), setplayer with its bonuses, AttributeCalc and
## checkattriblimits, ClockLength. Spec: docs/specs/data_attributes.md sections 1-2.

## asstab ids setplayer inserts for a player coming on from the box or the bench.
const ASS_BEN := 0x09
const ASS_EPEN := 0x0A
## ClockLength _timetab by OptPerlen: 5, 10, 20 minutes and 30 seconds.
const TIMETAB: Array[int] = [300, 600, 1200, 30]

var w: HockeyWorld
## PPBonus, PKBonus, HmAwBonus, ThirdPBonus from the last setplayer (signed bytes).
var pp_bonus: int = 0
var pk_bonus: int = 0
var ha_bonus: int = 0
var third_bonus: int = 0

func _init(world: HockeyWorld) -> void:
	w = world

## sub_17190: bind the two TeamData records to the team structs and copy the RAM lines.
func setup_teams(home: TeamData, away: TeamData) -> void:
	for team in 2:
		var data := home if team == 0 else away
		var st := w.stats[team]
		st.data = data
		st.team_index = data.team_index if data else -1
		st.rom = []
		if data == null:
			continue
		for p in data.players:
			st.rom.append(p.rom_bytes())
		copy_lines(team)

## sub_171BE: RAM lines from the data lines. Line changes on: data lines 1-7. Off: data
## line 0, then 2-7 (Sc1 is dropped).
func copy_lines(team: int) -> void:
	var st := w.stats[team]
	st.ram_lines = PackedInt32Array()
	if st.data == null:
		return
	var src := st.data.lines
	if w.opt_line_on:
		st.ram_lines = src.slice(8, 64)
	else:
		st.ram_lines = src.slice(0, 8) + src.slice(16, 64)

## Create_HotCold_Table: 416 form bytes per team, uniform -9..+8, filled from the top
## down (home first). Only byte 0 of each slot's 16 is read in play (AttributeCalc).
func new_game_form() -> void:
	for team in 2:
		var hc := w.stats[team].hotcold
		for i in range(0x19F, -1, -1):
			hc[i] = w.rng.signed(9)

## ClockLength: the period length in seconds from OptPerlen.
func clock_length() -> int:
	return TIMETAB[clampi(w.opt_perlen, 0, 3)]

## AttributeCalc: nibble * 5 plus a third of the slot's form byte 0, clamped 0..30.
func attribute_calc(team: int, slot: int, n: int) -> int:
	var hc := 0
	if TeamStats.valid_pnum(slot):
		hc = w.stats[team].hotcold[slot * 16]
	var q := hc / 3 if hc >= 0 else -((-hc) / 3)
	return clampi(n * 5 + q, 0, 30)

## checkattriblimits: a byte sum clamped to 0..30 (bit 7 set reads as negative).
static func lim(v: int) -> int:
	v &= 0xFF
	if v >= 0x80:
		return 0
	return mini(v, 30)

## aioff / aidef from a 0..30 rating: (30 - t/2) / 2, so 15 (slow) .. 7 (quick).
static func reaction(t: int) -> int:
	return ((((t >> 1) ^ 0x0F) + 0x0F) & 0xFF) >> 1

## setplayer (L51556): roster slot d3 takes object o. Without team data (sandbox, tests)
## only the slot bookkeeping runs and the object keeps its ratings.
func setplayer(o: SimObject, d3: int) -> void:
	o.flags2 &= ~SimObject.PF2_FIGHT_HURT
	var team := o.team()
	var st := w.stats[team]
	o.pnum = d3 if TeamStats.valid_pnum(d3) else -1
	if TeamStats.valid_pnum(d3):
		var d1 := st.tmpdst[d3]
		if d1 >= 0 or d1 == TeamStats.TMPDST_BENCH:
			w.assinsert(o, ASS_EPEN if d1 >= 0 else ASS_BEN)
			o.flags &= ~SimObject.PF_ALOCK
			o.spa = 0
		st.tmpdst[d3] = TeamStats.TMPDST_ON_ICE
	pp_bonus = 0
	pk_bonus = 0
	ha_bonus = 0
	third_bonus = 0
	if st.data == null or d3 < 0 or d3 >= st.rom.size():
		return
	var data := st.data
	if o.position != SimObject.POS_GOALIE:
		if w.sflags2 & HockeyWorld.SF2_PWRPLAY:
			if not w.ai.chkpk2(o):
				pp_bonus = data.pp_bonus & 0x0F
			else:
				pk_bonus = -(data.pk_penalty & 0x0F)
		ha_bonus = (data.home_bonus & 0x0F) if not o.away() else -(data.away_penalty & 0x0F)
		if _third_period_bonus_time():
			var diff := w.stats[0].goals - w.stats[1].goals
			if diff == 0 or (not o.away() and diff < 0) or (o.away() and diff > 0):
				third_bonus = 2
	_load(o, team, d3, st.rom[d3])

## The trailing-team bonus runs in OT, and in the 3rd period while at least half of it
## is left (the clock counts down; the listing calls this a bug).
func _third_period_bonus_time() -> bool:
	if w.gsp < 2:
		return false
	if w.gsp == 2 and (clock_length() >> 1) > w.gameclock:
		return false
	return true

## setplayer step 10 for a roster slot.
func _load(o: SimObject, team: int, slot: int, a: PackedByteArray) -> void:
	var hc := w.stats[team].hotcold[slot * 16]
	load_bytes(o, a, hc, pp_bonus, pk_bonus, ha_bonus, third_bonus)

## setplayer step 10: the rating bytes, in retail order, with form byte hc and the four
## bonuses. A PlayerData with no game around it loads with hc and bonuses 0.
static func load_bytes(o: SimObject, a: PackedByteArray, hc: int = 0, pp: int = 0, pk: int = 0,
		ha: int = 0, p3: int = 0) -> void:
	var q := hc / 3 if hc >= 0 else -((-hc) / 3)
	var ac := func(n: int) -> int: return clampi(n * 5 + q, 0, 30)
	o.rostnum = a[0]
	o.weight = (a[1] & 0xF0) >> 1
	o.legstr = ac.call(a[1] & 0xF)
	o.legspd = ac.call(a[2] >> 4)
	o.aioff = reaction(lim(ac.call(a[2] & 0xF) + pp + pk + ha + p3))
	o.aidef = reaction(lim(ac.call(a[3] >> 4) + ha))
	o.shotspd = ac.call(a[3] & 0xF)
	o.checking = lim(ac.call(a[4] >> 4) + p3)
	o.handed = (a[4] & 1) ^ 1
	o.attribute &= ~SimObject.ATTR_XFLIP
	if o.handed == 0:
		o.attribute |= SimObject.ATTR_XFLIP
	o.hf = a[4] & 0x0E
	o.stickhand = lim(ac.call(a[5] >> 4) + pp + pk + ha)
	o.shotacc = lim(ac.call(a[5] & 0xF) + pp + pk + ha)
	o.endurance = ac.call(a[6] >> 4)
	o.spodds = lim(ac.call(a[6] & 0xF) + 2 * p3)
	o.passacc = lim(ac.call(a[7] >> 4) + pp + ha)
	# Masked after scaling, so it wraps (AC 20 reads as 4).
	o.aggress = ac.call(a[7] & 0xF) & 0x0F
