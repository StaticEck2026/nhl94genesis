class_name HockeyGame
extends Node2D
## Owns the HockeyWorld and steps it in whole retail loops. Reads the pads into the
## world's stick inputs and keeps one view node per sort object in sync.
## Child views find the world through `game.world`.

## Pad port per object index (0 = none). Set by the setup screen or the scene.
@export var pad_ports: Dictionary = {}
## RNG seed. Retail seeds from the VDP counter; a fixed seed makes games replayable.
@export var seed: int = 0x00500000

var world: HockeyWorld
var sfx: SfxBank
var _frame_accum := 0.0

signal stepped

func _enter_tree() -> void:
	world = HockeyWorld.new(SimSettings.shared(self), seed)
	sfx = SfxBank.new()
	sfx.name = "Sfx"
	add_child(sfx)
	world.sound.connect(sfx.play)

func _exit_tree() -> void:
	if world:
		world.dispose()

func _physics_process(delta: float) -> void:
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
		world.pads[k].held = PadInput.held_bits(port)
