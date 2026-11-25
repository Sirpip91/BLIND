extends "res://Core/Combat/katana.gd"

## The same katana handled as a brush: it moves and fights exactly as before,
## but swings lay down ink, spend what the blade is carrying, and fling drops.

const Stroke = preload("res://Experiments/InkWash/ink_stroke.gd")

@export var ink: ShaderMaterial
## Tip speeds, in metres a second, where a stroke starts and lifts off.
@export var stroke_from := 4.0
@export var stroke_until := 2.0
## Metres across at its fullest.
@export_range(0.02, 0.4, 0.01) var stroke_width := 0.15
@export var stroke_dry_time := 0.5
## Ink left on the blade at the end of a full swing.
@export_range(0.0, 1.0, 0.05) var spent := 0.15
## Seconds before the ink starts to soak back, and to soak all the way.
@export var soak_delay := 0.2
@export var soak_time := 1.1

## Colours C steps through, for trying them without a fight.
@export var preview_colors: Array[Color] = [Color(0.9, 0.06, 0.05), Color(0.08, 0.3, 0.85), Color(0.1, 0.55, 0.25), Color(0.5, 0.15, 0.75)]

const FULL := 1.3
const STEPS := 8
# Rides over the beat where a cut hands over to its follow-through.
const LIFT_GRACE := 0.04

var _was: Transform3D
var _stroke: MeshInstance3D
var _fill := FULL
var _since_swing := 1.0
var _lifted := 0.0
var _heading := Vector3.ZERO
# Winding up for a cut isn't painting.
var _gathering := false
var _slosh := 0.0
var _slosh_speed := 0.0
var _drops: GPUParticles3D
var _preview := -1


func _ready():
	super()
	_was = transform
	# Glowing embers are white on white here.
	_embers.emitting = false
	_embers.visible = false
	var process := Fx.streak_process(0.2, 1.4, 35.0)
	process.gravity = Vector3(0, -5.0, 0)
	process.inherit_velocity_ratio = 0.25
	process.scale_min = 0.35
	process.color = Color(0.035, 0.035, 0.045)
	_drops = Fx.particles(26, 0.55, process, Fx.chip(0.0035, 0.013), Fx.ink(Color.WHITE))
	_drops.local_coords = false
	_drops.position = BLADE_TIP
	_drops.emitting = false
	add_child(_drops)


func _process(delta):
	super(delta)
	if ink == null:
		return
	# Only colour bleeds in: a white-hot moment is just ink.
	ink.set_shader_parameter("tint", _tint())
	ink.set_shader_parameter("tint_amount", 1.0 if _preview >= 0 else _heat * _heat_color.s)
	ink.set_shader_parameter("sweep", clampf(_charge / execution_charge, 0.0, 1.0) if _charging else 1.0)
	ink.set_shader_parameter("fill", _fill)
	ink.set_shader_parameter("slosh", _slosh)
	# The highlight slides along the blade as it turns to the light.
	ink.set_shader_parameter("glint", 0.45 + 0.9 * global_basis.z.normalized().dot(Vector3(0.4, 0.7, 0.3)))


func _unhandled_key_input(event):
	if event.pressed and not event.echo and event.physical_keycode == KEY_C and visible:
		_preview = -1 if _preview == preview_colors.size() - 1 else _preview + 1


func _tint() -> Color:
	return preview_colors[_preview] if _preview >= 0 else _heat_color


func _blend(t: float, from: Transform3D, to: Transform3D) -> void:
	super(t, from, to)
	_gathering = _slashing and _move >= 0 and to == _moves[_move]["poses"][0]


func _update_trail(delta: float) -> void:
	if delta <= 0.0:
		return
	# In the camera's space, so looking around isn't a swing.
	var moved := transform * BLADE_TIP - _was * BLADE_TIP
	var speed := moved.length() / delta
	var painting := visible and not _gathering and speed > (stroke_until if _stroke else stroke_from)
	# The swing settling back on itself isn't part of the stroke.
	var doubling_back := _stroke != null and moved.dot(_heading) < 0.0
	_lifted = 0.0 if painting else _lifted + delta
	if not doubling_back and (painting or (_stroke and _lifted < LIFT_GRACE and not _gathering)):
		_lay_ink()
		if moved.length() > 0.005:
			_heading = moved
	elif _stroke:
		_stroke.finish()
		_stroke = null
	_drops.emitting = painting and speed > stroke_from

	if speed > stroke_until:
		_since_swing = 0.0
		_fill = maxf(_fill - moved.length() * 0.55, spent)
	else:
		_since_swing += delta
		if _since_swing > soak_delay:
			_fill = minf(_fill + delta / soak_time, FULL)

	# The wet ink lags behind a turn of the wrist, then settles.
	var sideways := moved.dot(transform.basis.x.normalized()) / delta
	_slosh_speed += ((clampf(sideways * 0.06, -0.3, 0.3) - _slosh) * 160.0 - _slosh_speed * 11.0) * minf(delta, 0.03)
	_slosh += _slosh_speed * minf(delta, 0.03)
	_was = transform


func _lay_ink() -> void:
	if _stroke == null:
		_stroke = Stroke.new()
		_stroke.dry_time = stroke_dry_time
		_stroke.width = stroke_width
		_stroke.set_tint(_tint(), _tint().s)
		_world().add_child(_stroke)
	# A cut lasts only a few frames, so the arc between them is filled in.
	var held := (get_parent() as Node3D).global_transform
	var eye: Vector3 = player.camera.global_position
	for i in range(1, STEPS + 1):
		var between := held * _was.interpolate_with(transform, float(i) / STEPS)
		_stroke.add(between * BLADE_TIP, eye)
