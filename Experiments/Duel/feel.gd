extends Node

## What every moment of the fight looks and kicks like. The rules
## don't know this exists.

const Splash = preload("res://Experiments/Duel/splash.gd")
const Slash = preload("res://Experiments/Duel/slash.gd")
const Strike = preload("res://Experiments/Duel/strike.gd")

@export var player: CharacterBody3D
@export var impact_frames: Node
@export var overlay: ColorRect

@export var ink_color := Color(0.035, 0.035, 0.045)
@export var blood_color := Color(0.78, 0.03, 0.03)
## Radians the view is thrown by a blow.
@export var kick := 0.05

var _hurt := 0.0
var _slow := 0


func _process(delta: float):
	_hurt = move_toward(_hurt, 0.0, delta / maxf(Engine.time_scale, 0.05) * 1.8)
	overlay.material.set_shader_parameter("hurt", _hurt)
	if player.vitals:
		overlay.material.set_shader_parameter("wounds", 1.0 - player.vitals.health / player.vitals.max_health)


func swing(strike: Strike) -> void:
	# Thrown after the blade, so a cut has weight even when it misses.
	var d := strike.direction
	player.kick(Vector3(d.y, -d.x, d.x * 0.9) * kick * 0.3)


func wind_up(strike: Strike) -> void:
	var d := strike.direction
	player.kick(Vector3(-d.y, d.x, -d.x) * kick * 0.12)


func parry(at: Vector3, strike: Strike, late: float, mine: bool) -> void:
	var clean := late < 0.5
	_splash(at, 1.5 if clean else 1.0, ink_color, 0.5, Vector2.ZERO, 0.1)
	impact_frames.hit(at, 0.75 if clean else 0.8, clean, ink_color)
	var d := strike.direction
	# Theirs mirrors onto our view.
	var across := d.x if not mine else -d.x
	player.kick(Vector3(-0.35, across * -0.5, across * 0.8) * kick * (1.0 if clean else 0.7))


func block(at: Vector3, strike: Strike, mine: bool) -> void:
	_splash(at, 0.6, ink_color, 0.3, Vector2.ZERO, 0.08)
	impact_frames.hit(at, 0.5, false, ink_color)
	var across := strike.direction.x * (1.0 if mine else -1.0)
	player.kick(Vector3(strike.direction.y * 0.4, across * -0.5, across * 0.6) * kick)


func hit(at: Vector3, strike: Strike, mine: bool, fatal: bool) -> void:
	var d := strike.direction
	if mine:
		_splash(at, 2.4 if fatal else 1.3, blood_color, 0.8 if fatal else 0.5, d, 0.14)
		_splash(at, 1.2, ink_color, 0.35, d, 0.1)
		var weight := 1.0 + 0.35 * strike.link + (0.4 if fatal else 0.0)
		_slash(at, d, 1.0 + 0.3 * strike.link + (0.8 if fatal else 0.0), strike.earned or fatal)
		impact_frames.hit(at, 1.3 if fatal else (1.1 if strike.last_link else 0.9), fatal or strike.last_link, blood_color)
		# The view is dragged along the cut with the blade.
		player.kick(Vector3(d.y, -d.x, d.x) * kick * 0.6 * weight)
		player.spike_fov(player.base_fov - 2.5 * weight, 0.03, 0.22)
	else:
		_hurt = 1.0
		player.kick(Vector3(d.y * 0.8 - 0.3, d.x, -d.x * 1.5) * kick * 1.8)
		player.spike_fov(player.base_fov - 6.0, 0.03, 0.35)
		impact_frames.hit(at, 1.0, fatal, blood_color)


## Skidded off the side that was covered.
func glance(at: Vector3, strike: Strike) -> void:
	_splash(at, 0.5, ink_color, 0.25, strike.direction, 0.04)
	impact_frames.hit(at, 0.3, false, ink_color)
	var d := strike.direction
	player.kick(Vector3(-d.y, d.x, -d.x) * kick * 0.4)


func broke(at: Vector3) -> void:
	_splash(at, 2.6, blood_color, 0.9, Vector2(0, 0.4), 0.12)
	impact_frames.hit(at, 1.2, true, blood_color)


func enraged(at: Vector3) -> void:
	_splash(at, 2.2, blood_color, 0.8, Vector2.ZERO, 0.1)
	impact_frames.hit(at, 0.9, true, blood_color)


## A blow slipped at the last moment: time hangs, so you can see it go by.
func slipped() -> void:
	_slow += 1
	var mine := _slow
	impact_frames.set_time(0.3)
	await get_tree().create_timer(0.28, true, false, true).timeout
	if mine == _slow:
		impact_frames.set_time(1.0)


func _slash(at: Vector3, way: Vector2, size: float, bloody: bool) -> void:
	var slash := Slash.new()
	var scene := get_tree().current_scene
	(scene if scene else get_tree().root).add_child(slash)
	slash.play(at, way, size, blood_color if bloody else ink_color)


func _splash(at: Vector3, size: float, color: Color, seconds: float, thrown: Vector2, blot: float) -> void:
	var splash := Splash.new()
	var scene := get_tree().current_scene
	(scene if scene else get_tree().root).add_child(splash)
	# Sized by distance, so one at the blade isn't a faceful.
	var camera := get_viewport().get_camera_3d()
	var near := clampf(camera.global_position.distance_to(at) / 2.0, 0.35, 2.0) if camera else 1.0
	splash.play(at, size * near, color, seconds, thrown, blot)
