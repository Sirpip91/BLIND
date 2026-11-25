extends Node

## Decides where the enemy walks, when it attacks and when it guards. It only
## knows what the player could see too: where they are, and what their sword
## is doing, a human moment late.

const Strike = preload("res://Experiments/Arena/fighter/strike.gd")
const Pattern = preload("res://Experiments/Arena/fighter/pattern.gd")

enum { CIRCLE, CLOSE, FIGHT, GIVE_GROUND, REEL, FETCH, BEATEN, OUT, WAIT, CHANGE, VANISH, HAUNT }

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
## What's doing the thinking, once it's come back from the dead.
var haunt: Node:
	set(value):
		haunt = value
		if value:
			state = HAUNT
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
# The step its run ends before.
var _until := 0
# How much it likes each of its patterns, when it isn't the only one of its kind.
var _tastes := {}
var _joining := false
var _pretending := false
var _threat := 0.0
var _next_threat := 2.0
var _waking := -1.0
# How often each blow has been parried.
var _parried := {}
var _must_go_on := false
var _react := -1.0
var _drop := 0.0
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
@onready var _calm_circle := circle_speed
@onready var _calm_close := close_speed
@onready var _calm_from := strike_from
@onready var _calm_runs := most_runs


func start(owner_fighter: Node3D, against: Node3D, its_arm: Node3D) -> void:
	fighter = owner_fighter
	rival = against
	arm = its_arm
	arm.finished.connect(_on_finished)
	rival.arm.wound_up.connect(_on_rival_wound_up)
	reset()


func reset() -> void:
	_enter(CIRCLE, 0.9)
	_pretending = false
	_waking = -1.0
	_must_go_on = false
	_parried.clear()
	circle_speed = _calm_circle
	close_speed = _calm_close
	strike_from = _calm_from
	most_runs = _calm_runs
	press_on = temper.press_on
	_tastes.clear()
	for pattern in patterns:
		_tastes[pattern] = randf_range(0.15, 1.0) if temper.most_blows < 3 else 1.0
	_react = -1.0
	_runs = 0
	_wary = 0.0
	_shell = 0.0
	_blocks = 0
	_stooped = 0.0
	_dropping = false
	desperate = false
	patience = calm_patience


## The velocity it wants.
func think(delta: float) -> Vector3:
	if haunt:
		return haunt.think(delta)
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
		WAIT:
			if _waking >= 0.0:
				_waking -= delta
				if _waking < 0.0:
					_stand_up()
		CHANGE:
			if _left <= 0.0:
				_enter(CIRCLE, 0.2)
		VANISH:
			if _left <= 0.0:
				_come_back()
		CIRCLE:
			return _circle(delta, distance, toward)
		CLOSE:
			var first: Strike = _pattern.strikes[_step]
			arm.aim = first.direction if not first.is_thrust() else Vector2(0, 1)
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
			return toward * close_speed * (1.35 if _joining else 1.0)
		FIGHT:
			if _pretending and arm.phase == arm.Phase.WINDUP and arm.progress() > 0.75:
				_pretending = false
				arm.cancel()
				_enter(GIVE_GROUND, 0.3)
				return Vector3.ZERO
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
			return -toward * (0.1 if arm.is_flung() else temper.reel_back)
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
	if distance > ring + 2.2:
		return toward * close_speed * 1.2
	if not peaceful:
		_punish(distance)
		if state != CIRCLE:
			return Vector3.ZERO
		if _left <= 0.0 and arm.phase == arm.Phase.READY and fighter.may_go_in():
			_joining = false
			_pattern = _pick()
			_enter(CLOSE, 2.2)
	if fighter.is_in_crowd():
		return _surround(delta, distance, toward)
	var stand := ring
	var wanted := toward.cross(Vector3.UP) * _around + toward * clampf((distance - stand) * 1.4, -1.0, 1.0)
	return wanted.limit_length(1.0) * circle_speed


# Out to its own side of the player, with a step in now and then that comes to
# nothing.
func _surround(delta: float, distance: float, toward: Vector3) -> Vector3:
	_next_threat -= delta
	_threat -= delta
	if _next_threat <= 0.0:
		_next_threat = randf_range(1.6, 4.5)
		_threat = randf_range(0.35, 0.6)
	var place: Vector2 = fighter.director.place_for(fighter)
	var off := wrapf(place.x - fighter.director.bearing(fighter), -PI, PI)
	var stand := ring + place.y - (0.9 if _threat > 0.0 else 0.0)
	var wanted := -toward.cross(Vector3.UP) * clampf(off * 2.2, -1.0, 1.0) + toward * clampf((distance - stand) * 1.6, -1.0, 1.0)
	return wanted.limit_length(1.0) * circle_speed * 1.9


# A cut that hit nothing leaves the player stuck in it.
func _punish(distance: float) -> void:
	var missed: bool = rival.arm.phase == rival.arm.Phase.RECOVER
	if not missed:
		_weighed = false
		return
	if _weighed or distance > strike_from + 0.2 or arm.phase != arm.Phase.READY:
		return
	_weighed = true
	if randf() < punish_chance and fighter.may_go_in(true):
		_strike_now(answer_speed)


func _strike_now(quickness := 1.0) -> void:
	_pattern = _pick()
	_enter(FIGHT)
	_throw(quickness)


# One that only throws a blow or two takes them from anywhere in the run, and
# nobody comes in the way the last one did if there's another.
func _pick() -> Pattern:
	var known := patterns.filter(func(p): return (desperate or temper.fierce or not p.desperate_only) and p != _pattern)
	if fighter.has_changed():
		known.append_array(temper.second_patterns.filter(func(p): return p != _pattern))
	var most: int = mini(temper.most_blows, 2 if fighter.is_lame() else 99)
	if temper.most_blows < 3 and randf() < 0.35:
		most = 1
	var starts := []
	var total := 0.0
	for p: Pattern in known:
		var last := maxi(p.strikes.size() - most, 0) if temper.most_blows < 3 else 0
		for i in last + 1:
			var weight: float = p.weight * _tastes.get(p, 1.0) / (last + 1.0)
			if temper.most_blows < 3:
				weight *= fighter.director.freshness(p.strikes[i].direction)
			starts.append([p, i, weight])
			total += weight
	var at := randf() * total
	var picked: Array = starts[-1]
	for each: Array in starts:
		at -= each[2]
		if at <= 0.0:
			picked = each
			break
	_step = picked[1]
	_until = mini(picked[0].strikes.size(), _step + most)
	return picked[0]


## In the middle of throwing something, and not to be put off it.
func in_pattern() -> bool:
	return state == FIGHT


## Nothing between it and an edge.
func is_helpless() -> bool:
	return state in [FETCH, BEATEN, OUT, WAIT]


func is_last_strike() -> bool:
	return _pattern == null or _step >= _until - 1


func _throw(quickness := 1.0) -> void:
	arm.lower_guard()
	var strike := _pattern.strikes[_step]
	if temper.learns and not is_last_strike() and not strike.feint and _parried.get(strike, 0) >= 2 and randf() < 0.65:
		# They know that one by now.
		_parried[strike] -= 1
		strike = strike.duplicate()
		strike.feint = true
	if not arm.begin(strike, quickness * temper.slowness * (desperate_speed if desperate else 1.0)):
		_enter(GIVE_GROUND, 0.4)
		return
	fighter.director.note(strike.direction)
	if not strike.feint:
		arm.hold_back(fighter.director.hold_back(fighter, arm.time_to_land()))


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
	if haunt:
		return
	if state != FIGHT:
		return
	_step += 1
	if _pattern and _step < _until:
		_throw()
	elif _must_go_on:
		_must_go_on = false
		_strike_now(0.9)
	elif _runs < most_runs and randf() < (desperate_press_on if desperate else press_on):
		_runs += 1
		_strike_now()
	else:
		_runs = 0
		if _can_vanish() and randf() < 0.7:
			fighter.vanish()
			_enter(VANISH, randf_range(0.8, 1.6))
			return
		_enter(GIVE_GROUND, randf_range(0.4, 0.8) * (0.6 if temper.most_blows < 3 else 1.0))


func _on_rival_wound_up(strike: Strike) -> void:
	if haunt:
		return
	if fighter.reader.on:
		return
	if not strike.earned:
		_wary = minf(_wary + wariness_per_cut, 1.0)
	if is_helpless() or not fighter.is_armed():
		return
	if state == FIGHT:
		_weigh_attack()
		return
	if _shell > 0.0 or randf() < guard_chance + _wary * 0.6:
		_react = randf_range(reaction.x, reaction.y) * lerpf(1.0, 0.6, _wary)


# Landing second is no use to anyone.
func _weigh_attack() -> void:
	if arm.phase == arm.Phase.RECOVER or arm.phase == arm.Phase.BOUNCE:
		if randf() < think_better + _wary * 0.4:
			_react = randf_range(reaction.x, reaction.y) * 0.8
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
		_dropping = true


func _mind_guard(delta: float, distance: float) -> void:
	if _react >= 0.0:
		_react -= delta
		if _react < 0.0 and _dropping:
			_dropping = false
			if arm.cancel():
				_enter(GIVE_GROUND, 0.4)
		if _react < 0.0 and not arm.is_open_to_act() and rival.arm.is_attacking():
			# Still caught up in something; as soon as it's free.
			_react = 0.0
		elif _react < 0.0 and distance < 3.4 and rival.arm.strike and arm.is_open_to_act() and state != FIGHT and fighter.is_armed():
			# It answers the cut it saw start, so a feint draws the guard out.
			arm.parry_window = 0.3 if not fighter.one_handed() and randf() < parry_chance + _wary * 0.55 else 0.0
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
	if haunt:
		return
	_blocks += 1
	if peaceful:
		return
	if (parried or _blocks >= 2 or randf() < counter_chance) and fighter.may_go_in(true):
		_blocks = 0
		_runs = 0
		_strike_now(answer_speed)


func was_hit() -> void:
	_blocks = 0
	_shell = shell_time


## It drew blood: it stands back and lets it be felt.
func let_up() -> void:
	if haunt:
		haunt.let_up()
	if _pattern:
		_step = maxi(_until - 1, 0)
	_runs = most_runs


## Parried hard, and coming on regardless.
func go_on() -> void:
	_must_go_on = is_last_strike()


func was_parried(strike: Strike) -> void:
	if strike and _pattern and _step < _pattern.strikes.size():
		var which: Strike = _pattern.strikes[_step]
		_parried[which] = _parried.get(which, 0) + 1


func is_changing() -> bool:
	return state == CHANGE


func change(seconds: float) -> void:
	despair()
	_must_go_on = false
	_pattern = null
	_enter(CHANGE, seconds)
	if temper.changes == 1:
		press_on = 0.7
		desperate_press_on = 0.7
		most_runs = 2
		circle_speed = _calm_circle * 1.7
		close_speed = _calm_close * 1.5
		strike_from = 3.1


func _can_vanish() -> bool:
	return temper.changes == 2 and fighter.has_changed() and fighter.is_armed() and not fighter.is_lame() and not peaceful


# To one side, and already swinging.
func _come_back() -> void:
	var round_by: float = randf_range(0.6, 1.4) * [-1.0, 1.0].pick_random()
	var way: Vector3 = rival.facing().rotated(Vector3.UP, round_by)
	var at: Vector3 = rival.global_position + way * 2.3
	var flat := Vector2(at.x, at.z).limit_length(fighter.arena_radius - 0.6)
	fighter.appear_at(Vector3(flat.x, 0.0, flat.y))
	_joining = false
	_strike_now(1.0)


## On its knees until someone comes.
func wait(kneels: bool) -> void:
	_enter(WAIT)
	arm.go_down()
	fighter.body.kneeling = kneels


func wake(after: float) -> void:
	if state == WAIT and _waking < 0.0:
		_waking = after


func _stand_up() -> void:
	fighter.body.kneeling = false
	arm.reset()
	_enter(CIRCLE, randf_range(0.2, 0.8))
	if temper.starts_changed and temper.lives > 0:
		fighter.go_beyond()
	elif temper.starts_changed:
		fighter.change()


## Free to go in alongside someone.
func could_join() -> bool:
	return state == CIRCLE and not peaceful and arm.phase == arm.Phase.READY and fighter.is_armed()


func join() -> void:
	_joining = true
	_pattern = _pick()
	_enter(CLOSE, 2.6)


## The blow it's going in with isn't coming.
func only_pretend() -> void:
	_pretending = true


func is_pretending() -> bool:
	return _pretending


## One of its own has gone down.
func take_it(seconds: float) -> void:
	if state == CIRCLE:
		_left = minf(_left, seconds)


## Going in, or at it.
func is_engaged() -> bool:
	return state == CLOSE or state == FIGHT


func is_on_its_feet() -> bool:
	return state in [CIRCLE, CLOSE, GIVE_GROUND]


## Whatever it was doing, it isn't now.
func break_off() -> void:
	if state == FIGHT:
		_enter(GIVE_GROUND, 0.35)


func give_ground(seconds: float) -> void:
	_enter(GIVE_GROUND, seconds)


func hold_guard(seconds: float) -> void:
	_drop = seconds


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
	if haunt:
		if next == REEL:
			haunt.thrown_open()
		state = HAUNT
		return
	state = next
	_left = seconds
	if next not in [VANISH, FIGHT, CIRCLE] and fighter.is_unseen():
		fighter.show_again()
	if next != CLOSE and next != FIGHT:
		_pretending = false
