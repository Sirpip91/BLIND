extends Node3D

## One hit: a flash of real light, glowing streaks and ink shards bursting off
## the surface, and a shockwave ring. Frees itself when it's done.

const Fx = preload("res://Core/Combat/fx.gd")

# A variable, because reads through a const are baked in when the script
# loads and would never see the tuning panel change them.
var look: Resource = preload("res://Core/Combat/combat_look.tres")


## Call once it's in the tree.
func play(at: Vector3, normal: Vector3, strength: float, color := Color.WHITE) -> void:
	global_position = at
	# Local +Y points out of the surface so the burst and ring face away from it.
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
	global_basis = Basis(side, up, side.cross(up)).orthonormalized()

	# Everything shrinks as it gets close, so a burst right at the blade looks
	# the same size on screen as one across the room.
	var camera := get_viewport().get_camera_3d()
	var distance := clampf(camera.global_position.distance_to(at), 0.3, 6.0) if camera else 3.0
	var near := minf(distance / 3.0, 1.0)

	var light := OmniLight3D.new()
	light.light_energy = 8.0 * strength
	light.light_color = color
	light.omni_range = 7.0
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 4.0 * near
	light.position = Vector3(0, 0.3, 0)
	add_child(light)

	if look.flash_size > 0.0:
		_flash(strength * near, color)
	if look.spark_size > 0.0:
		_sparks(strength, near, color)
	if look.ring_size > 0.0:
		_ring(strength, color, distance)

	var tween := create_tween().set_parallel()
	tween.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.chain().tween_interval(0.6)
	tween.chain().tween_callback(queue_free)


func _flash(size: float, color: Color) -> void:
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.1 * size * look.flash_size
	var material := Fx.glow(Color(color, 0.9), BaseMaterial3D.BILLBOARD_ENABLED, Fx.soft_dot())
	quad.material = material
	flash.mesh = quad
	flash.position = Vector3(0, 0.1, 0)
	add_child(flash)
	var tween := create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.2)


func _sparks(strength: float, near: float, color: Color) -> void:
	var size: float = near * look.spark_size
	var streaks := Fx.streak_process(5.0 * near, 14.0 * strength * near, 75.0)
	streaks.damping_min = 10.0 * near
	streaks.damping_max = 18.0 * near
	streaks.scale_min = 0.35
	streaks.color_ramp = Fx.fade_ramp(color, Color(color * 0.6, 0))
	_one_shot(Fx.particles(maxi(int(40 * strength), 1), 0.45, streaks, Fx.needle(0.006 * size, 0.3 * size), Fx.glow(Color.WHITE)))

	var shards := Fx.streak_process(2.5 * near, 7.0 * strength * near, 80.0)
	shards.gravity = Vector3(0, -12, 0) * near
	shards.scale_min = 0.3
	shards.color_ramp = Fx.fade_ramp(Color(0, 0, 0, 1), Color(0, 0, 0, 0))
	_one_shot(Fx.particles(maxi(int(24 * strength), 1), 0.7, shards, Fx.chip(0.012 * size, 0.06 * size), Fx.ink(Color.WHITE)))


func _ring(strength: float, color: Color, distance: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 96
	torus.ring_segments = 8
	var material := Fx.glow(Color(color, 0.8))
	torus.material = material
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.02, 0)
	add_child(ring)
	var radius: float = look.ring_size * 0.13 * distance * lerpf(0.6, 1.0, minf(strength, 1.0))
	ring.scale = Vector3.ONE * radius * 0.25
	var tween := create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3.ONE * radius, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.25)


func _one_shot(p: GPUParticles3D) -> void:
	p.one_shot = true
	p.explosiveness = 1.0
	add_child(p)
	p.emitting = true
