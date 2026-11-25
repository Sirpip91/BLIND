extends Node

## The player's side of the swordplay: turns clicks into cuts and guards, and
## pays for them in ink. Cuts go the way the mouse last went. Guards go up on
## the side the mouse went to.

const Strike = preload("res://Experiments/Duel/strike.gd")

@export var player: CharacterBody3D
@export var arm: Node3D
@export var vitals: Node
@export var brush: Node
@export var cut: Strike
@export var thrust: Strike
@export_group("Openings")
## Seconds to start the first cut after a parry or a slipped blow.
@export var riposte_time := 0.9
@export var riposte_speed := 0.55
## How far off the way their sword went a cut still finds them bare.
@export_range(20.0, 120.0, 1.0, "radians_as_degrees") var open_tolerance := deg_to_rad(72.0)
## What a cut at the covered side is worth.
@export var glance_damage := 0.35
## Harm done by each cut through one opening. How many there are is how many
## an opening holds.
@export var link_damage: Array[float] = [1.3, 1.5, 2.2]
## Seconds each leaves them reeling, and so how long there is for the next.
@export var link_reel: Array[float] = [0.75, 0.44, 0.5]

@export_group("The beat")
## Seconds either side of a cut landing that the next is on the beat.
@export var beat := Vector2(0.08, 0.17)
@export var beat_speed := 0.5
@export var beat_damage := 1.25
## Coming back along the last cut is this much quicker than starting over.
@export var return_speed := 0.85
## Seconds the blade drags through a body.
@export var bite := 0.07

@export_group("Ink")
@export var cut_cost := 0.27
## Extra lost when a cut is blocked.
@export var blocked_cost := 0.12
@export var dodge_cost := 0.18
@export var block_cost := 0.2
@export var parry_gain := 0.4
@export var soak_rate := 0.26
@export var soak_delay := 0.55
## Cuts with a dry blade are this much slower.
@export var dry_slowness := 1.6
## And do this much of the harm.
@export var dry_damage := 0.4

## 0 dry, 1 loaded. Shown as the ink on the blade.
var ink := 1.0

## Where their sword went, in the player's view. A cut that chases it finds
## them bare; zero when every way does.
var open_way := Vector2.ZERO
## Cuts already landed through this opening.
var link := 0
## 1 as a cut lands, falling away: the moment to throw the next.
var pulse := 0.0

var _opening := 0.0
var _landed_ago := 10.0
var _pressed_ago := 10.0
var _pressed := false
var _on_beat := false
var _last_way := Vector2.ZERO
var _rested := 0.0
var _queued := 0.0
var _queued_thrust := false
var _guard_held := false
var _sway := Vector2.ZERO

const PACE := { 0: 1.0, 1: 0.55, 2: 0.3, 3: 0.55, 4: 0.7, 5: 0.5, 6: 0.3, 7: 0.0 }


func _ready():
	player.arm = arm
	player.vitals = vitals
	player.dodged.connect(func(_way): _spend(dodge_cost))
	arm.finished.connect(func(_s): _after())
	arm.released.connect(_step_in)


func reset() -> void:
	ink = 1.0
	close()
	_queued = 0.0
	_guard_held = false
	arm.reset()
	vitals.reset()


func has_opening() -> bool:
	return _opening > 0.0


## Whether a cut the way the mouse is going would find them bare.
func reads_true() -> bool:
	return has_opening() and _finds(player.aim)


## Their sword is out of the way, gone `way` in the player's view.
func open(way: Vector2) -> void:
	_opening = riposte_time
	open_way = way
	link = 0


func close() -> void:
	_opening = 0.0
	open_way = Vector2.ZERO
	link = 0


func _finds(way: Vector2) -> bool:
	return open_way == Vector2.ZERO or absf(way.angle_to(open_way)) <= open_tolerance


func _unhandled_input(event):
	if not event is InputEventMouseButton or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or vitals.dead:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				attack(false)
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				attack(true)
		MOUSE_BUTTON_RIGHT:
			_guard_held = event.pressed
			if event.pressed:
				guard()
			else:
				arm.lower_guard()


## Held over if the sword is busy, so a press a moment early still counts.
func attack(thrusting: bool) -> void:
	# Only the first press for each cut is timed, so mashing never finds it.
	if has_opening() and link > 0 and not _pressed:
		_pressed = true
		_pressed_ago = 0.0
		_on_beat = _landed_ago <= beat.y
	elif arm.is_attacking() and not _pressed:
		_pressed = true
		_pressed_ago = 0.0
		_on_beat = false
	if _try_attack(thrusting):
		return
	_queued = 0.3
	_queued_thrust = thrusting


## Pressed during a wind-up it's a feint: the cut is dropped for the guard.
func guard() -> void:
	_queued = 0.0
	arm.raise_guard(player.aim)


func _try_attack(thrusting: bool) -> bool:
	var through: bool = has_opening() and link > 0 and arm.phase == arm.Phase.RECOVER
	if vitals.dead or player.is_dodging() or not (arm.is_open_to_act() or (through and _on_beat)):
		return false
	var strike: Strike = thrust if thrusting else cut.aimed(player.aim)
	var speed := 1.0
	var cost := cut_cost
	if _last_way.dot(strike.direction) < 0.0 and arm.phase == arm.Phase.RECOVER:
		speed = return_speed
	if has_opening():
		strike = _through_opening(strike)
		if link == 0:
			speed = riposte_speed
		elif _on_beat:
			speed = beat_speed
		cost = 0.0
	elif ink < cut_cost * 0.6:
		strike = strike.duplicate()
		strike.damage *= dry_damage
		speed = dry_slowness
	if not arm.begin(strike, speed, strike.on_beat):
		return false
	# Spent on this cut. Landing it true opens the next.
	_opening = 0.0
	link = 0
	_pressed = false
	_on_beat = false
	_last_way = strike.direction
	_spend(cost)
	return true


func _through_opening(strike: Strike) -> Strike:
	var cut_in: Strike = strike.duplicate()
	cut_in.earned = true
	cut_in.link = link
	cut_in.last_link = link >= link_damage.size() - 1
	cut_in.reel = link_reel[link]
	cut_in.damage *= link_damage[link]
	cut_in.on_beat = link > 0 and _on_beat
	if cut_in.on_beat:
		cut_in.damage *= beat_damage
	cut_in.glancing = not strike.is_thrust() and not _finds(strike.direction)
	if cut_in.glancing:
		cut_in.damage *= glance_damage
	return cut_in


# Into range, never into them.
func _step_in(strike: Strike) -> void:
	if player.is_locked() and player.global_position.distance_to(player.rival.global_position) > 1.6:
		player.push(player.facing() * strike.lunge)


func _after() -> void:
	if _guard_held:
		arm.raise_guard(player.aim)


func _spend(amount: float) -> void:
	ink = maxf(ink - amount, 0.0)
	_rested = 0.0


## How one of our cuts was met.
func landed(result: String, strike: Strike) -> void:
	if result != "hit":
		close()
	match result:
		"glance":
			arm.bounce(0.3)
		"block":
			arm.bounce(0.45)
			_spend(blocked_cost)
		"parry":
			arm.stagger(0.55)
			_spend(blocked_cost)
		"hit":
			ink = minf(ink + 0.08, 1.0)
			arm.drag(bite * (2.0 if strike.last_link else 1.0))
			# Flung back against the cut, so the way on is the way back.
			open_way = _flung(strike)
			if strike.earned and not strike.last_link and not strike.is_thrust():
				_next_link(strike)


func _flung(strike: Strike) -> Vector2:
	if absf(strike.direction.x) < 0.35:
		return Vector2([-1.0, 1.0].pick_random(), -0.15).normalized()
	return Vector2(-signf(strike.direction.x), strike.direction.y * 0.2).normalized()


func _next_link(strike: Strike) -> void:
	link = strike.link + 1
	_opening = strike.reel + bite
	_landed_ago = 0.0
	pulse = 1.0
	# Pressed a hair before it landed is on the beat too.
	if _pressed:
		_on_beat = _pressed_ago <= beat.x


## How we met one of theirs. `opening` is whether that was the last of a run
## of blows, and so leaves them open.
func met(result: String, strike: Strike, opening: bool, past: Vector2) -> void:
	match result:
		"parry":
			ink = minf(ink + parry_gain, 1.0)
			if opening:
				open(past)
		"block":
			_spend(block_cost)
			if ink <= 0.0:
				# Nothing left to hold it with.
				arm.stagger(0.7, strike.comes_from() * -1.0)
		"hit":
			close()
			_queued = 0.0
			if arm.phase != arm.Phase.RELEASE:
				arm.stagger(0.4, strike.comes_from() * -1.0)


func _physics_process(delta: float):
	# A queued cut mustn't find its opening gone for want of a tick.
	if _opening > 0.0 and not arm.is_attacking():
		_opening -= delta
		if _opening <= 0.0:
			close()
	_landed_ago += delta
	_pressed_ago += delta
	pulse = move_toward(pulse, 0.0, delta / beat.y)
	if not arm.is_attacking() and link == 0:
		_pressed = false
	_rested += delta
	# Hiding behind a guard never fills it.
	if _rested > soak_delay and not arm.is_attacking() and arm.phase != arm.Phase.GUARD:
		ink = minf(ink + soak_rate * delta, 1.0)
	if _queued > 0.0:
		_queued -= delta
		if _try_attack(_queued_thrust):
			_queued = 0.0
	arm.aim = player.aim
	if arm.phase == arm.Phase.GUARD:
		if _guard_held:
			arm.turn_guard(player.aim)
		else:
			arm.lower_guard()
	elif _guard_held and arm.phase == arm.Phase.READY:
		arm.raise_guard(player.aim)
	player.pace = PACE[arm.phase]
	brush.fill = ink
	if arm.phase == arm.Phase.WINDUP:
		brush.stroke_tint = float(arm.strike.link) / maxf(link_damage.size() - 1, 1) if arm.strike.earned else 0.0
	brush.painting = arm.phase == arm.Phase.RELEASE or (arm.phase == arm.Phase.RECOVER and arm.progress() < 0.3)

	# The sword trails the view, then catches up.
	_sway = _sway.lerp((player.look_moved * 0.0011).limit_length(0.07), 1.0 - exp(-delta * 12.0))
	player.look_moved = player.look_moved.lerp(Vector2.ZERO, 1.0 - exp(-delta * 14.0))
	arm.sway = Transform3D(Basis.from_euler(Vector3(-_sway.y, -_sway.x * 1.2, _sway.x * 0.5)),
			Vector3(-_sway.x * 0.35, _sway.y * 0.25, 0))
