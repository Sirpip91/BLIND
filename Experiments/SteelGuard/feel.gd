extends Node

## What every moment of the fight looks and kicks like. The rules don't know
## this exists. It says little: the swords and the bodies do the telling, and
## only a death stops the page.

const Splash = preload("res://Experiments/SteelGuard/splash.gd")
const Slash = preload("res://Experiments/SteelGuard/slash.gd")
const Stain = preload("res://Experiments/SteelGuard/stain.gd")
const Strike = preload("res://Experiments/SteelGuard/strike.gd")

@export var player: CharacterBody3D
@export var impact_frames: Node
@export var overlay: ColorRect

@export var ink_color := Color(0.035, 0.035, 0.045)
@export var blood_color := Color(0.6, 0.015, 0.02)
## Radians the view is thrown by a blow.
@export var kick := 0.05
## The full page of silhouettes and burst lines, on a perfect parry.
@export var parry_bursts := false

## How slowly time goes while a cut is being drawn.
@export_range(0.05, 1.0, 0.05) var draw_slow := 0.3

var _hurt := 0.0
var _slow := 0


func _process(delta: float):
	_hurt = move_toward(_hurt, 0.0, delta / maxf(Engine.time_scale, 0.05) * 1.8)
	overlay.material.set_shader_parameter("hurt", _hurt)
	if player.vitals:
		overlay.material.set_shader_parameter("wounds", 1.0 - player.vitals.health / player.vitals.max_health)


## The world holds back while a cut is being drawn.
func drawing(on: bool) -> void:
	impact_frames.set_time(draw_slow if on else 1.0)


func swing(strike: Strike) -> void:
	# Thrown after the blade, so a cut has weight even when it misses.
	var d := strike.direction
	player.kick(Vector3(d.y, -d.x, d.x * 0.9) * kick * 0.22 * (0.5 + strike.power))


func parry(at: Vector3, strike: Strike, late: float) -> void:
	var clean := late < 0.5
	_splash(at, 0.8 if clean else 0.6, ink_color, 0.4, Vector2.ZERO, 0.05)
	impact_frames.hit(at, 1.3 if clean else 0.9, clean and parry_bursts, ink_color)
	var d := strike.direction
	# Theirs mirrors onto our view.
	player.kick(Vector3(-0.35, d.x * -0.5, d.x * 0.8) * kick * (1.0 if clean else 0.7))


func block(at: Vector3, strike: Strike, mine: bool) -> void:
	_splash(at, 0.4, ink_color, 0.3, Vector2.ZERO, 0.04)
	impact_frames.hit(at, 0.5, false, ink_color)
	var across := strike.direction.x * (1.0 if mine else -1.0)
	player.kick(Vector3(strike.direction.y * 0.4, across * -0.5, across * 0.6) * kick)


## Our edge in them: "scratch", "sever" or "kill".
func cut(at: Vector3, strike: Strike, result: String) -> void:
	var d := strike.direction
	var deep := result != "scratch"
	_slash(at, d, 0.55 if not deep else 0.95)
	if deep:
		_splash(at, 1.0, blood_color, 0.6, d, 0.03)
		_bleed(at)
	else:
		_splash(at, 0.5, blood_color, 0.35, d, 0.02)
	if deep:
		impact_frames.hit(at, 1.1 if result == "kill" else 0.8, result == "kill", blood_color)
	var weight := 1.5 if deep else 0.8
	# The view is dragged along the cut with the blade.
	player.kick(Vector3(d.y, -d.x, d.x) * kick * 0.6 * weight)
	player.spike_fov(player.base_fov - 2.5 * weight, 0.03, 0.25)


func hurt(strike: Strike, grazed: bool, fatal: bool) -> void:
	_hurt = 0.6 if grazed else 1.0
	var d := strike.direction
	player.kick(Vector3(d.y * 0.8 - 0.3, d.x, -d.x * 1.5) * kick * (1.2 if grazed else 2.2))
	player.spike_fov(player.base_fov - 6.0, 0.03, 0.4)
	impact_frames.hit(player.camera.global_position + player.facing(), 0.6 if grazed else 1.3, fatal, blood_color)


## A blow slipped at the last moment: time hangs, so you can see it go by.
func slipped() -> void:
	_slow += 1
	var mine := _slow
	impact_frames.set_time(0.35)
	await get_tree().create_timer(0.22, true, false, true).timeout
	if mine == _slow:
		impact_frames.set_time(1.0)


func _bleed(at: Vector3) -> void:
	for i in 3:
		var stain := Stain.new()
		get_tree().current_scene.add_child(stain)
		var off := Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
		stain.spread(at + off, randf_range(0.2, 0.5))


func _slash(at: Vector3, way: Vector2, size: float) -> void:
	var slash := Slash.new()
	get_tree().current_scene.add_child(slash)
	slash.play(at, way, size, blood_color)


func _splash(at: Vector3, size: float, color: Color, seconds: float, thrown: Vector2, blot: float) -> void:
	var splash := Splash.new()
	get_tree().current_scene.add_child(splash)
	# Sized by distance, so one at the blade isn't a faceful.
	var camera := get_viewport().get_camera_3d()
	var near := clampf(camera.global_position.distance_to(at) / 2.0, 0.35, 2.0) if camera else 1.0
	splash.play(at, size * near, color, seconds, thrown, blot)
