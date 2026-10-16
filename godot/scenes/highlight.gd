class_name HighlightGame
extends HockeyGame
## A highlight from another game (sub_1354C L48180; spec docs/specs/playoffs_records.md
## §5.3): during an intermission a close game of the night is played live, CPU against
## CPU, from its third period (or overtime) with 60-179 seconds on the clock. The
## players start from unk_1387C, play is live at once, and the clip ends 180 loops after
## the first stoppage (a goal or any whistle), or at a press of C or Start, which breaks
## a tie with a goal for a random side. The intermission's game is held meanwhile
## (retail saves its RAM and restores it; the port runs this world beside it).

signal finished(score1: int, score2: int)

const SKATER_SCENE := preload("res://scenes/skater.tscn")
## unk_1387C: the start by position code (G, LD, RD, LW, C, RW), first for the team
## attacking the top end, then for the other.
const START := [[0, -240], [-70, -140], [20, -110], [-100, -60], [25, -40], [70, -80],
	[0, 240], [34, 90], [-55, 80], [100, 40], [-10, 10], [-50, 0]]
const AFTER_STOP := 0xB4

## Set before the node enters the tree.
var team1: TeamData
var team2: TeamData
var period := 2
var score := [0, 0]
var clock := 60
var _after := AFTER_STOP
var _done := false

func _enter_tree() -> void:
	auto_place = false
	super._enter_tree()
	world.roster.setup_teams(team1, team2)

func _ready() -> void:
	for i in 12:
		var sk: Skater2D = SKATER_SCENE.instantiate()
		sk.index = i
		add_child(sk)
	add_object_views()
	var w := world
	for st in w.stats:
		st.clear_game()
	w.roster.new_game_form()
	w.gsp = period
	# gmode $10, bit 1 when the period number is odd (the ends switch each period).
	w.gmode = HockeyWorld.GM_HL | (HockeyWorld.GM_DIR if period & 1 else 0)
	w.setupice()
	for team in 2:
		var st := w.stats[team]
		w.roster.copy_lines(team)
		for k in 6:
			var o := w.objects[st.first_object + k]
			o.newpos = k
			o.newpnum = st.ram_lines[k] - 1 if k < st.ram_lines.size() else -1
		w.forcepldata(team)
	for i in 12:
		var o := w.objects[i]
		if o.position < 0:
			continue
		var p: Array = START[clampi(o.position, 0, 5) + (0 if o.attacking_top() else 6)]
		o.set_pos(Vector2i(p[0], p[1]))
		o.vel = Vector2i.ZERO
	w.puck().set_pos(Vector2i.ZERO)
	# The stalled-puck count, as a drop leaves it ($78 loops).
	w.puck().temp[1] = 0x78
	w.stats[0].goals = score[0]
	w.stats[1].goals = score[1]
	w.rules.reset_clock()
	w.gameclock = clock
	w.gmode &= ~HockeyWorld.GM_CLOCK
	w.cont_team = PackedInt32Array([0, 0, 0, 0])
	var hud := get_node_or_null("Hud")
	if hud:
		hud.call("bind", self)

func _physics_process(delta: float) -> void:
	if _done:
		return
	super._physics_process(delta)
	for k in 4:
		var p := "p%d_" % (k + 1)
		if Input.is_action_just_pressed(p + "c") or Input.is_action_just_pressed(p + "start"):
			# A press ends the clip; a tie goes to a side by the VDP counter's bit 0.
			if world.stats[0].goals == world.stats[1].goals:
				world.stats[randi() & 1].goals += 1
			_finish()
			return
	if world.gmode & HockeyWorld.GM_CLOCK:
		_after -= 1
		if _after < 0:
			_finish()

func _finish() -> void:
	_done = true
	finished.emit(world.stats[0].goals, world.stats[1].goals)
