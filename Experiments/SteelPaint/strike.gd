extends Resource

## One blow. Directions are the way the blade travels across the attacker's
## own view: right is +x, up is +y, and no direction at all is a thrust.

@export var direction := Vector2(-0.7, -0.7)
## Seconds raising the blade, the part a defender reads.
@export var windup := 0.3
## Seconds held at the top before letting go, to catch an early parry.
@export var delay := 0.0
## Seconds through the cut. It lands halfway.
@export var release := 0.2
@export var recover := 0.4
@export var reach := 2.3
## Metres a second stepped into it.
@export var lunge := 2.2
## Gets through a block. A parry or a step still beats it.
@export var heavy := false
## Wound up and never thrown: the next blow of the pattern comes instead.
@export var feint := false

## Thrown into an opening won by parrying or slipping a blow.
var earned := false
## Thrown with nothing left on the blade: it marks, but it can't go through.
var dry := false
## How hard it was swiped, 0 to 1, and so how far it runs.
var power := 0.5
## What it has left to cut with: every limb it goes through takes some.
var force := 1.0
## Where on the view it goes through, in radians from the middle.
var through := Vector2.ZERO
## The line it was drawn along, if it was drawn.
var path := PackedVector2Array()
## What it was drawn on, and where on it, so it stays there however either
## moves.
var pinned_to: Node3D
var pins := PackedVector3Array()


func is_thrust() -> bool:
	return direction.length_squared() < 0.01


## How far off the line it still catches someone: a chop is stepped around,
## a sweep has to be backed out of.
func half_arc() -> float:
	if is_thrust():
		return deg_to_rad(13.0)
	return deg_to_rad(lerpf(17.0, 60.0, absf(direction.normalized().x)))


## The side it comes from in the view of whoever is facing the attacker.
func comes_from() -> Vector2:
	return Vector2(direction.x, -direction.y)


## Where the blade ends up in the holder's own view, let go past its mark.
## A thrust could be turned to either side.
func carries_to() -> Vector2:
	return Vector2([-1.0, 1.0].pick_random(), 0.0) if is_thrust() else direction.normalized()


func aimed(way: Vector2) -> Resource:
	var copy := duplicate()
	copy.direction = way
	return copy
