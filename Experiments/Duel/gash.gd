extends Decal

## A cut left in cloth: one dry stroke of red, painted onto the body and
## nothing else.

const LAYER := 1 << 1

static var _stroke: ImageTexture
static var _glow: ImageTexture


## Through `at`, facing `out`, running the way the blade went as the attacker
## saw it.
func lay(at: Vector3, out: Vector3, direction: Vector2, length: float) -> void:
	if _stroke == null:
		var painted := _paint()
		_stroke = ImageTexture.create_from_image(painted)
		# Emission takes no notice of alpha.
		painted.premultiply_alpha()
		_glow = ImageTexture.create_from_image(painted)
	texture_albedo = _stroke
	texture_emission = _glow
	emission_energy = 0.25
	cull_mask = LAYER
	upper_fade = 0.01
	lower_fade = 0.01
	var right := Vector3.UP.cross(out).normalized()
	var way := direction if direction.length() > 0.1 else Vector2(0.3, -1.0)
	# Whoever struck it stood on the far side of `out`, looking in.
	var along := (right * way.x + Vector3.UP * way.y).normalized()
	basis = Basis(along, out, along.cross(out).normalized())
	position = at + out * 0.25
	size = Vector3(length, 0.5, 0.1 if direction.length() > 0.1 else 0.07)


static func _paint() -> Image:
	var wide := 256
	var high := 48
	var image := Image.create(wide, high, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	for x in wide:
		var t := float(x) / (wide - 1)
		# Pressed where it went in, dragged thin where it came out.
		var half := 0.62 * pow(sin(PI * pow(t, 0.62)), 1.9) * (1.0 + 0.5 * noise.get_noise_1d(x * 1.6))
		for y in high:
			var v := absf(float(y) / (high - 1) * 2.0 - 1.0 + 0.2 * noise.get_noise_1d(x * 0.5 + 900.0))
			var inside := smoothstep(half, half - 0.12, v)
			# The hairs part toward the end.
			var hairs := noise.get_noise_2d(x * 0.35, y * 11.0) * 0.5 + 0.5
			inside *= smoothstep(t * 0.8 - 0.25, t * 0.8 - 0.05, hairs)
			image.set_pixel(x, y, Color(0.6, 0.012, 0.012, inside))
	image.generate_mipmaps()
	return image
