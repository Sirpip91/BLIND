extends Node

## The player's edge. What's cut is what the point of the sword is seen to
## cross: once its line has gone into something and come out the other side,
## that's the shape it's cut along. A line that stops inside only wounds.

const Region = preload("res://Experiments/SteelGuard/region.gd")

## A blade was in the way.
signal clashed(strike: Resource, at: Vector3)
signal met(strike: Resource, part: Node3D, at: Vector3, region: RefCounted, travel: Vector3)

@export var sword: Node3D
@export var target: Node3D
## How far from the eye it still cuts, and how much further a hard swipe does.
@export var reach := 1.95
@export var reach_swiped := 0.2
@export var thrust_reach := 2.5
## How wide a blade in the way is seen to be, in radians.
@export var blade_width := 0.012
## Times one cut can go through the same thing.
@export var most_cuts := 3

var _strike: Resource
var _stopped := false
var _line := PackedVector2Array()
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
	_line.clear()
	_inside.clear()
	_cuts.clear()


func _sweep(strike: Resource, from: Vector2, to: Vector2) -> void:
	_begin(strike)
	if _line.is_empty():
		_line.append(from)
	_line.append(to)
	var eye: Transform3D = sword.get_parent().global_transform
	var far: float = reach + reach_swiped * strike.power
	_meet_blade(strike, eye, from, to, far)
	var left := []
	for part in target.body.parts:
		if part.gone or _stopped:
			continue
		if _touching(part, eye, from, to, far):
			if not _inside.has(part) and _cuts.get(part, 0) < most_cuts:
				_inside[part] = _line.size() - 2
		elif _inside.has(part):
			left.append(part)
	for part in left:
		_come_out(part, eye)


func _meet_blade(strike: Resource, eye: Transform3D, from: Vector2, to: Vector2, far: float) -> void:
	var blade: Array[Vector3] = target.sword_in_way()
	if blade.is_empty() or _stopped:
		return
	var back := eye.affine_inverse()
	var a: Vector2 = sword.seen_at(back * blade[0])
	var b: Vector2 = sword.seen_at(back * blade[1])
	var near := Geometry2D.get_closest_points_between_segments(from, to, a, b)
	if near[0].distance_to(near[1]) > blade_width:
		return
	var at := blade[0].lerp(blade[1], a.distance_to(near[1]) / maxf(a.distance_to(b), 0.001))
	if eye.origin.distance_to(at) < far:
		# Whatever it was already most of the way through, it's through.
		for part in _inside.keys():
			if _is_past_middle(part, eye):
				_come_out(part, eye)
		_stopped = true
		clashed.emit(strike, at)


func _is_past_middle(part: Node3D, eye: Transform3D) -> bool:
	var back := eye.affine_inverse()
	var a: Vector2 = sword.seen_at(back * part.start())
	var b: Vector2 = sword.seen_at(back * part.end())
	for i in range(_inside[part], _line.size() - 1):
		if Geometry2D.segment_intersects_segment(_line[i], _line[i + 1], a, b) != null:
			return true
	return false


func _touching(part: Node3D, eye: Transform3D, from: Vector2, to: Vector2, far: float) -> bool:
	var back := eye.affine_inverse()
	var a: Vector2 = sword.seen_at(back * part.start())
	var b: Vector2 = sword.seen_at(back * part.end())
	var near := Geometry2D.get_closest_points_between_segments(from, to, a, b)
	var along := a.distance_to(near[1]) / maxf(a.distance_to(b), 0.001)
	var away := eye.origin.distance_to(part.start().lerp(part.end(), along))
	return near[0].distance_to(near[1]) < part.radius / away and away - part.radius < far


func _come_out(part: Node3D, eye: Transform3D) -> void:
	var line := _line.slice(_inside[part])
	_inside.erase(part)
	if part.gone or _stopped or line.size() < 2 or line[0].distance_to(line[-1]) < 0.01:
		return
	var region = Region.from_line(line, eye, sword.ray)
	if region.planes.is_empty():
		return
	_cuts[part] = _cuts.get(part, 0) + 1
	met.emit(_strike, part, _middle(part, line, eye), region, _travel(line, eye))


# Whatever it's still in, it's stuck in.
func _run_out(strike: Resource) -> void:
	if strike != _strike or _stopped:
		return
	var eye: Transform3D = sword.get_parent().global_transform
	for part in _inside:
		if not part.gone and not _stopped:
			var line := _line.slice(_inside[part])
			met.emit(strike, part, _middle(part, line, eye), null, _travel(line, eye))
	_inside.clear()


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
	var eye: Transform3D = sword.get_parent().global_transform
	var ahead := -eye.basis.z
	var nearest := thrust_reach
	var hit: Node3D
	var where := Vector3.ZERO
	for part in target.body.parts:
		if part.gone:
			continue
		var near := Geometry3D.get_closest_points_between_segments(eye.origin, eye.origin + ahead * thrust_reach, part.start(), part.end())
		var away: float = near[1].distance_to(eye.origin) - part.radius
		if near[0].distance_to(near[1]) < part.radius and away < nearest:
			nearest = away
			hit = part
			where = near[1]
	if hit:
		_stopped = true
		met.emit(strike, hit, where, null, ahead)
