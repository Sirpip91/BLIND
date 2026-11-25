extends MeshInstance3D

## A brush stroke left in the air by one swing. It follows the path of the
## blade's tip and always lies flat to the eye, like a stroke on paper: a
## swing seen edge-on would otherwise be a hairline. Fed while the blade is
## moving fast, then it dries where it hangs and removes itself.

const STROKE = preload("res://Experiments/InkWash/ink_stroke.gdshader")

var dry_time := 0.45
## Metres across at its fullest.
var width := 0.12

var _path := PackedVector3Array()
var _eyes := PackedVector3Array()
var _along := PackedFloat32Array()
var _ribbon := ImmediateMesh.new()
var _material := ShaderMaterial.new()
var _age := 0.0
var _done := false


func _init():
	mesh = _ribbon
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 4.0
	_material.shader = STROKE
	_material.render_priority = 126
	_material.set_shader_parameter("seed", randf() * 50.0)


func set_tint(color: Color, amount: float) -> void:
	_material.set_shader_parameter("tint", color)
	_material.set_shader_parameter("tint_amount", amount)


func add(at: Vector3, eye: Vector3) -> void:
	var length := 0.0
	if not _path.is_empty():
		var step := at.distance_to(_path[-1])
		if step < 0.008:
			return
		length = _along[-1] + step
	_path.append(at)
	_eyes.append(eye)
	_along.append(length)


func length() -> float:
	return 0.0 if _along.is_empty() else _along[-1]


func finish() -> void:
	_done = true


func _process(delta):
	if _done:
		_age += delta / dry_time
		if _age >= 1.0:
			queue_free()
			return
	_material.set_shader_parameter("age", _age)
	_ribbon.clear_surfaces()
	var count := _path.size()
	if count < 3:
		return
	_material.set_shader_parameter("total", _along[-1])
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	var side := Vector3.ZERO
	for i in count:
		# Over a few points either way, so the edge doesn't kink.
		var ahead := _path[mini(i + 9, count - 1)] - _path[maxi(i - 9, 0)]
		var across := ahead.cross(_eyes[i] - _path[i])
		if across.length_squared() > 1e-8:
			across = across.normalized()
			side = across if side == Vector3.ZERO or across.dot(side) > 0.0 else -across
		var half := side * width * 0.5
		_ribbon.surface_set_uv(Vector2(_along[i], 0.0))
		_ribbon.surface_add_vertex(_path[i] - half)
		_ribbon.surface_set_uv(Vector2(_along[i], 1.0))
		_ribbon.surface_add_vertex(_path[i] + half)
	_ribbon.surface_end()
