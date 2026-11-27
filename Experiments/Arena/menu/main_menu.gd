extends CanvasLayer

## The front of the game, and what Esc brings up in the middle of it. Behind
## the first is whoever the arena has standing there, and a camera that won't
## quite keep still.

const Word = preload("res://Experiments/Arena/menu/word.gd")
const Slide = preload("res://Experiments/Arena/menu/slide.gd")
const STROKE = preload("res://Experiments/Arena/menu/stroke.gdshader")
const Blood = preload("res://Experiments/Arena/feel/blood.gd")

const SAVED := "user://settings.cfg"
## Mouse speeds, at either end of the line.
const SPEEDS := Vector2(0.0006, 0.0052)

signal begin(with_lessons: bool)
signal front_wanted
signal gore_changed

## The testing keys, off for anyone just playing.
static var developer := false

@export var player: CharacterBody3D
@export var shot: Camera3D
@export var font: Font
## Nothing's written over it if there's nothing here.
@export var title := ""
@export var ink := Color(0.02, 0.02, 0.025)
@export_group("The shot")
@export var shot_from := Vector3(0.15, 0.62, 1.35)
@export var shot_at := Vector3(-0.35, 1.32, -2.0)
@export var sway := Vector3(0.32, 0.06, 0.2)
@export var sway_time := 17.0

var at_front := false
var paused := false

var _words: Control
var _behind: ColorRect
var _time := 0.0
var _options_from := "front"


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_behind = ColorRect.new()
	var wiped := ShaderMaterial.new()
	wiped.shader = STROKE
	wiped.set_shader_parameter("ink", Color(0.94, 0.93, 0.9, 0.95))
	wiped.set_shader_parameter("dryness", 0.3)
	wiped.set_shader_parameter("seed", 7.0)
	_behind.material = wiped
	_behind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_behind)
	_words = Control.new()
	_words.set_anchors_preset(Control.PRESET_FULL_RECT)
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_words)
	visible = false
	_load()


# ---- the front

func open() -> void:
	at_front = true
	paused = false
	get_tree().paused = false
	visible = true
	shot.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_front()


func close() -> void:
	at_front = false
	paused = false
	visible = false
	get_tree().paused = false
	_clear()


func _front() -> void:
	_lay_out([
		["Start", _ask], ["Options", _options.bind("front")], ["Exit", func(): get_tree().quit()],
	], title, 210)


func _ask() -> void:
	_lay_out([
		["Yes", func(): begin.emit(true)], ["No", func(): begin.emit(false)], ["Back", _front],
	], "Learn the sword first?", 92)


# ---- in the middle of it

func _unhandled_input(event):
	if at_front or not event.is_action_pressed("escape"):
		return
	get_viewport().set_input_as_handled()
	if paused:
		_resume()
	else:
		_pause()


func _pause() -> void:
	paused = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_words()


func _pause_words() -> void:
	_lay_out([
		["Resume", _resume], ["Options", _options.bind("pause")], ["Main menu", func(): front_wanted.emit()],
	], "", 92)


func _resume() -> void:
	close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---- options

func _options(from: String) -> void:
	_options_from = from
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	_lay_out([
		["Full screen: %s" % ("yes" if full else "no"), _toggle_full],
		["Gore: %s" % ("on" if Blood.gore else "off"), _toggle_gore],
		["Developer mode: %s" % ("on" if developer else "off"), _toggle_developer],
		["Back", _front if from == "front" else _pause_words],
	], "Options", 92)
	var rows: Control = _words.get_child(0)
	var says := Word.new("Mouse speed", font, _unit(60), true, 0.1)
	rows.add_child(says)
	rows.move_child(says, 1)
	var slide := Slide.new()
	slide.ink = ink
	slide.value = inverse_lerp(SPEEDS.x, SPEEDS.y, player.mouse_sensitivity)
	slide.moved.connect(func(to):
		player.mouse_sensitivity = lerpf(SPEEDS.x, SPEEDS.y, to)
		_save())
	rows.add_child(slide)
	rows.move_child(slide, 2)


func _toggle_full() -> void:
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_save()
	_options(_options_from)


func _toggle_gore() -> void:
	Blood.gore = not Blood.gore
	_save()
	gore_changed.emit()
	_options(_options_from)


func _toggle_developer() -> void:
	developer = not developer
	_save()
	_options(_options_from)


func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("developer", "on", developer)
	file.set_value("player", "mouse_speed", player.mouse_sensitivity)
	file.set_value("blood", "red", Blood.gore)
	file.set_value("window", "full", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	file.save(SAVED)


func _load() -> void:
	var file := ConfigFile.new()
	if file.load(SAVED) != OK:
		return
	player.mouse_sensitivity = file.get_value("player", "mouse_speed", player.mouse_sensitivity)
	Blood.gore = file.get_value("blood", "red", true)
	developer = file.get_value("developer", "on", false)
	if file.get_value("window", "full", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---- setting the words out

func _unit(of: float) -> int:
	return int(of * get_viewport().get_visible_rect().size.y / 1080.0)


func _clear() -> void:
	for child in _words.get_children():
		child.queue_free()
		_words.remove_child(child)


func _lay_out(choices: Array, heading: String, heading_size: float) -> void:
	_clear()
	var view := get_viewport().get_visible_rect().size
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", _unit(16))
	_words.add_child(rows)
	var after := 0.0
	if heading != "":
		rows.add_child(Word.new(heading, font, _unit(heading_size), true))
		after = 0.15
	for choice: Array in choices:
		var word := Word.new(choice[0], font, _unit(90), false, after)
		word.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		word.pressed.connect(choice[1], CONNECT_DEFERRED)
		rows.add_child(word)
		after += 0.09
	rows.reset_size()
	rows.position = Vector2(view.x * (0.09 if at_front else 0.4), (view.y - rows.get_combined_minimum_size().y) * 0.5)
	_behind.position = Vector2(view.x * (-0.06 if at_front else 0.3), view.y * 0.1)
	_behind.size = Vector2(view.x * (0.5 if at_front else 0.5), view.y * 0.8)
	_behind.material.set_shader_parameter("ink", Color(0.93, 0.92, 0.89, 0.8 if at_front else 0.97))
	_behind.material.set_shader_parameter("size", _behind.size)
	_behind.material.set_shader_parameter("drawn", 1.0)


func _process(delta: float):
	if not at_front:
		return
	_time += delta
	var t := TAU * _time / sway_time
	shot.global_position = shot_from + sway * Vector3(sin(t), sin(t * 0.7 + 1.0), cos(t * 0.6))
	shot.look_at(shot_at + Vector3(sin(t * 0.5) * 0.06, sin(t * 0.9) * 0.02, 0.0))
