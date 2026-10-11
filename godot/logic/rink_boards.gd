class_name RinkBoards
extends RefCounted
## Board detection and bounce. Port of checkwallcoll2 (L49549), checkwallcoll (L959783)
## and wallcoll (L50143). Retail rink coordinates: origin at center ice, X right, Y up
## the ice, whole pixels. Velocities in rvu. Normals in 8.8 ($100 = 1.0).
##
## Retail keeps no position correction for boards. It reflects velocity and stores the
## normal (wallcos/wallsin), and playeracc then refuses to accelerate into it.
## Net and goal-mouth collision (checkgoal L49633) is not ported yet.

## Sideline X ($88).
const SIDELINE := 136
## End board Y ($12A).
const END_BOARD := 298
## Corner radius ($40). Corner centers sit this far inside both boards.
const CORNER_RADIUS := 64
## Normal length in 8.8 fixed point.
const ONE := 0x100

## Result of a board check. normal is zero when nothing was hit.
class Hit:
	## Outward board normal, 8.8. Retail stores normal.y as wallcos and -normal.x as wallsin.
	var normal: Vector2i = Vector2i.ZERO
	## Velocity after the bounce, rvu.
	var vel: Vector2i = Vector2i.ZERO
	## Set when a skater hit hard enough for SFXplayerwall (and impact >= $A).
	var hard: bool = false
	## Puck hit hard enough to pop up (puckflip, random Zvel).
	var puck_pop: bool = false

	func hit() -> bool:
		return normal != Vector2i.ZERO

## checkwallcoll2 without the goal check. pos is the object position, radius is the wall
## collision radius ($4A, $4C). Returns the outward normal in 8.8, or zero.
static func board_normal(pos: Vector2i, radius: Vector2i) -> Vector2i:
	var inner_x := SIDELINE - radius.x
	var inner_y := END_BOARD - radius.y
	var cx := inner_x - CORNER_RADIUS
	var cy := inner_y - CORNER_RADIUS
	if absi(pos.y) >= cy and absi(pos.x) > cx:
		# Corner zone. Outside the arc is a corner hit. Inside it, retail falls through to
		# the straight boards below, which only matter on the arc's outer edge.
		var center := Vector2i(cx * signi(pos.x), cy * signi(pos.y))
		var d := pos - center
		var dist_sq := d.x * d.x + d.y * d.y
		if dist_sq > CORNER_RADIUS * CORNER_RADIUS:
			var r := sroot(dist_sq)
			# cos = dy / r, sin = -dx / r, 8.8. divs truncates toward zero.
			return Vector2i(_div_trunc(d.x << 8, r), _div_trunc(d.y << 8, r))
	if pos.y >= inner_y:
		return Vector2i(0, ONE)
	if pos.y <= -inner_y:
		return Vector2i(0, -ONE)
	if pos.x >= inner_x:
		return Vector2i(ONE, 0)
	if pos.x <= -inner_x:
		return Vector2i(-ONE, 0)
	return Vector2i.ZERO

## sroot (L44215) returns an integer square root. Retail iterates Newton steps; floor of
## the real root matches it except possibly by 1 near large perfect squares.
static func sroot(v: int) -> int:
	if v <= 0:
		return 0
	return int(floor(sqrt(float(v))))

## wallcoll for a skater. vel is rvu. Returns the bounce result. Retail stores the
## normal first, so it is set even when the velocity is left alone.
static func bounce_skater(vel: Vector2i, normal: Vector2i) -> Hit:
	var h := Hit.new()
	h.vel = vel
	h.normal = normal
	var vn := _normal_speed(vel, normal)
	var vt := _tangent_speed(vel, normal)
	var n := -vn
	# Already moving away from the board faster than 1000: keep the velocity.
	if n > 1000:
		return h
	h.hard = n <= -0x1000
	n >>= 2
	if n >= -900:
		n = -1000
	h.vel = _rebuild(vt, n, normal)
	return h

## wallcoll for the puck. Quarter normal speed back, tangent loses 3/128.
static func bounce_puck(vel: Vector2i, normal: Vector2i) -> Hit:
	var h := Hit.new()
	h.vel = vel
	var vn := _normal_speed(vel, normal)
	var vt := _tangent_speed(vel, normal)
	var n := -vn
	h.normal = normal
	if n >= 0:
		return h
	n >>= 2
	h.puck_pop = n <= -0x400
	var t := vt >> 6
	vt -= t
	vt -= t >> 1
	h.vel = _rebuild(vt, n, normal)
	return h

## v1n: outward normal speed. Retail (cos * vy - sin * vx) >> 8.
static func _normal_speed(vel: Vector2i, normal: Vector2i) -> int:
	return (normal.y * vel.y + normal.x * vel.x) >> 8

## v1t: tangent speed along (cos, sin) = (normal.y, -normal.x). Retail (cos * vx + sin * vy) >> 8.
static func _tangent_speed(vel: Vector2i, normal: Vector2i) -> int:
	return (normal.y * vel.x - normal.x * vel.y) >> 8

## Retail Xvel = (cos * vt - sin * vn) >> 8, Yvel = (sin * vt + cos * vn) >> 8.
static func _rebuild(vt: int, vn: int, normal: Vector2i) -> Vector2i:
	var cos_a := normal.y
	var sin_a := -normal.x
	return Vector2i((cos_a * vt - sin_a * vn) >> 8, (sin_a * vt + cos_a * vn) >> 8)

static func _div_trunc(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

## Board outline in retail coordinates for drawing and static colliders.
static func outline(segments_per_corner: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cx := float(SIDELINE - CORNER_RADIUS)
	var cy := float(END_BOARD - CORNER_RADIUS)
	var centers := [Vector2(cx, cy), Vector2(-cx, cy), Vector2(-cx, -cy), Vector2(cx, -cy)]
	for c in 4:
		var start := float(c) * PI * 0.5
		for i in segments_per_corner + 1:
			var a := start + PI * 0.5 * float(i) / float(segments_per_corner)
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * CORNER_RADIUS)
	return pts
