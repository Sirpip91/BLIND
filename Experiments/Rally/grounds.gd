extends Node3D

## The clearing: open floor in the middle, everything else around the edge.

const Shapes = preload("res://Experiments/Rally/shapes.gd")

@export var clear_radius := 10.5
@export var stalk_count := 130
@export var tuft_count := 80

var _rng := RandomNumberGenerator.new()


func _ready():
	_rng.seed = 11
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	_add(plane, Shapes.grey(0.95), Transform3D())
	for i in 9:
		var angle := TAU * i / 9.0 + _rng.randf_range(-0.2, 0.2)
		var far := _rng.randf_range(150.0, 230.0)
		_add(Shapes.hill(_rng.randf_range(50.0, 85.0), _rng.randf_range(30.0, 60.0)), Shapes.grey(0.05),
				Transform3D(Basis(), Vector3(sin(angle) * far, -2.0, cos(angle) * far)))
	_bamboo()
	_tufts()


func _bamboo() -> void:
	var leaves: Array[Transform3D] = []
	for i in stalk_count:
		var at := _around(clear_radius + 1.2, clear_radius + 13.0)
		var height := _rng.randf_range(6.0, 10.0)
		var lean := Vector3(_rng.randf_range(-0.06, 0.06), 1.0, _rng.randf_range(-0.06, 0.06)).normalized()
		_add(Shapes.stalk(height, _rng.randf_range(0.035, 0.075)), Shapes.grey(_rng.randf_range(0.015, 0.06)),
				Transform3D(Basis(Quaternion(Vector3.UP, lean)), at))
		for cluster in _rng.randi_range(7, 13):
			var from := at + lean * height * _rng.randf_range(0.35, 1.0)
			from += Vector3(_rng.randfn(0.0, 0.35), 0.0, _rng.randfn(0.0, 0.35))
			var facing := _rng.randf() * TAU
			for l in _rng.randi_range(3, 6):
				var turn := Basis(Vector3.UP, facing + _rng.randf_range(-1.6, 1.6))
				var droop := Basis(Vector3.RIGHT, _rng.randf_range(1.7, 2.6))
				leaves.append(Transform3D((turn * droop).scaled_local(Vector3.ONE * _rng.randf_range(0.8, 1.6)), from))
	_scatter(Shapes.blade(0.3, 0.024, 0.2, 5), leaves, Shapes.grey(0.04, true))


func _tufts() -> void:
	var blades: Array[Transform3D] = []
	for i in tuft_count:
		var at := _around(clear_radius - 0.6, clear_radius + 5.0)
		for b in 30:
			var turn := Basis(Vector3.UP, _rng.randf() * TAU)
			var droop := Basis(Vector3.RIGHT, _rng.randf_range(0.15, 0.9))
			var spot := at + Vector3(_rng.randfn(0.0, 0.25), 0.0, _rng.randfn(0.0, 0.25))
			blades.append(Transform3D((turn * droop).scaled_local(Vector3.ONE * _rng.randf_range(0.6, 1.3)), spot))
	_scatter(Shapes.blade(0.6, 0.017, 0.55, 6), blades, Shapes.grey(0.03, true))


func _around(near: float, far: float) -> Vector3:
	var angle := _rng.randf() * TAU
	var radius := _rng.randf_range(near, far)
	return Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)


func _add(mesh: Mesh, material: Material, at: Transform3D) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = at
	add_child(node)


func _scatter(mesh: Mesh, where: Array[Transform3D], material: Material) -> void:
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = mesh
	many.instance_count = where.size()
	for i in where.size():
		many.set_instance_transform(i, where[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = many
	node.material_override = material
	add_child(node)
