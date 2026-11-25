extends CharacterBody3D

## Its guard has gone.
signal broke
signal lost

## The other swordsman: the same arm and the same rules as the player, with a
## brain where the mouse would be, and a body that can be taken apart.

const Strike = preload("res://Experiments/Rally/strike.gd")
const Region = preload("res://Experiments/Rally/region.gd")
const Part = preload("res://Experiments/Rally/part.gd")

@export var rival: Node3D
## How fast it turns to face the player, by what its sword is doing.
@export var turn_speed := 5.0
@export var turn_speed_winding := 9.0
@export var arena_radius := 10.0
## Seconds after being knocked out of something before a scratch can do it
## again.
@export var poise_time := 1.8
## Pressure from having a blow parried, at the edge of the window and dead on.
@export var parry_pressure := Vector2(8.0, 13.0)

@onready var arm: Node3D = $Shoulders/Arm
@onready var vitals: Node = $Vitals
@onready var brain: Node = $Brain
@onready var body: Node3D = $Body
@onready var brush: Node = $Brush

## Seconds its guard is gone for.
@export var break_time := 2.6

## What it might cover, from its shoulders.
const COVERS: Array[Vector2] = [Vector2(0.0, 0.14), Vector2(-0.05, -0.35), Vector2(0.2, -0.3)]

## Times its guard has gone this duel.
var breaks := 0
## Which hand has the sword: 0 right, 1 left.
var sword_hand := 0
## Where the sword is lying, when it isn't held.
var fallen_sword: Node3D

var _push := Vector3.ZERO
var _poise := 0.0


func begin() -> void:
	brain.start(self, rival, arm)
	arm.released.connect(_on_released)
	vitals.died.connect(_on_died)
	body.setup(self)


func reset_at(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_push = Vector3.ZERO
	_poise = 0.0
	sword_hand = 0
	breaks = 0
	if fallen_sword:
		fallen_sword.queue_free()
		fallen_sword = null
	arm.visible = true
	arm.wind_scale = 1.0
	vitals.reset()
	arm.reset()
	brain.reset()
	_face(1.0)
	body.reset()
	reset_physics_interpolation()


func facing() -> Vector3:
	return -global_basis.z


func is_evading() -> bool:
	return false


func push(velocity_change: Vector3) -> void:
	_push += velocity_change


func one_handed() -> bool:
	return not (body.has_arm(0) and body.has_arm(1))


func is_lame() -> bool:
	return not (body.has_leg(0) and body.has_leg(1))


func is_armed() -> bool:
	return arm.visible


func _physics_process(delta: float):
	if brain.rival == null:
		return
	_poise = maxf(_poise - delta, 0.0)
	arm.droop = vitals.weariness()
	var wanted: Vector3 = brain.think(delta)
	if is_lame():
		wanted = wanted.limit_length(0.4)
	if not vitals.dead:
		match arm.phase:
			# Committed to its line: this is what stepping aside beats.
			arm.Phase.RELEASE, arm.Phase.STAGGER, arm.Phase.DOWN:
				pass
			arm.Phase.WINDUP:
				_face(1.0 - exp(-turn_speed_winding * delta))
			_:
				_face(1.0 - exp(-turn_speed * delta))
	_push = _push.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	velocity = Vector3(velocity.x, 0, velocity.z).lerp(wanted, 1.0 - exp(-7.0 * delta))
	if _too_close():
		velocity -= facing() * maxf(velocity.dot(facing()), 0.0)
	velocity += _push
	move_and_slide()
	velocity -= _push
	var out := Vector2(global_position.x, global_position.z).limit_length(arena_radius)
	global_position = Vector3(out.x, 0.0, out.y)

	brush.painting = arm.visible and (arm.phase == arm.Phase.RELEASE or (arm.phase == arm.Phase.RECOVER and arm.progress() < 0.25))


func _too_close() -> bool:
	return global_position.distance_to(rival.global_position) < 1.3


func _face(amount: float) -> void:
	var to := rival.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), amount)


func _on_released(strike: Strike) -> void:
	_push += facing() * strike.lunge * (0.35 if is_lame() else 1.0)


## How one of its blows was met. `late` is 0 for a parry dead on the moment
## and 1 for one at the edge of the window.
func landed(result: String, late: float, heat: float) -> void:
	match result:
		"block":
			arm.bounce(0.15)
		"evade":
			vitals.press(7.0)
			_stand_or_break()
		"hit":
			brain.let_up()
		"parry":
			vitals.press(lerpf(parry_pressure.y, parry_pressure.x, late) * (1.0 + heat * 0.6))
			arm.bounce(0.2)
			_stand_or_break()


func _stand_or_break() -> void:
	if vitals.weariness() >= 1.0:
		_break()
	else:
		brain.stand_guard()


## It got its sword to one of the player's.
func stopped(strike: Strike, from: Vector3, parried: bool) -> void:
	push(_away(from) * 0.8)
	# Seeing one coming steadies it.
	vitals.press(-14.0 if parried else 2.0)
	if one_handed():
		# One hand can't hold it: the blade is beaten out of line.
		vitals.press(10.0)
	if vitals.weariness() >= 1.0:
		_break()


## Holding what's left of its guard over one thing, and nothing else.
func is_broken() -> bool:
	return brain.is_broken()


func _break() -> void:
	breaks += 1
	var over: Vector2 = COVERS.pick_random()
	if is_armed():
		arm.raise_ward(over, Vector2(0.95, 0.3) if over.y > 0.0 else Vector2(0.6, 0.8))
	brain.broken(break_time)
	broke.emit()


## The part of its blade that will stop another, if it's being held over
## something.
func sword_in_way() -> Array[Vector3]:
	if not arm.is_warding() or not is_armed() or vitals.dead:
		return []
	return [arm.global_transform * Vector3(0, 0.1, 0), arm.global_transform * Vector3(0, 0.95, 0)]


## What it takes to go through one of these.
const TAKES := { Part.Kind.HEAD: 0.35, Part.Kind.TORSO: 0.8, Part.Kind.ARM: 0.3, Part.Kind.LEG: 0.32 }

## An edge has been drawn through it, or stopped in it if there's no region.
## "none", "scratch", "sever" or "kill".
func cut(strike: Strike, part: Part, at: Vector3, region: Region, travel: Vector3, from: Vector3) -> String:
	var was_dead: bool = vitals.dead
	if strike.dry:
		strike.force = 0.0
		return _scratched(strike, part, at, travel, from)
	if strike.is_thrust():
		return _run_through(strike, part, at, from)
	if region == null or strike.force < TAKES[part.kind]:
		# A limb stops it. Anything bigger it only opens, and goes on.
		if not part.kind in [Part.Kind.HEAD, Part.Kind.TORSO] or region == null:
			strike.force = 0.0
		return _scratched(strike, part, at, travel, from, 2.0)
	strike.force -= TAKES[part.kind]
	var arms := [body.has_arm(0), body.has_arm(1)]
	var legs := [body.has_leg(0), body.has_leg(1)]
	var result: String = body.slice(part, region, travel * 1.6 + Vector3.UP * 0.7)
	if result == "none":
		strike.force += TAKES[part.kind]
		return "none"
	if was_dead:
		return "sever"
	push(_away(from) * 1.2)
	body.flinch(strike.direction, 1.15)
	if _is_fatal(part, result, region):
		vitals.kill()
		return "kill"
	vitals.wound(1.0 if result == "through" else 0.5)
	vitals.press(30.0)
	if not vitals.dead:
		_count_losses(arms, legs, travel)
	return "kill" if vitals.dead else "sever"


func _is_fatal(part: Part, result: String, region: Region) -> bool:
	if not body.has_head():
		return true
	match part.kind:
		Part.Kind.HEAD:
			# A slice off the side of it is only a slice off the side of it.
			var kept := region.contains(part.start()) == region.contains(body.brain_point())
			return not kept or region.distance_to(body.brain_point()) < 0.05
		Part.Kind.TORSO:
			return result == "through"
	return false


func _run_through(strike: Strike, part: Part, at: Vector3, from: Vector3) -> String:
	if not part.kind in [Part.Kind.HEAD, Part.Kind.TORSO]:
		return _scratched(strike, part, at, Vector3.UP, from)
	body.gash(part, at, Vector3.UP, from, 0.2)
	body.flinch(strike.direction, 1.0)
	if vitals.dead:
		return "scratch"
	vitals.kill()
	return "kill"


func _scratched(strike: Strike, part: Part, at: Vector3, travel: Vector3, from: Vector3, deep := 1.0) -> String:
	body.gash(part, at, travel, from, 0.36 * deep)
	if vitals.dead:
		return "scratch"
	if part.kind == Part.Kind.HEAD and part.whole and not strike.path.is_empty():
		body.drop_mask(travel)
	body.flinch(strike.direction, 0.6)
	push(_away(from) * 2.2)
	vitals.press(15.0)
	vitals.wound((0.2 if part.kind in [Part.Kind.TORSO, Part.Kind.HEAD] else 0.12) * deep)
	if vitals.dead:
		return "kill"
	# Swinging into its swing only trades blows.
	if not arm.is_attacking() and _poise <= 0.0 and is_armed():
		_poise = poise_time
		arm.stagger(0.3, Vector2(-strike.direction.x, strike.direction.y))
		brain.reel(0.3)
	if vitals.weariness() >= 1.0 and not is_broken():
		_break()
	return "scratch"


# What it's been left without, and what it does about it.
func _count_losses(arms: Array, legs: Array, travel: Vector3) -> void:
	var lost_arm: bool = arms != [body.has_arm(0), body.has_arm(1)]
	var lost_leg: bool = legs != [body.has_leg(0), body.has_leg(1)]
	if not lost_arm and not lost_leg:
		return
	lost.emit()
	brain.despair()
	if lost_leg:
		body.kneeling = true
		if is_armed():
			arm.stagger(0.9, Vector2(0.6, -0.4))
			brain.reel(0.9)
	if not lost_arm:
		return
	if not is_armed():
		# The hand it was going for its sword with.
		_give_up()
	elif body.has_arm(sword_hand):
		arm.wind_scale = 1.2
		arm.stagger(0.8, Vector2(0.7 if sword_hand == 0 else -0.7, -0.5))
		brain.reel(0.8)
	else:
		_drop_sword(travel)
		if body.has_arm(1 - sword_hand):
			brain.fetch()
		else:
			_give_up()


func _give_up() -> void:
	body.kneeling = true
	brain.give_up()


func _drop_sword(travel: Vector3) -> void:
	fallen_sword = Node3D.new()
	get_tree().current_scene.add_child(fallen_sword)
	fallen_sword.add_child(arm.get_node("Model").duplicate())
	fallen_sword.global_transform = arm.global_transform
	arm.visible = false
	arm.go_down()
	var way := Vector3(travel.x, 0.0, travel.z).normalized()
	var at := global_position + way * 0.5 - facing() * 0.75
	var flat := Vector2(at.x, at.z).limit_length(arena_radius - 1.0)
	var lying := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
	var fall := fallen_sword.create_tween().set_parallel()
	fall.tween_property(fallen_sword, "global_position", Vector3(flat.x, 0.03, flat.y), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall.tween_property(fallen_sword, "quaternion", lying.get_rotation_quaternion(), 0.45)


## It has reached its sword with the hand it has left.
func take_up_sword() -> void:
	if fallen_sword:
		fallen_sword.queue_free()
		fallen_sword = null
	sword_hand = 1 - sword_hand
	arm.visible = true
	arm.wind_scale = 1.25
	arm.reset()


func _away(from: Vector3) -> Vector3:
	var away := global_position - from
	away.y = 0.0
	return away.normalized()


func _on_died() -> void:
	if is_armed():
		_drop_sword(facing())
	arm.go_down()
	brain.out()
