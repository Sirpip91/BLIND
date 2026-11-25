extends RefCounted

## Where the sword is held for any direction, so both fighters move alike and
## either can be read off the other. Positions are from the holder's eyes:
## +x right, +y up, -z toward whoever they face.


## `droop` is a tired one, the point let down.
static func ready(aim: Vector2, shown := false, droop := 0.0) -> Transform3D:
	if shown:
		return pose(Vector3(0.2 - aim.x * 0.04, -0.46 - droop * 0.1, -0.32),
				Vector3(0.12 - aim.x * 0.08 + droop * 0.35, 0.95 - droop * 0.6, -0.32), Vector3(-0.3, 0.0, 1.0))
	# Leans toward the side the next cut would start from.
	return pose(Vector3(0.13 - aim.x * 0.08, -0.27 - aim.y * 0.035, -0.5),
			Vector3(-0.08 - aim.x * 0.34, 0.72 - aim.y * 0.18, -0.62), Vector3(-0.75, 0.0, 0.65))


## `shown` is for a fighter seen from the front: the sword is carried clear of
## the body with its flat turned out, so the blade can be read at a glance.
static func gather(d: Vector2, shown := false) -> Transform3D:
	if d == Vector2.ZERO:
		if shown:
			return pose(Vector3(0.36, -0.2, 0.0), Vector3(0.25, 0.18, -0.8), Vector3.UP)
		return pose(Vector3(0.23, -0.17, -0.2), Vector3(-0.1, 0.1, -1.0), Vector3.UP)
	if shown:
		return pose(Vector3(-d.x * 0.5 + 0.02, -d.y * 0.36 - 0.08, -0.2),
				Vector3(-d.x * 0.9, -d.y * 0.95 + 0.14, 0.08), Vector3.BACK)
	return pose(Vector3(-d.x * 0.42 + 0.04, -d.y * 0.2 - 0.1, -0.36),
			Vector3(-d.x * 0.9, -d.y * 0.95 + 0.12, 0.22 - d.y * 0.32), _flat(d))


## The moment it lands. Seen from behind the hands, the grip leads and the
## blade is drawn after it, so it lies across the view instead of end on.
static func cut(d: Vector2, shown := false) -> Transform3D:
	if d == Vector2.ZERO:
		return pose(Vector3(0.05, -0.14, -0.98), Vector3(-0.04, 0.05, -1.0), Vector3.UP)
	if not shown:
		var at := Vector3(0.04 + d.x * 0.2, -0.2 + d.y * 0.1, -0.62)
		var to := Vector3(-d.x * 0.22, 0.06 - d.y * 0.16, -1.18)
		# Rolled a little, or it's a line seen edge on.
		return pose(at, to - at, (_flat(d) + Vector3.BACK * (0.7 + 1.1 * maxf(d.x, 0.0))).normalized())
	return pose(Vector3(0.02, -0.15, -0.78), Vector3(d.x * 0.08, 0.2 + d.y * 0.1, -1.0), _flat(d))


static func finish(d: Vector2) -> Transform3D:
	if d == Vector2.ZERO:
		return pose(Vector3(0.08, -0.16, -0.8), Vector3(-0.06, 0.02, -1.0), Vector3.UP)
	return pose(Vector3(d.x * 0.4, d.y * 0.27 - 0.17, -0.48),
			Vector3(d.x * 0.92, d.y * 0.8, -0.42), _flat(d))


## The blade set across the side a blow comes from.
static func guard(from: Vector2) -> Transform3D:
	var c := from.normalized() if from.length_squared() > 0.01 else Vector2.RIGHT
	var along := Vector2(-c.y, c.x)
	if along.y < -0.05:
		along = -along
	var grip := c * 0.2 - along * 0.34
	return pose(Vector3(grip.x, grip.y - 0.03, -0.5), Vector3(along.x, along.y, -0.12), Vector3.BACK)


## The blade lying `across` something, its middle `at` it.
static func ward(at: Vector2, across: Vector2) -> Transform3D:
	return pose(Vector3(at.x - across.x * 0.55, at.y - across.y * 0.55, -0.48), Vector3(across.x, across.y, -0.1), Vector3.BACK)


## Knocked away, along `push` as the holder sees it.
static func thrown(push: Vector2, shown := false) -> Transform3D:
	if shown:
		return pose(Vector3(push.x * 0.5 + 0.02, push.y * 0.34 - 0.08, -0.16),
				Vector3(push.x, push.y * 0.9 + 0.12, 0.02), Vector3.BACK)
	return pose(Vector3(0.2 + push.x * 0.24, -0.12 + push.y * 0.2, -0.25),
			Vector3(push.x * 0.9 + 0.2, push.y * 0.8 + 0.25, 0.35), Vector3.BACK)


static func droop() -> Transform3D:
	return pose(Vector3(0.3, -0.5, -0.32), Vector3(0.1, -1.0, -0.3), Vector3.LEFT)


## Grip at `at`, blade along `blade`, its flat facing `flat`. The sharp edge is
## on -X, which points along flat cross blade.
static func pose(at: Vector3, blade: Vector3, flat: Vector3) -> Transform3D:
	var y := blade.normalized()
	var x := y.cross(flat).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), at)


# The flat faces across the swing, so it cuts edge first.
static func _flat(d: Vector2) -> Vector3:
	var way := d.normalized()
	return Vector3(way.y, -way.x, 0.0).normalized()
