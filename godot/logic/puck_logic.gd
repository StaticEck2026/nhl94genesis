class_name PuckLogic
extends RefCounted
## The puck. Port of pucknorm, findpc, a2touchpuck, a2offsides, ChkOffsides, puckIChk,
## puckflip/puckunflip/puckshadow, checkpuckcoll, puckstick (steals, pickup, _glue),
## puckbody, puckgoalie, deflect, checkgoal (nets, posts, goals), checkgoalp/CheckBump,
## wallcollb2 (over the glass) and the puck Z stall counter. Spec: docs/specs/puck.md.
## a2 is the player, a3 the puck, as in the asm.

## _cbg / _cbgsq (L50382): goalie body half-size and its square by agility.
const CBG: Array[int] = [0xC, 0xC, 0xD, 0xD, 0xD, 0xD, 0xD, 0xD, 0xD, 0xD, 0xE, 0xE, 0xE, 0xE, 0xF, 0xF, 0xF, 0xF, 0xF, 0xF]
const CBGSQ: Array[int] = [0x90, 0x90, 0xA9, 0xA9, 0xA9, 0xA9, 0xA9, 0xA9, 0xA9, 0xA9, 0xC4, 0xC4, 0xC4, 0xC4, 0xE1, 0xE1, 0xE1, 0xE1, 0xE1, 0xE1]

const SPA_PUCK_FLIP := 0x46A
const SPA_HIT_BY_PUCK := 0x10D0
const SPA_GOALIE_DIVE := 0x2F4
const SPA_PAD_STACK_L := 0x250
const SPA_PAD_STACK_R := 0x2A2
const SPA_GOAL_SIREN := 0x102E
const SPA_GOAL_LIGHT := 0x1078
const SHADOW_FRAME := 0x18A

const ASS_PUCKNORM := 0x18
const ASS_PUCKSHADOW := 0x19
const ASS_PUCKUNFLIP := 0x1A
const ASS_SCORE := 7

const PEN_STALLED := 6
const PEN_NET_OFF := 8
const PEN_PS_OVER := 0xA
const PEN_ICING := 0xC
const PEN_GOAL := 0xE
const PEN_OFFSIDE := 0x10

var w: HockeyWorld

func _init(world: HockeyWorld) -> void:
	w = world

# --- per loop -----------------------------------------------------------------------

## updateplayers L35335: a puck stuck in the air sinks 1 px every 17 loops.
func z_stall() -> void:
	if w.sflags & HockeyWorld.SF_HOR:
		return
	var p := w.puck()
	var pz := p.z()
	if pz <= 5:
		w.puck_z_cntr = 0
	elif w.tmp_puck_z != pz:
		w.tmp_puck_z = pz
		w.puck_z_cntr = 0
	else:
		w.puck_z_cntr += 1
		if w.puck_z_cntr >= 0x10:
			w.puck_z_cntr = 0
			p.z_fx = ((pz - 1) << 16) | (p.z_fx & 0xFFFF)

## pucknorm (L42526): the puck's assignment in normal play.
func pucknorm(a3: SimObject, d7: int) -> void:
	if w.ba_ps_flags & HockeyWorld.BA_LIVE:
		w.ps_attempt_check()
	if a3.flags & SimObject.PF_NA:
		a3.flags &= ~SimObject.PF_NA
		a3.temp[0] = 0
		a3.temp[1] = 0x78
	w.puckcross[1] -= d7
	w.puckcross[3] -= d7
	a3.temp[0] -= d7
	if a3.temp[0] < 0:
		a3.temp[0] += 5
		findpc()
	if w.puckc >= 0:
		var a2 := w.objects[w.puckc]
		a2touchpuck(a2)
		var hot := w.get_hot(a2)
		var dx := (hot.x + a2.x() - a3.x()) >> 2
		var dy := (hot.y + a2.y() - a3.y()) >> 2
		_add_pixels(a3, Vector2i(dx, dy))
		a3.vel = a2.vel
	puck_i_chk()
	chk_offsides(a3)
	if w.gmode & HockeyWorld.GM_CLOCK == 0:
		if w.puckc < 0 and a3.pos() == a3.old_pos():
			a3.temp[1] -= 1
			if a3.temp[1] < 0:
				w.add_penalty2(PEN_STALLED, a3)
		else:
			a3.temp[1] = 0x78
	if (a3.zvel >> 8) & 0xFF == 0 and a3.z() == 0:
		puckunflip(a3)
	checkpuckcoll(a3)

## Moves the pixel words only (word adds on the high words; fractions kept).
static func _add_pixels(o: SimObject, d: Vector2i) -> void:
	o.pos_fx = Vector2i(((o.x() + d.x) << 16) | (o.pos_fx.x & 0xFFFF), ((o.y() + d.y) << 16) | (o.pos_fx.y & 0xFFFF))

## findpc (L42894): where and when the loose puck crosses each goal line.
func findpc() -> void:
	var p := w.puck()
	for k in 2:
		var slot := k * 2
		var line := 0x108 if k == 0 else -0x108
		var dy := HockeyWorld.s16(line - p.y())
		if p.vel.y == 0:
			w.puckcross[slot + 1] = -1
			continue
		var t: Variant = _divs_or_null((dy << 16) >> 4, p.vel.y)
		if t == null or t < 0:
			# Overflow: the 68000 leaves N undefined; treated as no crossing (spec U1).
			w.puckcross[slot + 1] = -1
			continue
		w.puckcross[slot + 1] = t
		var xq: Variant = _divs_or_null(dy * p.vel.x, p.vel.y)
		if xq == null:
			w.puckcross[slot + 1] = -1
			continue
		var x: int = xq + p.x()
		if x >= 0x88:
			x = -x + 3 * 0x88
		if x <= -0x88:
			x = -x - 3 * 0x88
		w.puckcross[slot] = x

## divs.w: null on overflow (quotient outside 16 bits).
static func _divs_or_null(a: int, b: int) -> Variant:
	if b == 0:
		return null
	var q := absi(a) / absi(b)
	if (a >= 0) != (b >= 0):
		q = -q
	if q > 0x7FFF or q < -0x8000:
		return null
	return q

# --- touches, offsides, icing -------------------------------------------------------

## a2touchpuck (L42716): last touch, assist chain, shot flag, offside and icing.
func a2touchpuck(a2: SimObject) -> void:
	w.ltx = a2.x()
	w.lty = a2.y()
	w.ltplayer = a2.index
	var st := w.stats[a2.team()]
	var d0 := a2.pnum & 0xFF
	if a2.flags3 & SimObject.PF3_ONETIMER:
		w.f_c2fe |= HockeyWorld.C2FE_ONETIMER_TOUCH
	if d0 != (st.toucher & 0xFF):
		if st.flags30 & TeamStats.F30_CHAIN_RESET == 0:
			st.assist2 = st.assist1
			st.assist1 = st.toucher
		st.flags30 &= ~TeamStats.F30_CHAIN_RESET
		st.toucher = d0
		if (st.assist2 & 0xFF) == d0:
			st.assist2 = -1
	w.sflags2 &= ~HockeyWorld.SF2_SHOT
	a2offsides(a2)
	var ifl := w.iflags
	if ifl & HockeyWorld.IF_OK and ifl & HockeyWorld.IF_CGL and a2.position != 0:
		var icing: bool
		if ifl & HockeyWorld.IF_DIR:
			icing = not a2.attacking_top()
		else:
			icing = a2.attacking_top()
		if icing:
			w.add_penalty(PEN_ICING, w.objects[w.icing_player])
			return
	# Re-arm for this toucher.
	w.iflags = 0
	w.icing_player = a2.index
	var y := w.puck().y()
	if a2.attacking_top():
		w.iflags |= HockeyWorld.IF_DIR
		y = -y
	if y < 0:
		return
	var diff := w.stats[0].on_ice - w.stats[1].on_ice
	if a2.away():
		diff = -diff
	if diff < 0:
		return
	w.iflags |= HockeyWorld.IF_OK

## a2offsides (L42687).
func a2offsides(a2: SimObject) -> void:
	if w.gmode & HockeyWorld.GM_OFFS == 0:
		return
	var y := w.puck().y()
	if not a2.attacking_top():
		y = -y
	if y < 0x68:
		return
	if w.stats[a2.team()].flags30 & TeamStats.F30_OFFSIDE == 0:
		return
	if w.gmode & HockeyWorld.GM_HL:
		return
	w.add_penalty(PEN_OFFSIDE, a2)

## ChkOffsides (L42598) and sub_100A6: set or clear each team's offside flag.
func chk_offsides(a3: SimObject) -> void:
	if w.gmode & HockeyWorld.GM_OFFS == 0 or w.ba_ps_flags & HockeyWorld.BA_LIVE:
		return
	_clear_offside(w.stats[1])
	_clear_offside(w.stats[0])
	var top_team := 0 if w.gmode & HockeyWorld.GM_DIR == 0 else 1
	if a3.y() >= 0x54:
		if a3.old_pos().y >= 0x54:
			return
		_flag_offside(top_team, func(o: SimObject) -> bool: return o.y() > 0x5E)
	else:
		if a3.y() > -0x54:
			return
		if a3.old_pos().y <= -0x54:
			return
		_flag_offside(1 - top_team, func(o: SimObject) -> bool: return o.y() < -0x5E)

func _flag_offside(team: int, beyond: Callable) -> void:
	var st := w.stats[team]
	for i in 6:
		var o := w.objects[st.first_object + i]
		if o.position >= 0 and beyond.call(o):
			st.flags30 |= TeamStats.F30_OFFSIDE
			return

## sub_100A6: clear the flag once nobody of that team is still past the line. Off-ice
## structs are skipped (retail reuses a stale register for them; spec U3).
func _clear_offside(st: TeamStats) -> void:
	if st.flags30 & TeamStats.F30_OFFSIDE == 0:
		return
	for i in 6:
		var o := w.objects[st.first_object + i]
		if o.position < 0:
			continue
		var d0 := o.y() if o.attacking_top() else -o.y()
		if d0 > 0x58:
			return
	st.flags30 &= ~TeamStats.F30_OFFSIDE

## puckIChk (L42796): the armed icing puck crosses the far goal line.
func puck_i_chk() -> void:
	var ifl := w.iflags
	if ifl & HockeyWorld.IF_OK == 0 or ifl & HockeyWorld.IF_CGL or w.puckc >= 0:
		return
	var p := w.puck()
	if ifl & HockeyWorld.IF_DIR:
		if p.y() < 0x108:
			return
	elif p.y() >= -0x108:
		return
	if p.x() >= -0x2C and p.x() <= 0x2C:
		w.iflags &= ~HockeyWorld.IF_OK
	else:
		w.iflags |= HockeyWorld.IF_CGL

# --- puck animation ------------------------------------------------------------------

## puckunflip (L42831): the puck lies flat.
func puckunflip(a3: SimObject) -> void:
	if a3.spa_num >= 8 and a3.spa_num < 0x18:
		a3.facing_fx ^= 2 << 16
	a3.facing_fx |= 4 << 16
	a3.spa_num = 0
	a3.spa_cnt = -1

## puckflip (L42849): start the spin.
func puckflip(a3: SimObject, d0: int) -> void:
	var f := ((a3.facing() ^ (d0 & 1)) & 3)
	a3.facing_fx = (f << 16) | (a3.facing_fx & 0xFFFF)
	a3.spa_cnt = -1
	a3.set_spa(SPA_PUCK_FLIP)

## puckshadow (L42862): the shadow follows the puck, or plays the goal siren.
func puckshadow(s: SimObject) -> void:
	var p := w.puck()
	if s.frame == SHADOW_FRAME:
		s.pos_fx = Vector2i((p.x() << 16) | (s.pos_fx.x & 0xFFFF), ((p.y() + 1) << 16) | (s.pos_fx.y & 0xFFFF))
		s.z_fx &= 0xFFFF
		return
	if s.frame == 0:
		return
	var y := 0x12C
	var z := 0xE
	if p.y() < 0:
		s.attribute = 0x8000
		y = -0x12C
		z = 0xD
	s.pos_fx = Vector2i(s.pos_fx.x & 0xFFFF, (y << 16) | (s.pos_fx.y & 0xFFFF))
	s.z_fx = (z << 16) | (s.z_fx & 0xFFFF)

# --- puck vs players ----------------------------------------------------------------

## checkpuckcoll (L50247): walk the Y order for sticks, bodies and goalies.
func checkpuckcoll(a3: SimObject) -> void:
	if a3.y() > 0x190 or a3.y() <= -0x190:
		a3.vel.y = 0
	if a3.z() > 0x10:
		return
	var i := w.oo_pos[HockeyWorld.PUCK]
	while i != HockeyWorld.SORT_OBJS - 1:
		var n := w.oo_list[i + 1]
		if w.ylist[n] - a3.y() > 0x16:
			break
		_ccx(a3, n)
		i += 1
	i = w.oo_pos[HockeyWorld.PUCK]
	while i != 0:
		var n := w.oo_list[i - 1]
		if a3.y() - w.ylist[n] > 0x16:
			break
		_ccx(a3, n)
		i -= 1

func _ccx(a3: SimObject, p: int) -> void:
	if p == w.puckc or p > 11:
		return
	var a2 := w.objects[p]
	if w.ba_ps_flags & HockeyWorld.BA_LIVE and p != w.ba_sktr and p != w.ba_goalie:
		return
	if a2.flags & SimObject.PF_NC:
		return
	if a2.nopuck_hi != 0:
		return
	var stick := a2.flags2 & SimObject.PF2_UNAV == 0 and a3.z() <= 5 and HockeyWorld.s16(a3.zvel) <= 0x200
	if stick:
		var hot := w.get_hot(a2)
		var dx := hot.x + a2.x() - a3.x()
		var dy := hot.y + a2.y() - a3.y()
		if dx >= -0xE and dx <= 0xE and dy >= -0xE and dy <= 0xE:
			var d := dx * dx + dy * dy
			var lim := 0xC4
			if HockeyWorld._sbyte(a3.nopuck_hi & 0xFF) > 0:
				lim = 0xC4 >> 2
			if d <= lim:
				puckstick(a2, a3, d)
				return
	if a2.position == SimObject.POS_GOALIE:
		_chk_goalie(a2, a3)
		return
	if a2.flags3 & SimObject.PF3_ONETIMER:
		return
	var bx := a2.x() - a3.x()
	var by := a2.y() - a3.y()
	if bx > 8 or bx < -8 or by > 8 or by < -8:
		return
	var bd := bx * bx + by * by
	if bd > 0x40:
		return
	puckbody(a2, a3, bd)

## chkgoalie (L50425): the goalie's body box from agility.
func _chk_goalie(a2: SimObject, a3: SimObject) -> void:
	var d0 := a2.legstr & 0xFF
	if w.crowd_boost:
		d0 = (d0 + 2) & 0xFF
	d0 >>= 1
	if a2.joypad():
		d0 = 0xF
	d0 *= 2
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT and d0 != 0:
		d0 -= 2
	if d0 >= 0x1E:
		d0 = 0x1E
	var g: int = CBG[d0 >> 1]
	var gsq: int = CBGSQ[d0 >> 1]
	if w.f_c2f8 & HockeyWorld.C2F8_ONETIMER_SHOT:
		g = 0xC
		gsq = 0x90
	if a2.spa == SPA_PAD_STACK_L or a2.spa == SPA_PAD_STACK_R:
		g = 0x12
		gsq = 0x144
	if a3.z() > 0xF:
		return
	var gx := a2.x()
	var off := 0
	if a2.spa == SPA_PAD_STACK_L:
		off = -6
	elif a2.spa == SPA_PAD_STACK_R:
		off = 6
	if off != 0:
		if not a2.attacking_top():
			off = -off
		if a2.handed & 1:
			off = -off
		gx += off
	var dx := gx - a3.x()
	var dy := a2.y() - a3.y()
	if dx > g or dx < -g or dy > g or dy < -g:
		return
	if dx * dx + dy * dy > gsq:
		return
	puckgoalie(a2, a3)

## makepde (L51186): rating scaled by the player's energy.
func makepde(o: SimObject, rating: int) -> int:
	return (HockeyWorld._sbyte(rating & 0xFF) * w.energy_of(o)) >> 12

## puckstick (L50534): steal, pickup, deflection or one-timer.
func puckstick(a2: SimObject, a3: SimObject, d0: int) -> void:
	if a2.position == SimObject.POS_GOALIE and w.gmode & HockeyWorld.GM_HL:
		return
	a2.flags &= ~SimObject.PF_DOFF
	if w.puckc >= 0:
		var a0 := w.objects[w.puckc]
		if (a0.flags ^ a2.flags) & SimObject.PF_TEAM == 0:
			return
		var slot := w.f_c2f8 & HockeyWorld.C2F8_SLOT != 0
		if d0 > (0x40 if slot else 0x24):
			return
		if a2.position != SimObject.POS_GOALIE:
			if a0.position == SimObject.POS_GOALIE:
				return
			var c := makepde(a0, a0.stickhand >> 1)
			var k := makepde(a2, a2.stickhand >> 1)
			var r := w.rng.range_(c - k + 0x24)
			if r > (4 if slot else 2):
				return
		a0.nopuck_hi = (makepde(a0, a0.stickhand >> 1) + 0x14) & 0xFF
		a2.nopuck_hi = (makepde(a2, a2.stickhand >> 1) + 0x14) & 0xFF
		w.lastplayer = a0.index
		w.sflags &= ~(HockeyWorld.SF_PASSDIR | HockeyWorld.SF_SHOTDIR)
		_stdef(a2, a3)
		return
	if a2.position == SimObject.POS_GOALIE and d0 > 0x40:
		return
	if a2.flags3 & SimObject.PF3_ONETIMER:
		if d0 > 0x64:
			if d0 <= 0x144 and a2.spa_num < 0x18:
				a2.spa_num = 0x18
			return
		if a2.spa_num < 0x18:
			a2.spa_num = 0x18
			w.f_c2fe |= HockeyWorld.C2FE_ONETIMER_TOUCH
	var s := a3.vel.x * a3.vel.x + a3.vel.y * a3.vel.y
	var t: int
	if w.sflags2 & HockeyWorld.SF2_SHOT:
		t = 0x32C8
	elif a2.flags3 & SimObject.PF3_ONETIMER:
		w.onetimer_shot.emit(a2.index)
		return
	else:
		t = (a2.stickhand * 0x15E + 0x32C8) & 0xFFFF
	if s <= t * t:
		glue(a2)
		return
	a2.nopuck_hi = 8
	_stdef(a2, a3)

func _stdef(a2: SimObject, a3: SimObject) -> void:
	w.sound.emit(6)
	a2touchpuck(a2)
	deflect(a3)

## _glue (L50665): a2 takes the puck.
func glue(a2: SimObject) -> void:
	var snd := 7
	w.puckc = a2.index
	var mine := w.stats[a2.team()]
	var theirs := w.stats[1 - a2.team()]
	theirs.assist1 = -1
	theirs.assist2 = -1
	theirs.flags30 |= TeamStats.F30_CHAIN_RESET
	if w.sflags3 & HockeyWorld.SF3_FACEOFF_WIN:
		w.sflags3 &= ~HockeyWorld.SF3_FACEOFF_WIN
		mine.faceoffs_won += 1
		w.crowd_level += 0xC8
		snd = 0xC
		if not a2.away():
			w.crowd_excite += 0xA
			snd = 0xB
	w.song.emit(snd)
	if a2.index == w.passplayer:
		mine.passes += 1
	w.passplayer = -1
	w.sflags &= ~(HockeyWorld.SF_PASSDIR | HockeyWorld.SF_SHOTDIR)
	if a2.position == SimObject.POS_GOALIE:
		w.chk_shot_stat()
		a2.temp[4] = 5 if a2.spa == SPA_GOALIE_DIVE else 0x8C
	w.hand_control(a2)

## puckbody (L50765): the puck hits a skater.
func puckbody(a2: SimObject, a3: SimObject, d0: int) -> void:
	if a2.flags3 & SimObject.PF3_ONETIMER:
		return
	if a3.z() <= 8 and d0 & 0xF != 0:
		return
	a2touchpuck(a2)
	w.sound.emit(0x24)
	a3.zvel = 0
	a2.nopuck_hi = 8
	var off := Vector2i(a3.x() - a2.x(), a3.y() - a2.y())
	if off.y == 0:
		off = w.get_hot(a2)
	var ovx := a3.vel.x
	var ovy := a3.vel.y
	_set_vel_high_bytes(a3, off)
	puckflip(a3, off.x)
	if a3.z() <= 8:
		return
	if ovx * ovx + ovy * ovy > 0x9000000:
		if a3.z() > 0xC:
			w.checking.fall_down(a2, a3)
		return
	if a2.locked():
		return
	a2.flags |= SimObject.PF_ALOCK
	a2.set_spa(SPA_HIT_BY_PUCK)

## Ricochet: the pixel offset goes into the velocity high bytes; low bytes stay.
static func _set_vel_high_bytes(a3: SimObject, off: Vector2i) -> void:
	a3.vel = Vector2i(HockeyWorld.s16(((off.x & 0xFF) << 8) | (a3.vel.x & 0xFF)),
			HockeyWorld.s16(((off.y & 0xFF) << 8) | (a3.vel.y & 0xFF)))

## puckgoalie (L50818): cover or ricochet. The 94 save-rating tables are computed and
## discarded in retail, so they are left out (spec quirk).
func puckgoalie(a2: SimObject, a3: SimObject) -> void:
	if w.gmode & HockeyWorld.GM_HL:
		return
	w.chk_shot_stat()
	a2touchpuck(a2)
	if a3.vel.y > 0x3000 or a3.vel.y <= -0x3000:
		w.song.emit(0xB if not a2.away() else 0xD)
	w.sound.emit(0x24)
	var cover := false
	if w.puckc >= 0:
		var a0 := w.objects[w.puckc]
		w.puckc = -1
		a0.nopuck_hi = 0x14
		w.lastplayer = a0.index
		w.sflags &= ~(HockeyWorld.SF_PASSDIR | HockeyWorld.SF_SHOTDIR)
	elif a2.spa != SPA_GOALIE_DIVE:
		var lim := ((w.rng.range_((2 + a2.shotspd) << 9) + 0xC00) * 2) & 0xFFFF
		if lim >= 0x8000:
			lim = 0x7FFF
		if not a2.anim_busy() and absi(a3.x()) <= 0x2C and absi(a3.y()) <= 0x10E and absi(a3.y()) > 0xD2:
			lim >>= 2
		var vx := a3.vel.x
		var vy := a3.vel.y
		if not (vx > lim or vy > lim or vx < -lim or vy < -lim) and a2.flags2 & SimObject.PF2_UNAV == 0:
			cover = true
	a3.zvel = 0
	if cover:
		glue(a2)
		return
	a2.nopuck_hi = 0xA
	a2.temp[3] = 4
	var off := Vector2i(a3.x() - a2.x(), a3.y() - a2.y())
	if off.y == 0:
		off = w.get_hot(a2)
	_set_vel_high_bytes(a3, off)
	puckflip(a3, off.x)

## deflect (L51170): knock the puck loose in a random direction.
func deflect(a3: SimObject) -> void:
	w.puckc = -1
	a3.vel.y = w.rng.signed(0x1000)
	a3.vel.x = w.rng.signed(0x1000)
	a3.zvel = w.rng.range_(0x1000)
	puckflip(a3, a3.zvel)

# --- nets, goals, glass --------------------------------------------------------------

## checkgoal (L49633). a3 is any object in an end zone between the corners, net the
## net at that end, (d2, d3) the tested point, rad the wall radius used.
func checkgoal(a3: SimObject, net: SimObject, d2: int, d3: int, rad: Vector2i) -> void:
	if a3.z() > 0xD:
		return
	if a3.index != HockeyWorld.PUCK:
		checkgoalp(a3, net, d2, d3)
		return
	var dx := d2 - net.x()
	var xs := 0x10 + rad.x
	if dx > xs or dx < -xs:
		return
	var dy := d3 - net.y()
	var ys := 2 + rad.y
	if dy > ys or dy < -ys:
		return
	w.collflag = -1
	if (a3.old_z_fx >> 16) >= 0xD:
		a3.z_fx = (a3.old_z_fx & ~0xFFFF) | (a3.z_fx & 0xFFFF)
		a3.zvel = absi(a3.zvel)
		return
	a3.flags &= ~SimObject.PF_GOAL
	if w.puckc >= 0:
		var c := w.objects[w.puckc]
		w.puckc = -1
		c.nopuck_hi = 8
		var t := a3.y() if c.attacking_top() else -a3.y()
		if t < 0:
			a3.flags |= SimObject.PF_GOAL
	var my := HockeyWorld.s16((a3.pos_fx.y - a3.old_pos_fx.y) >> 8)
	if my == 0:
		_side_entry(a3)
		return
	var ny := 0x100 if my > 0 else -0x100
	var pen := dy + ys if my > 0 else dy - ys
	var mx := HockeyWorld.s16((a3.pos_fx.x - a3.old_pos_fx.x) >> 8)
	var back: Variant = _divs_or_null(pen * mx, my)
	if back == null:
		_side_entry(a3)
		return
	var cx: int = dx - back
	if cx < -xs or cx > xs:
		_side_entry(a3)
		return
	if signi(a3.y()) != signi(ny):
		w.wallcoll(a3, Vector2i(0, ny))
	ny = -ny
	if a3.flags & SimObject.PF_GOAL:
		w.wallcoll(a3, Vector2i(0, ny))
	if a3.z() == 0xD or cx > xs - 1 or cx < -(xs - 1):
		_post(a3)
		return
	goal(a3)

## A puck entering from the side bounces off the side of the net.
func _side_entry(a3: SimObject) -> void:
	if a3.x() - a3.old_pos().x < 0:
		w.wallcoll(a3, Vector2i(-0x100, 0))
	else:
		w.wallcoll(a3, Vector2i(0x100, 0))

## deflectsf: post or crossbar.
func _post(a3: SimObject) -> void:
	w.chk_shot_stat()
	var snd := 0x25
	if w.gmode & HockeyWorld.GM_CLOCK == 0:
		snd = 8
		w.crowd_level += 0x12C
		w.crowd_excite += 0x28
	w.sound.emit(snd)
	var r := w.rng.range_(0x1000)
	a3.vel.y = r if a3.y() < 0 else -r
	a3.vel.x = w.rng.signed(0x1000)
	a3.zvel = w.rng.signed(0x1000)
	puckflip(a3, a3.zvel)

## The goal (L49758).
func goal(a3: SimObject) -> void:
	if w.ba_ps_flags & HockeyWorld.BA_LIVE:
		var want_top: bool
		if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT == 0:
			want_top = w.objects[w.ba_sktr].attacking_top()
		else:
			want_top = w.shootout_side == 0
		if want_top and a3.y() < 0:
			return
		if not want_top and a3.y() >= 0:
			return
		w.f_c2f4 |= HockeyWorld.C2F4_PS_GOAL
		w.shootout_goals[1 if w.shootout_side != 0 else 0] += 1
		w.f_c2fe |= HockeyWorld.C2FE_PS_GOAL
		w.ps_attempt_end()
	elif w.gmode & HockeyWorld.GM_CLOCK:
		return
	w.f_c2f4 |= HockeyWorld.C2F4_GOAL
	w.f_c2fe &= ~HockeyWorld.C2FE_GOAL_TOGGLE
	w.chk_shot_stat()
	w.sound.emit(0)
	w.sflags |= HockeyWorld.SF_SLOCK
	w.crowd_level += 0x1F4
	# Scoring team: home scores in the top net unless gmdir flips the ends.
	var scorer := 0
	if a3.y() < 0:
		scorer = 1
	if w.gmode & HockeyWorld.GM_DIR:
		scorer = 1 - scorer
	var a2 := w.stats[scorer]
	var a1 := w.stats[1 - scorer]
	a2.goals += 1
	if w.f_c2f4 & HockeyWorld.C2F4_PS_GOAL and w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT == 0:
		a2.penalty_shot_goals += 1
	if w.f_c2fa & HockeyWorld.C2FA_BREAKAWAY:
		w.f_c2fa &= ~HockeyWorld.C2FA_BREAKAWAY
		a2.breakaway_goals += 1
	if w.sflags2 & HockeyWorld.SF2_PWRPLAY:
		var pp_away := w.sflags2 & HockeyWorld.SF2_PWRTM != 0
		if (not pp_away and scorer == 1) or (pp_away and scorer == 0):
			a2.shorthanded_goals += 1
	a2.period_goals[mini(w.gsp, 3)] += 1
	if w.f_c2fe & HockeyWorld.C2FE_ONETIMER_TOUCH:
		w.f_c2fe &= ~HockeyWorld.C2FE_ONETIMER_TOUCH
		a2.onetimer_goals += 1
	if scorer == 0:
		w.goal_song.emit()
	# Scoring summary record.
	var rec := {
		"time": (w.gsp << 14) + (w.period_seconds - w.clock_seconds()),
		"strength": 2 + a2.on_ice - a1.on_ice,
		"away": scorer == 1,
		"scorer": a2.toucher,
		"assist1": -1,
		"assist2": -1,
	}
	w.crowd_excite += 0x1E
	if scorer == 1:
		w.crowd_excite -= 0x14
	if TeamStats.valid_pnum(a2.toucher):
		a2.player_goals[a2.toucher] += 1
	if a2.assist1 >= 0 and a2.assist1 != a2.toucher:
		rec["assist1"] = a2.assist1
		if TeamStats.valid_pnum(a2.assist1):
			a2.player_assists[a2.assist1] += 1
		if a2.assist2 >= 0 and a2.assist2 != a2.toucher:
			rec["assist2"] = a2.assist2
			if TeamStats.valid_pnum(a2.assist2):
				a2.player_assists[a2.assist2] += 1
	if TeamStats.valid_pnum(a1.goalie_pnum) and not a1.goalie_pulled:
		a1.player_goals[a1.goalie_pnum] += 1
	if w.score_summary.size() >= 60:
		w.score_summary.pop_back()
	w.score_summary.append(rec)
	w.chk_shot_stat()
	w.pp_goal(scorer)
	w.ba_ps_flags &= ~HockeyWorld.BA_AWARDED
	w.goal_scored.emit(scorer, rec)
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT == 0:
		setass(scorer, ASS_SCORE)
	w.collflag = 0
	a3.vel = Vector2i.ZERO
	var gx := 6 if a3.x() >= 0 else -6
	var gy := 0x110 if a3.y() >= 0 else -0x110
	a3.pos_fx = Vector2i((gx << 16) | (a3.pos_fx.x & 0xFFFF), (gy << 16) | (a3.pos_fx.y & 0xFFFF))
	a3.zvel = 0x600
	a3.z_fx &= 0xFFFF
	w.puckcross[1] = -1
	w.puckcross[3] = -1
	a3.flags |= SimObject.PF_NC
	w.assreplace(a3, ASS_PUCKUNFLIP)
	w.objects[HockeyWorld.SHADOW].set_spa(SPA_GOAL_SIREN)
	w.objects[HockeyWorld.SHADOW].frame = 1
	w.add_penalty2(PEN_GOAL, w.objects[a1.first_object])

## setass (L49965): every on-ice skater of the team gets assignment id.
func setass(team: int, id: int) -> void:
	var st := w.stats[team]
	for i in 6:
		var o := w.objects[st.first_object + i]
		if o.position <= 0 or o.fighting():
			continue
		o.flags &= ~SimObject.PF_NC
		if o.flags3 & SimObject.PF3_ONETIMER:
			w.cancel_onetimer(o)
		w.assinsert(o, id)

## checkgoalp (L50000): a player against the net, as an ellipse.
func checkgoalp(a3: SimObject, net: SimObject, d2: int, d3: int) -> void:
	if a3.flags2 & SimObject.PF2_NOCOLL:
		return
	if a3.z() > 0xA or a3.index > 0xB:
		return
	var dy := d3 - net.y()
	var dx := d2 - net.x()
	var ex := HockeyWorld.s16(dx << 4)
	ex = (ex * ex) / 0x400
	if ex > 0x100:
		return
	var ey := HockeyWorld.s16(dy << 4)
	ey = (ey * ey) / 0x79
	if ((ex + ey) & 0xFFFF) > 0x100:
		return
	if _check_bump(a3, net):
		return
	var nx := net.y() - d3
	var ny := d2 - net.x()
	var r := RinkBoards.sroot(nx * nx + ny * ny) + 1
	var c := RinkBoards._div_trunc(nx << 8, r)
	var s := RinkBoards._div_trunc(ny << 8, r)
	# wallcoll(cos = c, sin = s): outward normal is (-s, c). The suppress flag keeps
	# wallcoll from setting the wall bit.
	w.f_c2f8 |= HockeyWorld.C2F8_NET
	w.wallcoll(a3, Vector2i(-s, c))
	w.f_c2f8 &= ~HockeyWorld.C2F8_NET

## CheckBump (L50048): a fast player knocks the net off (1 in 32 contact loops).
func _check_bump(a3: SimObject, net: SimObject) -> bool:
	if w.hv_rng.randi() & 0x1F != 0:
		return false
	var t := w.puck().y() - net.y()
	if t > 0x28 or t < -0x28:
		return false
	if a3.vel.x >= -0x2000 and a3.vel.x <= 0x2000 and a3.vel.y >= -0x2000 and a3.vel.y <= 0x2000:
		return false
	net.vel = Vector2i(a3.vel.x >> 2, a3.vel.y >> 2)
	a3.vel = Vector2i.ZERO
	w.sflags |= HockeyWorld.SF_SLOCK
	if w.gmode & HockeyWorld.GM_CLOCK == 0:
		w.add_penalty2(PEN_NET_OFF, a3)
	return true

## wallcollb2 (L50092) for the puck: over the glass, the goal light, or a normal bounce.
## Returns true when the puck left the rink (no bounce).
func over_glass(a3: SimObject, n: Vector2i) -> bool:
	var z := a3.z()
	if z <= 0x1D and (z & 0xFFFF) <= 0x12 and z >= 0:
		return false
	if z <= 0x1D and a3.y() >= 0x118:
		if a3.x() < 0xD or a3.x() > 0xF or HockeyWorld.s16(a3.vel.y) < 0xFA0:
			return false
		# The goal light above the top glass.
		a3.vel.y >>= 1
		w.objects[HockeyWorld.SHADOW].set_spa(SPA_GOAL_LIGHT)
		w.sound.emit(0xE)
		w.crowd_level += 0x258
		w.crowd_excite += 0xF
	w.sflags |= HockeyWorld.SF_SLOCK
	a3.flags |= SimObject.PF_NC
	if a3.y() < 0:
		a3.attribute |= 0x8000
	w.objects[HockeyWorld.SHADOW].frame = 0
	if w.gmode & HockeyWorld.GM_CLOCK == 0:
		w.add_penalty2(PEN_STALLED, w.objects[w.ltplayer])
	return true
