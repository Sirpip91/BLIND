extends "res://Core/Player/player.gd"

## The player in a duel. Locked on, the view holds the enemy and the feet
## circle it slowly; the mouse still drifts the view a little, but mostly
## says which way the sword goes.

signal dodged(way: Vector3)
signal slipped

@export var rival: Node3D
@export var lock_range := 9.0
## Nobody is pushed, or runs, out of the duel.
@export var arena_radius := 9.5

@export_group("Locked movement")
@export var circle_speed := 1.75
@export var advance_speed := 1.9
@export var retreat_speed := 1.5
## How quickly the feet pick up and lose speed. Lower is heavier.
@export var grip := 6.5

@export_group("Dodge")
@export var dodge_distance := 1.7
@export var dodge_time := 0.34
@export var dodge_cooldown := 0.6
## Seconds into a dodge that blows pass by.
@export var evade := Vector2(0.03, 0.24)

@export_group("Locked view")
## How firmly the view follows the enemy.
@export var hold := 9.0
## How far the mouse can carry its mark from the middle, in radians.
@export var drift := Vector2(0.5, 0.42)
## How much of that the view itself follows.
@export_range(0.0, 1.0, 0.05) var follow := 0.3
@export var mark_speed := 0.8
@export var look_at_height := 1.25
## Narrower than walking about, so the enemy fills more of it.
@export var locked_fov := 63.0

@export_group("Aim")
## Mouse travel, in pixels, before it counts as a direction.
@export var aim_threshold := 9.0

const FLICK_FADE := 13.0

var arm: Node3D
var vitals: Node
var locked := true
## Set by whatever the sword is doing: a swing plants the feet.
var pace := 1.0
## The way the mouse last went, and so the way a cut would go.
var aim := Vector2(-0.707, -0.707)
var look_moved := Vector2.ZERO

## The mouse's last few hundredths of a second, up being up: a flick.
var flick := Vector2.ZERO
## Where the mouse's mark is, in radians from the middle of the view.
var cursor := Vector2.ZERO
## The view keeps still for a line to be drawn on it.
var drawing := false
## The line so far, for anyone watching.
var line := PackedVector2Array()
## Mouse travel since it was last asked for.
var moved := Vector2.ZERO
var leg_hurt := false
var fallen := false

var _fall := 0.0
var _hurting := 0.0
var _travel := Vector2.ZERO
var _glance := Vector2.ZERO
var _dodge_left := 0.0
var _dodge_wait := 0.0
var _dodge_way := Vector3.ZERO
var _push := Vector3.ZERO
var _kick := Vector3.ZERO
var _kick_speed := Vector3.ZERO


func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_take_aim(event.relative)
		look_moved += event.relative
		flick += Vector2(event.relative.x, -event.relative.y)
		moved += Vector2(event.relative.x, -event.relative.y)
		if is_locked() or drawing:
			cursor += Vector2(event.relative.x, -event.relative.y) * mouse_sensitivity * mark_speed
			cursor = cursor.clamp(-drift, drift)
			return
	elif _pressed(event, KEY_Q) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE):
		locked = not locked
		_glance = Vector2.ZERO
	elif _pressed(event, KEY_SPACE):
		dodge()
	super(event)


func _pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == key


func is_locked() -> bool:
	return locked and is_instance_valid(rival) and not rival.vitals.dead \
			and global_position.distance_to(rival.global_position) < lock_range


func facing() -> Vector3:
	return -(Basis(Vector3.UP, rotation.y + head.rotation.y).z)


func is_evading() -> bool:
	if _dodge_left <= 0.0:
		return false
	var into := dodge_time - _dodge_left
	return into >= evade.x and into <= evade.y


func is_dodging() -> bool:
	return _dodge_left > 0.0


## Shoved, in metres a second, easing off.
func push(velocity_change: Vector3) -> void:
	_push += velocity_change


## A jolt to the view in radians: pitch, yaw, roll.
func kick(amount: Vector3) -> void:
	_kick_speed += amount * 26.0


func dodge() -> bool:
	if _dodge_left > 0.0 or _dodge_wait > 0.0 or vitals.dead:
		return false
	if arm.phase == arm.Phase.RELEASE or arm.phase == arm.Phase.STAGGER:
		return false
	arm.cancel()
	var keys := Input.get_vector("left", "right", "up", "down")
	if keys == Vector2.ZERO:
		keys = Vector2(0, 1)
	_dodge_way = (Basis(Vector3.UP, rotation.y + head.rotation.y) * Vector3(keys.x, 0, keys.y)).normalized()
	_dodge_left = dodge_time
	_dodge_wait = dodge_time + dodge_cooldown
	kick(Vector3(0.012 * signf(keys.y), 0.0, -keys.x * 0.05))
	dodged.emit(_dodge_way)
	return true


## How fast the mouse is being swiped, in pixels a second.
func swipe_speed() -> float:
	return flick.length() * FLICK_FADE


## A dodge that actually beat something.
func slip() -> void:
	slipped.emit()


func reset_at(at: Vector3, yaw: float) -> void:
	global_position = at
	rotation.y = yaw
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_push = Vector3.ZERO
	_dodge_left = 0.0
	_glance = Vector2.ZERO
	cursor = Vector2.ZERO
	leg_hurt = false
	fallen = false
	_fall = 0.0
	reset_physics_interpolation()


func _physics_process(delta: float):
	_dodge_left = maxf(_dodge_left - delta, 0.0)
	_dodge_wait = maxf(_dodge_wait - delta, 0.0)
	_push = _push.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * delta))
	_travel = _travel.lerp(Vector2.ZERO, 1.0 - exp(-9.0 * delta))
	flick = flick.lerp(Vector2.ZERO, 1.0 - exp(-FLICK_FADE * delta))
	# A spring, so a jolt overshoots and settles instead of snapping back.
	_kick_speed += (-_kick * 210.0 - _kick_speed * 22.0) * delta
	_kick += _kick_speed * delta
	base_fov = locked_fov if is_locked() else BASE_FOV
	if is_locked():
		_hold_view(delta)
	elif not drawing:
		cursor = cursor.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))
	super(delta)
	var inside := Vector2(global_position.x, global_position.z).limit_length(arena_radius)
	global_position = Vector3(inside.x, global_position.y, inside.y)
	# A wounded man can't hold his head still.
	var hurt: float = 1.0 - vitals.health / vitals.max_health
	_hurting += delta * 2.3
	_fall = lerpf(_fall, 1.0 if fallen else 0.0, 1.0 - exp(-3.2 * delta))
	head.rotation.x = _kick.x + sin(_hurting * 2.0) * 0.006 * hurt
	head.rotation.z = _kick.z + sin(_hurting) * 0.016 * hurt + _fall * 1.1
	camera.position.y -= _fall * 1.3


func _hold_view(delta: float) -> void:
	if not drawing:
		_glance = _glance.lerp(Vector2(-cursor.x, cursor.y) * follow, 1.0 - exp(-6.0 * delta))
	var to: Vector3 = rival.global_position + Vector3.UP * look_at_height - camera.global_position
	var yaw := atan2(-to.x, -to.z) - rotation.y + _glance.x + _kick.y
	var pitch := atan2(to.y, Vector2(to.x, to.z).length()) + _glance.y
	var firm := 1.0 - exp(-hold * delta)
	head.rotation.y = lerp_angle(head.rotation.y, yaw, firm)
	_pitch = lerpf(_pitch, pitch, firm)
	_apply_pitch()


func _steer(direction: Vector3, delta: float) -> void:
	if _dodge_left > 0.0:
		# Off hard, gliding to a stop.
		var k := _dodge_left / dodge_time
		var fast := _dodge_way * (dodge_distance * (0.65 if leg_hurt else 1.0) / dodge_time) * 2.0 * k
		velocity = Vector3(fast.x, velocity.y, fast.z)
		return
	if vitals and vitals.dead:
		direction = Vector3.ZERO
	if is_locked():
		var keys := Input.get_vector("left", "right", "up", "down")
		if vitals.dead:
			keys = Vector2.ZERO
		var toward := rival.global_position - global_position
		toward.y = 0.0
		var distance := toward.length()
		toward = toward.normalized()
		var side := toward.cross(Vector3.UP)
		var along := -keys.y
		# No walking into them.
		if distance < 1.25:
			along = minf(along, 0.0)
		var wanted := side * keys.x * circle_speed + toward * along * (advance_speed if along > 0.0 else retreat_speed)
		wanted *= pace * (0.6 if leg_hurt else 1.0)
		var flat := Vector3(velocity.x, 0, velocity.z).lerp(wanted, 1.0 - exp(-grip * delta))
		velocity = Vector3(flat.x, velocity.y, flat.z)
	else:
		super(direction, delta)
	velocity += _push * minf(delta * 12.0, 1.0)


func _take_aim(moved: Vector2) -> void:
	_travel += Vector2(moved.x, -moved.y)
	if _travel.length() > aim_threshold:
		aim = _travel.normalized()
