extends Node

## What makes several of them a group: who goes in and who goes with them,
## where the rest stand, and that no two blows land so close together that
## nobody could meet both.

## Seconds between any two blows landing. Less than a guard takes to be put
## up again and nothing could be done about the second.
@export var apart := 0.5
## Chance someone goes in with whoever goes in, and that it's a third too.
@export_range(0.0, 1.0, 0.05) var company := 0.7
@export_range(0.0, 1.0, 0.05) var crowding := 0.35
## Seconds between one wave of them and the next.
@export var breath := Vector2(0.45, 1.1)
## Chance the first of them is only there to be looked at.
@export_range(0.0, 1.0, 0.05) var bait := 0.3
## How far round to either side of the player they spread.
@export_range(20.0, 160.0, 1.0, "radians_as_degrees") var spread := deg_to_rad(78.0)
## Nobody strikes from further round than this.
@export_range(40.0, 180.0, 1.0, "radians_as_degrees") var in_view := deg_to_rad(82.0)

var foes: Array[Node3D] = []
var player: Node3D
var at_once := 1
var spacing := 0.9

var _since := 10.0
# How long since anyone was in there, and how long that has to be.
var _calm := 10.0
var _breath := 0.0
# The ways the last few blows came.
var _thrown: Array[Vector2] = []


func reset(new_at_once: int, new_spacing: float, new_in_view: float) -> void:
	in_view = new_in_view
	spread = maxf(new_in_view - 0.07, 1.0)
	at_once = new_at_once
	spacing = new_spacing
	_since = 10.0
	_calm = 10.0
	_thrown.clear()


func standing() -> Array[Node3D]:
	return foes.filter(func(foe): return not foe.vitals.dead and not foe.image)


## Leave to go in. They go in waves, but one answering something can join any.
func ask(who: Node3D, answering := false) -> bool:
	var going := _going(who)
	if going >= at_once or (going > 0 and _since < spacing):
		return false
	if is_crowd():
		if absf(bearing(who)) > in_view or (not answering and (going > 0 or _calm < _breath)):
			return false
	_since = 0.0
	if is_crowd() and going == 0 and not answering and randf() < company:
		_send_with(who)
	return true


# From as far round as can be, so there are two ways to look at once.
func _send_with(who: Node3D) -> void:
	var ready := standing().filter(func(foe): return foe != who and foe.brain.could_join() and absf(bearing(foe)) < in_view)
	if ready.is_empty():
		return
	ready.sort_custom(func(a, b): return absf(wrapf(bearing(a) - bearing(who), -PI, PI)) > absf(wrapf(bearing(b) - bearing(who), -PI, PI)))
	var many := 2 if at_once > 2 and randf() < crowding else 1
	for foe in ready.slice(0, mini(many, at_once - 1)):
		foe.brain.join()
	if randf() < bait:
		who.brain.only_pretend()


func _going(but: Node3D) -> int:
	return standing().filter(func(foe): return foe != but and foe.brain.is_engaged()).size()


## How much longer a blow has to be held back to land clear of the others.
func hold_back(who: Node3D, lands_in: float) -> float:
	var others: Array[float] = []
	for foe in standing():
		if foe != who and not foe.brain.is_pretending() and foe.arm.time_to_land() < 5.0:
			others.append(foe.arm.time_to_land())
	others.sort()
	var at := lands_in
	for other in others:
		if absf(at - other) < apart:
			at = other + apart
	return at - lands_in


## How fresh a way of coming in is, from 0 to 1.
func freshness(way: Vector2) -> float:
	var fresh := 1.0
	for i in _thrown.size():
		var same := way.dot(_thrown[i]) > 0.75 or (way == Vector2.ZERO and _thrown[i] == Vector2.ZERO)
		if same:
			fresh *= 0.15 + 0.25 * (_thrown.size() - 1 - i)
	return clampf(fresh, 0.02, 1.0)


func note(way: Vector2) -> void:
	_thrown.append(way)
	if _thrown.size() > 3:
		_thrown.pop_front()


## Which way round the player someone is from where they're looking. Right is
## positive.
func bearing(foe: Node3D) -> float:
	var to := foe.global_position - player.global_position
	var ahead: Vector3 = player.facing()
	return atan2(to.dot(ahead.cross(Vector3.UP)), to.dot(ahead))


## Where to be round the player while waiting, the same way, and how far back.
func place_for(who: Node3D) -> Vector2:
	var waiting := standing().filter(func(foe): return not foe.brain.is_engaged() or foe == who)
	waiting.sort_custom(func(a, b): return bearing(a) < bearing(b))
	var i := waiting.find(who)
	var many := waiting.size()
	# Never all in front: the ends go out to the sides first.
	var wide := spread * (0.75 if many < 3 else 1.0)
	var at := lerpf(-wide, wide, float(i) / (many - 1)) if many > 1 else 0.0
	return Vector2(at, 0.0 if i % 2 == 0 else 0.9)


## One of them is down. Some take it hard.
func lost_one() -> void:
	_breath *= 0.5
	for foe in standing():
		foe.brain.take_it(randf_range(0.3, 1.1))


## Room kept from the others, as a velocity.
func room_for(who: Node3D) -> Vector3:
	var away := Vector3.ZERO
	for foe in foes:
		if foe == who or foe.vitals.dead:
			continue
		var from := who.global_position - foe.global_position
		from.y = 0.0
		var near := from.length()
		if near > 0.01 and near < 1.5:
			away += from / near * (1.5 - near) * 1.4
	return away


func is_crowd() -> bool:
	return standing().size() > 1


func _physics_process(delta: float):
	_since += delta
	if _going(null) > 0:
		if _calm > 0.0:
			_breath = randf_range(breath.x, breath.y)
		_calm = 0.0
	else:
		_calm += delta
