extends Node

## Health, and how close a fighter's composure is to breaking. Composure
## breaking leaves them open to one terrible blow.

signal hurt(amount: float)
signal cracked(amount: float)
signal broke
signal recovered
signal died

@export var max_health := 100.0
## Pressure it takes to break.
@export var max_pressure := 100.0
## Pressure lost a second, once left alone for a while.
@export var calm := 5.0
@export var calm_after := 5.0
@export var open_time := 2.6
## What that blow takes.
@export var open_damage := 75.0

var health := 100.0
var pressure := 0.0
var dead := false
var open_left := 0.0

var _left_alone := 0.0


func _ready():
	reset()


func reset() -> void:
	health = max_health
	pressure = 0.0
	dead = false
	open_left = 0.0


func is_open() -> bool:
	return open_left > 0.0 and not dead


func wound(amount: float) -> void:
	if dead:
		return
	if is_open():
		amount = open_damage
		open_left = 0.0
		pressure = max_pressure * 0.3
	health -= amount
	hurt.emit(amount)
	if health <= 0.0:
		dead = true
		open_left = 0.0
		died.emit()


func press(amount: float) -> void:
	if dead or is_open():
		return
	_left_alone = 0.0
	pressure = minf(pressure + amount, max_pressure)
	cracked.emit(amount)
	if pressure >= max_pressure:
		open_left = open_time
		broke.emit()


func _physics_process(delta: float):
	if dead:
		return
	if open_left > 0.0:
		open_left -= delta
		if open_left <= 0.0:
			# Worn thin: it breaks sooner the next time.
			pressure = max_pressure * 0.35
			recovered.emit()
		return
	_left_alone += delta
	if _left_alone > calm_after:
		pressure = maxf(pressure - calm * delta, 0.0)
