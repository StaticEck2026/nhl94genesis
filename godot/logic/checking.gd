class_name Checking
extends RefCounted
## Body checks, holds, sweep checks, falls, board pins and injuries.
## Port of newcheck, checkint/checkint_ci, checkcheck/CCStart/CheckingCalc, checkagr,
## holdcheck, Bcheck, FallDown, setInjuryType, wallcollduringcheck, holdplayer/Acheck
## and the falling-down block of updateplayers. Spec: docs/specs/collisions_checking.md.
## Argument names follow the asm registers (a2, a3) so the spec reads across.

## checkinglist (L48956): checker animation by target direction relative to facing.
const CHECKINGLIST: Array[int] = [0xB96, 0xBC8, 0xC2C, 0xC2C, 0xC2C, 0xBFA, 0xBFA, 0xB96]
## FallList (L49396), indexed 0 top, 2 right, 4 bottom, 6 left.
const FALL_LIST: Array[int] = [0x1776, 0x1776, 0x17E8, 0x17E8, 0x185A, 0x185A, 0x18CC, 0x18CC]

const SPA_BURST := 0xC5E
const SPA_HOLD := 0x1122
const SPA_HOLD_HIGH := 0xC90
const SPA_HOLD2 := 0xCC2
const SPA_HOLD_AFTER := 0x1154
const SPA_FLAIL := 0xCF4
const SPA_SWEEP := 0xB24
const SPA_STAGGER := 0x11E6
const SPA_FALL_FRONT := 0xDD8
const SPA_FALL_BACK := 0xD26
const SPA_BIG_HIT := 0x136A
const SPA_INJURED_GAME := 0x145C
const SPA_INJURED_PERIOD := 0x1AF4
const SPA_BOARD_HITTER := 0x1AC2
const SPA_BOARDS_TOP := 0x1776
const SPA_BOARDS_RIGHT := 0x17E8
const SPA_BOARDS_BOTTOM := 0x185A
const SPA_BOARDS_LEFT := 0x18CC
const SPA_OVER_LEFT := 0x193E
const SPA_OVER_RIGHT := 0x1A00
## FallDown refuses a faller already in one of these.
const ALREADY_DOWN: Array[int] = [0x145C, 0x1AF4, 0x11E6, 0xD26, 0xDD8, 0x136A]

## Penalty ids (PenaltyList offsets; names checked against the ROM text).
const PEN_FACEOFF := 0x08
const PEN_ROUGHING_INJURY := 0x12
const PEN_STOPPAGE := 0x14
const PEN_CHARGING := 0x16
const PEN_SLASHING := 0x18
const PEN_ROUGHING := 0x1A
const PEN_CROSS_CHECK := 0x1C
const PEN_HOOKING := 0x1E
const PEN_TRIPPING := 0x20
const PEN_INTERFERENCE := 0x22
const PEN_HOLDING := 0x24

const SFX_INJURY := 0x0D
const SFX_TACKLE := 0x1C
const SONG_CHEER := 0x0B
const SONG_BOO := 0x0C

var w: HockeyWorld

func _init(world: HockeyWorld) -> void:
	w = world

## V counter byte stand-in (CCStart penalty variant).
func _vcounter() -> int:
	return w.hv_rng.randi() & 0xFF

## H/V counter word stand-in (FallDown stagger, CheckBump, check4check).
func _hvword() -> int:
	return w.hv_rng.randi() & 0xFFFF

static func _dir(from: SimObject, to: SimObject) -> int:
	return SkaterSteering.vtoa(Vector2i(to.x() - from.x(), to.y() - from.y()))

## newcheck (L48758): a tackle sound different from the last one.
func newcheck() -> void:
	var r := w.rng.range_(3) + 1
	w.ltack = (w.ltack + r) & 3
	w.sound.emit(SFX_TACKLE + w.ltack)

# --- goalie contact / interference --------------------------------------------------

## checkint (L48778): both directions. Returns FallDown's d1 when someone fell, else
## Collisions.D1_UNCHANGED (quirk Q1).
func checkint(a3: SimObject, a2: SimObject) -> int:
	var d1 := Collisions.D1_UNCHANGED
	var r := checkint_ci(a2, a3)
	if r != Collisions.D1_UNCHANGED:
		d1 = r
	r = checkint_ci(a3, a2)
	if r != Collisions.D1_UNCHANGED:
		d1 = r
	return d1

## checkint_ci (L48790): a2 is the goalie candidate, a3 the other skater.
func checkint_ci(a2: SimObject, a3: SimObject) -> int:
	if a2.position != SimObject.POS_GOALIE:
		return Collisions.D1_UNCHANGED
	if w.gmode & HockeyWorld.GM_CLOCK:
		return Collisions.D1_UNCHANGED
	if w.puckc != a3.index and a3.impact <= 0x19:
		return Collisions.D1_UNCHANGED
	if a3.impact <= 2:
		return Collisions.D1_UNCHANGED
	var d1 := fall_down(a3, a2)
	if a2.impact <= 0x1E:
		return d1
	if a3.flags2 & SimObject.PF2_PEN:
		return d1
	if a2.position != SimObject.POS_GOALIE:
		return d1
	var team := 2 if a3.away() else 1
	if w.cont_team[0] == team or w.cont_team[1] == team:
		if not a3.joypad():
			return d1
	var y := a2.y()
	if a2.attacking_top():
		y = -y
	if y < 0xEF or y > 0x10A:
		return d1
	if a2.x() > 0x14 or a2.x() < -0x14:
		return d1
	var r := w.rng.range_((0x28 - a3.aggress) & 0xFF)
	if r > 4:
		return d1
	if w.gmode & HockeyWorld.GM_HL:
		return d1
	w.add_penalty(PEN_INTERFERENCE, a3)
	return d1

# --- body checks, holds, sweeps ------------------------------------------------------

## checkcheck (L48854): CCStart both ways. d4 is the impact value from checkcx.
func checkcheck(a3: SimObject, a2: SimObject, d4: int) -> void:
	ccstart(a2, a3, d4)
	ccstart(a3, a2, d4)

## CCStart (L48864) with PlayerControlled / CheckingCalc.
func ccstart(a2: SimObject, a3: SimObject, d4: int) -> void:
	if a2.spa == SPA_HOLD_HIGH or a2.spa == SPA_HOLD:
		holdcheck(a2, a3)
		return
	if a2.spa == SPA_SWEEP:
		bcheck(a2, a3)
		return
	if a3.spa != SPA_BURST:
		return
	if w.gmode & HockeyWorld.GM_CLOCK:
		# A late hit always floors.
		a3.impact = 0x100
		a2.impact = 0x100
	var r := (_dir(a3, a2) - a3.facing()) & 7
	if a3.x_flip():
		r = (8 - r) & 7
	a3.flags |= SimObject.PF_ALOCK
	a3.set_spa(CHECKINGLIST[r])
	if a2.position == SimObject.POS_GOALIE:
		return
	if d4 < 0x14:
		return
	var d0 := 0xF0 if a3.joypad() else 0x78
	d0 = (d0 - a3.weight) & 0xFF
	d0 = (d0 + a2.weight) & 0xFF
	d0 >>= 1
	wallcollduringcheck(a3)
	d0 = HockeyWorld.s16(d0 - a2.impact)
	var down := false
	if d0 <= 0:
		down = true
	elif a3.flags3 & SimObject.PF3_WALL:
		down = true
	else:
		var roll := HockeyWorld._sbyte(w.rng.range_(d0) & 0xFF)
		down = roll <= ((a3.checking & 0xFF) >> 1)
	if not down:
		# The check failed, but a charging or slashing call is still possible.
		if checkagr(a3, a2) > 4 or w.gmode & HockeyWorld.GM_HL:
			return
		w.add_penalty(w.pen_shot_chk(PEN_CHARGING + (_vcounter() & 2), a2, a3), a3)
		return
	if checkagr(a3, a2) <= 3 and w.gmode & HockeyWorld.GM_HL == 0:
		w.add_penalty(w.pen_shot_chk(PEN_ROUGHING + (_vcounter() & 2), a2, a3), a3)
	fall_down(a2, a3)

## checkagr (L48971): penalty roll for a3 fouling a2. A call happens when the result is
## at or under the caller's threshold (charging 4, roughing 3, holding 6, tripping 4).
func checkagr(a3: SimObject, a2: SimObject) -> int:
	var d0 := (0x28 - a3.aggress) & 0xFF
	d0 >>= 1
	d0 = (d0 * 13) & 0xFFFF
	if a3.joypad():
		d0 = (d0 << 1) & 0xFFFF
	var p := w.puck()
	var dx := a3.x() - p.x()
	var dy := a3.y() - p.y()
	if dx >= -0x28 and dx <= 0x28 and dy >= -0x28 and dy <= 0x28:
		d0 = HockeyWorld.s16(d0) >> 1
	d0 = w.rng.range_(d0)
	if a2.flags3 & SimObject.PF3_BREAKAWAY:
		var dist := 0x108 - absi(a2.y())
		var n := 8
		if dist <= 0x75:
			n = 7
		if dist <= 0x3A:
			n = 4
		if dist <= 0x2C:
			n = 3
		d0 = w.rng.range_(n)
	if not a3.away():
		if w.delayed_pen & 4:
			d0 = 0x7F
	elif w.delayed_pen & 2:
		d0 = 0x7F
	return d0

## holdcheck (L49037): a2 holds a3 when a3 is within one direction of a2's facing.
func holdcheck(a2: SimObject, a3: SimObject) -> void:
	if a3.locked() or a3.position == SimObject.POS_GOALIE or a3.fighting():
		return
	if ((_dir(a2, a3) - a2.facing() + 1) & 7) > 2:
		return
	if w.puckc == a3.index:
		w.sflags &= ~(1 << 3)
	var ax := HockeyWorld.s16(a3.vel.x + a2.vel.x) >> 1
	var ay := HockeyWorld.s16(a3.vel.y + a2.vel.y) >> 1
	a3.vel = Vector2i(ax, ay)
	a2.vel = Vector2i(ax, ay)
	a3.flags |= SimObject.PF_ALOCK
	a3.set_spa(SPA_FLAIL)
	a2.flags |= SimObject.PF_ALOCK
	a2.set_spa(SPA_HOLD2 if a2.spa == SPA_HOLD_HIGH else SPA_HOLD_AFTER)
	if checkagr(a2, a3) <= 6 and w.gmode & HockeyWorld.GM_HL == 0:
		var id := PEN_HOLDING if a2.spa == SPA_HOLD2 else PEN_HOOKING
		w.add_penalty(w.pen_shot_chk(id, a3, a2), a2)
	w.collflag = -1

## Bcheck (L49103): a2 sweep-checks a3.
func bcheck(a2: SimObject, a3: SimObject) -> void:
	if a3.locked() or a3.position == SimObject.POS_GOALIE or a3.fighting():
		return
	if not w.opt_pen and a2.joypad():
		var d0 := (0x20 + a2.checking) & 0xFF
		d0 = (d0 - a3.legstr) & 0xFF
		if w.crowd_boost:
			d0 = (d0 - 2) & 0xFF
		if HockeyWorld.s16(w.rng.range_(d0)) < 0x18:
			return
	if ((_dir(a2, a3) - a2.facing() + 1) & 7) > 2:
		return
	fall_down(a3, a2)
	if checkagr(a2, a3) <= 4:
		w.add_penalty(w.pen_shot_chk(PEN_TRIPPING, a3, a2), a2)
	w.collflag = -1

## holdplayer (L36863): human A without the puck.
func holdplayer(a3: SimObject) -> void:
	a3.flags |= SimObject.PF_ALOCK
	if a3.impact == 0:
		a3.set_spa(SPA_HOLD)
		return
	acheck(a3, w.objects[a3.impactp])

## Acheck (L36872): hold, stick in the air when the target is not behind.
func acheck(a3: SimObject, a0: SimObject) -> void:
	a3.flags |= SimObject.PF_ALOCK
	var d1 := SPA_HOLD
	if a3.impact != 0:
		var d := a3.y() - a0.y()
		if a3.attacking_top():
			d = -d
		if d >= 0:
			d1 = SPA_HOLD_HIGH
	a3.set_spa(d1)

# --- falls ---------------------------------------------------------------------------

## FallDown (L49156): a2 falls, a3 is the hitter. Returns the d1 it leaves behind (Q1),
## or Collisions.D1_UNCHANGED when it returns before touching d1.
func fall_down(a2: SimObject, a3: SimObject) -> int:
	if a2.index > 11:
		return Collisions.D1_UNCHANGED
	if a2.spa in ALREADY_DOWN:
		return Collisions.D1_UNCHANGED
	if w.player_chked == a2.index and w.player_chking == a3.index:
		return Collisions.D1_UNCHANGED
	w.player_chked = a2.index
	w.player_chking = a3.index
	if a2.flags3 & SimObject.PF3_ONETIMER or a3.flags3 & SimObject.PF3_ONETIMER:
		return Collisions.D1_UNCHANGED
	var d1 := SPA_STAGGER
	if a3.flags3 & SimObject.PF3_WALL == 0:
		# CmpPlayerStk: good stickhandlers stagger instead of falling.
		if HockeyWorld._sbyte(a2.stickhand & 0xFF) >= 0x18 and a2.nopuck_lo == 0:
			var t := (_hvword() & 0xF) + 0x10
			if t > a2.impact:
				a2.nopuck_lo = 0x3C
				return _fall_anim(a2, a3, SPA_STAGGER)
	_add_check_stats(a3)
	# _chkpos
	a2.nopuck_hi = 0x78
	var d0 := _dir(a2, a3)
	if a2.position != SimObject.POS_GOALIE:
		wallcollduringcheck(a2)
		if a2.flags3 & SimObject.PF3_WALL and _faller_on_board_side(a2, a3):
			if not (a2.y() >= -0x10C and a2.y() <= 0x10C and a2.x() >= -0x68 and a2.x() <= 0x68):
				d1 = _board_check(a2, a3)
				return _big_hit(a2, a3, d1)
	# Normal fall: front if the hitter is within one direction of the faller's facing.
	d1 = SPA_FALL_FRONT
	if ((d0 - a2.facing() + 1) & 7) <= 2:
		return _fall_anim(a2, a3, d1)
	return _big_hit(a2, a3, SPA_FALL_BACK)

## AddChktoPlayerStats (L49211).
func _add_check_stats(a3: SimObject) -> void:
	if a3.position == SimObject.POS_GOALIE:
		return
	var st := w.stats[a3.team()]
	st.checks += 1
	if a3.pnum >= 0 and a3.pnum < TeamStats.ROSTER:
		st.player_checks[a3.pnum] += 1
	w.chk_cnt += 1
	if a3.hf & 0xFF == 0:
		w.chk_cnt += 2

## _chkawayfrommiddle: is the faller on the boards side of the hitter?
static func _faller_on_board_side(a2: SimObject, a3: SimObject) -> bool:
	var d3 := a2.x() - a3.x()
	var d4 := a2.y() - a3.y()
	if a3.y() > 0x108:
		return d4 >= 0
	if a3.y() < -0x108:
		return d4 < 0
	if a3.x() >= 0:
		return d3 >= 3
	return d3 <= -3

## Board check: pick the boards animation and pin the faller (FallList, _getchkanim).
func _board_check(a2: SimObject, a3: SimObject) -> int:
	if a3.index <= 11:
		w.crowd_excite += 0xA
		w.crowd_level += 0x96
		a3.temp[0] &= 0xFF
		a3.glitch = 0
		a3.set_spa(SPA_BOARD_HITTER)
		a3.vel = Vector2i.ZERO
	var k := 2
	if a2.y() > 0x10C:
		k = 0
	elif a2.y() < -0x10C:
		k = 4
	elif a2.x() < 0:
		k = 6
	var d1 := FALL_LIST[k]
	w.fall_y = a2.y()
	w.fall_x = a2.x()
	if d1 == SPA_BOARDS_LEFT and a2.y() >= -0x59 and a2.y() <= 0x59:
		# sub_FE510(7) starts background animation 7 (bench area); not ported.
		w.background_anim.emit(7)
		d1 = SPA_OVER_RIGHT if a2.x_flip() else SPA_OVER_LEFT
	elif d1 == SPA_BOARDS_RIGHT and a2.y() >= -0x38 and a2.y() <= 0x38:
		d1 = SPA_OVER_LEFT if a2.x_flip() else SPA_OVER_RIGHT
	elif a2.x_flip():
		if d1 == SPA_BOARDS_RIGHT:
			d1 = SPA_BOARDS_LEFT
		elif d1 == SPA_BOARDS_LEFT:
			d1 = SPA_BOARDS_RIGHT
	a2.vel = Vector2i.ZERO
	a2.flags3 |= SimObject.PF3_FALLING
	a2.flags |= SimObject.PF_DOFF
	return d1

## loc_14392: the big-hit upgrade, then the shared animation tail.
func _big_hit(a2: SimObject, a3: SimObject, d1: int) -> int:
	if a2.facing() & 3 == 0 and HockeyWorld._sbyte(a3.checking & 0xFF) >= 0x14 \
			and a3.index <= 11 and a2.flags3 & SimObject.PF3_FALLING == 0:
		d1 = SPA_BIG_HIT
	return _fall_anim(a2, a3, d1)

## _2 / _21 / _22: set the fall, drop the puck, maybe injure.
func _fall_anim(a2: SimObject, a3: SimObject, d1: int) -> int:
	a2.flags |= SimObject.PF_ALOCK
	a2.set_spa(d1)
	if a3.position != SimObject.POS_GOALIE and a2.position != SimObject.POS_GOALIE:
		w.crowd_level += 0x12C
		w.crowd_excite += 0xF
	if w.puckc < 0 or w.puckc != a2.index:
		newcheck()
		return d1
	w.puckc = -1
	# Injury test.
	if w.gmode & HockeyWorld.GM_HL == 0 and a2.spa == SPA_FALL_FRONT and a2.facing() & 3 == 0 \
			and a2.flags2 & SimObject.PF2_PEN == 0:
		var r := w.rng.range_(0xA0)
		if r <= a2.impact and w.gmode & HockeyWorld.GM_CLOCK == 0:
			a2.set_spa(SPA_INJURED_GAME)
			d1 = set_injury_type(a2, a3)
			if not w.injury_game:
				a2.set_spa(SPA_INJURED_PERIOD)
				d1 = SPA_INJURED_PERIOD
			w.inj_countdown = 4
			if a3.position == SimObject.POS_GOALIE or not w.opt_pen:
				w.add_penalty2(PEN_STOPPAGE, a3)
			else:
				w.add_penalty2(PEN_ROUGHING_INJURY, a3)
				# Retail tail-jumps to Stop4Pen with a0 at the stats block (spec U3).
			return d1
	w.song.emit(SONG_CHEER if a2.away() else SONG_BOO)
	return d1

## setInjuryType (L49497). Returns the d1 it leaves (pnum * 2).
func set_injury_type(a2: SimObject, a3: SimObject) -> int:
	a2.flags2 |= SimObject.PF2_UNAV
	w.crowd_level += 0x12C
	w.crowd_excite += 0x1E
	w.sound.emit(SFX_INJURY)
	w.scroll_lock = a2.pos()
	w.sflags |= 1 << 6
	var pn := HockeyWorld._sbyte(a2.pnum & 0xFF)
	w.temp_pl_offset = (0x8000 if a2.away() else 0) | (a2.pnum & 0xFF)
	var st := w.stats[a2.team()]
	var f := (a3.hf & 0xFF) >> 2
	var game := false
	if f == 3:
		game = true
	elif f != 0 and a2.hf & 2:
		game = true
	w.injury_game = game
	if pn >= 0 and pn < TeamStats.ROSTER:
		st.player_status[pn] = TeamStats.STATUS_INJURED_GAME if game else TeamStats.STATUS_INJURED_PERIOD
	return pn * 2

# --- walls during checks, board pins --------------------------------------------------

## wallcollduringcheck (L963039): the real board bounce with radius + 23, no nets.
func wallcollduringcheck(a2: SimObject) -> void:
	if a2.position == SimObject.POS_GOALIE:
		return
	var rad := a2.radius + Vector2i(0x17, 0x17)
	a2.flags3 &= ~SimObject.PF3_WALL
	var n := RinkBoards.corner_normal(a2.pos(), rad)
	if n != Vector2i.ZERO:
		w.wallcoll(a2, n)
	if a2.wall != Vector2i.ZERO:
		return
	n = RinkBoards.straight_normal(a2.pos(), rad)
	if n != Vector2i.ZERO:
		w.wallcoll(a2, n)

## The falling-down block of updateplayers (L35375-35452) and sub_FEB54: ease halfway
## to the boards on the first animation frame, then pin.
func pin_to_boards(o: SimObject) -> void:
	var xf := o.x_flip()
	var axis_x := true
	var target := 0
	match o.spa:
		SPA_OVER_LEFT:
			target = 0x88 if xf else -0x88
		SPA_OVER_RIGHT:
			target = -0x88 if xf else 0x88
		SPA_BOARDS_LEFT:
			target = 0x82 if xf else -0x82
		SPA_BOARDS_RIGHT:
			target = -0x82 if xf else 0x82
		SPA_BOARDS_TOP:
			axis_x = false
			target = 0x116 if (w.fall_x > 0x56 or w.fall_x <= -0x56) else 0x124
		SPA_BOARDS_BOTTOM:
			axis_x = false
			target = -0x116 if (w.fall_x > 0x56 or w.fall_x <= -0x56) else -0x124
		_:
			return
	var cur := o.x() if axis_x else o.y()
	var nv := target
	if o.spa_num == 0:
		var delta := HockeyWorld.s16(target - cur)
		if o.spa == SPA_BOARDS_TOP and delta < 0:
			return
		if o.spa == SPA_BOARDS_BOTTOM and delta >= 0:
			return
		nv = cur + (delta >> 1)
	if axis_x:
		o.pos_fx.x = (nv << 16) | (o.pos_fx.x & 0xFFFF)
	else:
		o.pos_fx.y = (nv << 16) | (o.pos_fx.y & 0xFFFF)
