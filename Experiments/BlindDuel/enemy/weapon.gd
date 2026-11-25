extends Node3D

## Holds the enemy's sword and swings it through an attack's poses. The
## sharp edge of the model is on -X.

const Attack = preload("res://Experiments/BlindDuel/enemy/attack.gd")

## The gather is done and the blow is on its way.
signal struck(attack: Attack)
signal landed(attack: Attack)
signal finished

# Across the body, flat of the blade toward whoever it's facing.
@export var rest_at := Vector3(0.26, 0.95, -0.38)
@export var rest_blade := Vector3(-0.62, 0.8, -0.2)
@export var rest_flat := Vector3.FORWARD

var _swing: Tween


func _ready():
	transform = _pose(rest_at, rest_blade, rest_flat)


func play(attack: Attack) -> void:
	var flat := attack.gather_blade.normalized().cross(attack.strike_blade.normalized())
	flat = flat.normalized() if flat.length() > 0.2 else Vector3.UP
	var gather := _pose(attack.gather_at, attack.gather_blade, flat)
	var strike := _pose(attack.strike_at, attack.strike_blade, flat)
	_start()
	_swing.tween_method(_blend.bind(transform, gather), 0.0, 1.0, attack.windup).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_swing.tween_callback(func(): struck.emit(attack))
	_swing.tween_method(_blend.bind(gather, strike), 0.0, 1.0, attack.strike).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_swing.tween_callback(func(): landed.emit(attack))
	_swing.tween_interval(attack.recover)
	_swing.tween_callback(func(): finished.emit())


## Knocked back out of whatever it was doing.
func throw_back() -> void:
	_move(_pose(Vector3(0.45, 1.5, 0.15), Vector3(0.7, 0.8, 0.5), Vector3.BACK), 0.12, Tween.TRANS_EXPO)


## Hanging at its side, point down.
func droop() -> void:
	_move(_pose(Vector3(0.34, 0.95, -0.1), Vector3(0.1, -1.0, -0.25), Vector3.LEFT), 0.35, Tween.TRANS_CUBIC)


func rest(seconds := 0.35) -> void:
	var resting := _pose(rest_at, rest_blade, rest_flat)
	if seconds <= 0.0:
		_start()
		transform = resting
		_swing.kill()
	else:
		_move(resting, seconds, Tween.TRANS_SINE)


func _move(to: Transform3D, seconds: float, transition: Tween.TransitionType) -> void:
	_start()
	_swing.tween_method(_blend.bind(transform, to), 0.0, 1.0, seconds).set_ease(Tween.EASE_OUT).set_trans(transition)


func _start() -> void:
	if _swing:
		_swing.kill()
	_swing = create_tween()


func _blend(t: float, from: Transform3D, to: Transform3D) -> void:
	transform = from.interpolate_with(to, t)


func _pose(at: Vector3, blade: Vector3, flat: Vector3) -> Transform3D:
	var y := blade.normalized()
	var x := y.cross(flat).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), at)
