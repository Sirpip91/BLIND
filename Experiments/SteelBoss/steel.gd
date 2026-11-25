extends Node3D

## One duel, start to finish. Both fighters' blows come here to be judged, and
## here is where the rules meet the feel.

const Exchange = preload("res://Experiments/SteelBoss/exchange.gd")
const Strike = preload("res://Experiments/SteelBoss/strike.gd")
const Part = preload("res://Experiments/SteelBoss/part.gd")
const Temper = preload("res://Experiments/SteelBoss/temper.gd")
const Piece = preload("res://Experiments/SteelBoss/piece.gd")

@export var player: CharacterBody3D
@export var enemy: CharacterBody3D
@export var swordsman: Node
@export var arm: Node3D
@export var edge: Node
@export var feel: Node
@export var hint: Label
@export var veil: ColorRect
## Opponents T goes through, starting with the first.
@export var tempers: Array[Temper] = []
@export var player_start := Vector3(0, 0, 3.6)
@export var enemy_start := Vector3(0, 0, -2.4)
## How much shorter than its reach a blow only grazes from.
@export var graze := 0.2

const HELP := "Left: click to cut, or hold and draw one     Wheel up: thrust     Right: guard     Space: step     Q: lock     R: again     T: opponent"

## The last few exchanges, for anyone watching.
signal judged(attacker: Node3D, result: String)

var _over := false
var _round := 0
var _temper := 0


func _ready():
	player.rival = enemy
	enemy.rival = player
	enemy.arm.struck.connect(_judge_theirs)
	arm.struck.connect(_meet_blade)
	edge.reached.connect(_meet_guard)
	edge.met.connect(_meet_body)
	arm.released.connect(feel.swing)
	player.slipped.connect(feel.slipped)
	player.vitals.died.connect(_on_player_died)
	tempers[0].apply(enemy.brain)
	enemy.begin()
	enemy.sprang_back.connect(swordsman.close)
	enemy.vitals.died.connect(_on_enemy_died)
	# The player's camera isn't ready to take children yet.
	_begin.call_deferred()


func _begin() -> void:
	arm.reparent(player.camera, false)
	arm.reset_physics_interpolation()
	restart()
	_say(HELP)
	await get_tree().create_timer(9.0).timeout
	if hint.text == HELP:
		_say("")


func _unhandled_key_input(event):
	if not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			restart()
		KEY_T:
			_temper = (_temper + 1) % tempers.size()
			tempers[_temper].apply(enemy.brain)
			restart()
			_tell(tempers[_temper].label)


func restart() -> void:
	_round += 1
	_over = false
	Engine.time_scale = 1.0
	veil.modulate.a = 0.0
	get_tree().call_group(Piece.GROUP, "queue_free")
	var to := enemy_start - player_start
	player.reset_at(player_start, atan2(-to.x, -to.z))
	swordsman.reset()
	enemy.reset_at(enemy_start)
	_say("")


func _judge_theirs(strike: Strike) -> void:
	if _over:
		return
	var result: String = Exchange.resolve(enemy, player, strike)
	var opening: bool = enemy.brain.is_last_strike()
	judged.emit(enemy, result)
	if result == "miss":
		return
	if result == "evade":
		if opening:
			player.slip()
			swordsman.open(swordsman.slip_time)
		return
	# How late in the window the guard came up: 0 is on the very moment.
	var late: float = clampf(arm.guard_age() / maxf(arm.parry_window, 0.01), 0.0, 1.0)
	var at := _meeting_point(arm)
	var away := player.global_position - enemy.global_position
	away.y = 0.0
	swordsman.met(result, strike)
	player.push(away.normalized() * {"parry": 0.8, "block": 3.2, "hit": 4.2}.get(result, 0.0))
	match result:
		"parry":
			feel.parry(at, strike, late)
		"block":
			feel.block(at, strike, false)
		"hit":
			var grazed: bool = away.length() > strike.reach - graze
			swordsman.wounded(strike)
			player.vitals.wound(0.5 if grazed else 1.0)
			feel.hurt(strike, grazed, player.vitals.dead)
	var open: float = enemy.landed(result, late, strike.carries_to())
	if open > 0.0:
		swordsman.open(open)


# Halfway through our cut: is there a blade in the way?
func _meet_blade(strike: Strike) -> void:
	if _over or (enemy.reader and enemy.reader.verdict != "block"):
		return
	var result: String = Exchange.resolve(player, enemy, strike)
	if result == "parry" or result == "block":
		_stopped(strike, result)


func _stopped(strike: Strike, result: String) -> void:
	edge.spend(strike)
	judged.emit(player, result)
	swordsman.stopped(result)
	enemy.stopped(result, strike, player.global_position)
	feel.block(_meeting_point(enemy.arm), strike, true)
	if enemy.one_handed():
		swordsman.open(0.5)


# About to go into him from this side: is that the side he's covering?
func _meet_guard(strike: Strike, way: Vector2) -> void:
	if _over or not enemy.is_armed():
		return
	if enemy.reader:
		if enemy.reader.verdict != "block":
			return
	elif not enemy.arm.covers(Vector2(way.x, -way.y)):
		return
	strike.direction = way
	_stopped(strike, "parry" if enemy.arm.is_fresh() else "block")


func _physics_process(_delta: float):
	if arm.phase != arm.Phase.RELEASE:
		enemy.hold(false)


func _meet_body(strike: Strike, part: Part, at: Vector3, region: RefCounted, travel: Vector3) -> void:
	if player.vitals.dead:
		return
	var result: String = enemy.cut(strike, part, at, region, travel, player.global_position)
	if result == "none":
		return
	if result == "glance":
		edge.spend(strike)
		judged.emit(player, result)
		feel.block(at, strike, true)
		return
	if strike.force <= 0.0:
		edge.spend(strike)
	enemy.hold(true)
	judged.emit(player, result)
	swordsman.bit(result == "scratch")
	feel.cut(at, strike, result)


func _meeting_point(guarding: Node3D) -> Vector3:
	# Where the blades cross: partway up the defender's.
	return guarding.global_transform * Vector3(-0.02, 0.45, 0.0)


func _on_enemy_died() -> void:
	_over = true
	swordsman.close()
	_end(4.2)


func _on_player_died() -> void:
	_over = true
	arm.go_down()
	player.fallen = true
	enemy.brain.let_up()
	_end(2.6)


func _end(after: float) -> void:
	var this_round := _round
	await get_tree().create_timer(after).timeout
	if this_round != _round:
		return
	var fade := create_tween()
	fade.tween_property(veil, "modulate:a", 1.0, 1.0)
	await fade.finished
	if this_round != _round:
		return
	restart()
	veil.modulate.a = 1.0
	create_tween().tween_property(veil, "modulate:a", 0.0, 0.8)


func _tell(text: String) -> void:
	_say(text)
	await get_tree().create_timer(2.5).timeout
	if hint.text == text:
		_say("")


func _say(text: String) -> void:
	hint.text = text
