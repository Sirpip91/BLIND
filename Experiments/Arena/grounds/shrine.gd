extends Node3D

## A mask hanging in the air. Gone up to and looked into, its eyes take the
## colour of whatever's asked of it; cut, it gives that up.

const Shapes = preload("res://Experiments/Arena/grounds/shapes.gd")
const Slicer = preload("res://Experiments/Arena/cutting/slicer.gd")
const Region = preload("res://Experiments/Arena/cutting/region.gd")
const Piece = preload("res://Experiments/Arena/cutting/piece.gd")
const Aspect = preload("res://Experiments/Arena/player/aspect.gd")

## Its halves are on the ground.
signal taken(aspect: Aspect, at: Vector3)
## Something to be told, or nothing.
signal told(text: String)

@export var player: CharacterBody3D
@export var sword: Node3D
@export var choosing: Control
@export var mask: PackedScene
@export var aspects: Array[Aspect] = []
@export var size := 1.5
@export var height := 1.55
## How near to look into it, and to cut it.
@export var near := 2.6
@export var reach := 3.0

var chosen: Aspect
## What's been taken from others like it.
var given: Array[Aspect] = []

var _mask: MeshInstance3D
var _floating: Node3D
var _eyes: Array[MeshInstance3D] = []
var _glow := StandardMaterial3D.new()
var _time := 0.0
var _whole := false
var _close := false
# The line through it so far, if the sword's in it.
var _line := PackedVector2Array()


func _ready():
	var stone := MeshInstance3D.new()
	stone.mesh = Shapes.lathe([[0.0, 0.42], [0.1, 0.4], [0.12, 0.26], [0.62, 0.2], [0.66, 0.32], [0.78, 0.34], [0.8, 0.01]], 0.05, 10)
	stone.material_override = Shapes.grey(0.12, true)
	add_child(stone)
	_floating = Node3D.new()
	add_child(_floating)
	var made := mask.instantiate()
	var model: MeshInstance3D = made.find_children("*", "MeshInstance3D", true, false)[0]
	_mask = MeshInstance3D.new()
	_mask.mesh = model.mesh
	made.free()
	_floating.add_child(_mask)
	# Modelled where a face would be.
	_mask.position = Vector3(0, -1.69, 0)
	for s in _mask.mesh.get_surface_count():
		var called: String = _mask.mesh.surface_get_material(s).resource_name
		_mask.set_surface_override_material(s, Shapes.grey({ "Mask": 0.95, "MaskInk": 0.005 }.get(called, 0.6), true))
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ball(Vector3(0.088, 0.1, 0.06), Vector3(0, 0, 0.03), Shapes.grey(0.0, true))
	for side: float in [1.0, -1.0]:
		_eyes.append(_ball(Vector3(0.024, 0.016, 0.014), Vector3(side * 0.038, 0.01, 0.09), _glow))
	_floating.scale = Vector3.ONE * size
	choosing.pointed_at.connect(_light)
	choosing.chose.connect(_choose)
	choosing.left.connect(_leave)
	sword.swept.connect(_swept)
	sword.ran_out.connect(func(_strike): _came_out())
	put_away()


func _ball(scaled: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	var node := MeshInstance3D.new()
	node.mesh = ball
	node.material_override = material
	node.scale = scaled
	node.position = at
	_floating.add_child(node)
	return node


func set_out() -> void:
	visible = true
	_whole = given.size() < aspects.size()
	_floating.visible = _whole
	_close = false
	chosen = null
	_line.clear()
	_light(null)


func put_away() -> void:
	if choosing.visible:
		choosing.close()
	visible = false
	_whole = false


func _light(aspect: Aspect) -> void:
	if aspect == null:
		aspect = chosen
	_glow.albedo_color = aspect.color if aspect else Color(0.01, 0.01, 0.01)
	for eye in _eyes:
		eye.scale = Vector3(0.024, 0.016, 0.014) * (1.25 if aspect else 1.0)


func _choose(aspect: Aspect) -> void:
	chosen = aspect
	choosing.close()


func _leave() -> void:
	_light(null)
	player.movement_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_say()


func _say() -> void:
	if not _whole or not _close:
		told.emit("")
	elif chosen:
		told.emit("Cut it     (E: look again)")
	else:
		told.emit("E: look into it")


func _unhandled_key_input(event):
	if not _whole or not _close or not event.pressed or event.echo or event.physical_keycode != KEY_E or choosing.visible:
		return
	player.movement_locked = true
	player.face_point(_floating.global_position, 0.4)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	told.emit("")
	choosing.open(aspects.filter(func(each): return not given.has(each)), chosen, _floating)


func _process(delta: float):
	if not visible:
		return
	_time += delta
	_floating.position = Vector3(0.0, height + sin(_time * 1.3) * 0.035, 0.0)
	var to := player.global_position - global_position
	_floating.rotation = Vector3(0.0, atan2(to.x, to.z) + sin(_time * 0.7) * 0.06, sin(_time * 0.9) * 0.03)
	var was := _close
	_close = _whole and Vector2(to.x, to.z).length() < near
	if was != _close and not choosing.visible:
		_say()


# ---- cutting it

func _eye() -> Transform3D:
	return sword.get_parent().global_transform


func _swept(_strike: Resource, from: Vector2, to: Vector2) -> void:
	if not _whole or chosen == null or not visible:
		return
	var eye := _eye()
	var away := eye.origin.distance_to(_floating.global_position)
	if away > reach:
		return
	var at: Vector2 = sword.seen_at(eye.affine_inverse() * _floating.global_position)
	var inside := Geometry2D.get_closest_point_to_segment(at, from, to).distance_to(at) < 0.14 * size / away
	if inside:
		if _line.is_empty():
			_line.append(from)
		_line.append(to)
	else:
		_came_out()


func _came_out() -> void:
	var line := _line
	_line = PackedVector2Array()
	if line.size() < 2 or not _whole:
		return
	var eye := _eye()
	var region = Region.from_line(line, eye, sword.ray)
	if region.planes.is_empty():
		return
	_whole = false
	var halves := Slicer.carve(_mask, region, null)
	var way: Vector3 = eye.basis * Vector3(line[-1].x - line[0].x, line[-1].y - line[0].y, 0.0).normalized()
	for i in 2:
		if halves[i] == null:
			continue
		var node := MeshInstance3D.new()
		node.mesh = halves[i]
		node.transform = _mask.global_transform
		var piece := Piece.new()
		get_tree().current_scene.add_child(piece)
		piece.bleeds = false
		var normal: Vector3 = region.planes[0].normal * (1.0 if i == 0 else -1.0)
		piece.begin([node] as Array[Node3D], normal * 1.1 + way * 0.5 + Vector3.UP * 0.6)
	_floating.visible = false
	_say()
	taken.emit(chosen, _floating.global_position)
