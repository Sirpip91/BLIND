extends Resource

## One thing to be learned: what's written over it, what's shown, and who's
## there to learn it on.

const Kind = preload("res://Experiments/Arena/foe/kind.gd")

enum Teaches { CUT, DRAW, GUARD, PARRY, STEP, FLICK, LOCK }

@export var title := ""
@export_multiline var says := ""
@export var teaches := Teaches.CUT
## Frames of it being done, in rows, left to right.
@export var film: Texture2D
@export var across := 6
@export var down := 6
@export var place := Vector3.ZERO
@export var kind: Kind
## Throws slow blows at whoever comes near, to be met.
@export var throws := false
