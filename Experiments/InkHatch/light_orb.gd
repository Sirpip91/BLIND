extends Node3D

## A ball of light held in hand. Tap to throw a bolt; hold to charge and
## release for a beam. Both end in an impact frame.

const Fx = preload("res://Core/Combat/fx.gd")
const Bolt = preload("res://Experiments/InkHatch/light_bolt.gd")
const Impact = preload("res://Core/Combat/impact.gd")
# A variable, because reads through a const are baked in when the script
# loads and would never see the tuning panel change them.
var look: Resource = preload("res://Core/Combat/combat_look.tres")

@export var player: CharacterBody3D
@export var impact_frames: Node
@export var bolt_speed := 45.0
## Seconds of holding before a release fires a beam instead of a bolt.
@export var beam_threshold := 0.35
## Seconds of holding to reach a full charge.
@export var charge_time := 1.0
@export var beam_range := 60.0
@export var bolt_damage := 15.0
## Beam damage at no charge; a full charge adds beam_charge_damage on top.
@export var beam_damage := 30.0
@export var beam_charge_damage := 40.0
## The glow, light and everything it fires take this colour; the core stays
## white-hot and the ink flecks stay black.
@export var color := Color.WHITE:
	set(value):
		color = value
		if is_node_ready():
			_apply_color()

var _held := false
var _hold_time := 0.0
var _pending: Callable
var _orb: Node3D
var _halo: MeshInstance3D
var _motes: ParticleProcessMaterial
var _light: OmniLight3D
var _aura: Array[GPUParticles3D] = []
var _kick := 0.0


func _ready():
	_orb = Node3D.new()
	add_child(_orb)
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = core_material
	var core := MeshInstance3D.new()
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.add_child(core)

	_halo = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.16
	quad.material = Fx.glow(Color(1, 1, 1, 0.55), BaseMaterial3D.BILLBOARD_ENABLED, Fx.soft_dot())
	_halo.mesh = quad
	_orb.add_child(_halo)

	_light = OmniLight3D.new()
	_light.light_energy = 1.2
	_light.omni_range = 4.0
	_light.shadow_enabled = true
	_light.light_volumetric_fog_energy = 2.0
	_light.position = Vector3(0, 0.05, -0.1)
	_orb.add_child(_light)

	var motes := ParticleProcessMaterial.new()
	motes.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.07
	motes.direction = Vector3(0, 1, 0)
	motes.spread = 60.0
	motes.initial_velocity_min = 0.05
	motes.initial_velocity_max = 0.25
	motes.gravity = Vector3(0, 0.3, 0)
	motes.radial_accel_min = 0.2
	motes.radial_accel_max = 0.6
	motes.scale_curve = Fx.shrink_curve()
	motes.color_ramp = Fx.fade_ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	var mote_mesh := QuadMesh.new()
	mote_mesh.size = Vector2.ONE * 0.025
	_motes = motes
	_add_aura(Fx.particles(28, 0.7, motes, mote_mesh, Fx.glow(Color.WHITE, BaseMaterial3D.BILLBOARD_PARTICLES, Fx.soft_dot())))

	var flecks := Fx.streak_process(0.1, 0.35, 90.0)
	flecks.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	flecks.emission_sphere_radius = 0.09
	flecks.gravity = Vector3(0, 0.4, 0)
	flecks.color_ramp = Fx.fade_ramp(Color(0, 0, 0, 1), Color(0, 0, 0, 0))
	_add_aura(Fx.particles(16, 0.6, flecks, Fx.chip(0.002, 0.014), Fx.ink(Color.WHITE)))
	look.changed.connect(_apply_look)
	_apply_look()


func _apply_look() -> void:
	color = look.orb_color
	_apply_color()


func _apply_color() -> void:
	(_halo.mesh.material as StandardMaterial3D).albedo_color = Color(color, 0.55)
	_light.light_color = color
	_motes.color_ramp = Fx.fade_ramp(color, Color(color, 0))


func _add_aura(p: GPUParticles3D) -> void:
	_orb.add_child(p)
	_aura.append(p)


## Called by the hands with the fire button's state.
func trigger(pressed: bool) -> void:
	if pressed:
		_held = true
		_hold_time = 0.0
	elif _held:
		_held = false
		var charge := _charge()
		# Rays have to be cast during physics, so the shot waits a tick.
		_pending = _fire_beam.bind(charge) if _hold_time >= beam_threshold else _fire_bolt


## Put away mid-charge: drop the charge rather than firing it.
func holster() -> void:
	_held = false


func _charge() -> float:
	return clampf(_hold_time / charge_time, 0.0, 1.0)


func _process(delta):
	if _held:
		_hold_time += delta
		player.shake(0.004 * _charge())
	var charge := _charge() if _held else 0.0
	_kick = move_toward(_kick, 0.0, delta * 4.0)
	_orb.scale = Vector3.ONE * (1.0 + charge * 0.8 + _kick * 0.6)
	_orb.position = Vector3(0, 0, _kick * 0.12)
	_light.light_energy = 1.2 + charge * 2.5 + _kick * 4.0
	for p in _aura:
		p.speed_scale = 1.0 + charge * 3.0


func _physics_process(_delta):
	if _pending.is_valid():
		var fire := _pending
		_pending = Callable()
		fire.call()


func _aim_point(reach: float) -> Dictionary:
	var camera: Camera3D = player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit if hit else {"position": to, "normal": camera.global_basis.z}


func _fire_bolt() -> void:
	_kick = 0.6
	var target: Vector3 = _aim_point(200.0).position
	var bolt: Node3D = Bolt.new()
	bolt.velocity = (target - _orb.global_position).normalized() * bolt_speed
	var exclude: Array[RID] = [player.get_rid()]
	bolt.exclude = exclude
	bolt.color = color
	bolt.on_hit = func(at: Vector3, strength: float, collider: Object): _struck(at, strength, collider, bolt_damage)
	_effects_root().add_child(bolt)
	bolt.global_position = _orb.global_position


func _fire_beam(charge: float) -> void:
	_kick = 1.0
	var strength := 0.8 + charge * 0.6
	var hit := _aim_point(beam_range)
	var from := _orb.global_position
	var to: Vector3 = hit.position
	var root := _effects_root()

	var beam := Node3D.new()
	root.add_child(beam)
	beam.global_position = (from + to) * 0.5
	# Cylinders run along Y, so point Y down the beam.
	var along := (to - from).normalized()
	var side := along.cross(Vector3.UP if absf(along.y) < 0.95 else Vector3.RIGHT).normalized()
	beam.global_basis = Basis(side, along, side.cross(along))
	var length := from.distance_to(to)
	for layer in [[0.03 + charge * 0.03, 1.0, color.lerp(Color.WHITE, 0.5)], [0.08 + charge * 0.08, 0.2, color]]:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = layer[0]
		# Thin at the hand, full at the target: a fat end right at the camera
		# reads as a white wall rather than a beam.
		cylinder.bottom_radius = layer[0] * 0.15
		cylinder.height = length
		cylinder.radial_segments = 12
		cylinder.rings = 1
		cylinder.material = Fx.glow(Color(layer[2], layer[1]))
		var mesh := MeshInstance3D.new()
		mesh.mesh = cylinder
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_child(mesh)
	var glow := OmniLight3D.new()
	glow.light_energy = 3.0 * strength
	glow.light_color = color
	glow.omni_range = maxf(length * 0.6, 4.0)
	glow.light_volumetric_fog_energy = 3.0
	beam.add_child(glow)

	var tween := beam.create_tween().set_parallel()
	tween.tween_property(beam, "scale", Vector3(0.0, 1.0, 0.0), 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(glow, "light_energy", 0.0, 0.3)
	tween.chain().tween_callback(beam.queue_free)

	var impact: Node3D = Impact.new()
	root.add_child(impact)
	impact.play(to, hit.normal, strength, color)
	_struck(to, strength, hit.get("collider"), beam_damage + beam_charge_damage * charge)


## Shots and bursts live in the world, not on the hand, so they don't move
## with the camera once fired.
func _effects_root() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root


## Impact frames are saved for hitting something that can be hurt, so a
## stray shot into a wall stays a plain burst; full force only on a kill.
func _struck(at: Vector3, strength: float, collider: Object, damage: float) -> void:
	if collider and collider.has_method("take_hit"):
		var killed: bool = collider.take_hit(at, -player.camera.global_basis.z, color, 1.0, damage)
		impact_frames.hit(at, maxf(strength, 1.0) if killed else strength, killed, color)
