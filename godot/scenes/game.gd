extends HockeyGame
## The match scene. One view per sort object; the rules run the game from the opening
## faceoff (StartGame) to the final horn. Options come from Sim.match; run directly it
## plays the first two teams with the setup screen's default controls.

const SKATER_SCENE := preload("res://scenes/skater.tscn")
const SETUP_SCENE := "res://ui/game_setup.tscn"
## OptPerlen by period length in minutes (ClockLength _timetab: 5, 10, 20 minutes).
const PERLEN := {5: 0, 10: 1, 20: 2}
## A CPU-only intermission waits this long (Intermission's waitxsr(480)).
const CPU_INTERMISSION_FRAMES := 480

var skaters: Array[Skater2D] = []
var _hold_frames := 0
var _over := false
var _quitting := false

func _enter_tree() -> void:
	auto_place = false
	super._enter_tree()
	# Teams first: the rink and the views build their palettes from them in _ready.
	var m: MatchConfig = Sim.match
	if m.home_team == null or m.away_team == null:
		var teams := MatchConfig.available_teams(m.edition)
		if teams.size() >= 2:
			m.home_team = teams[0]
			m.away_team = teams[1]
	world.roster.setup_teams(m.home_team, m.away_team)

func _ready() -> void:
	# In play the Genesis is in H32 (256 x 224).
	ScreenMode.set_h32(get_tree(), true)
	var m: MatchConfig = Sim.match
	for i in 12:
		var sk: Skater2D = SKATER_SCENE.instantiate()
		sk.index = i
		add_child(sk)
		skaters.append(sk)
	add_object_views()
	world.opt_perlen = m.perlen if m.perlen >= 0 else PERLEN.get(m.period_minutes, 0)
	# The menus' music stops: the game opens with AllSndOff and the intermission song.
	if Sim.menu_sfx:
		Sim.menu_sfx.stop_all()
	world.opt_pen = m.penalties
	world.opt_offsides = m.offsides
	world.opt_line_on = m.line_changes
	world.no_fatigue = m.line_changes and m.auto_lines
	world.auto_goalie = [m.auto_goalie, m.auto_goalie]
	world.opt_fight = m.opt_fight()
	# FigureJoy: each pad's team.
	world.cont_team = m.pad_teams()
	world.rules.intermission.connect(_on_intermission)
	world.rules.game_over.connect(_on_game_over)
	($Hud as Node).call("bind", self)
	($PauseMenu as Node).connect("quit_requested", _quit)
	($PauseMenu as Node).connect("intermission_closed", _release)
	if m.shootout:
		# GameSetUp with OptPlayMode 4: the shootout flag and sub_FC47C.
		world.f_c2fa |= HockeyWorld.C2FA_SHOOTOUT
		world.shootout.init_shootout()
	world.rules.init_other_games(MatchConfig.available_teams(m.edition))
	if m.form.size() == 2:
		world.roster.preset_form = m.form
	world.rules.start_game()
	world.stats[0].line = clampi(m.home_line, 0, 6)
	world.stats[1].line = clampi(m.away_line, 0, 6)

func _human() -> bool:
	return world.cont_team != PackedInt32Array([0, 0, 0, 0])

## Intermission (L47614), the pre-game one included: the side view and the menu for
## this point of the game; the sim holds until row 0 or Start (or a while, with no human
## playing).
func _on_intermission(gsp: int) -> void:
	hold = true
	_hold_frames = CPU_INTERMISSION_FRAMES
	world.begin_intermission()
	($PauseMenu as Node).call("open_intermission", gsp)

## The end of the game: the final intermission ("Exit Game" goes back to the setup).
func _on_game_over() -> void:
	_over = true
	hold = true
	_hold_frames = CPU_INTERMISSION_FRAMES
	if not world.intermission:
		world.begin_intermission()
	($PauseMenu as Node).call("open_intermission", 4, true)

func _physics_process(delta: float) -> void:
	if hold and not _human():
		_hold_frames -= 1
		if _hold_frames <= 0:
			($PauseMenu as Node).call("close")
			_release()
	if _quitting:
		return
	if not hold and not _human() and _demoread():
		return
	super._physics_process(delta)

## demoread (L30159), each loop of a game nobody plays (the demo, or CPU against CPU):
## Start on any pad pauses (PauseMenu), any other new press goes back to the menus
## (loc_172E4: Opening2; the menus start song $78).
func _demoread() -> bool:
	for k in 4:
		for b in ["up", "down", "left", "right", "a", "b", "c"]:
			if Input.is_action_just_pressed("p%d_%s" % [k + 1, b]):
				_quit()
				return true
	return false

func _release() -> void:
	if not hold:
		return
	if _over:
		hold = false
		_quit()
		return
	world.end_intermission()
	hold = false

func _exit_tree() -> void:
	ScreenMode.restore(get_tree())
	super._exit_tree()

func _quit() -> void:
	if _quitting or not is_inside_tree():
		return
	_quitting = true
	get_tree().change_scene_to_file(SETUP_SCENE)
