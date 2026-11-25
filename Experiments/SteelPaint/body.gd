extends Node3D

## A stand-in body to be replaced by a real one, built the way the real one
## has to be: separate closed parts, met at the joints, any of which can come
## off. It exists to make the sword readable, and to be cut.

const Shapes = preload("res://Experiments/SteelPaint/shapes.gd")
const Part = preload("res://Experiments/SteelPaint/part.gd")
const Piece = preload("res://Experiments/SteelPaint/piece.gd")
const Region = preload("res://Experiments/SteelPaint/region.gd")
const Gash = preload("res://Experiments/SteelPaint/gash.gd")
const MASK = preload("res://Experiments/SteelPaint/mask.gdshader")

@export var robe_value := 0.035
@export var skin_value := 0.5

const SHOULDER := Vector3(0.21, 1.4, 0.02)
const HIP := Vector3(0.1, 0.9, 0.0)
const UPPER_ARM := 0.3
const FOREARM := 0.34
const THIGH := 0.46
const SHIN := 0.46
## Where each foot stands: the right leads.
const STANCE := Vector3(0.14, 0.0, -0.14)
const KNEEL := 0.4
const FACE := Vector3(0.95, 1.0, 0.75)

var parts: Array[Part] = []
var mask_on := true
## Down on its knees, whether it chose to be or not.
var kneeling := false

var _fighter: Node3D
var _torso: Node3D
var _chest: Part
var _head: Part
var _hips: Part
var _upper: Array[Part] = []
var _fore: Array[Part] = []
var _thigh: Array[Part] = []
var _shin: Array[Part] = []
var _mask: MeshInstance3D
var _feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_step: Array[float] = [1.0, 1.0]
var _twist := 0.0
var _lean := Vector2.ZERO
var _sink := 0.0
# Sideways, forward, and round, on a spring.
var _flinch := Vector3.ZERO
var _flinch_speed := Vector3.ZERO
var _time := 0.0
var _dead_for := 0.0
# The way the last cut sent it.
var _falls := 1.0


func _ready():
	var cloth := Shapes.grey(robe_value, true)
	var skin := Shapes.grey(skin_value)
	_torso = Node3D.new()
	add_child(_torso)
	_chest = _part(Part.Kind.TORSO, 0.0, [[0.0, 0.19], [0.14, 0.2], [0.34, 0.25], [0.44, 0.26], [0.53, 0.18], [0.6, 0.08]], 0.07, cloth, _torso)
	_chest.position = Vector3(0, 0.92, 0)
	# The shoulders end short of the neck.
	_chest.length = 0.5
	_chest.radius = 0.22
	_chest.set_bone(0.0)
	_chest.dress(Shapes.lathe([[0.02, 0.21], [0.11, 0.21]], 0.0), Shapes.grey(0.25, true), true)
	_hips = _part(Part.Kind.TORSO, 0.0, [[0.0, 0.13], [0.06, 0.2], [0.2, 0.19]], 0.1, cloth, _torso)
	_hips.position = Vector3(0, 0.78, 0)
	_hips.set_bone(0.0)

	_head = _part(Part.Kind.HEAD, 0.0, [[0.0, 0.07], [0.06, 0.07], [0.1, 0.12], [0.2, 0.135], [0.28, 0.11], [0.32, 0.04]], 0.0, cloth, _torso)
	_head.position = Vector3(0, 1.48, -0.02)
	_head.radius = 0.12
	_head.set_bone(0.5)
	var face := SphereMesh.new()
	face.radius = 0.115
	face.height = 0.27
	_head.dress(face, skin).transform = Transform3D(Basis.from_scale(Vector3(0.9, 0.95, 0.7)), Vector3(0, 0.17, -0.035))
	var plate := SphereMesh.new()
	plate.radius = 0.125
	plate.height = 0.29
	var material := ShaderMaterial.new()
	material.shader = MASK
	_mask = _head.dress(plate, material, true)
	_mask.transform = Transform3D(Basis.from_scale(FACE), Vector3(0, 0.17, -0.05))
	_chest.hung = [_head]
	# The legs stay with whatever's left to stand on.
	_hips.hung = [_chest]

	for side: float in [1.0, -1.0]:
		var upper := _part(Part.Kind.ARM, side, [[0.0, 0.085], [0.15, 0.1], [UPPER_ARM, 0.105]], 0.06, cloth, self)
		var fore := _part(Part.Kind.ARM, side, [[0.0, 0.1], [0.2, 0.115], [0.25, 0.1]], 0.08, cloth, self)
		fore.length = FOREARM
		var hand := SphereMesh.new()
		hand.radius = 0.05
		hand.height = 0.12
		fore.dress(hand, skin).position = Vector3(0, 0.29, 0)
		upper.hung = [fore]
		_chest.hung.append(upper)
		_upper.append(upper)
		_fore.append(fore)
		# Cut wide, like the trousers they are.
		var thigh := _part(Part.Kind.LEG, side, [[0.0, 0.14], [0.2, 0.15], [THIGH, 0.145]], 0.1, cloth, self)
		var shin := _part(Part.Kind.LEG, side, [[0.0, 0.145], [0.25, 0.16], [0.4, 0.165]], 0.12, cloth, self)
		shin.length = SHIN
		var foot := SphereMesh.new()
		foot.radius = 0.06
		foot.height = 0.1
		var shoe := shin.dress(foot, skin)
		shoe.position = Vector3(0, 0.43, -0.04)
		shoe.scale = Vector3(0.9, 1.0, 1.7)
		thigh.hung = [shin]
		_thigh.append(thigh)
		_shin.append(shin)


func setup(fighter: Node3D) -> void:
	_fighter = fighter


func reset() -> void:
	_twist = 0.0
	_lean = Vector2.ZERO
	_sink = 0.0
	_flinch = Vector3.ZERO
	_flinch_speed = Vector3.ZERO
	_dead_for = 0.0
	kneeling = false
	mask_on = true
	_mask.visible = true
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	for part in parts:
		part.restore()
	for i in 2:
		_feet[i] = _home(i)
		_foot_step[i] = 1.0


func chest_point() -> Vector3:
	return _torso.global_transform * Vector3(0, 1.25, 0)


## 0 is the right, 1 the left.
func has_arm(i: int) -> bool:
	return _upper[i].whole and _fore[i].whole


func has_leg(i: int) -> bool:
	return _thigh[i].whole and _shin[i].whole


## Thrown along a cut, given the way it travels in the attacker's view.
func flinch(direction: Vector2, strength := 1.0) -> void:
	var way := Vector3(-direction.x * 0.45, -0.28 - direction.y * 0.4, direction.x * 0.75) * strength
	# Already thrown on the frame it lands, with more to come.
	_flinch = way * 0.55
	_flinch_speed = way * 8.0
	if absf(direction.x) > 0.1:
		_falls = -signf(direction.x)


## Opened along a cut, and left that way.
func gash(part: Part, at: Vector3, travel: Vector3, from: Vector3, length: float) -> void:
	var out := from - at
	out.y = 0.0
	out = out.normalized()
	var mark := Gash.new()
	part.add_child(mark)
	mark.lay(at + out * part.radius * 0.7, out, travel, minf(length, part.length * 1.2))


func has_head() -> bool:
	return not _head.gone


## The middle of the head, which is the part that matters.
func brain_point() -> Vector3:
	return _head.start().lerp(_head.far_end(), 0.55)


## Cut along a line, anywhere at all. What's on the far side of it from the
## joint falls, and takes with it whatever it was holding up.
## "none" if the edge went by, "chip" if a piece came out of it, or "through".
func slice(part: Part, region: Region, push: Vector3) -> String:
	var keep := region.contains(part.start())
	var away: Array[Node3D] = part.cut(region, keep)
	if away.is_empty():
		return "none"
	for next: Part in part.hung:
		if region.contains(next.start()) != keep:
			next.take(away)
	var through := region.contains(part.end()) != keep
	if through:
		# As far as the first place that's gone.
		var from := part.start()
		var to := part.end()
		for i in 24:
			if region.contains(from.lerp(to, (i + 1) / 24.0)) != keep:
				part.left *= i / 24.0
				break
		part.whole = false
	var piece := Piece.new()
	get_tree().current_scene.add_child(piece)
	piece.begin(away, push)
	return "through" if through else "chip"


func drop_mask(travel: Vector3) -> void:
	if not mask_on:
		return
	mask_on = false
	_mask.visible = false
	var piece := Piece.new()
	get_tree().current_scene.add_child(piece)
	var copy := _mask.duplicate() as Node3D
	copy.transform = _mask.global_transform
	copy.visible = true
	piece.bleeds = false
	piece.begin([copy] as Array[Node3D], travel * 1.2 + Vector3.UP * 0.8)


func _physics_process(delta: float):
	if _fighter == null:
		return
	_time += delta
	var arm: Node3D = _fighter.arm
	var dead: bool = _fighter.vitals.dead
	var weary: float = _fighter.vitals.weariness()
	var local: Vector3 = _fighter.global_basis.inverse() * _fighter.velocity
	var twist := 0.0
	var lean := Vector2(local.x * 0.06, -local.z * 0.07)
	var sink := 0.02
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
			lean.y += 0.2
			quick = 5.0
		_:
			# Tired men stoop, and breathe with their shoulders.
			lean.y += 0.12 * weary + sin(_time * lerpf(1.7, 3.4, weary)) * lerpf(0.008, 0.035, weary)
	if kneeling:
		sink = KNEEL
	if dead:
		_dead_for += delta
		# Stands a moment, not yet knowing it.
		sink = maxf(KNEEL * smoothstep(0.35, 0.8, _dead_for), KNEEL if kneeling else 0.0)
		var over := pow(smoothstep(0.8, 1.6, _dead_for), 2.0)
		rotation.z = -1.45 * over * _falls
		position.y = 0.16 * over
		lean = Vector2(0.0, 0.1)
		quick = 5.0
	var follow := 1.0 - exp(-quick * delta)
	_flinch_speed += (-_flinch * 130.0 - _flinch_speed * 13.0) * delta
	_flinch += _flinch_speed * delta
	_twist = lerpf(_twist, twist, follow)
	_lean = _lean.lerp(lean, follow)
	_sink = lerpf(_sink, sink, follow)

	var tilt := _lean + Vector2(_flinch.x, _flinch.y)
	var turn := _twist + _flinch.z
	_torso.position = Vector3(tilt.x * 0.3, -_sink, -tilt.y * 0.25)
	_torso.rotation = Vector3(-tilt.y, turn, -tilt.x)
	# The head is left behind by a blow.
	_head.rotation = Vector3(tilt.y * 0.7, -_twist * 0.85 - _flinch.z * 0.45, tilt.x * 0.6)
	# The sword is carried by the body it belongs to.
	arm.get_parent().position = _torso.position + Vector3(0, 1.48, 0.1)
	for i in 2:
		_carry(i, arm, dead)
		_stand(i, delta, dead)


func _carry(i: int, arm: Node3D, dead: bool) -> void:
	var side := 1.0 if i == 0 else -1.0
	var from := _torso.transform * (SHOULDER * Vector3(side, 1, 1))
	var to := _torso.transform * Vector3(side * 0.3, 0.86, -0.08)
	if arm.visible and not dead and _holds(i):
		# The one hand left takes the sword at the guard.
		var grip := 0.02 if i == _fighter.sword_hand else -0.17
		to = global_transform.affine_inverse() * (arm.global_transform * Vector3(0.01, grip, 0.0))
	_bend(_upper[i], _fore[i], from, to, Vector3(side * 0.7, -1.0, 0.35), UPPER_ARM, FOREARM)


func _holds(i: int) -> bool:
	return i == _fighter.sword_hand or not _fighter.one_handed()


func _home(i: int) -> Vector3:
	var at := STANCE if i == 0 else -STANCE
	return _fighter.global_transform * at if _fighter else at


# Feet stay where they were put until the body has left them behind.
func _stand(i: int, delta: float, dead: bool) -> void:
	var side := 1.0 if i == 0 else -1.0
	var home: Vector3 = _home(i) + _fighter.velocity * 0.1
	if not dead:
		if _foot_step[i] >= 1.0 and _foot_step[1 - i] >= 0.6 and _feet[i].distance_to(home) > 0.2:
			_foot_step[i] = 0.0
			_foot_from[i] = _feet[i]
		if _foot_step[i] < 1.0:
			_foot_step[i] = minf(_foot_step[i] + delta / 0.2, 1.0)
			var k := _foot_step[i]
			_feet[i] = _foot_from[i].lerp(home, k * k * (3.0 - 2.0 * k)) + Vector3.UP * 0.06 * sin(PI * k)
	var from := _torso.transform * (HIP * Vector3(side, 1, 1))
	var to: Vector3 = _fighter.global_transform.affine_inverse() * _feet[i]
	# Folded under, once it's down.
	to = to.lerp(Vector3(side * 0.13, 0.0, 0.42), smoothstep(0.2, KNEEL, _sink))
	_bend(_thigh[i], _shin[i], from, to + Vector3.UP * 0.02, Vector3(side * 0.25, 0.1, -1.0), THIGH, SHIN)


# Two bones from here to there, the joint toward `pole`.
func _bend(first: Part, second: Part, from: Vector3, to: Vector3, pole: Vector3, a: float, b: float) -> void:
	var way := to - from
	var far := maxf(way.length(), 0.05)
	var stretch := maxf(1.0, far / ((a + b) * 0.995))
	a *= stretch
	b *= stretch
	far = maxf(far, absf(a - b) + 0.01)
	way = way.normalized()
	var along := (a * a - b * b + far * far) / (2.0 * far)
	var out := sqrt(maxf(a * a - along * along, 0.0))
	var bow := (pole - way * pole.dot(way)).normalized()
	var joint := from + way * along + bow * out
	first.reach(from, joint)
	second.reach(joint, to)


func _part(kind: Part.Kind, side: float, profile: Array, folds: float, material: Material, parent: Node3D) -> Part:
	var part := Part.new()
	part.kind = kind
	part.side = side
	parent.add_child(part)
	part.build(profile, folds, material)
	parts.append(part)
	return part
