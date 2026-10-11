extends Node
## Autoload. Holds the shared SimSettings instance.

const SETTINGS_PATH := "res://core/sim_settings.tres"

var settings: SimSettings
## Set by the setup screen before the game scene loads.
var match: MatchConfig = MatchConfig.new()

func _enter_tree() -> void:
	if ResourceLoader.exists(SETTINGS_PATH):
		settings = load(SETTINGS_PATH) as SimSettings
	if settings == null:
		settings = SimSettings.new()
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
