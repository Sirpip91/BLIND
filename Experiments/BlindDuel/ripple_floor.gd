extends MeshInstance3D

## Draws sound on the floor. Oldest ripples give way when there are too many.

const MAX := 24

var _material: ShaderMaterial
var _drops: PackedVector4Array
var _shapes: PackedVector4Array
var _next := 0
var _now := 0.0


func _ready():
	_material = get_active_material(0)
	_drops.resize(MAX)
	_shapes.resize(MAX)


func drop(at: Vector3, strength: float, radius: float, life: float, rings := 3) -> void:
	_drops[_next] = Vector4(at.x, at.z, _now, life)
	_shapes[_next] = Vector4(radius, strength, rings, randf() * 100.0)
	_next = (_next + 1) % MAX
	_material.set_shader_parameter("drops", _drops)
	_material.set_shader_parameter("shapes", _shapes)


## How many are still spreading.
func live() -> int:
	var count := 0
	for d in _drops:
		if d.w > 0.0 and _now - d.z < d.w:
			count += 1
	return count


func _process(delta):
	# Its own clock, so ripples freeze and slow along with everything else.
	_now += delta
	_material.set_shader_parameter("now", _now)
