class_name FightLogic
extends RefCounted
## Fighting, from Chaos81's NHL '94 fight patch v1.01 (nhl94-patches, MIT): NHLPA '93's
## fight code moved into '94. checkfight (from checkcx), ChkFightValue, SF (start a
## fight), assfight ($14), chkhit, CwdFight, FightFall, assfwatch ($15), fightinput (from
## doinput), the fight banner and upgloves. The patch's menu option is opt_fight (OptFight:
## 0 Off, 1 On, 2 On - Arcade Mode); with it off (retail) nothing here runs.
## Spec: docs/specs/fight_patch.md.

const ASS_FIGHT := 0x14
const ASS_FWATCH := 0x15
const PEN_FIGHTING := 0x26
const PEN_FIGHTING_STAR := 0x28
const PEN_INSTIGATOR := 0x2A
## SPAList_Fight.bin.
const SPA_FIGHT := 0x1B96
const SPA_FGRAB := 0x1BC8
const SPA_FHELD := 0x1BEA
const SPA_FHIGH := 0x1C0C
const SPA_FLOW := 0x1C3E
const SPA_FHITH := 0x1C70
const SPA_FHITL := 0x1C92
const SPA_BFALL := 0x1CB4
const SPA_FFALL := 0x1CD6
## SPFfight: the first fight frame (847); gloves dropped at +2, grab +4/+9, high punch
## +6/+11, low punch +7/+12 (the second of each pair faces the other way).
const SPF_FIGHT := 0x34F
## The '93 gloves-and-stick frame (sprite_patch.asm's GloveCord frame).
const SPF_GLOVES := 0x34E
## Punch choice for the CPU (assfight .a1).
const PUNCHES: Array[int] = [SPA_FGRAB, SPA_FHIGH, SPA_FLOW]

## Testing tables (fight_patch.asm "Modifications"). By period length: < 2 min, 2-7 min,
## 7-20 min, >= 20 min.
const CHKCNT_TAB: Array[int] = [20, 30, 40, 40]    ## total checks before a fight
const CHKF_TAB: Array[int] = [8, 8, 16, 16]        ## ChksF needed to join (/2 in Arcade)
const FGTATT_TAB: Array[int] = [10, 6]             ## Fgt to start, by mode (On, Arcade)
const MINFGT_TAB: Array[int] = [2, 2]              ## Fgt to join, by mode
const INJ_TAB: Array[int] = [60, 45]               ## injury roll range, by mode
## Loopskip = 1: the ChksF clear after a fight is skipped.
const LOOPSKIP := true
## PerTimeTotal thresholds in seconds ($78, $1A4, $4B0).
const T_2MIN := 0x78
const T_7MIN := 0x1A4
const T_20MIN := 0x4B0

## sfx ids from the '93 code (SFXhithigh, SFXhitlow, SFXcrowdcheer, SFXcrowdboo), played
## through '94's sfx.
const SFX_HIT_HIGH := 9
const SFX_HIT_LOW := 0xA
const SFX_CHEER := 0xB
const SFX_BOO := 0xC

var w: HockeyWorld
## glovecords: where the dropped gloves and stick lie, in units of 4 px (0 = none).
var glove_x: int = 0
var glove_y: int = 0

## The fight banner: the two fighters, top line first (banner, sub_A8C4).
signal banner(lines: PackedStringArray)
## clear (sub_A8AE): the banner box is erased.
signal banner_cleared
## A fight started between objects a and b.
signal fight_started(a: int, b: int)

func _init(world: HockeyWorld) -> void:
	w = world

func register(t: Dictionary) -> void:
	t[ASS_FIGHT] = func(o: SimObject, d7: int) -> void: assfight(o, d7)
	t[ASS_FWATCH] = func(o: SimObject, d7: int) -> void: assfwatch(o, d7)

func _arcade() -> bool:
	return w.opt_fight == 2

## The period-length index of chkcnttab (d0 / 2).
func _period_index() -> int:
	var t := w.period_seconds
	if t >= T_20MIN:
		return 3
	if t > T_7MIN:
		return 2
	if t > T_2MIN:
		return 1
	return 0

## The same walk for chkftab ends on entry 1 for short periods ("moveq #2,d0").
func _period_index_chkf() -> int:
	var i := _period_index()
	return 1 if i == 0 else i

static func _ub(v: int) -> int:
	return v & 0xFF

static func _sb(v: int) -> int:
	return HockeyWorld._sbyte(v & 0xFF)

static func _sw(v: int) -> int:
	return HockeyWorld.s16(v)

# --- the start of a fight ----------------------------------------------------------------

## checkfight (from checkcx, after checkint and checkcheck, opposing teams only): a hard
## enough contact between two willing players starts a fight.
func checkfight(a3: SimObject, a2: SimObject) -> void:
	if w.opt_fight == 0:
		return
	if _sw(a3.impact) < 0xA or _sw(a2.impact) < 0xA:
		return
	if a3.locked() or a2.locked():
		return
	if a3.flags2 & SimObject.PF2_PEN or a2.flags2 & SimObject.PF2_PEN:
		return
	if a3.position == SimObject.POS_GOALIE or a2.position == SimObject.POS_GOALIE:
		return
	if w.gmode & HockeyWorld.GM_CLOCK or w.gmode & HockeyWorld.GM_HL:
		return
	var p := w.puck()
	if p.flags2 & SimObject.PF2_FIGHT:
		return
	# No fights in overtime.
	if w.gsp > 2:
		return
	if p.asslist[p.assnum & 7] == FaceoffLogic.ASS_PUCKFACEOFF:
		return
	var d0 := CHKCNT_TAB[_period_index()] - w.chk_cnt
	if _sw(d0) < 0:
		d0 = 0
	d0 = (d0 & 0xFFFF) >> 2
	d0 += FGTATT_TAB[1 if _arcade() else 0]
	# d0 is not restored between the two calls (the first may change it).
	d0 = chk_fight_value(a3, a2, d0)
	chk_fight_value(a2, a3, d0)
	if a3.flags2 & SimObject.PF2_FIGHT == 0:
		return
	w.chk_cnt = 0
	if not LOOPSKIP:
		for st in w.stats:
			st.player_checks.fill(0)
	w.crowd_level += 0x3E8
	w.crowd_excite += 0x23
	w.sflags &= ~(HockeyWorld.SF_PASSDIR | HockeyWorld.SF_SHOTDIR)
	w.puckc = a3.index
	w.scroll_lock.y = _sw(a3.y() + a2.y()) >> 1
	w.sflags |= HockeyWorld.SF_SLOCK
	# Face to face: the one on the left faces 2 (east), the other 5.
	var d1 := 2
	if a3.x() >= a2.x():
		d1 ^= 7
	_facing(a3, d1)
	_facing(a2, d1 ^ 7)
	start_fight(a3, a2)
	start_fight(a2, a3)
	for i in 12:
		var o := w.objects[i]
		if o.flags2 & SimObject.PF2_FIGHT or o.position == SimObject.POS_GOALIE:
			continue
		if o.flags2 & SimObject.PF2_UNAV:
			continue
		w.assinsert(o, ASS_FWATCH)
	p.flags2 |= SimObject.PF2_FIGHT
	w.assinsert(p, PuckLogic.ASS_PUCKUNFLIP)
	w.collflag = -1
	fight_started.emit(a3.index, a2.index)

## SF: one fighter squares up. a2 is his opponent.
func start_fight(a3: SimObject, a2: SimObject) -> void:
	a3.impactp = a2.index
	w.add_penalty2(PEN_FIGHTING, a3)
	w.hand_control(a3)
	w.assinsert(a3, ASS_FIGHT)
	a3.attribute &= ~SimObject.ATTR_XFLIP
	var d1 := -0x400
	if a3.facing() != 2:
		a3.attribute |= SimObject.ATTR_XFLIP
		d1 = 0x400
	a3.vel.x = d1
	a3.flags2 |= SimObject.PF2_UNAV | SimObject.PF2_AIP | SimObject.PF2_NOCOLL
	a3.flags &= ~SimObject.PF_ALOCK
	a3.set_spa(SPA_FIGHT)

## ChkFightValue: a3 starts it when his Fgt reaches d0; a2 joins on Fgt and his checks.
## Returns d0 as the routine leaves it (checkfight passes it on to the second call).
func chk_fight_value(a3: SimObject, a2: SimObject, d0: int) -> int:
	if _ub(d0) > _ub(a3.hf):
		return d0
	var d1 := MINFGT_TAB[1 if _arcade() else 0]
	if _sb(d1) > _sb(a2.hf):
		return d0
	var st := w.stats[a2.team()]
	d1 = st.player_checks[a2.pnum] if TeamStats.valid_pnum(a2.pnum) else 0
	d1 = _ub(-_ub(d1 << 1))
	d0 = CHKF_TAB[_period_index_chkf()]
	if _arcade():
		d0 = (d0 & 0xFF00) | _ub(_sb(d0) >> 1)
	d1 = _ub(d1 + d0)
	if _sb(d1) > _sb(a2.hf):
		return d0
	a2.flags2 |= SimObject.PF2_FIGHT
	var was := a3.flags2 & SimObject.PF2_FIGHT
	a3.flags2 |= SimObject.PF2_FIGHT
	if was:
		return d0
	if not w.opt_pen:
		return d0
	# The H/V counter: one fight in four also draws an instigator penalty.
	d0 = w.checking._vcounter() & 3
	if d0 != 0:
		return d0
	var base := 6 if a3.away() else 0
	d0 = 5
	for i in 6:
		var o := w.objects[base + i]
		if o != a3 and o.position > 0 and o.flags2 & (SimObject.PF2_PEN | SimObject.PF2_UNAV) == 0:
			w.add_penalty2(PEN_INSTIGATOR, o)
			return PEN_INSTIGATOR
		d0 -= 1
	return 0xFFFF

# --- the fight ------------------------------------------------------------------------------

## assfight ($14): square off, punch (CPU), take hits, until the penalty countdown runs out.
func assfight(a3: SimObject, d7: int) -> void:
	if a3.locked():
		return
	if w.rules.pencntdwn < 0:
		w.assnothing(a3, d7)
		return
	if a3.flags & SimObject.PF_NA:
		a3.flags &= ~SimObject.PF_NA
		# Strength: energy times Fgt (mulu.w), then lsr.w 8 and 4 on the low word only;
		# at least 5 hits.
		var d0 := ((w.energy_of(a3) & 0xFFFF) * (_sb(a3.hf) & 0xFFFF)) & 0xFFFF
		d0 >>= 12
		if d0 <= 5:
			d0 = 5
		a3.temp[2] = d0
		a3.temp[1] = 0
		a3.temp[3] = 0xFFFF
		if a3.facing() == 2:
			a3.temp[3] = 0x5A
	var t4 := (a3.temp[3] & 0xFFFF) - d7
	a3.temp[3] = t4 & 0xFFFF
	if t4 < 0:
		show_banner()
	if _sw(a3.temp[2]) < 0:
		return
	var a0 := w.objects[a3.impactp] if a3.impactp >= 0 and a3.impactp < 12 else a3
	w.scroll_lock.x = _sw(a3.x() + a0.x()) >> 1
	if not a3.joypad():
		var was := a3.flags2 & SimObject.PF2_AIP
		a3.flags2 |= SimObject.PF2_AIP
		if not was:
			var d0 := a3.x() - a0.x() + (_sw(a3.vel.x) >> 8) - (_sw(a0.vel.x) >> 8)
			if _sw(d0) <= 0x14 and _sw(d0) >= -0x14:
				var r := w.rng.range_(8)
				if r > 2:
					r &= 1
				a3.set_spa(PUNCHES[r])
	chkhit(a3, a0)
	var adjust_x: bool
	if a3.spa == SPA_FHELD:
		adjust_x = true
	elif a3.spa == SPA_FIGHT or a3.joypad():
		adjust_x = false
	else:
		adjust_x = true
	if adjust_x:
		var d0 := w.scroll_lock.x + 0xA
		if a3.facing() == 2:
			d0 -= 0x14
		d0 = _sw(_sw(d0 - a3.x()) << 5)
		a3.vel.x = _sw(a3.vel.x + d0)
	var d1 := _sw(_sw(w.scroll_lock.y - a3.y()) << 8)
	if d1 >= 0x1000:
		d1 = 0x1000
	if d1 <= -0x1000:
		d1 = -0x1000
	a3.vel.y = d1

## chkhit: once per new frame, a punch frame or the grab frame within reach of the
## opponent lands; the gloves frame drops the gloves.
func chkhit(a3: SimObject, a0: SimObject) -> void:
	var f := a3.frame & 0x7FF
	if f == a3.old_frame:
		return
	if f == SPF_FIGHT + 2:
		_dropped(a3)
		return
	var dx := _sw(a3.x() - a0.x())
	if dx > 0x16 or dx < -0x16:
		return
	var dy := _sw(a3.y() - a0.y())
	if dy > 8 or dy < -8:
		return
	if f == SPF_FIGHT + 6 or f == SPF_FIGHT + 6 + 5:
		_hit(a0, a3, SPA_FHITH, SFX_HIT_HIGH)
	elif f == SPF_FIGHT + 7 or f == SPF_FIGHT + 7 + 5:
		_hit(a0, a3, SPA_FHITL, SFX_HIT_LOW)
	elif f == SPF_FIGHT + 4 or f == SPF_FIGHT + 4 + 5:
		a0.flags2 |= SimObject.PF2_AIP
		a0.set_spa(SPA_FHELD)

## .dropped: the gloves and stick land between the fighters (clamped to 90 px of centre).
func _dropped(a3: SimObject) -> void:
	a3.flags2 &= ~SimObject.PF2_NOCOLL
	var d0 := clampi(w.scroll_lock.x, -0x5A, 0x5A) >> 2
	if d0 == 0:
		d0 = 1
	glove_x = _sb(d0)
	glove_y = _sb(w.scroll_lock.y >> 2)

## .hithigh / .hitlow: the victim reels and loses a point of strength; below zero he falls.
func _hit(victim: SimObject, attacker: SimObject, spa: int, sfx: int) -> void:
	cwd_fight(victim, attacker)
	victim.flags2 |= SimObject.PF2_AIP
	victim.temp[2] = _sw(victim.temp[2] - 1)
	if victim.temp[2] < 0:
		fight_fall(victim, attacker)
		return
	victim.set_spa(spa)
	w.sound.emit(sfx)

## CwdFight: the crowd reacts and the victim is knocked back.
func cwd_fight(victim: SimObject, attacker: SimObject) -> void:
	w.crowd_level += 0x50
	w.crowd_excite += 0xA
	var d0 := ((5 + attacker.temp[2]) & 0xFFFF) * 0x1F4
	d0 = _sw(d0)
	if victim.facing() == 2:
		d0 = _sw(-d0)
	victim.vel.x = _sw(victim.vel.x + d0)

## FightFall: the loser goes down. The winner's Fighting entry becomes Fighting *, the
## countdown to the call is cut to a second (three on an injury).
func fight_fall(loser: SimObject, winner: SimObject) -> void:
	var buf := w.rules.pen_buf
	# The ROM scans PenBuf without a bound; the entry is always there.
	for i in buf.size():
		if (buf[i] >> 8) & 0xFF == PEN_FIGHTING and (buf[i] & 0xF) == winner.index:
			buf[i] = (PEN_FIGHTING_STAR << 8) | (buf[i] & 0xFF)
			break
	w.rules.pencntdwn = 0x3C
	winner.temp[2] = -1
	w.crowd_level += 0x258
	w.crowd_excite += 0x1E
	var d0 := w.rng.range_(INJ_TAB[1 if _arcade() else 0])
	if _sb(d0) > _sb(winner.checking):
		loser.set_spa(SPA_BFALL)
		# A home loser draws boos, an away loser cheers.
		w.sound.emit(SFX_CHEER if loser.away() else SFX_BOO)
		return
	w.rules.pencntdwn = 0xB4
	loser.flags2 |= SimObject.PF2_FIGHT_HURT
	loser.set_spa(SPA_FFALL)
	banner_cleared.emit()
	injure(loser)

## The fight injury: setInjuryType, then `move.w #$112C,$66(a0,d1.w)` replaces his
## tmpdst: a 5:00 major ($12C) with bit 12, so InProgress keeps him off the strength
## count and the expiry leaves $1000, out for the rest of the game ("Injury G").
func injure(loser: SimObject) -> void:
	var d1 := w.checking.set_injury_type(loser, loser)
	var pn := d1 >> 1
	if pn >= 0 and pn < TeamStats.ROSTER:
		w.stats[loser.team()].tmpdst[pn] = 0x112C
	w.inj_countdown = 3

# --- the others ------------------------------------------------------------------------------

## assfwatch ($15): skate to a spot 80 px from the fight on your side of it and watch.
func assfwatch(a3: SimObject, d7: int) -> void:
	if a3.locked() or a3.joypad():
		return
	if a3.flags & SimObject.PF_NA:
		a3.flags &= ~SimObject.PF_NA
		a3.temp[0] = 0
	a3.temp[0] = _sw(a3.temp[0] - d7)
	if a3.temp[0] < 0:
		a3.temp[0] = _sw(a3.temp[0] + 0x3C)
		var d0 := _sw(a3.x() - w.scroll_lock.x)
		var d1 := _sw(a3.y() - w.scroll_lock.y)
		var d2 := RinkBoards.sroot(d0 * d0 + d1 * d1) & 0xFFFF
		if d2 == 0:
			d2 = 1
		d0 = _sw(_divs(d0 * 0x50, d2) + w.scroll_lock.x)
		d0 = clampi(d0, -0x7E, 0x7E)
		a3.temp[2] = d0
		d1 = _sw(_divs(d1 * 0x50, d2) + w.scroll_lock.y)
		a3.temp[3] = d1
	w.ai.skateto(a3, _sw(a3.temp[2]), _sw(a3.temp[3]), Callable(), d7)
	w.ai.check4check(a3)

static func _divs(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

# --- the pad ----------------------------------------------------------------------------------

## fightinput (doinput, fighting): the pad moves the fighter and throws C high, B low, A
## grab. d0 dpad (bit 3 = centred), d1 new buttons.
func fightinput(a3: SimObject, d0: int, d1: int, d7: int) -> void:
	if _sw(a3.temp[2]) < 0 or w.rules.pencntdwn < 0:
		return
	if a3.spa == SPA_FIGHT:
		return
	if d0 & 8 == 0:
		w.playeracc(a3, d0 & 7, d7)
	# Stay face to face, within reach of the centre of the fight.
	var t := w.scroll_lock.x + 0xC
	if a3.facing() == 2:
		t -= 0x18
	t = _sw(t - a3.x())
	if (t ^ a3.vel.x) & 0x8000:
		var m := (absi(t) * _sw(a3.vel.x)) >> 4
		a3.vel.x = _sw(a3.vel.x - m)
	var was := a3.flags2 & SimObject.PF2_AIP
	a3.flags2 |= SimObject.PF2_AIP
	if was:
		return
	if d1 & PadState.C:
		a3.set_spa(SPA_FHIGH)
	elif d1 & PadState.B:
		a3.set_spa(SPA_FLOW)
	elif d1 & PadState.A:
		a3.set_spa(SPA_FGRAB)
	else:
		a3.flags2 &= ~SimObject.PF2_AIP

# --- display -------------------------------------------------------------------------------

## banner (sub_A8C4): the last two PenBuf entries (the two Fighting calls), "jersey Name
## ABBR", one over "vs" over the other. The latest entry goes on top only when its Fgt
## is the higher.
func show_banner() -> void:
	# lcfound2 for both teams only erases the line-change boxes on screen; the HUD draws
	# the banner over them.
	var buf := w.rules.pen_buf
	var n := 0
	while n < buf.size() and buf[n] != 0:
		n += 1
	if n < 2:
		return
	var first := w.objects[buf[n - 1] & 0xF]
	var second := w.objects[buf[n - 2] & 0xF]
	var d3 := _sb(_sb(second.hf) - _sb(first.hf))
	var a := _fighter_line(first)
	var b := _fighter_line(second)
	if d3 < 0:
		banner.emit(PackedStringArray([a, "vs", b]))
	else:
		banner.emit(PackedStringArray([b, "vs", a]))

func _fighter_line(o: SimObject) -> String:
	var st := w.stats[o.team()]
	var name := "#%d" % o.pnum
	var abbr := "HOME" if o.team() == 0 else "AWAY"
	if st.data:
		abbr = st.data.abbreviation
		var p := st.data.player(o.pnum)
		if p:
			name = "%d %s" % [p.jersey_number, p.full_name]
	return "%s %s" % [name, abbr]

## glovecords cleared (puckfaceoff2, puckpenshot).
func clear_gloves() -> void:
	glove_x = 0
	glove_y = 0

## upgloves: the gloves-and-stick sprite's position, or null when none lie on the ice.
func gloves_pos() -> Variant:
	if glove_x == 0:
		return null
	return Vector2i(glove_x * 4, glove_y * 4)

static func _facing(o: SimObject, d: int) -> void:
	o.facing_fx = (d << 16) | (o.facing_fx & 0xFFFF)
