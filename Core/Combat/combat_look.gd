extends Resource

## Every colour, glow and timing in a fight, in one place. The tuning panel
## builds itself from what's exported here, so a new setting needs one line
## here and wherever it's read.

const Moment = preload("res://Core/Combat/moment_look.gd")

@export_group("Moments")
@export var slash: Moment
@export var flourish: Moment
@export var hit: Moment
@export var kill: Moment
@export var parry: Moment
@export var block: Moment
@export var deflected: Moment
@export var execute: Moment

@export_group("Sword glow")
## Glow left on when the sword is cold.
@export_range(0.0, 1.0, 0.01) var rest_glow := 0.0
## How far the hottest paint turns to the moment's core colour.
@export_range(0.0, 1.0, 0.01) var white_hot := 0.35
## Brightness on the glow map that lights when the sword is barely warm...
@export_range(0.05, 0.9, 0.01) var glow_from_cold := 0.75
## ...and when it's fully hot. Lower lets darker greys join in.
@export_range(0.05, 0.9, 0.01) var glow_from_hot := 0.1
@export_range(0.0, 12.0, 0.1) var pulse_speed := 3.0
@export_range(0.1, 5.0, 0.05) var cool_speed := 1.2
@export_range(0.0, 6.0, 0.05) var blade_light := 1.5

@export_group("Impact frames")
# Times are real seconds.
@export_range(0.0, 0.3, 0.005) var freeze := 0.09
@export_range(0.0, 0.2, 0.005) var silhouette_time := 0.035
@export_range(0.0, 0.2, 0.005) var negative_time := 0.035
## How long time takes to ease back to full speed.
@export_range(0.01, 0.5, 0.01) var thaw := 0.1
@export_range(0.01, 1.0, 0.01) var lines_fade := 0.25
## How hard the view punches in toward the hit.
@export_range(0.0, 0.6, 0.01) var punch := 0.22
## Freeze on an ordinary hit.
@export_range(0.0, 0.2, 0.005) var light_freeze := 0.045
@export var silhouette_shape := Color(0.05, 0.05, 0.06)
@export var silhouette_back := Color(0.95, 0.94, 0.91)
## How far the moment's own colour floods the silhouette background.
@export_range(0.0, 1.0, 0.01) var silhouette_tint := 0.0
## Share of burst lines in the moment's own colour.
@export_range(0.0, 1.0, 0.01) var lines_colored := 0.3
@export var fringe_color := Color(0.85, 0.08, 0.06)
@export_range(0.0, 3.0, 0.05) var fringe := 1.0

## Size of the sparks and ink shards.
@export_range(0.0, 3.0, 0.05) var spark_size := 1.0
## Size of the soft flash on a hit; 0 for none.
@export_range(0.0, 3.0, 0.05) var flash_size := 1.0
## Size of the thin ring that opens on a hit; 0 for none.
@export_range(0.0, 3.0, 0.05) var ring_size := 1.0

@export_group("Enemies")
@export var tell_color := Color.WHITE
@export var red_color := Color(1.0, 0.12, 0.08)

@export_group("World")
@export var orb_color := Color.WHITE
## Lets coloured light tint the black-and-white world.
@export_range(0.0, 1.0, 0.01) var world_color := 0.0
