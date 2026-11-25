extends Camera3D

## Orbits the origin, framed for a subject of 1 m radius. Holds no state of
## its own: everything comes in through frame(), so a recording can replay it.


## Angles in degrees. `zoom` of 1 just fits the subject; `pan` slides it
## around in frame, in metres.
func frame(yaw: float, pitch: float, zoom: float, pan: Vector2, lens: float, aspect: float) -> void:
	fov = lens
	# fov is the vertical angle, so a tall frame is limited by its width.
	var half := deg_to_rad(lens) * 0.5
	if aspect < 1.0:
		half = atan(tan(half) * aspect)
	var distance := 1.1 / sin(half) / maxf(zoom, 0.05)
	var turned := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0.0))
	transform = Transform3D(turned, turned * Vector3(-pan.x, -pan.y, distance))
	near = maxf(distance * 0.02, 0.01)
	far = distance + 20.0
