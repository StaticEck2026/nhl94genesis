class_name HockeyGame
extends Node2D
## Owns the HockeyWorld and steps it in whole retail loops. Reads the pads into the
## world's stick inputs and keeps one view node per sort object in sync.
## Child views find the world through `game.world`.

## Sandbox: pad port per object index (0 = none). A match uses `cont_team` instead and
## the rules hand each pad its player at every faceoff.
@export var pad_ports: Dictionary = {}
## RNG seed. Retail seeds from the VDP counter; a fixed seed makes games replayable.
@export var seed: int = 0x00500000
## Views place their objects themselves (sandbox). A match lets the rules do it.
@export var auto_place: bool = true
## Whistles, faceoffs, penalties and the clock. The skating sandbox turns them off.
@export var run_rules: bool = true

var world: HockeyWorld
var sfx: SfxBank
var _frame_accum := 0.0
## While set the simulation does not step (intermissions, the end of the game).
var hold: bool = false

signal stepped

func _enter_tree() -> void:
	world = HockeyWorld.new(SimSettings.shared(self), seed)
	world.rules_active = run_rules
	sfx = SfxBank.new()
	sfx.name = "Sfx"
	add_child(sfx)
	world.sound.connect(sfx.play)

func _exit_tree() -> void:
	if world:
		world.dispose()

func _physics_process(delta: float) -> void:
	if hold:
		_frame_accum = 0.0
		stepped.emit()
		return
	_frame_accum += Nhl94Units.frames(delta * world.settings.game_speed)
	while _frame_accum >= 1.0:
		_frame_accum -= 1.0
		_read_pads()
		world.step(1)
	stepped.emit()

## Gives pad k (port k + 1) object `index` and its team.
func assign_pad(k: int, index: int) -> void:
	var o := world.objects[index]
	world.cont_team[k] = 2 if o.away() else 1
	world.set_c_player(k, o)

func _read_pads() -> void:
	for i in pad_ports:
		var port: int = pad_ports[i]
		var k := port - 1
		if k < 0 or k > 1:
			continue
		if world.cont_team[k] == 0:
			assign_pad(k, i)
	for k in 2:
		if world.cont_team[k] != 0:
			world.pads[k].held = PadInput.held_bits(k + 1)
