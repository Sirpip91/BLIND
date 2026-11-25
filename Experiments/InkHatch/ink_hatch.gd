extends Node3D

## M switches between real light (Godot's shadows, darkness and fog shafts
##   over the hand-drawn surfaces) and ink shading (light drawn as strokes).
## N switches to night: the sun dims to moonlight and the street lamp comes on.
## H toggles the outline/paper pass to compare against the bare materials.
## L pauses the orbiting sun to study one lighting angle.

@export var props: Node3D
## Ink shading for props with no override of their own, so a freshly
## imported asset is drawn without any setup.
@export var ink_material: Material
## Real-light counterpart; a prop can carry its own as a "real_material"
## metadata entry.
@export var real_material: Material
## Kept unlit with the original texture, as the reference to compare against.
@export var as_painted: Node3D
@export var as_painted_material: Material
@export var painted_lit: Node3D
@export var painted_ink_material: Material
@export var painted_real_material: Material
@export var world_environment: WorldEnvironment
@export var ink_environment: Environment
@export var real_day_environment: Environment
@export var real_night_environment: Environment
@export var sun: DirectionalLight3D
@export var night_lights: Node3D
@export var moon_energy := 0.05
## Moonlight in the fog would grey out the whole night; lamps should be what
## cuts through the dark.
@export var moon_fog_energy := 0.1
@export var ink_pass: GeometryInstance3D
@export var sun_orbit_speed := 0.15
## Where the player starts, facing the way it faces.
@export var spawn: Node3D
@export var real_light := true
@export var night := true

var _orbiting := true
var _day_energy: float
var _day_fog_energy: float
var _ink_overrides := {}


func _ready():
	if spawn:
		var player: Node3D = $Sandbox/Player
		player.global_position = spawn.global_position
		player.rotation.y = spawn.rotation.y
	_day_energy = sun.light_energy
	_day_fog_energy = sun.light_volumetric_fog_energy
	for node in _drawn(props):
		_ink_overrides[node] = node.material_override if node.material_override else ink_material
	for node in _drawn(as_painted):
		node.material_override = as_painted_material
	_refresh()


func set_real_light(value: bool) -> void:
	real_light = value
	_refresh()


func set_night(value: bool) -> void:
	night = value
	_refresh()


func _refresh() -> void:
	for node in _ink_overrides:
		node.material_override = node.get_meta("real_material", real_material) if real_light else _ink_overrides[node]
	for node in _drawn(painted_lit):
		node.material_override = painted_real_material if real_light else painted_ink_material
	if not real_light:
		world_environment.environment = ink_environment
	else:
		world_environment.environment = real_night_environment if night else real_day_environment
	sun.light_energy = moon_energy if night else _day_energy
	sun.light_volumetric_fog_energy = moon_fog_energy if night else _day_fog_energy
	night_lights.visible = night


func _drawn(root: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		# The room's CSG pieces render through their root; bulbs keep their own glow.
		# Nodes built at runtime (health bars, effects) keep their own look.
		if node.has_meta("keep_material") or node.owner == null:
			continue
		if node is MeshInstance3D or (node is CSGShape3D and node.is_root_shape()):
			found.append(node)
	return found


func _process(delta):
	if _orbiting:
		sun.global_rotate(Vector3.UP, sun_orbit_speed * delta)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M:
				set_real_light(not real_light)
			KEY_N:
				set_night(not night)
			KEY_H:
				ink_pass.visible = not ink_pass.visible
			KEY_L:
				_orbiting = not _orbiting
