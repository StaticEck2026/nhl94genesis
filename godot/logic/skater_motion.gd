class_name SkaterMotion
extends RefCounted
## Skater acceleration, top speed, drag and stopping.
##
## Port of playeracc (L43705), MaxSpeed (L43855), stopna (L43908) and the drag in
## updateplayers (L35496). Math stays in retail velocity units (rvu, the Xvel/Yvel
## words) with the retail integer truncation, so results match the ROM step for step.
## Nhl94Units converts rvu to px/s for the node layer.

## Retail full energy (getpde). Energy scales the speed index.
const ENERGY_FULL := 0x1000
## playeracc caps boosted speed at $1E.
const SPEED_CAP := 0x1E

var settings: SimSettings

func _init(p_settings: SimSettings = null) -> void:
	settings = p_settings if p_settings != null else SimSettings.new()

## Inputs playeracc reads from the player struct and global flags.
class Skater:
	## $67 weight byte.
	var weight: int = 0
	## $68 agility (legstr) byte.
	var agility: int = 0
	## $69 speed (legspd) byte.
	var speed: int = 0
	## Energy from getpde. ENERGY_FULL is rested.
	var energy: int = ENERGY_FULL
	## $34(a3) == 0. doplayeracc sends these to goalieacc ("goalie is special").
	## In playeracc a goalie gets agility twice plus 16, and the puck-carrier cuts.
	var is_goalie: bool = false
	## byte_FFC2FE bit 1 or byte_FFC2FC bit 6: crowd meter boost (+2 agility, +2 speed).
	var crowd_boost: bool = false
	## byte_FFC2FC bit 4: energy ignored (line changes off).
	var ignore_energy: bool = false
	## $62 bit 3: joypad controlled.
	var joypad: bool = false
	## Carrying the puck (puckc == $52).
	var has_puck: bool = false
	## $63 bit 6: injured in a fight.
	var fight_injured: bool = false

## Agility factor k from playeracc. accel = run_speed * k / 32 per frame.
func agility_factor(s: Skater) -> int:
	var k := 64 - (s.weight >> 2)
	k += s.agility
	if s.crowd_boost:
		k += 2
	if s.is_goalie:
		k += s.agility + 16
	return k >> 1

## dirtab (L43933) entry for a retail direction 0-7, scaled by settings.run_speed.
func dirtab(dir: int) -> Vector2i:
	var v: Vector2i = DIRTAB[posmod(dir, 8)]
	if is_equal_approx(settings.run_speed, 200.0):
		return v
	var scale := settings.run_speed / 200.0
	return Vector2i(roundi(v.x * scale), roundi(v.y * scale))

## Retail dirtab: run speed 200 ($C8), 141 ($8D) on diagonals. Retail axes, Y up.
const DIRTAB: Array[Vector2i] = [
	Vector2i(0, 200), Vector2i(141, 141), Vector2i(200, 0), Vector2i(141, -141),
	Vector2i(0, -200), Vector2i(-141, -141), Vector2i(-200, 0), Vector2i(-141, 141),
]

## Acceleration for one retail frame in rvu. dir is a dirtab entry in retail axes (Y up),
## for example Vector2i(0, 200). frames is d7. wall is the last board normal from
## RinkBoards (wallcos/wallsin); acceleration into that board is dropped per axis.
func accel(s: Skater, dir: Vector2i, frames: int = 1, wall: Vector2i = Vector2i.ZERO) -> Vector2i:
	var dx := dir.x
	var dy := dir.y
	# wallsin is -normal.x, wallcos is normal.y. Retail clears an axis that pushes into the board.
	if wall.x != 0 and signi(dx) == signi(wall.x):
		dx = 0
	if wall.y != 0 and signi(dy) == signi(wall.y):
		dy = 0
	var k := agility_factor(s)
	var ax := (dx * k) >> 5
	var ay := (dy * k) >> 5
	ax *= frames
	ay *= frames
	if s.is_goalie and s.joypad and s.has_puck:
		ax >>= 1
		ay >>= 1
	return Vector2i(ax, ay)

## MaxSpeed table entry ((i + base) * step)^2.
func max_speed_sq_entry(i: int) -> int:
	var v := roundi((i + settings.max_speed_base) * settings.max_speed_step)
	return v * v

## Squared top speed in rvu^2, compared against Xvel^2 + Yvel^2.
func max_speed_sq(s: Skater) -> int:
	var energy := ENERGY_FULL if s.ignore_energy else s.energy
	var raw := s.speed
	if s.crowd_boost:
		raw = mini(raw + 2, SPEED_CAP)
	# lsr #1, mulu energy, asl.l #4, swap, asl.w #2, andi #$3F. The table index is offset / 4.
	var offset := ((((raw >> 1) * energy) << 4) >> 16) << 2
	offset &= 0x3F
	var i := offset >> 2
	var sq := max_speed_sq_entry(i)
	if offset < 0x3C and (raw & 1) == 1:
		sq += (max_speed_sq_entry(i + 1) - sq) >> 1
	if s.fight_injured:
		sq >>= 3
	if s.is_goalie and s.has_puck:
		sq >>= 1
	return sq

## Top speed in rvu.
func max_speed(s: Skater) -> float:
	return sqrt(float(max_speed_sq(s)))

## One playeracc call. Velocity only changes when the new speed is within the cap.
func apply_accel(s: Skater, vel: Vector2i, dir: Vector2i, frames: int = 1, wall: Vector2i = Vector2i.ZERO) -> Vector2i:
	var nv := vel + accel(s, dir, frames, wall)
	var speed_sq := nv.x * nv.x + nv.y * nv.y
	if speed_sq > max_speed_sq(s):
		return vel
	return nv

## Drag from updateplayers: v -= v >> shift, and at least 1 when v is not 0.
## Use settings.glide_drag_shift while receiving a pass (pfdoff).
static func drag_axis(v: int, shift: int) -> int:
	if v == 0:
		return 0
	var d := v >> shift
	if d == 0:
		d = 1
	return v - d

func apply_drag(vel: Vector2i, gliding: bool = false) -> Vector2i:
	var shift := settings.glide_drag_shift if gliding else settings.skate_drag_shift
	return Vector2i(drag_axis(vel.x, shift), drag_axis(vel.y, shift))

## stopna: each axis moves stop_decel toward 0 and does not cross it.
func apply_stop(vel: Vector2i) -> Vector2i:
	var d := roundi(settings.stop_decel)
	return Vector2i(_toward_zero(vel.x, d), _toward_zero(vel.y, d))

static func _toward_zero(v: int, d: int) -> int:
	if v < 0:
		return mini(v + d, 0)
	return maxi(v - d, 0)

## dostop plays the stop animation when either axis is faster than $1000.
static func wants_stop_anim(vel: Vector2i) -> bool:
	return absi(vel.x) > 0x1000 or absi(vel.y) > 0x1000

## Builds a Skater from a PlayerData resource.
static func skater_from(p: PlayerData) -> Skater:
	var s := Skater.new()
	s.weight = p.raw_weight()
	s.agility = p.raw_agility()
	s.speed = p.raw_speed()
	s.is_goalie = p.is_goalie()
	return s
