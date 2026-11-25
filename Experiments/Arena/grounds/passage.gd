extends Node

## The way from one clearing to the next. The gate ahead and the gate behind
## are the same inside, so shut in one the player can be put in the other, and
## the doors that open next open on somewhere new.

const Gate = preload("res://Experiments/Arena/grounds/gate.gd")

## Shut in between two clearings.
signal between
## Out in the open, with the doors shut behind.
signal stepped_out

enum { WITHIN, FIGHTING, CLEARED, LEAVING, SHUT }

@export var player: CharacterBody3D
@export var ahead: Gate
@export var behind: Gate
## Seconds shut in before the doors go.
@export var pause := 0.7

var _state := WITHIN
var _turn := 0


## Straight to the beginning of a clearing.
func begin() -> void:
	player.reset_at(behind.global_position + Vector3(0.0, 0.0, 0.8), 0.0)
	_wait_within()


## Nobody going anywhere.
func close() -> void:
	_turn += 1
	_state = SHUT
	ahead.shut(true)
	behind.shut(true)


## Nobody left to stop anyone leaving.
func clear() -> void:
	if _state != FIGHTING:
		return
	_state = CLEARED
	ahead.open()


func _wait_within() -> void:
	_turn += 1
	var turn := _turn
	_state = WITHIN
	ahead.shut(true)
	behind.shut(true)
	await get_tree().create_timer(pause, false).timeout
	if turn == _turn:
		behind.open()


func _physics_process(_delta: float):
	match _state:
		WITHIN:
			if behind.is_open and behind.depth(player.global_position) < -0.9:
				_state = FIGHTING
				behind.shut()
				stepped_out.emit()
		CLEARED:
			if ahead.depth(player.global_position) > 1.6:
				_leave()


func _leave() -> void:
	_state = LEAVING
	var turn := _turn
	ahead.shut()
	await get_tree().create_timer(ahead.shuts_in + 0.1, false).timeout
	if turn != _turn:
		return
	player.global_position += behind.global_position - ahead.global_position
	player.reset_physics_interpolation()
	_wait_within()
	between.emit()
