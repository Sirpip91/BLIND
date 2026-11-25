extends Node

## Decides where the enemy walks, when it attacks and when it guards. It only
## knows what the player could see too: where they are, and what their sword
## is doing, a human moment late.

const Strike = preload("res://Experiments/Duel/strike.gd")
const Pattern = preload("res://Experiments/Duel/pattern.gd")

enum { CIRCLE, CLOSE, FIGHT, GIVE_GROUND, REEL, OPEN, OUT }

@export var patterns: Array[Pattern] = []

@export_group("Footwork")
@export var ring := 3.0
@export var circle_speed := 0.95
@export var close_speed := 1.9
@export var retreat_speed := 1.5
## Seconds of circling between attacks.
@export var patience := Vector2(0.4, 1.2)
## How near it starts a swing from.
@export var strike_from := 2.55
## How fast it keeps up with someone backing off mid-pattern.
@export var chase_speed := 2.3

@export_group("Pressing on")
## Chance of going straight from one pattern into another, and how many times.
@export_range(0.0, 1.0, 0.05) var press_on := 0.55
@export var most_runs := 3

@export_group("Fury")
@export_range(0.5, 1.0, 0.01) var fury_speed := 0.87
@export_range(0.0, 1.0, 0.05) var fury_press_on := 0.8

@export_group("Guarding")
## Chance it answers a cut it sees coming, and how late.
@export_range(0.0, 1.0, 0.05) var guard_chance := 0.72
@export var reaction := Vector2(0.12, 0.22)
## Chance that answer is a parry.
@export_range(0.0, 1.0, 0.05) var parry_chance := 0.15
## Chance to strike straight back after blocking.
@export_range(0.0, 1.0, 0.05) var counter_chance := 0.75
## Chance to strike at a missed cut.
@export_range(0.0, 1.0, 0.05) var punish_chance := 0.8

@export_group("Reading the player")
## How much each cut thrown without an opening puts it on its guard, and how
## fast that wears off a second.
@export var wariness_per_cut := 0.2
@export var wariness_fade := 0.09
## Seconds after being hit that it's sure to guard the next.
@export var shell_time := 1.4

## Training: it circles and guards but never attacks.
var peaceful := false
var state := CIRCLE
var fighter: Node3D
var rival: Node3D
var arm: Node3D

var _left := 1.5
var _around := 1.0
var _turn_in := 1.0
var _pattern: Pattern
var _step := 0
var _react := -1.0
var _drop := 0.0
var _weighed := false
var _runs := 0
var _wary := 0.0
var _shell := 0.0
var _blocks := 0

## Past half health: faster, longer, and it has new tricks.
var fury := false


func start(owner_fighter: Node3D, against: Node3D, its_arm: Node3D) -> void:
	fighter = owner_fighter
	rival = against
	arm = its_arm
	arm.finished.connect(_on_finished)
	rival.arm.wound_up.connect(_on_rival_wound_up)
	reset()


func reset() -> void:
	_enter(CIRCLE, 1.6)
	_react = -1.0
	_runs = 0
	_wary = 0.0
	_shell = 0.0
	_blocks = 0
	fury = false


## The velocity it wants.
func think(delta: float) -> Vector3:
	_left -= delta
	_wary = maxf(_wary - wariness_fade * delta, 0.0)
	_shell = maxf(_shell - delta, 0.0)
	var to := rival.global_position - fighter.global_position
	to.y = 0.0
	var distance := to.length()
	var toward := to / maxf(distance, 0.01)
	_mind_guard(delta, distance)
	match state:
		CIRCLE:
			return _circle(delta, distance, toward)
		CLOSE:
			arm.aim = _pattern.strikes[0].direction if not _pattern.strikes[0].is_thrust() else Vector2(0, 1)
			if arm.phase == arm.Phase.GUARD:
				return Vector3.ZERO
			if distance <= strike_from:
				_enter(FIGHT)
				_throw()
				return Vector3.ZERO
			if _left <= 0.0:
				_back_to_circling()
			return toward * close_speed
		FIGHT:
			_keep_swinging()
			# Stays on whoever it's after between blows.
			if arm.phase != arm.Phase.RELEASE:
				return toward * clampf((distance - 1.95) * 3.0, -0.5, chase_speed)
		GIVE_GROUND:
			if _left <= 0.0:
				_back_to_circling()
			var side := toward.cross(Vector3.UP) * _around
			return (side * 0.6 - toward) * retreat_speed * (1.0 if distance < ring + 0.6 else 0.3)
		REEL:
			if _left <= 0.0:
				_enter(GIVE_GROUND, 0.5)
	return Vector3.ZERO


func _circle(delta: float, distance: float, toward: Vector3) -> Vector3:
	_turn_in -= delta
	if _turn_in <= 0.0:
		_turn_in = randf_range(1.1, 2.6)
		# Now and then it just stands and watches.
		_around = [1.0, -1.0, -signf(_around + 0.01), 0.0].pick_random()
	if distance > ring + 1.6:
		return toward * close_speed
	if not peaceful:
		_punish(distance)
		if state != CIRCLE:
			return Vector3.ZERO
		if _left <= 0.0 and arm.phase == arm.Phase.READY:
			_pattern = _pick()
			_enter(CLOSE, 2.2)
	var wanted := toward.cross(Vector3.UP) * _around + toward * clampf((distance - ring) * 1.4, -1.0, 1.0)
	return wanted.limit_length(1.0) * circle_speed


# A cut that hit nothing leaves the player stuck in it.
func _punish(distance: float) -> void:
	var missed: bool = rival.arm.phase == rival.arm.Phase.RECOVER
	if not missed:
		_weighed = false
		return
	if _weighed or distance > strike_from + 0.2 or arm.phase != arm.Phase.READY:
		return
	_weighed = true
	if randf() < punish_chance:
		_strike_now()


func _strike_now() -> void:
	_pattern = _pick()
	_enter(FIGHT)
	_throw()


func _pick() -> Pattern:
	_step = 0
	var known := patterns.filter(func(p): return (fury or not p.fury_only) and p != _pattern)
	var total := 0.0
	for p: Pattern in known:
		total += p.weight
	var at := randf() * total
	for p: Pattern in known:
		at -= p.weight
		if at <= 0.0:
			return p
	return known[-1]


## In the middle of throwing something, and not to be put off it.
func in_pattern() -> bool:
	return state == FIGHT


func is_last_strike() -> bool:
	return _pattern == null or _step >= _pattern.strikes.size() - 1


func _throw() -> void:
	arm.lower_guard()
	if not arm.begin(_pattern.strikes[_step], fury_speed if fury else 1.0):
		_enter(GIVE_GROUND, 0.4)


# The next blow follows as soon as the last one lets it, and a feint is dropped
# for it just before it would have come.
func _keep_swinging() -> void:
	if _pattern == null or is_last_strike():
		return
	var feinted: bool = arm.phase == arm.Phase.WINDUP and arm.strike.feint and arm.progress() > 0.72
	var through: bool = arm.phase == arm.Phase.RECOVER and arm.is_open_to_act()
	if feinted:
		arm.cancel()
	if feinted or through:
		_step += 1
		_throw()


func _on_finished(_strike: Strike) -> void:
	if state != FIGHT:
		return
	_step += 1
	if _pattern and _step < _pattern.strikes.size():
		_throw()
	elif _runs < most_runs and randf() < (fury_press_on if fury else press_on):
		_runs += 1
		_strike_now()
	else:
		_runs = 0
		_enter(GIVE_GROUND, randf_range(0.4, 0.8))


func _on_rival_wound_up(strike: Strike) -> void:
	if not strike.earned:
		_wary = minf(_wary + wariness_per_cut, 1.0)
	if state in [FIGHT, OPEN, OUT]:
		return
	if _shell > 0.0 or randf() < guard_chance + _wary * 0.6:
		_react = randf_range(reaction.x, reaction.y) * lerpf(1.0, 0.6, _wary)


func _mind_guard(delta: float, distance: float) -> void:
	if _react >= 0.0:
		_react -= delta
		if _react < 0.0 and not arm.is_open_to_act() and rival.arm.is_attacking():
			# Still caught up in something; as soon as it's free.
			_react = 0.0
		elif _react < 0.0 and distance < 3.4 and rival.arm.strike and arm.is_open_to_act() and state != FIGHT:
			# It answers the cut it saw start, so a feint draws the guard out.
			arm.parry_window = 0.3 if randf() < parry_chance + _wary * 0.55 else 0.0
			arm.raise_guard(rival.arm.strike.comes_from())
			_drop = 0.55
	if arm.phase == arm.Phase.GUARD:
		if not rival.arm.is_attacking():
			_drop -= delta
		if _drop <= 0.0:
			arm.lower_guard()


## It stopped one of the player's cuts. A second in a row is always answered,
## and so is one it parried.
func blocked(parried: bool) -> void:
	_blocks += 1
	if peaceful:
		return
	if parried or _blocks >= 2 or randf() < counter_chance:
		_blocks = 0
		_runs = 0
		_strike_now()


func was_hit(wary: bool) -> void:
	_blocks = 0
	if wary:
		_shell = shell_time


func enrage() -> void:
	fury = true
	_runs = 0
	_enter(GIVE_GROUND, 0.7)


func reel(seconds: float) -> void:
	_enter(REEL, seconds)


func open_up() -> void:
	_enter(OPEN)


func recover() -> void:
	_enter(GIVE_GROUND, 0.8)


func out() -> void:
	_enter(OUT)


func _back_to_circling() -> void:
	_enter(CIRCLE, randf_range(patience.x, patience.y))


func _enter(next: int, seconds := 0.0) -> void:
	state = next
	_left = seconds
