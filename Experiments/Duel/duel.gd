extends Node3D

## One duel, start to finish. Both fighters' blows come here to be judged, and
## here is where the rules meet the feel.

const Exchange = preload("res://Experiments/Duel/exchange.gd")
const Strike = preload("res://Experiments/Duel/strike.gd")

@export var player: CharacterBody3D
@export var enemy: CharacterBody3D
@export var swordsman: Node
@export var arm: Node3D
@export var feel: Node
@export var hint: Label
@export var player_start := Vector3(0, 0, 3.2)
@export var enemy_start := Vector3(0, 0, -2.2)

const HELP := "Mouse: aim     Left: cut that way (chase the sword you knock away, cut again as it lands)
Wheel up: thrust     Right: guard that side     WASD: circle     Space: step     Q: lock     R: again     T: training"

var _over := false
## The last few exchanges, for anyone watching.
signal judged(attacker: Node3D, result: String)


func _ready():
	player.rival = enemy
	enemy.rival = player
	arm.struck.connect(func(strike): _judge(player, enemy, strike))
	enemy.arm.struck.connect(func(strike): _judge(enemy, player, strike))
	arm.released.connect(feel.swing)
	arm.wound_up.connect(feel.wind_up)
	player.slipped.connect(feel.slipped)
	player.vitals.died.connect(_on_player_died)
	enemy.begin()
	enemy.vitals.broke.connect(func():
		feel.broke(enemy.body.mask_point())
		_say("OPEN"))
	enemy.vitals.recovered.connect(func(): _say(""))
	enemy.vitals.died.connect(_on_enemy_died)
	enemy.enraged.connect(func():
		feel.enraged(enemy.body.mask_point())
		swordsman.close()
		_say(""))
	# The player's camera isn't ready to take children yet.
	_begin.call_deferred()


func _begin() -> void:
	arm.reparent(player.camera, false)
	arm.reset_physics_interpolation()
	restart()
	_say(HELP)
	await get_tree().create_timer(12.0).timeout
	if hint.text == HELP:
		_say("")


func _unhandled_key_input(event):
	if not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			restart()
		KEY_T:
			enemy.brain.peaceful = not enemy.brain.peaceful
			_say("Training: it guards but won't attack" if enemy.brain.peaceful else "")


func restart() -> void:
	_over = false
	Engine.time_scale = 1.0
	var to := enemy_start - player_start
	player.reset_at(player_start, atan2(-to.x, -to.z))
	swordsman.reset()
	enemy.reset_at(enemy_start)
	_say("")


func _judge(attacker: Node3D, defender: Node3D, strike: Strike) -> void:
	if _over or attacker.vitals.dead or defender.vitals.dead:
		return
	var mine := attacker == player
	var result: String = Exchange.resolve(attacker, defender, strike)
	if not mine and defender.vitals.dead:
		return
	var opening: bool = enemy.brain.is_last_strike()
	# How late in the window the guard came up: 0 is on the very moment.
	var late: float = clampf(defender.arm.guard_age() / maxf(defender.arm.parry_window, 0.01), 0.0, 1.0)
	var at := _meeting_point(attacker, defender, result)
	judged.emit(attacker, result)
	match result:
		"miss":
			return
		"evade":
			if opening and not mine:
				player.slip()
				swordsman.open(_mirrored(strike.direction))
			return
		"parry":
			feel.parry(at, strike, late, mine)
		"block":
			feel.block(at, strike, mine)
	if mine:
		var finishing: bool = enemy.vitals.is_open()
		swordsman.landed(result, strike)
		enemy.met(result, strike, player.global_position, _mirrored(swordsman.open_way))
		if result == "hit":
			feel.hit(at, strike, true, finishing or enemy.vitals.dead)
		elif result == "glance":
			feel.glance(at, strike)
		if enemy.vitals.is_open() or enemy.vitals.dead:
			swordsman.close()
	else:
		var past: Vector2 = strike.carries_to()
		swordsman.met(result, strike, opening, _mirrored(past))
		var away := (player.global_position - enemy.global_position).normalized()
		player.push(away * {"parry": 0.8, "block": 3.2, "hit": 4.2}.get(result, 0.0))
		if result == "hit":
			player.vitals.wound(strike.damage)
			feel.hit(at, strike, false, player.vitals.dead)
		enemy.landed(result, late, past)
		if enemy.vitals.is_open():
			swordsman.close()


# The same way, as whoever they're facing sees it.
func _mirrored(way: Vector2) -> Vector2:
	return Vector2(-way.x, way.y)


func _meeting_point(attacker: Node3D, defender: Node3D, result: String) -> Vector3:
	if result == "hit" or result == "glance":
		return defender.global_position + Vector3.UP * 1.25 + (attacker.global_position - defender.global_position).normalized() * 0.25
	# Where the blades cross: partway up the defender's.
	return defender.arm.global_transform * Vector3(-0.02, 0.45, 0.0)


func _on_enemy_died() -> void:
	_over = true
	_say("")
	await get_tree().create_timer(3.2).timeout
	if _over:
		restart()


func _on_player_died() -> void:
	_over = true
	arm.go_down()
	enemy.brain.reset()
	enemy.brain.peaceful = true
	_say("You fell.   R: again")
	await get_tree().create_timer(2.6).timeout
	enemy.brain.peaceful = false
	if _over:
		restart()


func _say(text: String) -> void:
	hint.text = text
