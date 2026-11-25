extends Node

## Anime-style impact frames, in order: time freezes, a frame of flat black
## silhouettes, a frame of negative, then burst lines and a punch-in zoom as
## time eases back into motion.

# A variable, because reads through a const are baked in when the script
# loads and would never see the tuning panel change them.
var look: Resource = preload("res://Core/Combat/combat_look.tres")

## What hold() can pin on screen.
const HOLDS := ["silhouette", "negative", "rays", "focus lines", "spiral", "jagged", "punch-in"]

@export var ink_pass: MeshInstance3D
@export var player: Node

## Tuning aid: plays everything this many times slower.
var slow := 1.0:
	set(value):
		slow = value
		if _held == "":
			set_time(1.0)

var _material: ShaderMaterial
var _hit := 0
var _held := ""
var _after: Tween


func _ready():
	_material = ink_pass.mesh.surface_get_material(0)
	look.changed.connect(_apply_look)
	_apply_look()


func _exit_tree():
	Engine.time_scale = 1.0


## Use instead of Engine.time_scale, so slowed-down tuning holds.
func set_time(scale: float) -> void:
	Engine.time_scale = scale / slow


## Light hits (ordinary blows) get a short freeze and a small punch-in. Heavy
## ones (parries, killing blows) get the whole sequence, so it still lands
## when it shows up.
func hit(at: Vector3, strength: float, heavy := false, color := Color.WHITE) -> void:
	if _held != "":
		return
	_hit += 1
	var this_hit := _hit
	if _after:
		_after.kill()
	strength = clampf(strength, 0.0, 1.5)
	var p := _material
	_aim(at, color)
	if not heavy:
		_light(this_hit, strength)
		return
	var lines := minf(strength, 1.0)
	# A different burst every time, so it never reads as the same stamp.
	p.set_shader_parameter("impact_seed", randf() * 100.0)
	p.set_shader_parameter("impact_style", randi() % 4)
	p.set_shader_parameter("impact_twist", randf_range(1.5, 4.0) * (1.0 if randf() < 0.5 else -1.0))
	p.set_shader_parameter("impact_rays", randf_range(120.0, 240.0))
	p.set_shader_parameter("impact_lines", lines)
	p.set_shader_parameter("impact_zoom", look.punch * strength)

	player.shake(0.05 * strength)
	set_time(0.02)

	for step: Array in [[1, look.silhouette_time], [2, look.negative_time]]:
		if step[1] <= 0.0:
			continue
		p.set_shader_parameter("impact_mode", step[0])
		await _wait(step[1])
		if this_hit != _hit:
			return
	p.set_shader_parameter("impact_mode", 0)

	await _wait(look.freeze * strength)
	if this_hit != _hit:
		return
	# Easing out of the freeze rather than snapping reads as weight.
	_after = create_tween().set_ignore_time_scale(true).set_parallel()
	_after.tween_method(set_time, 0.1, 1.0, look.thaw * slow).set_ease(Tween.EASE_IN)
	_after.tween_method(func(v: float): p.set_shader_parameter("impact_zoom", v),
			look.punch * strength, 0.0, 0.3 * slow).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_after.tween_method(func(v: float): p.set_shader_parameter("impact_lines", v),
			lines, 0.0, look.lines_fade * slow).set_ease(Tween.EASE_IN)


func _light(this_hit: int, strength: float) -> void:
	var p := _material
	var zoom: float = look.punch * 0.3 * strength
	p.set_shader_parameter("impact_lines", 0.0)
	p.set_shader_parameter("impact_mode", 0)
	p.set_shader_parameter("impact_zoom", zoom)
	player.shake(0.02 * strength)
	set_time(0.05)
	await _wait(look.light_freeze * strength)
	if this_hit != _hit:
		return
	_after = create_tween().set_ignore_time_scale(true).set_parallel()
	_after.tween_method(set_time, 0.2, 1.0, look.thaw * 0.5 * slow)
	_after.tween_method(func(v: float): p.set_shader_parameter("impact_zoom", v),
			zoom, 0.0, 0.15 * slow).set_ease(Tween.EASE_OUT)


## Charging an execution: the view creeps in on the target and focus lines
## close around it as `amount` goes from 0 to 1. 0 lets go.
func focus(at: Vector3, amount: float, color := Color.WHITE) -> void:
	var p := _material
	if amount <= 0.0:
		p.set_shader_parameter("impact_lines", 0.0)
		p.set_shader_parameter("impact_zoom", 0.0)
		return
	_aim(at, color)
	p.set_shader_parameter("impact_split", 0.0)
	p.set_shader_parameter("impact_style", 1)
	p.set_shader_parameter("impact_rays", 200.0)
	p.set_shader_parameter("impact_lines", amount * 0.6)
	p.set_shader_parameter("impact_zoom", amount * 0.14)


## Tuning aid: pins one part of the sequence on screen with time stopped.
## Empty lets go.
func hold(what: String, at := Vector3.ZERO, color := Color.WHITE) -> void:
	if what == "" and _held == "":
		return
	_hit += 1
	if _after:
		_after.kill()
	_held = what
	var p := _material
	var style := HOLDS.find(what) - 2
	p.set_shader_parameter("impact_mode", {"silhouette": 1, "negative": 2}.get(what, 0))
	p.set_shader_parameter("impact_lines", 1.0 if style >= 0 and style < 4 else 0.0)
	p.set_shader_parameter("impact_zoom", look.punch if what == "punch-in" else 0.0)
	if what == "":
		set_time(1.0)
		return
	_aim(at, color)
	p.set_shader_parameter("impact_style", clampi(style, 0, 3))
	p.set_shader_parameter("impact_twist", 2.5)
	p.set_shader_parameter("impact_rays", 180.0)
	set_time(0.001)


func _aim(at: Vector3, color: Color) -> void:
	var camera: Camera3D = player.camera
	var center := Vector2(0.5, 0.5)
	if not camera.is_position_behind(at):
		center = camera.unproject_position(at) / get_viewport().get_visible_rect().size
	var p := _material
	p.set_shader_parameter("impact_center", center)
	p.set_shader_parameter("impact_depth", -(camera.global_transform.affine_inverse() * at).z)
	p.set_shader_parameter("impact_color", color)
	p.set_shader_parameter("impact_split", look.fringe)
	p.set_shader_parameter("impact_back", look.silhouette_back.lerp(color, look.silhouette_tint))


func _apply_look() -> void:
	var p := _material
	p.set_shader_parameter("saturation", look.world_color)
	p.set_shader_parameter("impact_shape", look.silhouette_shape)
	p.set_shader_parameter("impact_fringe", look.fringe_color)
	p.set_shader_parameter("impact_colored", look.lines_colored)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds * slow, true, false, true).timeout
