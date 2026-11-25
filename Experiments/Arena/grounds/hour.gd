extends Resource

## What the light and the paper are like at one time of day.

@export var label := ""
@export var paper := Color(0.93, 0.92, 0.89)
@export var ink := Color(0.035, 0.035, 0.045)
## How bright the sky is, before it's painted.
@export_range(0.0, 1.0, 0.01) var sky := 1.0
@export var sun_energy := 1.1
@export var ambient := 0.45
@export_range(0.0, 1.0, 0.01) var mist_limit := 0.93
@export var moon := false
## What's written over it.
@export var writing := Color(0.05, 0.05, 0.06)
