extends Node

## Turns distance walked into footfalls, left and right.

signal stepped(at: Vector3, strength: float)

@export var body: CharacterBody3D
@export var stride := 0.8
@export var stance := 0.16
## Speed that makes the loudest step.
@export var full_speed := 3.2

var _walked := 0.0
var _side := 1.0
var _last := Vector3.INF


func _physics_process(delta):
	var moved := body.global_position - _last
	_last = body.global_position
	moved.y = 0.0
	# A jump across the arena is an arrival, not a stride.
	if not moved.is_finite() or moved.length() > 1.0:
		return
	_walked += moved.length()
	if _walked < stride:
		return
	_walked = 0.0
	_side = -_side
	var speed: float = moved.length() / delta
	var across := moved.normalized().cross(Vector3.UP) * stance * _side
	stepped.emit(body.global_position + across, clampf(speed / full_speed, 0.35, 1.0))


## A foot planted on the spot, such as before a blow.
func stamp(strength: float) -> void:
	stepped.emit(body.global_position - body.global_basis.z * 0.3, strength)
