extends Node

## The player's edge. What's cut is what the point of the sword is seen to
## cross: once its line has gone into something and come out the other side,
## that's the shape it's cut along. A line that stops inside only wounds.

const Region = preload("res://Experiments/Arena/cutting/region.gd")

signal reached(strike: Resource, foe: Node3D, way: Vector2)
signal met(strike: Resource, foe: Node3D, part: Node3D, at: Vector3, region: RefCounted, travel: Vector3)

@export var sword: Node3D
## How far from the eye it still cuts, and how much further a hard swipe
## does, and one into an opening.
@export var reach := 1.95
@export var reach_swiped := 0.2
@export var reach_earned := 0.5
@export var thrust_reach := 2.5
## Times one cut can go through the same thing.
@export var most_cuts := 3

## Everyone who can be cut.
var foes: Array[Node3D] = []

var _strike: Resource
var _stopped := false
# For each foe, the line so far as places on them, so stepping in doesn't bend
# it.
var _lines := {}
# What the line is inside of, and how many points along it went in.
var _inside := {}
var _cuts := {}


func _ready():
	sword.swept.connect(_sweep)
	sword.ran_out.connect(_run_out)
	sword.struck.connect(_thrust)


## Stopped by something: it cuts nothing more.
func spend(strike: Resource) -> void:
	_begin(strike)
	_stopped = true


func _begin(strike: Resource) -> void:
	if strike == _strike:
		return
	_strike = strike
	_stopped = false
	_lines.clear()
	_inside.clear()
	_cuts.clear()


func _eye() -> Transform3D:
	return sword.get_parent().global_transform


func _is_near(foe: Node3D, eye: Transform3D) -> bool:
	if foe.is_unseen():
		return false
	var to := foe.global_position - eye.origin
	to.y = 0.0
	return to.length() < 4.0 and to.normalized().dot(-eye.basis.z) > -0.2


func _sweep(strike: Resource, from: Vector2, to: Vector2) -> void:
	_begin(strike)
	var eye := _eye()
	var far: float = reach + reach_swiped * strike.power + (reach_earned if strike.earned else 0.0)
	for foe in foes:
		if _stopped:
			return
		if _is_near(foe, eye):
			_sweep_foe(strike, foe, eye, from, to, far)


func _sweep_foe(strike: Resource, foe: Node3D, eye: Transform3D, from: Vector2, to: Vector2, far: float) -> void:
	if not _lines.has(foe):
		_lines[foe] = PackedVector3Array([sword.pin(from, eye, foe.global_position)])
	_lines[foe].append(sword.pin(to, eye, foe.global_position))
	var left := []
	for part in foe.body.parts:
		if part.gone or _stopped:
			continue
		if _touching(part, eye, from, to, far):
			if not _inside.has(part) and _cuts.get(part, 0) < most_cuts:
				_inside[part] = [foe, _lines[foe].size() - 2]
				reached.emit(strike, foe, (to - from).normalized())
		elif _inside.has(part):
			left.append(part)
	for part in left:
		_come_out(part, eye)


func _touching(part: Node3D, eye: Transform3D, from: Vector2, to: Vector2, far: float) -> bool:
	var back := eye.affine_inverse()
	var a: Vector2 = sword.seen_at(back * part.start())
	var b: Vector2 = sword.seen_at(back * part.end())
	var near := Geometry2D.get_closest_points_between_segments(from, to, a, b)
	var along := a.distance_to(near[1]) / maxf(a.distance_to(b), 0.001)
	var away := eye.origin.distance_to(part.start().lerp(part.end(), along))
	return near[0].distance_to(near[1]) < part.radius / away and away - part.radius < far


func _come_out(part: Node3D, eye: Transform3D) -> void:
	var foe: Node3D = _inside[part][0]
	var line := _seen(foe, _inside[part][1], eye)
	_inside.erase(part)
	if part.gone or _stopped or line.size() < 2 or line[0].distance_to(line[-1]) < 0.01:
		return
	var region = Region.from_line(line, eye, sword.ray)
	if region.planes.is_empty():
		return
	_cuts[part] = _cuts.get(part, 0) + 1
	met.emit(_strike, foe, part, _middle(part, line, eye), region, _travel(line, eye))


# Whatever it's still in, it's stuck in.
func _run_out(strike: Resource) -> void:
	if strike != _strike or _stopped:
		return
	var eye := _eye()
	for part in _inside:
		if not part.gone and not _stopped:
			var foe: Node3D = _inside[part][0]
			var line := _seen(foe, _inside[part][1], eye)
			met.emit(strike, foe, part, _middle(part, line, eye), null, _travel(line, eye))
	_inside.clear()


func _seen(foe: Node3D, from: int, eye: Transform3D) -> PackedVector2Array:
	var line := PackedVector2Array()
	for each: Vector3 in _lines[foe].slice(from):
		line.append(sword.unpin(each, eye, foe.global_position))
	return line


func _middle(part: Node3D, line: PackedVector2Array, eye: Transform3D) -> Vector3:
	var seen: Vector3 = eye.basis * sword.ray(line[line.size() / 2])
	return Geometry3D.get_closest_points_between_segments(eye.origin, eye.origin + seen * 4.0, part.start(), part.end())[1]


func _travel(line: PackedVector2Array, eye: Transform3D) -> Vector3:
	var way := (line[-1] - line[0]).normalized()
	return eye.basis * Vector3(way.x, way.y, 0.0)


func _thrust(strike: Resource) -> void:
	_begin(strike)
	if not strike.is_thrust() or _stopped:
		return
	var eye := _eye()
	var ahead := -eye.basis.z
	var nearest := thrust_reach
	var hit: Node3D
	var whose: Node3D
	var where := Vector3.ZERO
	for foe in foes:
		if not _is_near(foe, eye):
			continue
		for part in foe.body.parts:
			if part.gone:
				continue
			var near := Geometry3D.get_closest_points_between_segments(eye.origin, eye.origin + ahead * thrust_reach, part.start(), part.end())
			var away: float = near[1].distance_to(eye.origin) - part.radius
			if near[0].distance_to(near[1]) < part.radius and away < nearest:
				nearest = away
				hit = part
				whose = foe
				where = near[1]
	if hit == null:
		return
	reached.emit(strike, whose, Vector2.ZERO)
	if not _stopped:
		_stopped = true
		met.emit(strike, whose, hit, where, null, ahead)
