extends Node

## Whose turn it is to cut. Neither fighter waits for one: it's won by turning
## the other's blade, and lost by having your own turned, and each exchange
## comes a little quicker than the last until somebody is too late.

signal lapsed

enum { NOBODY, MINE, THEIRS }

## Seconds to answer in, at the start of a rally and at its quickest.
@export var beat := Vector2(0.95, 0.6)
## Exchanges it takes to get there.
@export var quickest := 7

var whose := NOBODY
## Exchanges so far.
var count := 0

var _left := 0.0


## 0 to 1, as it speeds up.
func heat() -> float:
	return clampf(count / float(quickest), 0.0, 1.0)


func is_mine() -> bool:
	return whose == MINE


func win() -> void:
	count += 1
	whose = MINE
	_left = lerpf(beat.x, beat.y, heat())


func lose() -> void:
	count += 1
	whose = THEIRS


func end() -> void:
	whose = NOBODY
	count = 0


func _physics_process(delta: float):
	if whose != MINE:
		return
	_left -= delta
	if _left <= 0.0:
		whose = NOBODY
		lapsed.emit()
