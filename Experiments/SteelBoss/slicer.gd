extends RefCounted

## Cuts any mesh in two, along one plane or a bent line of them, and closes
## both halves. Knows nothing of bodies: give it a mesh and where the edge went.

const Region = preload("res://Experiments/SteelBoss/region.gd")

## How near two points have to be to be the same point of a wound, in metres.
const WELD := 0.0005


## What's inside a region and what's out of it, as [inside, outside]. Either is
## null if nothing's there. With no
## `flesh` the cut is left open, as a hollow thing should be.
static func carve(node: MeshInstance3D, region: Region, flesh: Material) -> Array:
	var whole := ArrayMesh.new()
	for s in node.mesh.get_surface_count():
		whole.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, node.mesh.surface_get_arrays(s))
		whole.surface_set_material(s, node.get_active_material(s))
	var inside: Array[Mesh] = []
	var outside: Array[Mesh] = []
	_share(whole, _into(node.global_transform, region.planes[0]), flesh, inside, outside)
	for i in range(1, region.planes.size()):
		var plane := _into(node.global_transform, region.planes[i])
		var before: Array[Mesh] = (inside if region.both[i - 1] else outside).duplicate()
		(inside if region.both[i - 1] else outside).clear()
		for mesh in before:
			_share(mesh, plane, flesh, inside, outside)
	return [_joined(inside), _joined(outside)]


static func _share(mesh: Mesh, plane: Plane, flesh: Material, over: Array[Mesh], under: Array[Mesh]) -> void:
	var halves := slice(mesh, plane, flesh)
	if halves[0]:
		over.append(halves[0])
	if halves[1]:
		under.append(halves[1])


static func _joined(meshes: Array[Mesh]) -> Mesh:
	if meshes.size() < 2:
		return null if meshes.is_empty() else meshes[0]
	var one := ArrayMesh.new()
	for mesh in meshes:
		for s in mesh.get_surface_count():
			one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
			one.surface_set_material(one.get_surface_count() - 1, mesh.surface_get_material(s))
	return one


# Through points, so it holds however the mesh is stretched.
static func _into(space: Transform3D, plane: Plane) -> Plane:
	var back := space.affine_inverse()
	var at := plane.get_center()
	var u := plane.normal.cross(Vector3.UP if absf(plane.normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var local := Plane(back * at, back * (at + u), back * (at + plane.normal.cross(u)))
	return local if local.is_point_over(back * (at + plane.normal)) else -local


## The halves either side of a plane in the mesh's own space, [over, under].
static func slice(mesh: Mesh, plane: Plane, flesh: Material) -> Array:
	var halves: Array[ArrayMesh] = [ArrayMesh.new(), ArrayMesh.new()]
	var rim: Array[PackedVector3Array] = []
	for s in mesh.get_surface_count():
		var sides := [Half.new(), Half.new()]
		_split(mesh.surface_get_arrays(s), plane, sides, rim)
		for i in 2:
			sides[i].commit(halves[i], mesh.surface_get_material(s))
	if flesh:
		var loops := _loops(rim)
		for i in 2:
			if halves[i].get_surface_count() > 0:
				_close(loops, plane.normal * (-1.0 if i == 0 else 1.0)).commit(halves[i], flesh)
	return halves.map(func(half: ArrayMesh): return half if half.get_surface_count() > 0 else null)


## One side's worth of triangles.

class Half:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

	func add(corner: Array) -> void:
		points.append(corner[0])
		normals.append(corner[1])
		uvs.append(corner[2])

	func fan(corners: Array) -> void:
		for i in range(1, corners.size() - 1):
			add(corners[0])
			add(corners[i])
			add(corners[i + 1])

	func commit(mesh: ArrayMesh, material: Material) -> void:
		if points.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


static func _split(arrays: Array, plane: Plane, sides: Array, rim: Array[PackedVector3Array]) -> void:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var many: int = indices.size() if indices else points.size()
	for t in range(0, many - 2, 3):
		var over := []
		var under := []
		var seam := PackedVector3Array()
		var corners := []
		for c in 3:
			var i: int = indices[t + c] if indices else t + c
			corners.append([points[i], normals[i], uvs[i] if uvs else Vector2.ZERO])
		for c in 3:
			var here: Array = corners[c]
			var next: Array = corners[(c + 1) % 3]
			var a := plane.distance_to(here[0])
			var b := plane.distance_to(next[0])
			(over if a >= 0.0 else under).append(here)
			if (a >= 0.0) != (b >= 0.0):
				var between := _between(here, next, a, b)
				over.append(between)
				under.append(between)
				seam.append(between[0])
		sides[0].fan(over)
		sides[1].fan(under)
		if seam.size() == 2 and seam[0].distance_to(seam[1]) > WELD * 0.1:
			rim.append(seam)


# Worked out the same way round whichever triangle asks, so neighbours agree.
static func _between(here: Array, next: Array, a: float, b: float) -> Array:
	if next[0] < here[0]:
		return _between(next, here, b, a)
	var k := a / (a - b)
	return [here[0].lerp(next[0], k), here[1].lerp(next[1], k).normalized(), here[2].lerp(next[2], k)]


# The outlines of the wound, joined end to end.
static func _loops(rim: Array[PackedVector3Array]) -> Array[PackedVector3Array]:
	var at := {}
	for i in rim.size():
		for p in rim[i]:
			at.get_or_add(_key(p), []).append(i)
	var used := {}
	var loops: Array[PackedVector3Array] = []
	for i in rim.size():
		if used.has(i):
			continue
		used[i] = true
		var loop := PackedVector3Array([rim[i][0], rim[i][1]])
		while true:
			var found := -1
			for j: int in at.get(_key(loop[-1]), []):
				if not used.has(j):
					found = j
					break
			if found < 0:
				break
			used[found] = true
			var seam := rim[found]
			loop.append(seam[1] if _key(seam[0]) == _key(loop[-1]) else seam[0])
		if loop.size() >= 4:
			loops.append(loop)
	return loops


static func _key(p: Vector3) -> Vector3i:
	return Vector3i((p / WELD).round())


# Runs from the middle out, so its material can tell bone from skin.
static func _close(loops: Array[PackedVector3Array], normal: Vector3) -> Half:
	var half := Half.new()
	for loop in loops:
		var middle := Vector3.ZERO
		for p in loop:
			middle += p
		middle /= loop.size()
		for i in loop.size():
			half.add([middle, normal, Vector2(0, 0)])
			half.add([loop[i], normal, Vector2(1, 0)])
			half.add([loop[(i + 1) % loop.size()], normal, Vector2(1, 0)])
	return half
