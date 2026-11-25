extends MeshInstance3D

## The line of a cut that landed, drawn through whatever it hit. Removes
## itself.

const SLASH = preload("res://Experiments/SteelPaint/slash.gdshader")

var _material := ShaderMaterial.new()


func play(at: Vector3, way: Vector2, size: float, color: Color, seconds := 0.34) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shader = SLASH
	_material.render_priority = 126
	_material.set_shader_parameter("ink_color", color)
	_material.set_shader_parameter("seed", randf() * 60.0)
	_material.set_shader_parameter("way", way.normalized() if way.length() > 0.1 else Vector2(0.2, 1.0).normalized())
	material_override = _material
	global_position = at
	# In real time, so it's drawn while the world is frozen on it.
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_method(func(v: float): _material.set_shader_parameter("age", v), 0.0, 1.0, seconds)
	tween.tween_callback(queue_free)
