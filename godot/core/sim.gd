extends Node
## Autoload. Holds the shared SimSettings instance.

const SETTINGS_PATH := "res://core/sim_settings.tres"

var settings: SimSettings

func _enter_tree() -> void:
	if ResourceLoader.exists(SETTINGS_PATH):
		settings = load(SETTINGS_PATH) as SimSettings
	if settings == null:
		settings = SimSettings.new()

## Scaled delta for simulation code.
func sim_delta(delta: float) -> float:
	return delta * settings.game_speed
