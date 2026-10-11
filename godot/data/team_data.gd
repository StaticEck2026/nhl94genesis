@tool
class_name TeamData
extends Resource
## One retail team record (docs/specs/data_attributes.md section 1): roster, lines, team
## ratings and uniform palettes. Exported offline by tools/extract/teams.py.

enum Conference { EASTERN, WESTERN, ALL_STAR }
enum Division { ATLANTIC, NORTHEAST, CENTRAL, PACIFIC, NONE }

## The 8 data lines: line changes off, then the seven RAM lines.
const LINE_NAMES: Array[String] = ["Off", "Sc1", "Sc2", "Chk", "PP1", "PP2", "PK1", "PK2"]
## Line slot order: retail position codes 0-5, then the extra attacker.
const LINE_SLOTS: Array[String] = ["G", "LD", "RD", "LW", "C", "RW", "X"]

## Retail team number 0-27 (the pointer table at ROM $30E).
@export var team_index: int = 0
@export var city: String = ""
@export var team_name: String = ""
@export var abbreviation: String = ""
@export var conference: Conference = Conference.EASTERN
@export var division: Division = Division.ATLANTIC
@export var arena_name: String = ""

@export_group("Roster")
## Roster slots in retail order: goalies, forwards, defense.
@export var players: Array[PlayerData] = []
@export var goalie_count: int = 2
@export var forward_count: int = 14
@export var defense_count: int = 8
## The goalie word. Retail only counts its nibbles (goalie_count); kept for reference.
@export var goalie_marks: int = 0
## 8 lines x 8 bytes, 1-based roster slots: G, LD, RD, LW, C, RW, X (extra attacker), 0.
@export var lines: PackedInt32Array = PackedInt32Array()

@export_group("Ratings")
## Other-game ticker score rows (getscore), 0-7.
@export_range(0, 7, 1) var sim_offense: int = 0
@export_range(0, 7, 1) var sim_defense: int = 0
## setplayer bonuses: added on the power play, subtracted short-handed, added at home,
## subtracted on the road (0-15; the ROM uses 0-3).
@export_range(0, 15, 1) var pp_bonus: int = 0
@export_range(0, 15, 1) var pk_penalty: int = 0
@export_range(0, 15, 1) var home_bonus: int = 0
@export_range(0, 15, 1) var away_penalty: int = 0

@export_group("Colors")
## 16 Genesis CRAM words (0000BBB0GGG0RRR0) per uniform: palette line 2 at home, line 3
## on the road. Indices 3-5 and 8-13 are the team colors.
@export var home_palette: PackedInt32Array = PackedInt32Array()
@export var away_palette: PackedInt32Array = PackedInt32Array()

func display_name() -> String:
	return "%s %s" % [city, team_name]

func player(slot: int) -> PlayerData:
	return players[slot] if slot >= 0 and slot < players.size() else null

## Data line k (0-7) as 8 one-based slots.
func line(k: int) -> PackedInt32Array:
	if lines.size() < (k + 1) * 8:
		return PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	return lines.slice(k * 8, k * 8 + 8)

func goalies() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in players:
		if p.is_goalie():
			out.append(p)
	return out

## CRAM word to a color (3 bits per channel).
static func cram_color(w: int) -> Color:
	return Color8(((w >> 1) & 7) * 36, ((w >> 5) & 7) * 36, ((w >> 9) & 7) * 36)

func home_colors() -> PackedColorArray:
	return _colors(home_palette)

func away_colors() -> PackedColorArray:
	return _colors(away_palette)

static func _colors(p: PackedInt32Array) -> PackedColorArray:
	var out := PackedColorArray()
	for w in p:
		out.append(cram_color(w))
	return out
