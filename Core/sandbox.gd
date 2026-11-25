extends Node3D

## Tab swaps between walking and flying. Escape frees the mouse; click to
## take it back.

## Off for experiments that bring their own ground.
@export var show_floor := true
## Off for experiments that bring their own sky and light.
@export var use_stage_lighting := true

@onready var player: CharacterBody3D = $Player
@onready var fly_cam: Camera3D = $FlyCam

var flying := false


func _ready():
	if not show_floor:
		$Stage/Floor.queue_free()
	if not use_stage_lighting:
		# free(), not queue_free(), so the experiment's WorldEnvironment
		# isn't left competing with this one for a frame.
		$Stage/WorldEnvironment.free()
		$Stage/Sun.free()
	_set_flying(false)


func _unhandled_input(event):
	if event.is_action_pressed("toggle_view"):
		_set_flying(not flying)
	elif event.is_action_pressed("escape"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _set_flying(value: bool) -> void:
	flying = value
	if flying:
		fly_cam.match_view(player.camera)
		fly_cam.make_current()
	else:
		player.camera.make_current()
	# Disabled rather than just unfocused, so the parked one ignores input
	# and the player doesn't keep simulating while you're off looking around.
	player.process_mode = Node.PROCESS_MODE_DISABLED if flying else Node.PROCESS_MODE_INHERIT
	fly_cam.process_mode = Node.PROCESS_MODE_INHERIT if flying else Node.PROCESS_MODE_DISABLED
