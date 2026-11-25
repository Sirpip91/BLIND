extends Node3D

## The held katana. Left click slashes, alternating sides so clicks chain
## into a combo. Hold right click to guard; the stance follows the way the
## mouse is moving as you raise it. A guard raised just before a strike
## lands parries it. The mouse wheel plays flourishes. Its transform in the
## scene is the resting pose.

const Fx = preload("res://Core/Combat/fx.gd")
const Impact = preload("res://Core/Combat/impact.gd")
# A variable, because reads through a const are baked in when the script
# loads and would never see the tuning panel change them.
var look: Resource = preload("res://Core/Combat/combat_look.tres")

## Something worth seeing happened, for the tuning panel: the moment's name
## and any timing detail.
signal moment(kind: String, detail: String)

@export var player: CharacterBody3D
@export var impact_frames: Node
## The blade's glow pass; its heat and colours are driven from here.
@export var lava: ShaderMaterial
@export var reach := 2.3
## Seconds after raising the guard during which a strike is parried.
@export var parry_window := 0.2
@export var slash_damage := 25.0
## How far the sword lags behind mouse look before springing back.
@export var sway := 1.0
## Seconds of holding the button on a stunned enemy before the execution.
@export var execution_charge := 0.6
@export var execution_reach := 3.2

# The curve puts the middle of the blade a little to one side of the grip.
const BLADE_BASE := Vector3(-0.027, 0.5, 0)
const BLADE_TIP := Vector3(-0.002, 0.75, 0)
const TRAIL_LENGTH := 10

var _rest: Transform3D
# The animated pose. Sway and breathing are layered on top of it each frame.
var _pose_xf: Transform3D
var _anim: Tween
# Each move is [gather, cut, follow-through] poses. Chaining picks a next move
# that starts near where the last one ended, so combos flow without resets.
var _moves: Array[Dictionary] = []
var _move := -1
# Seconds left reeling after an enemy parries a swing.
var _stagger := 0.0
var _charging := false
var _charge := 0.0
var _target: Node3D
var _queued := false
var _slashing := false
var _guarding := false
var _guard_kind := "front"
# Game time, not real time: the parry window has to slow down with the hit
# freeze just like the strikes it's timed against.
var _guard_age := 0.0
var _heat := 0.0
# Colour of whatever last heated the blade; it cools in that colour.
var _heat_color := Color.WHITE
var _heat_core := Color.WHITE
# Tuning aid: pins the heat when 0 or more.
var _held_heat := -1.0
var _embers: GPUParticles3D
var _ember_process: ParticleProcessMaterial
var _light: OmniLight3D
var _look := Vector2.ZERO
var _sway := Vector2.ZERO
# Recent mouse movement, for picking a guard stance.
var _drift := Vector2.ZERO
var _time := 0.0
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_material: StandardMaterial3D
var _trail_points: Array[PackedVector3Array] = []
var _trailing := 0.0


func _ready():
	_rest = transform
	_pose_xf = _rest
	_build_moves()

	_ember_process = ParticleProcessMaterial.new()
	_ember_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_ember_process.emission_box_extents = Vector3(0.012, 0.32, 0.004)
	_ember_process.direction = Vector3(0, 1, 0)
	_ember_process.spread = 180.0
	_ember_process.initial_velocity_min = 0.02
	_ember_process.initial_velocity_max = 0.15
	_ember_process.gravity = Vector3(0, 0.5, 0)
	_ember_process.scale_curve = Fx.shrink_curve()
	var ember_mesh := QuadMesh.new()
	ember_mesh.size = Vector2.ONE * 0.012
	_embers = Fx.particles(48, 0.7, _ember_process, ember_mesh, Fx.glow(Color.WHITE, BaseMaterial3D.BILLBOARD_PARTICLES, Fx.soft_dot()))
	_add_particles(_embers)

	var ash := Fx.streak_process(0.02, 0.12, 180.0)
	ash.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ash.emission_box_extents = Vector3(0.012, 0.32, 0.004)
	ash.gravity = Vector3(0, 0.25, 0)
	ash.color_ramp = Fx.fade_ramp(Color(0, 0, 0, 1), Color(0, 0, 0, 0))
	_add_particles(Fx.particles(20, 0.9, ash, Fx.chip(0.0015, 0.009), Fx.ink(Color.WHITE)))

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.45, 0)
	_light.omni_range = 1.6
	add_child(_light)

	# A ribbon behind the blade, drawn in world space from where the blade
	# has just been.
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_material = Fx.glow(Color.WHITE)
	add_child(_trail)
	look.changed.connect(_apply_look)
	_take_colors(look.slash)
	_apply_look()


func _add_particles(p: GPUParticles3D) -> void:
	# World-space particles, so embers stream off behind a swing.
	p.local_coords = false
	p.position = Vector3(-0.025, 0.42, 0)
	add_child(p)


func _apply_look() -> void:
	if lava:
		for key in ["rest_glow", "white_hot", "glow_from_cold", "glow_from_hot", "pulse_speed"]:
			lava.set_shader_parameter(key, look.get(key))
	# Shows a colour being picked straight away, if the blade is cold.
	if _heat <= 0.0:
		_take_colors(look.slash)
	_apply_color()


func _take_colors(m: Resource) -> void:
	_heat_color = m.color
	_heat_core = m.core


func _apply_color() -> void:
	_ember_process.color_ramp = Fx.fade_ramp(_heat_color.lerp(Color.WHITE, 0.3), Color(_heat_color, 0))
	_light.light_color = _heat_color
	if lava:
		lava.set_shader_parameter("glow_color", _heat_color)
		lava.set_shader_parameter("core_color", _heat_core)


## Everything a moment sets off: sword glow, sparks, impact frames, shake.
func _land(kind: String, at: Vector3, normal: Vector3, detail := "") -> void:
	var m: Resource = look.get(kind)
	_burst(kind, at, normal)
	if m.impact > 0.0:
		impact_frames.hit(at, m.impact, m.heavy, m.color)
	_warm(kind, detail)


func _burst(kind: String, at: Vector3, normal: Vector3) -> void:
	var m: Resource = look.get(kind)
	if m.burst > 0.0:
		var burst: Node3D = Impact.new()
		_world().add_child(burst)
		burst.play(at, normal, m.burst, m.color)


## The sword's own part of a moment, for ones that don't strike anything.
func _warm(kind: String, detail := "") -> void:
	var m: Resource = look.get(kind)
	if m.shake > 0.0:
		player.shake(m.shake)
	_heat = maxf(_heat, m.heat)
	_take_colors(m)
	_apply_color()
	moment.emit(kind, detail)


func _input(event):
	if event is InputEventMouseMotion and visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look += event.relative
		_drift += event.relative


func _process(delta):
	_time += delta
	_heat = move_toward(_heat, 0.0, delta * look.cool_speed) if _held_heat < 0.0 else _held_heat
	_guard_age += delta
	_stagger = maxf(_stagger - delta, 0.0)
	if _charging:
		_charge_up(delta)
	if _guarding:
		# Flicking the mouse while guarding shifts stance (without restarting
		# the parry window).
		var stance := _stance_from_mouse()
		if _drift.length() > 25.0 and stance != _guard_kind and stance != "front":
			_guard_kind = stance
			_play([_guard_pose(stance)], [0.08], [[Tween.EASE_OUT, Tween.TRANS_CUBIC]])
	if lava:
		lava.set_shader_parameter("heat", _heat)
		# Charging, the glow climbs from the guard to the tip.
		lava.set_shader_parameter("sweep", clampf(_charge / execution_charge, 0.0, 1.0) if _charging else 1.0)
	_light.light_energy = 0.3 + _heat * look.blade_light
	_embers.amount_ratio = 0.3 + 0.7 * _heat

	# The sword trails the view: look right and it lags left, then catches up.
	_sway = _sway.lerp((_look * 0.0016 * sway).limit_length(0.12), 1.0 - exp(-delta * 14.0))
	_look = _look.lerp(Vector2.ZERO, 1.0 - exp(-delta * 16.0))
	_drift = _drift.lerp(Vector2.ZERO, 1.0 - exp(-delta * 8.0))
	var breathe := sin(_time * 1.7) * 0.004
	var tilt := Basis.from_euler(Vector3(-_sway.y * 1.2, -_sway.x * 1.4, _sway.x * 0.6))
	transform = Transform3D(tilt * _pose_xf.basis,
			_pose_xf.origin + Vector3(-_sway.x * 0.35, _sway.y * 0.25 + breathe, 0))
	_update_trail(delta)


## Called by the hands with the left button's state.
func trigger(pressed: bool) -> void:
	if not pressed:
		if _charging:
			_cancel_charge()
		return
	if _guarding or _stagger > 0.0 or _charging:
		return
	var open := _open_target()
	if open:
		_start_charge(open)
		return
	if _slashing:
		_queued = true
	else:
		_slash()


## Called by the hands with the right button's state.
func alt_trigger(pressed: bool) -> void:
	if pressed and _charging:
		_cancel_charge()
	if pressed:
		_guarding = true
		_guard_age = 0.0
		_queued = false
		_slashing = false
		_guard_kind = _stance_from_mouse()
		_play([_guard_pose(_guard_kind)], [0.07], [[Tween.EASE_OUT, Tween.TRANS_BACK]])
	elif _guarding:
		_guarding = false
		_play([_rest], [0.18], [[Tween.EASE_OUT, Tween.TRANS_CUBIC]])


## Called by the hands on the mouse wheel: +1 up, -1 down.
func flourish(direction: int) -> void:
	if _guarding or (_anim and _anim.is_running()):
		return
	_warm("flourish")
	_trailing = 0.6
	if direction > 0:
		_twirl()
	else:
		_flick()


## Put away mid-swing or mid-guard: snap back to rest.
func holster() -> void:
	if _charging:
		_charging = false
		impact_frames.set_time(1.0)
		impact_frames.focus(Vector3.ZERO, 0.0)
	_guarding = false
	_queued = false
	_slashing = false
	if _anim:
		_anim.kill()
	_pose_xf = _rest


## The guard stance being held, or "" when not guarding.
func stance() -> String:
	return _guard_kind if _guarding and visible else ""


## How a strike from `from` is met. An unblockable strike gets through
## anything but a parry. A strike with a `direction` (a stance name) is only
## stopped by a guard in that stance.
func receive_strike(from: Node3D, blockable := true, direction := "") -> String:
	var covered := _guarding and (direction == "" or direction == _guard_kind)
	var parried := covered and _guard_age <= parry_window
	if not visible or not (parried or (covered and blockable)):
		var force: float = from.get("hit_force") if from.get("hit_force") != null else 1.0
		_hurt(force, _miss_reason(direction))
		return "hit"
	var blade_mid := global_transform * Vector3(0, 0.45, 0)
	var toward := (from.global_position + Vector3.UP * 1.4 - blade_mid).normalized()
	var guard := _guard_pose(_guard_kind)
	var timing := "%.2f s after guard, window %.2f" % [_guard_age, parry_window]
	if parried:
		_land("parry", blade_mid, toward, timing)
		_trailing = 0.3
		# Knocked outward the way the stance faces, then back into guard.
		_play([_deflect_pose(_guard_kind), guard], [0.06, 0.2],
				[[Tween.EASE_OUT, Tween.TRANS_EXPO], [Tween.EASE_OUT, Tween.TRANS_BACK]])
		return "parry"
	_land("block", blade_mid + toward * 0.25, toward, timing)
	# Pushed back a little on the block.
	_play([guard.translated_local(Vector3(0, -0.05, 0.08)), guard], [0.05, 0.15],
			[[Tween.EASE_OUT, Tween.TRANS_QUAD], [Tween.EASE_OUT, Tween.TRANS_CUBIC]])
	return "block"


func _hurt(force: float, detail := "") -> void:
	player.shake(0.09 * force)
	player.spike_fov(player.BASE_FOV - 6.0 * force, 0.03, 0.25 + 0.1 * force)
	moment.emit("hurt", detail)


func _miss_reason(direction: String) -> String:
	if not _guarding:
		return "no guard"
	if direction != "" and direction != _guard_kind:
		return "guarded %s, attack was %s" % [_guard_kind, direction]
	return "guarded %.2f s early, window %.2f" % [_guard_age, parry_window]


## Right, left, high or low by the way the mouse was moving; still means a
## straight vertical guard in front.
func _stance_from_mouse() -> String:
	if _drift.length() < 8.0:
		return "front"
	if absf(_drift.x) > absf(_drift.y):
		return "right" if _drift.x > 0.0 else "left"
	return "high" if _drift.y < 0.0 else "low"


func _guard_pose(kind: String) -> Transform3D:
	match kind:
		"left":
			return _pose(Vector3(-0.16, -0.12, -0.45), Vector3(1.0, 0.22, -0.15), Vector3.BACK)
		"high":
			return _pose(Vector3(0.24, 0.06, -0.45), Vector3(-1.0, 0.1, -0.3), Vector3(0, -0.4, -1))
		"low":
			return _pose(Vector3(0.22, -0.2, -0.42), Vector3(-0.9, -0.3, -0.35), Vector3.BACK)
		"front":
			return _pose(Vector3(0.08, -0.2, -0.42), Vector3(0.04, 1.0, -0.12), Vector3(-0.8, 0, 0.6))
	return _pose(Vector3(0.12, -0.12, -0.45), Vector3(-1.0, 0.22, -0.15), Vector3.FORWARD)


## The parried guard thrown outward: shoved along `push` and turned by `turn`
## about `axis`, all in view space.
func _deflect_pose(kind: String) -> Transform3D:
	var push := Vector3(-0.05, 0.05, 0.06)
	var axis := Vector3.BACK
	var turn := 0.35
	match kind:
		"left":
			push = Vector3(0.05, 0.05, 0.06)
			turn = -0.35
		"high":
			push = Vector3(0.0, 0.09, 0.05)
			axis = Vector3.RIGHT
			turn = 0.3
		"low":
			push = Vector3(-0.04, -0.06, 0.06)
			turn = -0.3
		"front":
			push = Vector3(0.08, 0.02, 0.06)
			turn = -0.4
	var guard := _guard_pose(kind)
	return Transform3D(Basis(axis, turn) * guard.basis, guard.origin + push)


func _build_moves() -> void:
	for s in [1.0, -1.0]:
		# Diagonal from high on one side to low on the other...
		_moves.append(_arc("diagonal", Vector3(0.42 * s, -0.02, -0.35), Vector3(0.35 * s, 1.0, 0.45),
				Vector3(0.0, -0.18, -0.75), Vector3(-0.15 * s, 0.25, -1.0),
				Vector3(-0.38 * s, -0.38, -0.5), Vector3(-0.85 * s, -0.35, -0.45)))
		# ...a rising cut that starts where it ends and finishes where it began...
		_moves.append(_arc("rising", Vector3(-0.38 * s, -0.36, -0.45), Vector3(-0.8 * s, -0.45, -0.3),
				Vector3(0.0, -0.05, -0.75), Vector3(0.1 * s, 0.3, -1.0),
				Vector3(0.4 * s, 0.02, -0.42), Vector3(0.7 * s, 0.7, -0.2)))
		# ...and a flat sweep across, edge leading.
		_moves.append(_arc("sweep", Vector3(0.45 * s, -0.12, -0.35), Vector3(0.95 * s, 0.05, 0.2),
				Vector3(0.0, -0.15, -0.8), Vector3(0.0, 0.05, -1.0),
				Vector3(-0.45 * s, -0.15, -0.4), Vector3(-0.95 * s, 0.0, -0.15)))
	_moves.append(_arc("chop", Vector3(0.1, 0.12, -0.3), Vector3(0.0, 1.0, 0.6),
			Vector3(0.05, -0.1, -0.75), Vector3(0.0, 0.2, -1.0),
			Vector3(0.05, -0.42, -0.55), Vector3(0.0, -0.9, -0.4)))
	var thrust := _arc("thrust", Vector3(0.22, -0.2, -0.22), Vector3(-0.05, 0.08, -1.0),
			Vector3(0.08, -0.16, -0.95), Vector3(-0.08, 0.06, -1.0),
			Vector3(0.1, -0.17, -0.85), Vector3(-0.06, 0.05, -1.0), Vector3.UP)
	thrust["thrust"] = true
	_moves.append(thrust)


## A move from three grip positions and blade directions. The flat of the
## blade faces across the swing by default, so it cuts edge-first; that's
## measured through the cut, since a big swing turns too far to measure end
## to end.
func _arc(name: String, gather_at: Vector3, gather_dir: Vector3, cut_at: Vector3, cut_dir: Vector3,
		finish_at: Vector3, finish_dir: Vector3, flat := Vector3.ZERO) -> Dictionary:
	if flat == Vector3.ZERO:
		var cut := cut_dir.normalized()
		flat = (gather_dir.normalized().cross(cut) + cut.cross(finish_dir.normalized())).normalized()
	return {
		"name": name,
		"thrust": false,
		"poses": [_pose(gather_at, gather_dir, flat), _pose(cut_at, cut_dir, flat), _pose(finish_at, finish_dir, flat)],
	}


## A move that starts near where the blade is now, so it flows on from the
## last one; picked at random among those for variety.
func _pick_move() -> int:
	var here := _pose_xf.origin
	var near: Array[int] = []
	for i in _moves.size():
		if i != _move and (_moves[i]["poses"][0] as Transform3D).origin.distance_to(here) < 0.35:
			near.append(i)
	if near.is_empty():
		for i in _moves.size():
			if i != _move:
				near.append(i)
	return near.pick_random()


func _slash() -> void:
	_move = _pick_move()
	var poses: Array = _moves[_move]["poses"]
	var gather: Transform3D = poses[0]
	var cut: Transform3D = poses[1]
	var finish: Transform3D = poses[2]
	_slashing = true
	_warm("slash")
	_trailing = 0.35
	if _anim:
		_anim.kill()
	_anim = create_tween()
	# Gathering takes as long as the blade has to travel, so a chained move
	# that's already in place goes straight into its cut.
	var gather_time := clampf(_pose_xf.origin.distance_to(gather.origin) * 0.3, 0.04, 0.11)
	var cut_time := 0.07 if _moves[_move]["thrust"] else 0.055
	_anim.tween_method(_blend.bind(_pose_xf, gather), 0.0, 1.0, gather_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_anim.tween_method(_blend.bind(gather, cut), 0.0, 1.0, cut_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_anim.tween_callback(_strike)
	_anim.tween_method(_blend.bind(cut, finish), 0.0, 1.0, 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# A beat at the end of the swing to chain the next one.
	_anim.tween_interval(0.06)
	_anim.tween_callback(_after_slash)


func _after_slash() -> void:
	if _queued:
		_queued = false
		_slash()
	else:
		_slashing = false
		_move = -1
		_play([_rest], [0.26], [[Tween.EASE_IN_OUT, Tween.TRANS_SINE]])


## An enemy turned the swing aside: the blade is knocked back and you're
## open for a moment.
func _deflected(at: Vector3) -> void:
	_land("deflected", at, player.camera.global_basis.z)
	_queued = false
	_slashing = false
	_move = -1
	_stagger = 0.4
	var knocked := Transform3D(Basis(Vector3.BACK, 0.5) * Basis(Vector3.RIGHT, 0.4) * _pose_xf.basis,
			_pose_xf.origin + Vector3(0.12, 0.1, 0.15))
	_play([knocked, _rest], [0.07, 0.4], [[Tween.EASE_OUT, Tween.TRANS_EXPO], [Tween.EASE_IN_OUT, Tween.TRANS_SINE]])


## Wheel up: the blade spins a full turn in front of you, clock-hand style.
func _twirl() -> void:
	var up := _pose(Vector3(0.12, -0.2, -0.5), Vector3(0.0, 1.0, -0.15), Vector3.FORWARD)
	var keys: Array = [up]
	var times: Array = [0.1]
	var eases: Array = [[Tween.EASE_OUT, Tween.TRANS_CUBIC]]
	for quarter in range(1, 5):
		keys.append(Transform3D(Basis(Vector3.BACK, -quarter * PI * 0.5) * up.basis, up.origin))
		times.append(0.065)
		eases.append([Tween.EASE_IN_OUT, Tween.TRANS_LINEAR])
	keys.append(_rest)
	times.append(0.25)
	eases.append([Tween.EASE_OUT, Tween.TRANS_BACK])
	_play(keys, times, eases)


## Wheel down: raised, whipped down and out to the side, held, then back.
func _flick() -> void:
	var raised := _pose(Vector3(0.3, 0.0, -0.4), Vector3(0.15, 1.0, 0.3), Vector3.LEFT)
	var whipped := _pose(Vector3(0.45, -0.32, -0.5), Vector3(0.7, -0.6, -0.4), Vector3(-0.3, -0.4, -1.0))
	_play([raised, whipped, whipped, _rest], [0.12, 0.06, 0.18, 0.28],
			[[Tween.EASE_OUT, Tween.TRANS_CUBIC], [Tween.EASE_IN, Tween.TRANS_EXPO],
			[Tween.EASE_IN_OUT, Tween.TRANS_LINEAR], [Tween.EASE_IN_OUT, Tween.TRANS_SINE]])
	get_tree().create_timer(0.18).timeout.connect(func(): player.shake(0.01))


## The moment the blade passes through the middle of the view.
func _strike() -> void:
	var camera: Camera3D = player.camera
	var forward := -camera.global_basis.z
	# A thrust reaches further down a narrower line than a cut.
	var thrusting: bool = _move >= 0 and _moves[_move]["thrust"]
	var length := reach * (1.25 if thrusting else 1.0)
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, length) if thrusting else Vector3(1.6, 1.4, length)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(camera.global_basis, camera.global_position + forward * length * 0.5)
	query.exclude = [player.get_rid()]
	var struck := false
	var killed := false
	var first_at := Vector3.ZERO
	for result in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var target: Object = result.collider
		if not target.has_method("take_hit"):
			continue
		var center: Vector3 = target.global_position + Vector3.UP * 1.25
		var at := center + (camera.global_position - center).normalized() * 0.3
		if target.has_method("try_parry") and target.try_parry(at):
			_deflected(at)
			return
		var fatal: bool = target.take_hit(at, forward, look.hit.color, 1.0, slash_damage)
		killed = killed or fatal
		if struck:
			_burst("kill" if fatal else "hit", at, -forward)
		else:
			first_at = at
			struck = true
	if struck:
		# One impact frame per swing however many it hits; full force only
		# when the swing finishes something off.
		_land("kill" if killed else "hit", first_at, -forward)


func _update_trail(delta: float) -> void:
	_trailing = maxf(_trailing - delta, 0.0)
	if _trailing > 0.0:
		_trail_points.append(PackedVector3Array([global_transform * BLADE_BASE, global_transform * BLADE_TIP]))
		if _trail_points.size() > TRAIL_LENGTH:
			_trail_points.pop_front()
	elif not _trail_points.is_empty():
		_trail_points.pop_front()
	_trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_material)
	var count := _trail_points.size()
	for i in count:
		# Oldest end fades out; the newest, right at the blade, is brightest.
		var fade := float(i + 1) / count
		_trail_mesh.surface_set_color(Color(_heat_color.lerp(Color.WHITE, 0.3), fade * fade * 0.25))
		_trail_mesh.surface_add_vertex(_trail_points[i][0])
		_trail_mesh.surface_set_color(Color(_heat_color.lerp(Color.WHITE, 0.6), fade * fade * 0.55))
		_trail_mesh.surface_add_vertex(_trail_points[i][1])
	_trail_mesh.surface_end()


## Plays poses one after another, each with its own duration and easing
## ([ease, transition]).
func _play(keys: Array, times: Array, eases: Array) -> void:
	if _anim:
		_anim.kill()
	_anim = create_tween()
	var from := _pose_xf
	for i in keys.size():
		_anim.tween_method(_blend.bind(from, keys[i]), 0.0, 1.0, times[i]).set_ease(eases[i][0]).set_trans(eases[i][1])
		from = keys[i]


func _blend(t: float, from: Transform3D, to: Transform3D) -> void:
	_pose_xf = from.interpolate_with(to, t)


## A hold pose relative to the camera: grip at `at`, blade pointing along
## `blade`, flat of the blade facing `flat`. The sharp edge is on -X, which
## points along flat.cross(blade).
func _pose(at: Vector3, blade: Vector3, flat: Vector3) -> Transform3D:
	var y := blade.normalized()
	var x := y.cross(flat).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), at)


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root


## A stunned enemy in front of you and in reach, if there is one.
func _open_target() -> Node3D:
	var camera: Camera3D = player.camera
	var forward := -camera.global_basis.z
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.6, execution_reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(camera.global_basis, camera.global_position + forward * execution_reach * 0.5)
	query.exclude = [player.get_rid()]
	for result in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var target: Object = result.collider
		if target.has_method("is_open") and target.is_open():
			return target
	return null


func _start_charge(target: Node3D) -> void:
	_charging = true
	_charge = 0.0
	_target = target
	_queued = false
	_slashing = false
	_trailing = 0.3
	# Time drags while you gather yourself for it.
	impact_frames.set_time(0.5)
	# Drawn back to the hip, point aimed at the target, and pulling back
	# further as the charge builds, like a spring being wound.
	var drawn := _pose(Vector3(0.24, -0.2, -0.05), Vector3(-0.08, 0.06, -1.0), Vector3.UP)
	var wound := _pose(Vector3(0.28, -0.22, 0.12), Vector3(-0.1, 0.08, -1.0), Vector3.UP)
	_play([drawn, wound], [0.18, execution_charge * 0.9],
			[[Tween.EASE_OUT, Tween.TRANS_CUBIC], [Tween.EASE_OUT, Tween.TRANS_SINE]])


func _charge_up(delta: float) -> void:
	if not is_instance_valid(_target) or not _target.is_open():
		_cancel_charge()
		return
	# Real time, so the slowed world doesn't stretch the charge.
	_charge += delta / maxf(Engine.time_scale, 0.01)
	var amount := clampf(_charge / execution_charge, 0.0, 1.0)
	_heat = 1.0
	if _heat_color != look.execute.color or _heat_core != look.execute.core:
		_take_colors(look.execute)
		_apply_color()
	player.shake(0.002 + 0.01 * amount)
	impact_frames.focus(_target_point(), amount, look.execute.color)
	if amount >= 1.0:
		_execute()


func _cancel_charge() -> void:
	_charging = false
	impact_frames.set_time(1.0)
	impact_frames.focus(Vector3.ZERO, 0.0)
	_play([_rest], [0.25], [[Tween.EASE_IN_OUT, Tween.TRANS_SINE]])


func _target_point() -> Vector3:
	return _target.global_position + Vector3.UP * 1.25


## Dash straight through the target, cutting it on the way past.
func _execute() -> void:
	_charging = false
	impact_frames.set_time(1.0)
	impact_frames.focus(Vector3.ZERO, 0.0)
	var target := _target
	var through := target.global_position - player.global_position
	through.y = 0.0
	through = through.normalized()
	var land := target.global_position + through * 1.2
	land.y = player.global_position.y
	# Stop short of anything solid on the far side rather than dashing into it.
	var from := player.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, land + Vector3.UP * 0.9 + through * 0.4)
	query.exclude = [player.get_rid(), target.get_rid()]
	var blocked := get_world_3d().direct_space_state.intersect_ray(query)
	if blocked:
		land = blocked.position - through * 0.45
		land.y = player.global_position.y
	_trailing = 0.5
	# Driven straight forward and held at full extension through the dash.
	var lunge := _pose(Vector3(0.04, -0.14, -1.05), Vector3(-0.03, 0.04, -1.0), Vector3.UP)
	_play([lunge, lunge], [0.05, 0.3],
			[[Tween.EASE_IN, Tween.TRANS_EXPO], [Tween.EASE_IN_OUT, Tween.TRANS_LINEAR]])
	var dash := create_tween()
	dash.tween_property(player, "global_position", land, 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	dash.tween_callback(func():
		var at := _target_point()
		target.execute(at, through, look.execute.color)
		_land("execute", at, -through))
	# Through and past it: pull free and flick the blade clean.
	dash.tween_interval(0.35)
	dash.tween_callback(_flick)


## Tuning aid: plays a moment on the spot, no enemy needed.
func preview(kind: String) -> void:
	var back: Vector3 = player.camera.global_basis.z
	match kind:
		"slash":
			_slash()
		"flourish":
			flourish(1)
		"hurt":
			_hurt(1.0, "preview")
		"parry", "block":
			var guard := _guard_pose("front")
			_land(kind, player.camera.global_transform * Vector3(0.08, 0.1, -0.5), -back, "preview")
			_pose_xf = guard
			_trailing = 0.3
			_play([_deflect_pose("front"), guard, _rest], [0.06, 0.2, 0.3],
					[[Tween.EASE_OUT, Tween.TRANS_EXPO], [Tween.EASE_OUT, Tween.TRANS_BACK], [Tween.EASE_IN_OUT, Tween.TRANS_SINE]])
		_:
			_land(kind, preview_point(), back, "preview")


func preview_point() -> Vector3:
	return player.camera.global_position - player.camera.global_basis.z * 3.5


## Tuning aid: lights the sword up in its slash colours, then lets it cool.
func show_glow() -> void:
	_heat = 1.0
	_take_colors(look.slash)
	_apply_color()


## Tuning aid: pins the glow at `heat` in a moment's colour; negative lets go.
func hold_heat(heat: float, kind := "slash") -> void:
	_held_heat = heat
	if heat >= 0.0:
		_take_colors(look.get(kind))
		_apply_color()
