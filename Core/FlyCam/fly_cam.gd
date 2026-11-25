extends Camera3D

@export var mouse_sensitivity := 0.002
@export var speed := 5.0
@export var sprint_multiplier := 4.0

const MIN_SPEED = 0.25
const MAX_SPEED = 100.0
const LOOK_LIMIT = deg_to_rad(89.0)

var _yaw := 0.0
var _pitch := 0.0


func _ready():
	_yaw = rotation.y
	_pitch = rotation.x


## Jumps to another camera's view — so switching from the player doesn't
## teleport the viewpoint.
func match_view(other: Camera3D) -> void:
	global_position = other.global_position
	var forward := -other.global_basis.z
	_yaw = atan2(-forward.x, -forward.z)
	_pitch = clampf(asin(forward.y), -LOOK_LIMIT, LOOK_LIMIT)
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -LOOK_LIMIT, LOOK_LIMIT)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed:
		# Scroll sets cruising speed, multiplicative so it's useful from
		# inspecting a prop up close to crossing a whole level.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.2, MAX_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.2, MIN_SPEED)


func _process(delta):
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var rise := Input.get_axis("fly_down", "fly_up")
	var move := global_basis * Vector3(input_dir.x, 0.0, input_dir.y) + Vector3.UP * rise
	if move == Vector3.ZERO:
		return
	var current := speed * (sprint_multiplier if Input.is_action_pressed("sprint") else 1.0)
	global_position += move.normalized() * current * delta
