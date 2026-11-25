extends Resource

## The colour in the player's sword.

@export var color := Color(0.9, 0.06, 0.05)
## How far it's bled into the blade, and into the strokes it lays.
@export_range(0.0, 1.0, 0.01) var blade := 0.0
@export_range(0.0, 1.0, 0.01) var strokes := 0.0
