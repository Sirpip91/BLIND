extends RefCounted

## Everything on one side of a drawn line: one plane for each straight of it,
## joined the way its corners turn. Bent lines bite corners out of things.

## Straights a line is brought down to, at most.
const MOST := 6

var planes: Array[Plane] = []
## How each plane after the first is joined on: both sides, or either.
var both: Array[bool] = []


## From a line on the view, as rays out of an eye. A straight that turns left
## opens its right-hand side out; one that turns right closes it in.
static func from_line(line: PackedVector2Array, eye: Transform3D, ray: Callable) -> RefCounted:
	var region = new()
	var plain := simplified(line, 0.02)
	var last := Vector2.ZERO
	for i in plain.size() - 1:
		var way := plain[i + 1] - plain[i]
		var normal: Vector3 = (eye.basis * ray.call(plain[i])).cross(eye.basis * ray.call(plain[i + 1]))
		if normal.length() < 0.0005:
			continue
		if not region.planes.is_empty():
			region.both.append(last.cross(way) < 0.0)
		region.planes.append(Plane(normal.normalized(), eye.origin))
		last = way
	return region


func contains(point: Vector3) -> bool:
	var inside := planes[0].is_point_over(point)
	for i in range(1, planes.size()):
		var here := planes[i].is_point_over(point)
		inside = (inside and here) if both[i - 1] else (inside or here)
	return inside


func distance_to(point: Vector3) -> float:
	var nearest := 1000.0
	for plane in planes:
		nearest = minf(nearest, absf(plane.distance_to(point)))
	return nearest


## The corners that matter.
static func simplified(line: PackedVector2Array, slack: float) -> PackedVector2Array:
	var plain := _corners(line, slack)
	while plain.size() > MOST + 1:
		slack *= 1.5
		plain = _corners(line, slack)
	return plain


static func _corners(line: PackedVector2Array, slack: float) -> PackedVector2Array:
	if line.size() < 3:
		return line
	var worst := 0.0
	var at := 0
	for i in range(1, line.size() - 1):
		var off := line[i].distance_to(Geometry2D.get_closest_point_to_segment(line[i], line[0], line[-1]))
		if off > worst:
			worst = off
			at = i
	if worst <= slack:
		return PackedVector2Array([line[0], line[-1]])
	var front := _corners(line.slice(0, at + 1), slack)
	front.append_array(_corners(line.slice(at), slack).slice(1))
	return front
