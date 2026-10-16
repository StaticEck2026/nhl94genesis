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
var _palette: Texture2D
var _palette_side: Texture2D

signal stepped

func _enter_tree() -> void:
	world = HockeyWorld.new(SimSettings.shared(self), seed)
	world.rules_active = run_rules
	sfx = SfxBank.new()
	sfx.name = "Sfx"
	add_child(sfx)
	world.sound.connect(sfx.play)
	world.song.connect(sfx.play_song)

func _exit_tree() -> void:
	if world:
		world.dispose()

func _physics_process(delta: float) -> void:
	if hold:
		# The intermission's waitxsr steps the zamboni and the crowd every vblank.
		if world.intermission:
			_frame_accum += Nhl94Units.frames(delta * world.settings.game_speed)
			while _frame_accum >= 1.0:
				_frame_accum -= 1.0
				world.intermission_vblank()
		else:
			_frame_accum = 0.0
		stepped.emit()
		return
	_frame_accum += Nhl94Units.frames(delta * world.settings.game_speed)
	var d7 := maxi(world.settings.loop_vblanks, 1)
	while _frame_accum >= d7:
		_frame_accum -= d7
		_read_pads()
		world.step(d7)
	if world.rules_active:
		sfx.set_crowd_attenuation(world.rules.crowd_attenuation())
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
	for k in 4:
		if world.cont_team[k] != 0:
			world.pads[k].held = PadInput.held_bits(k + 1)

## The HockeyGame a node belongs to, or null.
static func find(n: Node) -> HockeyGame:
	var p := n.get_parent()
	while p != null and not (p is HockeyGame):
		p = p.get_parent()
	return p as HockeyGame

## Team numbers whose uniforms fill palette lines 2 and 3 (Boston and Montreal when no
## team data is loaded, as in the sandbox).
func palette_teams() -> Vector2i:
	var h := world.stats[0].team_index
	var a := world.stats[1].team_index
	return Vector2i(h if h >= 0 else 1, a if a >= 0 else 11)

## The game's CRAM (rink lines, home and away uniforms) as a palette texture.
func palette_texture(side: bool = false) -> Texture2D:
	var t := palette_teams()
	if side:
		if _palette_side == null:
			_palette_side = PaletteBank.texture(t.x, t.y, "side")
		return _palette_side
	if _palette == null:
		_palette = PaletteBank.texture(t.x, t.y)
	return _palette

## A palette material for index art; away objects take line 3 for line 2.
func palette_material(away: bool) -> ShaderMaterial:
	return PaletteBank.material(palette_texture(), away)

## Rebuild the palette after the teams change.
func refresh_palette() -> void:
	_palette = null
	_palette_side = null

## Views for the nets, the puck shadow and the puck (in that order, so the puck draws
## over its shadow when they share a screen row), the arena's crowd, box, background
## animation and zamboni, the fight patch's gloves (over the arena at the same z) and
## the indicators.
func add_object_views() -> void:
	for i in [HockeyWorld.NET_TOP, HockeyWorld.NET_BOTTOM, HockeyWorld.SHADOW, HockeyWorld.PUCK]:
		var v := SortObjectView.new()
		v.name = "Object%d" % i
		v.index = i
		add_child(v)
	var av := ArenaView.new()
	av.name = "Arena"
	add_child(av)
	var gv := GlovesView.new()
	gv.name = "Gloves"
	add_child(gv)
	var iv := IndicatorsView.new()
	iv.name = "Indicators"
	add_child(iv)
