class_name MatchConfig
extends Resource
## What the setup screen chose. The game scene reads it from Sim.match.

## Who plays a side: the CPU, one pad, or two pads together. Retail's player counts
## (OptNOP, _noplist) are the combinations: two pads on one team, head to head, and with
## the multitap pads 1 and 3 against pad 2 (or pads 2 and 4). Pad 3 always joins pad 1's
## side and pad 4 pad 2's.
enum Driver { CPU, PAD1, PAD2, PADS12, PADS13, PADS24 }
## Retail NHL '94, or "NHL Hockey '94-Fight": Chaos81's fight patch (nhl94-patches, MIT)
## with its rosters, the Fighting option, its title screen and credits.
enum Edition { RETAIL, FIGHT }
## OptFight, the fight patch's menu option: Off, On, On - Arcade Mode.
enum Fighting { OFF, ON, ARCADE }

const TEAM_DIRS := {Edition.RETAIL: "res://data/teams", Edition.FIGHT: "res://data/teams_fight"}

@export var home_team: TeamData
@export var away_team: TeamData
## Who plays each side.
@export var home_control: Driver = Driver.PAD1
@export var away_control: Driver = Driver.CPU
## Period length in minutes. Retail options are 5, 10 and 20 (ClockLength _timetab).
@export_range(1, 20, 1) var period_minutes: int = 5
## OptPerlen when set (0-3: 5, 10, 20 minutes, 30 seconds); -1 uses period_minutes. The
## 30-second periods are the Matchups screen's A + C + Start (StartGame L29756).
@export var perlen: int = -1
## The game's form tables (home, away), made on the Matchups screen; empty: StartGame makes
## them (Shootout, or no Matchups).
@export var form: Array = []
## OptPlayMode as the game sees it: 0 a regular-season game, 1-3 a playoff game (the
## League in Sim holds the series). The Shootout mode is `shootout`.
@export var play_mode: int = 0
## FigureJoy's pads for a playoff game (cont1team-cont4team); empty: from the drivers.
@export var pads: PackedInt32Array = PackedInt32Array()
## User Records On (OptUserRec 0): the game's records are saved at the end, for the
## users Name Entry picked ([home, away], ids 1-7, 0 = none).
@export var user_records: bool = false
@export var users: Array = [0, 0]
## Retail's Players row (OptNOP, the 4 Way Play list): when set it decides the pads
## instead of home_control / away_control.
@export var players: int = -1
@export var penalties: bool = true
@export var offsides: bool = true
@export var line_changes: bool = true
## OptLine 2, "Auto": line changes on, but nobody tires and the CPU changes every team's
## lines (byte_FFC2FC bit 4).
@export var auto_lines: bool = false
## OptGoalie: true Auto Control (the CPU plays a pad team's goalie), false Manual.
@export var auto_goalie: bool = true
## Shootout play mode (OptPlayMode 4): the whole game is a penalty-shot shootout.
@export var shootout: bool = false
@export var edition: Edition = Edition.FIGHT
## The patch's default is On (DefFight). Retail has no fighting.
@export var fighting: Fighting = Fighting.ON
## Starting line index for each team (into TeamData.lines).
@export var home_line: int = 0
@export var away_line: int = 0

## Each pad's team (cont1team-cont4team: 0 none, 1 home, 2 away) from the two drivers.
func pad_teams() -> PackedInt32Array:
	if pads.size() == 4:
		return pads
	if players >= 0:
		return players_pads(players)
	var out := PackedInt32Array([0, 0, 0, 0])
	for side in [[home_control, 1], [away_control, 2]]:
		for k in DRIVER_PADS[side[0]]:
			out[k] = side[1]
	return out

## FigureJoy's _noplist (L55157) with the 4 Way Play rows: OptNOP -> cont1team-cont4team.
## 0 Demo, 1 One - Home, 2 One - Visitor, 3 Two - Teammates, 4 Two - Head to Head,
## 5 Three (pad 3 with pad 1), 6 Four (pads 1 + 3 against 2 + 4).
const NOPLIST := [[0, 0, 0, 0], [1, 0, 0, 0], [2, 0, 0, 0], [1, 1, 0, 0], [1, 2, 0, 0],
	[1, 2, 1, 0], [1, 2, 1, 2]]

static func players_pads(nop: int) -> PackedInt32Array:
	return PackedInt32Array(NOPLIST[clampi(nop, 0, NOPLIST.size() - 1)])

const DRIVER_PADS := {Driver.CPU: [], Driver.PAD1: [0], Driver.PAD2: [1], Driver.PADS12: [0, 1],
	Driver.PADS13: [0, 2], Driver.PADS24: [1, 3]}
const DRIVER_NAMES := {Driver.CPU: "CPU", Driver.PAD1: "Pad 1", Driver.PAD2: "Pad 2",
	Driver.PADS12: "Pads 1 + 2", Driver.PADS13: "Pads 1 + 3 (multitap)",
	Driver.PADS24: "Pads 2 + 4 (multitap)"}

## OptFight for the world: the patch's option, and nothing in retail.
func opt_fight() -> int:
	return fighting if edition == Edition.FIGHT else 0

## Every TeamData resource of an edition (retail res://data/teams, the fight patch's
## res://data/teams_fight), sorted by display name.
static func available_teams(ed: Edition = Edition.RETAIL) -> Array[TeamData]:
	var out: Array[TeamData] = []
	var path: String = TEAM_DIRS[ed]
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres") or name.ends_with(".res"):
			var t := load(path + "/" + name) as TeamData
			if t:
				out.append(t)
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.display_name() < b.display_name())
	return out
