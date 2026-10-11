extends HockeyGame
## The match scene. One view per sort object; the rules run the game from the opening
## faceoff (StartGame) to the final horn. Options come from Sim.match; run directly it
## plays the first two teams with the setup screen's default controls.

const SKATER_SCENE := preload("res://scenes/skater.tscn")
const SETUP_SCENE := "res://ui/setup_screen.tscn"
## OptPerlen by period length in minutes (ClockLength _timetab: 5, 10, 20 minutes).
const PERLEN := {5: 0, 10: 1, 20: 2}
## A CPU-only intermission waits this long (Intermission's waitxsr(480)).
const CPU_INTERMISSION_FRAMES := 480

var skaters: Array[Skater2D] = []
var _hold_frames := 0
var _over := false

func _enter_tree() -> void:
	auto_place = false
	super._enter_tree()
	# Teams first: the rink and the views build their palettes from them in _ready.
	var m: MatchConfig = Sim.match
	if m.home_team == null or m.away_team == null:
		var teams := MatchConfig.available_teams()
		if teams.size() >= 2:
			m.home_team = teams[0]
			m.away_team = teams[1]
	world.roster.setup_teams(m.home_team, m.away_team)

func _ready() -> void:
	var m: MatchConfig = Sim.match
	for i in 12:
		var sk: Skater2D = SKATER_SCENE.instantiate()
		sk.index = i
		add_child(sk)
		skaters.append(sk)
	add_object_views()
	world.opt_perlen = PERLEN.get(m.period_minutes, 0)
	world.opt_pen = m.penalties
	world.opt_offsides = m.offsides
	world.opt_line_on = m.line_changes
	world.cont_team[0] = 0
	world.cont_team[1] = 0
	_take_pad(m.home_control, 1)
	_take_pad(m.away_control, 2)
	world.rules.intermission.connect(_on_intermission)
	world.rules.game_over.connect(_on_game_over)
	($Hud as Node).call("bind", self)
	($PauseMenu as Node).connect("quit_requested", _quit)
	if m.shootout:
		# GameSetUp with OptPlayMode 4: the shootout flag and sub_FC47C.
		world.f_c2fa |= HockeyWorld.C2FA_SHOOTOUT
		world.shootout.init_shootout()
	world.rules.start_game()
	world.stats[0].line = clampi(m.home_line, 0, 6)
	world.stats[1].line = clampi(m.away_line, 0, 6)

func _take_pad(driver: MatchConfig.Driver, team: int) -> void:
	match driver:
		MatchConfig.Driver.PAD1:
			world.cont_team[0] = team
		MatchConfig.Driver.PAD2:
			world.cont_team[1] = team

func _human() -> bool:
	return world.cont_team[0] != 0 or world.cont_team[1] != 0

## Intermission: the sim holds until Start (or a while, with no human playing).
func _on_intermission(gsp: int) -> void:
	if gsp == 0:
		return
	hold = true
	_hold_frames = CPU_INTERMISSION_FRAMES

func _on_game_over() -> void:
	_over = true
	hold = true
	_hold_frames = CPU_INTERMISSION_FRAMES

func _physics_process(delta: float) -> void:
	if hold and not _human():
		_hold_frames -= 1
		if _hold_frames <= 0:
			_release()
	super._physics_process(delta)

func _unhandled_input(event: InputEvent) -> void:
	if not hold:
		return
	if event.is_action_pressed("p1_start") or event.is_action_pressed("p2_start"):
		get_viewport().set_input_as_handled()
		_release()

func _release() -> void:
	if _over:
		_quit()
		return
	hold = false

func _quit() -> void:
	get_tree().change_scene_to_file(SETUP_SCENE)
