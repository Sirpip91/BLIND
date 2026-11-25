extends Node

## Health and posture. Posture fills from parries and blocks; full, the
## enemy is open to an execution for a moment.

signal opened
signal recovered
signal died

@export var max_health := 100.0
@export var max_posture := 100.0
@export var parry_pressure := 40.0
@export var block_pressure := 8.0
@export var posture_recovery := 8.0
## Seconds without pressure before posture starts to drain.
@export var breather := 4.0
@export var open_time := 2.5

var health := 0.0
var posture := 0.0
var open_left := 0.0
var dead := false

var _calm := 0.0


func _ready():
	reset()


func reset() -> void:
	health = max_health
	posture = 0.0
	open_left = 0.0
	dead = false


func is_open() -> bool:
	return open_left > 0.0 and not dead


## True if this was the blow that killed it.
func hurt(damage: float) -> bool:
	if dead:
		return false
	health -= damage * (2.0 if is_open() else 1.0)
	if health > 0.0:
		return false
	dead = true
	open_left = 0.0
	died.emit()
	return true


func press(amount: float) -> void:
	if dead or is_open():
		return
	_calm = 0.0
	posture += amount
	if posture >= max_posture:
		posture = 0.0
		open_left = open_time
		opened.emit()


func _process(delta):
	if open_left > 0.0:
		open_left -= delta
		if open_left <= 0.0 and not dead:
			recovered.emit()
		return
	_calm += delta
	if _calm > breather:
		posture = maxf(posture - posture_recovery * delta, 0.0)
