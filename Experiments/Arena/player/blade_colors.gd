extends Node

## Every colour the sword has been given, kept on the blade and in its
## strokes. V goes through the ways of laying them on.

const Aspect = preload("res://Experiments/Arena/player/aspect.gd")
const Menu = preload("res://Experiments/Arena/menu/main_menu.gd")

const STYLES: Array[String] = ["Bled", "Marbled", "Painted over", "Loaded brush", "Stirred", "Splashed", "Tempered"]

## What it's called now.
signal restyled(text: String)

@export var brush: Node
@export var swordsman: Node
@export var ink: ShaderMaterial
@export var sword: Node3D
@export_range(0, 6) var style := 5
@export_group("Moving")
## How fast the paint runs in a sword held still, and how much more for every
## radian a second the point is moving.
@export_range(0.0, 3.0, 0.05) var calm := 0.9
@export_range(0.0, 1.0, 0.01) var stirred_by := 0.28
@export var most := 5.0
## Seconds a new colour takes to be painted on.
@export var painting_on := 1.5

var aspects: Array[Aspect] = []

# How strongly each shows.
var _flow := 0.0
var _speed := 0.0
var _newest := 1.0
var _surge := 0.0
var _tip := Vector2.ZERO
var _shown: Array[float] = [1.0, 1.0, 1.0, 1.0]


func _ready():
	wear([])


func wear(what: Array[Aspect]) -> void:
	if what.size() > aspects.size():
		_newest = 0.0
	aspects = what.duplicate()
	var colors := PackedColorArray()
	var others: Array[Color] = []
	for aspect in aspects:
		colors.append(aspect.color)
		if colors.size() > 1:
			others.append(aspect.color)
	colors.resize(4)
	ink.set_shader_parameter("colors", colors)
	ink.set_shader_parameter("color_count", aspects.size())
	ink.set_shader_parameter("style", style)
	brush.others = others
	brush.blotted = not aspects.is_empty()
	if not aspects.is_empty():
		brush.tint = aspects[0].color
		brush.stroke_tint = maxf(brush.stroke_tint, 0.75)


## Something has gone through it.
func surge() -> void:
	_surge = 1.0


func _process(delta: float):
	if delta > 0.0:
		_speed = lerpf(_speed, minf((sword.tip - _tip).length() / delta * stirred_by, most), 1.0 - exp(-delta * 5.0))
		_tip = sword.tip
	_surge = move_toward(_surge, 0.0, delta / 0.8)
	_newest = move_toward(_newest, 1.0, delta / painting_on)
	_flow += delta * (calm + _speed + _surge * 2.0)
	ink.set_shader_parameter("flow", _flow)
	ink.set_shader_parameter("newest", _newest)
	ink.set_shader_parameter("surge", _surge)
	ink.set_shader_parameter("heat", clampf(maxf(_speed / most * 1.4, _surge), 0.0, 1.0))
	for i in aspects.size():
		var ready: bool = aspects[i].power != Aspect.Power.SUNDER or swordsman.is_charged()
		_shown[i] = lerpf(_shown[i], 1.0 if ready else 0.3, 1.0 - exp(-9.0 * delta))
	ink.set_shader_parameter("strengths", PackedFloat32Array(_shown))


func _unhandled_key_input(event):
	if Menu.developer and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		style = (style + 1) % STYLES.size()
		ink.set_shader_parameter("style", style)
		restyled.emit(STYLES[style])
