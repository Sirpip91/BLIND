extends Control

## What can be asked of a mask: a drop of each colour round it. Pointed at,
## it says what it does. One can be taken.

const Aspect = preload("res://Experiments/Arena/player/aspect.gd")

signal pointed_at(aspect: Aspect)
signal chose(aspect: Aspect)
signal left

@export var paper := Color(0.93, 0.92, 0.89, 0.92)
@export var ink := Color(0.04, 0.04, 0.05)
@export var drop := 34.0
@export var apart := 250.0

var _aspects: Array[Aspect] = []
var _chosen: Aspect
var _around: Node3D
var _over := -1
var _swell: Array[float] = []
var _shapes: Array[PackedVector2Array] = []
var _shown := 0.0


func _ready():
	visible = false
	mouse_filter = MOUSE_FILTER_STOP


func open(aspects: Array, chosen: Aspect, around: Node3D) -> void:
	_aspects.assign(aspects)
	_chosen = chosen
	_around = around
	_over = -1
	_shown = 0.0
	_swell.clear()
	_shapes.clear()
	for i in aspects.size():
		_swell.append(0.0)
		_shapes.append(_blot(i))
	visible = true


func close() -> void:
	visible = false
	left.emit()


# No two drops fall the same.
func _blot(of: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + of
	var noise := FastNoiseLite.new()
	noise.seed = of
	noise.frequency = 0.9
	var points := PackedVector2Array()
	for i in 48:
		var way := Vector2.from_angle(TAU * i / 48.0)
		points.append(way * (1.0 + 0.16 * noise.get_noise_2d(way.x * 1.6, way.y * 1.6) + 0.07 * noise.get_noise_2d(way.x * 6.0 + 9.0, way.y * 6.0)))
	return points


func _place(i: int) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	var middle := camera.unproject_position(_around.global_position)
	var unit := size.y / 1080.0
	# Two either side of it.
	var angle: float = [-2.72, -0.42, 2.72, 0.42][i % 4]
	return middle + Vector2.from_angle(angle) * apart * unit * Vector2(1.25, 1.0)


func _process(delta: float):
	if not visible:
		return
	_shown = move_toward(_shown, 1.0, delta * 4.0)
	var mouse := get_local_mouse_position()
	var over := -1
	for i in _aspects.size():
		if mouse.distance_to(_place(i)) < drop * size.y / 1080.0 * 1.9:
			over = i
		_swell[i] = lerpf(_swell[i], 1.0 if i == _over else 0.0, 1.0 - exp(-14.0 * delta))
	if over != _over:
		_over = over
		pointed_at.emit(_aspects[over] if over >= 0 else null)
	queue_redraw()


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _over >= 0:
			chose.emit(_aspects[_over])
		else:
			close()


func _input(event):
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_E, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		close()


func _draw():
	var unit := size.y / 1080.0
	var font := get_theme_default_font()
	var fade := smoothstep(0.0, 1.0, _shown)
	# Nothing to draw yet.
	if fade < 0.02:
		return
	for i in _aspects.size():
		var at := _place(i)
		var big := drop * unit * (1.0 + 0.4 * _swell[i]) * fade
		var taken := _aspects[i] == _chosen
		for layer: Array in [[paper, 1.28 if not taken else 1.4], [_aspects[i].color.darkened(0.15), 1.0]]:
			var points := PackedVector2Array()
			for p in _shapes[i]:
				points.append(at + p * big * layer[1])
			draw_colored_polygon(points, layer[0])
	if _over < 0:
		return
	var aspect := _aspects[_over]
	var lines := aspect.says.split("\n")
	var large := int(34 * unit)
	var small := int(22 * unit)
	var wide := font.get_string_size(aspect.label, HORIZONTAL_ALIGNMENT_LEFT, -1, large).x
	for line in lines:
		wide = maxf(wide, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x)
	var tall := (large + lines.size() * small * 1.45) + 34.0 * unit
	var from := Vector2((size.x - wide) * 0.5, size.y * 0.76)
	draw_rect(Rect2(from - Vector2(28, 12) * unit, Vector2(wide + 56 * unit, tall)), paper)
	draw_string(font, from + Vector2(0, large), aspect.label, HORIZONTAL_ALIGNMENT_LEFT, -1, large, aspect.color.darkened(0.2))
	for i in lines.size():
		draw_string(font, from + Vector2(0, large + (i + 1) * small * 1.45), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, small, ink)
