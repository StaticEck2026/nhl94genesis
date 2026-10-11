class_name GoalieLogic
extends RefCounted
## Goalies: assgoaliecpu ($0E), assgoalietopuck ($0F), assgoaliectrl ($1D),
## assgoaliebreakwait ($20), goaliesave, goalieacc (the goalie branch of doplayeracc),
## sub_DB3E, sub_DB68, stopna2, and pulling the goalie (ChkGoalies, ReturnGoalies,
## CPgoalie, ReadGoaliePulled). Spec: docs/specs/goalie.md.
## temp1 high byte = decision timer; temp2 high byte = skateto countdown, low byte =
## chosen direction; temp4 = rebound dive window; temp5 = hold-puck countdown.

const ASS_GOALIE_CPU := 0x0E
const ASS_GOALIE_TOPUCK := 0x0F
const ASS_GOALIE_CTRL := 0x1D
const ASS_GOALIE_BREAKWAIT := 0x20
## The CPU goalie assignments (SimSettings.enable_goalie_tracking gates them).
const CPU_IDS: Array[int] = [ASS_GOALIE_CPU, ASS_GOALIE_TOPUCK]

const SPA_READY := 0x2
const SPA_SKATE := 0x3D8
const SPA_DIVE := 0x2F4
const SPA_GOAL_AGAINST := 0x1596      ## pfgoal 0 goalie
const SPA_GOAL_AGAINST_TOP := 0x1684  ## pfgoal 1 goalie
const SPA_GLOVE := 0x178
const SPA_REACH_GLOVE := 0x1AA
## _saveanim (L39717): blocker, glove, pad stack right/left, kick, butterfly, high
## shoulder right/left, stick right/left.
const SAVE_ANIM: Array[int] = [0x146, 0x178, 0x250, 0x2A2, 0x1EC, 0x21E, 0x148E, 0x14C0,
	0x14F2, 0x1544]
## stopna2 (L959753): per-axis brake, not scaled by d7.
const STOPNA2 := 0x7D0
## The whistle for a frozen puck or a goalie out of range (PenaltyList + 8, PenFO).
const PEN_FACEOFF := 8

var w: HockeyWorld
## TmpPuckX: the goalie's working puck X (written by each CPU goalie every call).
var tmp_puck_x: int = 0

func _init(world: HockeyWorld) -> void:
	w = world

func register(t: Dictionary) -> void:
	t[ASS_GOALIE_CPU] = func(o: SimObject, d7: int) -> void: assgoaliecpu(o, d7)
	t[ASS_GOALIE_TOPUCK] = func(o: SimObject, d7: int) -> void: assgoalietopuck(o, d7)
	t[ASS_GOALIE_CTRL] = func(o: SimObject, d7: int) -> void: assgoaliectrl(o, d7)
	t[ASS_GOALIE_BREAKWAIT] = func(o: SimObject, d7: int) -> void: assgoaliebreakwait(o, d7)

static func s16(v: int) -> int:
	return HockeyWorld.s16(v)

## Decision timer reload: aidef >> 2, one less first when the crowd record is broken.
## SimSettings.goalie_reaction_frames adds a delay on top (0 is retail).
func _reload(o: SimObject) -> int:
	var d0 := o.aidef & 0xFF
	if d0 != 0 and w.crowd_record:
		d0 -= 1
	return mini((d0 >> 2) + roundi(w.settings.goalie_reaction_frames), 0x7F)

## temp1.b -= d7; true (and reloaded) when it went negative.
func _decision_due(o: SimObject, d7: int) -> bool:
	var t := (HockeyAI._hi(o.temp[0]) - d7) & 0xFF
	o.temp[0] = HockeyAI._with_hi(o.temp[0], t)
	if t < 0x80:
		return false
	o.temp[0] = HockeyAI._with_hi(o.temp[0], _reload(o))
	return true

# --- CPU goalie ------------------------------------------------------------------------

## assgoaliecpu (L39072): the goalie brain.
func assgoaliecpu(o: SimObject, d7: int) -> void:
	if o.joypad():
		assgoaliectrl(o, d7)
		return
	_checkanim(o, d7)

## _checkanim: entered directly by assgoaliectrl when the pad goalie is off camera.
func _checkanim(o: SimObject, d7: int) -> void:
	var p := w.puck()
	tmp_puck_x = p.x()
	# B. Goal-against reaction, once per goal. The bit 1 side holds a dead sfx $1C check
	# (frame $2C4 and $2C8 at once), so it does nothing.
	if w.f_c2f4 & HockeyWorld.C2F4_GOAL and not o.anim_busy():
		if w.f_c2f4 & HockeyWorld.C2F4_REACTED == 0:
			if (p.y() ^ o.y()) >= 0 and o.x() > -20 and o.x() <= 20:
				w.f_c2f4 |= HockeyWorld.C2F4_REACTED
				w.f_c2f4 &= ~HockeyWorld.C2F4_SFX
				o.set_spa(SPA_GOAL_AGAINST_TOP if o.attacking_top() else SPA_GOAL_AGAINST)
				o.flags2 |= SimObject.PF2_AIP
	# C. Assignment setup.
	if o.locked():
		return
	if w.ai.check4bench(o):
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[0] = 0
		o.temp[1] = 8
		o.temp[3] = HockeyAI._with_hi(o.temp[3], 0xFF)
	# D. Outside the crease box: skate back (either end's box counts).
	var x := o.x()
	var y := o.y()
	var in_box := x >= -52 and x <= 52 and y >= -270 and y <= 270 and (y > 210 or y < -210)
	if not in_box:
		var tx := 4 if x >= 0 else -4
		var ty := -0xE4 if o.attacking_top() else 0xE4
		w.ai.skateto(o, tx, ty, Callable(), d7)
		return
	# E. In the box.
	if o.anim_busy():
		return
	if w.f_c2f4 & HockeyWorld.C2F4_GOAL:
		if o.frame == 0x2C5:
			_set_facing(o, 0)
		elif o.frame == 0x2C9:
			_set_facing(o, 4)
	o.set_spa(SPA_READY)
	if w.ba_ps_flags & HockeyWorld.BA_LIVE == 0 and w.gmode & HockeyWorld.GM_CLOCK:
		return
	# F. Hold-puck whistle.
	_hold_whistle(o, d7)
	# G. Decision timer.
	if not _decision_due(o, d7):
		_nodec(o, d7)
		return
	# Unreachable in practice (pfjoycon here means assgoaliectrl sent us, which needs
	# pflags3 bit 2). Kept as retail has it.
	if o.joypad() and o.flags3 & SimObject.PF3_OFFCAM == 0:
		w.assinsert(o, ASS_GOALIE_CTRL)
		return
	# H. Puck in the other half: hold the top of the crease.
	if (p.y() ^ o.y()) < 0:
		_de5(o, 0, -0xF4 if o.attacking_top() else 0xF4)
		_nodec(o, d7)
		return
	# I. Same half.
	var t4 := s16(o.temp[3] - 1)
	o.temp[3] = t4 if t4 >= 0 else -1
	if w.puckc == o.index:
		if s16(o.temp[4]) < 0:
			o.temp[4] = 0x5A
		o.temp[3] = HockeyAI._with_hi(o.temp[3], 0xFF)
		if s16(o.temp[4]) <= 0x5A and w.hv_rng.randi() & 3 == 0 and not _opponent_close(o):
			w.threat = 1
			w.ai.chk4pass(o)
	elif _rebound_dive(o):
		return
	if _de1(o):
		return
	_nodec(o, d7)

## Step 15: temp5 counts down while the goalie holds the puck; then the whistle.
func _hold_whistle(o: SimObject, d7: int) -> void:
	if s16(o.temp[4]) < 0:
		return
	if w.puckc != o.index:
		o.temp[4] = HockeyAI._with_hi(o.temp[4], 0xFF)
		return
	o.temp[4] = s16(o.temp[4] - d7)
	if o.temp[4] >= 0:
		return
	if w.ba_ps_flags & HockeyWorld.BA_LIVE:
		w.ba_ps_flags |= HockeyWorld.BA_GOALIE_HELD
	else:
		w.add_penalty2(PEN_FACEOFF, o)

## Step 21 opponent scan: any opponent (goalie included) within the box near the puck.
func _opponent_close(o: SimObject) -> bool:
	var p := w.puck()
	var first := 6 if o.index < 6 else 0
	for i in 6:
		var a := w.objects[first + i]
		if a.flags2 & SimObject.PF2_UNAV:
			continue
		var ddy := s16(p.y() - a.y())
		if ddy < -28 or ddy > 28:
			continue
		var ddx := s16(p.x() - a.x())
		if ddx > 25:
			continue
		if ddx > -25:
			return true
	return false

## Step 22: dive on a slow loose puck on the 4th decision after a rebound.
func _rebound_dive(o: SimObject) -> bool:
	if s16(o.temp[3]) != 0 or w.puckc >= 0:
		return false
	var p := w.puck()
	var dx := s16(p.x() - o.x())
	if dx < -20 or dx > 20:
		return false
	if p.y() > 0x108 or p.y() < -0x108:
		return false
	var dy := s16(p.y() - o.y())
	if dy < -30 or dy > 30:
		return false
	# Word add, signed compare: two fast components can wrap and pass.
	if s16(absi(s16(p.vel.x)) + absi(s16(p.vel.y))) > 0x1000:
		return false
	# vtoa can give 8 here (puck under the goalie); kept as retail.
	_set_facing(o, SkaterSteering.vtoa(Vector2i(dx, dy)))
	o.nopuck_hi = 8
	o.set_spa(SPA_DIVE)
	o.flags2 |= SimObject.PF2_AIP
	w.crowd_level += 0x96
	return true

## _de1: positioning target and the save decision. True when it inserted
## assgoalietopuck (nothing else runs this loop).
func _de1(o: SimObject) -> bool:
	var p := w.puck()
	var slot := 2 if o.attacking_top() else 0
	var d3 := -0x104 if o.attacking_top() else 0x104
	var x := o.x()
	var y := o.y()
	if y > 0x104 or y <= -0x104:
		var bx := 0
		if x <= 44 and x >= -44:
			bx = 0x88 if x >= 0 else -0x88
		_de5(o, bx, 0)
		return false
	if w.puckc >= 0 and w.puckc != o.index and w.puckc < 12:
		var cx := w.objects[w.puckc].x()
		tmp_puck_x = s16(cx + (s16(p.x() - cx) >> 1))
	var v := sub_db3e(o, tmp_puck_x, p.y(), d3)
	sub_db68(o, SkaterSteering.vtoa(v))
	var f := (w.gameclock & 7) * 16 + 0xA0
	if p.y() > 0xDB or p.y() <= -0xDB:
		f -= 0x40
	var px := s16(((f * s16(p.vel.x)) >> 16) + tmp_puck_x)
	var py := s16(((f * s16(p.vel.y)) >> 16) + p.y())
	var vv := sub_db3e(o, px, py, d3)
	var dd := (vv.x * vv.x + vv.y * vv.y) & 0xFFFFFFFF
	var off := vv
	if dd > 0x384:
		var n := 1 + RinkBoards.sroot(dd)
		var ry := 0x1A if w.sflags & HockeyWorld.SF_SHOTDIR else 0x12
		var rx := ry + 8
		off = Vector2i(Shooting._divs(vv.x * rx, n), Shooting._divs(vv.y * ry, n))
	var tx := off.x
	var ty := s16(off.y + d3)
	# K. Save / reaction decision.
	var cx := s16(w.puckcross[slot])
	var t := w.puckcross[slot + 1] & 0xFFFF
	var early := false
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT == 0 and w.ba_ps_flags & HockeyWorld.BA_LIVE == 0 \
			and w.sflags & HockeyWorld.SF_SHOTDIR:
		if (p.y() > 0xD0 or p.y() < -0xD0) and x >= -20 and x <= 20 and w.gameclock & 2 == 0:
			early = true
	if not early:
		if t > 0x22:
			_de5(o, tx, ty)
			return false
		if cx > 0x18 or cx < -0x18:
			if _chase_wide(o):
				w.assinsert(o, ASS_GOALIE_TOPUCK)
				return true
			_de5(o, tx, ty)
			return false
	if early or t <= 0x0C:
		if p.y() >= -0x108 and p.y() <= 0x108:
			var was := o.flags2 & SimObject.PF2_AIP
			o.flags2 |= SimObject.PF2_AIP
			if was == 0:
				goaliesave(o, slot, d3)
	tx = cx
	if p.y() > 0xFC or p.y() <= -0xFC:
		tx = 0x18 if tmp_puck_x >= 0 else -0x18
	_de5(o, tx, ty)
	return false

## Step 35: the puck will cross wide of the net; chase it when nobody else is close.
func _chase_wide(o: SimObject) -> bool:
	if w.puckc >= 0 or w.iflags & HockeyWorld.IF_OK:
		return false
	if _sl(w.stats[o.team()].nearest_sq) < 0x1324 or _sl(w.stats[1 - o.team()].nearest_sq) < 0x9C4:
		return false
	var p := w.puck()
	if not (p.y() > 0xE0 or p.y() <= -0xE0):
		return false
	if not _toward_own_end(o):
		return false
	return absi(s16(p.vel.y)) >= absi(s16(p.vel.x))

## The puck moves toward this goalie's end. vy == 0 passes for pfgoal 0 only.
func _toward_own_end(o: SimObject) -> bool:
	var vy := s16(w.puck().vel.y)
	return vy < 0 if o.attacking_top() else vy >= 0

static func _sl(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v

## _de5: steer toward the target; within 4 px counts as there.
func _de5(o: SimObject, tx: int, ty: int) -> void:
	var dx := s16(tx - HockeyWorld._sbyte((o.vel.x >> 8) & 0xFF) - o.x())
	var dy := s16(ty - HockeyWorld._sbyte((o.vel.y >> 8) & 0xFF) - o.y())
	if dx >= -4 and dx <= 4 and dy >= -4 and dy <= 4:
		dx = 0
		dy = 0
	o.temp[1] = HockeyAI._with_lo(o.temp[1], SkaterSteering.vtoa(Vector2i(dx, dy)))

## _nodec: accelerate in the chosen absolute direction, or brake.
func _nodec(o: SimObject, d7: int) -> void:
	var d2 := HockeyWorld._sbyte(o.temp[1] & 0xFF)
	if d2 <= 7:
		w.playeracc(o, d2, d7)
	else:
		o.vel = w.motion.apply_stop(o.vel)

## sub_DB3E: vector from the net point (0, d3) to a puck point.
func sub_db3e(o: SimObject, x: int, y: int, d3: int) -> Vector2i:
	if w.puckc == o.index:
		x = 0
	if y >= 0x103:
		y = 0x103
	if y <= -0x103:
		y = -0x103
	return Vector2i(x, s16(y - d3))

## sub_DB68: turn facing one step toward d0. A CPU goalie at facing 1 or 6 never turns
## into his own net (only those two facings are checked, so pfgoal 1 only blocks 6 to 5).
func sub_db68(o: SimObject, d0: int) -> void:
	var f := o.facing()
	if s16(d0 - f) == 0:
		return
	var step := 1 if (f - d0) & 4 else -1
	var n := f + step
	if not o.joypad() and (f == 1 or f == 6):
		var bad := 0x38 if o.attacking_top() else 0x83
		if bad & (1 << (n & 7)):
			n = f - step
	_set_facing(o, n & 7)

static func _set_facing(o: SimObject, d: int) -> void:
	o.facing_fx = (d << 16) | (o.facing_fx & 0xFFFF)

## goaliesave (L39598): pick and start a save from the predicted crossing. slot is the
## puckcross entry (0 top line, 2 bottom line), d3 the goal line Y. The callers set
## pf2aip first.
func goaliesave(o: SimObject, slot: int, d3: int) -> void:
	var cx := s16(w.puckcross[slot])
	var t := w.puckcross[slot + 1] & 0xFFFF
	var rel := (SkaterSteering.vtoa(Vector2i(s16(cx - o.x()), s16(d3 - o.y()))) - o.facing()) & 7
	var i := rel >> 2
	if o.attribute & SimObject.ATTR_XFLIP:
		i ^= 1
	var p := w.puck()
	var off := s16(o.x() - cx)
	if p.z() > 8 or s16(p.zvel) > 0x800:
		if off >= -16 and off <= 16:
			i += 6
	else:
		i += 4
		if t <= 8:
			if off > 16 or off <= -16:
				i += 4
		elif o.facing() == 2 or o.facing() == 6 or w.puckc < 0:
			pass
		else:
			# Pad stack: slide 6 px toward the middle.
			i = 3 if o.attacking_top() else 2
			var xv := -0x1000
			var dx := -6
			if o.x() < 0:
				xv = 0x1000
				dx = 6
				i ^= 1
			o.vel.x = xv
			o.pos_fx.x += dx << 16
			if o.handed & 1:
				i ^= 1
	var spa: int = SAVE_ANIM[i]
	if spa == SPA_GLOVE and rel & 3 != 0 and HockeyWorld._sbyte(o.glove() & 0xFF) >= 11:
		spa = SPA_REACH_GLOVE
	o.set_spa(spa)
	w.crowd_level += 0x96
	w.crowd_excite += 0xA
	o.vel = Vector2i(o.vel.x >> 2, o.vel.y >> 2)

## assgoalietopuck (L39731): chase a puck rimmed wide of the net.
func assgoalietopuck(o: SimObject, d7: int) -> void:
	if o.joypad() or w.gmode & HockeyWorld.GM_CLOCK:
		w.assexit(o)
		return
	if w.ai.check4bench(o):
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[0] = 0
	if _decision_due(o, d7):
		var ok := w.puckc < 0 and _toward_own_end(o) \
				and _sl(w.stats[o.team()].nearest_sq) >= 0xE10 \
				and _sl(w.stats[1 - o.team()].nearest_sq) >= 0x640
		if not ok:
			w.assexit(o)
			return
	w.ai.skatetopuck(o, d7)

# --- pad goalie ------------------------------------------------------------------------

## assgoaliectrl (L38963): whistles and timers for a pad goalie; the CPU logic takes over
## while he is off camera.
func assgoaliectrl(o: SimObject, d7: int) -> void:
	if not o.joypad():
		w.assexit(o)
		return
	if o.flags & SimObject.PF_NA == 0:
		if o.y() >= -0xAA and o.y() <= 0xAA and w.gmode & HockeyWorld.GM_CLOCK == 0:
			w.add_penalty2(PEN_FACEOFF, o)
		var dx := s16(o.x() - w.camera.x)
		var dy := s16(o.y() - w.camera.y)
		o.flags3 &= ~SimObject.PF3_OFFCAM
		if dx >= 0x74 or dx <= -0x74 or dy >= 0x64 or dy <= -0x64:
			o.flags3 |= SimObject.PF3_OFFCAM
			_checkanim(o, d7)
			return
	if o.locked():
		return
	if w.ai.check4bench(o):
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[0] = 0
		o.temp[1] = 8
		o.temp[3] = HockeyAI._with_hi(o.temp[3], 0xFF)
	if o.anim_busy() or w.gmode & HockeyWorld.GM_CLOCK:
		return
	_hold_whistle(o, d7)
	# The decision timer runs, but its branch is a no-op in retail.
	_decision_due(o, d7)

## goalieacc (L43477): doplayeracc for goalies. d0 is the stick (pad goalie: 0-7 or 8)
## or the skateto direction byte (CPU).
func goalieacc(o: SimObject, d0: int, d7: int) -> void:
	var x := o.x()
	var y := o.y()
	if o.joypad() and w.puckc != o.index and x >= -48 and x <= 48 \
			and ((y >= -262 and y <= -192) or (y >= 192 and y <= 262)):
		# Pad goalie in his crease: face the puck, strafe with the stick.
		var p := w.puck()
		var dx := s16(p.x() - x)
		var dy := s16(p.y() - y)
		var t := o.facing()
		if not (dx >= -16 and dx <= 16 and dy >= -16 and dy <= 16):
			t = SkaterSteering.vtoa(Vector2i(dx, dy))
		if w.f_c2f4 & HockeyWorld.C2F4_GOAL == 0:
			sub_db68(o, t)
		elif d0 != 8:
			sub_db68(o, d0)
		if o.anim_busy():
			return
		o.set_spa(SPA_READY)
		if d0 != 8:
			w.playeracc(o, d0, d7)
			return
		stopna2(o)
		w.playeracc(o, 8, d7)
		return
	if o.joypad():
		if o.flags & SimObject.PF_NC == 0 and d0 != 8:
			_turn_and_skate(o, d0, d7)
			return
		if o.flags & SimObject.PF_NC == 0:
			var yy := -y if o.attacking_top() else y
			if yy >= 0xD8 and x >= -32 and x <= 32:
				o.vel = w.motion.apply_stop(o.vel)
	else:
		d0 &= 0xF
		if d0 <= 7:
			_turn_and_skate(o, d0, d7)
			return
		if d0 == 9 and o.vel != Vector2i.ZERO:
			stopna2(o)
			return
	if not o.anim_busy():
		o.set_spa(SPA_READY)

## goalieacc _d1: turn one step toward d0, then skate along the facing.
func _turn_and_skate(o: SimObject, d0: int, d7: int) -> void:
	var f := o.facing()
	if d0 != f:
		f = (f + (1 if (f - d0) & 4 else -1)) & 7
		_set_facing(o, f)
	# Set even over a running animation (retail).
	o.set_spa(SPA_SKATE)
	w.playeracc(o, f, d7)

## stopna2: each axis moves $7D0 toward 0.
static func stopna2(o: SimObject) -> void:
	o.vel = Vector2i(_toward_zero(o.vel.x, STOPNA2), _toward_zero(o.vel.y, STOPNA2))

static func _toward_zero(v: int, d: int) -> int:
	if v < 0:
		return mini(v + d, 0)
	return maxi(v - d, 0)

## assgoaliebreakwait (L38175): park non-participants during a penalty shot / shootout.
func assgoaliebreakwait(o: SimObject, _d7: int) -> void:
	if o.locked():
		return
	if w.ba_ps_flags & HockeyWorld.BA_LIVE == 0 and w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT == 0:
		w.assexit(o)
		return
	o.vel = Vector2i.ZERO
	var top := w.ba_goalie >= 0 and w.ba_goalie < 12 and w.objects[w.ba_goalie].attacking_top()
	o.pos_fx.y = ((0x191 if top else -0x191) << 16) | (o.pos_fx.y & 0xFFFF)

# --- pulling the goalie ----------------------------------------------------------------

## ReadGoaliePulled: the team's goalie word is negative (pulled, or no goalie).
func goalie_pulled(team: int) -> bool:
	var st := w.stats[team]
	return st.goalie_pulled or st.goalie_pnum < 0

func _human_team(team: int) -> bool:
	return w.cont_team[0] == team + 1 or w.cont_team[1] == team + 1

## ChkGoalies (L41839): from periodiceevents about every 24 vblanks.
func chk_goalies() -> void:
	if w.gmode & HockeyWorld.GM_CLOCK:
		return
	for team in 2:
		var st := w.stats[team]
		if goalie_pulled(team) or w.puckc < 0:
			continue
		var has := w.puckc < 6 if team == 0 else w.puckc > 5
		if not has:
			continue
		if w.gmode & HockeyWorld.GM_PENDEL:
			# Delayed penalty: the team with the puck pulls its goalie, human or CPU.
			st.goalie_pulled = true
			w.set_personel(team)
			continue
		if _human_team(team):
			continue
		cp_goalie(team, w.puck().y())

## ReturnGoalies (L41876): at a faceoff, every pulled goalie comes back; CPU teams may
## pull again right away.
func return_goalies() -> void:
	for team in 2:
		var st := w.stats[team]
		if st.goalie_pnum < 0:
			continue
		st.goalie_pulled = false
		if _human_team(team):
			continue
		cp_goalie(team, w.foy)

## CPgoalie (L41898): pull only in the 3rd period, down by exactly two, with a minute or
## less left, and with y (puck or faceoff) in the attacking half.
func cp_goalie(team: int, d1: int) -> void:
	if w.gsp != 2:
		return
	var diff := w.stats[1 - team].goals - w.stats[team].goals
	if diff != 2:
		return
	if w.gameclock > 0x3C:
		return
	if not w.objects[w.stats[team].first_object].attacking_top():
		d1 = -d1
	if d1 < 0:
		return
	w.stats[team].goalie_pulled = true
	w.set_personel(team)
