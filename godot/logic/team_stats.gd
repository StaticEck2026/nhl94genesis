class_name TeamStats
extends RefCounted
## One team struct (retail HmShots at $FFC6CE for home, + $364 for away). Offsets in the
## comments are from the struct start. Spec: rules_clock_penalties.md section 0.6 and
## puck.md section 2. Where the two disagree on a name, the field is named by what the
## code that writes it does.

const ROSTER := 26

## tmpdst values below 0.
const TMPDST_ON_ICE := -1
const TMPDST_BENCH := -2
const TMPDST_INJURED_PERIOD := -3
const TMPDST_INJURED_GAME := -4

## $1E: the team record (null in the sandbox and tests), $28 its team number, and
## the 8 roster bytes per slot rebuilt from it (setplayer reads these).
var data: TeamData = null
var team_index: int = -1
var rom: Array = []
## $16A: the 7 RAM lines (8 one-based slots each), copied by sub_171BE.
var ram_lines: PackedInt32Array = PackedInt32Array()
## $1A2: per-game form, 16 signed bytes per roster slot (Create_HotCold_Table).
var hotcold: PackedInt32Array

## $000 shots on goal.
var shots: int = 0
## $002 power-play goals (sub_1284A).
var pp_goals: int = 0
## $004 power plays, $006 penalties, $008 penalty minutes.
var power_plays: int = 0
var penalties: int = 0
var penalty_minutes: int = 0
## $00A attack time (game seconds).
var attack_time: int = 0
## $00C goals (the score).
var goals: int = 0
## $00E faceoffs won (credited in _glue on the first touch after a faceoff).
var faceoffs_won: int = 0
## $010 checks.
var checks: int = 0
## $012 pass attempts.
var pass_attempts: int = 0
## $014 passes completed.
var passes: int = 0
## $016 tmline: current line (0-1 scoring, 2 checking, 3-4 power play, 5-6 penalty kill).
var line: int = 0
## $018, $01A, $01C: last toucher and the two assist candidates (pnum, -1 none).
var toucher: int = -1
var assist1: int = -1
var assist2: int = -1
## $022 tmsort: first object index of the team (0 home, 6 away).
var first_object: int = 0
## $024 tmap: players on ice including the goalie, 4..6.
var on_ice: int = 6
## $026 goalie pnum on ice (-1 none); goalie_pulled is the high byte $FF.
var goalie_pnum: int = -1
var goalie_pulled: bool = false
## $030 flags: bit 0 redraw the line menu, bit 1 line menu used this stoppage, bit 2
## contain (assnearest; never set in play), bit 3 possession lost (restart the assist
## chain), bit 4 team offside.
var flags30: int = 0
const F30_LINE_REDRAW := 1 << 0
const F30_LINE_MENU := 1 << 1
## The team has used its timeout (pause menu, $9D7A): for the rest of the game its puck
## chaser contains instead of chasing (assnearest L40770).
const F30_TIMEOUT := 1 << 2
const F30_CHAIN_RESET := 1 << 3
const F30_OFFSIDE := 1 << 4
## $02E: the line-menu row picked last (A / B / C = 0-2).
var menu_row: int = 0
## $02A (long) squared distance of the team's nearest available skater to the
## lead-adjusted puck (assnearest); 0 when the team has the puck or none qualifies.
var nearest_sq: int = 0
## $032 + 2i energy per roster slot ($1000 rested).
var energy: PackedInt32Array
## $066 + 2i tmpdst per roster slot (see TMPDST_* and the penalty bits).
var tmpdst: PackedInt32Array
## $09A box list: pnums in assessment order.
var box: PackedInt32Array = PackedInt32Array()
## $0B4 + pnum goals (goalie: goals against), $0CE assists, $0E8 shots (goalie: shots
## against), $102 penalty minutes, $11C checks.
var player_goals: PackedInt32Array
var player_assists: PackedInt32Array
var player_shots: PackedInt32Array
var player_pim: PackedInt32Array
var player_checks: PackedInt32Array
## $342 + 2 * gsp goals per period, $34A + 2 * gsp shots per period (gsp 0..3).
var period_goals: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var period_shots: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## $352 power-play time, $354 power-play shots.
var pp_time: int = 0
var pp_shots: int = 0
## $356: checkgoal adds 1 when the scoring team is not the team on the power play,
## so it counts short-handed goals (the rules spec's listing comment says "PP goals").
var shorthanded_goals: int = 0
## $358 breakaway attempts (breakaway ding), $35A breakaway goals, $35C one-timer
## attempts, $35E one-timer goals.
var breakaway_attempts: int = 0
var breakaway_goals: int = 0
var onetimer_attempts: int = 0
var onetimer_goals: int = 0
## $360 penalty-shot / shootout attempts.
var ps_attempts: int = 0
## $362: checkgoal adds 1 for a penalty-shot goal outside shootouts.
var penalty_shot_goals: int = 0

func _init() -> void:
	energy = _filled(0x1000)
	tmpdst = _filled(TMPDST_BENCH)
	player_goals = _filled(0)
	player_assists = _filled(0)
	player_shots = _filled(0)
	player_pim = _filled(0)
	player_checks = _filled(0)
	hotcold = PackedInt32Array()
	hotcold.resize(ROSTER * 16)

## clearTeamStats (L53690): zero the struct for a new game. The record, the form
## table and the goalie word survive; the box list empties.
func clear_game() -> void:
	shots = 0
	pp_goals = 0
	power_plays = 0
	penalties = 0
	penalty_minutes = 0
	attack_time = 0
	goals = 0
	faceoffs_won = 0
	checks = 0
	pass_attempts = 0
	passes = 0
	line = 0
	toucher = -1
	assist1 = -1
	assist2 = -1
	on_ice = 6
	flags30 = 0
	nearest_sq = 0
	menu_row = 0
	energy = _filled(0)
	tmpdst = _filled(0)
	box = PackedInt32Array()
	player_goals = _filled(0)
	player_assists = _filled(0)
	player_shots = _filled(0)
	player_pim = _filled(0)
	player_checks = _filled(0)
	period_goals = PackedInt32Array([0, 0, 0, 0])
	period_shots = PackedInt32Array([0, 0, 0, 0])
	pp_time = 0
	pp_shots = 0
	shorthanded_goals = 0
	breakaway_attempts = 0
	breakaway_goals = 0
	onetimer_attempts = 0
	onetimer_goals = 0
	ps_attempts = 0
	penalty_shot_goals = 0

static func _filled(v: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(ROSTER)
	a.fill(v)
	return a

static func valid_pnum(p: int) -> bool:
	return p >= 0 and p < ROSTER
