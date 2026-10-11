@tool
extends EditorDebuggerPlugin
## Sends dock changes to every running game session over the debugger channel.
## The game side is the "nhl94" message capture in core/sim.gd.

func _has_capture(prefix: String) -> bool:
	return prefix == "nhl94"

func send_setting(prop_name: String, value: Variant) -> void:
	for session in get_sessions():
		if session.is_active():
			session.send_message("nhl94:set", [prop_name, value])
