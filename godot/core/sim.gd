extends Node
## Autoload. Holds the shared SimSettings instance.

const SETTINGS_PATH := "res://core/sim_settings.tres"

var settings: SimSettings
## Set by the setup screen before the game scene loads.
var match: MatchConfig = MatchConfig.new()
## The Game Setup options at $FFD048 (LoadDefMenuOptions: defmenuoptions L54847). They
## survive Opening2, so a game comes back to the menu as it was left: Play Mode, Players,
## Team 1, Team 2, Per. Length, Goalies, User Records, Penalties, Line Changes.
var options := PackedInt32Array([0, 1, 11, 10, 1, 0, 1, 0, 1])
## TmpOptUserRec / TmpOptPen / TmpOptLine: what Shootout overrode (GameSetUp_3).
var shootout_saved := PackedInt32Array()
## demoflag clear: the next Game Setup re-rolls both teams (GameSetUp L960200).
var demo_played := false
## The rest of the league and the playoff tree (retail rebuilds it at each Game Setup),
## the battery save, and the menus' RNG (retail seeds it from the HV counter).
var league := League.new()
var sram: Sram
var menu_rng := RetailRng.new(randi())
## Where the bracket screen goes next: Matchups before a game, Game Setup after one.
var bracket_next_matchups := true
## The menus' music (the title's $78 plays on into Game Setup; Matchups' $7A).
var menu_sfx: SfxBank

func _enter_tree() -> void:
	if ResourceLoader.exists(SETTINGS_PATH):
		settings = load(SETTINGS_PATH) as SimSettings
	if settings == null:
		settings = SimSettings.new()
	sram = Sram.new()
	menu_sfx = SfxBank.new()
	menu_sfx.name = "MenuSfx"
	add_child(menu_sfx)
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture("nhl94", _on_debugger_message)

## Live edits from the editor dock (addons/nhl94_debug/debugger_plugin.gd).
func _on_debugger_message(message: String, data: Array) -> bool:
	# Godot passes the part after "nhl94:"; accept the full name too.
	if (message == "set" or message == "nhl94:set") and data.size() == 2:
		settings.set(data[0], data[1])
		return true
	return false

## Scaled delta for simulation code.
func sim_delta(delta: float) -> float:
	return delta * settings.game_speed
