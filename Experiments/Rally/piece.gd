extends RigidBody3D

## Something cut off, left lying until the next duel.

const Stain = preload("res://Experiments/Rally/stain.gd")

const GROUP := "rally_remains"
## Corners its shape is worked out from, at most.
const CORNERS := 48

## Whether it has anything to bleed.
var bleeds := true


## Made of `parts`, whose transforms are where they are in the world.
func begin(parts: Array[Node3D], push: Vector3) -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 1
	mass = 3.0
	angular_damp = 1.2
	linear_damp = 0.15
	var middle := Vector3.ZERO
	var many := 0
	for part in parts:
		if part is MeshInstance3D:
			middle += part.transform * (part as MeshInstance3D).mesh.get_aabb().get_center()
			many += 1
	global_position = middle / maxi(many, 1)
	for part in parts:
		var place := global_transform.affine_inverse() * part.transform
		add_child(part)
		part.transform = place
		if part is MeshInstance3D:
			_give_shape(part)
	linear_velocity = push
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	reset_physics_interpolation()


func _give_shape(part: MeshInstance3D) -> void:
	var points := part.mesh.get_faces()
	var every := maxi(1, int(ceil(points.size() / float(CORNERS))))
	var corners := PackedVector3Array()
	for i in range(0, points.size(), every):
		corners.append(part.transform * points[i])
	if corners.size() < 4:
		return
	var shape := ConvexPolygonShape3D.new()
	shape.points = corners
	var node := CollisionShape3D.new()
	node.shape = shape
	add_child(node)


func _physics_process(_delta: float):
	if not bleeds or global_position.y > 0.3:
		return
	bleeds = false
	var stain := Stain.new()
	get_tree().current_scene.add_child(stain)
	stain.spread(global_position, randf_range(0.5, 0.75))
