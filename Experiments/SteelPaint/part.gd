extends Node3D

## One piece of a body, lying along its own +Y from the joint it hangs by.
## Whatever meshes are put under it can be cut anywhere.

const Shapes = preload("res://Experiments/SteelPaint/shapes.gd")
const Slicer = preload("res://Experiments/SteelPaint/slicer.gd")
const Region = preload("res://Experiments/SteelPaint/region.gd")
const FLESH = preload("res://Experiments/SteelPaint/flesh.gdshader")

enum Kind { HEAD, TORSO, ARM, LEG }

## What gashes are painted on and nothing else is.
const LAYER := 1 << 1

var kind := Kind.TORSO
## +1 the right of whoever's body it is, -1 the left.
var side := 0.0
## From joint to joint, whatever's been cut away.
var length := 0.3
var radius := 0.1
## What hangs from it, and goes where its joint goes.
var hung: Array[Node3D] = []
## How much is left of it, from the joint out.
var left := 1.0
## Still has its far end.
var whole := true
var gone := false

var _flesh := ShaderMaterial.new()
# Each mesh as it was before it was cut.
var _uncut := {}


func _init():
	_flesh.shader = FLESH


func build(profile: Array, folds: float, material: Material) -> void:
	length = profile[-1][0]
	radius = 0.0
	for ring: Array in profile:
		radius = maxf(radius, ring[1])
	# Closed at both ends, so a piece is solid wherever it's seen from.
	var closed := [[profile[0][0], 0.001]] + profile + [[profile[-1][0], 0.001]]
	dress(Shapes.lathe(closed, folds), material)


## Something worn rather than grown is left open where it's cut.
func dress(mesh: Mesh, material: Material, worn := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.layers |= LAYER
	node.set_meta("worn", worn)
	add_child(node)
	return node


func set_bone(amount: float) -> void:
	_flesh.set_shader_parameter("bone", amount)


## Lies between two points in the body's space, stretched if it has to.
func reach(from: Vector3, to: Vector3) -> void:
	var y := to - from
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.5:
		x = Vector3.RIGHT
	transform = Transform3D(Basis(x, y / length, x.cross(y).normalized()), from)


func start() -> Vector3:
	return global_position


func end() -> Vector3:
	return global_transform * Vector3(0, length * left, 0)


func far_end() -> Vector3:
	return global_transform * Vector3(0, length, 0)


## Cuts every mesh of it. Returns what's come away from the side of the line
## that isn't kept, as nodes placed in the world but not yet in it.
func cut(region: Region, keep_inside: bool) -> Array[Node3D]:
	var away: Array[Node3D] = []
	for child in get_children():
		if child is Decal:
			if region.contains(child.global_position) != keep_inside:
				away.append(_copied(child))
				child.queue_free()
			continue
		if not child is MeshInstance3D or not child.visible:
			continue
		var node := child as MeshInstance3D
		var halves := Slicer.carve(node, region, null if node.get_meta("worn") else _flesh)
		var kept: Mesh = halves[0 if keep_inside else 1]
		var lost: Mesh = halves[1 if keep_inside else 0]
		if lost == null:
			continue
		var piece := MeshInstance3D.new()
		piece.mesh = lost
		piece.layers = node.layers
		piece.transform = node.global_transform
		away.append(piece)
		_remember(node)
		node.visible = kept != null
		if kept:
			node.mesh = kept
			node.material_override = null
	return away


## Comes away whole, with everything hung from it.
func take(away: Array[Node3D]) -> void:
	if gone:
		return
	for child in get_children():
		if (child is MeshInstance3D and child.visible) or child is Decal:
			away.append(_copied(child))
	gone = true
	whole = false
	visible = false
	for next in hung:
		next.take(away)


func restore() -> void:
	left = 1.0
	whole = true
	gone = false
	visible = true
	for node: MeshInstance3D in _uncut:
		node.mesh = _uncut[node][0]
		node.material_override = _uncut[node][1]
		node.visible = true
	_uncut.clear()
	for child in get_children():
		if child is Decal:
			child.queue_free()


func _remember(node: MeshInstance3D) -> void:
	if not _uncut.has(node):
		_uncut[node] = [node.mesh, node.material_override]


func _copied(node: Node3D) -> Node3D:
	var copy := node.duplicate() as Node3D
	copy.transform = node.global_transform
	return copy
