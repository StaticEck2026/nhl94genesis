class_name MatchConfig
extends Resource
## What the setup screen chose. The game scene reads it from Sim.match.

enum Driver { CPU, PAD1, PAD2 }

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
## Starting line index for each team (into TeamData.lines).
@export var home_line: int = 0
@export var away_line: int = 0

## Every TeamData resource under res://data/teams, sorted by display name.
static func available_teams() -> Array[TeamData]:
	var out: Array[TeamData] = []
	var dir := DirAccess.open("res://data/teams")
	if dir == null:
		return out
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres") or name.ends_with(".res"):
			var t := load("res://data/teams/" + name) as TeamData
			if t:
				out.append(t)
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.display_name() < b.display_name())
	return out
