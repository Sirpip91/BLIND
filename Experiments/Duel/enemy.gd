extends CharacterBody3D

signal enraged

## The other swordsman: the same arm and the same rules as the player, with a
## brain where the mouse would be.

const Strike = preload("res://Experiments/Duel/strike.gd")

@export var rival: Node3D
## How fast it turns to face the player, by what its sword is doing.
@export var turn_speed := 5.0
@export var turn_speed_winding := 9.0
@export var arena_radius := 10.0
## Health it turns furious at.
@export_range(0.0, 1.0, 0.05) var fury_at := 0.5
## Seconds after being knocked out of something before an ordinary cut can do
## it again. Openings won by parrying always can.
@export var poise_time := 1.8
## Pressure from having a blow parried, at the edge of the window and dead on.
@export var parry_pressure := Vector2(15.0, 28.0)
## Seconds it's open for once the last blow of a run is parried.
@export var parry_reel := 1.0

@onready var arm: Node3D = $Shoulders/Arm
@onready var vitals: Node = $Vitals
@onready var brain: Node = $Brain
@onready var body: Node3D = $Body
@onready var brush: Node = $Brush

var _push := Vector3.ZERO
var _poise := 0.0


func begin() -> void:
	brain.start(self, rival, arm)
	arm.released.connect(_on_released)
	vitals.broke.connect(_on_broke)
	vitals.recovered.connect(_on_recovered)
	vitals.died.connect(_on_died)
	body.setup(self)


func reset_at(at: Vector3) -> void:
	global_position = at
	_push = Vector3.ZERO
	_poise = 0.0
	vitals.reset()
	arm.reset()
	brain.reset()
	body.reset()
	_face(1.0)
	reset_physics_interpolation()


func facing() -> Vector3:
	return -global_basis.z


func is_evading() -> bool:
	return false


func push(velocity_change: Vector3) -> void:
	_push += velocity_change


func _physics_process(delta: float):
	if brain.rival == null:
		return
	_poise = maxf(_poise - delta, 0.0)
	var wanted: Vector3 = brain.think(delta)
	if not vitals.dead and not vitals.is_open():
		match arm.phase:
			# Committed to its line: this is what stepping aside beats.
			arm.Phase.RELEASE, arm.Phase.STAGGER:
				pass
			arm.Phase.WINDUP:
				_face(1.0 - exp(-turn_speed_winding * delta))
			_:
				_face(1.0 - exp(-turn_speed * delta))
	_push = _push.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	var flat := Vector3(velocity.x, 0, velocity.z).lerp(wanted, 1.0 - exp(-7.0 * delta))
	velocity = flat
	if _too_close():
		velocity -= facing() * maxf(velocity.dot(facing()), 0.0)
	velocity += _push
	move_and_slide()
	velocity -= _push
	global_position.y = 0.0
	var out := Vector2(global_position.x, global_position.z).limit_length(arena_radius)
	global_position = Vector3(out.x, 0.0, out.y)

	var heavy: bool = arm.is_attacking() and arm.strike.heavy
	brush.painting = arm.phase == arm.Phase.RELEASE or (arm.phase == arm.Phase.RECOVER and arm.progress() < 0.25)
	brush.stroke_tint = 1.0 if heavy or brain.fury else 0.5
	brush.blade_tint = move_toward(brush.blade_tint, 1.0 if heavy else 0.0, delta * 4.0)


func _too_close() -> bool:
	return global_position.distance_to(rival.global_position) < 1.3


func _face(amount: float) -> void:
	var to := rival.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), amount)


func _on_released(strike: Strike) -> void:
	_push += facing() * strike.lunge


## How one of its blows was met. `late` is 0 for a parry dead on the moment
## and 1 for one at the edge of the window. `past` is where its sword is sent.
func landed(result: String, late: float, past: Vector2) -> void:
	match result:
		"block":
			arm.bounce(0.15)
		"parry":
			vitals.press(lerpf(parry_pressure.y, parry_pressure.x, late))
			if vitals.is_open():
				return
			# A parry only opens it up at the end of a run of blows.
			if brain.is_last_strike():
				arm.stagger(parry_reel, past)
				brain.reel(parry_reel)
			else:
				arm.bounce(0.17)


## How it met one of the player's. `flung` is where a hit sends its sword.
func met(result: String, strike: Strike, from: Vector3, flung: Vector2) -> void:
	var away := (global_position - from).normalized()
	away.y = 0.0
	match result:
		"block":
			vitals.press(2.0)
			push(away * 1.6)
			brain.blocked(false)
		"parry":
			push(away * 0.6)
			brain.blocked(true)
		"glance":
			vitals.wound(strike.damage)
			body.flinch(strike.direction, 0.35)
			push(away * 1.2)
			if not vitals.dead:
				# Shakes it off, and is ready again.
				arm.bounce(0.15)
				brain.reel(0.15)
				brain.was_hit(true)
		"hit":
			# Swinging into its swing only trades blows.
			var armored: bool = not strike.earned and (arm.is_attacking() or brain.in_pattern() or _poise > 0.0)
			var was_open: bool = vitals.is_open()
			vitals.wound(strike.damage)
			push(away * _thrown_back(strike, armored))
			body.flinch(strike.direction, 0.55 if armored else (1.3 if strike.last_link else 1.0))
			body.gash(strike.direction, from, 0.62 if strike.last_link else (0.48 if strike.earned else 0.36))
			if vitals.dead:
				return
			if was_open:
				vitals.cracked.emit(0.0)
				_enrage()
				return
			vitals.press(10.0 if strike.earned and strike.link == 0 else 4.0)
			if vitals.is_open():
				return
			if not brain.fury and vitals.health <= vitals.max_health * fury_at:
				_enrage()
				return
			if not armored:
				_poise = poise_time
				arm.stagger(strike.reel, flung)
				brain.reel(strike.reel)
			# It sees the third cut of a run coming.
			brain.was_hit(not strike.earned or strike.link >= 1)


# The cuts in the middle of a run keep it in reach of the next.
func _thrown_back(strike: Strike, armored: bool) -> float:
	if armored:
		return 1.5
	if strike.earned and not strike.last_link:
		return 1.9
	return 5.0 if strike.last_link else 3.4


func _enrage() -> void:
	arm.reset()
	brain.enrage()
	var away := rival.global_position - global_position
	away.y = 0.0
	rival.push(away.normalized() * 6.0)
	enraged.emit()


func _on_broke() -> void:
	arm.go_down()
	brain.open_up()


func _on_recovered() -> void:
	arm.reset()
	brain.recover()


func _on_died() -> void:
	arm.go_down()
	brain.out()
