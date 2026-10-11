@tool
extends EditorPlugin

const DOCK_SCENE := preload("res://addons/nhl94_debug/Nhl94DebugDock.tscn")
const DebuggerPlugin := preload("res://addons/nhl94_debug/debugger_plugin.gd")

var _dock: Control
var _debugger: EditorDebuggerPlugin

func _enter_tree() -> void:
	_debugger = DebuggerPlugin.new()
	add_debugger_plugin(_debugger)
	_dock = DOCK_SCENE.instantiate()
	_dock.set("debugger", _debugger)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _debugger:
		remove_debugger_plugin(_debugger)
		_debugger = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
