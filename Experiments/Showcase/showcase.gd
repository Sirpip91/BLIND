extends Node

## Turntable for showing off models: load one, light and frame it, then save
## a looping GIF, PNG frames or a still. No player here, so it doesn't start
## from Core/sandbox.tscn. The preview is rendered at the size it saves at,
## so what's on screen is what comes out.
## Physics interpolation is off on View: it would smooth each pose towards
## the last one, and recordings need them exact. (It has to be set there; a
## viewport turns it on for itself whatever its parent says.)

@onready var view: SubViewport = $View
@onready var turntable: Node3D = $View/Turntable
@onready var camera: Camera3D = $View/Camera
@onready var environment: Environment = $View/WorldEnvironment.environment
@onready var key_light: DirectionalLight3D = $View/Key
@onready var rim_light: DirectionalLight3D = $View/Rim
@onready var pedestal: MeshInstance3D = $View/Pedestal
@onready var ink_pass: MeshInstance3D = $View/InkPass
@onready var recorder: Node = $Recorder
@onready var ui: CanvasLayer = $UI

var model_path := ""

var _ink: ShaderMaterial
var _phase := 0.0
var _recording := false
var _shown_look := -1


func _ready():
	# A private copy, so tuning it here never changes another scene's ink.
	ink_pass.mesh = ink_pass.mesh.duplicate()
	_ink = ink_pass.mesh.surface_get_material(0).duplicate()
	ink_pass.mesh.surface_set_material(0, _ink)
	# Models here are a fixed size, so nothing should fade with distance.
	_ink.set_shader_parameter("fade_start", 1000.0)
	_ink.set_shader_parameter("fade_end", 2000.0)

	ui.preview.texture = view.get_texture()
	ui.preview.gui_input.connect(_on_preview_input)
	ui.model_chosen.connect(show_model)
	ui.action.connect(_on_action)
	recorder.progressed.connect(ui.set_progress)
	get_window().files_dropped.connect(func(files): show_model(files[0]))

	var models := _find_models("res://Assets")
	ui.list_models(models)
	var last: String = ui.last_model()
	if last != "" and (models.has(last) or FileAccess.file_exists(last)):
		show_model(last)
	elif not models.is_empty():
		show_model(models[0])


func _exit_tree():
	ui.save_settings(model_path)


func _process(delta):
	if _recording:
		return
	if ui.values.spin:
		_phase = fposmod(_phase + delta / ui.values.seconds, 1.0)
	pose(_phase, -1.0)


func show_model(path: String) -> void:
	if _recording:
		return
	var error: Error = turntable.load_model(path)
	if error != OK:
		ui.say("Couldn't load %s (%s)" % [path.get_file(), error_string(error)])
		return
	model_path = path
	ui.show_model(path, turntable.real_size)


## Everything on screen at one moment. `phase` is progress through a turn;
## `clock` drives the outline flicker, or is negative for real time.
func pose(phase: float, clock: float) -> void:
	var v: Dictionary = ui.values
	var size: Vector2i = ui.SIZES[v.size]
	var scale := 2 if v.smooth else 1
	if view.size != size * scale:
		view.size = size * scale

	turntable.pose(-phase if v.reverse else phase, v.tilt, v.lean, v.own_axis)
	if v.look != _shown_look:
		_shown_look = v.look
		turntable.set_ink(v.look == 0)
	pedestal.visible = v.pedestal
	var radius := clampf(turntable.footprint() * 1.3, 0.25, 1.0)
	pedestal.scale = Vector3(radius, 1.0, radius)
	pedestal.position.y = turntable.lowest(v.tilt, v.lean, v.own_axis) - 0.03

	# Both moves end where they began, so the loop has no seam.
	var swell := 0.5 - 0.5 * cos(phase * TAU)
	camera.frame(v.yaw, v.pitch + v.rise * swell, v.zoom * (1.0 + v.push * swell),
			Vector2(v.pan_x, v.pan_y), v.lens, float(size.x) / size.y)

	environment.background_color = Color.from_hsv(0.0, 0.0, v.background)
	environment.ambient_light_energy = v.ambient
	key_light.light_energy = v.key
	key_light.visible = v.key > 0.0
	# Lights are set relative to the camera's home angle, so they stay put in
	# frame as you orbit to choose a view.
	key_light.rotation_degrees = Vector3(-v.key_pitch, v.yaw + v.key_yaw, 0.0)
	rim_light.light_energy = v.rim
	rim_light.visible = v.rim > 0.0
	rim_light.rotation_degrees = Vector3(-20.0, v.yaw + v.key_yaw + 190.0, 0.0)

	ink_pass.visible = v.outlines
	_ink.set_shader_parameter("outline_px", v.outline * scale)
	_ink.set_shader_parameter("boil_amount", v.flicker)
	_ink.set_shader_parameter("boil_clock", clock)
	_ink.set_shader_parameter("saturation", v.color)
	_ink.set_shader_parameter("paper_grain", v.grain)
	_ink.set_shader_parameter("vignette", v.vignette)


func _on_action(what: String) -> void:
	var size: Vector2i = ui.SIZES[ui.values.size]
	match what:
		"cancel":
			recorder.cancelled = true
		"folder":
			OS.shell_open(_folder())
		"still":
			if not _recording:
				var path := _save_path(".png")
				_report(await recorder.still(view, size, path), path)
		"gif", "frames":
			if not _recording:
				await record(what)


func record(what: String) -> void:
	var v: Dictionary = ui.values
	var size: Vector2i = ui.SIZES[v.size]
	var rate: int = ui.RATES[v.rate]
	var path := _save_path(".gif" if what == "gif" else "")
	_recording = true
	ui.set_busy(true)
	var error: Error
	if what == "gif":
		error = await recorder.gif(view, pose, v.seconds, rate, size, path)
	else:
		error = await recorder.png_frames(view, pose, v.seconds, rate, size, path)
	_recording = false
	ui.set_busy(false)
	_report(error, path)


func _report(error: Error, path: String) -> void:
	if error == ERR_SKIP:
		ui.say("Cancelled.")
	elif error != OK:
		ui.say("Couldn't save: %s" % error_string(error))
	elif path.ends_with(".gif"):
		var file := FileAccess.open(path, FileAccess.READ)
		ui.say("Saved %s (%.1f MB)" % [path, file.get_length() / 1048576.0])
	else:
		ui.say("Saved %s" % path)


func _folder() -> String:
	var folder := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Showcase")
	DirAccess.make_dir_recursive_absolute(folder)
	return folder


func _save_path(extension: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	return _folder().path_join("%s_%s%s" % [model_path.get_file().get_basename(), stamp, extension])


func _find_models(folder: String) -> PackedStringArray:
	var found := PackedStringArray()
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_find_models(folder.path_join(sub)))
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() in ["glb", "gltf", "fbx", "tscn"]:
			found.append(folder.path_join(file))
	return found


func _on_preview_input(event: InputEvent) -> void:
	if _recording:
		return
	var v: Dictionary = ui.values
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			ui.set_value("yaw", wrapf(v.yaw - event.relative.x * 0.4, -180.0, 180.0))
			ui.set_value("pitch", clampf(v.pitch + event.relative.y * 0.4, -85.0, 85.0))
		elif event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			ui.set_value("pan_x", v.pan_x + event.relative.x * 0.003 / v.zoom)
			ui.set_value("pan_y", v.pan_y - event.relative.y * 0.003 / v.zoom)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			ui.set_value("zoom", v.zoom * 1.06)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ui.set_value("zoom", v.zoom / 1.06)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				ui.set_value("spin", not ui.values.spin)
			KEY_F:
				ui.reframe()
			KEY_H:
				ui.toggle_panel()
