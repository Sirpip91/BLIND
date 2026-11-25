extends Node3D

## A rigged model standing in for a body: its bones are put wherever the body
## says its chest, hands and feet are. Wants Unreal's bone names and a T-pose.

const Skinned = preload("res://Experiments/Arena/cutting/skinned.gd")
const Part = preload("res://Experiments/Arena/foe/part.gd")
const Region = preload("res://Experiments/Arena/cutting/region.gd")
const FLESH = preload("res://Experiments/Arena/cutting/flesh.gdshader")
const SKIN = preload("res://Experiments/Arena/foe/figure.gdshader")

## Knees never quite straight.
const CROUCH := 0.06
const FINGERS := ["index", "middle", "ring", "pinky"]
## Where a hilt lies in a hand: along it, and into the palm.
const PALM := Vector2(0.085, 0.028)
## How far an arm can be drawn out before it's let go of what it's reaching for.
const DRAWN := 1.12

# Models already taken in, so a crowd is only worked out once.
static var _ready_made := {}

var skeleton: Skeleton3D

var _skinned: RefCounted
var _whole: RefCounted
var _mesh: MeshInstance3D
var _uncut: Mesh
# The model faces +Z; everything here faces -Z.
var _turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
var _ids := {}
# Where each bone rests and where it's been put, in the body's space.
var _rest: Array[Transform3D] = []
var _turned := {}
var _placed := {}
var _order := PackedInt32Array()
var _was: Array[Transform3D] = []
var _now: Array[Transform3D] = []
var _swing := 0.0
var _grip: Array[float] = [-1.0, -1.0]
var _parts: Array[Part] = []
var _trunk := []


func _init():
	# Last tick's pose is put away before the body sets this one's.
	process_physics_priority = -10


## `inked` turns a material the model came with into what it's drawn with.
func build(model: PackedScene, extras: Array[PackedScene], parts: Array[Part], owner_names: Dictionary, inked: Callable, look: Array) -> void:
	_parts = parts
	_trunk = [owner_names["pelvis"], owner_names["spine_01"]]
	transform = _turn
	var scene := model.instantiate()
	skeleton = scene.find_children("*", "Skeleton3D", true, false)[0]
	skeleton.get_parent().remove_child(skeleton)
	skeleton.owner = null
	add_child(skeleton)
	for b in skeleton.get_bone_count():
		_ids[skeleton.get_bone_name(b)] = b
		_rest.append(_turn * skeleton.get_bone_global_rest(b))
	var meshes: Array[MeshInstance3D] = []
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	var others: Array[Node] = [scene]
	for extra in extras:
		others.append(extra.instantiate())
		for node in others[-1].find_children("*", "MeshInstance3D", true, false):
			meshes.append(node)
	var key := [model, extras, look]
	if not _ready_made.has(key):
		var taken := Skinned.new()
		# The hips go as far down as the legs part.
		var lids := {}
		for s: String in ["_r", "_l"]:
			lids[_mesh_of(owner_names["thigh" + s])] = [_at("thigh" + s).y - 0.1, _mesh_of(owner_names["pelvis"])]
		var flesh := ShaderMaterial.new()
		flesh.shader = FLESH
		flesh.set_shader_parameter("bone", 0.15)
		if look[-1]:
			flesh.set_shader_parameter("red", Color(0.02, 0.02, 0.025))
			flesh.set_shader_parameter("pale", Color(0.3, 0.3, 0.3))
		taken.take_in(meshes, skeleton, _owners(owner_names), lids, func(material: Material): return _dressed(material, inked), flesh)
		_ready_made[key] = [taken, taken.mesh()]
	_whole = _ready_made[key][0]
	_skinned = _whole
	for node in skeleton.get_children():
		node.free()
	for other in others:
		other.free()
	_mesh = MeshInstance3D.new()
	_uncut = _ready_made[key][1]
	_mesh.mesh = _uncut
	_mesh.skin = _whole.skin
	_mesh.layers |= Part.LAYER
	# Its arms go a long way from where they rest.
	_mesh.extra_cull_margin = 1.5
	skeleton.add_child(_mesh)
	_mesh.skeleton = NodePath("..")


func restore() -> void:
	_skinned = _whole
	_mesh.mesh = _uncut
	_was.clear()
	_now.clear()


func _dressed(material: Material, inked: Callable) -> Material:
	var cloth: Material = inked.call(material.resource_name)
	if cloth:
		cloth.set_meta("hollow", true)
		return cloth
	var skin := ShaderMaterial.new()
	skin.shader = SKIN
	if material is BaseMaterial3D:
		skin.set_shader_parameter("painting", material.albedo_texture)
		if "Eye" in material.resource_name:
			skin.set_shader_parameter("light", 0.95)
		elif "Hair" in material.resource_name:
			skin.set_shader_parameter("light", 0.06)
	return skin


func _owners(names: Dictionary) -> PackedByteArray:
	var owners := PackedByteArray()
	for b in skeleton.get_bone_count():
		var at := b
		while at >= 0 and not names.has(skeleton.get_bone_name(at)):
			at = skeleton.get_bone_parent(at)
		owners.append(_mesh_of(names[skeleton.get_bone_name(at)] if at >= 0 else names["pelvis"]))
	return owners


# Hips and chest are cut as one, wherever the line between them falls.
func _mesh_of(part: Part) -> int:
	return _parts.find(_trunk[1] if part in _trunk else part)


## Cut along a line. What came away, in the world; empty if nothing did.
func sever(part: Part, taken: Array[Part], region: Region, keep_inside: bool) -> Array[Node3D]:
	var flags := PackedByteArray()
	flags.resize(_parts.size())
	for each in taken:
		flags[_mesh_of(each)] = 1
	var pose: Array[Transform3D] = []
	var space := get_parent_node_3d().global_transform * _turn
	for i in _now.size():
		skeleton.set_bone_pose(_order[i], _now[i])
	for b in skeleton.get_bone_count():
		pose.append(space * skeleton.get_bone_global_pose(b) * skeleton.get_bone_global_rest(b).affine_inverse())
	var cut: RefCounted = _skinned.copy()
	var away: Array[Node3D] = []
	away.assign(cut.sever(_mesh_of(part), flags, region, keep_inside, pose))
	if away.is_empty():
		return away
	_skinned = cut
	_mesh.mesh = cut.mesh()
	for piece: MeshInstance3D in away:
		piece.layers = _mesh.layers
	return away


## Everything in the body's space. `hands` are the hilt each is on, or only a
## place to hang. Feet are where the soles go, with how far each is through a
## step, and `down` is how far it's on its knees.
func pose(torso: Transform3D, look: Basis, hands: Array, holding: Array[bool], feet: Array[Vector3], steps: Array[float], down: float, breath: float) -> void:
	_placed.clear()
	var turn := torso.basis.get_rotation_quaternion()
	var hips := torso * _at("pelvis") - Vector3.UP * CROUCH * (1.0 - down)
	var hip_turn := Quaternion().slerp(turn, 0.35)
	# Never so high that a foot can't reach the ground.
	for i in 2:
		var side: String = ["r", "l"][i]
		var hip := hips + hip_turn * (_at("thigh_" + side) - _at("pelvis"))
		var ankle := _ankle(i, feet[i])
		var leg := (_length("thigh_" + side, "calf_" + side) + _length("calf_" + side, "foot_" + side)) * 0.995
		var out := Vector2(hip.x - ankle.x, hip.z - ankle.z).length()
		hips.y -= maxf(hip.y - ankle.y - sqrt(maxf(leg * leg - out * out, 0.0)), 0.0)
	_put("pelvis", hip_turn, hips)
	_follow("spine_01", "pelvis", Quaternion().slerp(turn, 0.55))
	# Two hands on something to one side bring the shoulders round to it.
	var round_to := 0.0
	if holding[0] and holding[1]:
		var middle: Vector3 = (hands[0].origin + hands[1].origin) * 0.5 - point("spine_01")
		round_to = clampf(-middle.x * 1.5, -0.55, 0.55)
	_swing = lerpf(_swing, round_to, 0.2)
	_follow("spine_02", "spine_01", Quaternion(Vector3.UP, _swing * 0.5) * Quaternion().slerp(turn, 0.8) * Quaternion(Vector3.RIGHT, breath * 0.5))
	_follow("spine_03", "spine_02", Quaternion(Vector3.UP, _swing) * turn * Quaternion(Vector3.RIGHT, breath))
	var facing := (torso.basis * look).get_rotation_quaternion()
	_follow("neck_01", "spine_03", turn.slerp(facing, 0.5))
	_follow("Head", "neck_01", facing)
	for i in 2:
		_reach(i, hands[i], holding[i])
		_stand(i, feet[i], steps[i], down)
	_settle()


func lie_at_rest() -> void:
	for bone: String in _ids:
		_put(bone, Quaternion(), _at(bone))


func point(bone: String) -> Vector3:
	return _placed[_ids[bone]]


func turned(bone: String) -> Quaternion:
	return _turned[_ids[bone]]


func rest(bone: String) -> Vector3:
	return _at(bone)


func _reach(i: int, to: Transform3D, held: bool) -> void:
	var s: String = ["_r", "_l"][i]
	var side := 1.0 if i == 0 else -1.0
	var chest := turned("spine_03")
	# The shoulder goes some of the way with it.
	var from := point("spine_03") + chest * (_at("clavicle" + s) - _at("spine_03"))
	var rests := chest * (_at("upperarm" + s) - _at("clavicle" + s))
	var along := Quaternion(rests.normalized(), (to.origin - from).normalized())
	var shrug := Quaternion().slerp(along, clampf(0.2 * along.get_angle(), 0.0, 0.4) / maxf(along.get_angle(), 0.01))
	_put("clavicle" + s, shrug * chest, from)
	var shoulder := from + shrug * rests

	var along_hand := (_at("middle_01" + s) - _at("hand" + s)).normalized()
	var across := _at("index_01" + s) - _at("pinky_01" + s)
	var hand_frame := _frame(along_hand, across)
	var palm := hand_frame.z * -side
	var upper := _length("upperarm" + s, "lowerarm" + s)
	var fore := _length("lowerarm" + s, "hand" + s)
	# The elbow stays out in front of the ribs when it reaches across them.
	var across_by := clampf((shoulder.x - to.origin.x) * side * 3.0 - 0.3, 0.0, 1.0)
	var pole := Vector3(side * 0.75, -1.0, 0.3).lerp(Vector3(side * 1.3, -0.5, -0.5), across_by)
	var wrist := to.origin
	var hand := Quaternion()
	var elbow := _joint(shoulder, wrist, pole, upper, fore)
	for pass_ in 3:
		var way := (wrist - elbow).normalized()
		if held:
			# The fist closes square on the hilt, as far as a wrist will let it.
			var hilt := to.basis.y.normalized()
			var lean := clampf(way.dot(hilt), -0.5, 0.5)
			var flat := (way - hilt * way.dot(hilt)).normalized()
			var fist := (flat * sqrt(1.0 - lean * lean) + hilt * lean).normalized()
			hand = (_frame(fist, hilt) * hand_frame.inverse()).get_rotation_quaternion()
			wrist = to.origin - hand * (along_hand * PALM.x + palm * PALM.y)
		else:
			hand = (_frame(way, Vector3(-side * 0.3, 0.2, -1.0)) * hand_frame.inverse()).get_rotation_quaternion()
		elbow = _joint(shoulder, wrist, pole, upper, fore)
	var bow := elbow - shoulder
	bow -= (wrist - shoulder) * bow.dot(wrist - shoulder) / maxf((wrist - shoulder).length_squared(), 0.001)
	if bow.length() < 0.005:
		bow = pole
	var back := Vector3.BACK
	var upper_turn := (_frame(elbow - shoulder, bow) * _frame(_at("lowerarm" + s) - _at("upperarm" + s), back).inverse()).get_rotation_quaternion()
	var fore_rest := (_at("hand" + s) - _at("lowerarm" + s)).normalized()
	var fore_turn := (_frame(wrist - elbow, bow) * _frame(fore_rest, back).inverse()).get_rotation_quaternion()
	# Half of any turn of the wrist is made by the forearm.
	var twist := fore_turn.inverse() * hand
	var angle := wrapf(2.0 * atan2(Vector3(twist.x, twist.y, twist.z).dot(fore_rest), twist.w), -PI, PI)
	_put("upperarm" + s, upper_turn, shoulder)
	_put("lowerarm" + s, fore_turn * Quaternion(fore_rest, angle * 0.6), elbow)
	_put("hand" + s, hand, wrist)
	_close_hand(i, 1.0 if held else 0.3)


func _stand(i: int, sole: Vector3, step: float, down: float) -> void:
	var s: String = ["_r", "_l"][i]
	var side := 1.0 if i == 0 else -1.0
	var hip := point("pelvis") + turned("pelvis") * (_at("thigh" + s) - _at("pelvis"))
	var ankle := _ankle(i, sole)
	var thigh := _length("thigh" + s, "calf" + s)
	var shin := _length("calf" + s, "foot" + s)
	# Over the foot, which is turned out.
	var pole := Vector3(side * (0.15 if i == 0 else 0.5), 0.1, -1.0)
	var knee := _joint(hip, ankle, pole, thigh, shin)
	ankle = knee + (ankle - knee).normalized() * shin
	var forward := Vector3.FORWARD
	_put("thigh" + s, (_frame(knee - hip, pole) * _frame(_at("calf" + s) - _at("thigh" + s), forward).inverse()).get_rotation_quaternion(), hip)
	var shin_turn := (_frame(ankle - knee, pole) * _frame(_at("foot" + s) - _at("calf" + s), forward).inverse()).get_rotation_quaternion()
	_put("calf" + s, shin_turn, knee)
	var lift := sin(PI * clampf(step, 0.0, 1.0)) if step < 1.0 else 0.0
	var flat := Quaternion(Vector3.UP, -side * (0.1 if i == 0 else 0.55)) * Quaternion(Vector3.RIGHT, -0.4 * lift)
	_put("foot" + s, flat.slerp(shin_turn * Quaternion(Vector3.RIGHT, -0.9), down), ankle)
	_follow("ball" + s, "foot" + s, turned("foot" + s))


func _ankle(i: int, sole: Vector3) -> Vector3:
	var s: String = ["_r", "_l"][i]
	return sole + Vector3(0.0, _at("foot" + s).y, 0.07)


# Two bones from here to there, the joint toward `pole`.
static func _joint(from: Vector3, to: Vector3, pole: Vector3, a: float, b: float) -> Vector3:
	var way := to - from
	var far := clampf(way.length(), absf(a - b) + 0.01, (a + b) * DRAWN)
	var stretch := maxf(1.0, far / ((a + b) * 0.998))
	a *= stretch
	b *= stretch
	way = way.normalized()
	var along := (a * a - b * b + far * far) / (2.0 * far)
	var bow := (pole - way * pole.dot(way)).normalized()
	return from + way * along + bow * sqrt(maxf(a * a - along * along, 0.0))


func _close_hand(i: int, grip: float) -> void:
	if _grip[i] == grip:
		return
	_grip[i] = grip
	var s: String = ["_r", "_l"][i]
	var side := 1.0 if i == 0 else -1.0
	var along := (_at("middle_01" + s) - _at("hand" + s)).normalized()
	var frame := _frame(along, _at("index_01" + s) - _at("pinky_01" + s))
	var palm := frame.z * -side
	var axis := along.cross(palm).normalized()
	for finger: String in FINGERS:
		for k in 3:
			_curl("%s_0%d%s" % [finger, k + 1, s], axis, [1.25, 1.5, 1.0][k] * grip)
	for k in 2:
		_curl("thumb_0%d%s" % [k + 1, s], (along * 0.8 + axis * 0.6).normalized(), [0.35, 0.5][k] * grip)


func _curl(bone: String, axis: Vector3, angle: float) -> void:
	var b: int = _ids[bone]
	var own := _rest[b].basis.get_rotation_quaternion().inverse() * axis
	skeleton.set_bone_pose_rotation(b, skeleton.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(own.normalized(), angle))


func _at(bone: String) -> Vector3:
	return _rest[_ids[bone]].origin


func _length(a: String, b: String) -> float:
	return _at(a).distance_to(_at(b))


static func _frame(y: Vector3, pole: Vector3) -> Basis:
	y = y.normalized()
	var x := y.cross(pole).normalized()
	if x.length_squared() < 0.5:
		x = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
	return Basis(x, y, x.cross(y))


func _put(bone: String, turn: Quaternion, at: Vector3) -> void:
	_turned[_ids[bone]] = turn
	_placed[_ids[bone]] = at


func _follow(bone: String, parent: String, turn: Quaternion) -> void:
	_put(bone, turn, point(parent) + turned(parent) * (_at(bone) - _at(parent)))


# As poses on the skeleton, each against the one before it.
func _settle() -> void:
	if _order.is_empty():
		_order = PackedInt32Array(_placed.keys())
		_order.sort()
	var back := _turn.affine_inverse()
	var whole := {}
	_now.clear()
	for b in _order:
		whole[b] = back * Transform3D(Basis(_turned[b]) * _rest[b].basis, _placed[b])
		var parent := skeleton.get_bone_parent(b)
		var under: Transform3D = whole[parent] if whole.has(parent) else skeleton.get_bone_global_rest(parent)
		_now.append(under.affine_inverse() * whole[b])
	if _was.size() != _now.size():
		_was = _now.duplicate()


func _physics_process(_delta: float):
	if not _now.is_empty():
		_was = _now.duplicate()


# Between ticks, like everything else.
func _process(_delta: float):
	var k := Engine.get_physics_interpolation_fraction()
	for i in _now.size():
		if _was[i] == _now[i]:
			skeleton.set_bone_pose(_order[i], _now[i])
		else:
			skeleton.set_bone_pose(_order[i], _was[i].interpolate_with(_now[i], k))
