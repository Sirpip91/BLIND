extends Node

## How much more a body can take, and how near its wits are to their end.

signal died
## It would have, and hasn't.
signal held_on

## Wounds it takes to bring down, where no single cut has already done it.
@export var max_health := 2.0
## Pressure it takes to be worn out.
@export var max_pressure := 140.0
## Pressure lost a second, once left alone for a while.
@export var calm := 4.0
@export var calm_after := 4.0

var health := 2.0
var pressure := 0.0
var dead := false
## Not to be killed yet.
var holds_on := false

var _left_alone := 0.0


func _ready():
	reset()


func reset() -> void:
	health = max_health
	pressure = 0.0
	dead = false
	holds_on = false


func weariness() -> float:
	return pressure / max_pressure


func wound(amount: float) -> void:
	if dead:
		return
	health -= amount
	if health <= 0.001:
		kill()


func mend(amount: float) -> void:
	if not dead:
		health = minf(health + amount, max_health)


func kill() -> void:
	if dead:
		return
	if holds_on:
		health = max_health
		held_on.emit()
		return
	dead = true
	health = 0.0
	died.emit()


func press(amount: float) -> void:
	_left_alone = 0.0
	pressure = minf(pressure + amount, max_pressure)


func _physics_process(delta: float):
	_left_alone += delta
	if not dead and _left_alone > calm_after:
		pressure = maxf(pressure - calm * delta, 0.0)
