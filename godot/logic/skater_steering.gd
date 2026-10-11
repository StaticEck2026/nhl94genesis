class_name SkaterSteering
extends RefCounted
## Facing, turning, backwards skating and hockey stops for skaters.
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
enum Anim { GLIDE, GLIDE_BACK, STOP, TURN_RIGHT, TURN_LEFT, SKATE, SKATE_BACK, SKATE_INJURED, SKATE_PUCK }

## Retail SPA animation ids, for the sprite pass.
const ANIM_SPA := {
	Anim.GLIDE: 0x50C,
	Anim.GLIDE_BACK: 0xA60,
	Anim.STOP: 0x6C6,
	Anim.TURN_RIGHT: 0x694,
	Anim.TURN_LEFT: 0x662,
	Anim.SKATE: 0x5D0,
	Anim.SKATE_BACK: 0xA92,
	Anim.SKATE_INJURED: 0x11E6,
	Anim.SKATE_PUCK: 0x53E,
}

## Per-skater steering state.
class State:
	## facedir long ($54). High 16 bits are the direction 0-7.
	var facing_fx: int = 0
	## $62 bit 4 (pfrev): skating backwards.
	var reverse: bool = false
	## $63 bit 1 (pf2aip): a one-shot animation is playing. The node clears it when the
	## animation ends. Glide and skate do not replace a busy animation.
	var anim_busy: bool = false
	var anim: Anim = Anim.GLIDE
	## Set when anim changes (SetSPA restarts the animation).
	var anim_restarted: bool = false
	## Sprite attribute bit 3: drawn mirrored. Swaps the turn animation side.
	var x_flip: bool = false

	func facing() -> int:
		return facing_fx >> 16

	## Facing as an angle in radians, Godot axes (0 is screen up, clockwise positive).
	func facing_angle() -> float:
		return float(facing_fx) / float(FACING_ONE) * TAU / 8.0

## What doplayeracc reads besides the stick.
class Context:
	## Retail velocity, rvu, retail axes.
	var vel: Vector2i = Vector2i.ZERO
	## This skater carries the puck.
	var has_puck: bool = false
	## $63 bit 6: hurt in a fight.
	var injured: bool = false
	## Retail Ypos.
	var y: int = 0
	## Puck minus skater, retail axes. Y includes the high byte of puck Yvel as lookahead:
	## (pucky + (puck_yvel >> 8)) - Ypos.
	var to_puck: Vector2i = Vector2i.ZERO
	## $62 bit 7: attacking the goal at the top (+Y).
	var attacking_top: bool = true

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
func steer(st: State, joy: int, ctx: Context) -> Result:
	st.anim_restarted = false
	var r := Result.new()
	var idle_anim := Anim.GLIDE_BACK if st.reverse else Anim.GLIDE
	joy &= 15
	if joy > 7:
		if joy == JOY_BRAKE and ctx.vel != Vector2i.ZERO:
			return _stop(st, ctx.vel)
		if not st.anim_busy:
			_set_anim(st, idle_anim)
		return r
	if not settings.enable_momentum:
		return _snap(st, joy, ctx)
	_update_reverse(st, joy, ctx)
	var diff := (joy - st.facing()) & 7
	var turn := _FTAB[diff]
	if turn == 0:
		return _no_turn(st, diff, ctx)
	# Turn rate falls with speed: $300 - (speed^2 >> 16), never under $180.
	var speed_hi := ((ctx.vel.x * ctx.vel.x + ctx.vel.y * ctx.vel.y) >> 16) & 0xFFFF
	var rate := maxi(settings.turn_rate_standing - speed_hi, settings.turn_rate_floor)
	var delta := roundi(rate * turn * settings.turn_rate_scale)
	if st.reverse:
		delta = -delta
	st.facing_fx = posmod(st.facing_fx + delta, FACING_WRAP)
	var anim := idle_anim
	if speed_hi > 0x14:
		var left := turn < 0
		if st.x_flip:
			left = not left
		anim = Anim.TURN_LEFT if left else Anim.TURN_RIGHT
		st.anim_busy = true
	_set_anim(st, anim)
	# Nearly stopped (speed^2 >> 16 <= 2): turn in place, no push.
	if speed_hi > 2:
		return _accel(st)
	return r

## Stick lines up with facing (diff 0) or points straight back (diff 4). noturn0.
func _no_turn(st: State, diff: int, ctx: Context) -> Result:
	var window := 2
	var back := diff == 4
	if st.reverse:
		window += 4
		back = not back
	if not back:
		var anim := Anim.SKATE_BACK
		if not st.reverse:
			anim = Anim.SKATE_INJURED if ctx.injured else Anim.SKATE
			if ctx.has_puck:
				anim = Anim.SKATE_PUCK
		if not st.anim_busy:
			_set_anim(st, anim)
		return _accel(st)
	# Stick opposite the body. Moving along the body: hockey stop. Otherwise snap 45 degrees.
	var vd := vtoa(ctx.vel)
	if vd != JOY_NONE and ((vd - st.facing() + window) & 7) < 4:
		return _stop(st, ctx.vel)
	var step := -FACING_ONE if st.x_flip else FACING_ONE
	st.facing_fx = posmod(st.facing_fx + step, FACING_WRAP)
	_set_anim(st, Anim.GLIDE_BACK if st.reverse else Anim.GLIDE)
	return Result.new()

## noturn: push along facing, or opposite facing when skating backwards.
func _accel(st: State) -> Result:
	var r := Result.new()
	r.action = Action.ACCEL
	r.accel_dir = st.facing() ^ (4 if st.reverse else 0)
	return r

## dostop animation choice. The caller applies stopna.
func _stop(st: State, vel: Vector2i) -> Result:
	if SkaterMotion.wants_stop_anim(vel):
		if st.reverse:
			_set_anim(st, Anim.GLIDE)
		else:
			st.anim_busy = true
			_set_anim(st, Anim.STOP)
	var r := Result.new()
	r.action = Action.STOP
	return r

## Backwards skating. Only without the puck, only in the own half, only with the stick
## pointing back and the puck ahead. Once on, it holds while the stick stays within 45
## degrees of straight back and the puck stays in the front 225 degrees.
func _update_reverse(st: State, joy: int, ctx: Context) -> void:
	if ctx.has_puck:
		st.reverse = false
		return
	var p := ctx.to_puck
	var y := ctx.y
	var d := joy
	if not ctx.attacking_top:
		p = -p
		y = -y
		d ^= 4
	if not st.reverse:
		if y >= 0 or d != 4 or ((vtoa(p) + 1) & 7) > 2:
			st.reverse = false
			return
	else:
		if ((d - 3) & 7) > 2 or ((vtoa(p) + 2) & 7) > 4:
			st.reverse = false
			return
		return
	# Turning it on needs the skater still, or already drifting within 45 degrees of the stick.
	if ctx.vel == Vector2i.ZERO or ((vtoa(ctx.vel) - joy + 1) & 7) <= 2:
		st.reverse = true

## enable_momentum off: face the stick at once and push that way.
func _snap(st: State, joy: int, ctx: Context) -> Result:
	st.reverse = false
	st.facing_fx = joy << 16
	if not st.anim_busy:
		_set_anim(st, Anim.SKATE_PUCK if ctx.has_puck else Anim.SKATE)
	return _accel(st)

## SetSPA (L43319): restart only when the animation changes.
static func _set_anim(st: State, anim: Anim) -> void:
	if st.anim == anim:
		return
	st.anim = anim
	st.anim_restarted = true
