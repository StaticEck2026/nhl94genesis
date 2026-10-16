class_name Sram
extends RefCounted
## The cartridge's 8 KB battery RAM (spec docs/specs/playoffs_records.md §8), kept in a
## file. The layout is retail's:
## - $0000 player best games (4 bytes at 4 * (26 * team + slot));
## - $0B60 team records (16 bytes a team), $0D20 user records (16 bytes, users 0-7);
## - $0DA0 user names (12 bytes, ids 1-7);
## - $1EF6 the 256-byte $FFD076 block: the saved line, the playoff state (+$12, 5 words)
##   and the packed Playoff Stats (+$66);
## - $1FFE / $1FFF the checksum.
## A file that fails the checksum is cleared as InitSaveRAM does (ClearSRAM).

const SIZE := 0x2000
const PATH := "user://nhl94.srm"
const PLAYERS := 0x0000
const TEAMS := 0x0B60
const USERS := 0x0D20
const NAMES := 0x0DA0
const BLOCK := 0x1EF6
const BLOCK_SIZE := 0x100
const STATE := 0x12
const STATS := 0x66
const STAT_BYTES := 0x98

var bytes := PackedByteArray()
var path := ""

## path "" keeps the RAM in memory only (tests).
func _init(p_path: String = PATH) -> void:
	path = p_path
	bytes.resize(SIZE)
	if path != "" and FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var b := f.get_buffer(SIZE)
			if b.size() == SIZE:
				bytes = b
	if not valid():
		clear()

## ValidateSRAM: byte $1FFF is the sum of 0..$1FFD, $1FFE its complement.
func valid() -> bool:
	var s := _sum()
	return bytes[0x1FFF] == s and bytes[0x1FFE] == (~s & 0xFF)

func _sum() -> int:
	var s := 0
	for i in 0x1FFE:
		s += bytes[i]
	return s & 0xFF

## ClearSRAM: zero, byte 0 = 1, the checksum.
func clear() -> void:
	bytes.fill(0)
	bytes[0] = 1
	commit()

## MakeSRAMChecksum, then the file.
func commit() -> void:
	var s := _sum()
	bytes[0x1FFF] = s
	bytes[0x1FFE] = ~s & 0xFF
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)

func read(at: int, n: int) -> PackedByteArray:
	return bytes.slice(at, at + n)

func write(at: int, data: PackedByteArray) -> void:
	for i in data.size():
		bytes[at + i] = data[i]

# --- the $FFD076 block ---------------------------------------------------------------------------

## sub_FE696 for the playoff state and Playoff Stats (an empty state clears it).
func save_playoffs(state: PackedInt32Array, stats: PackedInt32Array) -> void:
	for i in 5:
		var w := state[i] if i < state.size() else 0
		bytes[BLOCK + STATE + 2 * i] = (w >> 8) & 0xFF
		bytes[BLOCK + STATE + 2 * i + 1] = w & 0xFF
	_pack_stats(stats)
	commit()

func playoff_state() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in 5:
		out.append((bytes[BLOCK + STATE + 2 * i] << 8) | bytes[BLOCK + STATE + 2 * i + 1])
	return out

## The 104 Playoff Stats entries, packed at their widths (League.STAT_WIDTHS).
func _pack_stats(stats: PackedInt32Array) -> void:
	var bit := 0
	for i in STAT_BYTES:
		bytes[BLOCK + STATS + i] = 0
	for i in mini(stats.size(), 104):
		var w: int = League.STAT_WIDTHS[(103 - i) & 3]
		var v := clampi(stats[i], 0, (1 << w) - 1)
		for k in w:
			if v & (1 << k):
				var at := BLOCK + STATS + ((bit + k) >> 3)
				bytes[at] |= 1 << ((bit + k) & 7)
		bit += w

func playoff_stats() -> PackedInt32Array:
	var out := PackedInt32Array()
	var bit := 0
	for i in 104:
		var w: int = League.STAT_WIDTHS[(103 - i) & 3]
		var v := 0
		for k in w:
			var at := BLOCK + STATS + ((bit + k) >> 3)
			if bytes[at] & (1 << ((bit + k) & 7)):
				v |= 1 << k
		out.append(v)
		bit += w
	return out

## The Save Team Line slot: team + 1 (0 none) and its 31 nibbles (sub_8928).
func saved_line() -> PackedByteArray:
	return read(BLOCK, 0x11)

func save_line(data: PackedByteArray) -> void:
	write(BLOCK, data)
	commit()
