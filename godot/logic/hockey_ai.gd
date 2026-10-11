class_name HockeyAI
extends RefCounted
## Skater AI: the assignment routines from asstab. Movement core (skateto, avdgoal,
## skatetopuck, EvadePC), the six positional routines, assnearest, check4check,
## setSlotBit, celebrations, check4bench, and the CPU puck carrier (asspuckc, chkpuckc,
## assbreakaway, breakaway, BreakawayOffsidesFlagSet, chk4shot, compshoot, chk4pass,
## checkob, the evade callback, the tired-line dump).
## Specs: docs/specs/ai_positional.md, docs/specs/ai_puckcarrier.md.
## temp1 high byte = reaction timer; temp2 high byte = re-aim countdown, low byte =
## cached stick direction; temp3/temp4 = target; temp5 = zone.

const ASS_DEFO := 1
const ASS_DEFD := 2
const ASS_WINGD := 3
const ASS_WINGO := 4
const ASS_CENTERD := 5
const ASS_CENTERO := 6
const ASS_SCORE := 7
const ASS_STANLEY := 8
const ASS_BENCH := 0x0B
const ASS_PUCKC := 0x10
const ASS_NEAREST := 0x11
const ASS_PASSREC := 0x13
const ASS_CHKPUCKC := 0x21
const ASS_BREAKAWAY := 0x22

## The ids this module registers (SimSettings.enable_skater_ai gates them).
const AI_IDS: Array[int] = [ASS_DEFO, ASS_DEFD, ASS_WINGD, ASS_WINGO, ASS_CENTERD, ASS_CENTERO,
	ASS_SCORE, ASS_STANLEY, ASS_PUCKC, ASS_NEAREST, ASS_CHKPUCKC, ASS_BREAKAWAY]

const SPA_CELEBRATE := 0xE8A
const SPA_ARM_PUMP := 0xEFC
const SPA_CUP := 0x109E

## asswingo _dedata (Xbase, Xrange, Ybase, Yrange) per zone 0/8/16/24.
const WINGO_DATA: Array[Vector4i] = [Vector4i(80, 20, -70, 10), Vector4i(100, 20, 58, 5),
	Vector4i(60, 50, 230, 20), Vector4i(80, 30, 250, 20)]
## asscentero _dedata.
const CENTERO_DATA: Array[Vector4i] = [Vector4i(0, 60, -70, 10), Vector4i(0, 60, 60, 10),
	Vector4i(0, 40, 170, 30), Vector4i(0, 80, 170, 20)]
## _postab2 (L40102): carrier targets. 0-5 offside wait by position, 6-9 normal spots.
const POSTAB2: Array[Vector2i] = [Vector2i(-100, -20), Vector2i(100, -20), Vector2i(-120, 40),
	Vector2i(20, 40), Vector2i(120, 40), Vector2i(-20, 40), Vector2i(-40, 240), Vector2i(0, 220),
	Vector2i(20, 230), Vector2i(30, 230)]

var w: HockeyWorld

func _init(world: HockeyWorld) -> void:
	w = world

func register(t: Dictionary) -> void:
	t[ASS_DEFO] = func(o: SimObject, d7: int) -> void: assdefo(o, d7)
	t[ASS_DEFD] = func(o: SimObject, d7: int) -> void: assdefd(o, d7)
	t[ASS_WINGD] = func(o: SimObject, d7: int) -> void: asswingd(o, d7)
	t[ASS_WINGO] = func(o: SimObject, d7: int) -> void: asswingo(o, d7)
	t[ASS_CENTERD] = func(o: SimObject, d7: int) -> void: asscenterd(o, d7)
	t[ASS_CENTERO] = func(o: SimObject, d7: int) -> void: asscentero(o, d7)
	t[ASS_SCORE] = func(o: SimObject, d7: int) -> void: assscore(o, d7)
	t[ASS_STANLEY] = func(o: SimObject, d7: int) -> void: assstanley(o, d7)
	t[ASS_PUCKC] = func(o: SimObject, d7: int) -> void: asspuckc(o, d7)
	t[ASS_NEAREST] = func(o: SimObject, d7: int) -> void: assnearest(o, d7)
	t[ASS_CHKPUCKC] = func(o: SimObject, d7: int) -> void: chkpuckc(o, d7)
	t[ASS_BREAKAWAY] = func(o: SimObject, d7: int) -> void: assbreakaway(o, d7)

# --- byte helpers -------------------------------------------------------------------

static func _hi(v: int) -> int:
	return HockeyWorld._sbyte((v >> 8) & 0xFF)

static func _lo(v: int) -> int:
	return v & 0xFF

static func _with_hi(v: int, b: int) -> int:
	return ((b & 0xFF) << 8) | (v & 0xFF)

static func _with_lo(v: int, b: int) -> int:
	return (v & 0xFF00) | (b & 0xFF)

## N: +1 when the object attacks the top goal, -1 otherwise.
static func _n(o: SimObject) -> int:
	return 1 if o.attacking_top() else -1

func _opponents(o: SimObject) -> int:
	return 6 if o.index < 6 else 0

func _same_team_carrier(o: SimObject) -> bool:
	return w.puckc >= 0 and w.puckc < 12 and (w.puckc < 6) == (o.index < 6)

func _other_team_carrier(o: SimObject) -> bool:
	return w.puckc >= 0 and w.puckc < 12 and (w.puckc < 6) != (o.index < 6)

## chkpk: true when o's team is killing a penalty.
func chkpk(o: SimObject) -> bool:
	if w.sflags2 & HockeyWorld.SF2_PWRPLAY == 0:
		return false
	return chkpk2(o)

## chkpk2: the power-play team bit differs from o's team.
func chkpk2(o: SimObject) -> bool:
	var pp_away := w.sflags2 & HockeyWorld.SF2_PWRTM != 0
	return pp_away != o.away()

## Reaction-timer pattern (spec 3.1). True when the timer expired and was reloaded.
func _timer(o: SimObject, d7: int, rating: int, goalie_bonus: bool) -> bool:
	var t := (_hi(o.temp[0]) - d7) & 0xFF
	o.temp[0] = _with_hi(o.temp[0], t)
	if t < 0x80:
		return false
	var r := rating & 0xFF
	if goalie_bonus and w.goalie_pulled(o.team()):
		r = (r - 1) & 0xFF
	elif w.crowd_record and r != 0:
		r -= 1
	o.temp[0] = _with_hi(o.temp[0], r)
	return true

# --- shared helpers -------------------------------------------------------------------

## check4bench (L37838). True when it ended the calling assignment (retail pops the
## caller's return address).
func check4bench(o: SimObject) -> bool:
	if w.ba_ps_flags & HockeyWorld.BA_LIVE or o.joypad() or o.flags2 & SimObject.PF2_PEN:
		return false
	if o.newpos < 0 and o.newpnum < 0:
		return false
	if (o.newpnum & 0xFF) == (o.pnum & 0xFF):
		o.flags2 &= ~SimObject.PF2_UNAV
		o.flags &= ~SimObject.PF_NC
		o.newpnum = -1
		o.newpos = -1
		w.setplass(o)
		return true
	if o.asslist[o.assnum & 7] == ASS_BENCH or w.puckc == o.index:
		return false
	o.flags2 |= SimObject.PF2_UNAV
	o.temp[0] = 0
	w.assreplace(o, ASS_BENCH)
	return true

## Common prologue of the six positional routines. False ends the routine.
func _prologue(o: SimObject, d7: int, zone_reset: bool) -> bool:
	if o.locked():
		return false
	if w.gmode & HockeyWorld.GM_CLOCK:
		w.assnothing(o, d7)
		return false
	if check4bench(o):
		return false
	if o.joypad():
		return false
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[0] = 0
		o.temp[1] = 8
		if zone_reset:
			o.temp[4] = _with_hi(o.temp[4], 0xFF)
	return true

# --- movement core --------------------------------------------------------------------

## skateto (L42953): steer toward (tx, ty), re-aiming every 12 frames. cb may replace
## the direction (EvadePC or the carrier's evade).
func skateto(o: SimObject, tx: int, ty: int, cb: Callable, d7: int) -> void:
	var hi := (_hi(o.temp[1]) - d7) & 0xFF
	if hi >= 0x80:
		hi = (hi + 12) & 0xFF
		o.temp[1] = _with_hi(o.temp[1], hi)
		var t := avdgoal(o, tx, ty)
		var dx := HockeyWorld.s16(t.x - (o.vel.x >> 8) - o.x())
		var dy := HockeyWorld.s16(t.y - (o.vel.y >> 8) - o.y())
		var dir := 9
		if not (dx >= -12 and dx <= 12 and dy >= -12 and dy <= 12):
			dir = SkaterSteering.vtoa(Vector2i(dx, dy))
		if cb.is_valid():
			dir = cb.call(o, dir)
		o.temp[1] = _with_lo(o.temp[1], dir)
		if dir > 7 and o.vel == Vector2i.ZERO:
			_turn_toward_puck(o)
	else:
		o.temp[1] = _with_hi(o.temp[1], hi)
	w.skate(o, _lo(o.temp[1]), d7)

func _turn_toward_puck(o: SimObject) -> void:
	var p := w.puck()
	var target := p.pos()
	if p.flags2 & 1:
		target = w.scroll_lock
	var t := SkaterSteering.vtoa(target - o.pos())
	var diff := t - o.facing()
	if diff == 0:
		return
	var step := ((((-diff) & 4) >> 1) - 1)
	o.facing_fx = (((o.facing() + step) & 7) << 16) | (o.facing_fx & 0xFFFF)

## avdgoal (L43026): bend the target so the path does not cross a net.
func avdgoal(o: SimObject, tx: int, ty: int) -> Vector2i:
	w.deltax = 0
	w.deltay = 0
	if o.position == SimObject.POS_GOALIE:
		return Vector2i(tx, ty)
	var x := o.x()
	var y := o.y()
	if (x ^ tx) < 0:
		var yc := HockeyWorld.s16(y + Shooting._divs(HockeyWorld.s16(ty - y) * x, HockeyWorld.s16(x - tx)))
		if yc >= 0xDB and yc <= 0x121:
			var r := 0x144
			if yc < 0xFE or (yc == 0xFE and y <= 0xFE):
				r = 0xB8
			w.deltay = r - yc
		elif yc >= -0x121 and yc <= -0xDB:
			var r := -0xB8
			if yc < -0xFE or (yc == -0xFE and y <= -0xFE):
				r = -0x144
			w.deltay = r - yc
	_ch1(o, tx, ty - 0xFE, y - 0xFE)
	_ch1(o, tx, ty + 0xFE, y + 0xFE)
	return Vector2i(tx + w.deltax, ty + w.deltay)

## ch1 (L43093): the X correction for crossing one goal line near the net.
func _ch1(o: SimObject, tx: int, d3: int, d2: int) -> void:
	if (d3 ^ d2) >= 0:
		return
	var x := o.x()
	var xc := HockeyWorld.s16(x + Shooting._divs(HockeyWorld.s16(tx - x) * d2, HockeyWorld.s16(d2 - d3)))
	if xc > 80 or xc < -80:
		return
	var r := 80
	if xc < 0 or (xc == 0 and x < 0):
		r = -80
	w.deltax = r - xc

## skatetopuckinit (L43123): the predicted puck point.
func skatetopuckinit() -> Vector2i:
	var p := w.puck()
	return Vector2i(p.x() + (HockeyWorld._sbyte((p.vel.x >> 8) & 0xFF) >> 1),
			p.y() + (HockeyWorld._sbyte((p.vel.y >> 8) & 0xFF) >> 1))

## skatetopuck (L43138): aim the stick at the predicted puck; sweep-check when close.
func skatetopuck(o: SimObject, d7: int) -> void:
	var t := skatetopuckinit()
	var hi := (_hi(o.temp[1]) - d7) & 0xFF
	if hi >= 0x80:
		hi = (hi + 10) & 0xFF
		o.temp[1] = _with_hi(o.temp[1], hi)
		t = avdgoal(o, t.x, t.y)
		var hot := w.get_hot(o)
		var bx := HockeyWorld._sbyte(((-hot.x) - ((o.vel.x >> 8) & 0xFF)) & 0xFF)
		var by := HockeyWorld._sbyte(((-hot.y) - ((o.vel.y >> 8) & 0xFF)) & 0xFF)
		var dx := HockeyWorld.s16(bx + t.x - o.x())
		var dy := HockeyWorld.s16(by + t.y - o.y())
		o.temp[1] = _with_lo(o.temp[1], SkaterSteering.vtoa(Vector2i(dx, dy)))
		if o.position != SimObject.POS_GOALIE and _sweep_ready(o):
			w.input.sweepcheck(o)
			return
	else:
		o.temp[1] = _with_hi(o.temp[1], hi)
	w.skate(o, _lo(o.temp[1]), d7)

func _sweep_ready(o: SimObject) -> bool:
	var p := w.puck()
	if (SkaterSteering.vtoa(p.vel) ^ 4) == o.facing():
		return false
	var dx := p.x() - o.x()
	var dy := p.y() - o.y()
	if SkaterSteering.vtoa(Vector2i(dx, dy)) != o.facing():
		return false
	var d2 := (dx * dx + dy * dy) & 0xFFFFFFFF
	return d2 > 0x384 and d2 <= 0x5A4

## EvadePC (L40442): get out of the puck carrier's way.
func evade_pc(o: SimObject, d0: int) -> int:
	if w.puckc < 0:
		return d0
	var p := w.puck()
	var ex := HockeyWorld._sbyte((((o.vel.x >> 8) & 0xFF) - ((p.vel.x >> 8) & 0xFF)) & 0xFF) + o.x() - p.x()
	if ex > 40 or ex < -40:
		return d0
	var ey := HockeyWorld._sbyte((((o.vel.y >> 8) & 0xFF) - ((p.vel.y >> 8) & 0xFF)) & 0xFF) + o.y() - p.y()
	if ey > 40 or ey < -40:
		return d0
	d0 = SkaterSteering.vtoa(Vector2i(o.x() - p.x(), o.y() - p.y()))
	if w.gmode & HockeyWorld.GM_OFFS == 0:
		return d0
	var t := (o.y() if o.attacking_top() else -o.y()) - 0x58
	if t > 10 or t < -50:
		return d0
	return 2 if o.x() > p.x() else 6

## skateto callbacks are plain method Callables (lambdas would keep this module alive).
var _evade := evade_pc
var _none := Callable()

# --- positional routines --------------------------------------------------------------

## assdefo (L38375): defenseman on offense.
func assdefo(o: SimObject, d7: int) -> void:
	if not _prologue(o, d7, false):
		return
	if _timer(o, d7, o.aioff, true):
		var st := w.stats[o.team()]
		if st.flags30 & TeamStats.F30_OFFSIDE:
			w.assreplace(o, ASS_DEFD)
			return
		if _n(o) * w.puck().y() < 0x5D:
			w.assreplace(o, ASS_DEFD)
			return
		if _other_team_carrier(o):
			w.assreplace(o, ASS_DEFD)
			return
	var lane := 80 if o.position == SimObject.POS_RD else -80
	var y := 98
	if _n(o) < 0:
		lane = -lane
		y = -y
	var px := w.puck().x()
	var x := px if (px ^ lane) >= 0 else lane + (px >> 1)
	skateto(o, x, y, _evade, d7)

## assdefd (L38447): defenseman on defense.
func assdefd(o: SimObject, d7: int) -> void:
	if not _prologue(o, d7, false):
		return
	if _timer(o, d7, o.aidef, false):
		var p := w.puck()
		var n := _n(o)
		var vn := maxi(n * (p.vel.y >> 6), 0)
		var pr := n * p.y() + vn
		if pr >= 0x58 and w.stats[o.team()].flags30 & TeamStats.F30_OFFSIDE == 0 and w.puckc >= 0 \
				and not chkpk(o) and _same_team_carrier(o):
			w.assreplace(o, ASS_DEFO)
			return
		_assdefd_target(o)
	skateto(o, HockeyWorld.s16(o.temp[2]), HockeyWorld.s16(o.temp[3]), _evade, d7)
	check4check(o)

## assdefd _de0: hold the lane, 50 px goal-side of the deepest opponent.
func _assdefd_target(o: SimObject) -> void:
	var t3 := 0x41 if o.position == SimObject.POS_RD else -0x41
	var first := _opponents(o)
	var best: int
	if _n(o) > 0:
		best = 1000
		for i in 6:
			var a := w.objects[first + i]
			if a.flags2 & SimObject.PF2_UNAV or a.position < 0:
				continue
			var v := a.vel.y if a.vel.y < 0 else 0
			var py := (v >> 4) + a.y()
			if py <= best:
				best = py
		best -= 50
		if best <= -190:
			best = -220
	else:
		best = -1000
		for i in 6:
			var a := w.objects[first + i]
			if a.flags2 & SimObject.PF2_UNAV or a.position < 0:
				continue
			var v := a.vel.y if a.vel.y > 0 else 0
			var py := (v >> 4) + a.y()
			if py >= best:
				best = py
		best += 50
		if best >= 190:
			best = 220
		t3 = -t3
	if (w.puck().x() ^ t3) < 0:
		t3 = 0
	o.temp[2] = t3
	o.temp[3] = best

## asswingd (L38591): winger on defense.
func asswingd(o: SimObject, d7: int) -> void:
	if not _prologue(o, d7, false):
		return
	if _timer(o, d7, o.aidef, false) and _same_team_carrier(o):
		w.assreplace(o, ASS_WINGO)
		return
	var p := w.puck()
	var offside := w.stats[o.team()].flags30 & TeamStats.F30_OFFSIDE != 0
	var lane := 100
	if o.position == SimObject.POS_RW:
		lane = -lane
	var y: int
	if _n(o) > 0:
		lane = -lane
		if offside:
			y = -78
		elif p.y() < -78:
			y = -158 if p.y() > -264 else -264
		else:
			y = p.y()
	else:
		if offside:
			y = 78
		elif p.y() > 78:
			y = 158 if p.y() < 264 else 264
		else:
			y = p.y()
	var x := lane if (p.x() ^ lane) < 0 else p.x()
	skateto(o, x, y, _none, d7)

## asswingo (L38682): winger on offense.
func asswingo(o: SimObject, d7: int) -> void:
	if not _prologue(o, d7, true):
		return
	if _timer(o, d7, o.aidef, false):
		if _other_team_carrier(o):
			w.assreplace(o, ASS_WINGD)
			return
		var p := w.puck()
		var n := _n(o)
		var yn := n * p.y()
		var pn := n * (p.y() + (p.vel.y >> 6))
		var zone := 24
		if pn < -88:
			zone = 0
		elif yn < 88 or w.stats[o.team()].flags30 & TeamStats.F30_OFFSIDE:
			zone = 8
		elif pn < 264:
			zone = 16
		_roll_zone(o, zone, WINGO_DATA)
	var x := HockeyWorld.s16(o.temp[2])
	if o.position != SimObject.POS_RW:
		x = -x
	var y := HockeyWorld.s16(o.temp[3])
	if _n(o) < 0:
		x = -x
		y = -y
	skateto(o, x, y, _evade, d7)

## Zone target re-roll shared by asswingo and asscentero: same zone keeps the target
## unless the H/V counter gives a 1-in-128 re-roll.
func _roll_zone(o: SimObject, zone: int, data: Array[Vector4i]) -> void:
	if o.temp[4] == zone and (w.hv_rng.randi() & 0x7F) != 0:
		return
	o.temp[4] = zone
	var e: Vector4i = data[zone >> 3]
	o.temp[2] = w.rng.signed(e.y) + e.x
	o.temp[3] = w.rng.signed(e.w) + e.z

## asscenterd (L38800): center on defense.
func asscenterd(o: SimObject, d7: int) -> void:
	if not _prologue(o, d7, false):
		return
	if _timer(o, d7, o.aidef, false) and _same_team_carrier(o):
		w.assreplace(o, ASS_CENTERO)
		return
	var p := w.puck()
	var x := p.x() >> 1
	var y := -128
	if _n(o) * p.y() >= -88:
		# Retail uses the raw puck Y here, so the two directions differ (quirk).
		y = (-128 + p.y()) >> 1
	if _n(o) < 0:
		y = -y
	skateto(o, x, y, _none, d7)

## asscentero (L38856): center on offense.
func asscentero(o: SimObject, d7: int) -> void:
	if not _prologue(o, d7, true):
		return
	if _timer(o, d7, o.aidef, false):
		if _other_team_carrier(o):
			w.assreplace(o, ASS_CENTERD)
			return
		var yn := _n(o) * w.puck().y()
		var zone := 24
		if yn < -88:
			zone = 0
		elif yn < 88 or w.stats[o.team()].flags30 & TeamStats.F30_OFFSIDE:
			zone = 8
		elif yn < 264:
			zone = 16
		_roll_zone(o, zone, CENTERO_DATA)
	var x := HockeyWorld.s16(o.temp[2])
	var y := HockeyWorld.s16(o.temp[3])
	if _n(o) < 0:
		y = -y
	skateto(o, x, y, _evade, d7)

# --- assnearest ----------------------------------------------------------------------

## assnearest (L40574): the team's puck chaser.
func assnearest(o: SimObject, d7: int) -> void:
	if w.f_c2f6 & HockeyWorld.C2F6_BREAKAWAY_RAN:
		w.f_c2f6 &= ~HockeyWorld.C2F6_BREAKAWAY_RAN
	else:
		o.flags3 &= ~SimObject.PF3_BREAKAWAY
	if w.puckc == o.index and o.flags3 & SimObject.PF3_BREAKAWAY == 0 and w.ba_ps_flags & HockeyWorld.BA_LIVE == 0:
		if breakaway_offsides_flag_set(o):
			w.assreplace(o, ASS_BREAKAWAY)
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		if o.flags3 & SimObject.PF3_BREAKAWAY:
			_breakaway_ding(o)
		o.temp[2] = 0
		o.temp[1] = 8
		o.temp[0] = 0
	if w.puckc == o.index:
		if o.position == SimObject.POS_GOALIE:
			w.goalie.assgoaliecpu(o, d7)
		elif not o.joypad():
			w.assinsert(o, ASS_PUCKC)
		return
	# Re-evaluation on the reaction timer.
	if _timer(o, d7, o.aioff, true):
		# L40642: a carrier number of 5 or less (no carrier, -1, included) counts as home.
		if w.f_c2f8 & HockeyWorld.C2F8_SLOT and (w.puckc > 5) != o.away():
			var t := _hi(o.temp[0]) >> 1
			if t == 0:
				t = 1
			o.temp[0] = _with_hi(o.temp[0], t)
		var st := w.stats[o.team()]
		st.nearest_sq = 0
		var a1: SimObject = null
		var d2 := 9 if o.flags & SimObject.PF_DOFF else 6
		if _same_team_carrier(o):
			a1 = w.objects[w.puckc]
		else:
			var best := 0xFFFFFFFF
			var p := w.puck()
			for i in 6:
				var c := w.objects[st.first_object + i]
				if c.position <= 0 or c.nopuck_hi != 0 or c.flags2 & SimObject.PF2_UNAV:
					continue
				if c.asslist[c.assnum & 7] == ASS_PASSREC:
					continue
				var hot := w.get_hot(c)
				var dx := hot.x + c.x() - p.x() - (p.vel.x >> 6)
				var dy := hot.y + c.y() - p.y() - (p.vel.y >> 6)
				var d := (dx * dx + dy * dy) & 0xFFFFFFFF
				if d <= best:
					best = d
					a1 = c
			if a1 == null:
				d2 = 0xFFFFFFFF
			else:
				st.nearest_sq = best
				d2 = best
		if a1 != null and a1 != o and w.gmode & HockeyWorld.GM_CLOCK == 0 \
				and a1.flags2 & SimObject.PF2_UNAV == 0 and a1.flags3 & SimObject.PF3_ONETIMER == 0:
			a1.flags &= ~SimObject.PF_DOFF
			w.assinsert(a1, ASS_NEAREST)
			w.assexit(o)
			return
		if o.locked():
			return
		_pressure_roll(o, d2)
	_assnearest_move(o, d7)

## assnearest _de1: maybe start 240 frames of direct pressure.
func _pressure_roll(o: SimObject, d2: int) -> void:
	var sh := 2
	if (d2 & 0xFFFF) <= 0x190:
		sh = 0
		if o.position <= SimObject.POS_RD:
			return
	if w.sflags2 & HockeyWorld.SF2_PWRPLAY:
		sh -= 2
		if chkpk2(o):
			sh += 4
	var base := (0x28 - o.checking) & 0xFF
	var shift := sh & 63
	var r := w.rng.range_((base << shift) & 0xFFFF if shift < 16 else 0)
	if r <= 2:
		o.temp[2] = 0xF0

## assnearest _nodec: chase or contain.
func _assnearest_move(o: SimObject, d7: int) -> void:
	if o.locked():
		return
	if not (w.ba_ps_flags & HockeyWorld.BA_LIVE and w.ba_ps_flags & HockeyWorld.BA_STARTED == 0):
		if w.gmode & HockeyWorld.GM_CLOCK:
			w.assnothing(o, d7)
			return
	if o.joypad():
		return
	var st := w.stats[o.team()]
	var contain := false
	if st.flags30 & TeamStats.F30_TIMEOUT:
		contain = true
	elif w.puckc >= 0:
		o.temp[2] = HockeyWorld.s16(o.temp[2] - d7)
		if o.temp[2] < 0:
			o.temp[2] = 0
			contain = true
	if not contain:
		skatetopuck(o, d7)
		check4check(o)
		return
	var f := skatetopuckinit()
	var x := ((-f.x) >> 1) + f.x
	var y: int
	if _n(o) < 0:
		y = ((0xF4 - f.y) >> 1) + f.y
	else:
		y = ((-f.y - 0xF4) >> 1) + f.y
	if st.flags30 & TeamStats.F30_TIMEOUT:
		if _n(o) > 0 and y >= 0x53:
			y = 0x44
		elif _n(o) < 0 and y <= -0x53:
			y = -0x44
	if w.f_c2f8 & HockeyWorld.C2F8_SLOT:
		var saved := o.legspd
		o.legspd += 6
		if w.crowd_boost:
			o.legspd += 2
		if HockeyWorld._sbyte(o.legspd & 0xFF) > 0x1E:
			o.legspd = 0x1E
		skateto(o, x, y, _none, d7)
		o.legspd = saved
		_goal_side_check(o)
	else:
		skateto(o, x, y, _none, d7)
		check4check(o)

## _chkslot / _pospuck: goal-side of the slot carrier, check with doubled Chk.
func _goal_side_check(o: SimObject) -> void:
	var pp := w.puck().y()
	var q := o.y()
	if pp < 0:
		pp = -pp
		q = -q
	if q - pp < 10:
		return
	if absi(o.x() - w.puck().x()) >= 15:
		return
	var saved := o.checking
	o.checking = mini((o.checking * 2) & 0xFF, 0x1E) if HockeyWorld._sbyte((o.checking * 2) & 0xFF) < 0x1E else 0x1E
	check4check(o)
	o.checking = saved

## check4check (L40878): a random body check or hold on an opponent in front.
func check4check(o: SimObject) -> void:
	if o.position == SimObject.POS_GOALIE:
		return
	var r := (0x28 - o.checking) & 0xFF
	if w.opt_pen:
		r = (r << 1) & 0xFFFF
	if w.rng.range_(r) > 6:
		return
	var first := _opponents(o)
	for i in 6:
		var a := w.objects[first + i]
		if a.position == SimObject.POS_GOALIE or a.locked() or a.fighting():
			continue
		var dx := a.x() - o.x()
		var dy := a.y() - o.y()
		if dx < -30 or dx > 30 or dy < -30 or dy > 30:
			continue
		if SkaterSteering.vtoa(Vector2i(dx, dy)) != o.facing():
			continue
		if w.f_c2f8 & HockeyWorld.C2F8_SLOT:
			w.checking.acheck(o, a)
		elif w.hv_rng.randi() & 3 != 0:
			w.shooting.burst(o)
		else:
			w.checking.acheck(o, a)
		return

# --- slot, celebrations --------------------------------------------------------------

## setSlotBit (L963062): the carrier is in his offensive slot.
func set_slot_bit() -> void:
	w.f_c2f8 &= ~HockeyWorld.C2F8_SLOT
	if w.puckc < 0 or w.puckc > 11:
		return
	var c := w.objects[w.puckc]
	var yn := c.y() if c.attacking_top() else -c.y()
	if yn >= 0x58 and c.x() >= -0x47 and c.x() <= 0x47:
		w.f_c2f8 |= HockeyWorld.C2F8_SLOT

## assscore (L38315): skate toward the camera side and celebrate.
func assscore(o: SimObject, d7: int) -> void:
	if o.locked():
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[0] = w.rng.range_(0x78)
		o.temp[1] = 8
		o.temp[2] = -90 if w.camera.x < 0 else 90
		o.temp[3] = w.camera.y
	var tx := HockeyWorld.s16(o.temp[2])
	var ty := HockeyWorld.s16(o.temp[3])
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		if w.so_replay_stop != 0:
			w.so_replay_stop -= 1
			if w.so_replay_stop == 0:
				w.sflags2 |= 1 << 2
		if o.x() > 0x88 or o.x() <= -0x88:
			ty = 0
	o.temp[0] = HockeyWorld.s16(o.temp[0] - d7)
	if o.temp[0] >= 0:
		if not o.joypad():
			skateto(o, tx, ty, _none, d7)
		return
	o.flags |= SimObject.PF_ALOCK
	o.set_spa(SPA_ARM_PUMP if w.shotplayer == o.index else SPA_CELEBRATE)
	o.temp[0] = w.rng.range_(0x78)

## assstanley (L38287): skate with the cup.
func assstanley(o: SimObject, d7: int) -> void:
	if o.locked():
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[2] = -90 if w.camera.x < 0 else 90
		o.temp[3] = w.camera.y
		o.set_spa(SPA_CUP)
	var dir := SkaterSteering.vtoa(Vector2i(HockeyWorld.s16(o.temp[2]) - o.x(), HockeyWorld.s16(o.temp[3]) - o.y()))
	if dir > 7:
		return
	o.facing_fx = (dir << 16) | (o.facing_fx & 0xFFFF)
	w.playeracc(o, dir, d7)

# --- the CPU puck carrier --------------------------------------------------------------

## breakaway (L39775). True = keep the breakaway (N clear).
func breakaway(o: SimObject) -> bool:
	w.f_c2f6 |= HockeyWorld.C2F6_BREAKAWAY_RAN
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		_breakaway_ding(o)
	if o.vel.y == 0:
		return false
	return (o.y() ^ o.vel.y) >= 0

func _breakaway_ding(o: SimObject) -> void:
	w.sound.emit(1)
	w.stats[o.team()].breakaway_attempts += 1
	w.crowd_excite += 0x14
	w.crowd_level += 0xC8

## BreakawayOffsidesFlagSet (L39808). True when a breakaway just started.
func breakaway_offsides_flag_set(o: SimObject) -> bool:
	if o.flags & SimObject.PF_NA:
		o.flags3 &= ~(SimObject.PF3_OSIDE | SimObject.PF3_BREAKAWAY)
	var y := o.y()
	if y >= 0x108 or y <= -0x108:
		return false
	var in_zone := y > 0x58 if o.attacking_top() else y <= -0x58
	if not in_zone:
		o.flags3 |= SimObject.PF3_OSIDE
		return false
	var was_outside := o.flags3 & SimObject.PF3_OSIDE != 0
	o.flags3 &= ~SimObject.PF3_OSIDE
	if not was_outside:
		return false
	for i in range(11, -1, -1):
		var a := w.objects[i]
		var ahead := a.y() > y if y >= 0 else a.y() < y
		if ahead and a.position != SimObject.POS_GOALIE:
			return false
	o.flags3 |= SimObject.PF3_BREAKAWAY
	return true

## chkpuckc ($21): the CPU carrier on a breakaway.
func chkpuckc(o: SimObject, d7: int) -> void:
	var keep := false
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT == 0 and w.ba_ps_flags & HockeyWorld.BA_LIVE == 0:
		keep = breakaway(o)
	if not keep:
		o.flags3 &= ~SimObject.PF3_BREAKAWAY
		w.assreplace(o, ASS_PUCKC)
	asspuckc(o, d7)

## assbreakaway ($22): a human carrier's breakaway.
func assbreakaway(o: SimObject, d7: int) -> void:
	if o.index == w.puckc and breakaway(o):
		assnearest(o, d7)
		return
	o.flags3 &= ~SimObject.PF3_BREAKAWAY
	w.assreplace(o, ASS_NEAREST)
	assnearest(o, d7)

## asspuckc ($10): the CPU puck carrier.
func asspuckc(o: SimObject, d7: int) -> void:
	if w.f_c2f6 & HockeyWorld.C2F6_BREAKAWAY_RAN:
		w.f_c2f6 &= ~HockeyWorld.C2F6_BREAKAWAY_RAN
	else:
		o.flags3 &= ~SimObject.PF3_BREAKAWAY
	if w.puckc != o.index:
		w.assexit(o)
		return
	var ps := w.ba_ps_flags & HockeyWorld.BA_LIVE != 0
	if ps and w.ps_intro > 1:
		return
	if o.flags3 & SimObject.PF3_BREAKAWAY == 0 and not ps:
		if breakaway_offsides_flag_set(o):
			w.assreplace(o, ASS_CHKPUCKC)
	if o.locked():
		return
	if not ps and w.gmode & HockeyWorld.GM_CLOCK:
		w.assnothing(o, d7)
		return
	if o.joypad():
		w.assexit(o)
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		if o.flags3 & SimObject.PF3_BREAKAWAY:
			_breakaway_ding(o)
		o.temp[0] = 0
		o.temp[1] = 8
		o.temp[2] = w.hv_rng.randi() & 3
	if _timer(o, d7, o.aioff, true):
		var so := w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT != 0
		if ps or so:
			if w.ps_should_shoot(o):
				compshoot(o)
				return
		else:
			checkob(o)
			if _tired_line_dump(o):
				return
			if not (w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT or w.ba_ps_flags & HockeyWorld.BA_LIVE):
				var run_shot := true
				if o.flags3 & SimObject.PF3_BREAKAWAY == 0:
					var t := 2 if o.away() else 1
					if w.cont_team[0] != t and w.cont_team[1] != t and w.vcount & 2:
						run_shot = false
				if run_shot and chk4shot(o):
					return
				if chk4pass(o):
					return
	_carrier_move(o, d7)

## asspuckc step 12: skate to a scoring spot, or wait for a delayed offside.
func _carrier_move(o: SimObject, d7: int) -> void:
	var idx := 6 + (o.temp[2] & 3)
	if w.sflags2 & HockeyWorld.SF2_OFFSIG:
		idx = clampi(o.position, 0, 9)
	var t: Vector2i = POSTAB2[idx]
	var ps := w.ba_ps_flags & HockeyWorld.BA_LIVE or w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT
	if ps:
		var wp: Variant = w.ps_waypoint(o)
		if wp == null:
			return
		t = wp
	if not o.attacking_top():
		t = -t
	var cb := Callable() if ps else Callable(carrier_evade)
	skateto(o, t.x, t.y, cb, d7)

## loc_E12C: count threats and turn away from the last close opponent.
func carrier_evade(o: SimObject, d0: int) -> int:
	var p := w.puck()
	var cx := HockeyWorld._sbyte((o.vel.x >> 8) & 0xFF) + p.x()
	var cy := HockeyWorld._sbyte((o.vel.y >> 8) & 0xFF) + p.y()
	w.threat = 0
	var first := _opponents(o)
	for i in 6:
		var a := w.objects[first + i]
		var dx := HockeyWorld._sbyte((a.vel.x >> 8) & 0xFF) + a.x() - cx
		if dx > 20 or dx < -20:
			continue
		var dy := HockeyWorld._sbyte((a.vel.y >> 8) & 0xFF) + a.y() - cy
		if dy > 20 or dy < -20:
			continue
		w.threat += 1
		d0 = SkaterSteering.vtoa(Vector2i(o.x() - a.x(), o.y() - a.y()))
		if (o.facing() ^ 4) == d0:
			d0 = (d0 + (w.hv_rng.randi() & 1)) & 7
	return d0

## sub_E1F4: tired line in the neutral zone changes and dumps the puck. True when it shot.
func _tired_line_dump(o: SimObject) -> bool:
	if w.no_fatigue:
		return false
	var y := w.puck().y() if o.attacking_top() else -w.puck().y()
	if y < 0 or y > 0x58:
		return false
	if w.hv_rng.randi() & 3 != 0:
		return false
	if o.flags2 & SimObject.PF2_LCMENU:
		return false
	if w.average_energy(o.team()) > 0xC00:
		return false
	w.cpu_line_change(o.team())
	compshoot(o)
	return true

## chk4shot (L40183). True when the carrier shot (the assignment is over).
func chk4shot(o: SimObject) -> bool:
	if chkpk(o) and w.threat != 0 and w.hv_rng.randi() & 3 == 0:
		var deep := o.y() > -0x58 if o.attacking_top() else o.y() < 0x58
		if deep:
			compshoot(o)
			return true
		w.f_c2f6 |= HockeyWorld.C2F6_FLIP
		w.shooting.dopass(o)
		return false
	var p := w.puck()
	if o.flags3 & SimObject.PF3_BREAKAWAY:
		var t := w.rng.range_(0x1E) + 0x82
		if p.y() > t or p.y() < -t:
			o.facing_fx = (((o.facing() + w.rng.signed(2)) & 7) << 16) | (o.facing_fx & 0xFFFF)
			compshoot(o)
			return true
	var d4 := (((0x20 - ((o.spodds & 0xFF) >> 1)) & 0xFF) << 4) & 0xFFFF
	var gx := HockeyWorld.s16(-p.x())
	var gy := HockeyWorld.s16((0x108 if o.attacking_top() else -0x108) - p.y())
	if ((gx * gx + gy * gy) & 0xFFFFFFFF) <= 0x2710:
		d4 >>= 4
		var gdir := SkaterSteering.vtoa(Vector2i(gx, gy))
		var first := _opponents(o)
		for i in 6:
			var a := w.objects[first + i]
			if a.position == SimObject.POS_GOALIE:
				if a.anim_busy():
					d4 = 1
					break
			elif SkaterSteering.vtoa(Vector2i(a.x() - p.x(), a.y() - p.y())) == gdir:
				d4 = (d4 << 1) & 0xFFFF
	var r := w.rng.range_(d4)
	if r > (7 if o.spodds & 1 else 8):
		return false
	var y := p.y() if o.attacking_top() else -p.y()
	if y < 0 or 0x108 - y < 0:
		return false
	if w.sflags2 & HockeyWorld.SF2_OFFSIG:
		return false
	compshoot(o)
	return true

## compshoot (L40316): wind up for up to 20 frames and shoot.
func compshoot(o: SimObject) -> void:
	var y := w.puck().y() if o.attacking_top() else -w.puck().y()
	var d1 := ((0x108 - y) & 0xFFFF) >> 3
	if HockeyWorld.s16(d1) >= 0x14:
		d1 = 0x14
	o.temp[1] = d1
	w.assreplace(o, Shooting.ASS_SHOOT)

## chk4pass (L40337). True when it passed and the skater's assignment ended.
func chk4pass(o: SimObject) -> bool:
	if w.threat == 0 and w.rng.range_((0x10 + o.spodds) & 0xFF) > 12:
		return false
	var n := w.rng.range_(6)
	if o.index >= 6:
		n += 6
	var p := w.puck()
	if o.position != SimObject.POS_GOALIE:
		if p.x() >= -40 and p.x() <= 40 and (p.y() > 0xCC or p.y() < -0xCC):
			return false
	if n == o.index:
		return false
	var r := w.objects[n]
	if r.position <= 0 or r.flags2 & SimObject.PF2_UNAV or r.locked():
		return false
	var ry := r.y()
	var cy := o.y()
	if not o.attacking_top():
		ry = -ry
		cy = -cy
	if w.gmode & HockeyWorld.GM_OFFS and ((ry - 0x58) ^ (cy - 0x58)) < 0:
		return false
	if ry <= 0x58 and ry - cy < -15:
		return false
	var dx := r.x() - p.x()
	var dy := r.y() - p.y()
	var dir := SkaterSteering.vtoa(Vector2i(dx, dy))
	# L40403: passdir is written before the lane check, so a pass turned down still
	# leaves it pointing at the receiver.
	w.passdir = dir
	var rd2 := (dx * dx + dy * dy) & 0xFFFFFFFF
	var first := _opponents(o)
	for i in 6:
		var a := w.objects[first + i]
		var ox := a.x() - p.x()
		var oy := a.y() - p.y()
		if ((ox * ox + oy * oy) & 0xFFFFFFFF) > rd2:
			continue
		if SkaterSteering.vtoa(Vector2i(ox, oy)) == dir:
			return false
	w.shooting.dopass(o)
	if o.position == SimObject.POS_GOALIE:
		return false
	w.assexit(o)
	return true

## checkob (L40493): the delayed-offside signal.
func checkob(o: SimObject) -> void:
	if w.gmode & HockeyWorld.GM_OFFS == 0 or w.ba_ps_flags & HockeyWorld.BA_LIVE:
		return
	var p := w.puck()
	var past_line := func(y: int) -> bool: return y > 0x5C if o.attacking_top() else y < -0x5C
	var set_it := false
	if not past_line.call(p.y()):
		var st := w.stats[o.team()]
		for i in 6:
			var a := w.objects[st.first_object + i]
			if a.position >= 0 and past_line.call(a.y()):
				set_it = true
				break
	# PushRef only while no referee script runs (RefCnt < 0, L40536).
	if set_it:
		if w.sflags2 & HockeyWorld.SF2_OFFSIG == 0:
			w.sflags2 |= HockeyWorld.SF2_OFFSIG
			if w.rules.refcnt < 0:
				w.ref_signal.emit(6)
	elif w.sflags2 & HockeyWorld.SF2_OFFSIG:
		w.sflags2 &= ~HockeyWorld.SF2_OFFSIG
		if w.rules.refcnt < 0:
			w.ref_signal.emit(0x40)
