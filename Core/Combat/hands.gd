extends Node3D

## The player's held tools, riding on the camera. Number keys pick one
## (1 = first child, 2 = second, ...). The left mouse button goes to
## whichever is out as trigger(pressed), the right as alt_trigger(pressed),
## and the wheel as flourish(+1 or -1).

@export var player: Node

var _tools: Array[Node3D] = []
var _current := 0
var _switching: Tween


func _ready():
	for child in get_children():
		if child is Node3D:
			_tools.append(child)
	for i in _tools.size():
		_tools[i].visible = i == _current
	# Deferred: the player's camera isn't ready to take children mid-setup.
	_attach.call_deferred()


func _attach() -> void:
	reparent(player.camera, false)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var index: int = event.physical_keycode - KEY_1
		if index >= 0 and index < _tools.size() and index != _current:
			_switch(index)
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _switching:
		var tool := _tools[_current]
		var method := ""
		if event.button_index == MOUSE_BUTTON_LEFT:
			method = "trigger"
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			method = "alt_trigger"
		elif event.pressed and tool.has_method("flourish") and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			tool.flourish(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		if method and tool.has_method(method):
			tool.call(method, event.pressed)


func _switch(index: int) -> void:
	var outgoing := _tools[_current]
	if outgoing.has_method("holster"):
		outgoing.holster()
	_switching = create_tween()
	_switching.tween_property(self, "position:y", -0.4, 0.1).set_ease(Tween.EASE_IN)
	_switching.tween_callback(func():
		outgoing.visible = false
		_current = index
		_tools[index].visible = true)
	_switching.tween_property(self, "position:y", 0.0, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_switching.tween_callback(func(): _switching = null)
