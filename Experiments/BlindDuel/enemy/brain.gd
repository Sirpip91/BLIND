extends Node

## Decides where to walk and when to strike: circles, goes quiet, closes in,
## strikes one or more times, backs away.

const Attack = preload("res://Experiments/BlindDuel/enemy/attack.gd")

enum { STALK, WAIT, CLOSE, ATTACK, BACK_OFF, REEL, OUT }

signal wants_attack(attack: Attack)

@export var attacks: Array[Attack] = []
@export var stalk_distance := 4.2
@export var stalk_speed := 1.5
@export var close_speed := 3.2
@export var back_off_speed := 2.2
@export var stalk_time := Vector2(1.2, 2.8)
## Standing still makes no sound at all.
@export var wait_time := Vector2(0.4, 1.0)
@export_range(0.0, 1.0, 0.05) var chance_to_wait := 0.4
@export var most_in_a_row := 3

var state := STALK
var attack: Attack

var _left := 2.0
var _around := 1.0
var _struck := 0


## The velocity it wants, given where the player is.
func decide(delta: float, to_target: Vector3, room_ahead: bool) -> Vector3:
	_left -= delta
	var distance := to_target.length()
	var toward := to_target / maxf(distance, 0.001)
	match state:
		STALK:
			if _left <= 0.0:
				if randf() < chance_to_wait:
					_enter(WAIT, randf_range(wait_time.x, wait_time.y))
				else:
					_begin_close()
			var sideways := toward.cross(Vector3.UP) * _around
			var correction := toward * clampf(distance - stalk_distance, -1.0, 1.0)
			# Up against the edge, give up the distance rather than the circle.
			if not room_ahead:
				correction = toward
			return (sideways + correction).normalized() * stalk_speed
		WAIT:
			if _left <= 0.0:
				_begin_close()
		CLOSE:
			if distance <= attack.reach * 0.8:
				_enter(ATTACK, 0.0)
				_struck = 1
				wants_attack.emit(attack)
				return Vector3.ZERO
			return toward * close_speed
		BACK_OFF:
			if _left <= 0.0 or not room_ahead:
				_around = 1.0 if randf() < 0.5 else -1.0
				_enter(STALK, randf_range(stalk_time.x, stalk_time.y))
			return -toward * back_off_speed
		REEL:
			if _left <= 0.0:
				_enter(BACK_OFF, 0.6)
	return Vector3.ZERO


## The swing is over: go again, or give ground.
func attack_finished(to_target: Vector3) -> void:
	if state != ATTACK:
		return
	if _struck < most_in_a_row and randf() < attack.chance_to_chain and to_target.length() < attack.reach * 1.4:
		_struck += 1
		attack = attacks.pick_random()
		wants_attack.emit(attack)
	else:
		_enter(BACK_OFF, randf_range(0.7, 1.2))


func reel(seconds: float) -> void:
	_enter(REEL, seconds)


func knock_out() -> void:
	_enter(OUT, 0.0)


func wake() -> void:
	_enter(STALK, randf_range(stalk_time.x, stalk_time.y))


func _begin_close() -> void:
	attack = attacks.pick_random()
	_enter(CLOSE, 0.0)


func _enter(next: int, seconds: float) -> void:
	state = next
	_left = seconds
