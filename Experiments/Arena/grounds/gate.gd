extends Node3D

## A gatehouse to walk through, with doors at both ends. Only the ones facing
## the clearing ever move.

const Shapes = preload("res://Experiments/Arena/grounds/shapes.gd")

const GREYS := { "Wood": 0.03, "Plank": 0.09, "Plaster": 0.5, "Tile": 0.03, "Iron": 0.01, "Paper": 1.0 }
## Inside, from the middle.
const HALF := Vector2(1.5, 2.5)
const TALL := 2.75

@export var model: PackedScene
## Which end faces the clearing: "front" is +Z.
@export var faces := "front"
@export var slides := 1.42
@export var opens_in := 1.1
@export var shuts_in := 0.45

var is_open := false

var _leaves: Array[Node3D] = []
var _bar: CollisionShape3D
var _tween: Tween


func _ready():
	var made := model.instantiate()
	add_child(made)
	for node: MeshInstance3D in made.find_children("*", "MeshInstance3D", true, false):
		for s in node.mesh.get_surface_count():
			node.set_surface_override_material(s, Shapes.grey(GREYS[node.mesh.surface_get_material(s).resource_name], true))
		if String(node.name).begins_with(faces):
			_leaves.append(node)
	var body := StaticBody3D.new()
	add_child(body)
	for side: float in [1.0, -1.0]:
		_wall(body, Vector3(side * (HALF.x + 0.15), TALL * 0.5, 0.0), Vector3(0.3, TALL, HALF.y * 2.0))
		for end: float in [1.0, -1.0]:
			_wall(body, Vector3(side * (HALF.x + 1.0), TALL * 0.5, end * (HALF.y + 0.15)), Vector3(1.8, TALL, 0.5))
	var way := facing()
	_wall(body, Vector3(0.0, TALL * 0.5, -way * HALF.y), Vector3(HALF.x * 2.0, TALL, 0.3))
	_bar = _wall(body, Vector3(0.0, TALL * 0.5, way * HALF.y), Vector3(HALF.x * 2.0, TALL, 0.3))


## +1 if the clearing is toward +Z of it.
func facing() -> float:
	return 1.0 if faces == "front" else -1.0


## How far past its clearing-side doors something is, going in.
func depth(at: Vector3) -> float:
	var local := to_local(at)
	return HALF.y - local.z * facing() if absf(local.x) < HALF.x else -100.0


func open() -> void:
	is_open = true
	_bar.disabled = true
	_slide(slides, opens_in, Tween.TRANS_CUBIC)


func shut(at_once := false) -> void:
	is_open = false
	_bar.disabled = false
	_slide(0.0, 0.0 if at_once else shuts_in, Tween.TRANS_QUAD)


func _slide(out: float, seconds: float, how: Tween.TransitionType) -> void:
	if _tween:
		_tween.kill()
	if seconds <= 0.0:
		for leaf in _leaves:
			leaf.position.x = _side(leaf) * out
			leaf.reset_physics_interpolation()
		return
	_tween = create_tween().set_parallel().set_trans(how).set_ease(Tween.EASE_IN_OUT)
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	for leaf in _leaves:
		_tween.tween_property(leaf, "position:x", _side(leaf) * out, seconds)


func _side(leaf: Node3D) -> float:
	return 1.0 if String(leaf.name).ends_with("r") else -1.0


func _wall(body: StaticBody3D, at: Vector3, size: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = at
	body.add_child(node)
	return node
