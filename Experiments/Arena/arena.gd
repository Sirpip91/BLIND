extends Node3D

## The one place everything is fought. Puts an encounter's foes in the
## clearing, judges every blow, and is where the rules meet the feel.

const Exchange = preload("res://Experiments/Arena/fighter/exchange.gd")
const Strike = preload("res://Experiments/Arena/fighter/strike.gd")
const Part = preload("res://Experiments/Arena/foe/part.gd")
const Piece = preload("res://Experiments/Arena/cutting/piece.gd")
const Encounter = preload("res://Experiments/Arena/encounter.gd")
const Aspect = preload("res://Experiments/Arena/player/aspect.gd")
const Blood = preload("res://Experiments/Arena/feel/blood.gd")
const Menu = preload("res://Experiments/Arena/menu/main_menu.gd")
const FOE = preload("res://Experiments/Arena/foe/foe.tscn")

## The last few exchanges, for anyone watching.
signal judged(attacker: Node3D, result: String)
## A blow was turned on the very moment it came.
signal met_perfectly

@export var player: CharacterBody3D
@export var swordsman: Node
@export var sword: Node3D
@export var edge: Node
@export var director: Node
@export var feel: Node
@export var passage: Node
@export var grounds: Node3D
@export var daylight: Node
@export var shrine: Node3D
@export var sense: Control
@export var picker: Node
@export var blade_colors: Node
@export var main_menu: CanvasLayer
@export var hud: CanvasLayer
@export var lessons: Node3D
## Who stands there behind the menu.
@export var front_shows: Encounter
@export var front_place := Vector3(0.75, 0.0, -1.9)
@export var hint: Label
@export var menu: Label
@export var veil: ColorRect
## What the number keys start.
@export var encounters: Array[Encounter] = []
## Seconds from the last of them falling to the way on opening.
@export var gate_after := 1.6
## Where they wait, on the far side of this point from the gate.
@export var foes_wait := Vector3(0, 0, -1.0)
## How much shorter than its reach a blow only grazes from.
@export var graze := 0.2
## How early in the parry window a blow has to land to be met perfectly: the
## later the guard went up, the nearer to nothing this is.
@export_range(0.0, 1.0, 0.05) var perfect_within := 0.55

## How early in a step a blow has to be slipped to be slipped perfectly, and
## how long that leaves someone standing.
@export var slip_within := 0.15
## Locked on, with a guard up: turns to a blow from someone else if it lands
## within this, and this much before one from whoever's being looked at.
@export var turns_within := 0.6
@export var turns_before := 0.12
@export var stands_for := 1.1

const HELP := "Left: click to cut, or hold and draw one     Right: guard     Wheel up: thrust     Space or Shift: step\nQ: lock     Wheel down: flick the blood off     Middle: next foe     R: again     H: list of fights     N: day and night     C or Esc: sword colour     1-9, 0: start one     Shift and 1-6: a night one
Testing   ]: skip to the next     [: back one     K: kill everyone and open the gate     G: next colour     Shift and G: none     V: how they're painted"

var foes: Array[Node3D] = []
## What's in the sword, one for every mask cut.
var aspects: Array[Aspect] = []

var _over := false
var _round := 0
var _now := 0


func _ready():
	edge.reached.connect(_meet_guard)
	edge.met.connect(_meet_body)
	edge.foes = foes
	director.foes = foes
	director.player = player
	passage.between.connect(_go_on)
	passage.stepped_out.connect(_wake_them)
	sword.released.connect(feel.swing)
	player.slipped.connect(feel.slipped)
	player.next_rival.connect(_look_to_next)
	player.side_rival.connect(_look_to_side)
	player.vitals.died.connect(_on_player_died)
	sense.foes = foes
	shrine.taken.connect(_take)
	blade_colors.restyled.connect(func(text): _tell(text, 2.0))
	shrine.told.connect(func(text): hint.text = text)
	main_menu.begin.connect(_start_out)
	main_menu.front_wanted.connect(_to_front)
	main_menu.gore_changed.connect(func(): feel.spill(encounters[_now].tutorial or not Blood.gore))
	var listed := PackedStringArray()
	var many := 0
	for fight in encounters:
		if fight.shrine and not fight.night:
			listed.append("0   %s\n" % fight.label)
			many = 0
		elif not fight.shrine and not fight.tutorial:
			many += 1
			listed.append(("Shift %d   %s" if fight.night else "%d   %s") % [many, fight.label])
	# Only there when it's asked for, with H.
	menu.text = "\n".join(listed) + "\n\n" + HELP.replace("     ", "\n")
	menu.visible = false
	# The player's camera isn't ready to take children yet.
	_begin.call_deferred()


func _begin() -> void:
	sword.reparent(player.camera, false)
	sword.reset_physics_interpolation()
	if main_menu.visible or foes.is_empty():
		_show_front()


# ---- before any of it

func _show_front() -> void:
	passage.close()
	_now = 0
	_clear_away()
	daylight.turn_to(0)
	shrine.put_away()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.reset_at(Vector3(-0.2, 0.0, 4.0), 0.0)
	sword.visible = false
	hud.visible = false
	picker.kept_away = true
	director.reset(1, 1.0, 1.4)
	for kind in front_shows.foes:
		_bring_in(kind, front_place)
	foes[0].brain.wait(false)
	player.rival = null
	main_menu.open()
	veil.modulate.a = 0.0


func _to_front() -> void:
	main_menu.close()
	await _shut_eyes(0.4)
	_show_front()
	_open_eyes(0.8)


func _start_out(with_lessons: bool) -> void:
	await _shut_eyes(0.5)
	start(_find(func(fight): return fight.tutorial, 0) if with_lessons else _after_lessons())
	veil.modulate.a = 1.0
	_open_eyes(0.9)


func _after_lessons() -> int:
	return _find(func(fight): return fight.tutorial, 0) + 1


# The veil's part of what's hidden behind the menu, so it has a layer to
# itself.
func _shut_eyes(seconds: float) -> void:
	var fade := create_tween()
	fade.tween_property(veil, "modulate:a", 1.0, seconds)
	await fade.finished


func _open_eyes(seconds: float) -> void:
	create_tween().tween_property(veil, "modulate:a", 0.0, seconds)


func _unhandled_key_input(event):
	if not Menu.developer or not event.pressed or event.echo or main_menu.at_front:
		return
	var key: int = event.physical_keycode
	if key == KEY_R:
		start(_now)
	elif key == KEY_H:
		menu.visible = not menu.visible
	elif key == KEY_BRACKETRIGHT:
		start(_after(_now))
	elif key == KEY_BRACKETLEFT:
		start(maxi(_now - 1, 0))
	elif key == KEY_G:
		if event.shift_pressed:
			_give(null)
		else:
			_give_next()
	elif key == KEY_K:
		_clear_out()
	elif key == KEY_0:
		start(_find(func(fight): return fight.shrine, 0))
	elif key >= KEY_1 and key <= KEY_9:
		var night: bool = event.shift_pressed
		var at := _find(func(fight): return fight.night == night and not fight.shrine and not fight.tutorial, key - KEY_1)
		if at >= 0:
			start(at)


# For trying things out: everyone dead, and the way on open.
func _clear_out() -> void:
	for foe in _standing():
		foe.vitals.holds_on = false
		foe.vitals.kill()
	passage.clear()


func _find(is_one: Callable, after: int) -> int:
	for i in encounters.size():
		if is_one.call(encounters[i]):
			if after == 0:
				return i
			after -= 1
	return -1


## Straight to the gate of one of them.
func start(which: int) -> void:
	if main_menu.visible or main_menu.at_front:
		main_menu.close()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.camera.make_current()
	sword.visible = true
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	passage.begin()
	player.vitals.max_health = encounters[which].player_health
	swordsman.reset()
	_set_out(which)


# Through the gate and into the next.
func _go_on() -> void:
	grounds.grow(randi(), true)
	player.vitals.max_health = encounters[_after(_now)].player_health
	player.vitals.reset()
	player.leg_hurt = false
	_set_out(_after(_now))


# From the last of them it's night again.
func _after(which: int) -> int:
	if which + 1 < encounters.size():
		return which + 1 if not encounters[which + 1].tutorial else which + 2
	return _find(func(fight): return fight.night, 0)


func _set_out(which: int) -> void:
	_now = which
	veil.modulate.a = 0.0
	_clear_away()
	var fight := encounters[which]
	feel.spill(fight.tutorial or not Blood.gore)
	director.reset(fight.at_once, fight.spacing, fight.in_view)
	player.locked = fight.locked
	player.movement_locked = false
	daylight.turn_to(1 if fight.night else 0)
	if fight.shrine:
		shrine.set_out()
	else:
		shrine.put_away()
	picker.kept_away = fight.shrine
	player.rival = null
	if fight.tutorial:
		lessons.set_out()
	if fight.foes.is_empty():
		return
	for i in fight.foes.size():
		_bring_in(fight.foes[i], _place(i, fight.foes.size()))
	_look_to_nearest()


func _clear_away() -> void:
	_round += 1
	_over = false
	Engine.time_scale = 1.0
	get_tree().call_group(Piece.GROUP, "queue_free")
	feel.blood.clear()
	lessons.put_away()
	for foe in foes:
		foe.leave()
	foes.clear()


func _wake_them() -> void:
	if encounters[_now].tutorial:
		_tell("The far gate is open, whenever you're ready", 5.0)
		passage.clear()
		return
	if encounters[_now].shrine:
		# Nothing left to be given.
		if aspects.size() >= shrine.aspects.size():
			passage.clear()
		return
	_tell(encounters[_now].label, 2.5)
	for foe in foes:
		foe.brain.wake(randf_range(0.2, 0.7))


# In an arc facing the gate.
func _place(i: int, many: int) -> Vector3:
	var angle := 0.0 if many < 2 else lerpf(-1.0, 1.0, float(i) / (many - 1)) * minf(0.25 * many, 1.0)
	return foes_wait + Vector3(sin(angle), 0.0, -cos(angle) + 1.0) * 3.6


func _bring_in(kind: Resource, at: Vector3) -> Node3D:
	var foe := FOE.instantiate() as Node3D
	kind.dress(foe)
	foe.rival = player
	foe.director = director
	add_child(foe)
	foes.append(foe)
	foe.begin()
	foe.arm.struck.connect(_judge_theirs.bind(foe))
	foe.sprang_back.connect(swordsman.close)
	foe.reader.stepped.connect(func(_way): feel.stepped(foe.global_position))
	foe.vitals.died.connect(_on_foe_died)
	foe.changed_into.connect(func(which):
		player.push(-foe.facing() * -4.5)
		feel.changed(foe.global_position, which.lacquer if which.changes == 1 else Color(0.5, 0.15, 0.75)))
	foe.vanished.connect(func(): feel.stepped(foe.global_position))
	foe.gathering.connect(_on_gathering.bind(foe))
	foe.risen.connect(_on_risen.bind(foe))
	foe.reset_at(at)
	foe.brain.wait(foes.size() % 2 == 1)
	return foe


# ---- who's being looked at

func _standing() -> Array[Node3D]:
	return foes.filter(func(foe): return not foe.vitals.dead and not foe.image)


func _look_to_nearest() -> void:
	var standing := _standing()
	if standing.is_empty():
		return
	var wanted := func(foe: Node3D) -> float:
		var coming := 1.5 if foe.arm.time_to_land() < 1.2 and not foe.brain.is_pretending() else 0.0
		return _away(foe) + absf(director.bearing(foe)) * 1.2 - coming
	standing.sort_custom(func(a, b): return wanted.call(a) < wanted.call(b))
	player.look_to(standing[0])


## The next one round to the right.
func _look_to_next() -> void:
	if not is_instance_valid(player.rival):
		return
	var here := _bearing(player.rival)
	var best: Node3D
	var least := TAU
	for foe in _standing():
		if foe == player.rival:
			continue
		var off := wrapf(here - _bearing(foe), 0.0, TAU)
		if off < least:
			least = off
			best = foe
	if best:
		player.look_to(best)


## Whoever's nearest along on that side of who's being looked at.
func _look_to_side(way: float) -> void:
	if not is_instance_valid(player.rival):
		return
	var here: float = director.bearing(player.rival)
	var best: Node3D
	var least := 100.0
	for foe in _standing():
		if foe == player.rival or foe.is_unseen() or _away(foe) > player.lock_range:
			continue
		var off := wrapf(director.bearing(foe) - here, -PI, PI) * way
		if off <= 0.02:
			continue
		# One right beside is nearer along than one further off behind him.
		var score := off + 0.05 * _away(foe)
		if score < least:
			least = score
			best = foe
	if best:
		player.look_to(best)


# A guard goes up against whoever's blow is coming.
func _turn_to_blow() -> void:
	if not player.crowd or not player.is_locked() or sword.phase != sword.Phase.GUARD:
		return
	var soonest: Node3D
	var least := turns_within
	for foe in _standing():
		var left: float = foe.arm.time_to_land()
		if left < least and not foe.brain.is_pretending() and not foe.is_unseen() and _away(foe) < foe.arm.strike.reach + 0.5:
			least = left
			soonest = foe
	if soonest and soonest != player.rival and player.rival.arm.time_to_land() > least + turns_before:
		player.look_to(soonest)


func _away(foe: Node3D) -> float:
	return player.global_position.distance_to(foe.global_position)


func _bearing(foe: Node3D) -> float:
	var to := foe.global_position - player.global_position
	return atan2(-to.x, -to.z)


# ---- blows

func _judge_theirs(strike: Strike, foe: Node3D) -> void:
	if _over or foe.vitals.dead or foe.image:
		return
	var result: String = Exchange.resolve(foe, player, strike)
	var opening: bool = foe.brain.is_last_strike()
	judged.emit(foe, result)
	if result == "miss":
		return
	if result == "evade":
		if _has(Aspect.Power.STILL) and player.dodging_for() <= slip_within and not foe.brain.is_changing():
			_leave_standing(foe)
			return
		if opening:
			player.slip()
			swordsman.open(swordsman.slip_time)
		return
	# How late in the window the guard came up: 0 is on the very moment.
	var late: float = clampf(sword.guard_age() / maxf(sword.parry_window, 0.01), 0.0, 1.0)
	var perfect: bool = result == "parry" and late < perfect_within
	var at := _meeting_point(sword)
	var away := player.global_position - foe.global_position
	away.y = 0.0
	swordsman.met(result, strike)
	player.push(away.normalized() * (0.0 if perfect else {"parry": 0.8, "block": 3.2, "hit": 4.2}.get(result, 0.0)))
	var open: float = foe.landed(result, late, strike.carries_to(), perfect)
	match result:
		"parry":
			feel.parry(at, strike, perfect, open > 0.0)
			if perfect:
				blade_colors.surge()
				met_perfectly.emit()
			if perfect and _has(Aspect.Power.MEND):
				_mend()
		"block":
			feel.block(at, strike, false)
		"hit":
			var grazed: bool = away.length() > strike.reach - graze
			swordsman.wounded(strike)
			player.vitals.wound(0.5 if grazed else 1.0)
			feel.hurt(strike, grazed, player.vitals.dead)
	if open > 0.0:
		swordsman.open(open)


# About to go into them from this side: is that a side they're covering?
func _meet_guard(strike: Strike, foe: Node3D, way: Vector2) -> void:
	if _over or foe.vitals.dead or not foe.stops(way):
		return
	if strike.sunder:
		# Straight through it.
		foe.arm.stagger(0.7, Vector2(-way.x, way.y))
		foe.brain.reel(0.7)
		feel.block(_meeting_point(foe.arm), strike, true)
		return
	if way != Vector2.ZERO:
		strike.direction = way
	var parried: bool = foe.arm.is_fresh()
	edge.spend(strike)
	judged.emit(player, "parry" if parried else "block")
	swordsman.stopped("parry" if parried else "block")
	foe.stopped("parry" if parried else "block", strike, player.global_position)
	feel.block(_meeting_point(foe.arm), strike, true)
	if foe.one_handed():
		swordsman.open(0.5)


func _meet_body(strike: Strike, foe: Node3D, part: Part, at: Vector3, region: RefCounted, travel: Vector3) -> void:
	if player.vitals.dead:
		return
	var result: String = foe.cut(strike, part, at, region, travel, player.global_position)
	if result == "none":
		return
	judged.emit(player, result)
	if result == "glance":
		edge.spend(strike)
		feel.block(at, strike, true)
		return
	if strike.force <= 0.0:
		edge.spend(strike)
	foe.hold(true)
	swordsman.bit(result == "scratch")
	feel.cut(at, strike, result, _standing().is_empty(), travel)
	if result == "kill":
		blade_colors.surge()


func _physics_process(delta: float):
	player.crowd = _standing().size() > 1
	_turn_to_blow()
	for foe in foes:
		if not foe.is_still(delta) and sword.phase != sword.Phase.RELEASE:
			foe.hold(false)


# ---- one that won't stay dead

func _on_gathering(foe: Node3D) -> void:
	daylight.turn_to(1)
	feel.gather(foe.body.chest_point() if foe.body.has_head() else foe.global_position, foe.GATHERS)


func _on_risen(foe: Node3D) -> void:
	get_tree().call_group(Piece.GROUP, "queue_free")
	player.vitals.mend(1.0)
	for i in 2:
		var image := _bring_in(foe.kind, foe.global_position)
		image.become_image()
		foe.haunt.images.append(image)
	var ahead: Vector3 = player.facing()
	ahead.y = 0.0
	var flat := Vector2(player.global_position.x, player.global_position.z) + Vector2(ahead.x, ahead.z).normalized() * 3.6
	flat = flat.limit_length(8.5)
	foe.appear_at(Vector3(flat.x, 0.0, flat.y))
	player.look_to(foe)
	feel.changed(foe.global_position, Color(0.5, 0.15, 0.75))


# ---- what a mask gave

func _has(power: Aspect.Power) -> bool:
	return _with(power) != null


func _with(power: Aspect.Power) -> Aspect:
	for each in aspects:
		if each.power == power:
			return each
	return null


func _take(what: Aspect, at: Vector3) -> void:
	_give(what)
	feel.mask_cut(at, what.color)
	await get_tree().create_timer(gate_after).timeout
	if encounters[_now].shrine:
		passage.clear()


func _give(what: Aspect) -> void:
	if what == null:
		aspects.clear()
	elif not aspects.has(what):
		aspects.append(what)
	swordsman.sunders = _has(Aspect.Power.SUNDER)
	sense.on = _has(Aspect.Power.SENSE)
	shrine.given = aspects
	if what:
		picker._wear(what.color)
	else:
		picker._plain()
	blade_colors.wear(aspects)


# For trying things out: the next one it hasn't got.
func _give_next() -> void:
	for each in shrine.aspects:
		if not aspects.has(each):
			_give(each)
			_tell(each.label, 1.5)
			return


func _mend() -> void:
	player.vitals.mend(0.5)
	player.leg_hurt = false
	sword.wind_scale = 1.0
	feel.mended(_with(Aspect.Power.MEND).color)


# Its blow has gone by, and it hasn't noticed yet.
func _leave_standing(foe: Node3D) -> void:
	player.slip()
	var color := _with(Aspect.Power.STILL).color
	foe.brush.tint = color
	foe.brush.blade_tint = 1.0
	foe.still_for(stands_for)
	player.rival = foe
	swordsman.open(stands_for)
	feel.stilled(foe.global_position, color)


func _meeting_point(guarding: Node3D) -> Vector3:
	# Where the blades cross: partway up the defender's.
	return guarding.global_transform * Vector3(-0.02, 0.45, 0.0)


# ---- endings

func _on_foe_died() -> void:
	if encounters[_now].tutorial or main_menu.at_front:
		return
	for foe in foes:
		if foe.image and _standing().is_empty():
			foe.vanish()
	if is_instance_valid(player.rival) and player.rival.vitals.dead:
		_look_to_nearest()
	if not _standing().is_empty():
		director.lost_one()
		return
	swordsman.close()
	var this_round := _round
	await get_tree().create_timer(gate_after).timeout
	if this_round == _round:
		passage.clear()


func _on_player_died() -> void:
	_over = true
	sword.go_down()
	player.fallen = true
	for foe in foes:
		foe.brain.let_up()
	_end(2.6)


# Their eyes close, and open again at the gate.
func _end(after: float) -> void:
	var this_round := _round
	await get_tree().create_timer(after).timeout
	if this_round != _round:
		return
	var fade := create_tween()
	fade.tween_property(veil, "modulate:a", 1.0, 0.5)
	await fade.finished
	if this_round != _round:
		return
	start(_now)
	veil.modulate.a = 1.0
	create_tween().tween_property(veil, "modulate:a", 0.0, 0.8)


func _tell(text: String, seconds: float) -> void:
	hint.text = text
	await get_tree().create_timer(seconds).timeout
	if hint.text == text:
		hint.text = ""
