extends "res://Experiments/SteelBoss/arm.gd"

## The sword in the player's hands. It's all one point on the view, the tip,
## and the line it draws: it rests drawn back from the way the mouse points,
## goes off at full speed, runs out, and is carried home from wherever that
## left it. Nothing in between ever stops it.
##
## Places on the view are angles from its middle, in radians, up being up.

## The line the tip has just drawn, while it's cutting.
signal swept(strike: Strike, from: Vector2, to: Vector2)
## It's done cutting.
signal ran_out(strike: Strike)

## How far drawn back it rests.
@export var rest := 0.62
## How far past the middle a slow swipe and a hard one run.
@export var follow_through := Vector2(0.95, 1.5)
## Most a cut can be bent by the mouse while it's going, in radians.
@export_range(0.0, 120.0, 1.0, "radians_as_degrees") var bend_most := deg_to_rad(75.0)
## Above 1 it's spent early: fast out, long to settle.
@export var snap := 2.4
## How far before and after a drawn line the sword runs, not cutting.
@export var run_in := 0.3
@export var run_out := 0.45
## How tightly the tip is held at rest, and how loosely after a cut.
@export var hold_firm := 150.0
@export var hold_loose := 46.0

var tip := Vector2(0.4, 0.45)
var bend := 0.0

var _tip_speed := Vector2.ZERO
var _tip_from := Vector2.ZERO
# The way the edge faces.
var _way := Vector2(-0.7, -0.7)
# A drawn line as the sword takes it, and how far along each point is.
var _track := PackedVector2Array()
var _marks := PackedFloat32Array()
var _along := 0.0
var _blend := 1.0
var _sway_shown := Transform3D.IDENTITY

const BLADE := 0.75


func _ready():
	super()
	# Drawn as often as the screen is, not as often as the world moves.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _physics_process(_delta: float):
	pass


func _process(delta: float):
	if delta > 0.0:
		step(delta)


## Where the tip is seen, as a direction out of the eye.
static func ray(at: Vector2) -> Vector3:
	var r := at.length()
	if r < 0.0001:
		return Vector3.FORWARD
	return Vector3(at.x / r * sin(r), at.y / r * sin(r), -cos(r))


## Where a point in the eye's space is seen.
static func seen_at(point: Vector3) -> Vector2:
	var flat := Vector2(point.x, point.y)
	return flat.normalized() * atan2(flat.length(), -point.z)


## Where a place on the view falls on someone, from where they stand. `eye` is
## who's looking.
static func pin(at: Vector2, eye: Transform3D, on: Vector3) -> Vector3:
	var away := on - eye.origin
	var flat := Vector2(away.x, away.z)
	var along := eye.basis * ray(at)
	var toward := maxf(Vector2(along.x, along.z).dot(flat.normalized()), 0.1)
	return eye.origin + along * flat.length() / toward - on


## And where that's seen from somewhere else.
static func unpin(pinned: Vector3, eye: Transform3D, on: Vector3) -> Vector2:
	return seen_at(eye.affine_inverse() * (on + pinned))


## How far round the blade has to come to start a cut this way, 0 to 1.
func turn_to(way: Vector2) -> float:
	return absf(angle_difference(tip.angle(), (-way).angle())) / PI


func begin(next: Strike, speed := 1.0, eager := false) -> bool:
	if not super(next, speed, eager):
		return false
	_tip_from = tip
	_track.clear()
	_along = 0.0
	bend = 0.0
	if not next.path.is_empty():
		_lay_track(next.path)
	return true


func _enter(next: Phase, seconds := 0.0) -> void:
	# Out of some other pose: carry on from wherever that left the tip.
	if phase in [Phase.GUARD, Phase.BOUNCE, Phase.STAGGER, Phase.DOWN]:
		tip = seen_at(_pose * Vector3(0, BLADE, 0))
		_tip_speed = Vector2.ZERO
		_blend = 0.0
	super(next, seconds)


func _rest(delta: float) -> void:
	_carry(_resting(), hold_firm, delta)


func _wind(delta: float) -> void:
	if strike.is_thrust():
		super(delta)
		tip = Vector2.ZERO
	else:
		# Round the outside to the start of the line, gathering speed into it.
		var k := clampf(_t / maxf(_length, 0.001), 0.0, 1.0)
		k *= k
		var middle := strike.through
		var to := middle - strike.direction * rest if _track.is_empty() else _track[0]
		var out := _tip_from - middle
		var angle := out.angle() + angle_difference(out.angle(), (to - middle).angle()) * k
		tip = middle + Vector2.from_angle(angle) * lerpf(out.length(), (to - middle).length(), k)
		_turn_edge(strike.direction, delta)
		_show(delta)
		if _t >= _length:
			_tip_from = tip
			_enter(Phase.RELEASE, strike.release)
			released.emit(strike)


func _cut(delta: float) -> void:
	if strike.is_thrust():
		super(delta)
		tip = Vector2.ZERO
		return
	if not _track.is_empty():
		_follow_track(delta)
		return
	var was := tip
	var k := 1.0 - pow(1.0 - progress(), snap)
	var d := strike.direction
	var to := strike.through + d.rotated(bend) * lerpf(follow_through.x, follow_through.y, strike.power)
	# From the start, through the middle, and off wherever it's been bent to.
	tip = _tip_from * (1.0 - k) * (1.0 - k) + strike.through * 2.0 * k * (1.0 - k) + to * k * k
	if tip.distance_to(was) > 0.0005:
		_tip_speed = (tip - was) / delta
		_turn_edge((tip - was).normalized(), delta)
		if not _landed and (was - strike.through).dot(d) < 0.0 and (tip - strike.through).dot(d) >= 0.0:
			_landed = true
			struck.emit(strike)
		if phase == Phase.RELEASE:
			swept.emit(strike, was, tip)
	if phase != Phase.RELEASE:
		return
	_show(delta)
	if _t >= _length:
		_spent()


func _spent() -> void:
	ran_out.emit(strike)
	_track.clear()
	if phase == Phase.RELEASE:
		_enter(Phase.RECOVER, strike.recover)


# The line as drawn, with room to come into it and out of it.
func _lay_track(path: PackedVector2Array) -> void:
	_set_track(path)
	_marks = PackedFloat32Array([0.0])
	for i in range(1, _track.size()):
		_marks.append(_marks[-1] + _track[i - 1].distance_to(_track[i]))


func _set_track(path: PackedVector2Array) -> void:
	var into := (path[mini(3, path.size() - 1)] - path[0]).normalized()
	var off := (path[-1] - path[maxi(path.size() - 4, 0)]).normalized()
	_track = PackedVector2Array([path[0] - into * run_in])
	_track.append_array(path)
	_track.append(path[-1] + off * run_out)


# Drawn on someone, it goes where they go.
func _keep_pinned() -> void:
	if strike.pinned_to == null or strike.pins.size() != _track.size() - 2:
		return
	var eye: Transform3D = (get_parent() as Node3D).global_transform
	var path := PackedVector2Array()
	for pinned in strike.pins:
		path.append(unpin(pinned, eye, strike.pinned_to.global_position))
	_set_track(path)


func _follow_track(delta: float) -> void:
	_keep_pinned()
	var far := _marks[-1] * (1.0 - pow(1.0 - progress(), 1.5))
	var was := tip
	# Every corner of it, however much a frame covers.
	for i in range(1, _track.size()):
		if _marks[i] <= _along or _marks[i - 1] >= far:
			continue
		var from := _track_at(i, maxf(_along, _marks[i - 1]))
		var to := _track_at(i, minf(far, _marks[i]))
		# The run in and the run out don't cut.
		if i > 1 and i < _track.size() - 1 and from.distance_to(to) > 0.0005:
			swept.emit(strike, from, to)
		if phase != Phase.RELEASE:
			_track.clear()
			return
		tip = to
	_along = far
	if tip.distance_to(was) > 0.0005:
		_tip_speed = (tip - was) / delta
		_turn_edge((tip - was).normalized(), delta)
	_show(delta)
	if _t >= _length:
		_spent()


func _track_at(i: int, far: float) -> Vector2:
	var span := _marks[i] - _marks[i - 1]
	return _track[i - 1].lerp(_track[i], (far - _marks[i - 1]) / span if span > 0.0 else 1.0)


func _recover(delta: float) -> void:
	if strike.is_thrust():
		super(delta)
		tip = seen_at(_pose * Vector3(0, BLADE, 0))
		_blend = 0.0
		return
	# Let run, then gathered in.
	_carry(_resting(), lerpf(8.0, hold_loose, progress()), delta)


func _ready_pose() -> Transform3D:
	return _shape()


func _resting() -> Vector2:
	return -aim * rest + Vector2(0.1, 0.12)


# A weight on a spring, which is why it never starts or stops dead.
func _carry(to: Vector2, firm: float, delta: float) -> void:
	_tip_speed += ((to - tip) * firm - _tip_speed * 2.0 * sqrt(firm) * 0.9) * delta
	_tip_speed = _tip_speed.limit_length(30.0)
	tip += _tip_speed * delta
	_turn_edge(aim, delta, 12.0)
	_show(delta)


func _turn_edge(way: Vector2, delta: float, quickness := 45.0) -> void:
	_way = Vector2.from_angle(lerp_angle(_way.angle(), way.angle(), 1.0 - exp(-quickness * delta)))


func _show(delta: float) -> void:
	_blend = minf(_blend + delta / 0.12, 1.0)
	_pose = _from.interpolate_with(_shape(), smoothstep(0.0, 1.0, _blend)) if _blend < 1.0 else _shape()


# The tip is on its line, the hands lead it, and the blade is what's between.
func _shape() -> Transform3D:
	var lead := tip + _way * 0.4
	var hands := Vector3(0.07 + clampf(lead.x, -1.2, 1.2) * 0.26, -0.27 + clampf(lead.y, -1.2, 1.2) * 0.1, -0.42)
	var at := ray(tip) * lerpf(1.16, 0.9, clampf(tip.length() / 1.6, 0.0, 1.0))
	var blade := (at - hands).normalized()
	var across := Vector3(_way.x, _way.y, 0.0)
	var flat := blade.cross(across - blade * across.dot(blade)).normalized()
	return Poses.pose(at - blade * BLADE, blade, (flat + Vector3.BACK * 0.35).normalized())


func _place(delta: float) -> void:
	_sway_shown = _sway_shown.interpolate_with(sway, 1.0 - exp(-30.0 * delta))
	var breathe := Vector3(0.0, sin(_time * 1.7) * 0.004, 0.0)
	transform = Transform3D(_sway_shown.basis * _pose.basis, _pose.origin + _sway_shown.origin + breathe)
