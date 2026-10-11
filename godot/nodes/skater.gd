@tool
class_name Skater2D
extends CharacterBody2D
## A skater on the ice. Retail logic owns the motion: position is the retail 16.16 long,
## velocity is rvu, and each physics tick runs whole retail loops (d7 = 1 each) in the
## updateplayers order: drag and move, steer and accelerate, then board check.
## Node position is retail position with Y flipped (Nhl94Units.rink_to_godot).

signal hit_boards(normal: Vector2, hard: bool)

@export var player: PlayerData
## Pad port, 1 or 2. 0 leaves the skater to `ai_joy`.
@export_range(0, 2, 1) var port: int = 0
## $62 bit 7. Attacking the goal at the top of the rink.
@export var attacking_top: bool = true
## Wall collision radius ($4A, $4C). defaultsprites2 gives skaters (8, 4).
@export var wall_radius: Vector2i = Vector2i(8, 4)
## Stick direction used when port is 0. 0-7 or SkaterSteering.JOY_NONE.
var ai_joy: int = SkaterSteering.JOY_NONE
## Puck position in retail coordinates, set by the game. Used for backwards skating.
var puck_retail: Vector2i = Vector2i.ZERO
## Puck Y velocity in rvu, for the backwards-skating lookahead.
var puck_vel_y: int = 0
var has_puck: bool = false

## Placeholder length of one-shot animations (stop, turn) in retail frames, until the
## SPA tables (SetSPA, updateanim) are ported.
const ONE_SHOT_FRAMES := 12

var pos_fx: Vector2i = Vector2i.ZERO
var vel: Vector2i = Vector2i.ZERO
var wall_normal: Vector2i = Vector2i.ZERO
var steer_state := SkaterSteering.State.new()
var fsm := PlayerFSM.new()

var _settings: SimSettings
var _motion: SkaterMotion
var _steering: SkaterSteering
var _skater: SkaterMotion.Skater
var _frame_accum := 0.0
var _anim_frames := 0

func _ready() -> void:
	_sync_from_node()
	if not Engine.is_editor_hint():
		setup()

## Builds the logic objects. Runs from _ready, or on the first retail_loop when the node
## is driven directly (headless tests).
func setup() -> void:
	_settings = SimSettings.shared(self)
	var settings := _settings
	_motion = SkaterMotion.new(settings)
	_steering = SkaterSteering.new(settings)
	_skater = SkaterMotion.skater_from(player) if player else SkaterMotion.Skater.new()
	_skater.joypad = port > 0
	if not player:
		_skater.weight = 6
		_skater.agility = 15
		_skater.speed = 15

## Sets the retail position from the node position (used at start and after a teleport).
func _sync_from_node() -> void:
	var r := Nhl94Units.rink_to_godot(position)
	pos_fx = Vector2i(roundi(r.x * 65536.0), roundi(r.y * 65536.0))

func retail_pos() -> Vector2i:
	return Vector2i(pos_fx.x >> 16, pos_fx.y >> 16)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_frame_accum += Nhl94Units.frames(delta * _settings.game_speed)
	while _frame_accum >= 1.0:
		_frame_accum -= 1.0
		retail_loop()
	var p := Vector2(pos_fx) / 65536.0
	position = Nhl94Units.rink_to_godot(p)
	velocity = Nhl94Units.rink_to_godot(Vector2(vel)) * Nhl94Units.VEL_STEP * Nhl94Units.RETAIL_HZ / Nhl94Units.FIXED_ONE
	queue_redraw()

## One retail loop with d7 = 1.
func retail_loop() -> void:
	if _motion == null:
		setup()
	var old_pos := retail_pos()
	_skater.has_puck = has_puck
	# updateplayers: drag, then move. pfdoff (pass receive) is not wired yet.
	vel = _motion.apply_drag(vel)
	pos_fx += vel * int(Nhl94Units.VEL_STEP)
	# Assignment / doinput: steer and push.
	var joy := PadInput.direction(port) if port > 0 else ai_joy
	var ctx := SkaterSteering.Context.new()
	ctx.vel = vel
	ctx.has_puck = has_puck
	ctx.y = retail_pos().y
	ctx.to_puck = Vector2i(puck_retail.x - retail_pos().x, puck_retail.y + (puck_vel_y >> 8) - retail_pos().y)
	ctx.attacking_top = attacking_top
	var r := _steering.steer(steer_state, joy, ctx)
	match r.action:
		SkaterSteering.Action.ACCEL:
			vel = _motion.apply_accel(_skater, vel, _motion.dirtab(r.accel_dir), 1, wall_normal)
		SkaterSteering.Action.STOP:
			vel = _motion.apply_stop(vel)
	_tick_anim()
	# Clear wallcos/wallsin, then checkcoll if the skater moved.
	wall_normal = Vector2i.ZERO
	var now := retail_pos()
	if now != old_pos:
		var n := RinkBoards.board_normal(now, wall_radius)
		if n != Vector2i.ZERO:
			var hit := RinkBoards.bounce_skater(vel, n)
			vel = hit.vel
			wall_normal = hit.normal
			hit_boards.emit(Nhl94Units.rink_to_godot(Vector2(n) / 256.0), hit.hard)
	fsm.tick(1.0)
	_update_fsm()

func _tick_anim() -> void:
	if steer_state.anim_restarted and steer_state.anim_busy:
		_anim_frames = ONE_SHOT_FRAMES
	if _anim_frames > 0:
		_anim_frames -= 1
		if _anim_frames == 0:
			steer_state.anim_busy = false

func _update_fsm() -> void:
	var want := PlayerFSM.State.IDLE
	match steer_state.anim:
		SkaterSteering.Anim.STOP:
			want = PlayerFSM.State.STOPPING
		SkaterSteering.Anim.TURN_LEFT, SkaterSteering.Anim.TURN_RIGHT:
			want = PlayerFSM.State.TURNING
		SkaterSteering.Anim.GLIDE, SkaterSteering.Anim.GLIDE_BACK:
			want = PlayerFSM.State.IDLE if vel == Vector2i.ZERO else PlayerFSM.State.SKATING
		_:
			want = PlayerFSM.State.SKATING
	if want != fsm.state and not fsm.enter(want):
		# Route through SKATING when the direct move is not allowed (for example TURNING to IDLE).
		if fsm.enter(PlayerFSM.State.SKATING):
			fsm.enter(want)

func _draw() -> void:
	var color := Color(0.85, 0.2, 0.2) if attacking_top else Color(0.2, 0.35, 0.9)
	draw_circle(Vector2.ZERO, 5.0, color)
	var facing := Vector2.UP.rotated(steer_state.facing_angle())
	draw_line(Vector2.ZERO, facing * 10.0, Color(0.1, 0.1, 0.15), 1.0)
	if not Engine.is_editor_hint():
		draw_line(Vector2.ZERO, velocity * 0.1, Color(1, 1, 0, 0.8), 1.0)
