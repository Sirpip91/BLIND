extends Node3D

## Holds one model, centred and scaled to fit a 1 m radius so every asset
## frames and lights the same whatever its real size.

const InkReal = preload("res://Core/Ink/ink_real.gdshader")

## Real size of the model as authored, in metres.
var real_size := Vector3.ZERO

var _holder: Node3D
var _box := AABB()
var _ink := true


## Loads a project resource, or a .glb, .gltf or .fbx from anywhere on disk.
func load_model(path: String) -> Error:
	var model: Node
	if path.begins_with("res://"):
		var scene := load(path) as PackedScene
		if scene:
			model = scene.instantiate()
	else:
		var is_fbx := path.get_extension().to_lower() == "fbx"
		var document: GLTFDocument = FBXDocument.new() if is_fbx else GLTFDocument.new()
		var state: GLTFState = FBXState.new() if is_fbx else GLTFState.new()
		var error := document.append_from_file(path, state)
		if error != OK:
			return error
		model = document.generate_scene(state)
	if model == null:
		return ERR_CANT_OPEN

	var holder := Node3D.new()
	holder.add_child(model)
	# Exports often carry the file's own camera and lights along.
	for type in ["Camera3D", "Light3D", "WorldEnvironment"]:
		for node in holder.find_children("*", type, true, false):
			node.free()
	var box := _bounds(holder)
	if box.size.length() < 0.00001:
		holder.free()
		return ERR_INVALID_DATA

	if _holder:
		_holder.free()
	_holder = holder
	real_size = box.size
	var radius := box.size.length() * 0.5
	_holder.scale = Vector3.ONE / radius
	_holder.position = -box.get_center() / radius
	_box = AABB(-box.size * 0.5 / radius, box.size / radius)
	add_child(_holder)
	set_ink(_ink)
	return OK


## `phase` is how far through a turn it is, 0 to 1; tilt and lean in degrees.
func pose(phase: float, tilt: float, lean: float, own_axis: bool) -> void:
	var spin := Basis(Vector3.UP, phase * TAU)
	var posed := _posed(tilt, lean)
	# Spinning inside the tilt turns it about its own length, like a drill;
	# outside, the tilted model sweeps around the vertical.
	basis = posed * spin if own_axis else spin * posed


## Lowest point of the tilted model, for standing it on the pedestal.
func lowest(tilt: float, lean: float, own_axis: bool) -> float:
	if own_axis and (tilt != 0.0 or lean != 0.0):
		return -1.0
	var posed := _posed(tilt, lean)
	var low := 0.0
	for i in 8:
		low = minf(low, (posed * _box.get_endpoint(i)).y)
	return low


## How far it reaches sideways from the spin axis.
func footprint() -> float:
	return Vector2(_box.size.x, _box.size.z).length() * 0.5


## Ink keeps the painted texture as black-on-paper under real light; off
## shows the materials as they were imported.
func set_ink(on: bool) -> void:
	_ink = on
	if not _holder:
		return
	for mesh: MeshInstance3D in _holder.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, _inked(mesh.mesh.surface_get_material(i)) if on else null)


func _posed(tilt: float, lean: float) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(lean)) * Basis(Vector3.RIGHT, deg_to_rad(tilt))


func _inked(original: Material) -> ShaderMaterial:
	var inked := ShaderMaterial.new()
	inked.shader = InkReal
	inked.set_shader_parameter("use_painting", true)
	var base := original as BaseMaterial3D
	if base:
		if base.albedo_texture:
			inked.set_shader_parameter("painting", base.albedo_texture)
		else:
			inked.set_shader_parameter("paper_color", base.albedo_color)
	return inked


func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var found := false
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var to_root := Transform3D.IDENTITY
		var node: Node = mesh
		while node != root:
			if node is Node3D:
				to_root = node.transform * to_root
			node = node.get_parent()
		var part := to_root * mesh.get_aabb()
		box = box.merge(part) if found else part
		found = true
	return box
