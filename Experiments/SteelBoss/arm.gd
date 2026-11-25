extends Node3D

## A fighter's sword, the same for the player and the enemy: winds up, cuts,
## guards, gets knocked aside. Whoever owns it says what to do; it says when
## things land.

const Poses = preload("res://Experiments/SteelBoss/poses.gd")
const Strike = preload("res://Experiments/SteelBoss/strike.gd")

const DRAG_PACE := 0.22

enum Phase { READY, WINDUP, RELEASE, RECOVER, GUARD, BOUNCE, STAGGER, DOWN }

signal wound_up(strike: Strike)
signal released(strike: Strike)
signal struck(strike: Strike)
signal finished(strike: Strike)

## Seconds after a guard goes up, or is swung to a new side, that it parries.
@export var parry_window := 0.2
## A guard put up again sooner than this only blocks, so mashing never parries.
@export var parry_lockout := 0.45
## How far off the side of a blow a guard still meets it.
@export_range(20.0, 120.0, 1.0, "radians_as_degrees") var guard_tolerance := deg_to_rad(60.0)
## Held to be read from the front, for a fighter the player faces.
@export var shown := false
## A blow knocked away mid-pattern still flows into the next.
@export var flow := 0.3
## Follow-on cuts wind up this much quicker.
@export var chain_speed := 0.85

var phase := Phase.READY
var strike: Strike
## The way the next cut would go, so the ready stance can lean into it.
var aim := Vector2(-0.7, -0.7)
var guard_side := Vector2.RIGHT
## The way it was last knocked, as the holder sees it.
var pushed := Vector2.ZERO
## Winds up this much slower: one hand, or a wounded one.
var wind_scale := 1.0
## How far a tired stance has sunk, 0 to 1.
var droop := 0.0
## Layered on top: the sword trailing the view.
var sway := Transform3D.IDENTITY

var _pose: Transform3D
var _from: Transform3D
var _t := 0.0
var _length := 0.0
var _landed := false
var _drag := 0.0
var _bit := false
var _since_raise := 10.0
var _since_fresh := 10.0
var _fresh := 10.0
var _fresh_side := Vector2.ZERO
var _time := 0.0


func _ready():
	_pose = _ready_pose()
	transform = _pose


func is_open_to_act() -> bool:
	return phase == Phase.READY or phase == Phase.GUARD or (phase == Phase.RECOVER and _t > _length * flow)


func is_attacking() -> bool:
	return phase == Phase.WINDUP or phase == Phase.RELEASE


## `eager` cuts again the moment the last one is through.
func begin(next: Strike, speed := 1.0, eager := false) -> bool:
	var freed := (phase == Phase.BOUNCE and _t >= _length * 0.8) or (eager and phase == Phase.RECOVER)
	if not is_open_to_act() and not freed:
		return false
	var chained := phase == Phase.RECOVER
	strike = next
	_enter(Phase.WINDUP, (strike.windup * (chain_speed if chained else 1.0) + strike.delay) * speed * wind_scale)
	_landed = false
	wound_up.emit(strike)
	return true


## Thinking better of it.
func cancel() -> bool:
	if phase != Phase.WINDUP:
		return false
	_enter(Phase.READY)
	return true


## Only one put up on purpose can parry.
func raise_guard(side: Vector2, meant := true) -> bool:
	if phase == Phase.WINDUP:
		cancel()
	if not is_open_to_act():
		return false
	_enter(Phase.GUARD)
	guard_side = side.normalized()
	if meant and _since_raise > parry_lockout:
		_refresh()
	else:
		_fresh = 10.0
		_fresh_side = guard_side
	_since_raise = 0.0
	return true


## Swinging a raised guard to another side can parry too.
func turn_guard(side: Vector2) -> void:
	guard_side = side.normalized()
	if absf(guard_side.angle_to(_fresh_side)) > deg_to_rad(55.0) and _since_fresh > parry_lockout:
		_refresh()


func lower_guard() -> void:
	if phase == Phase.GUARD:
		_enter(Phase.READY)


func covers(from: Vector2) -> bool:
	if phase != Phase.GUARD:
		return false
	return from.length_squared() < 0.01 or absf(guard_side.angle_to(from)) <= guard_tolerance


## Seconds until the blow under way would land.
func time_to_land() -> float:
	match phase:
		Phase.WINDUP:
			return _length - _t + strike.release * 0.5
		Phase.RELEASE:
			return maxf(_length * 0.5 - _t, 0.0)
	return 99.0


func is_fresh() -> bool:
	return _fresh <= parry_window


## Seconds since the guard last went up or changed sides.
func guard_age() -> float:
	return _fresh


## Bites into what it hit and has to be pulled on through.
func drag(seconds: float) -> void:
	if phase == Phase.RELEASE:
		_drag = seconds
		_bit = true


## Stopped by a block: knocked back the way it came.
func bounce(seconds: float) -> void:
	pushed = -strike.direction if strike else Vector2.UP
	_enter(Phase.BOUNCE, seconds)


## Thrown wide by a parry or a hit.
func stagger(seconds: float, push := Vector2.ZERO) -> void:
	pushed = push if push != Vector2.ZERO else (-strike.direction if strike else Vector2(0.5, 0.5))
	_enter(Phase.STAGGER, seconds)


func go_down() -> void:
	_enter(Phase.DOWN)


func reset() -> void:
	_enter(Phase.READY)


## 0 to 1 through the current phase.
func progress() -> float:
	return clampf(_t / _length, 0.0, 1.0) if _length > 0.0 else 0.0


func _ready_pose() -> Transform3D:
	return Poses.ready(aim, shown, droop)


func _refresh() -> void:
	_fresh = 0.0
	_since_fresh = 0.0
	_fresh_side = guard_side


func _enter(next: Phase, seconds := 0.0) -> void:
	phase = next
	_from = _pose
	_t = 0.0
	_drag = 0.0
	_bit = false
	_length = seconds


func _physics_process(delta: float):
	step(delta)


func step(delta: float) -> void:
	_time += delta
	_t += delta * (DRAG_PACE if _drag > 0.0 else 1.0)
	_drag -= delta
	_fresh += delta
	_since_fresh += delta
	_since_raise += delta
	match phase:
		Phase.READY:
			_rest(delta)
		Phase.WINDUP:
			_wind(delta)
		Phase.RELEASE:
			_cut(delta)
		Phase.RECOVER:
			_recover(delta)
			if _t >= _length:
				_enter(Phase.READY)
				finished.emit(strike)
		Phase.GUARD:
			_settle(Poses.guard(guard_side), 24.0, delta)
		Phase.BOUNCE, Phase.STAGGER:
			var out := minf(_t / 0.09, 1.0)
			if out < 1.0:
				_pose = _from.interpolate_with(Poses.thrown(pushed, shown and phase == Phase.STAGGER), 1.0 - pow(1.0 - out, 3.0))
			elif progress() > 0.55:
				_settle(_ready_pose(), 7.0, delta)
			if _t >= _length:
				_enter(Phase.READY)
				finished.emit(strike)
		Phase.DOWN:
			_settle(Poses.droop(), 8.0, delta)
	_place(delta)


func _place(_delta: float) -> void:
	var breathe := Vector3(0.0, sin(_time * 1.7) * 0.004, 0.0)
	transform = Transform3D(sway.basis * _pose.basis, _pose.origin + sway.origin + breathe)


func _rest(delta: float) -> void:
	_settle(_ready_pose(), 9.0, delta)


# Held at the end of the cut, then eased home: the price of missing.
func _recover(delta: float) -> void:
	if progress() > 0.4:
		_settle(_ready_pose(), 7.0, delta)


func _wind(_delta: float) -> void:
	var rise := maxf(_length - strike.delay, 0.01)
	var k := clampf(_t / rise, 0.0, 1.0)
	_pose = _from.interpolate_with(Poses.gather(strike.direction, shown), 1.0 - pow(1.0 - k, 2.6))
	# Coiling a little further for as long as it's held.
	var coil := clampf((_t - rise * 0.6) / 0.6, 0.0, 1.0)
	_pose.origin += Vector3(-strike.direction.x * 0.05, -strike.direction.y * 0.04, 0.05) * coil
	if _t >= _length:
		_enter(Phase.RELEASE, strike.release)
		released.emit(strike)


func _cut(_delta: float) -> void:
	var k := progress()
	var middle := Poses.cut(strike.direction, shown)
	if k < 0.5:
		_pose = _from.interpolate_with(middle, pow(k * 2.0, 1.7))
	else:
		if not _landed:
			_landed = true
			_pose = middle
			struck.emit(strike)
			# Whatever it hit may have stopped it.
			if phase != Phase.RELEASE:
				return
		_pose = middle.interpolate_with(Poses.finish(strike.direction), _follow(k * 2.0 - 1.0))
	if _t >= _length:
		_enter(Phase.RECOVER, strike.recover)


# Pulled on through, rather than flicked past, when it's in something.
func _follow(k: float) -> float:
	return k * k * (3.0 - 2.0 * k) if _bit else 1.0 - pow(1.0 - k, 2.0)


func _settle(to: Transform3D, quickness: float, delta: float) -> void:
	_pose = _pose.interpolate_with(to, 1.0 - exp(-quickness * delta))
