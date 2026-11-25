extends Control

## Something to be picked: black lettering, and a black brush pulled across
## behind it when it's pointed at.

const TEXT = preload("res://Experiments/Arena/menu/ink_text.gdshader")
const STROKE = preload("res://Experiments/Arena/menu/stroke.gdshader")

signal pressed

var text := "":
	set(value):
		text = value
		if _label:
			_label.text = value
			_fit()
var font: Font
var big := 64
var ink := Color(0.02, 0.02, 0.025)
var paper := Color(0.94, 0.93, 0.9)
## Only there to be read.
var still := false

var _label: Label
var _stroke: ColorRect
var _lettering := ShaderMaterial.new()
var _brush := ShaderMaterial.new()
var _over := 0.0
var _drawn := 0.0
var _wait := 0.0


func _init(what := "", written_in: Font = null, size_of := 64, only_read := false, after := 0.0):
	text = what
	font = written_in
	big = size_of
	still = only_read
	_wait = after


func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE if still else MOUSE_FILTER_STOP
	_stroke = ColorRect.new()
	_stroke.mouse_filter = MOUSE_FILTER_IGNORE
	_brush.shader = STROKE
	_brush.set_shader_parameter("ink", ink)
	_brush.set_shader_parameter("seed", randf() * 30.0)
	_stroke.material = _brush
	add_child(_stroke)
	_label = Label.new()
	_label.text = text
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", big)
	_lettering.shader = TEXT
	_lettering.set_shader_parameter("seed", randf() * 30.0)
	_lettering.set_shader_parameter("dryness", 0.3 if not still else 0.2)
	_label.material = _lettering
	add_child(_label)
	_fit()


func _fit() -> void:
	var fits := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, big)
	custom_minimum_size = fits + Vector2(big * 0.9, big * 0.1)
	_label.position = Vector2(big * 0.4, 0.0)
	_stroke.position = Vector2(-big * 0.1, -big * 0.04)
	_stroke.size = fits + Vector2(big * 1.1, big * 0.2)
	_brush.set_shader_parameter("size", _stroke.size)
	_lettering.set_shader_parameter("width", fits.x)


func _process(delta: float):
	_wait -= delta
	if _wait > 0.0:
		_lettering.set_shader_parameter("drawn", 0.0)
		return
	_drawn = move_toward(_drawn, 1.0, delta * 2.4)
	_over = move_toward(_over, 1.0 if not still and is_hovered() else 0.0, delta * (6.0 if is_hovered() else 9.0))
	_lettering.set_shader_parameter("drawn", smoothstep(0.0, 1.0, _drawn))
	_brush.set_shader_parameter("drawn", smoothstep(0.0, 1.0, _over))
	_label.add_theme_color_override("font_color", ink.lerp(paper, smoothstep(0.35, 0.9, _over)))


func is_hovered() -> bool:
	return is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()
