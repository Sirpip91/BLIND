extends CharacterBody3D

## Ties an enemy's parts together and is what the player's sword talks to.
## The parts don't know about each other: swap the weapon, body or attack
## list and it's a different enemy.

const Attack = preload("res://Experiments/BlindDuel/enemy/attack.gd")

signal stepped(at: Vector3, strength: float)
signal opened
signal closed
signal died

@export var target: Node3D
## Asked how each blow is met: receive_strike(from, blockable) -> "parry",
## "block" or "hit".
@export var guard: Node
## How hard its blows land on the player.
@export var hit_force := 1.0
@export var arena_radius := 10.0
## Seconds it can be seen after swords clash.
@export var clash_reveal := 1.6

@onready var vitals: Node = $Vitals
@onready var brain: Node = $Brain
@onready var weapon: Node3D = $Weapon
@onready var footsteps: Node = $Footsteps
@onready var veil: Node = $Veil

var _knock := Vector3.ZERO


func _ready():
	footsteps.stepped.connect(func(at, strength): stepped.emit(at, strength))
	brain.wants_attack.connect(_on_wants_attack)
	weapon.struck.connect(_on_struck)
	weapon.landed.connect(_on_landed)
	weapon.finished.connect(_on_finished)
	vitals.opened.connect(_on_opened)
	vitals.recovered.connect(_on_recovered)
	vitals.died.connect(_on_died)


func appear(at: Vector3) -> void:
	global_position = at
	reset_physics_interpolation()
	_knock = Vector3.ZERO
	vitals.reset()
	veil.hide_now()
	weapon.rest(0.0)
	brain.wake()


func _physics_process(delta):
	var to_target := _to_target()
	var wanted := Vector3.ZERO
	if not vitals.dead:
		var flat := Vector3(global_position.x, 0, global_position.z)
		wanted = brain.decide(delta, to_target, flat.length() < arena_radius - 0.8)
		# Committed to the line of a blow once it's under way.
		if brain.state != brain.ATTACK and to_target.length() > 0.1 and not vitals.is_open():
			rotation.y = lerp_angle(rotation.y, atan2(-to_target.x, -to_target.z), 1.0 - exp(-8.0 * delta))
	_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * delta))
	velocity = wanted + _knock
	move_and_slide()
	global_position.y = 0.0


func _to_target() -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	return to


func _on_wants_attack(attack: Attack) -> void:
	var to := _to_target()
	rotation.y = atan2(-to.x, -to.z)
	# The tell in the dark: a planted foot, and light catching the blade.
	footsteps.stamp(1.6)
	veil.glint(1.0)
	weapon.play(attack)


func _on_struck(attack: Attack) -> void:
	_knock += -global_basis.z * attack.lunge * 7.0
	veil.glint(0.7)


func _on_landed(attack: Attack) -> void:
	if vitals.dead or vitals.is_open():
		return
	var to := _to_target()
	if to.length() > attack.reach or (-global_basis.z).dot(to.normalized()) < 0.5:
		return
	var met: String = guard.receive_strike(self, attack.blockable)
	veil.reveal(clash_reveal)
	if met == "parry":
		_knock = -to.normalized() * 4.0
		vitals.press(vitals.parry_pressure)
		if not vitals.is_open():
			weapon.throw_back()
			brain.reel(0.9)
	elif met == "block":
		vitals.press(vitals.block_pressure)


func _on_finished() -> void:
	brain.attack_finished(_to_target())
	if brain.state != brain.ATTACK:
		weapon.rest()


func _on_opened() -> void:
	brain.knock_out()
	weapon.droop()
	veil.reveal(vitals.open_time)
	veil.flare()
	footsteps.stamp(2.0)
	opened.emit()


func _on_recovered() -> void:
	weapon.rest()
	brain.wake()
	closed.emit()


func _on_died() -> void:
	brain.knock_out()
	weapon.droop()
	closed.emit()
	died.emit()


# What the player's sword calls.

func is_open() -> bool:
	return vitals.is_open()


func take_hit(_at: Vector3, direction: Vector3, _color: Color, force := 1.0, damage := 0.0) -> bool:
	if vitals.dead:
		return false
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	_knock += flat * 5.0 * force
	veil.reveal(clash_reveal)
	veil.flare()
	footsteps.stamp(1.0)
	return vitals.hurt(damage)


func execute(at: Vector3, direction: Vector3, color: Color) -> void:
	take_hit(at, direction, color, 1.5, vitals.max_health * 10.0)
