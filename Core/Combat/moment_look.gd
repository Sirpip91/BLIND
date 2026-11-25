extends Resource

## How one moment of a fight looks and lands.

@export var color := Color.WHITE
## Colour of the hottest part of the sword's glow.
@export var core := Color.WHITE
## Sword glow it sets off: 0 cold, 1 white-hot.
@export_range(0.0, 1.0, 0.01) var heat := 0.0
## Size of the spark burst; 0 for none.
@export_range(0.0, 3.0, 0.05) var burst := 0.0
## Strength of the freeze and zoom; 0 for none.
@export_range(0.0, 1.5, 0.05) var impact := 0.0
## The whole sequence (silhouette, negative, burst lines) rather than a
## short freeze.
@export var heavy := false
@export_range(0.0, 0.2, 0.001) var shake := 0.0
