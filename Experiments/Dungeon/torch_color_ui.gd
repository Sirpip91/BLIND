extends CanvasLayer

## Shows while the mouse is free (Esc), hides again once you click back in.

@export var generator: Node

@onready var panel: Control = $Panel
@onready var hue: HSlider = $Panel/VBox/Hue
@onready var swatch: ColorRect = $Panel/VBox/Swatch

var _saturation := 0.7


func _ready():
	var start: Color = generator.torch_color
	_saturation = start.s
	hue.value = start.h
	swatch.color = start
	hue.value_changed.connect(_on_hue_changed)


func _process(_delta):
	panel.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


func _on_hue_changed(value: float) -> void:
	var color := Color.from_hsv(value, _saturation, 1.0)
	swatch.color = color
	generator.torch_color = color
