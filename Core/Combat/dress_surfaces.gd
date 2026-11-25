extends Node3D

## Swaps materials on an imported model by the material names it came with,
## so each part (blade, handle) can be dressed without editing the model.

@export var surface_materials: Dictionary[String, Material] = {}


func _ready():
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(i)
			if original and surface_materials.has(original.resource_name):
				mesh.set_surface_override_material(i, surface_materials[original.resource_name])
