extends RefCounted

## Writes animated GIFs. Build a palette from sample images, quantise each
## frame to palette indices, then encode. Quantising and encoding are static
## and touch nothing shared, so frames can run on worker threads.

## Palette slot marking "same as the previous frame", which is what keeps a
## mostly still turntable small.
const SAME := 255
const RAMP_LEVELS := 128
## Channel spread, out of 255, still treated as a tinted grey.
const GREY_TOLERANCE := 24

## 256 RGB triplets.
var palette := PackedByteArray()
## True when colours run along one light-to-dark ramp, looked up by lightness.
var ramp := true
## Colour mode: palette index for each 5-bit-per-channel colour.
var lookup := PackedByteArray()


## `samples` are RGB8 images.
func build_palette(samples: Array[Image]) -> void:
	palette.resize(256 * 3)
	palette.fill(0)
	var counts := {}
	var sums := PackedInt64Array()
	sums.resize(RAMP_LEVELS * 4)
	var coloured := 0
	var total := 0
	for image in samples:
		var data := image.get_data()
		for i in range(0, data.size() - 2, 9):
			var r := data[i]
			var g := data[i + 1]
			var b := data[i + 2]
			total += 1
			if maxi(r, maxi(g, b)) - mini(r, mini(g, b)) > GREY_TOLERANCE:
				coloured += 1
			var level := ((r * 2 + g * 5 + b) >> 3) * RAMP_LEVELS >> 8
			sums[level * 4] += r
			sums[level * 4 + 1] += g
			sums[level * 4 + 2] += b
			sums[level * 4 + 3] += 1
			var key := (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
			counts[key] = counts.get(key, 0) + 1
	# A few fringe pixels don't make a colour image.
	ramp = coloured < total * 0.002
	if ramp:
		_build_ramp(sums)
	else:
		_build_boxes(counts)


func _build_ramp(sums: PackedInt64Array) -> void:
	for level in RAMP_LEVELS:
		var n := sums[level * 4 + 3]
		for c in 3:
			palette[level * 3 + c] = sums[level * 4 + c] / n if n > 0 else level * 256 / RAMP_LEVELS


## Median cut. The boxes partition the whole colour cube rather than just the
## colours sampled, so one that only turns up later still lands in a box.
func _build_boxes(counts: Dictionary) -> void:
	var boxes: Array[Dictionary] = [{"lo": Vector3i.ZERO, "hi": Vector3i(31, 31, 31), "keys": counts.keys()}]
	while boxes.size() < SAME:
		var best := -1
		var best_score := 0
		var best_axis := 0
		for i in boxes.size():
			if not boxes[i].has("score"):
				_score(boxes[i], counts)
			if boxes[i].score > best_score:
				best = i
				best_score = boxes[i].score
				best_axis = boxes[i].axis
		if best < 0:
			break
		var box: Dictionary = boxes[best]
		var shift := 10 - best_axis * 5
		var tally := PackedInt64Array()
		tally.resize(32)
		for key: int in box["keys"]:
			tally[key >> shift & 31] += counts[key]
		var half: int = box["weight"] / 2
		var seen := 0
		var cut: int = box["min"]
		for v in range(box["min"], box["max"]):
			cut = v
			seen += tally[v]
			if seen >= half:
				break
		var low := {"lo": box["lo"], "hi": box["hi"], "keys": []}
		var high := {"lo": box["lo"], "hi": box["hi"], "keys": []}
		var edge: Vector3i = low["hi"]
		edge[best_axis] = cut
		low["hi"] = edge
		edge = high["lo"]
		edge[best_axis] = cut + 1
		high["lo"] = edge
		for key: int in box["keys"]:
			(low if key >> shift & 31 <= cut else high)["keys"].append(key)
		boxes[best] = low
		boxes.append(high)

	lookup.resize(32768)
	for i in boxes.size():
		var box: Dictionary = boxes[i]
		var sum := Vector3.ZERO
		var weight := 0
		for key: int in box["keys"]:
			var n: int = counts[key]
			sum += Vector3(key >> 10 & 31, key >> 5 & 31, key & 31) * n
			weight += n
		var lo: Vector3i = box["lo"]
		var hi: Vector3i = box["hi"]
		var mean := sum / weight if weight > 0 else Vector3(lo + hi) * 0.5
		for c in 3:
			palette[i * 3 + c] = clampi(roundi(mean[c] * 255.0 / 31.0), 0, 255)
		for r in range(lo.x, hi.x + 1):
			for g in range(lo.y, hi.y + 1):
				for b in range(lo.z, hi.z + 1):
					lookup[r << 10 | g << 5 | b] = i


func _score(box: Dictionary, counts: Dictionary) -> void:
	var lo := Vector3i(31, 31, 31)
	var hi := Vector3i.ZERO
	var weight := 0
	for key: int in box["keys"]:
		var v := Vector3i(key >> 10 & 31, key >> 5 & 31, key & 31)
		lo = lo.min(v)
		hi = hi.max(v)
		weight += counts[key]
	var axis := 0
	for a in [1, 2]:
		if hi[a] - lo[a] > hi[axis] - lo[axis]:
			axis = a
	box["axis"] = axis
	box["weight"] = weight
	box["min"] = lo[axis]
	box["max"] = hi[axis]
	box["score"] = weight * (hi[axis] - lo[axis]) if hi[axis] > lo[axis] else 0


## One palette index per pixel of an RGB8 image.
static func quantise(image: Image, is_ramp: bool, table: PackedByteArray) -> PackedByteArray:
	var data := image.get_data()
	var count := data.size() / 3
	var out := PackedByteArray()
	out.resize(count)
	var at := 0
	if is_ramp:
		for i in count:
			out[i] = ((data[at] * 2 + data[at + 1] * 5 + data[at + 2]) >> 3) * RAMP_LEVELS >> 8
			at += 3
	else:
		for i in count:
			out[i] = table[(data[at] >> 3) << 10 | (data[at + 1] >> 3) << 5 | (data[at + 2] >> 3)]
			at += 3
	return out


## One frame's bytes. `previous` is empty for the first frame.
static func encode_frame(indices: PackedByteArray, previous: PackedByteArray, size: Vector2i, delay_cs: int) -> PackedByteArray:
	var out := PackedByteArray([0x21, 0xF9, 4, 0x05, delay_cs & 255, delay_cs >> 8, SAME, 0, 0x2C, 0, 0, 0, 0,
			size.x & 255, size.x >> 8, size.y & 255, size.y >> 8, 0, 8])
	var pixels := indices
	if not previous.is_empty():
		pixels = indices.duplicate()
		for i in pixels.size():
			if pixels[i] == previous[i]:
				pixels[i] = SAME
	var packed := _lzw(pixels)
	var at := 0
	while at < packed.size():
		var block := packed.slice(at, at + 255)
		out.append(block.size())
		out.append_array(block)
		at += 255
	out.append(0)
	return out


static func _lzw(pixels: PackedByteArray) -> PackedByteArray:
	const CLEAR := 256
	const END := 257
	var out := PackedByteArray()
	var codes := {}
	var next := 258
	var width := 9
	var bits := CLEAR
	var held := 9
	var prefix := pixels[0]
	for i in range(1, pixels.size()):
		var value := pixels[i]
		var key := prefix << 8 | value
		var known: int = codes.get(key, -1)
		if known >= 0:
			prefix = known
			continue
		bits |= prefix << held
		held += width
		while held >= 8:
			out.append(bits & 255)
			bits >>= 8
			held -= 8
		if next < 4096:
			codes[key] = next
			if next == 1 << width:
				width += 1
			next += 1
		else:
			bits |= CLEAR << held
			held += width
			codes.clear()
			next = 258
			width = 9
		prefix = value
	bits |= prefix << held
	held += width
	if next < 4096 and next == 1 << width:
		width += 1
	bits |= END << held
	held += width
	while held > 0:
		out.append(bits & 255)
		bits >>= 8
		held -= 8
	return out


## The complete file, looping forever.
func assemble(frames: Array, size: Vector2i) -> PackedByteArray:
	var out := "GIF89a".to_ascii_buffer()
	out.append_array(PackedByteArray([size.x & 255, size.x >> 8, size.y & 255, size.y >> 8, 0xF7, 0, 0]))
	out.append_array(palette)
	out.append_array(PackedByteArray([0x21, 0xFF, 11]))
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	out.append_array(PackedByteArray([3, 1, 0, 0, 0]))
	for frame: PackedByteArray in frames:
		out.append_array(frame)
	out.append(0x3B)
	return out
