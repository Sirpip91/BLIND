extends Node3D

## A stand-in body to be replaced by a real one: robe, mask, and two sleeves
## that reach for wherever the sword is. It exists to make the sword readable,
## by leaning and turning with every blow.

const Shapes = preload("res://Experiments/Duel/shapes.gd")
const Gash = preload("res://Experiments/Duel/gash.gd")
const MASK = preload("res://Experiments/Duel/mask.gdshader")

@export var robe_value := 0.035
@export var eye_color := Color(0.85, 0.05, 0.04)

const MOST_GASHES := 14
## What gashes are painted on and nothing else is.
const LAYER := 1 << 1
const SHOULDER := Vector3(0.21, 1.4, 0.02)

var _fighter: Node3D
var _torso: Node3D
var _head: Node3D
var _robe: MeshInstance3D
var _sleeves: Array[MeshInstance3D] = []
var _mask: ShaderMaterial
var _twist := 0.0
var _lean := Vector2.ZERO
var _sink := 0.0
# Sideways, forward, and round, on a spring.
var _flinch := Vector3.ZERO
var _flinch_speed := Vector3.ZERO
var _gashes: Array[Node] = []
var _walked := 0.0


func _ready():
	var cloth := Shapes.grey(robe_value, true)
	_robe = _part(Shapes.lathe([[0.0, 0.44], [0.2, 0.4], [0.55, 0.3], [0.9, 0.21], [1.0, 0.2]], 0.16), cloth, self)
	_torso = Node3D.new()
	add_child(_torso)
	_part(Shapes.lathe([[0.82, 0.2], [0.98, 0.215], [1.2, 0.27], [1.38, 0.28], [1.47, 0.2], [1.54, 0.09]], 0.07), cloth, _torso)
	_part(Shapes.lathe([[0.94, 0.225], [1.04, 0.225]], 0.0), Shapes.grey(0.25, true), _torso)
	for side: float in [1.0, -1.0]:
		var sleeve := _part(Shapes.lathe([[0.0, 0.1], [0.45, 0.115], [0.85, 0.135], [1.0, 0.05]], 0.08), cloth, self)
		_sleeves.append(sleeve)

	_head = Node3D.new()
	_head.position = Vector3(0, 1.66, -0.02)
	_torso.add_child(_head)
	var skull := SphereMesh.new()
	skull.radius = 0.135
	skull.height = 0.3
	_part(skull, cloth, _head)
	var face := SphereMesh.new()
	face.radius = 0.125
	face.height = 0.29
	_mask = ShaderMaterial.new()
	_mask.shader = MASK
	_mask.set_shader_parameter("eye_color", eye_color)
	var plate := _part(face, _mask, _head)
	plate.position = Vector3(0, -0.01, -0.045)
	plate.scale = Vector3(0.95, 1.0, 0.75)
	for side: float in [1.0, -1.0]:
		var horn := CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.026
		horn.height = 0.19
		var cone := _part(horn, Shapes.grey(0.03), _head)
		cone.position = Vector3(side * 0.075, 0.19, -0.06)
		cone.rotation = Vector3(-0.25, 0.0, -side * 0.45)


func setup(fighter: Node3D) -> void:
	_fighter = fighter
	_fighter.vitals.cracked.connect(func(_amount): _show_cracks())


func reset() -> void:
	_twist = 0.0
	_lean = Vector2.ZERO
	_sink = 0.0
	_flinch = Vector3.ZERO
	_flinch_speed = Vector3.ZERO
	for gash in _gashes:
		gash.queue_free()
	_gashes.clear()
	_mask.set_shader_parameter("cracks", 0.0)


func mask_point() -> Vector3:
	return _head.global_position


## Thrown along a cut, given the way it travels in the attacker's view.
func flinch(direction: Vector2, strength := 1.0) -> void:
	var way := Vector3(-direction.x * 0.45, -0.28 - direction.y * 0.4, direction.x * 0.75) * strength
	# Already thrown on the frame it lands, with more to come.
	_flinch = way * 0.55
	_flinch_speed = way * 8.0


## Opened along a cut, and left that way.
func gash(direction: Vector2, from: Vector3, length: float) -> void:
	var out := _torso.global_basis.inverse() * (from - global_position)
	out.y = 0.0
	var mark := Gash.new()
	_torso.add_child(mark)
	mark.lay(Vector3(0, randf_range(1.12, 1.34), 0), out.normalized(), direction, length)
	_gashes.append(mark)
	if _gashes.size() > MOST_GASHES:
		_gashes.pop_front().queue_free()


func _show_cracks() -> void:
	_mask.set_shader_parameter("cracks", _fighter.vitals.pressure / _fighter.vitals.max_pressure)


func _physics_process(delta: float):
	if _fighter == null:
		return
	var arm: Node3D = _fighter.arm
	var local: Vector3 = _fighter.global_basis.inverse() * _fighter.velocity
	var twist := 0.0
	var lean := Vector2(local.x * 0.06, -local.z * 0.07)
	var sink := 0.0
	var quick := 8.0
	var d: Vector2 = arm.strike.direction if arm.strike else Vector2.ZERO
	match arm.phase:
		arm.Phase.WINDUP:
			# Coils away from the blow: weight back, hips round.
			var k: float = arm.progress()
			twist = d.x * 0.6
			lean += Vector2(-d.x * 0.1, -0.16 + maxf(d.y, 0.0) * 0.3)
			sink = 0.07 + 0.05 * k + (0.08 if arm.strike.heavy else 0.0)
		arm.Phase.RELEASE:
			twist = -d.x * 0.65
			lean += Vector2(d.x * 0.1, 0.26)
			sink = 0.14
			quick = 20.0
		arm.Phase.RECOVER:
			twist = -d.x * 0.4
			lean += Vector2(d.x * 0.07, 0.18)
			sink = 0.1
			quick = 6.0
		arm.Phase.GUARD:
			twist = -arm.guard_side.x * 0.25
			lean.y -= 0.06
			sink = 0.05
			quick = 14.0
		arm.Phase.STAGGER:
			# Dragged round after its own sword, the other side left bare.
			lean += Vector2(arm.pushed.x * 0.16, -0.2)
			twist = -arm.pushed.x * 0.7
			quick = 14.0
		arm.Phase.BOUNCE:
			lean.y -= 0.34
			twist = d.x * 0.5
			quick = 14.0
		arm.Phase.DOWN:
			sink = 0.5 if not _fighter.vitals.dead else 0.95
			lean.y += 0.25 if not _fighter.vitals.dead else 0.9
			quick = 6.0
	var follow := 1.0 - exp(-quick * delta)
	_flinch_speed += (-_flinch * 130.0 - _flinch_speed * 13.0) * delta
	_flinch += _flinch_speed * delta
	_twist = lerpf(_twist, twist, follow)
	_lean = _lean.lerp(lean, follow)
	_sink = lerpf(_sink, sink, follow)

	_walked += Vector2(local.x, local.z).length() * delta
	var bob := sin(_walked * 5.5) * 0.02 * clampf(local.length(), 0.0, 1.0)
	_mask.set_shader_parameter("fury", move_toward(_mask.get_shader_parameter("fury") if _mask.get_shader_parameter("fury") != null else 0.0, 1.0 if _fighter.brain.fury else 0.0, delta * 2.0))
	var tilt := _lean + Vector2(_flinch.x, _flinch.y)
	var turn := _twist + _flinch.z
	position.y = bob
	_torso.position = Vector3(tilt.x * 0.3, -_sink, -tilt.y * 0.25)
	_torso.rotation = Vector3(-tilt.y, turn, -tilt.x)
	# The skirt leans with the waist, so the two never come apart.
	var waist := _torso.transform * Vector3(0, 0.96, 0)
	var spread := 1.0 + _sink * 0.35
	var hem := Basis(Vector3.UP, turn * 0.4)
	_robe.basis = Basis(hem.x * spread, waist / 0.96, hem.z * spread)
	_head.rotation = Vector3(tilt.y * 0.7, -_twist * 0.85 - _flinch.z * 0.45, tilt.x * 0.6)
	# The sword is carried by the body it belongs to.
	arm.get_parent().position = _torso.position + Vector3(0, 1.48 - tilt.y * 0.0, 0.1)
	_reach(0, SHOULDER, arm, 0.02)
	_reach(1, SHOULDER * Vector3(-1, 1, 1), arm, -0.17)


func _reach(i: int, shoulder: Vector3, arm: Node3D, along: float) -> void:
	var from := _torso.transform * shoulder
	var to := global_transform.affine_inverse() * (arm.global_transform * Vector3(0.01, along, 0.0))
	var way := to - from
	var y := way.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.UP).normalized()
	_sleeves[i].transform = Transform3D(Basis(x, y * way.length(), x.cross(y)), from)


func _part(mesh: Mesh, material: Material, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.layers |= LAYER
	parent.add_child(node)
	return node
