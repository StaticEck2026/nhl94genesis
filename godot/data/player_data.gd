@tool
class_name PlayerData
extends Resource
## One player's ratings. Ratings are 0-100. Retail stores them as small integers;
## the raw_* helpers give the retail value the logic tables expect.

enum Position { CENTER, LEFT_WING, RIGHT_WING, DEFENSE, GOALIE }
enum Hand { LEFT, RIGHT }

@export var full_name: String = ""
@export_range(0, 99, 1) var jersey_number: int = 0
@export var position: Position = Position.CENTER
@export var handedness: Hand = Hand.LEFT
## Body weight in pounds.
@export_range(140.0, 260.0, 1.0) var weight_lbs: float = 190.0

@export_group("Ratings (0-100)")
@export_range(0.0, 100.0, 1.0) var agility: float = 50.0
@export_range(0.0, 100.0, 1.0) var speed: float = 50.0
@export_range(0.0, 100.0, 1.0) var offensive_awareness: float = 50.0
@export_range(0.0, 100.0, 1.0) var defensive_awareness: float = 50.0
@export_range(0.0, 100.0, 1.0) var shot_power: float = 50.0
@export_range(0.0, 100.0, 1.0) var shot_accuracy: float = 50.0
@export_range(0.0, 100.0, 1.0) var pass_rating: float = 50.0
@export_range(0.0, 100.0, 1.0) var checking: float = 50.0
@export_range(0.0, 100.0, 1.0) var stick_handling: float = 50.0
@export_range(0.0, 100.0, 1.0) var endurance: float = 50.0
@export_range(0.0, 100.0, 1.0) var aggressiveness: float = 50.0
@export_range(0.0, 100.0, 1.0) var roughness: float = 50.0
@export_group("Goalie (0-100)")
@export_range(0.0, 100.0, 1.0) var glove_left: float = 50.0
@export_range(0.0, 100.0, 1.0) var glove_right: float = 50.0
@export_range(0.0, 100.0, 1.0) var stick_left: float = 50.0
@export_range(0.0, 100.0, 1.0) var stick_right: float = 50.0
@export_range(0.0, 100.0, 1.0) var puck_control: float = 50.0

## Retail speed byte ($69, legspd). playeracc caps it at $1E.
## Mapping 0-100 to 0-30 is provisional (see GODOT_TODO open questions).
func raw_speed() -> int:
	return roundi(speed / 100.0 * 30.0)

## Retail agility byte ($68, legstr). Provisional 0-30 mapping.
func raw_agility() -> int:
	return roundi(agility / 100.0 * 30.0)

## Retail weight byte ($67). Provisional: pounds above 140, in 8 lb steps, 0-15.
func raw_weight() -> int:
	return clampi(roundi((weight_lbs - 140.0) / 8.0), 0, 15)

## Retail endurance byte ($72). Provisional 0-30 mapping.
func raw_endurance() -> int:
	return roundi(endurance / 100.0 * 30.0)

func is_goalie() -> bool:
	return position == Position.GOALIE
