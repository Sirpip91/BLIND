extends Control

## A drop of ink on a line, to be dragged along it.

signal moved(to: float)

## 0 to 1.
var value := 0.5
var ink := Color(0.02, 0.02, 0.025)

var _held := false


func _ready():
	custom_minimum_size = Vector2(420, 54)
	mouse_filter = MOUSE_FILTER_STOP


func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_held = event.pressed
		accept_event()
	if (event is InputEventMouseMotion and _held) or (event is InputEventMouseButton and _held):
		value = clampf((event.position.x - 30.0) / (size.x - 60.0), 0.0, 1.0)
		moved.emit(value)
		queue_redraw()


func _draw():
	var middle := size.y * 0.5
	var line := PackedVector2Array()
	var back := PackedVector2Array()
	for i in 41:
		var t := i / 40.0
		var at := Vector2(lerpf(20.0, size.x - 20.0, t), middle + sin(t * 9.0) * 1.2)
		var wide := 1.2 + 3.2 * pow(sin(PI * pow(t, 0.4)), 0.8) * (1.0 - 0.6 * t)
		line.append(at - Vector2(0, wide))
		back.append(at + Vector2(0, wide))
	back.reverse()
	line.append_array(back)
	draw_colored_polygon(line, ink)
	var drop := PackedVector2Array()
	for i in 36:
		var way := Vector2.from_angle(TAU * i / 36.0)
		drop.append(Vector2(lerpf(30.0, size.x - 30.0, value), middle) + way * (15.0 + 2.2 * sin(i * 2.1) + 1.4 * sin(i * 5.3)))
	draw_colored_polygon(drop, ink)
