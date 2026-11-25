extends StaticBody3D

## Training dummy: flinches and flashes when struck. With `attacks` on it
## also turns to face the player and swings on a rhythm, its arm glowing as
## it winds up, so guards and parries have something to meet.

const Fx = preload("res://Core/Combat/fx.gd")
const Impact = preload("res://Core/Combat/impact.gd")
# A variable, because reads through a const are baked in when the script
# loads and would never see the tuning panel change them.
var look: Resource = preload("res://Core/Combat/combat_look.tres")
const InkReal = preload("res://Core/Ink/ink_real.gdshader")
const Sheet = preload("res://Assets/HatchCube/hatch_swatches.png")

# Swatches off the hand-drawn sheet, as (x, y, w, h) in its UV space.
const SCRIBBLE := Vector4(0.3906, 0.7227, 0.2148, 0.2148)
const LIGHT_DIAGONAL := Vector4(0.3906, 0.3906, 0.2148, 0.2148)
const VERTICAL := Vector4(0.0537, 0.3906, 0.2148, 0.2148)
const WRAP := Vector4(0.0537, 0.7227, 0.2148, 0.2148)

@export var attacks := false
@export var player: Node3D
## Asked how each strike is met:
## receive_strike(from, blockable) -> "parry", "block" or "hit".
@export var guard: Node
@export var reach := 2.6
@export var tempo := 2.2
@export var windup_time := 0.55
## Swings even when the player is out of reach, for practising the timing.
@export var always_attack := false
## Strikes in a row before it rests.
@export var combo := 1
## Wind-up of each follow-up strike, as a fraction of the first.
@export var followup_windup := 0.7
## Metres a full-strength hit shoves it back before it springs home.
@export var knockback := 0.6
## Swings a heavy club instead of a stick.
@export var club := false
## How hard its hits land on the player.
@export var hit_force := 1.0
@export var max_health := 100.0
## Seconds it stays down after being beaten before standing back up.
@export var respawn_time := 3.0

@export_group("Parry training")
## Off: a plain guard isn't enough, only a parry stops the strike.
@export var blockable := true
## On: a parry staggers it and ends the combo. Off: it keeps swinging.
@export var parry_breaks_combo := true
## Parrying every strike of a combo stuns it.
@export var stun_on_perfect := false
## Seconds it stays stunned, open to an execution.
@export var stun_time := 2.0
## A counter over its head: parries landed out of the combo.
@export var show_count := false

@export_group("Testing")
## Permanently stunned and open to an execution, for trying executions fast.
@export var always_open := false
## Share of max health an execution takes; 0 or less kills outright.
@export var execution_damage := 0.0

@export_group("Red sequences")
## Chance each attack is a red sequence instead: unblockable strikes that
## carry on whether parried or not. Parry every one, in order, to stun it.
@export var red_chance := 0.0
@export var red_combo := 5

@export_group("Posture")
## Parries and blocks wear it down; full, it breaks and is open to an execution.
@export var max_posture := 100.0
@export var posture_per_parry := 40.0
@export var posture_per_block := 8.0
## Drained per second once it has gone 4 seconds without being pressured.
@export var posture_recovery := 8.0

@export_group("Duelling")
## Sides it strikes from, picked at random each swing: "high", "left",
## "right", "low" (seen from the player) or "front" for a thrust. Only a
## guard in the matching stance stops it. Empty: plain overhead strikes.
@export var directions: PackedStringArray = []
## Turns the player's swings aside when it isn't busy attacking.
@export var parries_player := false
@export var parry_chance := 0.5

var _pivot: Node3D
var _arm: Node3D
# Turns the whole swing around the dummy's facing, so one overhead motion can
# come from any side.
var _swing: Node3D
var _arm_base := Vector3.ZERO
var _dir := ""
var _red := false
var _total := 1
var _arm_mesh: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []
var _flash: StandardMaterial3D
var _tell: StandardMaterial3D
var _cooldown := 1.5
var _busy := false
var _wobble: Tween
var _knock: Tween
var _home: Vector3
var _parries := 0
var _stunned := 0.0
var _stars: Node3D
var _label: Label3D
var _health: float
var _dead := false
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _ghost: Tween
var _fall: Tween
var _posture := 0.0
var _since_pressured := 0.0
var _posture_fill: MeshInstance3D

const BAR_WIDTH := 0.7

const ARM_REST := -2.3
const ARM_RAISED := 0.45
const ARM_STRUCK := -1.85


func _ready():
	_home = position
	_health = max_health
	_build_bar()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.9
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)

	_pivot = Node3D.new()
	add_child(_pivot)
	var post := CylinderMesh.new()
	post.top_radius = 0.05
	post.bottom_radius = 0.07
	post.height = 0.8
	_part(post, Vector3(0, 0.4, 0), _pivot, VERTICAL)
	var body := CapsuleMesh.new()
	body.radius = 0.27
	body.height = 0.95
	_part(body, Vector3(0, 1.2, 0), _pivot, SCRIBBLE)
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	_part(head, Vector3(0, 1.82, 0), _pivot, LIGHT_DIAGONAL)

	if attacks:
		_swing = Node3D.new()
		_swing.position = Vector3(0, 1.45, 0)
		_pivot.add_child(_swing)
		_arm = Node3D.new()
		# Directional strikes come from the middle of the body, so every side
		# reads the same; plain ones from the right shoulder.
		_arm_base = Vector3(0, 0, -0.45) if not directions.is_empty() else Vector3(0.34, 0, 0)
		_arm.position = _arm_base
		_arm.rotation.x = ARM_REST
		_swing.add_child(_arm)
		var stick := BoxMesh.new()
		stick.size = Vector3(0.07, 0.95, 0.07)
		_arm_mesh = _part(stick, Vector3(0, 0.47, 0), _arm, WRAP)
		_tell = Fx.glow(Color(look.tell_color, 0.0))
		_arm_mesh.material_overlay = _tell
		if club:
			stick.size = Vector3(0.09, 1.25, 0.09)
			_arm_mesh.position.y = 0.62
			# A fat head on the end, glowing with the tell like the shaft.
			var club_mesh := CylinderMesh.new()
			club_mesh.top_radius = 0.2
			club_mesh.bottom_radius = 0.14
			club_mesh.height = 0.75
			var club_head := _part(club_mesh, Vector3(0, 1.55, 0), _arm, SCRIBBLE)
			_meshes.erase(club_head)
			club_head.material_overlay = _tell

	if stun_on_perfect or attacks or always_open:
		_stars = Node3D.new()
		_stars.position = Vector3(0, 2.1, 0)
		_stars.visible = false
		_pivot.add_child(_stars)
		for i in 3:
			var star := MeshInstance3D.new()
			var dot := SphereMesh.new()
			dot.radius = 0.04
			dot.height = 0.08
			dot.material = Fx.glow(Color(look.tell_color.lerp(Color.WHITE, 0.4), 1.0))
			star.mesh = dot
			star.position = Vector3(cos(i * TAU / 3.0), 0, sin(i * TAU / 3.0)) * 0.26
			_stars.add_child(star)

	if show_count or attacks or always_open:
		_label = Label3D.new()
		_label.position = Vector3(0, 2.6, 0)
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		_label.font_size = 40
		_label.outline_size = 10
		_label.outline_modulate = Color.BLACK
		_label.text = "PARRY 0/%d" % combo if show_count else ""
		add_child(_label)

	_flash = Fx.glow(Color(1, 1, 1, 0))
	if always_open:
		_open_forever.call_deferred()


func _part(mesh: PrimitiveMesh, at: Vector3, parent: Node3D, swatch: Vector4) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	# Painted through its own UVs, so the strokes stay put as it rocks and falls.
	var paint := ShaderMaterial.new()
	paint.shader = InkReal
	paint.set_shader_parameter("swatches", Sheet)
	paint.set_shader_parameter("painting", Sheet)
	paint.set_shader_parameter("use_painting", true)
	paint.set_shader_parameter("painting_rect", swatch)
	part.material_override = paint
	part.set_meta("keep_material", true)
	parent.add_child(part)
	_meshes.append(part)
	return part


func _build_bar() -> void:
	_bar = Node3D.new()
	_bar.position = Vector3(0, 2.3, 0)
	add_child(_bar)
	_bar_quad(Vector2(BAR_WIDTH + 0.04, 0.09), Fx.ink(Color(0, 0, 0, 0.85)), 125, -0.002)
	_ghost_material = Fx.ink(Color.WHITE)
	_bar_ghost = _bar_quad(Vector2(BAR_WIDTH, 0.05), _ghost_material, 126, 0.0)
	_bar_fill = _bar_quad(Vector2(BAR_WIDTH, 0.05), Fx.ink(Color(0.95, 0.94, 0.91)), 127, 0.002)
	if attacks:
		# Posture fills from the middle outward, under the health bar.
		_posture_fill = _bar_quad(Vector2(BAR_WIDTH, 0.03), Fx.ink(look.tell_color), 127, 0.002)
		_posture_fill.position.y = -0.075
		_posture_fill.scale.x = 0.001


func _bar_quad(size: Vector2, material: StandardMaterial3D, priority: int, z: float) -> MeshInstance3D:
	material.render_priority = priority
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position.z = z
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.add_child(mesh)
	return mesh


## Left-anchored fill: 0 empty, 1 full.
func _set_bar(bar: MeshInstance3D, fraction: float) -> void:
	bar.scale.x = maxf(fraction, 0.001)
	bar.position.x = -BAR_WIDTH * 0.5 * (1.0 - fraction)


## Struck by the player. `direction` is the way the blow travels. Returns
## true if this blow was the one that beat it, so the attacker can make the
## moment land harder.
func take_hit(at: Vector3, direction: Vector3, color: Color, force := 1.0, damage := 0.0) -> bool:
	if _dead:
		return false
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	var axis := Vector3.UP.cross(flat).normalized() if flat.length() > 0.1 else Vector3.RIGHT
	var killed := false
	if damage > 0.0:
		var before := _health / max_health
		# Stunned from a perfect parry run: wide open, hits land double.
		_health -= damage * (2.0 if _stunned > 0.0 else 1.0)
		killed = _health <= 0.0
		var after := maxf(_health, 0.0) / max_health
		_set_bar(_bar_fill, after)
		# The lost chunk flashes in the weapon's colour, then drains away.
		_ghost_material.albedo_color = color
		if _ghost:
			_ghost.kill()
		_set_bar(_bar_ghost, before)
		_ghost = create_tween()
		_ghost.tween_method(func(f: float): _set_bar(_bar_ghost, f), before, after, 0.35).set_delay(0.25)
	if _wobble:
		_wobble.kill()
	# A damped spring: knocked back hard, rocking a few times as it settles.
	_wobble = create_tween()
	_wobble.tween_method(func(t: float): _pivot.basis = Basis(axis, 0.45 * force * exp(-5.0 * t) * cos(16.0 * t)), 0.0, 1.0, 1.0)
	if _knock:
		_knock.kill()
	# Shoved back along the blow, then springs home. Runs on game time, so
	# it holds during the hit freeze and flies once time resumes.
	_knock = create_tween()
	_knock.tween_property(self, "position", _home + flat * knockback * force, 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	_knock.tween_property(self, "position", _home, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_flash.albedo_color = Color(color.lerp(Color.WHITE, 0.5), 0.85)
	for part in _meshes:
		if part != _arm_mesh:
			part.material_overlay = _flash
	var fade := create_tween()
	fade.tween_property(_flash, "albedo_color:a", 0.0, 0.18).set_delay(0.04)
	fade.tween_callback(func():
		for part in _meshes:
			if part != _arm_mesh:
				part.material_overlay = null)
	if killed:
		_die(axis)
	return killed


func _die(axis: Vector3) -> void:
	_dead = true
	_busy = true
	_stunned = 0.0
	if _stars:
		_stars.visible = false
	if _tell:
		_tell.albedo_color.a = 0.0
	_show("DOWN")
	if _wobble:
		_wobble.kill()
	_fall = create_tween()
	_fall.tween_method(func(a: float): _pivot.basis = Basis(axis, a), 0.0, 1.45, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	_fall.tween_interval(respawn_time)
	_fall.tween_method(func(a: float): _pivot.basis = Basis(axis, a), 1.45, 0.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_fall.tween_callback(_respawn)


func _respawn() -> void:
	_dead = false
	_busy = false
	_health = max_health
	_set_bar(_bar_fill, 1.0)
	_set_bar(_bar_ghost, 1.0)
	_parries = 0
	_cooldown = tempo
	if _arm:
		_arm.rotation.x = ARM_REST
	_show("PARRY 0/%d" % combo if show_count else "")
	if always_open:
		_open_forever()


func _process(delta):
	var camera := get_viewport().get_camera_3d()
	if camera:
		_bar.look_at(camera.global_position, Vector3.UP)
		# look_at points -Z at the camera; the quads face +Z.
		_bar.rotate_object_local(Vector3.UP, PI)
	if _stunned > 0.0 and _stars:
		_stars.rotate_y(delta * 6.0)
	if not attacks or not player or _dead:
		return
	if _stunned > 0.0:
		_stunned -= delta
		if _stunned <= 0.0:
			_recover_from_stun()
		return
	_since_pressured += delta
	if _posture > 0.0 and _since_pressured > 4.0:
		_posture = maxf(_posture - posture_recovery * delta, 0.0)
		_set_posture_bar()
	var to_player := player.global_position - global_position
	to_player.y = 0
	if not _busy and to_player.length() > 0.1:
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 5.0)
	_cooldown -= delta
	if not _busy and _cooldown <= 0.0 and (always_attack or to_player.length() < reach * 1.8):
		_parries = 0
		_red = randf() < red_chance
		_total = red_combo if _red else combo
		_tell.albedo_color = Color(look.red_color if _red else look.tell_color, 0.0)
		if _label:
			_label.modulate = look.red_color if _red else Color.WHITE
		_show("RED 0/%d" % _total if _red else ("PARRY 0/%d" % combo if show_count else ""))
		_attack(_total)


func _attack(strikes: int, windup := windup_time) -> void:
	_busy = true
	_dir = "" if directions.is_empty() else directions[randi() % directions.size()]
	if _dir != "":
		_show(_dir.to_upper())
	var swing := create_tween()
	if _dir == "front":
		# A thrust: the arm points straight out, draws back, then drives in.
		swing.tween_property(_swing, "rotation:z", 0.0, windup * 0.3)
		swing.parallel().tween_property(_arm, "rotation:x", -PI * 0.5, windup * 0.5).set_ease(Tween.EASE_OUT)
		swing.parallel().tween_property(_arm, "position", _arm_base + Vector3(0, 0, 0.3), windup).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		swing.parallel().tween_property(_tell, "albedo_color:a", 0.9, windup).set_ease(Tween.EASE_IN)
		swing.tween_property(_arm, "position", _arm_base + Vector3(0, 0, -0.5), 0.08).set_ease(Tween.EASE_IN)
	else:
		swing.tween_property(_swing, "rotation:z", _side_angle(_dir), windup * 0.35).set_ease(Tween.EASE_OUT)
		swing.parallel().tween_property(_arm, "rotation:x", ARM_RAISED, windup).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		swing.parallel().tween_property(_tell, "albedo_color:a", 0.9, windup).set_ease(Tween.EASE_IN)
		swing.tween_property(_arm, "rotation:x", ARM_STRUCK, 0.08).set_ease(Tween.EASE_IN)
	swing.tween_callback(_land.bind(strikes - 1))


## Which way the swing is turned so the strike comes from `side` as the
## player sees it. Facing each other, its left is the player's right.
func _side_angle(side: String) -> float:
	match side:
		"right":
			return PI * 0.5
		"left":
			return -PI * 0.5
		"low":
			return PI
	return 0.0


## The player swung at it. Returns true if it turned the blow aside.
func try_parry(at: Vector3) -> bool:
	if not parries_player or _busy or _dead or _stunned > 0.0 or not _arm or randf() > parry_chance:
		return false
	_busy = true
	_show("PARRIED YOU")
	var flash := create_tween()
	_tell.albedo_color = Color(Color.WHITE, 0.9)
	flash.tween_property(_arm, "rotation:x", -1.2, 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	flash.parallel().tween_property(_swing, "rotation:z", randf_range(-0.6, 0.6), 0.06)
	flash.tween_property(_tell, "albedo_color:a", 0.0, 0.2)
	flash.tween_property(_arm, "rotation:x", ARM_REST, 0.35).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	flash.parallel().tween_property(_swing, "rotation:z", 0.0, 0.35)
	flash.tween_callback(func():
		_tell.albedo_color = Color(look.tell_color, 0.0)
		_busy = false)
	# A quick riposte follows a successful parry.
	_cooldown = minf(_cooldown, 0.5)
	return true


func _land(strikes_left: int) -> void:
	if _dead:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0
	var facing := -global_basis.z
	var result := "miss"
	var stance: String = guard.stance() if guard and guard.has_method("stance") else ""
	if to_player.length() < reach and facing.dot(to_player.normalized()) > 0.5:
		result = guard.receive_strike(self, blockable and not _red, _dir) if guard else "hit"
	_tell.albedo_color.a = 0.0
	if result == "parry":
		_parries += 1
	if _dir != "":
		var called := {"parry": "PARRIED!", "block": "BLOCKED", "miss": "OUT OF REACH"}
		_show(called.get(result, "WRONG SIDE" if stance != "" else "HIT"))
	else:
		_show("PARRY %d/%d" % [_parries, combo] if show_count else "")
	_cooldown = tempo
	if result == "parry" or result == "block":
		_posture += posture_per_parry if result == "parry" else posture_per_block
		_since_pressured = 0.0
		_set_posture_bar()
		if _posture >= max_posture:
			# Posture broken: it reels, open to an execution.
			_stun(-to_player.normalized())
			return

	var recover := create_tween()
	if _red:
		_show("RED %d/%d" % [_parries, _total] if result == "parry" else "RED - MISSED")
	if result == "parry" and parry_breaks_combo and not _red:
		# Knocked off balance: arm thrown back, a long opening before it swings again.
		recover.tween_property(_arm, "rotation:x", ARM_RAISED + 0.6, 0.12).set_ease(Tween.EASE_OUT)
		take_hit(global_position, -to_player.normalized(), look.tell_color)
		_cooldown = tempo + 1.5
		strikes_left = 0
	elif result == "parry" or result == "block":
		recover.tween_property(_arm, "rotation:x", ARM_STRUCK + 0.5, 0.08).set_ease(Tween.EASE_OUT)

	if strikes_left > 0:
		# Red sequences vary their rhythm, so the timing has to be read, not counted.
		var next := windup_time * (randf_range(0.45, 1.1) if _red else followup_windup)
		recover.tween_callback(_attack.bind(strikes_left, next))
		return
	if (stun_on_perfect or _red) and _parries == _total:
		recover.kill()
		_stun(-to_player.normalized())
		return
	if stun_on_perfect or _red:
		_show("%d/%d - try again" % [_parries, _total])
	_red = false
	recover.tween_property(_arm, "rotation:x", ARM_REST, 0.45).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	recover.parallel().tween_property(_arm, "position", _arm_base, 0.45)
	recover.parallel().tween_property(_swing, "rotation:z", 0.0, 0.45)
	recover.tween_callback(func(): _busy = false)


## Every strike parried: it reels back and is left open for a few seconds.
func _stun(away: Vector3) -> void:
	_red = false
	if _label:
		_label.modulate = Color.WHITE
	_stunned = stun_time
	_posture = 0.0
	_set_posture_bar()
	_tell.albedo_color.a = 0.0
	_show("EXECUTE!  hold click")
	take_hit(global_position, away, look.tell_color, 1.3)
	var burst: Node3D = Impact.new()
	get_parent().add_child(burst)
	burst.play(global_position + Vector3.UP * 1.9, Vector3.UP, 1.2, look.tell_color)
	_stars.visible = true
	var slump := create_tween()
	slump.tween_property(_arm, "rotation:x", -3.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	slump.parallel().tween_property(_arm, "position", _arm_base, 0.3)
	slump.parallel().tween_property(_swing, "rotation:z", 0.0, 0.3)


func _recover_from_stun() -> void:
	_stars.visible = false
	_parries = 0
	_show("PARRY 0/%d" % combo if show_count else "")
	var stand := create_tween()
	stand.tween_property(_arm, "rotation:x", ARM_REST, 0.4).set_ease(Tween.EASE_OUT)
	stand.tween_callback(func(): _busy = false)
	_cooldown = tempo


func _show(text: String) -> void:
	if _label:
		_label.text = text


func _set_posture_bar() -> void:
	if _posture_fill:
		_posture_fill.scale.x = maxf(_posture / max_posture, 0.001)


## Stunned and wide open to an execution.
func is_open() -> bool:
	return _stunned > 0.0 and not _dead


## The finishing blow of an execution.
func execute(at: Vector3, direction: Vector3, color: Color) -> void:
	_stunned = 0.0
	var damage := max_health * (execution_damage if execution_damage > 0.0 else 10.0)
	if not take_hit(at, direction, color, 2.0, damage):
		if always_open:
			_open_forever()
		elif attacks:
			_recover_from_stun()


func _open_forever() -> void:
	_stunned = INF
	_stars.visible = true
	_show("EXECUTE  hold click")
