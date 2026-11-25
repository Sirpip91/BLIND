extends Control

## A small brush mark in the middle of the view: the way a cut would go, or
## the side a raised guard covers.

@export var player: CharacterBody3D
@export var arm: Node3D
@export var swordsman: Node
## The mark when a cut that way would find them bare.
@export var true_color := Color(0.8, 0.04, 0.04, 0.95)
@export var ink := Color(0.05, 0.05, 0.06, 0.75)
@export var paper := Color(0.95, 0.94, 0.91, 0.8)
@export var radius := 30.0

var _shown := Vector2(-0.7, -0.7)
var _guarding := 0.0
var _true := 0.0


func _process(delta: float):
	var want: Vector2 = arm.guard_side if arm.phase == arm.Phase.GUARD else player.aim
	_shown = _shown.slerp(want.normalized(), 1.0 - exp(-22.0 * delta)) if _shown.length() > 0.1 else want
	_guarding = move_toward(_guarding, 1.0 if arm.phase == arm.Phase.GUARD else 0.0, delta * 10.0)
	_true = move_toward(_true, 1.0 if swordsman.reads_true() else 0.0, delta * 14.0)
	visible = player.is_locked()
	queue_redraw()


func _draw():
	var middle := size * 0.5
	var way := Vector2(_shown.x, -_shown.y).normalized()
	var side := way.orthogonal()
	var mark := ink.lerp(true_color, _true)
	var long: float = radius * (1.0 + 0.35 * _true + 0.6 * swordsman.pulse)
	if _guarding < 0.5:
		# A stroke pulled along the cut: pressed at the start, lifted at the end.
		for layer: Array in [[paper, 2.0], [mark, 0.0]]:
			var line := PackedVector2Array()
			var back := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				var at := middle + way * lerpf(-long * 0.55, long, t)
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
