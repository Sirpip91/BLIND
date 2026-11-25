extends Node3D

## Grey placeholder shapes for judging the wash pass: a bamboo path, a
## swordsman, hills. B swaps between the wash and the current ink look.

@export var wash: MeshInstance3D
@export var ink: MeshInstance3D
@export var stalk_count := 130
@export var tuft_count := 150

var _rng := RandomNumberGenerator.new()


func _ready():
	_rng.seed = 7
	_build_ground()
	_build_bamboo()
	_build_tufts()
	_build_hills()
	_build_swordsman(Vector3(0.3, 0.0, -6.5), PI)
	_build_splash(Vector3(0.7, 0.02, -6.1))


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		wash.visible = not wash.visible
		ink.visible = not wash.visible


func _grey(value: float, two_sided := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(value, value, value)
	material.roughness = 1.0
	material.metallic_specular = 0.0
	if two_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _add(mesh: Mesh, material: Material, at: Transform3D, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = at
	parent.add_child(node)
	return node


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	_add(plane, _grey(0.95), Transform3D())
	for i in 60:
		var side := -1.0 if i % 2 else 1.0
		var mound := SphereMesh.new()
		mound.radius = 1.0
		mound.height = 2.0
		var size := Vector3(_rng.randf_range(0.5, 1.3), _rng.randf_range(0.2, 0.5), _rng.randf_range(0.5, 1.2))
		var at := Vector3(side * _rng.randf_range(2.6, 6.5), -0.05, _rng.randf_range(-30.0, 4.0))
		_add(mound, _grey(_rng.randf_range(0.03, 0.12)), Transform3D(Basis.from_scale(size), at))


func _build_bamboo() -> void:
	var leaf := _blade(0.3, 0.024, 0.2, 5)
	var leaves: Array[Transform3D] = []
	for i in stalk_count:
		var side := -1.0 if i % 2 else 1.0
		var at := Vector3(side * _rng.randf_range(2.2, 13.0), 0.0, _rng.randf_range(-38.0, 5.0))
		var height := _rng.randf_range(6.0, 10.0)
		var lean := Vector3(_rng.randf_range(-0.06, 0.06), 1.0, _rng.randf_range(-0.06, 0.06)).normalized()
		_add(_stalk(height, _rng.randf_range(0.035, 0.075)), _grey(_rng.randf_range(0.015, 0.06)),
				Transform3D(Basis(Quaternion(Vector3.UP, lean)), at))
		for cluster in _rng.randi_range(9, 16):
			var from := at + lean * height * _rng.randf_range(0.35, 1.0)
			from += Vector3(_rng.randfn(0.0, 0.35), 0.0, _rng.randfn(0.0, 0.35))
			var facing := _rng.randf() * TAU
			for l in _rng.randi_range(3, 6):
				var turn := Basis(Vector3.UP, facing + _rng.randf_range(-1.6, 1.6))
				var droop := Basis(Vector3.RIGHT, _rng.randf_range(1.7, 2.6))
				leaves.append(Transform3D((turn * droop).scaled_local(Vector3.ONE * _rng.randf_range(0.8, 1.6)), from))
	_scatter(leaf, leaves, _grey(0.04, true))


func _build_tufts() -> void:
	var blade := _blade(0.6, 0.017, 0.55, 6)
	var blades: Array[Transform3D] = []
	for i in tuft_count:
		var side := -1.0 if i % 2 else 1.0
		var at := Vector3(side * _rng.randf_range(1.7, 6.0), 0.0, _rng.randf_range(-26.0, 4.0))
		for b in 34:
			var turn := Basis(Vector3.UP, _rng.randf() * TAU)
			var droop := Basis(Vector3.RIGHT, _rng.randf_range(0.15, 0.9))
			var spot := at + Vector3(_rng.randfn(0.0, 0.25), 0.0, _rng.randfn(0.0, 0.25))
			blades.append(Transform3D((turn * droop).scaled_local(Vector3.ONE * _rng.randf_range(0.6, 1.3)), spot))
	_scatter(blade, blades, _grey(0.03, true))


func _build_hills() -> void:
	for hill: Array in [[-60.0, -170.0, 60.0, 46.0], [35.0, -220.0, 90.0, 60.0], [110.0, -190.0, 60.0, 34.0]]:
		_add(_hill(hill[2], hill[3]), _grey(0.05), Transform3D(Basis(), Vector3(hill[0], -2.0, hill[1])))


func _build_swordsman(at: Vector3, yaw: float) -> void:
	var body := Node3D.new()
	body.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(body)
	var cloth := _grey(0.02, true)
	_add(_lathe([[0.0, 0.46], [0.25, 0.4], [0.6, 0.3], [0.95, 0.2], [1.05, 0.21], [1.3, 0.27], [1.45, 0.24], [1.52, 0.1]], 0.16), cloth, Transform3D(), body)
	_add(_lathe([[1.5, 0.08], [1.58, 0.1], [1.7, 0.1], [1.78, 0.0]], 0.0), cloth, Transform3D(), body)
	_add(_lathe([[1.64, 0.42], [1.7, 0.3], [1.8, 0.12], [1.88, 0.03], [1.95, 0.0]], 0.03), _grey(0.12, true), Transform3D(), body)
	for side: float in [-1.0, 1.0]:
		var arm := Transform3D(Basis(Vector3.FORWARD, -side * 0.22), Vector3(side * 0.4, 0.74, 0.0))
		_add(_lathe([[0.0, 0.14], [0.3, 0.11], [0.62, 0.08]], 0.1), cloth, arm, body)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.02, 0.95, 0.035)
	_add(blade, _grey(0.02), Transform3D(Basis(Vector3(0.2, 0.0, 1.0).normalized(), -0.75), Vector3(-0.75, 0.42, 0.15)), body)


func _build_splash(at: Vector3) -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.03, 0.03)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 46:
		var disc := CylinderMesh.new()
		var away := absf(_rng.randfn(0.0, 0.5))
		disc.top_radius = maxf(0.012, 0.16 * exp(-away * 3.5) * _rng.randf_range(0.4, 1.0))
		disc.bottom_radius = disc.top_radius
		disc.height = 0.004
		var turn := _rng.randf() * TAU
		_add(disc, red, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, _rng.randf_range(0.5, 1.0))), at + Vector3(cos(turn), 0.0, sin(turn)) * away))


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


# One brush stroke of a leaf: swells, then runs out to a point.
func _blade(length: float, width: float, curl: float, parts: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in parts + 1:
		var t := float(i) / parts
		var w := width * sin(PI * pow(t, 0.6)) + 0.002 * (1.0 - t)
		var at := Vector3(0.0, length * t, curl * length * t * t)
		for side: float in [-1.0, 1.0]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(at + Vector3(side * w, 0.0, 0.0))
	return st.commit()


# Swells slightly at every joint.
func _stalk(height: float, radius: float) -> ArrayMesh:
	var profile := []
	var y := 0.0
	while y < height:
		var r := radius * (1.0 - 0.6 * y / height)
		profile.append_array([[y, r * 0.8], [y + 0.02, r * 1.25], [y + 0.05, r]])
		y += 0.42
	profile.append([height + 0.1, 0.004])
	return _lathe(profile, 0.0, 8)


# Profile of [height, radius] rings, with folds pressed in for cloth.
func _lathe(profile: Array, folds: float, sides := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		for s in sides:
			var corners: Array[Vector3] = []
			for c: Array in [[i, s], [i + 1, s], [i + 1, s + 1], [i, s + 1]]:
				var ring: Array = profile[c[0]]
				var angle: float = TAU * (int(c[1]) % sides) / sides
				var r: float = ring[1] * (1.0 + folds * sin(angle * 7.0) * cos(angle * 3.0 + 1.0))
				corners.append(Vector3(cos(angle) * r, ring[0], sin(angle) * r))
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(corners[k])
	st.generate_normals()
	return st.commit()


func _hill(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = int(width + height)
	noise.frequency = 0.03
	var cells := 48
	for x in cells:
		for z in cells:
			for c: Array in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var p := Vector2(float(x + c[0]) / cells - 0.5, float(z + c[1]) / cells - 0.5) * 2.0 * width
				var up := height * pow(maxf(0.0, 1.0 - p.length() / width), 1.35)
				up *= 1.0 + 0.45 * noise.get_noise_2dv(p)
				st.add_vertex(Vector3(p.x, up, p.y))
	st.generate_normals()
	return st.commit()
