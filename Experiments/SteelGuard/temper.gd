extends Resource

## How hard an opponent is, laid over its brain.

const Brain = preload("res://Experiments/SteelGuard/brain.gd")

@export var label := ""
@export var attacks := true
## Seconds between attacks.
@export var patience := Vector2(1.2, 3.4)
## Blows it'll throw in a row.
@export var most_blows := 99
## How drawn out its blows are.
@export var slowness := 1.0
## Seconds late it sees a line being drawn.
@export var read_delay := 0.16
## How fast it can bring its sword across, in metres and in radians a second.
## Nothing at all and it doesn't try.
@export var ward_speed := 1.5
@export var ward_turn := 5.0
## Seconds it keeps its guard up for, and lets it down for, while nothing's
## coming.
@export var watch := Vector2(2.0, 4.0)
@export var lapse := Vector2(0.4, 0.9)
## Whether it'll let its guard down within reach of a sword.
@export var careless := false
## Chance it goes for someone who's started drawing.
@export_range(0.0, 1.0, 0.05) var rush_chance := 0.6
@export_range(0.0, 1.0, 0.05) var counter_chance := 0.9
@export_range(0.0, 1.0, 0.05) var punish_chance := 0.8
@export_range(0.0, 1.0, 0.05) var think_better := 0.85
@export var wariness_per_cut := 0.2
## Extra seconds it's open for after a parry.
@export var slow_to_recover := 0.0


func apply(brain: Brain) -> void:
	brain.peaceful = not attacks
	brain.temper = self
	for what in ["patience", "counter_chance", "punish_chance", "think_better", "wariness_per_cut"]:
		brain.set(what, get(what))
	brain.calm_patience = patience
