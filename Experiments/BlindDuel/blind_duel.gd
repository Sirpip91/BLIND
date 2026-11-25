extends Node3D

## A duel in the dark. The enemy can only be heard: its footsteps ripple
## across the floor like drops on water. A flourish sends out a ring of its
## own, and where that touches the enemy its sword shows, with the aura of
## whoever holds it.

@export var player: CharacterBody3D
@export var katana: Node3D
@export var enemy: CharacterBody3D
@export var floor_ripples: Node3D
@export var hint: Label
@export var arena_radius := 10.0
## Your own footsteps, against the enemy's.
@export_range(0.0, 1.0, 0.05) var own_steps := 0.3
## Seconds for a flourish's ring to cross the arena.
@export var pulse_time := 2.0
## Seconds the enemy stays visible after a flourish finds it.
@export var flourish_reveal := 4.0
@export var rise_again := 3.0

const PULSE_RADIUS := 22.0
# Lights only what's in the player's hands.
const HELD_LAYER := 2


func _enter_tree():
	# A private copy, so black ink here doesn't reach other scenes. Before
	# ready, since the impact frames take hold of it then.
	var ink_pass: MeshInstance3D = $InkPass
	ink_pass.mesh = ink_pass.mesh.duplicate()
	var ink: ShaderMaterial = ink_pass.mesh.surface_get_material(0).duplicate()
	ink.set_shader_parameter("ink_color", Color.BLACK)
	# Deep enough that a parry's silhouette shows who struck.
	ink.set_shader_parameter("impact_reach", 3.5)
	ink.set_shader_parameter("fade_start", 200.0)
	ink.set_shader_parameter("fade_end", 400.0)
	ink_pass.mesh.surface_set_material(0, ink)


func _ready():
	_build_wall()
	player.footstep.connect(_on_own_step)
	enemy.stepped.connect(_on_enemy_step)
	enemy.opened.connect(_say.bind("OPEN - hold left click"))
	enemy.closed.connect(_say.bind(""))
	enemy.died.connect(_on_enemy_died)
	katana.moment.connect(_on_moment)
	_light_hands.call_deferred()
	enemy.appear(Vector3(0, 0, -arena_radius * 0.6))
	_say("Listen for its steps.   Wheel: flourish to see its sword.   Right click: guard.   Left click: cut.")
	await get_tree().create_timer(9.0).timeout
	if hint.text.begins_with("Listen"):
		_say("")


func _on_own_step(strength: float) -> void:
	floor_ripples.drop(player.global_position, own_steps * strength, 0.9, 0.9, 1)


func _on_enemy_step(at: Vector3, strength: float) -> void:
	floor_ripples.drop(at, strength * 1.4, 1.1 + strength * 0.6, 1.4, 4 if strength > 1.2 else 3)


func _on_moment(kind: String, _detail: String) -> void:
	match kind:
		"flourish":
			_pulse()
		"parry", "block", "hit", "kill", "execute":
			var between := (player.global_position + enemy.global_position) * 0.5
			floor_ripples.drop(between, 0.9, 3.5, 1.2, 2)


func _pulse() -> void:
	var from := player.global_position
	floor_ripples.drop(from, 0.8, PULSE_RADIUS, pulse_time, 1)
	# Found when the ring reaches it. The ring starts fast and slows, so this
	# follows the same curve the floor draws.
	var reach := clampf(from.distance_to(enemy.global_position) / PULSE_RADIUS, 0.0, 1.0)
	await get_tree().create_timer((1.0 - sqrt(1.0 - reach)) * pulse_time).timeout
	if not enemy.vitals.dead:
		enemy.veil.reveal(flourish_reveal)
		floor_ripples.drop(enemy.global_position, 0.8, 1.6, 1.2, 2)


func _on_enemy_died() -> void:
	await get_tree().create_timer(rise_again).timeout
	# Back behind you or to one side, never in view.
	var away := player.global_basis.z.rotated(Vector3.UP, randf_range(-1.2, 1.2))
	var at := player.global_position + away * 6.0
	at.y = 0.0
	enemy.appear(at.limit_length(arena_radius - 1.0))


func _say(text: String) -> void:
	hint.text = text


func _light_hands() -> void:
	for mesh: MeshInstance3D in katana.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		mesh.layers = HELD_LAYER
	var light := OmniLight3D.new()
	light.light_cull_mask = HELD_LAYER
	light.light_energy = 0.7
	light.omni_range = 2.5
	light.light_specular = 0.0
	light.position = Vector3(-0.15, 0.25, 0.1)
	player.camera.add_child(light)


func _build_wall() -> void:
	var wall := StaticBody3D.new()
	add_child(wall)
	var sides := 32
	for i in sides:
		var angle := TAU * i / sides
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(arena_radius * TAU / sides * 1.2, 4.0, 0.6)
		shape.shape = box
		shape.position = Vector3(sin(angle), 0.0, cos(angle)) * (arena_radius + 0.3) + Vector3.UP * 2.0
		shape.rotation.y = angle
		wall.add_child(shape)
