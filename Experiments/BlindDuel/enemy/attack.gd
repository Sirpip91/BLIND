extends Resource

## One attack, as data. An enemy is its model plus a list of these.

@export var title := ""
## Seconds of gathering before the blow: how long the player has to react.
@export_range(0.1, 3.0, 0.01) var windup := 0.7
@export_range(0.03, 0.5, 0.01) var strike := 0.1
@export_range(0.0, 3.0, 0.01) var recover := 0.5
@export var reach := 2.5
## How hard it drives forward as it strikes.
@export var lunge := 0.5
## Off: only a parry stops it.
@export var blockable := true
@export_range(0.0, 1.0, 0.05) var chance_to_chain := 0.35

@export_group("Sword")
# Grip positions and blade directions, facing -Z.
@export var gather_at := Vector3(0.3, 1.5, 0.1)
@export var gather_blade := Vector3(0.2, 1.0, 0.5)
@export var strike_at := Vector3(0.0, 1.1, -0.6)
@export var strike_blade := Vector3(0.0, -0.1, -1.0)
