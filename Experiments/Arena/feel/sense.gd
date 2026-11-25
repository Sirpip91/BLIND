extends Control

## A blow about to land that can't be seen, felt at that edge of the sheet: one
## stroke of colour, pressed harder the nearer it is. Nothing's felt of a blow
## that isn't really coming.

@export var player: CharacterBody3D
## Seconds ahead that it's felt.
@export var ahead := 0.95
@export var color := Color(0.08, 0.3, 0.85)
## How far inside the edge of the view still counts as out of it.
@export_range(0.0, 0.4, 0.01) var margin := 0.06

var on := false
var foes: Array[Node3D] = []

var _felt := {}


func _process(delta: float):
	if not on and _felt.is_empty():
		return
	var now := {}
	if on and not player.vitals.dead:
		for foe in foes:
			var left: float = foe.arm.time_to_land()
			if left < ahead and not foe.vitals.dead and not foe.is_unseen() and not foe.image and not foe.brain.is_pretending() and not foe.arm.strike.feint and _is_out_of_view(foe):
				now[foe] = 1.0 - left / ahead
	for foe: Variant in _felt.keys():
		if not is_instance_valid(foe):
			_felt.erase(foe)
		elif not now.has(foe):
			_felt[foe] -= delta * 5.0
			if _felt[foe] <= 0.0:
				_felt.erase(foe)
	for foe: Node3D in now:
		_felt[foe] = now[foe]
	queue_redraw()


func _is_out_of_view(foe: Node3D) -> bool:
	var camera: Camera3D = player.camera
	var at := foe.global_position + Vector3.UP * 1.3
	if camera.is_position_behind(at):
		return true
	var seen := camera.unproject_position(at) / size
	return seen.x < margin or seen.x > 1.0 - margin


func _draw():
	for foe: Node3D in _felt:
		_stroke(foe, _felt[foe])


func _stroke(foe: Node3D, strength: float) -> void:
	var to := foe.global_position - player.global_position
	var ahead_way: Vector3 = player.facing()
	var bearing := atan2(to.dot(ahead_way.cross(Vector3.UP)), to.dot(ahead_way))
	# Out to the sides, and round to the foot of the sheet for what's behind.
	var way := Vector2(sin(bearing), -cos(bearing))
	if way.y < 0.0:
		way = Vector2(signf(way.x), way.y * 0.35).normalized()
	var middle := size * 0.5
	var rim := Vector2(size.x * 0.46, size.y * 0.43)
	var long := lerpf(0.16, 0.34, strength)
	var wide := lerpf(5.0, 40.0, strength * strength) * size.y / 1080.0
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var start := way.angle()
	for i in 25:
		var t := i / 24.0
		var spoke := Vector2.from_angle(start + lerpf(-long, long, t))
		# Pressed in the middle, lifted at the ends, and never quite even.
		var press := pow(sin(PI * t), 0.8) * (1.0 + 0.18 * sin(t * 23.0 + start * 5.0))
		outer.append(middle + spoke * rim)
		inner.append(middle + spoke * (rim - Vector2.ONE * (wide * press + 0.6)))
	inner.reverse()
	outer.append_array(inner)
	draw_colored_polygon(outer, Color(color, lerpf(0.35, 0.95, strength)))
