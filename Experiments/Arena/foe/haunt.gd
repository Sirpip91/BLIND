extends Node

## How something fights that's already been killed once. It's never anywhere
## for longer than a blow takes, and some of it isn't there at all.

const Strike = preload("res://Experiments/Arena/fighter/strike.gd")

enum { GONE, STRIKING, OPEN, HURT, RISEN }

## Blows in a run, the first time and from then on.
@export var first_run := 3
@export var runs := Vector2i(2, 4)
## Seconds unseen between the blows of a run, and before the next one.
@export var between := Vector2(0.28, 0.5)
@export var before_run := Vector2(0.9, 1.5)
## Seconds it has to get its breath at the end of one.
@export var winded := 1.15
## And stood there to be looked at, when it's first back.
@export var stands := 1.5
## Where it comes back: round from where the player's looking, and how far off.
@export_range(10.0, 150.0, 1.0, "radians_as_degrees") var nearest_round := deg_to_rad(26.0)
@export_range(10.0, 170.0, 1.0, "radians_as_degrees") var furthest_round := deg_to_rad(80.0)
@export var away := 2.2
@export var windup := 0.56
## Each life lost makes it this much quicker.
@export var quicker := 0.93
## Chance it's gone from under a cut it sees begun.
@export_range(0.0, 1.0, 0.05) var slips := 0.8
## Chance of there being more than one of it, once it's been cut.
@export_range(0.0, 1.0, 0.05) var doubles := 0.6

var fighter: Node3D
var rival: Node3D
var arm: Node3D
## Others of it, that can't hurt anyone.
var images: Array[Node3D] = []
var state := GONE

var _left := 1.0
var _blows := 0
var _side := 1.0
var _pace := 1.0
var _cuts := 0
var _last := Vector2.ZERO
var _drew_blood := false
var _among := false


func begin(whose: Node3D, against: Node3D) -> void:
	fighter = whose
	rival = against
	arm = fighter.arm
	_pace = 1.0
	_cuts = 0
	_blows = first_run
	_side = [1.0, -1.0].pick_random()
	if not rival.arm.wound_up.is_connected(_on_cut_begun):
		rival.arm.wound_up.connect(_on_cut_begun)
	state = RISEN
	_left = stands


func end() -> void:
	_send_images_off()
	if rival and rival.arm.wound_up.is_connected(_on_cut_begun):
		rival.arm.wound_up.disconnect(_on_cut_begun)


## There's more than one of it, and no telling which.
func is_among_others() -> bool:
	return _among


func think(delta: float) -> Vector3:
	_left -= delta
	if rival.vitals.dead:
		return Vector3.ZERO
	var to := rival.global_position - fighter.global_position
	to.y = 0.0
	match state:
		RISEN:
			if _left <= 0.0:
				_go(0.55)
		GONE:
			if _left <= 0.0:
				_come_back()
		STRIKING:
			_mind_images()
			if arm.phase == arm.Phase.READY:
				_after_blow()
			elif arm.phase == arm.Phase.WINDUP:
				# Stays on whoever it's come for.
				return to.normalized() * clampf((to.length() - 1.9) * 3.0, -0.4, 2.4)
		OPEN:
			if arm.phase == arm.Phase.READY:
				_blows = randi_range(runs.x, runs.y) + mini(_cuts / 2, 1)
				_go(randf_range(before_run.x, before_run.y) * _pace)
		HURT:
			if _left <= 0.0:
				fighter.make_whole()
				_blows = randi_range(runs.x, runs.y) + mini(_cuts / 2, 1)
				_go(1.5 * _pace)
	return Vector3.ZERO


func _go(seconds: float) -> void:
	if not fighter.is_unseen():
		fighter.vanish()
	arm.reset()
	state = GONE
	_left = seconds


func _come_back() -> void:
	# Nearly always the other side from last time.
	_side *= -1.0 if randf() < 0.75 else 1.0
	var round_by := _side * randf_range(nearest_round, furthest_round)
	var blow := _blow()
	fighter.appear_at(_place(round_by))
	arm.reset()
	arm.begin(blow)
	state = STRIKING
	_among = false
	if _cuts > 0 and randf() < doubles:
		_show_images(round_by, blow)


func _place(round_by: float) -> Vector3:
	var at: Vector3 = rival.global_position + rival.facing().rotated(Vector3.UP, -round_by) * away
	var flat := Vector2(at.x, at.z).limit_length(fighter.arena_radius - 0.6)
	return Vector3(flat.x, 0.0, flat.y)


func _blow() -> Strike:
	var ways := [Vector2(-0.75, -0.66), Vector2(0.75, -0.66), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0.8, 0.6), Vector2(-0.8, 0.6)]
	ways.erase(_last)
	_last = ways.pick_random()
	var blow := Strike.new()
	blow.direction = _last
	blow.windup = windup * _pace
	blow.release = 0.24
	blow.recover = 0.3
	blow.reach = 2.6
	blow.lunge = 3.0
	return blow


func _after_blow() -> void:
	_among = false
	_send_images_off()
	_blows -= 1
	if _drew_blood:
		# It stands back and lets it be felt.
		_drew_blood = false
		_blows = randi_range(runs.x, runs.y)
		_go(randf_range(before_run.x, before_run.y))
	elif _blows > 0:
		_go(randf_range(between.x, between.y) * _pace)
	else:
		_open(winded)


# Spent, and for once it stays where it is.
func _open(seconds: float) -> void:
	_send_images_off()
	_among = false
	state = OPEN
	arm.stagger(seconds, Vector2(0.4, -0.7))


func let_up() -> void:
	_drew_blood = true


## Thrown open by a parry.
func thrown_open() -> void:
	_send_images_off()
	_among = false
	state = OPEN


## Cut, and it'd have been the end of anyone else.
func was_cut() -> void:
	_send_images_off()
	_among = false
	_cuts += 1
	_pace *= quicker
	state = HURT
	_left = 0.35


func is_between() -> bool:
	return state in [HURT, GONE, RISEN]


func _on_cut_begun(strike: Strike) -> void:
	if fighter.vitals.dead or fighter.is_unseen():
		return
	if state == RISEN:
		return
	if state == OPEN or strike.sunder:
		strike.earned = true
		return
	if state != STRIKING or strike.earned:
		return
	# Too far into its own to be anywhere else.
	var committed: bool = arm.phase == arm.Phase.RELEASE or (arm.phase == arm.Phase.WINDUP and arm.progress() > 0.6)
	if committed or rival.global_position.distance_to(fighter.global_position) > 3.2 or randf() > slips:
		return
	strike.pinned_to = null
	_among = false
	_send_images_off()
	_go(0.3 * _pace)


# ---- the rest of it

func _show_images(round_by: float, blow: Strike) -> void:
	_among = true
	var spots := [-round_by, round_by * 0.15, round_by + signf(round_by) * 0.9]
	spots.shuffle()
	for i in mini(images.size(), 1 + _cuts):
		var image := images[i]
		image.appear_at(_place(spots[i]))
		image.arm.reset()
		var feint: Strike = blow.duplicate()
		feint.direction = [Vector2(-0.75, -0.66), Vector2(0.75, -0.66), Vector2(0, -1)].pick_random()
		image.arm.begin(feint)


func _mind_images() -> void:
	for image in images:
		# Gone as it would have landed.
		if not image.is_unseen() and image.arm.phase == image.arm.Phase.RELEASE and image.arm.progress() > 0.35:
			image.vanish()
	if arm.phase == arm.Phase.RELEASE:
		_among = false


func _send_images_off() -> void:
	for image in images:
		if is_instance_valid(image) and not image.is_unseen():
			image.vanish()
