extends CanvasLayer

## One colour for everything that glows: the sword in every moment, and the
## orb. Esc frees the mouse to use it; click the world to take it back. The
## tuning panel (F1) sets each moment separately.

const MOMENTS := ["slash", "flourish", "hit", "kill", "parry", "block", "deflected", "execute"]

@export var katana: Node3D
@export var tuning_panel: CanvasLayer
## Stay out of sight until Esc frees the mouse.
@export var only_with_mouse := false

# A variable, because reads through a const are baked in when the script
# loads and would never see changes.
var look: Resource = preload("res://Core/Combat/combat_look.tres")

var _picker: ColorPickerButton
var _sliders := {}
var _keep: Button


func _ready():
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 38)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.14, 0.14, 0.15, 0.85)
	fill.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", fill)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(230, 0)
	panel.add_child(rows)

	var title := HBoxContainer.new()
	rows.add_child(title)
	var label := Label.new()
	label.text = "Glow colour  (Esc)"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(label)
	_picker = ColorPickerButton.new()
	_picker.custom_minimum_size = Vector2(60, 26)
	_picker.edit_alpha = false
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.color_changed.connect(_set_color)
	title.add_child(_picker)

	_slider(rows, "hue", "Hue", _on_hue)
	# A full turn of hue is red again, which would snap the slider back.
	_sliders.hue.max_value = 0.99
	_slider(rows, "strength", "Colour strength", func(_v): _from_sliders())
	_slider(rows, "rest", "Glow at rest", func(v): _set_look("rest_glow", v))
	_slider(rows, "world", "Colour in the world", func(v): _set_look("world_color", v))
	_keep = Button.new()
	_keep.text = "Save"
	_keep.focus_mode = Control.FOCUS_NONE
	_keep.pressed.connect(_save)
	rows.add_child(_keep)

	_read_look()
	tuning_panel.toggled.connect(_on_tuning_toggled)


func _process(_delta):
	if only_with_mouse:
		visible = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not tuning_panel.is_open()


func _on_tuning_toggled(open: bool) -> void:
	visible = not open
	_read_look()


func _read_look() -> void:
	_show(look.parry.color)
	_sliders.rest.set_value_no_signal(look.rest_glow)
	_sliders.world.set_value_no_signal(look.world_color)


func _show(color: Color) -> void:
	_picker.color = color
	# Grey has no hue of its own; leave the slider where it was.
	if color.s > 0.0:
		_sliders.hue.set_value_no_signal(color.h)
	_sliders.strength.set_value_no_signal(color.s)


func _on_hue(_value: float) -> void:
	# Touching the hue means wanting colour, so don't leave it on white.
	if _sliders.strength.value <= 0.0:
		_sliders.strength.set_value_no_signal(0.9)
	_from_sliders()


func _from_sliders() -> void:
	_set_color(Color.from_hsv(_sliders.hue.value, _sliders.strength.value, 1.0))


func _set_color(color: Color) -> void:
	for kind: String in MOMENTS:
		look.get(kind).color = color
	look.orb_color = color
	_show(color)
	_changed()
	katana.show_glow()


func _set_look(key: String, value: float) -> void:
	look.set(key, value)
	_changed()


func _changed() -> void:
	look.emit_changed()
	_keep.text = "Save"


func _save() -> void:
	var error := ResourceSaver.save(look)
	_keep.text = "Saved" if error == OK else "Couldn't save: %s" % error_string(error)


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
