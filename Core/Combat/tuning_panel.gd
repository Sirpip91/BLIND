extends CanvasLayer

## F1 opens it. Plays any moment of a fight on demand, pins effects on
## screen to study, and edits the combat look live. Every row comes from
## what combat_look.gd exports, so new settings show up by themselves.

signal toggled(open: bool)

# A variable, because reads through a const are baked in when the script
# loads and would never see the tuning panel change them.
var look: Resource = preload("res://Core/Combat/combat_look.tres")

const MOMENTS := ["slash", "flourish", "hit", "kill", "parry", "block", "deflected", "execute", "hurt"]
const LOG_LINES := 6

@export var katana: Node3D
@export var impact_frames: Node

var _panel: Control
var _log: Label
var _hint: Label
var _status: Label
var _rows: VBoxContainer
var _settings: VBoxContainer
var _last := "parry"
var _kind := "parry"
var _loop := false
var _since := 0.0
var _hold := ""
var _hold_heat := false
var _heat := 1.0
var _lines: PackedStringArray = []


func _ready():
	_hint = Label.new()
	_hint.text = "F1 tuning"
	_hint.position = Vector2(14, 8)
	_hint.modulate = Color(1, 1, 1, 0.45)
	add_child(_hint)

	_panel = PanelContainer.new()
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.14, 0.14, 0.15, 0.94)
	fill.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", fill)
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.custom_minimum_size.x = 380
	_panel.visible = false
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_right", 14)
	scroll.add_child(inset)
	_rows = VBoxContainer.new()
	inset.add_child(_rows)

	_heading(_rows, "Play a moment")
	var grid := GridContainer.new()
	grid.columns = 3
	_rows.add_child(grid)
	for kind: String in MOMENTS:
		var button := _button(grid, kind.capitalize(), func(): _play(kind))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle(_rows, "Repeat the last one", false, func(on): _loop = on)
	_slider(_rows, "Slow motion", 1.0, 1.0, 12.0, 0.5, func(v): impact_frames.slow = v)

	_heading(_rows, "Hold still")
	_options(_rows, "Moment to take colours from", MOMENTS.slice(0, -1), MOMENTS.find(_kind), func(i):
		_kind = MOMENTS[i]
		_refresh_holds())
	_options(_rows, "Impact", ["off"] + impact_frames.HOLDS, 0, func(i):
		_hold = "" if i == 0 else impact_frames.HOLDS[i - 1]
		_refresh_holds())
	_toggle(_rows, "Hold sword glow", false, func(on):
		_hold_heat = on
		_refresh_holds())
	_slider(_rows, "Sword heat", _heat, 0.0, 1.0, 0.01, func(v):
		_heat = v
		_refresh_holds())

	_settings = VBoxContainer.new()
	_rows.add_child(_settings)
	_build_settings()
	var buttons := HBoxContainer.new()
	_rows.add_child(buttons)
	for entry in [["Save", _save], ["Undo to saved", _revert]]:
		var button := _button(buttons, entry[0], entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Changes are live. Save keeps them."
	_rows.add_child(_status)

	_log = Label.new()
	_log.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_log.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_log.add_theme_color_override("font_outline_color", Color.BLACK)
	_log.add_theme_constant_override("outline_size", 6)
	_log.visible = false
	add_child(_log)
	katana.moment.connect(_on_moment)


func _process(delta):
	if not _loop or _hold != "":
		return
	# Real seconds, however slowed the game is.
	_since += delta / maxf(Engine.time_scale, 0.0001)
	if _since > 0.6 + 0.8 * impact_frames.slow:
		_play(_last)


func _unhandled_key_input(event):
	if event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		_panel.visible = not _panel.visible
		_hint.visible = not _panel.visible
		_log.visible = _panel.visible
		if _panel.visible:
			# The glow picker may have changed things since.
			_build_settings()
		toggled.emit(_panel.visible)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _panel.visible else Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _panel.visible


func _play(kind: String) -> void:
	_last = kind
	_since = 0.0
	katana.preview(kind)


func _on_moment(kind: String, detail: String) -> void:
	_lines.append(kind.to_upper() + ("  " + detail if detail != "" else ""))
	if _lines.size() > LOG_LINES:
		_lines.remove_at(0)
	_log.text = "\n".join(_lines)


func _refresh_holds() -> void:
	katana.hold_heat(_heat if _hold_heat else -1.0, _kind)
	impact_frames.hold(_hold, katana.preview_point(), look.get(_kind).color)


func _changed() -> void:
	look.emit_changed()
	_status.text = "Not saved yet."
	if _hold != "" or _hold_heat:
		_refresh_holds()


func _save() -> void:
	var error := ResourceSaver.save(look)
	_status.text = "Saved to %s" % look.resource_path.get_file() if error == OK else "Couldn't save: %s" % error_string(error)


func _revert() -> void:
	var saved := ResourceLoader.load(look.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_copy(saved, look)
	_build_settings()
	_changed()
	_status.text = "Back to the saved look."


func _copy(from: Resource, to: Resource) -> void:
	for property in _settings_of(to):
		var value: Variant = from.get(property.name)
		if value is Resource:
			_copy(value, to.get(property.name))
		else:
			to.set(property.name, value)


func _settings_of(resource: Resource) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for property in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			found.append(property)
	return found


func _build_settings() -> void:
	for child in _settings.get_children():
		child.queue_free()
	for property in look.get_property_list():
		if property.usage & PROPERTY_USAGE_GROUP and property.name != "Resource":
			_heading(_settings, property.name)
		elif property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			var value: Variant = look.get(property.name)
			if value is Resource:
				_foldout(property.name, value)
			else:
				_setting(_settings, look, property)


func _foldout(title: String, resource: Resource) -> void:
	var body := VBoxContainer.new()
	body.visible = false
	var head := HBoxContainer.new()
	_settings.add_child(head)
	var button := Button.new()
	button.text = "+  " + title.capitalize()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func():
		body.visible = not body.visible
		button.text = ("-  " if body.visible else "+  ") + title.capitalize())
	head.add_child(button)
	_button(head, "Play", func(): _play(title))
	_settings.add_child(body)
	for property in _settings_of(resource):
		_setting(body, resource, property)


func _setting(rows: Control, resource: Resource, property: Dictionary) -> void:
	var key: String = property.name
	var title := key.capitalize()
	match property.type:
		TYPE_COLOR:
			var line := HBoxContainer.new()
			rows.add_child(line)
			var label := Label.new()
			label.text = title
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(label)
			var picker := ColorPickerButton.new()
			picker.custom_minimum_size = Vector2(90, 26)
			picker.edit_alpha = false
			picker.focus_mode = Control.FOCUS_NONE
			picker.color = resource.get(key)
			picker.color_changed.connect(func(c):
				resource.set(key, c)
				_changed())
			line.add_child(picker)
		TYPE_BOOL:
			_toggle(rows, title, resource.get(key), func(on):
				resource.set(key, on)
				_changed())
		TYPE_FLOAT:
			var limits: PackedFloat64Array = property.hint_string.split_floats(",")
			_slider(rows, title, resource.get(key), limits[0], limits[1], limits[2], func(v):
				resource.set(key, v)
				_changed())


func _heading(rows: Control, text: String) -> void:
	rows.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	rows.add_child(label)


func _button(rows: Control, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	rows.add_child(button)
	return button


func _toggle(rows: Control, text: String, on: bool, toggled: Callable) -> void:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = on
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(toggled)
	rows.add_child(toggle)


func _options(rows: Control, text: String, names: Array, selected: int, chosen: Callable) -> void:
	var label := Label.new()
	label.text = text
	rows.add_child(label)
	var options := OptionButton.new()
	options.focus_mode = Control.FOCUS_NONE
	for option: String in names:
		options.add_item(option.capitalize())
	options.select(selected)
	options.item_selected.connect(chosen)
	rows.add_child(options)


func _slider(rows: Control, text: String, value: float, low: float, high: float, step: float, moved: Callable) -> void:
	var label := Label.new()
	label.text = "%s   %s" % [text, snappedf(value, step)]
	rows.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v):
		label.text = "%s   %s" % [text, snappedf(v, step)]
		moved.call(v))
	rows.add_child(slider)
