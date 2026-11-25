extends CanvasLayer

## Picks the sword's colour. C goes through the ready-made ones. Esc frees the
## mouse and brings up the panel; click the world to go back to it.

const Look = preload("res://Experiments/Arena/player/sword_look.gd")

@export var brush: Node
@export var look: Look
## Plain ink, then these.
@export var ready_made: Array[Color] = [Color(0.9, 0.06, 0.05), Color(0.08, 0.3, 0.85), Color(0.1, 0.55, 0.25), Color(0.5, 0.15, 0.75)]

var _panel: PanelContainer
var _picker: ColorPickerButton
var _sliders := {}
var _keep: Button


func _ready():
	# Still there when Esc has stopped everything else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	_panel = PanelContainer.new()
	_panel.position = Vector2(28, 210)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.14, 0.14, 0.15, 0.88)
	fill.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", fill)
	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(250, 0)
	_panel.add_child(rows)

	var title := HBoxContainer.new()
	rows.add_child(title)
	var label := Label.new()
	label.text = "Sword colour  (C)"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(label)
	_picker = ColorPickerButton.new()
	_picker.custom_minimum_size = Vector2(60, 26)
	_picker.edit_alpha = false
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.color_changed.connect(_set_color)
	title.add_child(_picker)

	var swatches := HBoxContainer.new()
	rows.add_child(swatches)
	_swatch(swatches, Color(0.05, 0.05, 0.06), _plain)
	for color in ready_made:
		_swatch(swatches, color, func(): _wear(color))

	_slider(rows, "hue", "Hue", _on_hue)
	# A full turn of hue is red again, which would snap the slider back.
	_sliders.hue.max_value = 0.99
	_slider(rows, "blade", "In the blade", func(v): _set_look("blade", v))
	_slider(rows, "strokes", "In the strokes", func(v): _set_look("strokes", v))
	_keep = Button.new()
	_keep.focus_mode = Control.FOCUS_NONE
	_keep.pressed.connect(_save)
	rows.add_child(_keep)
	_show()


func _process(_delta):
	_panel.visible = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not kept_away


func _unhandled_key_input(event):
	if not event.pressed or event.echo or event.physical_keycode != KEY_C:
		return
	var at := -1
	if look.blade > 0.0:
		for i in ready_made.size():
			if ready_made[i].is_equal_approx(look.color):
				at = i
	if at == ready_made.size() - 1:
		_plain()
	else:
		_wear(ready_made[at + 1])


## Something else is using the mouse.
var kept_away := false


func _wear(color: Color) -> void:
	look.color = color
	look.blade = 1.0
	look.strokes = maxf(look.strokes, 0.65)
	_show()


func _plain() -> void:
	look.blade = 0.0
	look.strokes = 0.0
	_show()


func _set_color(color: Color) -> void:
	look.color = color
	# Picking one means wanting to see it.
	if look.blade <= 0.0:
		look.blade = 1.0
		look.strokes = 0.65
	_show()


func _on_hue(hue: float) -> void:
	_set_color(Color.from_hsv(hue, maxf(look.color.s, 0.85), maxf(look.color.v, 0.6)))


func _set_look(key: String, value: float) -> void:
	look.set(key, value)
	_show()


func _show() -> void:
	_picker.color = look.color
	_sliders.hue.set_value_no_signal(look.color.h)
	_sliders.blade.set_value_no_signal(look.blade)
	_sliders.strokes.set_value_no_signal(look.strokes)
	brush.tint = look.color
	brush.blade_tint = look.blade
	brush.stroke_tint = look.strokes
	_keep.text = "Save"


func _save() -> void:
	var error := ResourceSaver.save(look)
	_keep.text = "Saved" if error == OK else "Couldn't save: %s" % error_string(error)


func _swatch(row: Control, color: Color, picked: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(40, 26)
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var fill := StyleBoxFlat.new()
		fill.bg_color = color.lightened(0.15) if state == "hover" else color
		button.add_theme_stylebox_override(state, fill)
	button.pressed.connect(picked)
	row.add_child(button)


func _slider(rows: Control, key: String, text: String, moved: Callable) -> void:
	var label := Label.new()
	label.text = text
	rows.add_child(label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.01
	# Keeps arrow keys and WASD from nudging it while walking.
	slider.focus_mode = Control.FOCUS_NONE
	slider.scrollable = false
	slider.value_changed.connect(moved)
	rows.add_child(slider)
	_sliders[key] = slider
