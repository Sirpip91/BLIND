extends Control

## A small brush mark where the mouse is: the line a cut would take, or the
## side a raised guard covers. Drawing one, it's the line itself, drying as
## the time to draw it goes.

@export var player: CharacterBody3D
@export var arm: Node3D
@export var swordsman: Node
@export var ink := Color(0.05, 0.05, 0.06, 0.75)
@export var paper := Color(0.95, 0.94, 0.91, 0.8)
@export var radius := 30.0
@export var line_width := 11.0

var _shown := Vector2(-0.7, -0.7)
var _guarding := 0.0


func _process(delta: float):
	var want: Vector2 = arm.guard_side if arm.phase == arm.Phase.GUARD else player.aim
	_shown = _shown.slerp(want.normalized(), 1.0 - exp(-22.0 * delta)) if _shown.length() > 0.1 else want
	_guarding = move_toward(_guarding, 1.0 if arm.phase == arm.Phase.GUARD else 0.0, delta * 10.0)
	queue_redraw()


func _draw():
	if swordsman.is_drawing():
		_draw_line_taken()
		return
	if not player.is_locked():
		return
	var middle := _on_screen(player.cursor)
	var way := Vector2(_shown.x, -_shown.y).normalized()
	var side := way.orthogonal()
	if _guarding < 0.5:
		# Faint, the line it'll cut along.
		for end: float in [-1.0, 1.0]:
			draw_line(middle + way * end * radius * 1.5, middle + way * end * radius * 5.0, Color(ink, 0.28), 1.0, true)
		# A stroke pulled along the cut: pressed at the start, lifted at the end.
		for layer: Array in [[paper, 2.0], [ink, 0.0]]:
			var line := PackedVector2Array()
			var back := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				var at := middle + way * lerpf(-radius * 0.55, radius, t)
				var w: float = 3.0 * sin(PI * pow(t, 0.45)) * (1.0 - 0.5 * t) + layer[1] + 0.2
				line.append(at + side * w)
				back.append(at - side * w)
			back.reverse()
			line.append_array(back)
			draw_colored_polygon(line, layer[0])
	else:
		# An arc over the side that's covered.
		for layer: Array in [[paper, 1.8], [ink, 0.0]]:
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for i in 25:
				var t := i / 24.0
				var a := way.angle() + lerpf(-0.85, 0.85, t)
				var w: float = 2.6 * sin(PI * t) + 0.3 + layer[1]
				outer.append(middle + Vector2.from_angle(a) * (radius + w))
				inner.append(middle + Vector2.from_angle(a) * (radius - w))
			inner.reverse()
			outer.append_array(inner)
			draw_colored_polygon(outer, layer[0])


func _draw_line_taken() -> void:
	var line: PackedVector2Array = swordsman.drawn
	var left: float = swordsman.draw_left()
	draw_circle(_on_screen(player.cursor), 2.5 + 2.5 * left, ink, true, -1.0, true)
	if line.size() < 2:
		return
	for layer: Array in [[paper, 3.0], [Color(ink, lerpf(0.45, 0.95, left)), 0.0]]:
		for i in line.size() - 1:
			# Thin where it began, and thinner as the time runs out.
			var t := float(i) / maxf(line.size() - 1, 1)
			var wide := line_width * lerpf(0.3, 1.0, left) * (0.35 + 0.65 * minf(t * 4.0, 1.0))
			var to := _on_screen(line[i + 1])
			draw_line(_on_screen(line[i]), to, layer[0], wide + layer[1], true)
			draw_circle(to, (wide + layer[1]) * 0.5, layer[0])


func _on_screen(at: Vector2) -> Vector2:
	var camera: Camera3D = player.camera
	return camera.unproject_position(camera.global_transform * (arm.ray(at) * 3.0))
