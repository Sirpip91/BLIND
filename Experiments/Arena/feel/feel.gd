extends Node

## What every moment of the fight looks and kicks like. The rules don't know
## this exists. It says little: only a perfect parry and a last death
## stop the page.

const Splash = preload("res://Experiments/Arena/feel/splash.gd")
const Look = preload("res://Experiments/Arena/player/sword_look.gd")
const Slash = preload("res://Experiments/Arena/feel/slash.gd")
const Strike = preload("res://Experiments/Arena/fighter/strike.gd")

@export var player: CharacterBody3D
@export var impact_frames: Node
@export var overlay: ColorRect
@export var blood: Node3D

@export var ink_color := Color(0.035, 0.035, 0.045)
@export var blood_color := Color(0.6, 0.015, 0.02)
## Radians the view is thrown by a blow.
@export var kick := 0.05
## How hard a perfect parry stops the page.
@export var perfect_strength := 1.1
@export var look: Look

@onready var _red := blood_color

var _hurt := 0.0
var _slow := 0


func _process(delta: float):
	_hurt = move_toward(_hurt, 0.0, delta / maxf(Engine.time_scale, 0.05) * 1.8)
	overlay.material.set_shader_parameter("hurt", _hurt)
	if player.vitals:
		overlay.material.set_shader_parameter("wounds", 1.0 - player.vitals.health / player.vitals.max_health)


## Whether they're only straw here.
func spill(straw: bool) -> void:
	blood.spill(straw)
	blood_color = ink_color if straw else _red


func swing(strike: Strike) -> void:
	# Thrown after the blade, so a cut has weight even when it misses.
	var d := strike.direction
	player.kick(Vector3(d.y, -d.x, d.x * 0.9) * kick * 0.22 * (0.5 + strike.power))


## Their blade turned. Dead on the moment, the whole page goes with it.
## `opens` if there's nothing left of their guard after it.
func parry(at: Vector3, strike: Strike, perfect: bool, opens: bool) -> void:
	var color := look.color if look.blade > 0.0 else ink_color
	var d := strike.direction
	# Theirs mirrors onto our view.
	var thrown := Vector3(-0.35, d.x * -0.5, d.x * 0.8) * kick
	if perfect and not opens:
		# Nearly.
		_splash(at, 1.4, color, 0.5, Vector2(-d.x, d.y), 0.06)
		impact_frames.hit(at, 1.0, false, color)
		player.kick(thrown * 1.2)
		return
	if not perfect:
		_splash(at, 0.7, ink_color, 0.4, Vector2.ZERO, 0.05)
		impact_frames.hit(at, 0.9, false, ink_color)
		player.kick(thrown * 0.7)
		return
	_splash(at, 1.9, ink_color, 0.55, Vector2.ZERO, 0.1)
	_splash(at, 1.2, color, 0.45, Vector2(-d.x, d.y), 0.06)
	_slash(at, Vector2(-d.x, d.y) if d != Vector2.ZERO else Vector2.RIGHT, 1.1, color)
	impact_frames.hit(at, perfect_strength, true, color)
	player.kick(thrown * 1.5)
	player.spike_fov(player.base_fov + 7.0, 0.04, 0.5)


func block(at: Vector3, strike: Strike, mine: bool) -> void:
	_splash(at, 0.4, ink_color, 0.3, Vector2.ZERO, 0.04)
	impact_frames.hit(at, 0.5, false, ink_color)
	var across := strike.direction.x * (1.0 if mine else -1.0)
	player.kick(Vector3(strike.direction.y * 0.4, across * -0.5, across * 0.6) * kick)


## Our edge in them: "scratch", "armour", "sever" or "kill".
## `travel` is the way it went through, in the world.
func cut(at: Vector3, strike: Strike, result: String, last: bool, travel: Vector3) -> void:
	var d := strike.direction
	var deep := result != "scratch"
	_slash(at, d, 0.55 if not deep else 0.95, ink_color if result == "armour" else blood_color)
	if result == "armour":
		_splash(at, 0.9, ink_color, 0.5, d, 0.04)
	elif deep:
		_splash(at, 0.85, blood_color, 0.5, d, 0.03)
	else:
		_splash(at, 0.4, blood_color, 0.3, d, 0.02)
	if result != "armour":
		blood.spray(at, travel, player.global_position, deep, result == "kill")
		blood.stain_blade(deep)
	if deep:
		impact_frames.hit(at, 1.1 if result == "kill" else 0.8, result == "kill" and last, blood_color)
	var weight := 1.5 if deep else 0.8
	# The view is dragged along the cut with the blade.
	player.kick(Vector3(d.y, -d.x, d.x) * kick * 0.6 * weight)
	player.spike_fov(player.base_fov - 2.5 * weight, 0.03, 0.25)


func hurt(strike: Strike, grazed: bool, fatal: bool) -> void:
	_hurt = 0.6 if grazed else 1.0
	var d := strike.direction
	# Ours, the way their edge went.
	var across: Vector3 = player.camera.global_basis * Vector3(-d.x, d.y, -0.15)
	blood.spray(player.global_position + Vector3.UP * 1.15 + player.facing() * 0.35, across, player.global_position + player.facing() * 2.0, not grazed, false)
	player.kick(Vector3(d.y * 0.8 - 0.3, d.x, -d.x * 1.5) * kick * (1.2 if grazed else 2.2))
	player.spike_fov(player.base_fov - 6.0, 0.03, 0.4)
	impact_frames.hit(player.camera.global_position + player.facing(), 0.6 if grazed else 1.3, fatal, blood_color)


## They're something else now, and the whole page knows it.
func changed(at: Vector3, color: Color) -> void:
	for i in 3:
		_splash(at + Vector3(0.0, 0.5 + 0.45 * i, 0.0), 2.0, color if i == 1 else ink_color, 0.7, Vector2.ZERO, 0.14)
	impact_frames.hit(at + Vector3.UP * 1.3, 1.2, true, color)
	player.kick(Vector3(-0.5, 0.0, 0.0) * kick)
	player.spike_fov(player.base_fov + 8.0, 0.05, 0.6)


## What's left of them running together, faster and faster.
func gather(at: Vector3, seconds: float) -> void:
	var t := 0.0
	var k := 0
	while t < seconds:
		var left := 1.0 - t / seconds
		var way := Vector3.RIGHT.rotated(Vector3.UP, k * 2.4) * left * 1.6
		_splash(Vector3(at.x, 0.25 + (1.0 - left) * 1.3, at.z) + way, 0.7 + 1.3 * (1.0 - left), ink_color if k % 3 else Color(0.5, 0.15, 0.75), 0.5, Vector2(-way.x, way.z).limit_length(1.0), 0.16)
		player.kick(Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)) * kick * (1.0 - left))
		k += 1
		var wait := lerpf(0.05, 0.2, left)
		t += wait
		await get_tree().create_timer(wait).timeout


## Left standing in its own blow.
func stilled(at: Vector3, color: Color) -> void:
	for i in 2:
		_splash(at + Vector3(0.0, 0.8 + 0.5 * i, 0.0), 1.3, color, 0.6, Vector2.ZERO, 0.1)
	impact_frames.hit(at + Vector3.UP * 1.3, 0.9, false, color)


## Something given back.
func mended(color: Color) -> void:
	var at: Vector3 = player.camera.global_position - player.camera.global_basis.z * 1.2 + Vector3.DOWN * 0.45
	_splash(at, 0.7, color, 0.7, Vector2.UP, 0.02)


func mask_cut(at: Vector3, color: Color) -> void:
	_splash(at, 2.0, color, 0.8, Vector2.ZERO, 0.1)
	_splash(at, 1.2, ink_color, 0.5, Vector2.ZERO, 0.08)
	impact_frames.hit(at, 1.2, true, color)
	player.spike_fov(player.base_fov + 6.0, 0.04, 0.5)


## Somebody gone from where they were, leaving the ink of them.
func stepped(at: Vector3) -> void:
	for i in 3:
		_splash(at + Vector3(randf_range(-0.1, 0.1), 0.5 + 0.45 * i, 0.0), 1.1, ink_color, 0.5, Vector2.ZERO, 0.14)


## A blow slipped at the last moment: time hangs, so you can see it go by.
func slipped() -> void:
	_slow += 1
	var mine := _slow
	impact_frames.set_time(0.35)
	await get_tree().create_timer(0.22, true, false, true).timeout
	if mine == _slow:
		impact_frames.set_time(1.0)


func _slash(at: Vector3, way: Vector2, size: float, color: Color) -> void:
	var slash := Slash.new()
	get_tree().current_scene.add_child(slash)
	slash.play(at, way, size, color)


func _splash(at: Vector3, size: float, color: Color, seconds: float, thrown: Vector2, blot: float) -> void:
	var splash := Splash.new()
	get_tree().current_scene.add_child(splash)
	# Sized by distance, so one at the blade isn't a faceful.
	var camera := get_viewport().get_camera_3d()
	var near := clampf(camera.global_position.distance_to(at) / 2.0, 0.35, 2.0) if camera else 1.0
	splash.play(at, size * near, color, seconds, thrown, blot)
