class_name SkaterSteering
extends RefCounted
## Facing, turning, backwards skating and hockey stops for skaters. Works on a SimObject:
## facedir ($54), pfrev ($62 bit 4), pf2aip ($63 bit 1), SPA ($58) and the sprite x flip.
##
## Port of doplayeracc (L43331), noturn0 / noturn (L43644-43704), vtoa (L43222) and the
## animation choice in dostop (L43876). Goalies go to goalieacc (L43477), not ported yet.
##
## Facing is the retail facedir long ($54): 16.16 fixed point over 8 directions, so
## 1 << 16 is 45 degrees. A skater turns facing toward the stick a little each loop and
## accelerates along facing, not along the stick. That lag is the momentum.
## Directions use dirtab order: 0 is up the ice (retail +Y), then clockwise.

## Stick input values above the 8 directions.
const JOY_NONE := 8
## Retail 9. Stops a moving skater (dostop), otherwise glides.
const JOY_BRAKE := 9

const FACING_ONE := 1 << 16
const FACING_WRAP := 8 << 16

## Turn sign per (stick - facing) & 7. 0 and 4 do not turn (doplayeracc _ftab).
const _FTAB: Array[int] = [0, 16, 16, 16, 0, -16, -16, -16]
## vtoa lookup (L43256).
const _DT: Array[int] = [1, 7, 3, 5, 0, 0, 4, 4, 2, 6, 2, 6, 1, 7, 3, 5]

enum Action { NONE, ACCEL, STOP }

## What doplayeracc reads besides the stick and the skater's own struct.
class Context:
	## This skater carries the puck (puckc == SCnum).
	var has_puck: bool = false
	## Puck minus skater, retail axes. Y includes the high byte of puck Yvel as lookahead:
	## (pucky + (puck_yvel >> 8)) - Ypos.
	var to_puck: Vector2i = Vector2i.ZERO

## doplayeracc output.
class Result:
	var action: Action = Action.NONE
	## Retail direction 0-7 for playeracc when action is ACCEL.
	var accel_dir: int = -1
	## dostop asked for the stop. The caller runs SkaterMotion.apply_stop.
	func stopping() -> bool:
		return action == Action.STOP

var settings: SimSettings

func _init(p_settings: SimSettings = null) -> void:
	settings = p_settings if p_settings != null else SimSettings.new()

## vtoa: vector to retail direction 0-7, or JOY_NONE for a zero vector.
## A component counts when it is at least half the other one.
static func vtoa(v: Vector2i) -> int:
	if v == Vector2i.ZERO:
		return JOY_NONE
	var idx := 0
	var ax := absi(v.x)
	var ay := absi(v.y)
	if v.x < 0:
		idx |= 1
	if v.y < 0:
		idx |= 2
	if ax <= ay * 2:
		idx |= 4
	if ay <= ax * 2:
		idx |= 8
	return _DT[idx]

## One doplayeracc call for a skater. joy is 0-7, JOY_NONE or JOY_BRAKE.
func steer(o: SimObject, joy: int, ctx: Context) -> Result:
	var r := Result.new()
	var idle_anim := Spa.GLIDE_BACK if o.reverse() else Spa.GLIDE
	joy &= 15
	if joy > 7:
		if joy == JOY_BRAKE and o.vel != Vector2i.ZERO:
			return _stop(o)
		if not o.anim_busy():
			o.set_spa(idle_anim)
		return r
	if not settings.enable_momentum:
		return _snap(o, joy, ctx)
	_update_reverse(o, joy, ctx)
	var diff := (joy - o.facing()) & 7
	var turn := _FTAB[diff]
	if turn == 0:
		return _no_turn(o, diff, ctx)
	# Turn rate falls with speed: $300 - (speed^2 >> 16), never under $180.
	var speed_hi := ((o.vel.x * o.vel.x + o.vel.y * o.vel.y) >> 16) & 0xFFFF
	var rate := maxi(settings.turn_rate_standing - speed_hi, settings.turn_rate_floor)
	var delta := roundi(rate * turn * settings.turn_rate_scale)
	if o.reverse():
		delta = -delta
	o.facing_fx = posmod(o.facing_fx + delta, FACING_WRAP)
	var anim := idle_anim
	if speed_hi > 0x14:
		var left := turn < 0
		if o.x_flip():
			left = not left
		anim = Spa.TURN_LEFT if left else Spa.TURN_RIGHT
		o.set_flag2(SimObject.PF2_AIP, true)
	o.set_spa(anim)
	# Nearly stopped (speed^2 >> 16 <= 2): turn in place, no push.
	if speed_hi > 2:
		return _accel(o)
	return r

## Stick lines up with facing (diff 0) or points straight back (diff 4). noturn0.
func _no_turn(o: SimObject, diff: int, ctx: Context) -> Result:
	var window := 2
	var back := diff == 4
	if o.reverse():
		window += 4
		back = not back
	if not back:
		var anim := Spa.SKATE_BACK
		if not o.reverse():
			anim = Spa.SKATE_INJURED if o.flags2 & SimObject.PF2_PEN else Spa.SKATE
			if ctx.has_puck:
				anim = Spa.SKATE_PUCK
		if not o.anim_busy():
			o.set_spa(anim)
		return _accel(o)
	# Stick opposite the body. Moving along the body: hockey stop. Otherwise snap 45 degrees.
	var vd := vtoa(o.vel)
	if vd != JOY_NONE and ((vd - o.facing() + window) & 7) < 4:
		return _stop(o)
	var step := -FACING_ONE if o.x_flip() else FACING_ONE
	o.facing_fx = posmod(o.facing_fx + step, FACING_WRAP)
	o.set_spa(Spa.GLIDE_BACK if o.reverse() else Spa.GLIDE)
	return Result.new()

## noturn: push along facing, or opposite facing when skating backwards.
func _accel(o: SimObject) -> Result:
	var r := Result.new()
	r.action = Action.ACCEL
	r.accel_dir = o.facing() ^ (4 if o.reverse() else 0)
	return r

## dostop animation choice. The caller applies stopna.
func _stop(o: SimObject) -> Result:
	if SkaterMotion.wants_stop_anim(o.vel):
		if o.reverse():
			o.set_spa(Spa.GLIDE)
		else:
			o.set_flag2(SimObject.PF2_AIP, true)
			o.set_spa(Spa.STOP)
	var r := Result.new()
	r.action = Action.STOP
	return r

## Backwards skating. Only without the puck, only in the own half, only with the stick
## pointing back and the puck ahead. Once on, it holds while the stick stays within 45
## degrees of straight back and the puck stays in the front 225 degrees.
func _update_reverse(o: SimObject, joy: int, ctx: Context) -> void:
	if ctx.has_puck:
		o.set_flag(SimObject.PF_REV, false)
		return
	var p := ctx.to_puck
	var y := o.y()
	var d := joy
	if not o.attacking_top():
		p = -p
		y = -y
		d ^= 4
	if not o.reverse():
		if y >= 0 or d != 4 or ((vtoa(p) + 1) & 7) > 2:
			return
	else:
		if ((d - 3) & 7) > 2 or ((vtoa(p) + 2) & 7) > 4:
			o.set_flag(SimObject.PF_REV, false)
		return
	# Turning it on needs the skater still, or already drifting within 45 degrees of the stick.
	if o.vel == Vector2i.ZERO or ((vtoa(o.vel) - joy + 1) & 7) <= 2:
		o.set_flag(SimObject.PF_REV, true)

## enable_momentum off: face the stick at once and push that way.
func _snap(o: SimObject, joy: int, ctx: Context) -> Result:
	o.set_flag(SimObject.PF_REV, false)
	o.facing_fx = joy << 16
	if not o.anim_busy():
		o.set_spa(Spa.SKATE_PUCK if ctx.has_puck else Spa.SKATE)
	return _accel(o)
