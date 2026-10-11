@tool
extends EditorPlugin

const DOCK_SCENE := preload("res://addons/nhl94_debug/Nhl94DebugDock.tscn")

var _dock: Control

func _enter_tree() -> void:
	_dock = DOCK_SCENE.instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
