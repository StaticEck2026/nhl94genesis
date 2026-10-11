@tool
class_name TeamData
extends Resource
## One team: roster, lines, colors and arena.

enum Conference { EASTERN, WESTERN, ALL_STAR }
enum Division { ATLANTIC, NORTHEAST, CENTRAL, PACIFIC, NONE }

@export var city: String = ""
@export var team_name: String = ""
@export var abbreviation: String = ""
@export var conference: Conference = Conference.EASTERN
@export var division: Division = Division.ATLANTIC

@export_group("Roster")
@export var players: Array[PlayerData] = []
## Line slots as indices into players. Retail lines: scoring, checking, power play,
## penalty kill, plus the starting goalie. Filled by SetPersonel / SetPlList ports.
@export var lines: Dictionary = {}

@export_group("Colors")
## Palette swap targets for the team shader. Order matches the jersey mask channels.
@export var home_colors: PackedColorArray = PackedColorArray()
@export var away_colors: PackedColorArray = PackedColorArray()

@export_group("Arena")
@export var arena_name: String = ""
## Home ice bonus applied by setplayer (_habonus). Not translated yet.
@export_range(0.0, 10.0, 1.0) var home_ice_bonus: float = 0.0
## Organ and crowd sound set name under res://assets/audio.
@export var organ_set: String = "default"

func display_name() -> String:
	return "%s %s" % [city, team_name]

func goalies() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in players:
		if p.is_goalie():
			out.append(p)
	return out
