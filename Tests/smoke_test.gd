extends SceneTree

## Headless check that everything still loads and the core rig works:
##   godot --headless --path . -s res://Tests/smoke_test.gd
## Exits non-zero on any failure.

const SCAN_DIRS = ["res://Core", "res://Experiments"]

var _failures: Array[String] = []


func _initialize():
	for dir in SCAN_DIRS:
		_check_scenes_in(dir)
	await _check_sandbox()
	if _failures.is_empty():
		print("PASS")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _check_scenes_in(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_check_scenes_in(path.path_join(sub))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			# A scene still instantiates when its script is broken, so scripts
			# are checked on their own.
			var script := load(path.path_join(file)) as GDScript
			if script == null or not script.can_instantiate():
				_failures.append("%s failed to compile" % path.path_join(file))
		if not file.ends_with(".tscn"):
			continue
		var scene_path := path.path_join(file)
		var scene := load(scene_path) as PackedScene
		if scene == null:
			_failures.append("%s failed to load" % scene_path)
			continue
		var node := scene.instantiate()
		if node == null:
			_failures.append("%s failed to instantiate" % scene_path)
		else:
			node.free()


func _check_sandbox() -> void:
	# The root isn't in the tree yet during _initialize.
	await process_frame
	var sandbox: Node = (load("res://Core/sandbox.tscn") as PackedScene).instantiate()
	root.add_child(sandbox)
	var player: CharacterBody3D = sandbox.get_node("Player")
	player.global_position = Vector3(0, 3, 0)
	for i in 120:
		await physics_frame
	if not player.is_on_floor():
		_failures.append("player didn't land on the stage floor (y = %.2f)" % player.global_position.y)

	var fly_cam: Camera3D = sandbox.get_node("FlyCam")
	sandbox._set_flying(true)
	await process_frame
	if not fly_cam.current:
		_failures.append("fly cam didn't take over the view")
	if fly_cam.global_position.distance_to(player.camera.global_position) > 0.01:
		_failures.append("fly cam didn't start from the player's view")
	sandbox._set_flying(false)
	await process_frame
	if not player.camera.current:
		_failures.append("player camera didn't get the view back")
	sandbox.free()
