extends Node3D

## Red ink, thrown the way the edge was going: out of whoever's cut, onto the
## ground, and along the blade, where it stays until it's flicked off.

const Stroke = preload("res://Core/Wash/ink_stroke.gd")
const SPLAT = preload("res://Experiments/Arena/feel/blood.gdshader")

@export var sword: Node3D
## The player's blade, as it's drawn.
@export var ink: ShaderMaterial
@export var red := Color(0.62, 0.008, 0.014)
## Off in the options, and everyone bleeds ink.
static var gore := true
## What there is in a man of straw.
@export var black := Color(0.014, 0.014, 0.018)
@export var gravity := 9.5
## How much one cut leaves on the blade.
@export var from_scratch := 0.12
@export var from_deep := 0.27
## Seconds between drops off the point of a bloody sword.
@export var drips := Vector2(0.5, 2.0)

const GROUP := "arena_blood"
const IN_AIR := 220
const ON_GROUND := 420
## The blade, in the sword's own space.
const BLADE := Vector2(0.1, 0.74)

## How much is on the blade.
var on_blade := 0.0

# What's spilt here, and what's on the blade from wherever that was.
var _color := Color.RED
var _blade_color := Color.RED
var _tints := PackedColorArray()
var _splat := ShaderMaterial.new()
var _drops: MultiMesh
var _ground: MultiMesh
var _at := PackedVector3Array()
var _going := PackedVector3Array()
var _big := PackedFloat32Array()
var _next_drop := 0
var _next_splat := 0
# Where there's none left, from the guard up, while it's being flicked off.
var _clean := 0.0
var _flicking := false
var _seed := 0.0
var _drip := 1.0
var _run := 0.0
var _arc: MeshInstance3D


func _ready():
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 8
	ball.rings = 4
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	_drops = _many(ball, paint, IN_AIR, false)
	var flat := PlaneMesh.new()
	flat.size = Vector2.ONE
	_splat.shader = SPLAT
	_ground = _many(flat, _splat, ON_GROUND, true)
	_at.resize(IN_AIR)
	_going.resize(IN_AIR)
	_big.resize(IN_AIR)
	_tints.resize(IN_AIR)
	_color = red
	_blade_color = red
	add_to_group(GROUP)
	sword.flicked.connect(_flick)
	sword.flicking.connect(_start_flick)
	clear()


func _many(mesh: Mesh, material: Material, count: int, custom: bool) -> MultiMesh:
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = custom
	many.mesh = mesh
	many.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = many
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 12, 80))
	add_child(node)
	return many


## Straw men aren't full of blood.
func spill(straw: bool) -> void:
	_color = black if straw else red


## Somewhere else. What's on the blade stays on it.
func clear() -> void:
	for i in IN_AIR:
		_big[i] = 0.0
		_drops.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.DOWN * 5.0))
	for i in ON_GROUND:
		_ground.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.DOWN * 5.0))


## Out of a cut at `at`, the way the edge went through it. `from` is where the
## one who cut stands.
func spray(at: Vector3, travel: Vector3, from: Vector3, deep: bool, fatal: bool) -> void:
	var away := at - from
	away.y = 0.0
	away = away.normalized()
	var way := (travel.normalized() + away * 0.28).normalized()
	var many := 42 if fatal else (28 if deep else 9)
	for i in many:
		# A fan, tight along the cut, the fast ones tightest.
		var fast := randf()
		var off := Vector3(randfn(0.0, 0.3), randfn(0.12, 0.26), randfn(0.0, 0.3)) * (1.25 - fast)
		var speed := lerpf(0.8, 5.2 if deep else 3.2, fast * fast) * randf_range(0.8, 1.2)
		var going := (way + off).normalized() * speed + Vector3.UP * randf_range(0.2, 1.1)
		_throw(at + way * 0.06, going, lerpf(0.05, 0.016, fast) * randf_range(0.7, 1.4) * (1.0 if deep else 0.7))
	if not deep:
		return
	for i in 3 if fatal else 2:
		var side := away.cross(way).normalized() * randfn(0.0, 0.22)
		_lash(at, (way + side + Vector3.UP * randf_range(0.0, 0.25)).normalized() * randf_range(2.6, 4.4), randf_range(0.14, 0.26), randf_range(0.16, 0.26))
	_pulse(at, way, 4 if fatal else 2)


# What keeps coming, weaker each time.
func _pulse(at: Vector3, way: Vector3, times: int) -> void:
	for k in times:
		await get_tree().create_timer(0.13 + 0.07 * k).timeout
		if not is_inside_tree():
			return
		for i in 7 - k:
			var off := Vector3(randfn(0.0, 0.3), randfn(0.35, 0.2), randfn(0.0, 0.3))
			_throw(at + Vector3.DOWN * 0.06 * k, (way * 0.7 + off).normalized() * randf_range(0.8, 2.4) / (1.0 + 0.3 * k), randf_range(0.014, 0.04))


## A little of it is on the blade now.
func stain_blade(deep: bool) -> void:
	if on_blade <= 0.02:
		_seed = randf() * 40.0
	_clean = 0.0
	_blade_color = _color
	ink.set_shader_parameter("blood_color", _blade_color)
	on_blade = minf(on_blade + (from_deep if deep else from_scratch), 1.0)


func _throw(at: Vector3, going: Vector3, size: float, tint := _color) -> void:
	_tints[_next_drop] = tint
	_drops.set_instance_color(_next_drop, tint)
	_at[_next_drop] = at
	_going[_next_drop] = going
	_big[_next_drop] = size
	_next_drop = (_next_drop + 1) % IN_AIR


# One long stroke of it through the air.
func _lash(at: Vector3, going: Vector3, seconds: float, width: float) -> void:
	var stroke := _stroke(width, _color)
	var camera := get_viewport().get_camera_3d()
	var here := at
	var left := seconds
	# Laid over a few frames, so it's seen to go.
	while left > 0.0 and is_instance_valid(stroke):
		var step := minf(get_process_delta_time(), 0.03)
		for i in 5:
			var d := step / 5.0
			here += going * d
			going.y -= gravity * d
			stroke.add(here, camera.global_position)
		left -= step
		await get_tree().process_frame
	if is_instance_valid(stroke):
		stroke.finish()


func _stroke(width: float, tint: Color) -> MeshInstance3D:
	var stroke := Stroke.new()
	stroke.width = width
	stroke.dry_time = 0.34
	stroke.set_tint(tint, 1.0)
	stroke._material.set_shader_parameter("ink_color", tint)
	stroke._material.set_shader_parameter("water", 0.12)
	get_tree().current_scene.add_child(stroke)
	return stroke


## On the ground at `at`, thrown along `going`.
func _land(at: Vector3, going: Vector3, size: float, tint := _color) -> void:
	var flat := Vector3(going.x, 0.0, going.z)
	var fast := flat.length()
	var way := flat / fast if fast > 0.05 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	# The flatter it comes in, the longer the mark.
	var long := clampf(1.0 + fast / maxf(absf(going.y), 1.2) * 1.3, 1.0, 3.6)
	var wide := size * randf_range(5.5, 9.0)
	var basis := Basis(way * wide * long, Vector3.UP, way.cross(Vector3.UP) * wide)
	_ground.set_instance_transform(_next_splat, Transform3D(basis, Vector3(at.x, 0.006 + 0.00002 * _next_splat, at.z) + way * wide * long * 0.25))
	_ground.set_instance_color(_next_splat, tint)
	_ground.set_instance_custom_data(_next_splat, Color(randf() * 50.0, Time.get_ticks_msec() / 1000.0, long, clampf(size / 0.04, 0.0, 1.0)))
	_next_splat = (_next_splat + 1) % ON_GROUND


## Where something that's been cut off has come down.
func pool(at: Vector3, going: Vector3) -> void:
	for i in 5:
		var off := Vector3(randfn(0.0, 0.16), 0.0, randfn(0.0, 0.16))
		_land(at + off, going * randf_range(0.3, 1.0) + off * 4.0, randf_range(0.025, 0.07))


func _process(delta: float):
	for i in IN_AIR:
		if _big[i] <= 0.0:
			continue
		_going[i].y -= gravity * delta
		_at[i] += _going[i] * delta
		if _at[i].y <= 0.0:
			_land(_at[i], _going[i], _big[i], _tints[i])
			_big[i] = 0.0
			_drops.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.DOWN * 5.0))
			continue
		var speed := _going[i].length()
		var y := _going[i] / maxf(speed, 0.01)
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.UP).normalized()
		_drops.set_instance_transform(i, Transform3D(Basis(x, y, x.cross(y)).scaled_local(Vector3(_big[i], _big[i] * (1.0 + speed * 0.55), _big[i])), _at[i]))
	_run += delta
	ink.set_shader_parameter("blood", on_blade)
	ink.set_shader_parameter("blood_seed", _seed)
	ink.set_shader_parameter("blood_clean", _clean)
	ink.set_shader_parameter("blood_run", _run)
	_splat.set_shader_parameter("blood_now", Time.get_ticks_msec() / 1000.0)
	_fall_off(delta)


# Off the point, if it's left there.
func _fall_off(delta: float) -> void:
	if on_blade < 0.15 or _flicking:
		return
	_drip -= delta * on_blade
	if _drip > 0.0:
		return
	_drip = randf_range(drips.x, drips.y)
	_throw(_point(1.0), Vector3(randfn(0.0, 0.05), 0.0, randfn(0.0, 0.05)), randf_range(0.012, 0.022), _blade_color)


## A place along the blade, from the guard to the point.
func _point(along: float) -> Vector3:
	return sword.global_transform * Vector3(0.0, lerpf(BLADE.x, BLADE.y, along), 0.0)


# ---- flicked off

func _start_flick() -> void:
	if on_blade < 0.04:
		return
	_flicking = true
	_arc = _stroke(0.05 + 0.09 * on_blade, _blade_color)
	var arc := _arc
	var camera := get_viewport().get_camera_3d()
	var was := sword.global_transform
	var on := true
	while on and is_instance_valid(arc):
		on = _flicking
		# Round, not straight across, however long the frame was.
		for i in range(1, 9):
			var there := was.interpolate_with(sword.global_transform, i / 8.0)
			arc.add(there * Vector3(0.0, BLADE.y, 0.0), camera.global_position)
		was = sword.global_transform
		if on:
			await get_tree().process_frame
	if is_instance_valid(arc):
		arc.finish()


## At the bottom of it, all at once, and off the point of the sword.
func _flick(way: Vector3) -> void:
	if on_blade < 0.04:
		return
	_flicking = false
	var much := on_blade
	var out := way.normalized()
	for i in int(10 + 34 * much):
		var along := sqrt(randf())
		var fast := randf()
		# In a line, the way the blade was going.
		var off := Vector3(randfn(0.0, 0.07), randfn(0.0, 0.09), randfn(0.0, 0.07))
		_throw(_point(along), (out + off).normalized() * lerpf(2.0, 7.5, along * lerpf(0.45, 1.0, fast)), lerpf(0.045, 0.014, fast) * randf_range(0.7, 1.3), _blade_color)
	var wipe := create_tween()
	wipe.tween_property(self, "_clean", 1.15, 0.1)
	wipe.tween_callback(func(): on_blade = 0.0)
