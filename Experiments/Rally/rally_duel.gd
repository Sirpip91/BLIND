extends Node3D

## One duel, start to finish. Both fighters' blows come here to be judged, and
## here is where the rules meet the feel.

const Exchange = preload("res://Experiments/Rally/exchange.gd")
const Strike = preload("res://Experiments/Rally/strike.gd")
const Part = preload("res://Experiments/Rally/part.gd")
const Temper = preload("res://Experiments/Rally/temper.gd")
const Piece = preload("res://Experiments/Rally/piece.gd")

@export var player: CharacterBody3D
@export var enemy: CharacterBody3D
@export var swordsman: Node
@export var arm: Node3D
@export var edge: Node
@export var feel: Node
@export var hint: Label
@export var veil: ColorRect
@export var rally: Node
## Opponents T goes through, starting with the first.
@export var tempers: Array[Temper] = []
@export var player_start := Vector3(0, 0, 3.6)
@export var enemy_start := Vector3(0, 0, -2.4)
## How much shorter than its reach a blow only grazes from.
@export var graze := 0.2

const HELP := "Left: cut, or hold and draw once his guard is broken     Wheel up: thrust     Right: guard     Space: step     Q: lock     R: again     T: opponent"

## The last few exchanges, for anyone watching.
signal judged(attacker: Node3D, result: String)

var _over := false
var _round := 0
var _temper := 0


func _ready():
	player.rival = enemy
	enemy.rival = player
	enemy.arm.struck.connect(_judge_theirs)
	arm.ran_out.connect(_on_line_spent)
	edge.clashed.connect(_meet_blade)
	enemy.broke.connect(_on_broke)
	rally.lapsed.connect(enemy.brain.take_beat)
	edge.reached.connect(_meet_guard)
	edge.met.connect(_meet_body)
	swordsman.drawing.connect(feel.drawing)
	arm.released.connect(feel.swing)
	player.slipped.connect(feel.slipped)
	player.vitals.died.connect(_on_player_died)
	tempers[0].apply(enemy.brain)
	enemy.begin()
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
	rally.end()
	swordsman.reset()
	enemy.reset_at(enemy_start)
	_say("")


func _judge_theirs(strike: Strike) -> void:
	if _over:
		return
	var result: String = Exchange.resolve(enemy, player, strike)
	judged.emit(enemy, result)
	if result == "miss":
		return
	# How late in the window the guard came up: 0 is on the very moment.
	var late: float = clampf(arm.guard_age() / maxf(arm.parry_window, 0.01), 0.0, 1.0)
	var at := _meeting_point(arm)
	var away := player.global_position - enemy.global_position
	away.y = 0.0
	swordsman.met(result, strike)
	player.push(away.normalized() * {"parry": 0.5, "block": 2.4, "hit": 4.2}.get(result, 0.0))
	match result:
		"evade":
			player.slip()
			rally.win()
		"parry":
			rally.win()
			feel.parry(at, strike, late)
		"block":
			feel.block(at, strike, false)
		"hit":
			var grazed: bool = away.length() > strike.reach - graze
			rally.end()
			swordsman.wounded(strike)
			player.vitals.wound(0.5 if grazed else 1.0)
			feel.hurt(strike, grazed, player.vitals.dead)
	enemy.landed(result, late, rally.heat())
	_mind_player_guard()


# Worn right through, a guard goes.
func _mind_player_guard() -> void:
	if player.vitals.weariness() >= 1.0 and not player.vitals.dead:
		rally.lose()
		swordsman.break_down()
		feel.hurt(enemy.arm.strike, true, false)
		enemy.brain.strike_back(0.5)


# About to go into him from this side: has he got his sword there?
func _meet_guard(strike: Strike, way: Vector2) -> void:
	if _over or not strike.path.is_empty() or not enemy.is_armed() or enemy.is_broken():
		return
	var answer: String = enemy.brain.answer
	if answer == "" or not enemy.arm.covers(Vector2(way.x, -way.y)):
		return
	strike.direction = way
	edge.spend(strike)
	judged.emit(player, answer)
	swordsman.stopped(answer == "parry")
	enemy.stopped(strike, player.global_position, answer == "parry")
	feel.block(_meeting_point(enemy.arm), strike, true)
	_mind_player_guard()
	if not enemy.is_broken() and enemy.brain.state != enemy.brain.FIGHT:
		rally.lose()
		enemy.brain.strike_back(rally.heat() if answer == "parry" else rally.heat() * 0.5)


# What's left of a broken guard, held over something.
func _meet_blade(strike: Strike, at: Vector3) -> void:
	judged.emit(player, "covered")
	swordsman.stopped(false)
	feel.block(at, strike, true)
	_after_line()


func _on_broke() -> void:
	rally.end()
	# The first time it takes a hand. After that, anything.
	swordsman.line_length = 0.85 if enemy.breaks < 2 else 2.0
	swordsman.line_force = 0.34 if enemy.breaks < 2 else 2.0
	swordsman.may_draw = true
	feel.broke(enemy.body.chest_point())


# One line is all a break is worth.
func _after_line() -> void:
	swordsman.may_draw = false
	if enemy.brain.state == enemy.brain.BROKEN:
		enemy.brain.recover()


func _on_line_spent(strike: Strike) -> void:
	if not strike.path.is_empty():
		_after_line()


func _physics_process(_delta: float):
	if not enemy.is_broken():
		swordsman.may_draw = false


func _meet_body(strike: Strike, part: Part, at: Vector3, region: RefCounted, travel: Vector3) -> void:
	if player.vitals.dead:
		return
	var fallen: bool = enemy.vitals.dead
	var result: String = enemy.cut(strike, part, at, region, travel, player.global_position)
	if result == "none":
		return
	if strike.force <= 0.0:
		edge.spend(strike)
	judged.emit(player, result)
	if strike.path.is_empty():
		rally.end()
		if not fallen and enemy.brain.state == enemy.brain.ANSWER:
			enemy.arm.stagger(0.3, _mirrored(strike.direction))
			enemy.brain.reel(0.3)
	swordsman.bit(result == "scratch")
	feel.cut(at, strike, result)


func _mirrored(way: Vector2) -> Vector2:
	return Vector2(-way.x, way.y)


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
