class_name RetailRng
extends RefCounted
## randomd0 (L44190): 32-bit LCG, seed = seed * $BB40E62D + 1. A roll returns
## bits 8-23 of the new seed scaled to the range. Retail seeds it from the VDP H/V
## counter; the port takes an explicit seed so games and tests can replay.

var seed: int = 0

func _init(p_seed: int = 0x00500000) -> void:
	seed = p_seed & 0xFFFFFFFF

func _next() -> int:
	seed = (seed * 0xBB40E62D + 1) & 0xFFFFFFFF
	return (seed >> 8) & 0xFFFF

## randomd0: 0 <= result < range. range is an unsigned word.
func range_(n: int) -> int:
	return (_next() * (n & 0xFFFF)) >> 16

## randomd0s (L44178): -range <= result < range.
func signed(n: int) -> int:
	return range_(n * 2) - n
