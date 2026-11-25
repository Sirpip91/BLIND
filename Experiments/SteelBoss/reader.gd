extends Node

## A master's eye. It stops anything it can see coming: it watches a line from
## the moment it's begun and guards the way it sets out. What beats it is being
## wrong about that, or having no sword to guard with. It's only wrong the same
## way once.

signal tricked

const Strike = preload("res://Experiments/SteelBoss/strike.gd")

## How far a line has to have turned, between setting out and coming in.
@export_range(20.0, 120.0, 1.0, "radians_as_degrees") var turn := deg_to_rad(50.0)
## Tricks it'll remember at once.
@export var remembers := 2
## Plain cuts that get by it anyhow.
@export_range(0.0, 1.0, 0.01) var lapses := 0.06
## How far into its own attack it can still think better of it.
@export_range(0.0, 1.0, 0.05) var commits := 0.6
## Seconds a line begun and dropped keeps it looking the wrong way.
@export var taken_in := 0.4

var fighter: Node3D
var rival: Node3D
var arm: Node3D
var brain: Node
## What it makes of the cut on its way: "block", "trade" or "through".
var verdict := "through"

var _known: Array[String] = []
var _feint := 0.0
var _feint_way := Vector2.ZERO


func start(owner_fighter: Node3D, against: Node3D) -> void:
	fighter = owner_fighter
	rival = against
	arm = fighter.arm
	brain = fighter.brain
	rival.arm.wound_up.connect(_judge)


func reset() -> void:
	verdict = "through"
	_known.clear()
	_feint = 0.0


func _physics_process(delta: float):
	if fighter == null:
		return
	_feint -= delta
	if not rival.drawing or rival.line.size() < 5 or not _is_free():
		return
	_feint_way = _setting_out(rival.line)
	_feint = taken_in
	_guard(_feint_way, 0.3)


func _is_free() -> bool:
	return arm.is_open_to_act() and fighter.is_armed() and brain.is_on_its_feet()


func _judge(strike: Strike) -> void:
	verdict = "through"
	var caught: bool = arm.phase in [arm.Phase.STAGGER, arm.Phase.DOWN]
	if strike.earned or caught or not fighter.is_armed() or fighter.vitals.dead or brain.is_helpless():
		strike.earned = strike.earned or caught or brain.is_helpless()
		return
	if arm.is_attacking() and not (arm.phase == arm.Phase.WINDUP and arm.progress() < commits):
		# Too late to stop: it takes the touch, and gives the blow.
		verdict = "trade"
		return
	var out := strike.direction
	var into := strike.direction
	var trick := ""
	if strike.is_thrust():
		trick = "thrust"
	elif not strike.path.is_empty():
		out = _setting_out(strike.path)
		into = _coming_in(strike.path, out)
		if absf(out.angle_to(into)) > turn:
			trick = "from %d" % wrapi(roundi(into.angle() / (PI / 3.0)), 0, 6)
	elif _feint > 0.0 and absf(_feint_way.angle_to(out)) > PI * 0.5:
		trick = "feint"
		out = _feint_way
	if (trick != "" and not _known.has(trick)) or (trick == "" and randf() < lapses):
		if trick != "":
			_known.append(trick)
			if _known.size() > remembers:
				_known.pop_front()
			tricked.emit()
		# Guarding, and against the wrong thing.
		if not strike.is_thrust():
			_guard(out, 0.3)
		strike.earned = true
		return
	verdict = "block"
	brain.break_off()
	arm.reset()
	_guard(into if not strike.is_thrust() else Vector2.DOWN, 0.5)


func _guard(way: Vector2, seconds: float) -> void:
	var side := Vector2(way.x, -way.y)
	if arm.phase == arm.Phase.GUARD:
		arm.guard_side = side
	else:
		arm.raise_guard(side)
	brain.hold_guard(seconds)


# The way a line starts off.
func _setting_out(line: PackedVector2Array) -> Vector2:
	for i in range(1, line.size()):
		if line[i].distance_to(line[0]) > 0.1:
			return (line[i] - line[0]).normalized()
	return (line[-1] - line[0]).normalized()


# The way it goes once it's got to us.
func _coming_in(line: PackedVector2Array, otherwise: Vector2) -> Vector2:
	var eye: Transform3D = rival.camera.global_transform
	for i in line.size():
		var sight: Vector3 = eye.basis * rival.arm.ray(line[i])
		if fighter.body.in_sight(eye.origin, eye.origin + sight * 3.5):
			var on := mini(i + 4, line.size() - 1)
			return (line[on] - line[i]).normalized() if on > i else otherwise
	return otherwise
