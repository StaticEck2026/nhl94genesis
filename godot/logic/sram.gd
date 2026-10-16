class_name Sram
extends RefCounted
## The cartridge's 8 KB battery RAM (spec docs/specs/playoffs_records.md §8), kept in a
## file. The layout is retail's:
## - $0000 player best games (4 bytes at 4 * (26 * team + slot));
## - $0B60 team records (16 bytes a team), $0D20 user records (16 bytes, users 0-7);
## - $0DA0 user names (12 bytes, ids 1-7);
## - $1EF6 the 256-byte $FFD076 block: the saved line, the playoff state (+$12, 5 words)
##   and the packed Playoff Stats (+$66-$FD, filled from the top);
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
## The packed stats' first word: $FFD172, block offset $FC (AddPOStats' longs at
## $FFD170 - 2 * (bit >> 4)).
const STATS_TOP := 0xFC

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

## The 104 Playoff Stats entries, packed as AddPOStats (L55445) does: entry i at its width
## (League.STAT_WIDTHS), from bit 0 on. Bit b is bit b & 15 of the big-endian word at
## block offset $FC - 2 * (b >> 4) ($FFD172 down), so the stats fill $D0DC-$D173 from
## the top. Only the fields are written; the 4 spare bits keep their value.
func _pack_stats(stats: PackedInt32Array) -> void:
	var bit := 0
	for i in 104:
		var w: int = League.STAT_WIDTHS[(103 - i) & 3]
		var v := clampi(stats[i] if i < stats.size() else 0, 0, (1 << w) - 1)
		for k in w:
			var at := _stat_bit(bit + k)
			if v & (1 << k):
				bytes[at.x] |= at.y
			else:
				bytes[at.x] &= ~at.y & 0xFF
		bit += w

## sub_1833A: the 104 entries back.
func playoff_stats() -> PackedInt32Array:
	var out := PackedInt32Array()
	var bit := 0
	for i in 104:
		var w: int = League.STAT_WIDTHS[(103 - i) & 3]
		var v := 0
		for k in w:
			var at := _stat_bit(bit + k)
			if bytes[at.x] & at.y:
				v |= 1 << k
		out.append(v)
		bit += w
	return out

## Bit b of the packed stats: (byte index, mask).
static func _stat_bit(b: int) -> Vector2i:
	var word := BLOCK + STATS_TOP - 2 * (b >> 4)
	var bit := b & 15
	return Vector2i(word + (0 if bit >= 8 else 1), 1 << (bit & 7))

## The Save Team Line slot: team + 1 (0 none) and its 33 nibbles (sub_8928), up to the
## playoff state at +$12.
func saved_line() -> PackedByteArray:
	return read(BLOCK, STATE)

func save_line(data: PackedByteArray) -> void:
	write(BLOCK, data)
	commit()

# --- records -------------------------------------------------------------------------------

## A player's best game (4 bytes): best, own user, opponent team, opponent user.
func player_record(team: int, slot: int) -> PackedByteArray:
	return read(PLAYERS + 4 * (26 * team + slot), 4)

func set_player_record(team: int, slot: int, rec: PackedByteArray) -> void:
	write(PLAYERS + 4 * (26 * team + slot), rec)

## A team's records (16 bytes): goals, saves and home crowd dB, each with its users and
## opponent.
func team_record(team: int) -> PackedByteArray:
	return read(TEAMS + 16 * team, 16)

func set_team_record(team: int, rec: PackedByteArray) -> void:
	write(TEAMS + 16 * team, rec)

## A user's record (16 bytes): best goals and saves in a win, wins, games, ties (words).
func user_record(user: int) -> PackedByteArray:
	return read(USERS + 16 * user, 16)

func set_user_record(user: int, rec: PackedByteArray) -> void:
	write(USERS + 16 * user, rec)

## User names, ids 1-7 (12 characters, blank = empty).
func user_name(id: int) -> String:
	if id <= 0 or id > 7:
		return ""
	return read(NAMES + 12 * id, 12).get_string_from_ascii().strip_edges(false, true)

func set_user_name(id: int, name: String) -> void:
	var b := PackedByteArray()
	b.resize(12)
	var a := name.to_ascii_buffer()
	for i in mini(a.size(), 12):
		b[i] = a[i]
	write(NAMES + 12 * id, b)
	commit()

## A team's crowd record in dB: team +8, $50 when none (LoadCrowdRec).
func crowd_record(team: int) -> int:
	var v := team_record(team)[8]
	return v if v != 0 else 0x50

## sub_FEC5E: the league's crowd record and its team (the last scanning from 27 down).
func league_crowd_record() -> Vector2i:
	var best := Vector2i(0, -1)
	for t in range(27, -1, -1):
		var v := crowd_record(t)
		if v > best.x:
			best = Vector2i(v, t)
	return best

static func word(b: PackedByteArray, at: int) -> int:
	return (b[at] << 8) | b[at + 1]

static func set_word(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = (v >> 8) & 0xFF
	b[at + 1] = v & 0xFF
