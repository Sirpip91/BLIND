extends CharacterBody3D

@export var mouse_sensitivity := 0.002

var speed
const WALK_SPEED = 2.5
const CROUCH_SPEED = 2
const SPRINT_SPEED = 4.5
# Real-world scale (1.8 m tall) so Blender assets built in metres fit as-is.
const HEAD_HEIGHT = 1.65
const CROUCH_DEPTH = -0.6
const lerp_speed = 10

#bob variables — stride is metres per step, amp is how far the head moves
const STRIDE = 1.65
const STRIDE_CROUCH = 1.2
const STRIDE_SPRINT = 2.1
const BOB_AMP = 0.05
const BOB_AMP_CROUCH = 0.025
const BOB_AMP_SPRINT = 0.06
# Above 1 rounds off the dip as each foot lands — 1 is a hard snap.
const STEP_SOFTNESS = 1.4
# Head pitched forward at a full sprint, like driving into the run.
const SPRINT_LEAN = deg_to_rad(1.0)
# Where the walk cycle is, in half-turns per step — advanced by distance over
# the current stride, so switching stance changes pace without a jump.
var _bob_phase := 0.0
var _stride := STRIDE
# Standing still the camera settles into a slow breathing drift instead of
# freezing wherever the bob happened to stop.
const BREATH_AMP = 0.006
const BREATH_SPEED = 1.4
const STRAFE_TILT = deg_to_rad(0.6)
# The view tips down this much as each foot lands.
const STEP_NOD = deg_to_rad(0.15)

## Fires as each foot lands, synced to the camera's dip — for footstep audio.
## strength is 0..1 by how fast the player's going (crouch soft, sprint heavy).
signal footstep(strength: float)

var _step_index := 0
var _nod := 0.0
# The player's own up/down look, before the nod and lean go on top.
var _pitch := 0.0
const LOOK_LIMIT = deg_to_rad(89.0)
var _sprint_lean := 0.0
const LAND_DIP_MAX = 0.12

#fov variables
const BASE_FOV = 75.0
const SPRINT_FOV_BOOST = 6.0
const CROUCH_FOV_DROP = 3.0

## What the view settles to at a walk.
var base_fov := BASE_FOV

var _bob_weight := 0.0
var _bob_amp := BOB_AMP
var _breath_t := 0.0
var _land_offset := 0.0
var _fall_speed := 0.0

var _shake_offset: Vector2 = Vector2.ZERO
var _fov_override: bool = false

var movement_locked: bool = false

var gravity = 9.8

var crouched: bool = false


@onready var head = $Head
@onready var camera = $Head/Camera3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pitch = camera.rotation.x
	camera.make_current()
	# Extra recovery slack and slide iterations so the capsule doesn't hang up
	# on imperfect level collision (uneven hulls, seams between pieces) —
	# Godot's defaults (0.001 margin, 4 slides) are too tight for that.
	safe_margin = 0.15
	max_slides = 8


func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if movement_locked:
			return
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		_look_pitch(-event.relative.y * mouse_sensitivity)


## Turns the view to look at a point — a cutscene following whoever's talking.
func face_point(point: Vector3, seconds: float = 0.6) -> void:
	var to: Vector3 = point - (camera as Camera3D).global_position
	var yaw: float = atan2(-to.x, -to.z) - rotation.y
	var pitch: float = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -LOOK_LIMIT, LOOK_LIMIT)
	var turn := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	turn.tween_property(head, "rotation:y", head.rotation.y + wrapf(yaw - head.rotation.y, -PI, PI), seconds)
	turn.tween_method(func(value: float) -> void:
		_pitch = value
		_apply_pitch(), _pitch, pitch, seconds)


## Up/down look. The player's own pitch is kept separately from the footstep
## nod and sprint lean layered on top of it, and the sum is clamped short of
## straight up/down — past vertical the camera would flip over.
func _look_pitch(amount: float) -> void:
	_pitch = clampf(_pitch + amount, -LOOK_LIMIT, LOOK_LIMIT)
	_apply_pitch()


func _apply_pitch() -> void:
	camera.rotation.x = clampf(_pitch + _nod, -LOOK_LIMIT, LOOK_LIMIT)


func _physics_process(delta):
	if movement_locked:
		velocity = Vector3.ZERO
		return

	# ── Gravity -----------------------------------------
	if not is_on_floor():
		velocity.y -= gravity * delta

	# ── Crouch / Sprint / Walk ------------------------------------
	if Input.is_action_just_pressed("crouch"):
		crouched = !crouched

	# Sprinting always stands back up.
	if crouched and Input.is_action_pressed("sprint"):
		crouched = false

	if crouched:
		speed = CROUCH_SPEED
		head.position.y = lerp(head.position.y, HEAD_HEIGHT + CROUCH_DEPTH, delta * lerp_speed)
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
		head.position.y = lerp(head.position.y, HEAD_HEIGHT, delta * lerp_speed)
	else:
		speed = WALK_SPEED
		head.position.y = lerp(head.position.y, HEAD_HEIGHT, delta * lerp_speed)

	# ── Movement ---------------------------------------------
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * transform.basis *
					 Vector3(input_dir.x, 0, input_dir.y)).normalized()

	_steer(direction, delta)

	# ── Apply physics --------------------------------------
	var was_on_floor := is_on_floor()
	if not was_on_floor:
		_fall_speed = -velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor:
		# Landing dip, deeper the harder the landing.
		_land_offset = -clampf(_fall_speed * 0.025, 0.0, LAND_DIP_MAX)

	# ── Camera feel ------------------------------------------
	# Read AFTER move_and_slide() resolves collisions, not before — otherwise
	# this reflects requested velocity (e.g. holding sprint into a wall) rather
	# than what actually happened, and the FOV ramps up while fully stuck.
	var ground_speed := Vector2(velocity.x, velocity.z).length() * float(is_on_floor())
	var sprinting: bool = speed == SPRINT_SPEED and not crouched
	var sprint_amount := clampf((ground_speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0)
	# Stride and bob size follow the stance, eased so switching doesn't pop.
	_stride = lerpf(_stride, STRIDE_CROUCH if crouched else (STRIDE_SPRINT if sprinting else STRIDE), delta * 6.0)
	_bob_amp = lerpf(_bob_amp, BOB_AMP_CROUCH if crouched else (BOB_AMP_SPRINT if sprinting else BOB_AMP), delta * 6.0)
	_bob_phase += ground_speed * delta / _stride * PI
	# Bob fades in with speed and back out when stopping, so the camera eases to
	# rest rather than freezing mid-step.
	_bob_weight = lerpf(_bob_weight, clampf(ground_speed / WALK_SPEED, 0.0, 1.0), delta * 8.0)
	_breath_t += delta * BREATH_SPEED
	var breath := Vector3(0.0, sin(_breath_t) * BREATH_AMP, 0.0)
	_land_offset = lerpf(_land_offset, 0.0, delta * 9.0)
	_shake_offset = _shake_offset.lerp(Vector2.ZERO, delta * 15.0)
	camera.transform.origin = _headbob(_bob_phase) * _bob_weight + breath * (1.0 - _bob_weight) \
		+ Vector3(_shake_offset.x, _shake_offset.y + _land_offset, 0.0)
	# A slight lean into strafes.
	camera.rotation.z = lerp_angle(camera.rotation.z, -input_dir.x * STRAFE_TILT, delta * 8.0)
	# The footfall nod and sprint lean ride on top of the player's own look
	# pitch (_apply_pitch), never baked into it, so neither drifts the aim.
	var step := pow(absf(sin(_bob_phase)), STEP_SOFTNESS)
	_sprint_lean = lerpf(_sprint_lean, SPRINT_LEAN * sprint_amount, delta * 5.0)
	_nod = -(1.0 - step) * STEP_NOD * _bob_weight - _sprint_lean
	_apply_pitch()
	var step_index := floori(_bob_phase / PI)
	if step_index != _step_index:
		_step_index = step_index
		if ground_speed > 0.5:
			footstep.emit(clampf(ground_speed / SPRINT_SPEED, 0.0, 1.0))

	if not _fov_override:
		# Wider at a sprint, narrower crouched — sneaking should feel close.
		var target_fov := base_fov + SPRINT_FOV_BOOST * sprint_amount - (CROUCH_FOV_DROP if crouched else 0.0)
		camera.fov = lerp(camera.fov, target_fov, delta * 6.0)


## Turns the way the player wants to go into velocity.
func _steer(direction: Vector3, delta: float) -> void:
	if is_on_floor():
		# Lerp instead of a hard set even while grounded — snapping straight to
		# full input-direction speed every tick fights move_and_slide()'s own
		# resolved velocity when sliding along a wall at an angle, oscillating
		# between full speed and the slid speed every frame (visible as the
		# camera/FOV "spazzing" when running into a wall at a glancing angle).
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 15.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 15.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)


func shake(intensity: float) -> void:
	_shake_offset = Vector2(
		randf_range(-intensity, intensity),
		randf_range(-intensity, intensity)
	)


# Quick jolt up then back — used for sudden scares
func spike_fov(target: float, duration_in: float, duration_out: float) -> void:
	_fov_override = true
	var tween := create_tween()
	tween.tween_property(camera, "fov", target, duration_in).set_ease(Tween.EASE_IN)
	tween.tween_property(camera, "fov", base_fov, duration_out).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _fov_override = false)


# One-way expansion — no return, for when the scene is about to change
func warp_fov(target: float, duration: float) -> void:
	_fov_override = true
	var tween := create_tween()
	tween.tween_property(camera, "fov", target, duration).set_ease(Tween.EASE_IN)


# Each step is half a sine cycle: abs(sin) puts a sharp dip where the foot
# lands and a smooth rise between, which reads as footfalls rather than the
# float of a plain sine. The sideways sway takes two steps, shifting weight
# from one foot to the other.
func _headbob(phase: float) -> Vector3:
	var pos = Vector3.ZERO
	# Minus roughly the curve's average, so the eye line stays centred on
	# standing height.
	pos.y = (pow(absf(sin(phase)), STEP_SOFTNESS) - 0.57) * _bob_amp * 2.0
	pos.x = sin(phase) * _bob_amp * 0.7
	return pos
