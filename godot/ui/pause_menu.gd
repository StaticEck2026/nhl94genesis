extends CanvasLayer
## Pause menu. Start (p1_start / p2_start) toggles it; the game tree pauses underneath.

@onready var _panel: Control = %Panel
@onready var _resume: Button = %Resume
@onready var _quit: Button = %Quit

signal quit_requested

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	_resume.pressed.connect(toggle)
	_quit.pressed.connect(func() -> void:
		get_tree().paused = false
		quit_requested.emit())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("p1_start") or event.is_action_pressed("p2_start"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	_panel.visible = not _panel.visible
	get_tree().paused = _panel.visible
	if _panel.visible:
		_resume.grab_focus()
