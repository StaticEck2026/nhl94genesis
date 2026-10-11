extends CanvasLayer
## Score, period and clock. Reads HockeyWorld.game_state once rules are ported; until
## then it shows what the world has.

@onready var _label: Label = %Scoreboard
var game: HockeyGame

func bind(p_game: HockeyGame) -> void:
	game = p_game
	game.stepped.connect(_refresh)

func _refresh() -> void:
	var w := game.world
	var home := Sim.match.home_team.abbreviation if Sim.match.home_team else "HOME"
	var away := Sim.match.away_team.abbreviation if Sim.match.away_team else "AWAY"
	var secs := w.clock_seconds()
	var period := "OT" if w.gsp == 3 else "P%d" % (mini(w.gsp, 2) + 1)
	_label.text = "%s %d  %s %d   %s  %d:%02d" % [home, w.score(0), away, w.score(1), period, secs / 60, secs % 60]
