extends CanvasLayer

## The control panel. Everything adjustable is a row in SPEC, so a new
## setting is one line here plus wherever showcase.gd reads it.

signal model_chosen(path: String)
signal action(name: String)

const SETTINGS_FILE := "user://showcase.cfg"

const SIZES: Array[Vector2i] = [Vector2i(480, 480), Vector2i(600, 600), Vector2i(800, 800), Vector2i(1080, 1080),
		Vector2i(960, 540), Vector2i(1280, 720), Vector2i(720, 1280)]
# GIF delays are whole hundredths of a second; these divide evenly.
const RATES: Array[int] = [10, 20, 25]

# [key, label, default, min, max, step], or [key, label, default] for a
# tick box, or [key, label, default, options] for a list.
const SPEC := [
	["", "Spin"],
	["spin", "Spinning", true],
	["seconds", "Seconds per turn", 14.0, 2.0, 60.0, 0.5],
	["reverse", "Other way", false],
	["tilt", "Tilt", 0.0, -90.0, 90.0, 1.0],
	["lean", "Lean", 0.0, -90.0, 90.0, 1.0],
	["own_axis", "Spin along its own length", false],
	["", "Camera"],
	["yaw", "Around", 25.0, -180.0, 180.0, 1.0],
	["pitch", "Height", 12.0, -85.0, 85.0, 1.0],
	["zoom", "Zoom", 1.0, 0.3, 6.0, 0.01],
	["pan_x", "Slide left / right", 0.0, -1.5, 1.5, 0.01],
	["pan_y", "Slide up / down", 0.0, -1.5, 1.5, 0.01],
	["lens", "Lens (low = flat)", 30.0, 8.0, 80.0, 1.0],
	["push", "Push in during turn", 0.0, 0.0, 1.0, 0.01],
	["rise", "Rise during turn", 0.0, -30.0, 30.0, 1.0],
	["", "Look"],
	["look", "Materials", 0, ["Ink + real light", "As imported"]],
	["outlines", "Outlines and paper", true],
	["outline", "Outline thickness", 1.6, 0.5, 6.0, 0.1],
	["flicker", "Outline flicker", 1.0, 0.0, 2.0, 0.05],
	["color", "Colour", 0.0, 0.0, 1.0, 0.01],
	["grain", "Paper grain", 0.0, 0.0, 0.3, 0.01],
	["vignette", "Vignette", 0.0, 0.0, 1.0, 0.01],
	["", "Light"],
	["background", "Background", 0.0, 0.0, 1.0, 0.01],
	["key", "Main light", 1.2, 0.0, 4.0, 0.05],
	["key_yaw", "Main light around", -40.0, -180.0, 180.0, 1.0],
	["key_pitch", "Main light height", 45.0, -80.0, 89.0, 1.0],
	["rim", "Rim light", 0.8, 0.0, 4.0, 0.05],
	["ambient", "Shadow brightness", 0.12, 0.0, 1.0, 0.01],
	["pedestal", "Pedestal", false],
	["", "Save"],
	["size", "Size", 1, ["480 square", "600 square", "800 square", "1080 square", "960 x 540", "1280 x 720", "720 x 1280"]],
	["rate", "Frames per second", 1, ["10", "20", "25"]],
	["smooth", "Smooth edges", true],
]

const CAMERA_PRESETS := {
	"Front": {"yaw": 0.0, "pitch": 0.0},
	"3/4": {"yaw": 30.0, "pitch": 18.0},
	"Hero": {"yaw": 20.0, "pitch": -18.0},
	"Top": {"yaw": 0.0, "pitch": 70.0},
}
const CAMERA_HOME := {"zoom": 1.0, "pan_x": 0.0, "pan_y": 0.0}
const LIGHT_PRESETS := {
	"Night": {"background": 0.0, "key": 1.2, "key_yaw": -40.0, "key_pitch": 45.0, "rim": 0.8, "ambient": 0.12},
	"Moody": {"background": 0.0, "key": 0.7, "key_yaw": -65.0, "key_pitch": 25.0, "rim": 1.6, "ambient": 0.05},
	"Studio": {"background": 0.3, "key": 1.3, "key_yaw": -35.0, "key_pitch": 40.0, "rim": 0.5, "ambient": 0.3},
	"Paper": {"background": 1.0, "key": 1.0, "key_yaw": -35.0, "key_pitch": 50.0, "rim": 0.0, "ambient": 0.4},
}

var values := {}
var preview: TextureRect

var _controls := {}
var _labels := {}
var _panel: Control
var _models: OptionButton
var _info: Label
var _status: Label
var _bar: ProgressBar
var _buttons: Array[Button] = []
var _cancel: Button
var _dialog: FileDialog


func _ready():
	var back := ColorRect.new()
	back.color = Color(0.09, 0.09, 0.1)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(columns)

	_panel = PanelContainer.new()
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.17, 0.17, 0.18)
	fill.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", fill)
	columns.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	# Room for the scroll bar, so it doesn't sit on the sliders.
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_right", 14)
	scroll.add_child(inset)
	var rows := VBoxContainer.new()
	inset.add_child(rows)

	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	columns.add_child(preview)

	_heading(rows, "Model")
	_models = OptionButton.new()
	_models.focus_mode = Control.FOCUS_NONE
	_models.fit_to_longest_item = false
	_models.item_selected.connect(func(i): model_chosen.emit(_models.get_item_metadata(i)))
	rows.add_child(_models)
	_button(rows, "Open file... (or drop one on the window)", func(): _dialog.popup_centered())
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_info)

	for row: Array in SPEC:
		if row[0] == "":
			_heading(rows, row[1])
			if row[1] == "Camera":
				_presets(rows, CAMERA_PRESETS, CAMERA_HOME)
			elif row[1] == "Light":
				_presets(rows, LIGHT_PRESETS, {})
		else:
			_row(rows, row)

	_buttons.append(_button(rows, "Save GIF", func(): action.emit("gif")))
	_buttons.append(_button(rows, "Save PNG frames", func(): action.emit("frames")))
	_buttons.append(_button(rows, "Save still", func(): action.emit("still")))
	_button(rows, "Open save folder", func(): action.emit("folder"))
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.visible = false
	rows.add_child(_bar)
	_cancel = _button(rows, "Cancel", func(): action.emit("cancel"))
	_cancel.visible = false
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Drag to orbit, right-drag to slide, wheel to zoom.\nSpace pauses, F re-frames, H hides this panel."
	rows.add_child(_status)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray(["*.glb,*.gltf,*.fbx;3D models"])
	_dialog.file_selected.connect(func(path): model_chosen.emit(path))
	add_child(_dialog)
	_restore()


func set_value(key: String, value: Variant) -> void:
	var control: Control = _controls[key]
	if control is HSlider:
		control.value = value
	elif control is CheckButton:
		control.button_pressed = value
	else:
		control.select(value)
		values[key] = value


func reframe() -> void:
	for key in CAMERA_HOME:
		set_value(key, CAMERA_HOME[key])


func toggle_panel() -> void:
	_panel.visible = not _panel.visible


func list_models(paths: PackedStringArray) -> void:
	_models.clear()
	for path in paths:
		_models.add_item(path.trim_prefix("res://Assets/"))
		_models.set_item_metadata(_models.item_count - 1, path)


func show_model(path: String, size: Vector3) -> void:
	var index := -1
	for i in _models.item_count:
		if _models.get_item_metadata(i) == path:
			index = i
	if index < 0:
		_models.add_item(path.get_file())
		index = _models.item_count - 1
		_models.set_item_metadata(index, path)
	_models.select(index)
	_info.text = "%.2f m wide, %.2f m tall, %.2f m deep" % [size.x, size.y, size.z]


func say(text: String) -> void:
	_status.text = text


func set_busy(busy: bool) -> void:
	_bar.visible = busy
	_bar.value = 0.0
	_cancel.visible = busy
	for button in _buttons:
		button.disabled = busy


func set_progress(amount: float, what: String) -> void:
	_bar.value = amount
	_status.text = what


func save_settings(model: String) -> void:
	var file := ConfigFile.new()
	for key in values:
		file.set_value("settings", key, values[key])
	file.set_value("model", "path", model)
	file.save(SETTINGS_FILE)


func last_model() -> String:
	var file := ConfigFile.new()
	return file.get_value("model", "path", "") if file.load(SETTINGS_FILE) == OK else ""


func _restore() -> void:
	var file := ConfigFile.new()
	if file.load(SETTINGS_FILE) != OK:
		return
	for key in _controls:
		if file.has_section_key("settings", key):
			set_value(key, file.get_value("settings", key))


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


func _presets(rows: Control, presets: Dictionary, also: Dictionary) -> void:
	var line := HBoxContainer.new()
	rows.add_child(line)
	for title: String in presets:
		var preset: Dictionary = presets[title].merged(also)
		var button := _button(line, title, func():
			for key in preset:
				set_value(key, preset[key]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _row(rows: Control, row: Array) -> void:
	var key: String = row[0]
	values[key] = row[2]
	if row.size() == 3:
		var box := CheckButton.new()
		box.text = row[1]
		box.button_pressed = row[2]
		box.focus_mode = Control.FOCUS_NONE
		box.toggled.connect(func(on): values[key] = on)
		rows.add_child(box)
		_controls[key] = box
		return
	var label := Label.new()
	label.text = row[1]
	rows.add_child(label)
	if row.size() == 4:
		var options := OptionButton.new()
		options.focus_mode = Control.FOCUS_NONE
		for text: String in row[3]:
			options.add_item(text)
		options.select(row[2])
		options.item_selected.connect(func(i): values[key] = i)
		rows.add_child(options)
		_controls[key] = options
		return
	var slider := HSlider.new()
	slider.min_value = row[3]
	slider.max_value = row[4]
	slider.step = row[5]
	slider.value = row[2]
	slider.focus_mode = Control.FOCUS_NONE
	# So scrolling the panel doesn't nudge whatever is under the mouse.
	slider.scrollable = false
	_labels[key] = label
	slider.value_changed.connect(func(v):
		values[key] = v
		label.text = "%s   %s" % [row[1], str(snappedf(v, row[5]))])
	label.text = "%s   %s" % [row[1], str(row[2])]
	rows.add_child(slider)
	_controls[key] = slider
