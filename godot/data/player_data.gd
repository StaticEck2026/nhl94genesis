@tool
class_name PlayerData
extends Resource
## One roster player. Ratings use the retail roster-screen scale (25-99): the value the
## game shows for a rating nibble with hot/cold 0 (CalcAttrib + AttribAdjust,
## docs/specs/data_attributes.md section 3). Nibbles 0-6 show as 25, 34, 43, 54, 72, 90
## and 99. `rom_bytes()` turns the ratings back into the 8 roster bytes setplayer reads,
## picking the nearest nibble, so the extracted teams round-trip exactly.
## Goalies use the goalie group for the nibbles they share with skater ratings.

## The roster groups retail keeps: slots 0..G-1 goalies, then forwards, then defense.
enum Position { FORWARD, DEFENSE, GOALIE }
enum Hand { LEFT, RIGHT }

@export var full_name: String = ""
@export_range(0, 99, 1) var jersey_number: int = 0
@export var position: Position = Position.FORWARD
@export var handedness: Hand = Hand.LEFT
## Pounds: 140 + 8 per weight step (0-15), so 140-260.
@export_range(140.0, 260.0, 8.0) var weight_lbs: float = 188.0

@export_group("Ratings (25-99)")
@export_range(0.0, 100.0, 1.0) var agility: float = 54.0
@export_range(0.0, 100.0, 1.0) var speed: float = 54.0
@export_range(0.0, 100.0, 1.0) var offensive_awareness: float = 54.0
@export_range(0.0, 100.0, 1.0) var defensive_awareness: float = 54.0
@export_range(0.0, 100.0, 1.0) var shot_power: float = 54.0
@export_range(0.0, 100.0, 1.0) var checking: float = 54.0
## Fgt, 0-100 on the fight patch's scale (nibble * 100 / 7, see fight_display). Not
## shown on the retail roster screens; the fight engine reads it ($74).
@export_range(0.0, 100.0, 1.0) var fighting: float = 0.0
@export_range(0.0, 100.0, 1.0) var stick_handling: float = 54.0
@export_range(0.0, 100.0, 1.0) var shot_accuracy: float = 54.0
@export_range(0.0, 100.0, 1.0) var endurance: float = 54.0
## Shot / pass bias (spodds $70). Not shown on the retail screens.
@export_range(0.0, 100.0, 1.0) var shot_bias: float = 43.0
@export_range(0.0, 100.0, 1.0) var pass_accuracy: float = 54.0
@export_range(0.0, 100.0, 1.0) var aggressiveness: float = 54.0

@export_group("Goalie (25-99)")
## Shot power's nibble for goalies ($6C).
@export_range(0.0, 100.0, 1.0) var puck_control: float = 54.0
## Endurance's nibble ($72, GSSright).
@export_range(0.0, 100.0, 1.0) var stick_right: float = 54.0
## Shot bias's nibble ($70, GSSleft).
@export_range(0.0, 100.0, 1.0) var stick_left: float = 54.0
## Pass accuracy's nibble ($6E, GGSright).
@export_range(0.0, 100.0, 1.0) var glove_right: float = 54.0
## Aggressiveness's nibble ($73, GGSleft).
@export_range(0.0, 100.0, 1.0) var glove_left: float = 54.0

## Roster-screen value of a nibble with hot/cold 0.
static func display_value(n: int) -> int:
	var v := 18 * n
	if v >= 100:
		return 99
	if v < 50:
		return (v >> 1) + 25
	return v

## The nibble 0-6 whose screen value is nearest r (ties go to the lower nibble).
static func nibble_of(r: float) -> int:
	var best := 0
	var best_d := INF
	for n in 7:
		var d := absf(display_value(n) - r)
		if d < best_d:
			best = n
			best_d = d
	return best

## The fight patch's Fgt column (fgtdisp): (H/F & $E) * 100 / 14, no curve. Fight
## nibbles run 0-7 (the patched rosters use 7).
static func fight_display(n: int) -> int:
	return (2 * n * 100) / 14

## The fight nibble 0-7 whose Fgt value is nearest r.
static func fight_nibble_of(r: float) -> int:
	var best := 0
	var best_d := INF
	for n in 8:
		var d := absf(fight_display(n) - r)
		if d < best_d:
			best = n
			best_d = d
	return best

func is_goalie() -> bool:
	return position == Position.GOALIE

## Weight step 0-15.
func weight_step() -> int:
	return clampi(roundi((weight_lbs - 140.0) / 8.0), 0, 15)

## The 8 roster bytes A0..A7 (docs/specs/data_attributes.md section 1.3).
func rom_bytes() -> PackedByteArray:
	var g := is_goalie()
	var a := PackedByteArray()
	a.resize(8)
	var j := clampi(jersey_number, 0, 99)
	a[0] = ((j / 10) << 4) | (j % 10)
	a[1] = (weight_step() << 4) | nibble_of(agility)
	a[2] = (nibble_of(speed) << 4) | nibble_of(offensive_awareness)
	a[3] = (nibble_of(defensive_awareness) << 4) | nibble_of(puck_control if g else shot_power)
	var hand := 1 if handedness == Hand.RIGHT else 0
	a[4] = (nibble_of(checking) << 4) | (fight_nibble_of(fighting) << 1) | hand
	a[5] = (nibble_of(stick_handling) << 4) | nibble_of(shot_accuracy)
	a[6] = (nibble_of(stick_right if g else endurance) << 4) | nibble_of(stick_left if g else shot_bias)
	a[7] = (nibble_of(glove_right if g else pass_accuracy) << 4) | nibble_of(glove_left if g else aggressiveness)
	return a

## CalcAttrib's nibble numbers of the Overall attributes (the form byte is 15 - n).
const OVERALL_NIBBLES := [12, 11, 10, 9, 8, 7, 5, 4, 3, 1]
const OVERALL_NIBBLES_GOALIE := [12, 9, 8, 3, 2, 1, 0]

## The retail Overall rating (CalcAttrib with the Overall weight lists, then AttribAdjust).
## `form` is the slot's 16 hot/cold bytes: the truncated mean of the bytes of the rated
## attributes is added (OvrDivisor / OvrDividend). Without it the form is 0.
func overall(form: PackedInt32Array = PackedInt32Array()) -> int:
	var raw: int
	if is_goalie():
		raw = (9 * nibble_of(agility)) / 2 + (9 * nibble_of(defensive_awareness)) / 2 \
				+ (9 * nibble_of(puck_control)) / 2 + nibble_of(stick_right) + nibble_of(stick_left) \
				+ nibble_of(glove_right) + nibble_of(glove_left)
	else:
		raw = 2 * nibble_of(agility) + 3 * nibble_of(speed) + 3 * nibble_of(offensive_awareness) \
				+ 2 * nibble_of(defensive_awareness) + nibble_of(shot_power) + 2 * nibble_of(checking) \
				+ 3 * nibble_of(stick_handling) + 2 * nibble_of(shot_accuracy) + nibble_of(endurance) \
				+ nibble_of(pass_accuracy)
	if form.size() >= 16:
		var ns: Array = OVERALL_NIBBLES_GOALIE if is_goalie() else OVERALL_NIBBLES
		var sum := 0
		for n in ns:
			sum += form[15 - n]
		raw += int(sum / float(ns.size())) if sum >= 0 else -int(-sum / float(ns.size()))
	if raw >= 100:
		return 99
	if raw < 50:
		return (raw >> 1) + 25
	return raw
