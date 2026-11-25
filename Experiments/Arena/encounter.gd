extends Resource

## One fight: who's in it, and how many of them come at once.

const Kind = preload("res://Experiments/Arena/foe/kind.gd")

@export var label := ""
@export var foes: Array[Kind] = []
## The rest circle and wait.
@export var at_once := 1
## Seconds between one starting and the next.
@export var spacing := 0.9
## Whether it starts with eyes on one of them.
@export var locked := true
## Full hits the player can take.
@export var player_health := 2.0
## After dark, and everything that comes with that.
@export var night := false
## Nobody to fight: a mask to be taken.
@export var shrine := false
## Somewhere to learn, with nobody to beat.
@export var tutorial := false
## How far round from where the player's looking they'll strike from.
@export_range(40.0, 180.0, 1.0, "radians_as_degrees") var in_view := deg_to_rad(82.0)
