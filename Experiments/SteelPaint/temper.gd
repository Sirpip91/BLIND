extends Resource

## How hard an opponent is, laid over its brain.

const Brain = preload("res://Experiments/SteelPaint/brain.gd")

@export var label := ""
@export var attacks := true
## Seconds between attacks.
@export var patience := Vector2(1.2, 3.4)
## Blows it'll throw in a row.
@export var most_blows := 99
## How drawn out its blows are.
@export var slowness := 1.0
@export_range(0.0, 1.0, 0.05) var guard_chance := 0.85
@export_range(0.0, 1.0, 0.05) var parry_chance := 0.15
@export_range(0.0, 1.0, 0.05) var counter_chance := 0.9
@export_range(0.0, 1.0, 0.05) var punish_chance := 0.8
@export_range(0.0, 1.0, 0.05) var think_better := 0.85
@export var wariness_per_cut := 0.2
@export var shell_time := 1.4
## Extra seconds it's open for after a parry.
@export var slow_to_recover := 0.0


func apply(brain: Brain) -> void:
	brain.peaceful = not attacks
	brain.temper = self
	for what in ["patience", "guard_chance", "parry_chance", "counter_chance", "punish_chance", "think_better", "wariness_per_cut", "shell_time"]:
		brain.set(what, get(what))
	brain.calm_patience = patience
