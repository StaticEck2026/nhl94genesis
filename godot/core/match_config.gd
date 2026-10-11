class_name MatchConfig
extends Resource
## What the setup screen chose. The game scene reads it from Sim.match.

enum Driver { CPU, PAD1, PAD2 }
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
@export var penalties: bool = true
@export var offsides: bool = true
@export var line_changes: bool = true
## Shootout play mode (OptPlayMode 4): the whole game is a penalty-shot shootout.
@export var shootout: bool = false
@export var edition: Edition = Edition.FIGHT
## The patch's default is On (DefFight). Retail has no fighting.
@export var fighting: Fighting = Fighting.ON
## Starting line index for each team (into TeamData.lines).
@export var home_line: int = 0
@export var away_line: int = 0

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
