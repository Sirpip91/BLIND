extends Node

## Turns the hour: N goes on to the next. Everything eases over, paper and all.

const Hour = preload("res://Experiments/Arena/grounds/hour.gd")

signal turned(hour: Hour)

@export var wash_pass: MeshInstance3D
@export var world: WorldEnvironment
@export var sun: DirectionalLight3D
@export var moon: Node3D
@export var writing: Array[Label] = []
@export var hours: Array[Hour] = []
@export var takes := 1.4

var _now := 0
var _tween: Tween


func _ready():
	_go_to(0, 0.0)


func _unhandled_key_input(event):
	if event.pressed and not event.echo and event.physical_keycode == KEY_N:
		_go_to((_now + 1) % hours.size(), takes)


## 0 is day and 1 is night.
func turn_to(which: int) -> void:
	if which != _now:
		_go_to(which, 0.5)


func _go_to(which: int, seconds: float) -> void:
	_now = which
	var hour := hours[which]
	var wash: ShaderMaterial = wash_pass.mesh.surface_get_material(0)
	var env := world.environment
	if _tween:
		_tween.kill()
	if seconds > 0.0:
		_tween = create_tween().set_parallel().set_ignore_time_scale(true)
	_ease(wash, "shader_parameter/paper_color", hour.paper, seconds)
	_ease(wash, "shader_parameter/ink_color", hour.ink, seconds)
	_ease(wash, "shader_parameter/mist_limit", hour.mist_limit, seconds)
	_ease(env, "background_color", Color(hour.sky, hour.sky, hour.sky), seconds)
	_ease(env, "ambient_light_energy", hour.ambient, seconds)
	_ease(sun, "light_energy", hour.sun_energy, seconds)
	for label in writing:
		_ease(label, "theme_override_colors/font_color", hour.writing, seconds)
	moon.visible = hour.moon
	turned.emit(hour)


# A shader's own default can't be eased from until it's been set.
func _ease(what: Object, property: String, to: Variant, seconds: float) -> void:
	if seconds <= 0.0 or what.get(property) == null:
		what.set(property, to)
	else:
		_tween.tween_property(what, property, to, seconds)
