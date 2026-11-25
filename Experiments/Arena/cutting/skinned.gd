extends RefCounted

## A whole rigged model as one mesh that can be cut while it's still moving.
## What's kept goes on bending with the skeleton, cut faces and all; what's
## lost is handed back frozen as it stood.

const Region = preload("res://Experiments/Arena/cutting/region.gd")

## How near two points have to be to be the same point of a wound, in metres.
const WELD := 0.0005
## A triangle as it's passed about: three corners, its surface, and whether
## it's on the border between two parts.
const STRIDE := 5

var skin: Skin
## One for each surface. The last is the inside of things.
var materials: Array[Material] = []
## Which of those are cloth, and have no inside to show.
var hollow := PackedByteArray()

var _points := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
# Each part's own triangles.
var _triangles: Array[PackedInt32Array] = []

# While it's being cut: where each point really is, and the pose it's in.
var _posed := PackedVector3Array()
var _known := PackedByteArray()
var _pose: Array[Transform3D] = []
var _welded := {}
var _weld_ids := PackedInt32Array()
var _rim := {}


## `owner_of` gives the part each bone belongs to, `dressed` what to wear for
## each material the model came with. Whatever's above a part's `lids` height at
## rest belongs to the part given with it instead.
func take_in(meshes: Array[MeshInstance3D], skeleton: Skeleton3D, owner_of: PackedByteArray, lids: Dictionary, dressed: Callable, flesh: Material) -> void:
	skin = Skin.new()
	for b in skeleton.get_bone_count():
		skin.add_bind(b, skeleton.get_bone_global_rest(b).affine_inverse())
	for node in meshes:
		var theirs: Skeleton3D = node.get_parent()
		var bone_of := PackedInt32Array()
		for i in node.skin.get_bind_count():
			var called := String(node.skin.get_bind_name(i))
			if called.is_empty():
				called = theirs.get_bone_name(node.skin.get_bind_bone(i))
			bone_of.append(skeleton.find_bone(called))
		for s in node.mesh.get_surface_count():
			_add(node.mesh.surface_get_arrays(s), bone_of, owner_of, lids, materials.size())
			materials.append(dressed.call(node.get_active_material(s)))
			hollow.append(1 if materials[-1].has_meta("hollow") else 0)
	materials.append(flesh)
	hollow.append(0)
	_find_borders()


func copy() -> RefCounted:
	var other: RefCounted = new_one()
	other.skin = skin
	other.materials = materials
	other.hollow = hollow
	for what: String in ["_points", "_normals", "_uvs", "_bones", "_weights"]:
		other.set(what, get(what).duplicate())
	for list in _triangles:
		other._triangles.append(list.duplicate())
	return other


func new_one() -> RefCounted:
	return get_script().new()


func _add(arrays: Array, bone_of: PackedInt32Array, owner_of: PackedByteArray, lids: Dictionary, surface: int) -> void:
	var first := _points.size()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	_points.append_array(points)
	_normals.append_array(arrays[Mesh.ARRAY_NORMAL])
	_uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
	var each := bones.size() / points.size()
	for i in points.size():
		var sum := 0.0
		for k in 4:
			sum += weights[i * each + k]
		for k in 4:
			_bones.append(bone_of[bones[i * each + k]])
			_weights.append(weights[i * each + k] / sum)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0, indices.size(), 3):
		var pull := {}
		var one := PackedInt32Array()
		for c in 3:
			var i := first + indices[t + c]
			one.append(i)
			for k in 4:
				var part := owner_of[_bones[i * 4 + k]]
				pull[part] = pull.get(part, 0.0) + _weights[i * 4 + k]
		var most := -1
		for part: int in pull:
			if most < 0 or pull[part] > pull[most]:
				most = part
		if lids.has(most) and (_points[one[0]].y + _points[one[1]].y + _points[one[2]].y) / 3.0 > lids[most][0]:
			most = lids[most][1]
		one.append(surface)
		one.append(0)
		while _triangles.size() <= most:
			_triangles.append(PackedInt32Array())
		_triangles[most].append_array(one)


func _find_borders() -> void:
	var ids := {}
	var weld := PackedInt32Array()
	for p in _points:
		weld.append(ids.get_or_add(Vector3i((p / WELD).round()), ids.size()))
	var seen := {}
	for part in _triangles.size():
		for t in range(0, _triangles[part].size(), STRIDE):
			for c in 3:
				var a := weld[_triangles[part][t + c]]
				var b := weld[_triangles[part][t + (c + 1) % 3]]
				var other: Vector2i = seen.get_or_add(Vector2i(mini(a, b), maxi(a, b)), Vector2i(part, t))
				if other.x != part:
					_triangles[part][t + 4] = 1
					_triangles[other.x][other.y + 4] = 1


## Everything that's left, to be hung on the skeleton.
func mesh() -> ArrayMesh:
	var by_surface: Array[PackedInt32Array] = []
	for m in materials:
		by_surface.append(PackedInt32Array())
	for list in _triangles:
		for t in range(0, list.size(), STRIDE):
			var into := by_surface[list[t + 3]]
			into.append(list[t])
			into.append(list[t + 1])
			into.append(list[t + 2])
	var whole := ArrayMesh.new()
	for s in materials.size():
		if by_surface[s].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _points
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_BONES] = _bones
		arrays[Mesh.ARRAY_WEIGHTS] = _weights
		arrays[Mesh.ARRAY_INDEX] = by_surface[s]
		whole.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		whole.surface_set_material(whole.get_surface_count() - 1, materials[s])
	return whole


## Cuts one part along a region, and drops with it every part in `taken`.
## `pose` takes each bone's rest to where it is in the world. Returns what came
## away, one mesh to a part, where it was in the world. Empty if nothing did.
func sever(part: int, taken: PackedByteArray, region: Region, keep_inside: bool, pose: Array[Transform3D]) -> Array[MeshInstance3D]:
	_pose = pose
	_posed = PackedVector3Array()
	_posed.resize(_points.size())
	_known = PackedByteArray()
	_known.resize(_points.size())
	_weld_ids = PackedInt32Array()
	_weld_ids.resize(_points.size())
	_welded.clear()
	_rim.clear()
	var halves := _share(_triangles[part], region.planes[0])
	var inside := halves[0]
	var outside := halves[1]
	for i in range(1, region.planes.size()):
		halves = _share(inside if region.both[i - 1] else outside, region.planes[i])
		if region.both[i - 1]:
			inside = halves[0]
			outside.append_array(halves[1])
		else:
			outside = halves[1]
			inside.append_array(halves[0])
	var kept := inside if keep_inside else outside
	var lost := outside if keep_inside else inside
	if lost.is_empty():
		return []

	var rest: Array[PackedInt32Array] = []
	var falling: Array[PackedInt32Array] = []
	for each in _triangles.size():
		if each != part and not _triangles[each].is_empty():
			(falling if taken[each] else rest).append(_triangles[each])
	_close_seams(kept, rest, lost, falling)

	var pieces: Array[MeshInstance3D] = [_frozen(lost)]
	for list in falling:
		pieces.append(_frozen(list))
	_triangles[part] = kept
	for each in _triangles.size():
		if each != part and taken[each]:
			_triangles[each] = PackedInt32Array()
	return pieces


# Either side of a plane, both closed.
func _share(list: PackedInt32Array, plane: Plane) -> Array[PackedInt32Array]:
	var over := PackedInt32Array()
	var under := PackedInt32Array()
	var rim: Array[Vector2i] = []
	var between := {}
	for t in range(0, list.size(), STRIDE):
		var away: Array[float] = []
		for c in 3:
			away.append(plane.distance_to(_at(list[t + c])))
		if away[0] >= 0.0 and away[1] >= 0.0 and away[2] >= 0.0:
			over.append_array(list.slice(t, t + STRIDE))
			continue
		if away[0] < 0.0 and away[1] < 0.0 and away[2] < 0.0:
			under.append_array(list.slice(t, t + STRIDE))
			continue
		var above := PackedInt32Array()
		var below := PackedInt32Array()
		var seam := PackedInt32Array()
		for c in 3:
			var here := list[t + c]
			var next := list[t + (c + 1) % 3]
			var a := away[c]
			var b := away[(c + 1) % 3]
			if a >= 0.0:
				above.append(here)
			else:
				below.append(here)
			if (a >= 0.0) != (b >= 0.0):
				var edge := Vector2i(mini(here, next), maxi(here, next))
				if not between.has(edge):
					between[edge] = _between(edge.x, edge.y, absf(a if edge.x == here else b) / absf(a - b))
				above.append(between[edge])
				below.append(between[edge])
				seam.append(between[edge])
		_fan(above, list[t + 3], list[t + 4], over)
		_fan(below, list[t + 3], list[t + 4], under)
		if seam.size() == 2 and not hollow[list[t + 3]] and _weld(seam[0]) != _weld(seam[1]):
			rim.append(Vector2i(seam[0], seam[1]))
			_rim[_edge(seam[0], seam[1])] = true
	for loop in _loops(rim):
		_close(loop, -plane.normal, over)
		_close(loop, plane.normal, under)
	return [over, under]


static func _fan(corners: PackedInt32Array, surface: int, border: int, into: PackedInt32Array) -> void:
	for i in range(1, corners.size() - 1):
		into.append_array(PackedInt32Array([corners[0], corners[i], corners[i + 1], surface, border]))


# Where a part that's gone joined one that isn't, off the line of the cut.
func _close_seams(kept: PackedInt32Array, rest: Array[PackedInt32Array], lost: PackedInt32Array, falling: Array[PackedInt32Array]) -> void:
	var staying := {}
	_border_edges(kept, staying)
	for list in rest:
		_border_edges(list, staying)
	var going := {}
	_border_edges(lost, going)
	for list in falling:
		_border_edges(list, going)
	var torn: Array[Vector2i] = []
	for edge: Vector2i in staying:
		if going.has(edge) and not _rim.has(edge):
			torn.append(staying[edge])
	for loop in _loops(torn):
		var normal := (_at(loop[1]) - _at(loop[0])).cross(_at(loop[2]) - _at(loop[0])).normalized()
		_close(loop, normal, kept)
		_close(loop, -normal, lost)


func _border_edges(list: PackedInt32Array, into: Dictionary) -> void:
	for t in range(0, list.size(), STRIDE):
		if list[t + 4] == 0 or hollow[list[t + 3]]:
			continue
		for c in 3:
			var a := list[t + c]
			var b := list[t + (c + 1) % 3]
			into[_edge(a, b)] = Vector2i(a, b)


func _edge(a: int, b: int) -> Vector2i:
	var x := _weld(a)
	var y := _weld(b)
	return Vector2i(mini(x, y), maxi(x, y))


# Edges joined end to end. Loose ends go first, so a line that isn't closed is
# found whole.
func _loops(edges: Array[Vector2i]) -> Array[PackedInt32Array]:
	var at := {}
	for i in edges.size():
		for p: int in [edges[i].x, edges[i].y]:
			at.get_or_add(_weld(p), []).append(i)
	var order: Array[int] = []
	for i in edges.size():
		if at[_weld(edges[i].x)].size() == 1 or at[_weld(edges[i].y)].size() == 1:
			order.push_front(i)
		else:
			order.append(i)
	var used := {}
	var loops: Array[PackedInt32Array] = []
	for i in order:
		if used.has(i):
			continue
		used[i] = true
		var ends := edges[i]
		if at[_weld(ends.y)].size() == 1:
			ends = Vector2i(ends.y, ends.x)
		var loop := PackedInt32Array([ends.x, ends.y])
		while true:
			var found := -1
			for j: int in at[_weld(loop[-1])]:
				if not used.has(j):
					found = j
					break
			if found < 0:
				break
			used[found] = true
			loop.append(edges[found].y if _weld(edges[found].x) == _weld(loop[-1]) else edges[found].x)
		if loop.size() >= 3:
			loops.append(loop)
	return loops


# Runs from the middle out, so its material can tell bone from skin.
func _close(loop: PackedInt32Array, normal: Vector3, into: PackedInt32Array) -> void:
	var middle := Vector3.ZERO
	for i in loop:
		middle += _points[i]
	middle /= loop.size()
	var flesh := materials.size() - 1
	var first := _copy(loop[0], normal, Vector2.ZERO)
	_points[first] = middle
	for i in loop:
		_copy(i, normal, Vector2(1, 0))
	for i in loop.size():
		into.append_array(PackedInt32Array([first, first + 1 + i, first + 1 + (i + 1) % loop.size(), flesh, 0]))


func _copy(i: int, normal: Vector3, uv: Vector2) -> int:
	return _new(_points[i], (_pose[_bones[i * 4]].basis.inverse() * normal).normalized(), uv,
			_bones.slice(i * 4, i * 4 + 4), _weights.slice(i * 4, i * 4 + 4))


func _new(point: Vector3, normal: Vector3, uv: Vector2, bones: PackedInt32Array, weights: PackedFloat32Array) -> int:
	_points.append(point)
	_normals.append(normal)
	_uvs.append(uv)
	_bones.append_array(bones)
	_weights.append_array(weights)
	_posed.append(Vector3.ZERO)
	_known.append(0)
	_weld_ids.append(0)
	return _points.size() - 1


func _between(a: int, b: int, k: float) -> int:
	var pull := {}
	for j in 4:
		pull[_bones[a * 4 + j]] = pull.get(_bones[a * 4 + j], 0.0) + _weights[a * 4 + j] * (1.0 - k)
		pull[_bones[b * 4 + j]] = pull.get(_bones[b * 4 + j], 0.0) + _weights[b * 4 + j] * k
	var strongest: Array = pull.keys()
	strongest.sort_custom(func(x: int, y: int): return pull[x] > pull[y])
	var bones := PackedInt32Array([0, 0, 0, 0])
	var weights := PackedFloat32Array([0, 0, 0, 0])
	var sum := 0.0
	for j in mini(4, strongest.size()):
		bones[j] = strongest[j]
		weights[j] = pull[strongest[j]]
		sum += weights[j]
	for j in 4:
		weights[j] /= sum
	var at := _at(a).lerp(_at(b), k)
	var i := _new(_points[a].lerp(_points[b], k), _normals[a].lerp(_normals[b], k).normalized(), _uvs[a].lerp(_uvs[b], k), bones, weights)
	_know(i, at)
	return i


func _at(i: int) -> Vector3:
	if not _known[i]:
		var at := Vector3.ZERO
		for k in 4:
			var weight := _weights[i * 4 + k]
			if weight > 0.0:
				at += _pose[_bones[i * 4 + k]] * _points[i] * weight
		_know(i, at)
	return _posed[i]


func _know(i: int, at: Vector3) -> void:
	_posed[i] = at
	_known[i] = 1
	_weld_ids[i] = _welded.get_or_add(Vector3i((at / WELD).round()), _welded.size())


func _weld(i: int) -> int:
	if not _known[i]:
		_at(i)
	return _weld_ids[i]


func _turned(i: int) -> Vector3:
	var way := Vector3.ZERO
	for k in 4:
		var weight := _weights[i * 4 + k]
		if weight > 0.0:
			way += _pose[_bones[i * 4 + k]].basis * _normals[i] * weight
	return way.normalized()


func _frozen(list: PackedInt32Array) -> MeshInstance3D:
	var by_surface: Array[PackedInt32Array] = []
	for m in materials:
		by_surface.append(PackedInt32Array())
	for t in range(0, list.size(), STRIDE):
		var into := by_surface[list[t + 3]]
		into.append(list[t])
		into.append(list[t + 1])
		into.append(list[t + 2])
	var solid := ArrayMesh.new()
	for s in materials.size():
		if by_surface[s].is_empty():
			continue
		var place := PackedInt32Array()
		place.resize(_points.size())
		var points := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for i in by_surface[s]:
			if place[i] == 0:
				points.append(_at(i))
				normals.append(_turned(i))
				uvs.append(_uvs[i])
				place[i] = points.size()
			indices.append(place[i] - 1)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		solid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		solid.surface_set_material(solid.get_surface_count() - 1, materials[s])
	var node := MeshInstance3D.new()
	node.mesh = solid
	return node
