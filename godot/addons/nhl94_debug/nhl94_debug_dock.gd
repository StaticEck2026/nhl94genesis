@tool
extends VBoxContainer
## Builds one row per exported SimSettings property: a CheckBox for bools and a
## slider + value label for ranged numbers. Edits save to res://core/sim_settings.tres,
## which the Sim autoload loads at startup.

const SETTINGS_PATH := "res://core/sim_settings.tres"

var settings: SimSettings

@onready var _rows: VBoxContainer = %Rows
@onready var _save_button: Button = %SaveButton
@onready var _reset_button: Button = %ResetButton

func _ready() -> void:
	settings = load(SETTINGS_PATH) as SimSettings
	if settings == null:
		settings = SimSettings.new()
	_save_button.pressed.connect(_save)
	_reset_button.pressed.connect(_reset)
	_build()

func _build() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for prop in settings.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_GROUP:
			var header := Label.new()
			header.text = prop["name"]
			header.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			_rows.add_child(header)
			continue
		if not (usage & PROPERTY_USAGE_EDITOR) or not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		match prop["type"]:
			TYPE_BOOL:
				_add_toggle(prop["name"])
			TYPE_FLOAT, TYPE_INT:
				if prop["hint"] == PROPERTY_HINT_RANGE:
					_add_slider(prop["name"], prop["hint_string"], prop["type"] == TYPE_INT)

func _add_toggle(prop_name: String) -> void:
	var box := CheckBox.new()
	box.text = prop_name.capitalize()
	box.button_pressed = settings.get(prop_name)
	box.toggled.connect(func(on: bool) -> void: _set_value(prop_name, on))
	_rows.add_child(box)

func _add_slider(prop_name: String, hint: String, is_int: bool) -> void:
	var parts := hint.split(",")
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = prop_name.capitalize()
	label.custom_minimum_size.x = 140
	label.clip_text = true
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = float(parts[0])
	slider.max_value = float(parts[1])
	slider.step = float(parts[2]) if parts.size() > 2 else (1.0 if is_int else 0.01)
	slider.value = float(settings.get(prop_name))
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 48
	value_label.text = str(settings.get(prop_name))
	slider.value_changed.connect(func(v: float) -> void:
		var typed: Variant = int(v) if is_int else v
		_set_value(prop_name, typed)
		value_label.text = str(typed))
	row.add_child(label)
	row.add_child(slider)
	row.add_child(value_label)
	_rows.add_child(row)

func _set_value(prop_name: String, value: Variant) -> void:
	settings.set(prop_name, value)
	# A running game in the editor shares the resource path, so saving makes the change visible on next load.
	_save()

func _save() -> void:
	ResourceSaver.save(settings, SETTINGS_PATH)

func _reset() -> void:
	settings = SimSettings.new()
	_save()
	_build()
