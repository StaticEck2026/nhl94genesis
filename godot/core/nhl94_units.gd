class_name Nhl94Units
extends RefCounted
## Fixed-point to float conversion for values read from lst/nhl94.bin.lst.
##
## Retail positions are 32-bit 16.16 longs (high word is the pixel). Each loop adds
## vel * STEP * d7 to the long, where d7 is the vblanks since the last loop
## (DoGameFrame L29914, updateplayers L35517). NTSC vblank is 60 Hz.

## Vblanks per second. One retail "frame" in every table.
const RETAIL_HZ := 60.0
## updateplayers multiplies velocity by $11 before adding it to the 16.16 position.
const VEL_STEP := 17.0
## Step used when word_FFD06E is set (meaning not named yet).
const VEL_STEP_ALT := 22.0
## 16.16 fixed point scale.
const FIXED_ONE := 65536.0

## Retail velocity word to px per retail frame.
static func vel_to_px_per_frame(vel: float, step: float = VEL_STEP) -> float:
	return vel * step / FIXED_ONE

## Retail velocity word to px per second.
static func vel_to_px_per_sec(vel: float, step: float = VEL_STEP) -> float:
	return vel_to_px_per_frame(vel, step) * RETAIL_HZ

## px per second to a retail velocity word.
static func px_per_sec_to_vel(px_per_sec: float, step: float = VEL_STEP) -> float:
	return px_per_sec / RETAIL_HZ * FIXED_ONE / step

## Godot delta seconds to retail frames (the d7 value).
static func frames(delta: float) -> float:
	return delta * RETAIL_HZ

## Per-frame multiplier k applied n times, as a rate over delta seconds.
static func decay(per_frame: float, delta: float) -> float:
	return pow(per_frame, frames(delta))

## Retail 8-way direction index to a Godot unit vector.
## dirtab L43933 lists (x, y): 0 = (0, 200), 1 = (141, 141), 2 = (200, 0), and on clockwise.
## Retail rink Y grows up the ice. Godot Y grows down, so retail (x, y) is Godot (x, -y).
static func dir8_to_vector(dir: int) -> Vector2:
	return Vector2.UP.rotated(TAU * float(posmod(dir, 8)) / 8.0)

## Retail rink vector (Y up) to Godot (Y down).
static func rink_to_godot(v: Vector2) -> Vector2:
	return Vector2(v.x, -v.y)
