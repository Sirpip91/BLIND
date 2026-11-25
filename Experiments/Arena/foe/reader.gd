extends Node

## A trained eye. It stops what it can see coming: it watches a line from the
## moment it's begun and guards the way it sets out. What beats it is being
## wrong about that, or having no sword to guard with. Which parts of this a
## foe has is up to its kind.

signal tricked
signal stepped(way: Vector3)

const Strike = preload("res://Experiments/Arena/fighter/strike.gd")

## How far a line has to have turned, between setting out and coming in.
@export_range(20.0, 120.0, 1.0, "radians_as_degrees") var turn := deg_to_rad(50.0)
## How far into its own attack it can still think better of it.
@export_range(0.0, 1.0, 0.05) var commits := 0.6
## Seconds a line begun and dropped keeps it looking the wrong way.
@export var taken_in := 0.4
## Metres a second it steps aside at.
@export var step_speed := 8.5

var on := false
var stops := 0.94
var watches := true
var remembers := 2
var knows_hooks := false
var knows_feints := false
var knows_thrusts := false
var iron := true
var steps := 0
var breath := 2.2

var fighter: Node3D
var rival: Node3D
var arm: Node3D
var brain: Node
## What it makes of the cut on its way: "block", "step", "trade" or "through".
var verdict := "through"

var _known: Array[String] = []
var _feint := 0.0
var _feint_way := Vector2.ZERO
var _stepped := 0
var _breath := 0.0


func start(owner_fighter: Node3D, against: Node3D) -> void:
	fighter = owner_fighter
	rival = against
	arm = fighter.arm
	brain = fighter.brain
	rival.arm.wound_up.connect(_judge)


## Out of breath, for anyone who can step and has.
func is_winded() -> bool:
	return _stepped >= steps and _breath > 0.0


func _physics_process(delta: float):
	if not on or fighter == null:
		return
	_feint -= delta
	_breath -= delta
	if _breath <= 0.0:
		_stepped = 0
	if not watches or not rival.drawing or rival.line.size() < 5 or not _is_free():
		return
	_feint_way = _setting_out(rival.line)
	_feint = taken_in
	_guard(_feint_way, 0.3)


func _is_free() -> bool:
	return arm.is_open_to_act() and fighter.is_armed() and brain.is_on_its_feet()


func _judge(strike: Strike) -> void:
	if not on or fighter.vitals.dead:
		return
	verdict = "through"
	var caught: bool = arm.phase in [arm.Phase.STAGGER, arm.Phase.DOWN] or brain.is_helpless()
	if strike.earned or strike.sunder or caught or not fighter.is_armed():
		strike.earned = true
		return
	if arm.is_attacking() and not (arm.phase == arm.Phase.WINDUP and arm.progress() < commits):
		# Too late to stop: it takes the touch, and gives the blow.
		verdict = "trade"
		strike.earned = not iron
		return
	var out := strike.direction
	var into := strike.direction
	var trick := ""
	var known := false
	if strike.is_thrust():
		trick = "thrust"
		known = knows_thrusts
	elif not strike.path.is_empty():
		out = _setting_out(strike.path)
		into = _coming_in(strike.path, out)
		if absf(out.angle_to(into)) > turn:
			trick = "from %d" % wrapi(roundi(into.angle() / (PI / 3.0)), 0, 6)
			known = knows_hooks
	elif _feint > 0.0 and absf(_feint_way.angle_to(out)) > PI * 0.5:
		trick = "feint"
		out = _feint_way
		known = knows_feints
	if steps > 0:
		_step_or_not(strike, trick, known)
		return
	if trick == "" and randf() > stops:
		strike.earned = true
		return
	if trick != "" and not known and not _known.has(trick):
		_learn(trick)
		# Guarding, and against the wrong thing.
		if not strike.is_thrust():
			_guard(out, 0.3)
		strike.earned = true
		return
	verdict = "block"
	brain.break_off()
	arm.reset()
	_guard(into if not strike.is_thrust() else Vector2.DOWN, 0.5)


# Gone the way the blade was going, before it got there. A line long enough,
# or the wrong way round, finds it anyway; so does one too many.
func _step_or_not(strike: Strike, trick: String, known: bool) -> void:
	if _stepped >= steps or (trick != "" and not known and not _known.has(trick)):
		if trick != "":
			_learn(trick)
		strike.earned = true
		return
	verdict = "step"
	strike.earned = true
	# Where it was, and not where it's gone.
	strike.pinned_to = null
	_stepped += 1
	_breath = breath
	brain.break_off()
	arm.cancel()
	var away: Vector3 = (fighter.global_position - rival.global_position).normalized()
	var side: Vector3 = rival.camera.global_basis.x * (signf(strike.direction.x) if absf(strike.direction.x) > 0.25 else [-1.0, 1.0].pick_random())
	var way := (side + away * 0.45).normalized()
	fighter.push(way * step_speed)
	stepped.emit(way)


func _learn(trick: String) -> void:
	tricked.emit()
	_known.append(trick)
	while _known.size() > remembers:
		_known.pop_front()


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
			var on_to := mini(i + 4, line.size() - 1)
			return (line[on_to] - line[i]).normalized() if on_to > i else otherwise
	return otherwise
