class_name PadState
extends RefCounted
## One Genesis pad as the game reads it. The game layer sets `held` (active high) each
## loop; read() is ReadJoyN (L44509): the opposite-direction cleanup of ReadJoyData
## (unk_1A4DE), the direction from jdtab, and new / changed / held masks against last
## loop's byte (ljN). Edges only move when read() runs, as in retail.

const UP := 1 << 0
const DOWN := 1 << 1
const LEFT := 1 << 2
const RIGHT := 1 << 3
const B := 1 << 4
const C := 1 << 5
const A := 1 << 6
const START := 1 << 7

## unk_1A4DE: RLDU cleanup (U+D gives Up, L+R gives Right, all four nothing).
const CLEAN: Array[int] = [0, 1, 2, 1, 4, 5, 6, 6, 8, 9, 0xA, 0xA, 8, 9, 0xA, 0]
## jdtab (L44581): RLDU to direction 0-7, 8 = none.
const JDTAB: Array[int] = [8, 0, 4, 8, 6, 7, 5, 8, 2, 1, 3, 8, 8, 8, 8, 8]

## Buttons and directions currently down (set by the game layer).
var held: int = 0
## ljN: last loop's cleaned byte.
var last: int = 0
## ReadJoyN outputs: d0 = direction | held buttons, d1 = new, d2 = changed, d3 = held.
var d0: int = 8
var d1: int = 0
var d2: int = 0
var d3: int = 0

func read() -> void:
	var h := (held & 0xF0) | CLEAN[held & 0xF]
	d0 = (h & 0xF0) | JDTAB[h & 0xF]
	d2 = h ^ last
	last = h
	d3 = h
	d1 = h & d2

func dir() -> int:
	return d0 & 0xF
