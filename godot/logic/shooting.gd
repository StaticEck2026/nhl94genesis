class_name Shooting
extends RefCounted
## Shooting, passing, bursts and one-timers. Port of burst, setpassmode, passmode,
## dopass (with the 94 flip pass sub_F67E4 / sub_F6778), Findhittype, passto, passtoa0,
## SetShotMode, ShotMode, prepshot, doshot, shotdiradj, shotdirmath, puckvzadj,
## PSandSOpassdir, asspassrec ($13), assshoot ($12), assonetimer ($23),
## setonetimeranim/noidea, sub_F6C44, onetimershot and sub_FEFF0.
## Spec: docs/specs/shooting_passing.md. a3 is the player, as in the asm.

const ASS_SHOOT := 0x12
const ASS_PASSREC := 0x13
const ASS_ONETIMER := 0x23

const SPA_PASS_F := 0x718
const SPA_PASS_B := 0x78A
const SPA_GOALIE_PASS := 0x366
const SPA_SHOT_F := 0x7FC
const SPA_SHOT_B := 0x92E
const SPA_BURST := 0xC5E

## shotsets (L37697): aim (x offset, height) per passdir 0..8.
const SHOTSETS: Array[Vector2i] = [
	Vector2i(0, 12), Vector2i(16, 12), Vector2i(16, 6), Vector2i(16, 0), Vector2i(0, 0),
	Vector2i(-16, 0), Vector2i(-16, 6), Vector2i(-16, 12), Vector2i(0, 6),
]
## passdirlist (L974252): left-right mirror of a direction.
const PASSDIRLIST: Array[int] = [0, 7, 6, 5, 4, 3, 2, 1, 8]
## Flip-pass targets by direction (ROM $F68DE, $F68FE, $F691E).
const FLIP_DUMP: Array[Vector2i] = [Vector2i(116, 194), Vector2i(116, 194), Vector2i(116, 194), Vector2i(116, 194),
	Vector2i(-116, 194), Vector2i(-116, 194), Vector2i(-116, 194), Vector2i(-116, 194)]
const FLIP_ZONE: Array[Vector2i] = [Vector2i(-5, 171), Vector2i(-5, 171), Vector2i(-5, 171), Vector2i(-5, 171),
	Vector2i(-5, 171), Vector2i(-5, 171), Vector2i(-5, 171), Vector2i(-5, 171)]
const FLIP_GOALIE: Array[Vector2i] = [Vector2i(-5, -9), Vector2i(50, -9), Vector2i(50, -9), Vector2i(50, -9),
	Vector2i(-5, -9), Vector2i(-50, -9), Vector2i(-50, -9), Vector2i(-50, -9)]

## word_FFBF76 one-timer state bits.
const OT_SHOT_DONE := 1 << 0
const OT_HOLDING := 1 << 1
const OT_SWING := 1 << 2

var w: HockeyWorld

func _init(world: HockeyWorld) -> void:
	w = world

## dirtab entry, with entry 8 = (0, 0).
static func _dirtab(d: int) -> Vector2i:
	if d < 0 or d > 7:
		return Vector2i.ZERO
	return SkaterMotion.DIRTAB[d]

## divs.w: quotient word; on overflow the destination keeps the dividend (low word used).
static func _divs(a: int, b: int) -> int:
	if b == 0:
		return HockeyWorld.s16(a)
	var q := absi(a) / absi(b)
	if (a >= 0) != (b >= 0):
		q = -q
	if q > 0x7FFF or q < -0x8000:
		return HockeyWorld.s16(a)
	return q

## divu.w: unsigned quotient word; on overflow the low word of the dividend.
static func _divu(a: int, b: int) -> int:
	a &= 0xFFFFFFFF
	b &= 0xFFFF
	if b == 0:
		return a & 0xFFFF
	var q := a / b
	if q > 0xFFFF:
		return a & 0xFFFF
	return q

# --- burst ----------------------------------------------------------------------------

## burst (L36830): speed burst along facing; also the CPU body-check charge.
func burst(a3: SimObject) -> void:
	var e := w.energy_raw(a3)
	if w.opt_line_on:
		e = maxi(e - 0xCC, 0)
		w.set_energy(a3, e)
		if w.no_fatigue:
			e = 0x1000
	var k := (e & 0xFFFF) >> 7
	var d := _dirtab(a3.facing())
	a3.vel = Vector2i(HockeyWorld.s16(a3.vel.x + d.x * k), HockeyWorld.s16(a3.vel.y + d.y * k))
	a3.flags |= SimObject.PF_ALOCK
	a3.set_spa(SPA_BURST)

# --- passing --------------------------------------------------------------------------

## Penalty-shot gate shared by setpassmode and SetShotMode. False when the one PS
## attempt was already used.
func _ps_gate() -> bool:
	if w.ba_ps_flags & HockeyWorld.BA_LIVE:
		w.f_c2fa &= ~(1 << 2)
		if w.ba_ps_flags & HockeyWorld.BA_STARTED:
			return false
		w.ba_ps_flags |= HockeyWorld.BA_STARTED
		w.f_c2fa &= ~(1 << 5)
		w.ps_timer = 0x64
	return true

## setpassmode (L36893).
func setpassmode(a3: SimObject) -> void:
	w.passdir = a3.facing() & 7
	if not _ps_gate():
		return
	w.sflags |= HockeyWorld.SF_PASSDIR

## passmode (L36913): fire on B release, a flip request, or a held direction.
func passmode(a3: SimObject, d0: int, d2: int) -> void:
	if d2 & PadState.B or w.f_c2f6 & HockeyWorld.C2F6_FLIP:
		dopass(a3)
		return
	if d0 & 8:
		return
	w.passdir = d0 & 7
	dopass(a3)

## dopass (L36924).
func dopass(a3: SimObject) -> void:
	var p := w.puck()
	w.sflags &= ~HockeyWorld.SF_PASSDIR
	w.puckc = -1
	a3.nopuck_hi = 0x10
	w.lastplayer = a3.index
	var goalie := a3.position == SimObject.POS_GOALIE
	if w.f_c2f6 & HockeyWorld.C2F6_FLIP:
		w.f_c2f6 &= ~HockeyWorld.C2F6_FLIP
		_flip_target(a3)
		w.flip_apex = 0x3A if w.f_c2f8 & HockeyWorld.C2F8_HIGH_DUMP else 0x12
		_flip_velocity()
	else:
		var d0 := 8 if goalie else (a3.passacc & 0xFF)
		var v := ((d0 << 2) >> 1) + 0xA0
		w.passspeed = v
		if a3.passacc & 1:
			w.passspeed += v >> 4
		var receiver := _find_receiver(a3)
		if receiver != null:
			passto(a3, receiver)
		else:
			var dt := _dirtab(w.passdir)
			p.vel.y = HockeyWorld.s16(_divs((dt.y * w.passspeed) << 10, 0xBB8) + a3.vel.y)
			p.vel.x = HockeyWorld.s16(_divs((dt.x * w.passspeed) << 10, 0xBB8) + a3.vel.x)
			p.zvel = w.rng.range_(0x1000)
	if goalie:
		if a3.attacking_top() and p.vel.y < 0:
			p.vel.y = -p.vel.y
		elif not a3.attacking_top() and p.vel.y >= 0:
			p.vel.y = HockeyWorld.s16(-p.vel.y)
	var ld := SkaterSteering.vtoa(p.vel)
	var anim := SPA_GOALIE_PASS
	if not goalie:
		anim = SPA_PASS_B if findhittype(a3, ld) else SPA_PASS_F
	a3.set_spa(anim)
	a3.flags |= SimObject.PF_ALOCK
	var zhi := (p.zvel >> 8) & 0xFF
	w.sound.emit(0x10 + ((((0x0C - zhi) & 0xFF) >> 2) & 3))

## _findplayer: the teammate closest to the puck within 45 degrees of passdir.
func _find_receiver(a3: SimObject) -> SimObject:
	var p := w.puck()
	var first := 6 if a3.index >= 6 else 0
	if first == 6 and w.ba_ps_flags & HockeyWorld.BA_LIVE:
		return null
	var best := 0xFFFFFFFF
	var a0: SimObject = null
	for i in 6:
		var a1 := w.objects[first + i]
		if a1 == a3 or a1.position == SimObject.POS_GOALIE or a1.flags2 & SimObject.PF2_UNAV:
			continue
		var dx := HockeyWorld.s16(a1.x() - p.x())
		var dy := HockeyWorld.s16(a1.y() - p.y())
		var dir := SkaterSteering.vtoa(Vector2i(dx, dy))
		var diff := (dir - w.passdir) & 7
		var pen_b := HockeyWorld._sbyte((diff << 5) & 0xFF) << 3
		var pen := pen_b * pen_b
		if pen > 65536:
			continue
		var score := (dx * dx + dy * dy + pen) & 0xFFFFFFFF
		if score <= best:
			best = score
			a0 = a1
	return a0

## Findhittype (L37396, decoded from ROM): true = backhand for launch direction d0.
static func findhittype(a3: SimObject, d0: int) -> bool:
	var rel := (a3.facing() - d0) & 7
	var mask := 0xF0 if a3.x_flip() else 0x1E
	return (mask >> rel) & 1 != 0

## passto (L37074): a human goalie hands his pad to the receiver.
func passto(a3: SimObject, a0: SimObject) -> void:
	if a3.joypad() and a3.position == SimObject.POS_GOALIE and not a0.joypad():
		a0.flags3 |= SimObject.PF3_BLOCK_B
		if w.cont_team[0] == w.cont_team[1]:
			w.set_c_player(0 if a3.index == w.c_player[0] else 1, a0)
		else:
			var team := 2 if a3.away() else 1
			w.set_c_player(0 if w.cont_team[0] == team else 1, a0)
	passtoa0(a3, a0)

## passtoa0 (L37114): lead pass to the receiver's stick. Integer for integer.
func passtoa0(a3: SimObject, a0: SimObject) -> void:
	var p := w.puck()
	w.stats[a3.team()].pass_attempts += 1
	w.passplayer = a0.index
	var s := HockeyWorld.s16(w.passspeed) >> 2
	w.assinsert(a0, ASS_PASSREC)
	var hot := w.get_hot(a0)
	var big_ax := HockeyWorld.s16(hot.x + a0.x() - p.x())
	var big_ay := HockeyWorld.s16(hot.y + a0.y() - p.y())
	var ax := big_ax >> 2
	var ay := big_ay >> 2
	var vx := (a0.vel.x * 0xF0) >> 16
	var vy := (a0.vel.y * 0xF0) >> 16
	var j := HockeyWorld.s16(HockeyWorld.s16(vx * ax + vy * ay) << 1)
	var k := vx * vx + vy * vy - s * s
	var a2sq := ax * ax + ay * ay
	var q := (HockeyWorld.s16(k) * HockeyWorld.s16(a2sq)) << 2
	var dd := (j * j - q) & 0xFFFFFFFF
	var r := RinkBoards.sroot(dd)
	var kd := HockeyWorld.s16(k) >> 2
	if kd == 0:
		kd = 1
	var t := _divs(HockeyWorld.s16(r - j), kd)
	if t < 0:
		t = _divs(HockeyWorld.s16(-r - j), kd)
	if t == 0:
		t = 1
	if (t & 0xFFFF) > 0x18:
		t = 0x18
	var zhi := t
	if t >= 0xC:
		zhi = 0xC
	p.zvel = HockeyWorld.s16(((zhi & 0xFF) << 8) | (p.zvel & 0xFF))
	var w8 := t * 8 - 0xA
	a0.temp[0] = ((w8 & 0xFF) << 8) | (a0.temp[0] & 0xFF)
	w8 -= 6
	p.nopuck_hi = w8 & 0xFF
	var lx := (vx * t) >> 1
	var ix := HockeyWorld.s16(lx + big_ax)
	a0.temp[2] = HockeyWorld.s16(p.x() + ix)
	var ly := (vy * t) >> 1
	var iy := HockeyWorld.s16(ly + big_ay)
	a0.temp[3] = HockeyWorld.s16(p.y() + iy)
	var den := t * 0x78
	p.vel.x = _divs((ix << 16) | ((lx >> 16) & 0xFFFF), den)
	p.vel.y = _divs((iy << 16) | ((ly >> 16) & 0xFFFF), den)

## sub_F67E4: flip-pass target.
func _flip_target(a3: SimObject) -> void:
	w.f_c2f8 &= ~HockeyWorld.C2F8_HIGH_DUMP
	var table := FLIP_GOALIE
	var zone := false
	if a3.position != SimObject.POS_GOALIE:
		var yr := a3.y() if a3.attacking_top() else -a3.y()
		w.f_c2f8 |= HockeyWorld.C2F8_HIGH_DUMP
		table = FLIP_DUMP
		if yr >= 0x58:
			table = FLIP_ZONE
			zone = true
			w.f_c2f8 &= ~HockeyWorld.C2F8_HIGH_DUMP
	var i := a3.facing()
	if not a3.attacking_top():
		i = (i + 4) & 7
	var tx: int = table[i].x
	var ty: int = table[i].y
	if zone and absi(a3.y()) >= 0x8A and absi(a3.x()) <= 0x37:
		ty = 0x103
	if not a3.attacking_top():
		tx = -tx
		ty = -ty
	tx += w.rng.range_(10)
	ty += w.rng.range_(10)
	w.flip_target = Vector2i(tx, ty)
	if a3.position != SimObject.POS_GOALIE:
		var d := tx - a3.x()
		if d >= 0:
			if d - 60 < 0:
				w.flip_target.x += 60 - d
		elif d + 60 >= 0:
			w.flip_target.x -= d + 60

## sub_F6778: flip-pass velocity (apex about flip_apex px, lands at the target).
func _flip_velocity() -> void:
	var p := w.puck()
	var vz := RinkBoards.sroot(((0xC * w.flip_apex) & 0xFFFF) << 16)
	p.zvel = HockeyWorld.s16(vz)
	var t := (vz & 0xFFFF) / 3
	if t == 0:
		t = 1
	p.vel.x = _divs(((w.flip_target.x - p.x()) & 0xFFFF) << 16, t)
	p.vel.y = _divs(((w.flip_target.y - p.y()) & 0xFFFF) << 16, t)
	w.puck_logic.puckflip(p, p.zvel)

# --- shooting -------------------------------------------------------------------------

## SetShotMode (L37411): start the windup.
func set_shot_mode(a3: SimObject) -> void:
	if not _ps_gate():
		return
	w.passdir = 8
	w.sflags |= HockeyWorld.SF_SHOTDIR
	var gy := 0x128 if a3.attacking_top() else -0x128
	var ld := SkaterSteering.vtoa(Vector2i(-a3.x(), gy - a3.y()))
	w.passspeed = 0xF
	a3.set_spa(SPA_SHOT_B if findhittype(a3, ld) else SPA_SHOT_F)

## ShotMode (L37444): charge during the windup, aim with the pad, swing on release.
func shot_mode(a3: SimObject, d0: int, d2: int, d7: int) -> void:
	if a3.spa_num >= 0x1C:
		prepshot(a3)
		return
	if d0 & 8 == 0:
		w.passdir = d0 & 7
	if a3.spa_num >= 0x10:
		return
	w.passspeed += d7
	var forced := HockeyWorld._sbyte(a3.shotspd & 0xFF) < 0x14 and a3.spa_num > 8
	if not forced and d2 & PadState.C == 0:
		return
	a3.spa_num = 0x1C - a3.spa_num

## prepshot (L37473): the in-close top-shelf flag, then doshot.
func prepshot(a3: SimObject) -> void:
	w.f_c2f6 &= ~HockeyWorld.C2F6_TOPSHELF
	var g := w.goalie_of(1 - a3.team())
	var open_top := g == null or g.spa == PuckLogic.SPA_PAD_STACK_L or g.spa == PuckLogic.SPA_PAD_STACK_R
	if open_top and (w.passdir <= 1 or w.passdir == 7):
		var yr := w.puck().y() if a3.attacking_top() else -w.puck().y()
		if yr >= 0xD8:
			w.f_c2f6 |= HockeyWorld.C2F6_TOPSHELF
	doshot(a3)

## doshot (L37514): launch the shot.
func doshot(a3: SimObject) -> void:
	var p := w.puck()
	w.f_c2fa &= ~HockeyWorld.C2FA_BREAKAWAY
	if a3.flags3 & SimObject.PF3_BREAKAWAY:
		w.f_c2fa |= HockeyWorld.C2FA_BREAKAWAY
	shotdiradj(a3)
	var snd := 5
	w.shotplayer = a3.index
	w.sflags &= ~HockeyWorld.SF_SHOTDIR
	a3.flags |= SimObject.PF_ALOCK
	var onet := a3.flags3 & SimObject.PF3_ONETIMER != 0
	if not onet and w.puckc != a3.index:
		w.sound.emit(snd)
		return
	snd = 0x18
	w.sflags2 |= HockeyWorld.SF2_SHOT
	if a3.spa == SPA_SHOT_B:
		snd = 0x14
		w.passspeed = (w.passspeed - ((w.passspeed & 0xFFFF) >> 2)) & 0xFFFF
	if onet:
		w.passspeed = 0x1F
	var k := w.puck_logic.makepde(a3, (a3.shotspd & 0xFF) >> 1) + 0x14
	var pw := (k * w.passspeed) & 0xFFFF
	w.passspeed = (pw * 0x5249) >> 16
	var v := w.passspeed
	if a3.shotspd & 1:
		v = ((v >> 4) + w.passspeed) & 0xFFFF
	var off := 3 - ((v & 0xFFFF) >> 4)
	if off < 0:
		off = 0
	snd += off
	w.puckc = -1
	a3.nopuck_hi = 0x10
	w.lastplayer = a3.index
	# Aim.
	var gy := 0x108 if a3.attacking_top() else -0x108
	var aim: Vector2i = SHOTSETS[clampi(w.passdir, 0, 8)]
	var dx := HockeyWorld.s16(aim.x - p.x())
	var dy := HockeyWorld.s16(gy - p.y())
	var z := aim.y
	var dist := RinkBoards.sroot(dx * dx + dy * dy)
	if dist == 0:
		dist = 1
	if not _perfect(a3, dist):
		var e := (w.passspeed & 0xFFFF) >> 4
		var lo := ((e & 0xFF) - ((a3.shotacc & 0xFF) >> 1) + 0x10) & 0xFF
		e = (e & 0xFF00) | lo
		e = ((e * dist) & 0xFFFF) >> 6
		if dist <= 0xFA:
			e >>= 1
		if HockeyWorld.s16(e) >= 0x88:
			e = 0x88
		dx = HockeyWorld.s16(dx + w.rng.signed(e))
		var ey := e
		if (ey & 0xFFFF) > 0x3C:
			ey = 0x3C
		var ey2 := ey
		if dy < 0:
			ey2 >>= 1
		dy = HockeyWorld.s16(dy + w.rng.signed(ey2))
		z += w.rng.range_(ey >> 1)
	# Velocity.
	var m := HockeyWorld.s16(w.passspeed * 0x44)
	p.vel.x = _divs(m * dx, dist)
	p.vel.y = _divs(m * dy, dist)
	if a3.attacking_top():
		if p.vel.y < 0:
			p.vel.y = 0x3810
	elif p.vel.y >= 0:
		p.vel.y = HockeyWorld.s16(0xC7F0)
	# Elevation (z == 0 leaves Zvel as it was).
	if z != 0:
		var a := ((z * w.passspeed) & 0xFFFF) * 0x44
		a = _divu(a, dist)
		var b := _divu(dist * 0xB33, w.passspeed)
		var vz := (a + b) & 0xFFFF
		if vz > 0x1800:
			vz = 0x1800
		p.zvel = vz
	var top_shelf := w.f_c2f6 & HockeyWorld.C2F6_TOPSHELF != 0
	w.f_c2f6 &= ~HockeyWorld.C2F6_TOPSHELF
	if top_shelf and not onet:
		puckvzadj()
	w.sound.emit(snd)

## The perfect-shot test in doshot.
func _perfect(a3: SimObject, dist: int) -> bool:
	if w.gmode & HockeyWorld.GM_HL:
		return true
	if dist > 0xC8:
		return false
	if w.stats[a3.team()].goalie_pulled or w.stats[a3.team()].goalie_pnum < 0:
		# ReadGoaliePulled reads the shooter's own team (quirk).
		return true
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		return true
	var r := w.rng.range_((0x10 + a3.shotacc) & 0xFF)
	return r > 0xE

## shotdiradj (L37721): CPU shooters and every one-timer aim away from the goalie.
func shotdiradj(a3: SimObject) -> void:
	if a3.flags3 & SimObject.PF3_ONETIMER == 0 and a3.joypad():
		return
	var g := w.goalie_of(1 - a3.team())
	if g == null:
		w.passdir = 8
	else:
		var p := w.puck()
		var gx := HockeyWorld._sbyte((g.vel.x >> 8) & 0xFF) >> 1
		var dx := HockeyWorld.s16(gx + g.x() - p.x())
		var gyv := HockeyWorld._sbyte((g.vel.y >> 8) & 0xFF) >> 1
		var dy := HockeyWorld.s16(gyv + g.y() - p.y())
		var gd := RinkBoards.sroot(dx * dx + dy * dy + 1)
		var gl := 0x108 if a3.attacking_top() else -0x108
		var s := HockeyWorld.s16(shotdirmath(dx, dy, gd, 0x12, gl) + shotdirmath(dx, dy, gd, -0x12, gl))
		if s > 0x2C or s < -0x2C:
			w.passdir = 0
		else:
			if a3.attacking_top():
				s = -s
			w.passdir = 2 if s >= 0 else 6
	if w.ba_ps_flags & HockeyWorld.BA_LIVE or w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		var d := clampi(w.ps_script_dir, 0, 8)
		w.passdir = d if a3.attacking_top() else PASSDIRLIST[d]

## shotdirmath (L37806): signed distance of a post from the puck-goalie line.
func shotdirmath(dx: int, dy: int, gd: int, post_x: int, gl: int) -> int:
	var p := w.puck()
	var px := HockeyWorld.s16(post_x - p.x())
	var py := HockeyWorld.s16(gl - p.y())
	return _divs(dx * py - dy * px, gd)

## puckvzadj (L958869): float an in-close shot to about 10 px at the goal line.
func puckvzadj() -> void:
	var p := w.puck()
	var dist := absi(absi(p.y()) - 0x108)
	if p.vel.y == 0:
		return
	var v := absi(p.vel.y)
	var c := 17
	var t := _divu(dist << 16, v) & 0xFFFF
	t = _divu(t, c) & 0xFFFF
	if t == 0:
		t = 1
	var a := _divu(0xA0000, (t * c) & 0xFFFF)
	var b := 3 * c * t
	if b >= 0x7FFF:
		b = 0x7FFF
	var vz := (a + b) & 0xFFFF
	if vz >= 0x8000:
		vz = 0x7FFF
	p.zvel = vz

# --- assignments ----------------------------------------------------------------------

## asspassrec ($13): glide to the pass; the CPU may one-time it.
func asspassrec(a3: SimObject, d7: int) -> void:
	if a3.locked():
		return
	if w.gmode & HockeyWorld.GM_CLOCK:
		w.assnothing(a3, d7)
		return
	if a3.joypad():
		w.assexit(a3)
		return
	if a3.flags & SimObject.PF_NA:
		a3.flags &= ~SimObject.PF_NA
		a3.flags |= SimObject.PF_DOFF
		a3.temp[1] = 8
		a3.temp[3] = -2
	if w.puckc < 0:
		a3.temp[3] = HockeyWorld.s16(a3.temp[3] + 1)
		if a3.temp[3] <= 0 and _wants_onetimer(a3):
			w.inputjoy = -1
			w.assreplace(a3, ASS_ONETIMER)
			return
		var hi := (((a3.temp[0] >> 8) & 0xFF) - d7) & 0xFF
		a3.temp[0] = (hi << 8) | (a3.temp[0] & 0xFF)
		if hi < 0x80:
			return
	a3.flags &= ~SimObject.PF_DOFF
	w.assexit(a3)

## asspassrec step 7: the CPU one-timer decision.
func _wants_onetimer(a3: SimObject) -> bool:
	if w.onetimerplayer >= 0 or a3.position == SimObject.POS_GOALIE:
		return false
	a3.temp[3] = 0
	var team := 2 if a3.away() else 1
	if w.cont_team[0] == team or w.cont_team[1] == team:
		return false
	if not onetimer_gate(a3):
		return false
	var yr := a3.y() if a3.attacking_top() else -a3.y()
	if yr >= 0x58 and yr <= 0x108:
		return true
	return w.rng.range_(8) == 0

## assshoot ($12): the CPU winds up for temp2 vblanks, then releases.
func assshoot(a3: SimObject, d7: int) -> void:
	if a3.locked():
		return
	if a3.flags & SimObject.PF_NA:
		a3.flags &= ~SimObject.PF_NA
		set_shot_mode(a3)
		return
	if w.sflags & HockeyWorld.SF_SHOTDIR == 0:
		w.assexit(a3)
		return
	var d2 := 0
	a3.temp[1] = HockeyWorld.s16(a3.temp[1] - d7)
	if a3.temp[1] < 0:
		d2 = PadState.C
	shot_mode(a3, a3.assnum, d2, d7)

## sub_F6C44: one-timer gate, the puck in the player's attacking half.
func onetimer_gate(a3: SimObject) -> bool:
	var yr := w.puck().y() if a3.attacking_top() else -w.puck().y()
	return yr >= 0

## setonetimeranim (L959316) with noidea: forehand or backhand one-timer.
func onetimer_anim(a3: SimObject) -> int:
	var gy := 0x108 if a3.attacking_top() else -0x108
	var dir := SkaterSteering.vtoa(Vector2i(-a3.x(), gy - a3.y()))
	var rel := (a3.facing() + ((8 - dir) & 7)) & 7
	var forehand: bool
	if rel <= 4:
		forehand = a3.x_flip()
	else:
		forehand = not a3.x_flip()
	return SPA_SHOT_F if forehand else SPA_SHOT_B

## assonetimer ($23): wind up so the swing meets the puck; abort if it is caught or
## goes away; clean up after the shot.
func assonetimer(a3: SimObject, d7: int) -> void:
	var p := w.puck()
	if a3.flags & SimObject.PF_NA:
		a3.flags &= ~SimObject.PF_NA
		var was_set := a3.flags3 & SimObject.PF3_ONETIMER != 0
		a3.flags3 |= SimObject.PF3_ONETIMER
		if not was_set:
			w.f_c2fe &= ~(1 << 5)
			w.onetimer_state = 0
			w.passplayer = -1
			w.onetimerplayer = a3.index
			if not a3.joypad() and w.inputjoy >= 0:
				w.set_c_player(0 if w.inputjoy == 0 else 1, a3)
			var anim := onetimer_anim(a3)
			a3.spa_num = 0
			a3.set_spa(anim)
			a3.flags |= SimObject.PF_ALOCK
			a3.flags2 |= SimObject.PF2_AIP
			return
	if w.onetimer_state & OT_SHOT_DONE == 0 and _puck_going_away(a3, p):
		_abort_onetimer(a3)
		return
	if w.puckc >= 0:
		_abort_onetimer(a3)
		return
	if w.gmode & HockeyWorld.GM_CLOCK:
		end_onetimer(a3)
		return
	var st := w.onetimer_state
	if a3.spa_num < 0x10 and st & OT_SWING == 0:
		var ax := absi(a3.x() - p.x())
		var ay := absi(a3.y() - p.y())
		var d := ay
		var v := p.vel.y
		if p.vel.x != 0 and ay <= ax:
			d = ax
			v = p.vel.x
		v = absi(v)
		if v == 0:
			v = 1
		var t := _divu(_divu(d << 16, v) & 0xFFFF, 17) & 0xFFFF
		var win := (6 - (a3.spa_num >> 2)) * 4
		if t <= win:
			a3.spa_num = 0x18 - a3.spa_num
			_finish_check(a3)
			return
	else:
		w.onetimer_state |= OT_SWING
		if w.onetimer_state & OT_HOLDING == 0 and a3.spa_num == 0x18:
			a3.spa_cnt += 0x30
			w.onetimer_state |= OT_HOLDING
	st = w.onetimer_state
	if st & OT_HOLDING and a3.spa_num > 0x18 and st & OT_SHOT_DONE == 0:
		end_onetimer(a3)
		return
	if st & OT_SHOT_DONE and a3.spa_num == 0x18 and a3.spa_cnt > 1:
		a3.spa_cnt = 1
	_finish_check(a3)

func _finish_check(a3: SimObject) -> void:
	if not a3.anim_busy():
		end_onetimer(a3)
		return
	if w.onetimer_state & OT_SHOT_DONE:
		a3.flags &= ~SimObject.PF_ALOCK

## assonetimer step 2: true when the puck is far and moving away on an axis.
static func _puck_going_away(a3: SimObject, p: SimObject) -> bool:
	var dx := p.x() - a3.x()
	if dx > 0x3C or dx <= -0x3C:
		if (dx ^ p.vel.x) >= 0:
			return true
	var dy := p.y() - a3.y()
	if dy > 0x3C or dy <= -0x3C:
		if (dy ^ p.vel.y) >= 0:
			return true
	return false

func _abort_onetimer(a3: SimObject) -> void:
	w.f_c2fe &= ~HockeyWorld.C2FE_ONETIMER_TOUCH
	end_onetimer(a3)

## onetimershot (L959386): the puck reached a one-timer's stick.
func onetimershot(a3: SimObject) -> void:
	w.passdir = 4
	doshot(a3)
	var st := w.stats[a3.team()]
	st.assist2 = st.assist1
	st.assist1 = st.toucher
	st.toucher = a3.pnum & 0xFF
	w.f_c2fe |= HockeyWorld.C2FE_ONETIMER_TOUCH
	w.crowd_level += 0x96
	w.crowd_excite += 0xA
	st.onetimer_attempts += 1
	w.onetimer_state |= OT_SHOT_DONE
	a3.flags2 |= SimObject.PF2_AIP
	w.f_c2f8 |= HockeyWorld.C2F8_ONETIMER_SHOT

## sub_FEFF0: end a one-timer.
func end_onetimer(a3: SimObject) -> void:
	a3.flags3 &= ~SimObject.PF3_ONETIMER
	a3.flags &= ~SimObject.PF_ALOCK
	a3.flags2 &= ~SimObject.PF2_AIP
	w.onetimer_state = 0
	w.onetimerplayer = -1
	a3.set_spa(Spa.GLIDE)
	if a3.position >= 0:
		w.setplass(a3)
	else:
		w.assexit(a3)
	a3.spa_num = 0
	a3.spa_cnt = -1
