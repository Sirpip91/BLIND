extends Decal

## Ink let into the paper of the ground, still spreading.

const GROUP := "steel_guard_remains"
const SEEP := 2.5

static var _blot: ImageTexture


func spread(at: Vector3, wide: float) -> void:
	add_to_group(GROUP)
	if _blot == null:
		_blot = _paint()
	texture_albedo = _blot
	upper_fade = 0.1
	lower_fade = 0.1
	global_position = Vector3(at.x, 0.0, at.z)
	rotation.y = randf() * TAU
	size = Vector3(wide * 0.15, 0.06, wide * 0.15)
	create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART) \
			.tween_property(self, "size", Vector3(wide, 0.06, wide), SEEP)


static func _paint() -> ImageTexture:
	var wide := 128
	var image := Image.create(wide, wide, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	for x in wide:
		for y in wide:
			var p := (Vector2(x, y) / (wide - 1) - Vector2.ONE * 0.5) * 2.0
			var edge := 0.62 + 0.3 * noise.get_noise_2d(x, y) + 0.16 * noise.get_noise_2d(x * 3.0, y * 3.0)
			image.set_pixel(x, y, Color(0.42, 0.01, 0.015, smoothstep(edge, edge - 0.09, p.length()) * 0.92))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
