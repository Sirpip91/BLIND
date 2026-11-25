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
@export var damage := 20.0
## Metres a second stepped into it.
@export var lunge := 2.2
## Gets through a block. A parry or a step still beats it.
@export var heavy := false
## Wound up and never thrown: the next blow of the pattern comes instead.
@export var feint := false

## Thrown into an opening won by parrying or slipping a blow. Only these
## break into what the other fighter is doing.
var earned := false
## Thrown at the side their sword still covers.
var glancing := false
## Where it falls in a run of cuts through one opening: 0 is the first.
var link := 0
var last_link := false
## Thrown on the moment the one before it landed.
var on_beat := false
## Seconds it leaves them reeling.
var reel := 0.36


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
