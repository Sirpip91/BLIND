extends RefCounted

## Building blocks for the light-magic effects. Glow materials render after
## the ink pass (priority 127), so they stay soft and additive instead of
## being redrawn flat; they're authored in greys since nothing desaturates
## them afterwards.


static func soft_dot() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## Additive light: white adds brightness, black adds nothing.
static func glow(color: Color, billboard := BaseMaterial3D.BILLBOARD_DISABLED, texture: Texture2D = null) -> StandardMaterial3D:
	var m := _base(color, billboard, texture)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## Ink drawn over the top: dark specks that additive blending can't make.
static func ink(color: Color, billboard := BaseMaterial3D.BILLBOARD_DISABLED, texture: Texture2D = null) -> StandardMaterial3D:
	return _base(color, billboard, texture)


static func _base(color: Color, billboard: int, texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = texture
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.render_priority = 127
	return m


static func fade_ramp(from: Color, to: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func shrink_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func particles(amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: PrimitiveMesh, material: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = process
	mesh.material = material
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	return p


## A thin spike for particles that point where they fly. Solid rather than a
## card, so it needs no billboarding and never shows as a flat rectangle.
static func needle(radius: float, length: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = 0.0
	mesh.height = length
	mesh.radial_segments = 5
	mesh.rings = 1
	return mesh


## A small rough chip, for shards and flecks.
static func chip(radius: float, length: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = length
	mesh.radial_segments = 4
	mesh.rings = 1
	return mesh


## Streaks that stretch along their direction of travel.
static func streak_process(speed_min: float, speed_max: float, spread: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = spread
	m.initial_velocity_min = speed_min
	m.initial_velocity_max = speed_max
	m.gravity = Vector3.ZERO
	m.particle_flag_align_y = true
	m.scale_curve = shrink_curve()
	return m
