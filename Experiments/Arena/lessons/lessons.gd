extends Node3D

## The clearing where the sword is learned: someone to try each thing on, with
## what it is written over them, and struck through once it's been done.

const Lesson = preload("res://Experiments/Arena/lessons/lesson.gd")
const Strike = preload("res://Experiments/Arena/fighter/strike.gd")
const FILM = preload("res://Experiments/Arena/lessons/film.gdshader")
const STRUCK = preload("res://Core/Wash/ink_stroke.gdshader")

@export var arena: Node3D
@export var player: CharacterBody3D
@export var sword: Node3D
@export var edge: Node
@export var lessons: Array[Lesson] = []
@export var font: Font
@export var ink := Color(0.02, 0.02, 0.025)
## How near someone has to be to be looked at, or swung at.
@export var near := 3.5
@export var between_blows := 1.6
@export var back_after := 2.6

var on := false

var _foes := {}
var _signs := {}
var _done := {}
var _wait := {}
var _hurt := {}
var _lock_range := 9.0
var _time := 0.0
# Since the next one along was asked for, which the nearest gives way to.
var _since_next := 10.0


func _ready():
	edge.met.connect(_on_cut)
	sword.flicked.connect(func(_way): _learned(Lesson.Teaches.FLICK))
	player.next_rival.connect(func(): _since_next = 0.0)
	player.side_rival.connect(func(_way): _since_next = 0.0)
	arena.judged.connect(_on_judged)
	arena.met_perfectly.connect(func(): _learned(Lesson.Teaches.PARRY))


func set_out() -> void:
	on = true
	_lock_range = player.lock_range
	player.lock_range = near + 0.3
	for lesson in lessons:
		_signs[lesson] = _sign(lesson)
		if lesson.kind:
			var foe: Node3D = arena._bring_in(lesson.kind, lesson.place)
			_foes[lesson] = foe
			_stand(lesson)


func put_away() -> void:
	if not on:
		return
	on = false
	player.lock_range = _lock_range
	for lesson: Lesson in _signs:
		_signs[lesson].queue_free()
	for what: Dictionary in [_foes, _signs, _done, _wait, _hurt]:
		what.clear()


func _stand(lesson: Lesson) -> void:
	var foe: Node3D = _foes[lesson]
	foe.reset_at(lesson.place)
	foe.brain.wait(false)
	foe.arm.reset()
	_wait[lesson] = 0.8
	_hurt[lesson] = 0.0


func _physics_process(delta: float):
	if not on:
		return
	# Nobody's killed by a lesson.
	player.vitals.mend(delta * 40.0)
	player.leg_hurt = false
	sword.wind_scale = 1.0
	var closest: Node3D
	var least := 100.0
	for lesson: Lesson in _foes:
		var foe: Node3D = _foes[lesson]
		var body: Node3D = foe.body
		if foe.vitals.dead or not (body.has_arm(0) and body.has_arm(1) and body.has_leg(0) and body.has_leg(1) and body.has_head()):
			_hurt[lesson] += delta
			if _hurt[lesson] > back_after:
				_stand(lesson)
			continue
		var away := player.global_position.distance_to(foe.global_position)
		if away < least:
			least = away
			closest = foe
		_keep_still(lesson, foe, delta, away)
	if closest and not (player.is_locked() and _since_next < 4.0):
		player.rival = closest
	_since_next += delta
	if player.is_locked():
		_learned(Lesson.Teaches.LOCK)


func _keep_still(lesson: Lesson, foe: Node3D, delta: float, away: float) -> void:
	var brain: Node = foe.brain
	if brain.state in [brain.CIRCLE, brain.CLOSE, brain.GIVE_GROUND, brain.FIGHT]:
		brain.wait(false)
		if foe.arm.phase == foe.arm.Phase.DOWN:
			foe.arm.reset()
	if foe.arm.phase != foe.arm.Phase.READY:
		return
	var home := lesson.place - foe.global_position
	home.y = 0.0
	foe.global_position += home.limit_length(delta * 1.4)
	if not lesson.throws or away > near or foe.is_still(0.0):
		return
	_wait[lesson] -= delta
	if _wait[lesson] > 0.0:
		return
	_wait[lesson] = between_blows
	var blow := Strike.new()
	blow.direction = [Vector2(-0.75, -0.66), Vector2(0.75, -0.66), Vector2(0, -1)].pick_random()
	blow.windup = 0.95
	blow.release = 0.24
	blow.recover = 0.6
	blow.lunge = 3.2
	foe.arm.begin(blow)


# ---- what's been done

func _on_cut(strike: Strike, _foe: Node3D, _part: Node3D, _at: Vector3, region: RefCounted, _travel: Vector3) -> void:
	if region != null and not strike.path.is_empty():
		_learned(Lesson.Teaches.DRAW)
	elif region != null:
		_learned(Lesson.Teaches.CUT)


func _on_judged(attacker: Node3D, result: String) -> void:
	if attacker == player:
		return
	match result:
		"block", "parry":
			_learned(Lesson.Teaches.GUARD)
		"evade":
			_learned(Lesson.Teaches.STEP)


func _learned(what: Lesson.Teaches) -> void:
	if not on or _done.has(what):
		return
	_done[what] = true
	for lesson in lessons:
		if lesson.teaches == what:
			_strike_out(_signs[lesson], lesson)


# ---- what's written

func _sign(lesson: Lesson) -> Node3D:
	var sign_post := Node3D.new()
	add_child(sign_post)
	sign_post.position = lesson.place
	var film := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 0.844)
	film.mesh = quad
	var shown := ShaderMaterial.new()
	shown.shader = FILM
	shown.render_priority = 118
	shown.set_shader_parameter("film", lesson.film)
	shown.set_shader_parameter("grid", Vector2(lesson.across, lesson.down))
	film.material_override = shown
	film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	film.position.y = 3.08
	_fade_far(film)
	film.name = "Film"
	sign_post.add_child(film)
	_write(sign_post, lesson.title, 2.48, 92)
	_write(sign_post, lesson.says, 2.16, 50)
	return sign_post


func _write(on_what: Node3D, text: String, height: float, big: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = big
	label.pixel_size = 0.0035
	label.modulate = ink
	label.outline_modulate = Color(0.93, 0.92, 0.89, 0.92)
	label.outline_size = 16
	label.render_priority = 122
	label.outline_render_priority = 121
	label.double_sided = true
	label.line_spacing = -8.0
	label.position.y = height
	_fade_far(label)
	on_what.add_child(label)


# One at a time is enough to read.
func _fade_far(what: GeometryInstance3D) -> void:
	what.visibility_range_end = 6.5
	what.visibility_range_end_margin = 1.0
	what.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _strike_out(sign_post: Node3D, lesson: Lesson) -> void:
	var wide := font.get_string_size(lesson.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 92).x * 0.0035 + 0.9
	var quad := QuadMesh.new()
	quad.size = Vector2(wide, 0.11)
	var line := MeshInstance3D.new()
	line.mesh = quad
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var paint := ShaderMaterial.new()
	paint.shader = STRUCK
	paint.render_priority = 125
	paint.set_shader_parameter("ink_color", Color(0.62, 0.01, 0.015))
	paint.set_shader_parameter("tint_amount", 0.0)
	paint.set_shader_parameter("total", 1.0)
	paint.set_shader_parameter("seed", randf() * 40.0)
	paint.set_shader_parameter("dryness", 0.5)
	line.material_override = paint
	line.position = Vector3(0, 2.48, 0.02)
	sign_post.add_child(line)
	line.scale.x = 0.01
	var pull := create_tween()
	pull.tween_property(line, "scale:x", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _process(delta: float):
	if not on:
		return
	_time += delta
	for lesson: Lesson in _signs:
		var sign_post: Node3D = _signs[lesson]
		var to := player.global_position - sign_post.global_position
		if lesson.kind and is_instance_valid(_foes.get(lesson)):
			sign_post.global_position = sign_post.global_position.lerp(Vector3(_foes[lesson].global_position.x, 0.0, _foes[lesson].global_position.z), 1.0 - exp(-4.0 * delta))
		sign_post.rotation.y = atan2(to.x, to.z)
		(sign_post.get_node("Film") as MeshInstance3D).material_override.set_shader_parameter("now", _time)
