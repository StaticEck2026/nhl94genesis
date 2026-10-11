class_name TeamStats
extends RefCounted
## One team's stats block (retail HmShots for home, HmShots + $364 for away). Offsets
## in comments are from HmShots. More fields arrive with the rules port.

const ROSTER := 26

## +$10 team checks.
var checks: int = 0
## +$11C + pnum: per-player checks.
var player_checks: PackedInt32Array
## +$66 + pnum * 2: per-player status word ($FFFD injured for the period, $FFFC for the game).
var player_status: PackedInt32Array
## Shots, goals, power play and the rest come with the rules port.
var shots: int = 0
var goals: int = 0

func _init() -> void:
	player_checks.resize(ROSTER)
	player_status.resize(ROSTER)

const STATUS_INJURED_PERIOD := 0xFFFD
const STATUS_INJURED_GAME := 0xFFFC
