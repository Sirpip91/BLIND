extends Node3D

## Grid dungeon: rooms placed at random, joined by one-cell corridors, then
## dressed with kit pieces — floors on every cell, walls on every open edge,
## doorways where a corridor enters a room, pillars on every corner a wall
## touches. R rebuilds with a new seed.

const CELL = 4.0
const DIRS = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

enum { ROOM, CORRIDOR }

@export var kit_scene: PackedScene
@export var seed := 0
@export var grid_size := Vector2i(12, 12)
@export var room_attempts := 40
@export var room_min := 2
@export var room_max := 4
@export_range(0.0, 1.0) var debris_chance := 0.3
@export_range(0.0, 1.0) var prop_chance := 0.15
@export_range(0.0, 1.0) var torch_chance := 0.2
## Leave empty for an open top.
@export var roof_material: Material
## Just under the wall tops so the roof's edges hide inside them.
@export var roof_height := 2.98
@export var give_player_torch := true
## Every torch light and flame, wall-mounted and held, follows this.
@export var torch_color := Color(1.0, 0.62, 0.3):
	set(value):
		torch_color = value
		_apply_torch_color()

const TORCH_ENERGY = 2.0
const HELD_TORCH_ENERGY = 1.5
# The kit's flame glows at ~15, which blows out to white whatever the tint.
const FLAME_GLOW = 6.0

var cells := {}
var rooms: Array[Rect2i] = []
var _doors := {}
var _kit: DungeonKit
var _rng := RandomNumberGenerator.new()
var _floor_shape := BoxShape3D.new()
var _roof_mesh := PlaneMesh.new()
var _torches: Array[OmniLight3D] = []
var _held_light: OmniLight3D
var _flame_material: StandardMaterial3D
var _time := 0.0


func _ready():
	_kit = DungeonKit.new(kit_scene)
	_floor_shape.size = Vector3(CELL, 0.2, CELL)
	_roof_mesh.size = Vector2(CELL, CELL)
	generate(seed)
	if give_player_torch:
		_give_player_torch()


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		generate(randi())


func _process(delta):
	_time += delta
	# Two out-of-step waves per torch, offset by its index so neighbours
	# don't pulse together.
	for i in _torches.size():
		_torches[i].light_energy = TORCH_ENERGY * _flicker(_time + i * 1.7)
	if _held_light:
		_held_light.light_energy = HELD_TORCH_ENERGY * _flicker(_time + 0.4)


func _flicker(t: float) -> float:
	return 1.0 + 0.12 * sin(t * 9.0) + 0.07 * sin(t * 23.0)


func generate(new_seed: int) -> void:
	seed = new_seed
	_rng.seed = seed
	for child in get_children():
		child.queue_free()
	cells.clear()
	rooms.clear()
	_doors.clear()
	_torches.clear()
	_layout()
	_build()
	_spawn_player()


func _layout() -> void:
	for i in room_attempts:
		var size := Vector2i(_rng.randi_range(room_min, room_max), _rng.randi_range(room_min, room_max))
		var pos := Vector2i(_rng.randi_range(0, grid_size.x - size.x), _rng.randi_range(0, grid_size.y - size.y))
		var rect := Rect2i(pos, size)
		# One cell of clearance keeps rooms from merging into each other,
		# leaving space for corridors to run between them.
		if rooms.any(func(r: Rect2i) -> bool: return r.grow(1).intersects(rect)):
			continue
		rooms.append(rect)
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				cells[Vector2i(x, y)] = ROOM
	# Joined in order along x, so corridors mostly run between neighbours
	# instead of criss-crossing the whole map.
	rooms.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
	for i in range(1, rooms.size()):
		_carve(_center(rooms[i - 1]), _center(rooms[i]))


func _carve(from: Vector2i, to: Vector2i) -> void:
	var p := from
	var x_first := _rng.randf() < 0.5
	while p != to:
		var step: Vector2i
		if (x_first and p.x != to.x) or p.y == to.y:
			step = Vector2i(signi(to.x - p.x), 0)
		else:
			step = Vector2i(0, signi(to.y - p.y))
		var q := p + step
		if not cells.has(q):
			cells[q] = CORRIDOR
		if cells[p] != cells[q]:
			_doors[_edge_key(p, q)] = true
		p = q


func _build() -> void:
	var corners := {}
	for cell in cells:
		var center := _cell_pos(cell)
		var floor_name := "FloorDebre" if _kit.has("FloorDebre") and _rng.randf() < debris_chance else "Floor"
		# Floors keep their authored height — debris dips below 0 on purpose.
		_place(floor_name, center, _rng.randi_range(0, 3) * PI / 2.0, _floor_shape, false, false)
		if roof_material:
			var roof := MeshInstance3D.new()
			roof.mesh = _roof_mesh
			roof.material_override = roof_material
			roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			roof.position = center + Vector3.UP * roof_height
			add_child(roof)

		for dir in DIRS:
			var other: Vector2i = cell + dir
			var piece := ""
			if not cells.has(other):
				piece = "Wall"
			elif cells[cell] == ROOM and cells[other] == CORRIDOR:
				# Only the room side places the edge, so it isn't built twice.
				piece = "Doorway" if _doors.has(_edge_key(cell, other)) else "Wall"
			if piece == "":
				continue
			var along := Vector3(absi(dir.y), 0, absi(dir.x))
			var start := center + Vector3(dir.x, 0, dir.y) * CELL / 2.0 - along * CELL / 2.0
			_place_edge(piece, start, along)
			corners[_corner_key(start)] = true
			corners[_corner_key(start + along * CELL)] = true
			if piece == "Wall" and _kit.has("Torchy") and _rng.randf() < torch_chance:
				_place_torch(start + along * CELL / 2.0, -Vector3(dir.x, 0, dir.y))

		if cells[cell] == ROOM and not _has_door(cell) and _rng.randf() < prop_chance:
			var prop := "Crate" if _rng.randf() < 0.5 else "Barrel"
			var offset := Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0))
			_place(prop, center + offset, _rng.randf() * TAU, null, true)

	for corner in corners:
		_place("Pillar", Vector3((corner.x - 0.5) * CELL, 0, (corner.y - 0.5) * CELL), 0.0)


func _place_edge(category: String, start: Vector3, along: Vector3) -> void:
	# Wall pieces start at one end and run 4 m along their local +X.
	var piece := _kit.pick(category, _rng)
	var rot := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	_add(piece, Transform3D(rot * piece.basis, start + Vector3.UP * piece.lift), piece.shape_for(true))


func _place(category: String, pos: Vector3, yaw: float, shape: Shape3D = null, convex := false, lift := true) -> void:
	if not _kit.has(category):
		return
	var piece := _kit.pick(category, _rng)
	if shape == null:
		shape = piece.shape_for(not convex)
	var rot := Basis(Vector3.UP, yaw) * piece.basis
	_add(piece, Transform3D(rot, pos + Vector3.UP * (piece.lift if lift else 0.0)), shape)


func _place_torch(wall_mid: Vector3, inward: Vector3) -> void:
	var piece := _kit.pick("Torchy", _rng)
	var pos := wall_mid + inward * 0.45 + Vector3.UP * 1.4
	var torch := _add(piece, Transform3D(piece.basis, pos), null)
	_dress_torch(torch)
	var light := OmniLight3D.new()
	light.light_color = torch_color
	light.light_energy = TORCH_ENERGY
	light.omni_range = 7.0
	# Without shadows the light passes straight through walls into the
	# rooms next door.
	light.shadow_enabled = true
	light.position = pos + Vector3.UP * 0.8 + inward * 0.2
	add_child(light)
	_torches.append(light)


func _give_player_torch() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not _kit.has("Torchy"):
		return
	var piece := _kit.pick("Torchy", _rng)
	# Low and to the right of the view, leaning in a little, like it's held
	# out in front.
	var holder := Node3D.new()
	holder.position = Vector3(0.3, -0.42, -0.55)
	holder.rotation = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(8.0))
	holder.scale = Vector3.ONE * 0.6
	player.camera.add_child(holder)
	var mi := MeshInstance3D.new()
	mi.mesh = piece.mesh
	mi.basis = piece.basis
	holder.add_child(mi)
	_dress_torch(mi)
	_held_light = OmniLight3D.new()
	_held_light.light_color = torch_color
	_held_light.light_energy = HELD_TORCH_ENERGY
	_held_light.omni_range = 9.0
	_held_light.shadow_enabled = true
	_held_light.position = Vector3(0.0, 0.75, 0.0)
	holder.add_child(_held_light)


## Shadow casting off (its light sits inside it, so it would throw a
## torch-shaped shadow up the wall) and the flame swapped for one shared
## material that torch_color can tint in one place.
func _dress_torch(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i)
		if mat == null or mat.resource_name != "flame":
			continue
		if _flame_material == null:
			_flame_material = mat.duplicate()
			_apply_torch_color()
		mi.set_surface_override_material(i, _flame_material)


func _apply_torch_color() -> void:
	for light in _torches:
		light.light_color = torch_color
	if _held_light:
		_held_light.light_color = torch_color
	if _flame_material:
		_flame_material.albedo_color = torch_color
		_flame_material.emission = torch_color
		_flame_material.emission_energy_multiplier = FLAME_GLOW


func _add(piece: DungeonKit.Piece, xform: Transform3D, shape: Shape3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = piece.mesh
	mi.transform = xform
	add_child(mi)
	if shape:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		mi.add_child(body)
		if shape == _floor_shape:
			# A flat box rather than the tile's mesh, so loose debris doesn't
			# snag the player's capsule.
			col.position = Vector3(0, -0.1, 0)
	return mi


func _spawn_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or rooms.is_empty():
		return
	player.global_position = global_transform * _cell_pos(_center(rooms[0])) + Vector3.UP * 0.1
	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO


## Props stay out of these cells so nothing can block a way in or out.
func _has_door(cell: Vector2i) -> bool:
	for dir in DIRS:
		if _doors.has(_edge_key(cell, cell + dir)):
			return true
	return false


func _cell_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL, 0, cell.y * CELL)


func _center(rect: Rect2i) -> Vector2i:
	return rect.position + rect.size / 2


func _corner_key(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / CELL + 0.5), roundi(world.z / CELL + 0.5))


func _edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var t := a
		a = b
		b = t
	return Vector4i(a.x, a.y, b.x, b.y)
