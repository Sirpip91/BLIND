extends Node

## Watches the line the player is drawing, or threatening to, and puts the
## sword in its way: across it, where it would come in. It sees a moment late
## and moves only so fast, so a line can be drawn round it or turned at the
## last.

## How far off it bothers.
@export var from_distance := 3.2
## How near is in reach of a sword.
@export var in_reach := 2.9
## How far in front of itself it holds the sword.
@export var held_out := 0.55
## Where the middle of the blade can be brought, either side and up and down.
@export var sideways := 0.45
@export var up_and_down := Vector2(-0.8, 0.22)

var fighter: Node3D
var rival: Node3D
var arm: Node3D

# What's been seen, oldest first: [seconds ago, where, which way].
var _seen := []
# Where a line being drawn first came in.
var _entry := []
# Seconds left of watching, or if it's less than nothing, of not.
var _attention := 2.0
var _lapsing := false


func start(owner_fighter: Node3D, against: Node3D, its_arm: Node3D) -> void:
	fighter = owner_fighter
	rival = against
	arm = its_arm


func reset() -> void:
	_seen.clear()
	_entry.clear()
	_attention = 1.0
	_lapsing = true


func mind(delta: float, temper: Resource, distance: float, may: bool) -> void:
	_watch(delta, temper.read_delay)
	_attend(delta, temper)
	if _lapsing and not temper.careless and distance < in_reach:
		_lapsing = false
		_attention = temper.watch.x
	if not may or _lapsing or temper.ward_speed <= 0.0 or distance > from_distance or not fighter.is_armed():
		if arm.is_warding():
			arm.lower_guard()
		return
	if _seen.is_empty() or not arm.is_open_to_act():
		return
	var way: Vector2 = _seen[0][2]
	var at := _before_it(_seen[0][1])
	var across := Vector2(-way.x, way.y).orthogonal()
	# Point up, unless it's the legs.
	if (across.y < 0.0) != (at.y < -0.5):
		across = -across
	if not arm.is_warding():
		arm.raise_ward()
	arm.ward_at = arm.ward_at.move_toward(at, temper.ward_speed * delta)
	arm.ward_across = Vector2.from_angle(rotate_toward(arm.ward_across.angle(), across.angle(), temper.ward_turn * delta))


# Nobody can stay ready forever; seeing a line begun wakes them.
func _attend(delta: float, temper: Resource) -> void:
	_attention -= delta
	if rival.drawing and rival.line.size() > 2:
		if _lapsing and _attention > temper.read_delay:
			_attention = temper.read_delay
		elif not _lapsing:
			_attention = maxf(_attention, 0.2)
	if _attention <= 0.0:
		_lapsing = not _lapsing
		var span: Vector2 = temper.lapse if _lapsing else temper.watch
		_attention = randf_range(span.x, span.y)


func _watch(delta: float, late: float) -> void:
	for each in _seen:
		each[0] += delta
	while _seen.size() > 1 and _seen[1][0] >= late:
		_seen.pop_front()
	_seen.append([0.0] + _threat())


# Where a cut would come in, on the player's view, and which way it's going.
func _threat() -> Array:
	var their_arm: Node3D = rival.arm
	if rival.drawing and rival.line.size() > 2:
		var line: PackedVector2Array = rival.line
		var way := (line[-1] - line[maxi(line.size() - 5, 0)]).normalized()
		if _entry.is_empty() and _is_on_us(line[-1]):
			_entry = [line[-1], way]
		return _entry if not _entry.is_empty() else [line[-1] + way * 0.12, way]
	if their_arm.is_attacking():
		return _entry if not _entry.is_empty() else _coming(their_arm.strike.through, their_arm.strike.direction)
	_entry = []
	return _coming(rival.cursor, rival.aim)


# Back along a straight line to where it first comes in.
func _coming(through: Vector2, way: Vector2) -> Array:
	for i in 12:
		var at := through - way * lerpf(0.5, 0.0, i / 11.0)
		if _is_on_us(at):
			return [at - way * 0.07, way]
	return [through - way * 0.06, way]


func _is_on_us(at: Vector2) -> bool:
	var eye: Transform3D = rival.camera.global_transform
	return not fighter.body.touched(eye.origin, eye.origin + eye.basis * rival.arm.ray(at) * 3.5).is_empty()


# The same place, as where to hold a sword.
func _before_it(at: Vector2) -> Vector2:
	var eye: Transform3D = rival.camera.global_transform
	var shoulders: Node3D = arm.get_parent()
	var front := Plane(fighter.facing(), shoulders.global_position + fighter.facing() * held_out)
	var hit = front.intersects_ray(eye.origin, eye.basis * rival.arm.ray(at))
	if hit == null:
		return arm.ward_at
	var local: Vector3 = shoulders.global_transform.affine_inverse() * hit
	return Vector2(clampf(local.x, -sideways, sideways), clampf(local.y, up_and_down.x, up_and_down.y))
