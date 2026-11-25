extends Node

## The player's side of the swordplay: turns clicks into cuts and guards, and
## pays for them in ink. A click cuts the way the mouse was swiped. Held, it
## draws: let go, or run out of time, and the sword takes the line that was
## drawn.

const Strike = preload("res://Experiments/SteelPaint/strike.gd")

@export var player: CharacterBody3D
@export var arm: Node3D
@export var vitals: Node
@export var brush: Node
@export var cut: Strike
@export var thrust: Strike

@export_group("Swing")
## Swipes, in pixels a second, that count as barely trying and as everything.
@export var swipe := Vector2(350.0, 2600.0)
## How hard a click with no swipe behind it is.
@export_range(0.0, 1.0, 0.05) var plain := 0.4
## Seconds a cut takes, barely trying and with everything.
@export var slash_time := Vector2(0.24, 0.15)
## What a cut has to go through things with, the same.
@export var slash_force := Vector2(0.45, 1.7)
## Radians a cut bends for each pixel the mouse pulls it aside.
@export var bend_speed := 0.006

@export_group("Drawing")
## Seconds there are to draw a line, and how long it can be, in radians.
@export var draw_time := 1.4
@export var draw_length := 2.6
## Shorter than this it was only a click.
@export var draw_least := 0.16
## Seconds the sword takes for each radian of it.
@export var draw_pace := 0.16
@export var draw_force := 2.0
@export var draw_cost := 0.25

@export_group("Openings")
## Seconds to answer a blow that was slipped.
@export var slip_time := 0.6
@export var opening_speed := 0.6
## Seconds the blade drags through a body.
@export var bite := 0.03

@export_group("Ink")
@export var cut_cost := 0.14
## Extra lost when a cut is blocked.
@export var blocked_cost := 0.12
@export var dodge_cost := 0.18
@export var block_cost := 0.2
@export var parry_gain := 0.4
@export var soak_rate := 0.26
@export var soak_delay := 0.55
## Cuts with a dry blade are this much slower, and don't go through.
@export var dry_slowness := 1.6
@export var hurt_slowness := 1.2

## The line so far, in radians from the middle of the view.
var drawn := PackedVector2Array()
## 0 dry, 1 loaded. Shown as the ink on the blade.
var ink := 1.0

var _drawing := false
var _drawing_for := 0.0
var _queued_path := PackedVector2Array()
var _queued_pins := PackedVector3Array()
var _opening := 0.0
var _rested := 0.0
var _queued := 0.0
var _queued_thrust := false
var _guard_held := false
var _sway := Vector2.ZERO

const PACE := { 0: 1.0, 1: 0.55, 2: 0.3, 3: 0.55, 4: 0.7, 5: 0.5, 6: 0.3, 7: 0.0 }


func _ready():
	player.arm = arm
	player.vitals = vitals
	player.dodged.connect(func(_way):
		_stop_drawing()
		_spend(dodge_cost))
	arm.finished.connect(func(_s): _after())
	# Into range as it's raised, so the edge is there when it comes down.
	arm.wound_up.connect(_step_in)


func reset() -> void:
	ink = 1.0
	_stop_drawing()
	close()
	_queued = 0.0
	_guard_held = false
	arm.wind_scale = 1.0
	arm.reset()
	vitals.reset()


func has_opening() -> bool:
	return _opening > 0.0


## Their sword is out of the way, for this long.
func open(seconds: float) -> void:
	_opening = seconds


func close() -> void:
	_opening = 0.0


func _unhandled_input(event):
	if not event is InputEventMouseButton or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or vitals.dead:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_drawing()
			else:
				finish_drawing()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				attack(true)
		MOUSE_BUTTON_RIGHT:
			_guard_held = event.pressed
			if event.pressed:
				guard()
			else:
				arm.lower_guard()


func is_drawing() -> bool:
	return _drawing


## How much of the time to draw is left, 1 to 0.
func draw_left() -> float:
	return 1.0 - clampf(_drawing_for / draw_time, 0.0, 1.0)


func start_drawing() -> void:
	if vitals.dead or _drawing:
		return
	_drawing = true
	_drawing_for = 0.0
	drawn = PackedVector2Array([player.cursor])
	player.drawing = true


## The sword takes the line, or if there isn't one, cuts through the mark.
func finish_drawing() -> void:
	if not _drawing:
		return
	var line := drawn
	_queued_pins = _pinned(line)
	var far := _length_of(line)
	_stop_drawing()
	if far < draw_least:
		attack(false)
	else:
		attack(false, line)


func _stop_drawing() -> void:
	_drawing = false
	player.drawing = false


# Where each point of a line falls on whoever it's drawn over.
func _pinned(line: PackedVector2Array) -> PackedVector3Array:
	var pins := PackedVector3Array()
	var eye: Transform3D = player.camera.global_transform
	for at in line:
		pins.append(arm.pin(at, eye, player.rival.global_position))
	return pins


func _length_of(line: PackedVector2Array) -> float:
	var far := 0.0
	for i in range(1, line.size()):
		far += line[i - 1].distance_to(line[i])
	return far


func _draw_on(delta: float) -> void:
	if not _drawing:
		return
	_drawing_for += delta
	if player.cursor.distance_to(drawn[-1]) > 0.012:
		drawn.append(player.cursor)
	var far := _length_of(drawn)
	if _drawing_for >= draw_time or far >= draw_length:
		finish_drawing()


## Held over if the sword is busy, so a press a moment early still counts.
func attack(thrusting: bool, path := PackedVector2Array()) -> void:
	_queued_path = path
	if _try_attack(thrusting):
		return
	_queued = 0.3
	_queued_thrust = thrusting


## Pressed during a wind-up it's a feint: the cut is dropped for the guard.
func guard() -> void:
	_stop_drawing()
	_queued = 0.0
	arm.raise_guard(player.aim)


func _try_attack(thrusting: bool) -> bool:
	if vitals.dead or player.is_dodging() or not arm.is_open_to_act():
		return false
	var strike: Strike = thrust.duplicate() if thrusting else cut.aimed(player.aim)
	var speed := 1.0
	var cost := cut_cost
	if not thrusting and not _queued_path.is_empty():
		strike.path = _queued_path
		if player.is_locked():
			strike.pinned_to = player.rival
			strike.pins = _queued_pins
		strike.direction = (_queued_path[mini(3, _queued_path.size() - 1)] - _queued_path[0]).normalized()
		strike.through = _queued_path[0]
		strike.power = 1.0
		strike.force = draw_force
		strike.release = clampf(_length_of(_queued_path) * draw_pace, 0.16, 0.45)
		speed = 0.5
		cost = draw_cost
	elif not thrusting:
		strike.through = player.cursor
		# Next to nothing from where it rests; the time it takes to come round
		# from anywhere else.
		speed = lerpf(0.12, 1.0, smoothstep(0.1, 1.0, arm.turn_to(strike.direction)))
		strike.power = lerpf(plain, 1.0, smoothstep(swipe.x, swipe.y, player.swipe_speed()))
		strike.release = lerpf(slash_time.x, slash_time.y, strike.power)
		strike.force = lerpf(slash_force.x, slash_force.y, strike.power)
	if has_opening():
		strike.earned = true
		speed *= opening_speed
		cost *= 0.5
	elif ink < cut_cost * 0.6:
		strike.dry = true
		speed *= dry_slowness
	if not arm.begin(strike, speed):
		return false
	player.moved = Vector2.ZERO
	_spend(cost)
	return true


# Into range, never into them.
func _step_in(strike: Strike) -> void:
	if player.is_locked() and player.global_position.distance_to(player.rival.global_position) > 1.5:
		player.push(player.facing() * strike.lunge)


func _after() -> void:
	if _guard_held:
		arm.raise_guard(player.aim, false)


func _spend(amount: float) -> void:
	ink = maxf(ink - amount, 0.0)
	_rested = 0.0


## One of our cuts was stopped by a blade.
func stopped(result: String) -> void:
	close()
	_spend(blocked_cost)
	if result == "parry":
		arm.stagger(0.55)
	else:
		arm.bounce(0.45)


## One of our cuts is in them.
func bit(deep: bool) -> void:
	arm.drag(bite * (2.0 if deep else 1.0))


## How we met one of theirs.
func met(result: String, strike: Strike) -> void:
	match result:
		"parry":
			ink = minf(ink + parry_gain, 1.0)
		"block":
			_spend(block_cost)
			if ink <= 0.0:
				# Nothing left to hold it with.
				arm.stagger(0.7, strike.comes_from() * -1.0)
		"hit":
			_stop_drawing()
			close()
			_queued = 0.0
			if arm.phase != arm.Phase.RELEASE:
				arm.stagger(0.4, strike.comes_from() * -1.0)


## Where it went in stays with us.
func wounded(strike: Strike) -> void:
	if absf(strike.direction.y) < 0.2 or strike.direction.y > 0.0:
		player.leg_hurt = player.leg_hurt or not strike.is_thrust()
	if strike.is_thrust() or strike.direction.y < -0.2:
		arm.wind_scale = hurt_slowness


func _physics_process(delta: float):
	_opening = maxf(_opening - delta, 0.0)
	_rested += delta
	# Hiding behind a guard never fills it.
	if _rested > soak_delay and not arm.is_attacking() and arm.phase != arm.Phase.GUARD:
		ink = minf(ink + soak_rate * delta, 1.0)
	if _queued > 0.0:
		_queued -= delta
		if _try_attack(_queued_thrust):
			_queued = 0.0
	arm.aim = player.aim
	_draw_on(delta)
	_bend()
	if arm.phase == arm.Phase.GUARD:
		if _guard_held:
			arm.turn_guard(player.aim)
		else:
			arm.lower_guard()
	elif _guard_held and arm.phase == arm.Phase.READY:
		arm.raise_guard(player.aim, false)
	player.pace = PACE[arm.phase]
	brush.fill = ink
	brush.painting = arm.phase == arm.Phase.RELEASE or (arm.phase == arm.Phase.RECOVER and arm.progress() < 0.3)

	# The sword trails the view, then catches up.
	_sway = _sway.lerp((player.look_moved * 0.0011).limit_length(0.07), 1.0 - exp(-delta * 12.0))
	player.look_moved = player.look_moved.lerp(Vector2.ZERO, 1.0 - exp(-delta * 14.0))
	arm.sway = Transform3D(Basis.from_euler(Vector3(-_sway.y, -_sway.x * 1.2, _sway.x * 0.5)),
			Vector3(-_sway.x * 0.35, _sway.y * 0.25, 0))


# The hand still on it: pulled aside, it curves.
func _bend() -> void:
	var pulled: Vector2 = player.moved
	player.moved = Vector2.ZERO
	if arm.phase == arm.Phase.RELEASE and not arm.strike.is_thrust():
		var d: Vector2 = arm.strike.direction
		arm.bend = clampf(arm.bend + pulled.dot(Vector2(-d.y, d.x)) * bend_speed, -arm.bend_most, arm.bend_most)
