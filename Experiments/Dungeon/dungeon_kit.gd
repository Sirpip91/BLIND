class_name DungeonKit
extends RefCounted

## Reads a modular kit scene (an imported .glb) into pieces grouped by name.
## Trailing numbers are dropped, so Pillar_003/Pillar_004/Pillar_005 are all
## variants of "Pillar" — adding Wall.002 in Blender just adds a wall variant.

class Piece:
	var mesh: Mesh
	var basis: Basis
	## How far to raise it so its lowest point sits at y = 0.
	var lift: float
	var _trimesh: Shape3D
	var _convex: Shape3D

	## Built once per piece and shared by every copy placed.
	func shape_for(trimesh: bool) -> Shape3D:
		if trimesh:
			if _trimesh == null:
				_trimesh = mesh.create_trimesh_shape()
			return _trimesh
		if _convex == null:
			_convex = mesh.create_convex_shape()
		return _convex

var _pieces := {}


func _init(kit_scene: PackedScene) -> void:
	var root := kit_scene.instantiate()
	var strip := RegEx.create_from_string("[._]?\\d+$")
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var piece := Piece.new()
		piece.mesh = mi.mesh
		piece.basis = mi.transform.basis
		piece.lift = -(mi.transform * mi.mesh.get_aabb()).position.y
		var category := strip.sub(String(mi.name), "")
		if not _pieces.has(category):
			_pieces[category] = []
		_pieces[category].append(piece)
	root.free()


func has(category: String) -> bool:
	return _pieces.has(category)


func pick(category: String, rng: RandomNumberGenerator) -> Piece:
	var list: Array = _pieces[category]
	return list[rng.randi() % list.size()]


func categories() -> Array:
	return _pieces.keys()
