extends Node

## Decides where the enemy walks, when it attacks and when it guards. It only
## knows what the player could see too: where they are, and what their sword
## is doing, a human moment late.

const Strike = preload("res://Experiments/SteelGuard/strike.gd")
const Pattern = preload("res://Experiments/SteelGuard/pattern.gd")

enum { CIRCLE, CLOSE, FIGHT, GIVE_GROUND, REEL, FETCH, BEATEN, OUT }

@export var patterns: Array[Pattern] = []

@export_group("Footwork")
@export var ring := 3.3
@export var circle_speed := 0.75
@export var close_speed := 1.9
@export var retreat_speed := 1.5
## Seconds of circling between attacks.
@export var patience := Vector2(1.2, 3.4)
## How near it starts a swing from.
@export var strike_from := 2.55
## How fast it keeps up with someone backing off mid-pattern.
@export var chase_speed := 2.3

@export_group("Pressing on")
## Chance of going straight from one pattern into another, and how many times.
@export_range(0.0, 1.0, 0.05) var press_on := 0.15
@export var most_runs := 1

@export_group("Desperate")
@export_range(0.5, 1.0, 0.01) var desperate_speed := 0.9
@export_range(0.0, 1.0, 0.05) var desperate_press_on := 0.5
@export var fetch_speed := 1.1
## Seconds stooping for its sword.
@export var stoop := 0.9

@export_group("Guarding")
## How late it answers a cut it sees coming.
@export var reaction := Vector2(0.12, 0.22)
## Chance to strike straight back after blocking.
@export_range(0.0, 1.0, 0.05) var counter_chance := 0.9
## An answer comes this much quicker than an attack of its own.
@export_range(0.4, 1.0, 0.05) var answer_speed := 0.7
## Chance to strike at a missed cut.
@export_range(0.0, 1.0, 0.05) var punish_chance := 0.8

## Chance it drops an attack it has begun, to meet one that would land first.
@export_range(0.0, 1.0, 0.05) var think_better := 0.85

@export_group("Reading the player")
## How much each cut thrown without an opening puts it on its guard, and how
## fast that wears off a second.
@export var wariness_per_cut := 0.2
@export var wariness_fade := 0.09

var temper: Resource
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
# Seconds until it goes for someone busy drawing.
var _rush := -1.0
var _saw_drawing := false
var _weighed := false
var _runs := 0
var _wary := 0.0
var _blocks := 0

## Maimed: faster, and nothing left to save its strength for.
var desperate := false

var _stooped := 0.0

@onready var calm_patience := patience


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
	_rush = -1.0
	_saw_drawing = false
	_blocks = 0
	_stooped = 0.0
	desperate = false
	patience = calm_patience


## The velocity it wants.
func think(delta: float) -> Vector3:
	if rival.vitals.dead and state not in [FIGHT, OUT]:
		out()
	_left -= delta
	_wary = maxf(_wary - wariness_fade * delta, 0.0)
	var to := rival.global_position - fighter.global_position
	to.y = 0.0
	var distance := to.length()
	var toward := to / maxf(distance, 0.01)
	_mind_attack(delta)
	_mind_drawing(delta, distance)
	fighter.ward.mind(delta, temper, distance, state in [CIRCLE, CLOSE, GIVE_GROUND])
	match state:
		CIRCLE:
			return _circle(delta, distance, toward)
		CLOSE:
			arm.aim = _pattern.strikes[0].direction if not _pattern.strikes[0].is_thrust() else Vector2(0, 1)
			if distance <= strike_from:
				# Nobody walks onto a blade already on its way.
				if rival.arm.is_attacking():
					return -toward * retreat_speed
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
			# Backing out from under whatever comes next.
			return -toward * 0.8
		FETCH:
			return _go_for_sword(delta)
	return Vector3.ZERO


func _go_for_sword(delta: float) -> Vector3:
	var to: Vector3 = fighter.fallen_sword.global_position - fighter.global_position
	to.y = 0.0
	if to.length() > 0.45 and _stooped <= 0.0:
		return to.normalized() * fetch_speed
	_stooped += delta
	fighter.body.kneeling = true
	if _stooped >= stoop:
		fighter.body.kneeling = fighter.is_lame()
		fighter.take_up_sword()
		_enter(GIVE_GROUND, 0.8)
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
		if _left <= 0.0 and arm.is_idle():
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
	if _weighed or distance > strike_from + 0.2 or not arm.is_idle():
		return
	_weighed = true
	if randf() < punish_chance:
		_strike_now(answer_speed)


func _strike_now(quickness := 1.0) -> void:
	_pattern = _pick()
	_enter(FIGHT)
	_throw(quickness)


func _pick() -> Pattern:
	_step = 0
	var known := patterns.filter(func(p): return (desperate or not p.desperate_only) and p != _pattern)
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


# From its knees it can't keep a run going.
func _blows() -> int:
	return mini(_pattern.strikes.size(), mini(temper.most_blows, 2 if fighter.is_lame() else 99))


## Nothing between it and an edge.
func is_helpless() -> bool:
	return state in [FETCH, BEATEN, OUT]


func is_last_strike() -> bool:
	return _pattern == null or _step >= _blows() - 1


func _throw(quickness := 1.0) -> void:
	arm.lower_guard()
	if not arm.begin(_pattern.strikes[_step], quickness * temper.slowness * (desperate_speed if desperate else 1.0)):
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
	if _pattern and _step < _blows():
		_throw()
	elif _runs < most_runs and randf() < (desperate_press_on if desperate else press_on):
		_runs += 1
		_strike_now()
	else:
		_runs = 0
		_enter(GIVE_GROUND, randf_range(0.4, 0.8))


func _on_rival_wound_up(strike: Strike) -> void:
	if not strike.earned:
		_wary = minf(_wary + wariness_per_cut, 1.0)
	if is_helpless() or not fighter.is_armed():
		return
	if state == FIGHT:
		_weigh_attack()


# Landing second is no use to anyone.
func _weigh_attack() -> void:
	if arm.phase == arm.Phase.RECOVER or arm.phase == arm.Phase.BOUNCE:
		if randf() < think_better + _wary * 0.4:
			_enter(GIVE_GROUND, 0.4)
		return
	if arm.phase != arm.Phase.WINDUP or arm.strike.feint:
		return
	var mine: float = arm.time_to_land()
	var wait := randf_range(reaction.x, reaction.y)
	if mine < rival.arm.time_to_land() or mine < wait + 0.1:
		return
	if randf() < think_better + _wary * 0.4:
		_react = wait


func _mind_attack(delta: float) -> void:
	if _react < 0.0:
		return
	_react -= delta
	if _react < 0.0 and state == FIGHT and arm.cancel():
		_enter(GIVE_GROUND, 0.4)


# Someone drawing has no guard up.
func _mind_drawing(delta: float, distance: float) -> void:
	if not rival.drawing:
		_saw_drawing = false
		_rush = -1.0
		return
	if not _saw_drawing:
		_saw_drawing = true
		if not peaceful and randf() < temper.rush_chance:
			_rush = temper.read_delay + randf_range(0.05, 0.2)
	if _rush < 0.0:
		return
	_rush -= delta
	if _rush < 0.0 and distance < strike_from + 0.3 and arm.is_idle() and state in [CIRCLE, CLOSE, GIVE_GROUND]:
		_runs = 0
		_strike_now(answer_speed)


## It stopped one of the player's cuts. A second in a row is always answered.
func blocked() -> void:
	_blocks += 1
	if peaceful:
		return
	if _blocks >= 2 or randf() < counter_chance:
		_blocks = 0
		_runs = 0
		_strike_now(answer_speed)


func was_hit() -> void:
	_blocks = 0


## It drew blood: it stands back and lets it be felt.
func let_up() -> void:
	if _pattern:
		_step = _blows() - 1
	_runs = most_runs


func despair() -> void:
	desperate = true
	_runs = 0
	patience = calm_patience * 0.5


func fetch() -> void:
	_stooped = 0.0
	_enter(FETCH)


func give_up() -> void:
	_enter(BEATEN)


func reel(seconds: float) -> void:
	_enter(REEL, seconds)


func out() -> void:
	_enter(OUT)


func _back_to_circling() -> void:
	_enter(CIRCLE, randf_range(patience.x, patience.y))


func _enter(next: int, seconds := 0.0) -> void:
	state = next
	_left = seconds
