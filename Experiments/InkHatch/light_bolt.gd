extends Node3D

## A thrown ball of light: lights the room as it flies, leaves a trail of
## motes and ink flecks, and bursts on whatever it hits.

const Fx = preload("res://Core/Combat/fx.gd")
const Impact = preload("res://Core/Combat/impact.gd")

var velocity := Vector3.ZERO
var exclude: Array[RID] = []
var strength := 0.6
var color := Color.WHITE
var max_distance := 80.0
var on_hit: Callable

var _travelled := 0.0
var _done := false
var _core: Node3D
var _light: OmniLight3D
var _trail: Array[GPUParticles3D] = []


func _ready():
	_core = Node3D.new()
	add_child(_core)
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.material = Fx.glow(color.lerp(Color.WHITE, 0.6))
	var ball := MeshInstance3D.new()
	ball.mesh = sphere
	_core.add_child(ball)
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.5
	quad.material = Fx.glow(Color(color, 0.7), BaseMaterial3D.BILLBOARD_ENABLED, Fx.soft_dot())
	halo.mesh = quad
	_core.add_child(halo)

	_light = OmniLight3D.new()
	_light.light_energy = 2.0
	_light.light_color = color
	_light.omni_range = 5.0
	_light.shadow_enabled = true
	_light.light_volumetric_fog_energy = 2.0
	add_child(_light)

	var motes := ParticleProcessMaterial.new()
	motes.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.05
	motes.spread = 180.0
	motes.initial_velocity_min = 0.2
	motes.initial_velocity_max = 0.8
	motes.gravity = Vector3.ZERO
	motes.scale_curve = Fx.shrink_curve()
	motes.color_ramp = Fx.fade_ramp(color, Color(color, 0))
	var mote_mesh := QuadMesh.new()
	mote_mesh.size = Vector2.ONE * 0.08
	_add_trail(Fx.particles(48, 0.35, motes, mote_mesh, Fx.glow(Color.WHITE, BaseMaterial3D.BILLBOARD_PARTICLES, Fx.soft_dot())))

	var flecks: ParticleProcessMaterial = motes.duplicate()
	flecks.color_ramp = Fx.fade_ramp(Color(0, 0, 0, 1), Color(0, 0, 0, 0))
	flecks.particle_flag_align_y = true
	_add_trail(Fx.particles(24, 0.5, flecks, Fx.chip(0.006, 0.03), Fx.ink(Color.WHITE)))


func _add_trail(p: GPUParticles3D) -> void:
	p.local_coords = false
	add_child(p)
	_trail.append(p)


func _physics_process(delta):
	if _done:
		return
	var step: Vector3 = velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_burst(hit.position, hit.normal, hit.collider)
		return
	global_position += step
	_travelled += step.length()
	if _travelled > max_distance:
		_burst(global_position, -velocity.normalized())


func _burst(at: Vector3, normal: Vector3, collider: Object = null) -> void:
	_done = true
	global_position = at
	_core.visible = false
	_light.visible = false
	for p in _trail:
		p.emitting = false
	var impact: Node3D = Impact.new()
	get_parent().add_child(impact)
	impact.play(at, normal, strength, color)
	if on_hit.is_valid():
		on_hit.call(at, strength, collider)
	get_tree().create_timer(0.6).timeout.connect(queue_free)
