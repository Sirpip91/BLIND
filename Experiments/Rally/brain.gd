extends Node

## Decides where the enemy walks, when it attacks and when it guards. It only
## knows what the player could see too: where they are, and what their sword
## is doing, a human moment late.

const Strike = preload("res://Experiments/Rally/strike.gd")
const Pattern = preload("res://Experiments/Rally/pattern.gd")

enum { CIRCLE, CLOSE, FIGHT, GIVE_GROUND, REEL, ANSWER, BROKEN, FETCH, BEATEN, OUT }

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
@export var stoop := 0.5

@export_group("Guarding")
## Chance it answers a cut it sees coming, and how late.
@export_range(0.0, 1.0, 0.05) var guard_chance := 0.85
@export var reaction := Vector2(0.12, 0.22)
## Chance that answer is a parry.
@export_range(0.0, 1.0, 0.05) var parry_chance := 0.15
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
## Seconds after being hit that it's sure to guard the next.
@export var shell_time := 1.4

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
var _drop := 0.0
var _think := 0.0
# The player's last few cuts; nothing at all for a thrust.
var _cuts: Array[Vector2] = []
## How the cut on its way will be met: "parry", "block" or not.
var answer := ""
var _weighed := false
var _runs := 0
var _wary := 0.0
var _shell := 0.0
var _blocks := 0

## Maimed: faster, and nothing left to save its strength for.
var desperate := false

var _stooped := 0.0
var _dropping := false

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
	_shell = 0.0
	_blocks = 0
	_cuts.clear()
	answer = ""
	_stooped = 0.0
	_dropping = false
	desperate = false
	patience = calm_patience


## The velocity it wants.
func think(delta: float) -> Vector3:
	if rival.vitals.dead and state not in [FIGHT, OUT]:
		out()
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
		ANSWER:
			_expect(delta)
			return toward * clampf((distance - 1.9) * 2.5, -0.6, 1.2)
		BROKEN:
			if _left <= 0.0:
				recover()
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


func is_broken() -> bool:
	return state == BROKEN or state == BEATEN


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
	if strike.is_thrust() or strike.path.is_empty():
		_read(strike)
	return


func _mind_guard(delta: float, _distance: float) -> void:
	if arm.phase != arm.Phase.GUARD or state in [ANSWER, BROKEN]:
		return
	_drop -= delta
	if _drop <= 0.0:
		arm.lower_guard()


## Someone's beat to cut at it: it shows where it thinks that will come from.
func stand_guard() -> void:
	_runs = 0
	_think = 0.0
	_enter(ANSWER, 3.0)


# What they did last time, or the other way back, or where they're pointing.
func _expect(delta: float) -> void:
	_think -= delta
	if _think > 0.0 or not arm.is_open_to_act() or not fighter.is_armed():
		return
	_think = temper.rethink * randf_range(0.8, 1.3)
	var guess: Vector2 = rival.aim
	if _cuts.size() > 1 and _alike(_cuts[-1], _cuts[-2]):
		guess = _cuts[-1]
	elif not _cuts.is_empty() and randf() < 0.45:
		guess = -_cuts[-1]
	elif not _cuts.is_empty() and randf() < 0.35:
		guess = _cuts[-1]
	arm.raise_guard(_from(guess))
	_drop = 0.6


# One is on its way. Where it was already looking, it's turned aside; anywhere
# else it has to get there.
func _read(strike: Strike) -> void:
	var way := strike.direction if not strike.is_thrust() else Vector2.ZERO
	answer = ""
	if fighter.is_armed() and not state in [FIGHT, REEL, BROKEN, FETCH, BEATEN, OUT] and (arm.is_open_to_act() or arm.phase == arm.Phase.BOUNCE):
		var from: Vector2 = _from(way) if way != Vector2.ZERO else arm.guard_side
		var off := absf(arm.guard_side.angle_to(from)) if arm.phase == arm.Phase.GUARD else PI * 0.35
		if way != Vector2.ZERO and arm.phase == arm.Phase.GUARD and off < arm.guard_tolerance:
			answer = "parry"
		elif randf() < _chance(way, off):
			answer = "block"
		if answer != "":
			arm.reset()
			arm.raise_guard(from)
			_drop = 0.4
		elif arm.phase == arm.Phase.GUARD and way == Vector2.ZERO:
			arm.lower_guard()
	_cuts.append(way)
	if _cuts.size() > 6:
		_cuts.pop_front()


func _chance(way: Vector2, off: float) -> float:
	var chance: float = temper.react - 0.4 * off / PI - 0.25 * fighter.vitals.weariness()
	if fighter.one_handed():
		chance -= 0.2
	# It remembers.
	for i in _cuts.size():
		if _alike(way, _cuts[i]):
			chance += 0.07 + 0.16 * (i + 1.0) / _cuts.size()
	return chance


func _alike(one: Vector2, other: Vector2) -> bool:
	if one == Vector2.ZERO or other == Vector2.ZERO:
		return one == other
	return absf(one.angle_to(other)) < deg_to_rad(40.0)


func _from(way: Vector2) -> Vector2:
	return Vector2(way.x, -way.y)


## It has turned one aside, or waited long enough, and it's its beat. `quick`
## is 0 to 1.
func strike_back(quick: float) -> void:
	if peaceful or fighter.vitals.dead or not fighter.is_armed() or state in [BROKEN, FETCH, BEATEN, OUT]:
		_enter(GIVE_GROUND, 0.4)
		return
	_pattern = _pick()
	_step = 0
	while _step < _blows() - 1 and _pattern.strikes[_step].feint:
		_step += 1
	arm.reset()
	_enter(FIGHT)
	_throw(lerpf(1.0, temper.quickest, quick))


func take_beat() -> void:
	if state != ANSWER:
		return
	if randf() < 0.7:
		strike_back(0.2)
	else:
		_enter(GIVE_GROUND, 0.5)


func broken(seconds: float) -> void:
	_enter(BROKEN, seconds)


func recover() -> void:
	fighter.vitals.pressure = fighter.vitals.max_pressure * 0.45
	arm.reset()
	_enter(GIVE_GROUND, 0.9)


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
