extends Node

## What can be seen of the enemy. Its body is always black in the black; its
## sword and aura show only while it's revealed, then sink back.

@export var sword: Node3D
@export var body: Node3D
@export var fade_in := 0.25
@export var fade_out := 1.4
## How fast a glint dies away, per second.
@export var glint_fade := 1.1

var _left := 0.0
var _shown := 0.0
# A glimpse that dies away by itself, such as a glint off the blade.
var _glint := 0.0
var _flare := 0.0
var _materials: Array[ShaderMaterial] = []


func _ready():
	for root: Node3D in [sword, body]:
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var top := mesh.get_active_material(0)
			if top and top.next_pass is ShaderMaterial and not _materials.has(top.next_pass):
				_materials.append(top.next_pass)


func reveal(seconds: float) -> void:
	_left = maxf(_left, seconds)


## Out of sight at once.
func hide_now() -> void:
	_left = 0.0
	_shown = 0.0


func glint(amount: float) -> void:
	_glint = maxf(_glint, amount)


func flare() -> void:
	_flare = 1.0


## 0 hidden, 1 in plain sight.
func shown() -> float:
	return _shown


func _process(delta):
	_left = maxf(_left - delta, 0.0)
	var wanted := 1.0 if _left > 0.0 else 0.0
	_shown = move_toward(_shown, wanted, delta / (fade_in if wanted > _shown else fade_out))
	_glint = move_toward(_glint, 0.0, delta * glint_fade)
	_flare = move_toward(_flare, 0.0, delta * 4.0)
	for material in _materials:
		material.set_shader_parameter("reveal", _shown)
		material.set_shader_parameter("glint", _glint)
		material.set_shader_parameter("flare", _flare)
