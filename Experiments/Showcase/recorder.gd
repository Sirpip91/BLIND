extends Node

## Records one full turn. Each frame is posed, rendered and saved in its own
## time, so the result is smooth and loops exactly however slow saving is.

const Gif = preload("res://Experiments/Showcase/gif_encoder.gd")

signal progressed(amount: float, what: String)

## Posed angles the GIF palette is sampled from.
const PALETTE_SAMPLES := 8
const MAX_PENDING := 24

var cancelled := false

var _mutex := Mutex.new()
var _results := {}


## `pose` is called as pose(phase, clock) before each frame.
func gif(view: SubViewport, pose: Callable, seconds: float, fps: int, size: Vector2i, path: String) -> Error:
	cancelled = false
	_results.clear()
	var count := maxi(roundi(seconds * fps), 2)
	var encoder := Gif.new()
	var samples: Array[Image] = []
	for i in PALETTE_SAMPLES:
		pose.call(float(i) / PALETTE_SAMPLES, 0.0)
		samples.append(_fit(await _grab(view), size))
	encoder.build_palette(samples)

	var tasks: Array[int] = []
	var is_ramp: bool = encoder.ramp
	var table: PackedByteArray = encoder.lookup
	for i in count:
		pose.call(float(i) / count, float(i) / fps)
		var image := await _grab(view)
		if tasks.size() >= MAX_PENDING:
			WorkerThreadPool.wait_for_task_completion(tasks.pop_front())
		tasks.append(WorkerThreadPool.add_task(func(): _store(i, Gif.quantise(_fit(image, size), is_ramp, table)), true))
		progressed.emit(0.6 * (i + 1) / count, "Frame %d of %d" % [i + 1, count])
		if cancelled:
			break
	for task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	if cancelled:
		_results.clear()
		return ERR_SKIP

	var indexed := _results
	_results = {}
	var delay := roundi(100.0 / fps)
	tasks.clear()
	for i in count:
		var current: PackedByteArray = indexed[i]
		var previous: PackedByteArray = indexed[i - 1] if i > 0 else PackedByteArray()
		tasks.append(WorkerThreadPool.add_task(func(): _store(i, Gif.encode_frame(current, previous, size, delay)), true))
	for i in count:
		while not WorkerThreadPool.is_task_completed(tasks[i]):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(tasks[i])
		progressed.emit(0.6 + 0.4 * (i + 1) / count, "Compressing %d of %d" % [i + 1, count])
	var frames := []
	for i in count:
		frames.append(_results[i])
	_results.clear()
	return _write(path, encoder.assemble(frames, size))


## Numbered PNGs into `folder`, for a video editor.
func png_frames(view: SubViewport, pose: Callable, seconds: float, fps: int, size: Vector2i, folder: String) -> Error:
	cancelled = false
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		return error
	var count := maxi(roundi(seconds * fps), 2)
	for i in count:
		pose.call(float(i) / count, float(i) / fps)
		error = _fit(await _grab(view), size).save_png(folder.path_join("frame_%04d.png" % i))
		if error != OK:
			return error
		progressed.emit(float(i + 1) / count, "Frame %d of %d" % [i + 1, count])
		if cancelled:
			return ERR_SKIP
	return OK


func still(view: SubViewport, size: Vector2i, path: String) -> Error:
	return _fit(await _grab(view), size).save_png(path)


func _grab(view: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


static func _fit(image: Image, size: Vector2i) -> Image:
	image.convert(Image.FORMAT_RGB8)
	if image.get_size() != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return image


func _store(index: int, data: PackedByteArray) -> void:
	_mutex.lock()
	_results[index] = data
	_mutex.unlock()


func _write(path: String, data: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(data)
	return OK
