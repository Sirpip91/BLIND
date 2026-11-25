extends Node

## Makes a blade behave like a brush: swings lay ink along the tip's path,
## and the ink it's carrying sloshes, runs out and soaks back.

const Stroke = preload("res://Core/Wash/ink_stroke.gd")
const Fx = preload("res://Core/Combat/fx.gd")

@export var blade: Node3D
@export var ink: ShaderMaterial
@export var tip := Vector3(-0.002, 0.75, 0.0)
## Tip speed, in metres a second, where a stroke starts and where it lifts.
@export var stroke_from := 4.0
@export var stroke_until := 2.0
@export_range(0.02, 0.4, 0.01) var stroke_width := 0.13
@export var stroke_dry_time := 0.45
@export var tint := Color(0.85, 0.05, 0.04)
## Colour in the strokes, and bled into the blade.
@export_range(0.0, 1.0) var stroke_tint := 0.0

## Colours the strokes have besides.
var others: Array[Color] = []
## Strokes are black first, and only splashed with their colours.
var blotted := false

## Only a cut paints; winding up for one doesn't.
var painting := false
## Ink on the blade, 0 dry to 1 loaded.
var fill := 1.0
var blade_tint := 0.0

const STEPS := 10
const FULL := 1.3

var _was: Transform3D
var _holder_was: Transform3D
var _stroke: MeshInstance3D
var _heading := Vector3.ZERO
var _shown := FULL
var _slosh := 0.0
var _slosh_speed := 0.0
var _drops: GPUParticles3D


func _ready():
	_was = blade.transform
	var process := Fx.streak_process(0.2, 1.4, 35.0)
	process.gravity = Vector3(0, -5.0, 0)
	process.inherit_velocity_ratio = 0.25
	process.scale_min = 0.35
	process.color = Color(0.035, 0.035, 0.045)
	_drops = Fx.particles(26, 0.55, process, Fx.chip(0.0035, 0.013), Fx.ink(Color.WHITE))
	_drops.local_coords = false
	_drops.position = tip
	_drops.emitting = false
	blade.add_child.call_deferred(_drops)


func _physics_process(delta: float):
	if delta <= 0.0:
		return
	# Relative to whoever holds it, so turning around isn't a swing.
	var moved: Vector3 = blade.transform * tip - _was * tip
	var speed := moved.length() / delta
	var laying := painting and speed > (stroke_until if _stroke else stroke_from)
	if laying and not (_stroke and moved.dot(_heading) < 0.0):
		_lay_ink()
		_heading = moved
	elif _stroke:
		lift()
	_drops.emitting = laying
	_shown = lerpf(_shown, fill * FULL, 1.0 - exp(-delta * (14.0 if fill * FULL < _shown else 3.0)))

	var sideways := moved.dot(blade.transform.basis.x.normalized()) / delta
	_slosh_speed += ((clampf(sideways * 0.06, -0.3, 0.3) - _slosh) * 160.0 - _slosh_speed * 11.0) * delta
	_slosh += _slosh_speed * delta
	_was = blade.transform
	_holder_was = (blade.get_parent() as Node3D).global_transform
	if ink:
		ink.set_shader_parameter("fill", _shown)
		ink.set_shader_parameter("slosh", _slosh)
		ink.set_shader_parameter("tint", tint)
		ink.set_shader_parameter("tint_amount", blade_tint)
		ink.set_shader_parameter("glint", 0.45 + 0.9 * blade.global_basis.z.normalized().dot(Vector3(0.4, 0.7, 0.3)))


func _exit_tree():
	lift()


## Ends the stroke where it is, as when the blade is stopped dead.
func lift() -> void:
	if _stroke:
		_stroke.finish()
		_stroke = null


func _lay_ink() -> void:
	if _stroke == null:
		_stroke = Stroke.new()
		_stroke.dry_time = stroke_dry_time
		_stroke.width = stroke_width
		_stroke.set_tint(tint, stroke_tint)
		_stroke.set_others(others, blotted)
		var scene := get_tree().current_scene
		(scene if scene else get_tree().root).add_child(_stroke)
	var holder := (blade.get_parent() as Node3D).global_transform
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else holder.origin
	# A cut lasts only a few ticks, so the arc between them is filled in.
	for i in range(1, STEPS + 1):
		var t := float(i) / STEPS
		var held := _holder_was.interpolate_with(holder, t)
		_stroke.add(held * _was.interpolate_with(blade.transform, t) * tip, eye)
