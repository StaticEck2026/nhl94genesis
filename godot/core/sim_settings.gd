@tool
class_name SimSettings
extends Resource
## Live tuning and module toggles. The game reads one shared instance (Sim.settings).
## The debug dock edits the same resource. Defaults are the retail values.

static var _fallback: SimSettings

## The Sim autoload's settings, or a default instance when the autoload is not running
## (headless tests, editor previews).
static func shared(from: Node) -> SimSettings:
	var sim: Node = from.get_node_or_null("/root/Sim") if from != null and from.is_inside_tree() else null
	if sim != null:
		return sim.get("settings")
	if _fallback == null:
		_fallback = SimSettings.new()
	return _fallback

@export_group("Global")
## Scales delta for the whole simulation. 1.0 is retail speed.
@export_range(0.1, 3.0, 0.05) var game_speed: float = 1.0:
	set(v): game_speed = v; emit_changed()

@export_group("Modules")
## CPU skater AI (the positional routines, assnearest, the CPU carrier). Off: CPU
## skaters glide to a stop.
@export var enable_skater_ai: bool = true:
	set(v): enable_skater_ai = v; emit_changed()
## CPU goalie AI (assgoaliecpu, assgoalietopuck). Off: goalies glide to a stop.
@export var enable_goalie_tracking: bool = true:
	set(v): enable_goalie_tracking = v; emit_changed()
## Checks and bumps (checkcoll, CheckingCalc).
@export var enable_body_collisions: bool = true:
	set(v): enable_body_collisions = v; emit_changed()
## Ice drag on the loose puck.
@export var enable_puck_friction: bool = true:
	set(v): enable_puck_friction = v; emit_changed()
## Turning inertia. Off makes skaters snap to the stick direction.
@export var enable_momentum: bool = true:
	set(v): enable_momentum = v; emit_changed()

@export_group("Skating")
## dirtab run speed, retail velocity units ($C8).
@export_range(50.0, 400.0, 1.0) var run_speed: float = 200.0:
	set(v): run_speed = v; emit_changed()
## Max speed base: MaxSpeed[i] = ((i + base) * step)^2.
@export_range(0.0, 40.0, 1.0) var max_speed_base: float = 20.0:
	set(v): max_speed_base = v; emit_changed()
## Max speed step per index, retail velocity units.
@export_range(100.0, 500.0, 1.0) var max_speed_step: float = 275.0:
	set(v): max_speed_step = v; emit_changed()
## Skate drag per loop: vel -= vel / 2^shift. 6 is retail (1/64).
@export_range(3, 12, 1) var skate_drag_shift: int = 6:
	set(v): skate_drag_shift = v; emit_changed()
## Drag shift while receiving a pass, and for a normal puck (pfdoff).
@export_range(3, 12, 1) var glide_drag_shift: int = 9:
	set(v): glide_drag_shift = v; emit_changed()
## stopna deceleration per call, retail velocity units ($96).
@export_range(0.0, 600.0, 1.0) var stop_decel: float = 150.0:
	set(v): stop_decel = v; emit_changed()
## Turn rate when standing, facing units per loop before the x16 (doplayeracc $300).
## $300 is 0.1875 of a 45 degree step, about 8.4 degrees per loop.
@export_range(64, 2048, 1) var turn_rate_standing: int = 0x300:
	set(v): turn_rate_standing = v; emit_changed()
## Lowest turn rate at speed (doplayeracc $180), about 4.2 degrees per loop.
@export_range(32, 2048, 1) var turn_rate_floor: int = 0x180:
	set(v): turn_rate_floor = v; emit_changed()
## Multiplier on the doplayeracc turn step. 1.0 is retail.
@export_range(0.1, 4.0, 0.05) var turn_rate_scale: float = 1.0:
	set(v): turn_rate_scale = v; emit_changed()

@export_group("Fatigue")
## Energy drained per drain tick (playeracc subi #$21). Full energy is $1000.
@export_range(0.0, 200.0, 1.0) var energy_drain: float = 33.0:
	set(v): energy_drain = v; emit_changed()
## A playeracc call drains on 1 in this many calls. Retail gates on the H counter's low
## 7 bits (1 in 128 nominal; 86-106 on hardware timing).
@export_range(1, 1024, 1) var energy_drain_gate: int = 128:
	set(v): energy_drain_gate = v; emit_changed()
## Energy a benched player regains per game second (periodiceevents loc_79F8).
@export_range(0, 200, 1) var bench_recovery: int = 9:
	set(v): bench_recovery = v; emit_changed()

@export_group("Puck")
## Shot power multiplier. 1.0 is retail.
@export_range(0.1, 3.0, 0.05) var shot_power_scale: float = 1.0:
	set(v): shot_power_scale = v; emit_changed()
## Pass velocity multiplier. 1.0 is retail.
@export_range(0.1, 3.0, 0.05) var pass_speed_scale: float = 1.0:
	set(v): pass_speed_scale = v; emit_changed()
## Pass reception window in retail frames.
@export_range(0.0, 60.0, 1.0) var pass_receive_frames: float = 8.0:
	set(v): pass_receive_frames = v; emit_changed()
## Fraction of the gap to the carrier hot spot closed per loop (pucknorm asr #2).
@export_range(0.05, 1.0, 0.05) var carrier_bungee: float = 0.25:
	set(v): carrier_bungee = v; emit_changed()

@export_group("Checking")
## Check impulse multiplier. 1.0 is retail.
@export_range(0.0, 3.0, 0.05) var check_force_scale: float = 1.0:
	set(v): check_force_scale = v; emit_changed()

@export_group("Goalie")
## Extra frames between CPU goalie decisions (retail reloads aidef / 4). 0 is retail.
@export_range(0.0, 30.0, 1.0) var goalie_reaction_frames: float = 0.0:
	set(v): goalie_reaction_frames = v; emit_changed()

@export_group("Overlay")
## Tactical grid (columns across, rows up the ice).
@export var show_grid: bool = true:
	set(v): show_grid = v; emit_changed()
@export_range(1, 16, 1) var grid_columns: int = 5:
	set(v): grid_columns = v; emit_changed()
@export_range(1, 16, 1) var grid_rows: int = 9:
	set(v): grid_rows = v; emit_changed()
## Lines from the puck to both posts of each net, and the goalie's angle.
@export var show_goalie_cones: bool = true:
	set(v): show_goalie_cones = v; emit_changed()
## Lanes from the puck carrier to teammates, with interception radii on opponents.
@export var show_pass_lanes: bool = true:
	set(v): show_pass_lanes = v; emit_changed()
## Interception radius drawn around opponents, px.
@export_range(4.0, 64.0, 1.0) var interception_radius: float = 16.0:
	set(v): interception_radius = v; emit_changed()

