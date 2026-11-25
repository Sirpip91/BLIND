extends MeshInstance3D

## One burst of ink where blades or bodies meet. Removes itself.

const SPLASH = preload("res://Experiments/SteelGuard/splash.gdshader")

var _material := ShaderMaterial.new()


func play(at: Vector3, size: float, color: Color, seconds := 0.4, thrown := Vector2.ZERO, blot := 0.16) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shader = SPLASH
	_material.render_priority = 127
	_material.set_shader_parameter("ink_color", color)
	_material.set_shader_parameter("seed", randf() * 60.0)
	_material.set_shader_parameter("thrown", thrown)
	_material.set_shader_parameter("blot", blot)
	material_override = _material
	global_position = at
	# In real time, so it's still flying while the world is frozen on it.
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_method(func(v: float): _material.set_shader_parameter("age", v), 0.0, 1.0, seconds)
	tween.tween_callback(queue_free)
