extends Resource

## A run of blows the enemy throws together, to be learned as one thing.

const Strike = preload("res://Experiments/SteelGuard/strike.gd")

@export var strikes: Array[Strike] = []
## How often it's picked against the others.
@export var weight := 1.0
## Kept back until the enemy is furious.
@export var desperate_only := false
