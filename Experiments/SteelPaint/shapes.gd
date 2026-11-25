extends RefCounted

## Placeholder meshes.


static func grey(value: float, two_sided := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(value, value, value)
	material.roughness = 1.0
	material.metallic_specular = 0.0
	if two_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## A profile of [height, radius] rings spun round, with folds pressed in for
## cloth.
static func lathe(profile: Array, folds: float, sides := 24) -> ArrayMesh:
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


## One brush stroke of a leaf: swells, then runs out to a point.
static func blade(length: float, width: float, curl: float, parts: int) -> ArrayMesh:
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


static func stalk(height: float, radius: float) -> ArrayMesh:
	var profile := []
	var y := 0.0
	while y < height:
		var r := radius * (1.0 - 0.6 * y / height)
		profile.append_array([[y, r * 0.8], [y + 0.02, r * 1.25], [y + 0.05, r]])
		y += 0.42
	profile.append([height + 0.1, 0.004])
	return lathe(profile, 0.0, 8)


static func hill(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = int(width + height)
	noise.frequency = 0.03
	var cells := 40
	for x in cells:
		for z in cells:
			for c: Array in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var p := Vector2(float(x + c[0]) / cells - 0.5, float(z + c[1]) / cells - 0.5) * 2.0 * width
				var up := height * pow(maxf(0.0, 1.0 - p.length() / width), 1.35)
				up *= 1.0 + 0.45 * noise.get_noise_2dv(p)
				st.add_vertex(Vector3(p.x, up, p.y))
	st.generate_normals()
	return st.commit()
