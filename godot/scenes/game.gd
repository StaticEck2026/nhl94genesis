extends HockeyGame
## The match scene. Builds the views from Sim.match: 12 skaters (goalie + 5 per side),
## the puck, the rink, the camera, the HUD and the pause menu.

const SKATER_SCENE := preload("res://scenes/skater.tscn")
const SETUP_SCENE := "res://ui/setup_screen.tscn"

## Temporary center-ice lineup (role, x, y for a team attacking up) until puckfaceoff2's
## tables are ported. Retail roles: 0 G, 1 LD, 2 RD, 3 LW, 4 C, 5 RW.
const TEMP_LINEUP := [
	[SimObject.POS_GOALIE, 0, -250], [SimObject.POS_LD, -40, -70], [SimObject.POS_RD, 40, -70],
	[SimObject.POS_LW, -50, -20], [SimObject.POS_C, 0, -12], [SimObject.POS_RW, 50, -20],
]

var skaters: Array[Skater2D] = []

func _ready() -> void:
	var m: MatchConfig = Sim.match
	var ports := {}
	for team in 2:
		var data: TeamData = m.home_team if team == 0 else m.away_team
		var attack_top := team == 0
		var driver: MatchConfig.Driver = m.home_control if team == 0 else m.away_control
		for slot in 6:
			var row: Array = TEMP_LINEUP[slot]
			var sk: Skater2D = SKATER_SCENE.instantiate()
			sk.index = team * 6 + slot
			sk.role = row[0]
			sk.attacking_top = attack_top
			var y: int = row[2] if attack_top else -row[2]
			var x: int = row[1] if attack_top else -row[1]
			sk.position = Nhl94Units.rink_to_godot(Vector2(x, y))
			sk.player = _player_for(data, row[0])
			add_child(sk)
			skaters.append(sk)
			# The pad drives the center until player switching is ported.
			if driver != MatchConfig.Driver.CPU and row[0] == SimObject.POS_C:
				ports[sk.index] = 1 if driver == MatchConfig.Driver.PAD1 else 2
	pad_ports = ports
	# Start both lines the way a faceoff does (forcepldata): positions, assignments and
	# the centre chasing the puck. CPU players then run on the AI.
	for sk in skaters:
		sk.obj.newpos = sk.role
		sk.obj.newpnum = sk.index % 6
	world.forcepldata(0)
	world.forcepldata(1)
	world.drop_puck(Vector2i.ZERO)
	($Hud as Node).call("bind", self)
	($PauseMenu as Node).connect("quit_requested", func() -> void: get_tree().change_scene_to_file(SETUP_SCENE))

func _player_for(data: TeamData, role: int) -> PlayerData:
	if data == null:
		return null
	for p in data.players:
		var want := PlayerData.Position.GOALIE if role == SimObject.POS_GOALIE else -1
		if want >= 0 and p.position == want:
			return p
	return null
