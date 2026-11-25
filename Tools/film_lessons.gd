extends SceneTree
# Plays each tutorial lesson and films it into Experiments/Arena/lessons/*.png:
#   godot --path . --fixed-fps 60 --resolution 1280x720 -s res://Tools/film_lessons.gd -- cut draw guard parry step flick lock
# Run an --import afterwards.
class Glyph extends Control:
	var left := false
	var right := false
	var wheel := 0.0
	var key := ""
	var key_down := false
	var arrow := Vector2.ZERO
	var off := Vector2.ZERO
	var font: Font
	var mouse := true
	func _draw():
		var u := size.y / 180.0
		var ink := Color(0.02, 0.02, 0.025)
		var paper := Color(0.95, 0.94, 0.91)
		var at := Vector2(34, 138) * u + off * 11.0 * u
		if key != "":
			var kw := (14.0 + key.length() * 10.0) * u
			var kb := Rect2(Vector2(size.x - kw - 14.0 * u, 138.0 * u), Vector2(kw, 28.0 * u))
			draw_rect(kb, ink if key_down else paper)
			draw_rect(kb, ink, false, 2.4 * u)
			draw_string(font, kb.position + Vector2(8, 20) * u, key, HORIZONTAL_ALIGNMENT_LEFT, -1, int(21 * u), paper if key_down else ink)
		if not mouse: return
		var body := PackedVector2Array()
		for i in 48:
			var w := Vector2.from_angle(TAU * i / 48.0)
			body.append(at + Vector2(signf(w.x) * pow(absf(w.x), 0.7) * 17.0, signf(w.y) * pow(absf(w.y), 0.75) * 25.0) * u)
		draw_colored_polygon(body, paper)
		for side in [-1.0, 1.0]:
			if (side < 0 and left) or (side > 0 and right):
				var half := PackedVector2Array()
				for p in body:
					var q := p - at
					if q.x * side > 1.0 * u and q.y < -3.0 * u: half.append(p)
				half.append(at + Vector2(side * 2.0, -3.0) * u)
				half.append(at + Vector2(side * 2.0, -23.0) * u)
				var sorted := Array(half)
				var mid := Vector2.ZERO
				for p in sorted: mid += p
				mid /= sorted.size()
				sorted.sort_custom(func(a, b): return (a - mid).angle() < (b - mid).angle())
				draw_colored_polygon(PackedVector2Array(sorted), Color(0.72, 0.02, 0.03))
		body.append(body[0])
		draw_polyline(body, ink, 2.6 * u, true)
		draw_line(at + Vector2(0, -25) * u, at + Vector2(0, -3) * u, ink, 1.8 * u, true)
		draw_line(at + Vector2(-16, -3) * u, at + Vector2(16, -3) * u, ink, 1.8 * u, true)
		draw_rect(Rect2(at + Vector2(-3, -19) * u, Vector2(6, 12) * u), Color(0.72, 0.02, 0.03) if wheel != 0.0 else paper)
		draw_rect(Rect2(at + Vector2(-3, -19) * u, Vector2(6, 12) * u), ink, false, 1.8 * u)
		if wheel != 0.0:
			_arrow(at + Vector2(0, -13) * u + Vector2(0, 14.0 * wheel) * u, Vector2(0, wheel), 24.0 * u, u)
		if arrow != Vector2.ZERO:
			_arrow(at + Vector2(52, 0) * u - off * 11.0 * u, arrow, 30.0 * u, u)
	func _arrow(from: Vector2, way: Vector2, long: float, u: float):
		way = way.normalized()
		var to := from + way * long
		var side := way.orthogonal()
		for layer in [[Color(0.95, 0.94, 0.91), 8.0], [Color(0.72, 0.02, 0.03), 4.2]]:
			draw_line(from, to, layer[0], layer[1] * u, true)
			draw_colored_polygon(PackedVector2Array([to + way * (9.0 + layer[1]) * u, to + side * (5.0 + layer[1]) * u, to - side * (5.0 + layer[1]) * u]), layer[0])

const W := 320
const H := 180
var s
var p
var g
var sheet: Image
var frame := 0
var ticks := 0
var rolling := false

func _initialize():
	s = (load("res://Experiments/Arena/arena.tscn") as PackedScene).instantiate()
	root.add_child(s)
	current_scene = s
	create_timer(200.0, true, false, true).timeout.connect(quit)
	for i in 30: await process_frame
	p = s.player
	var layer := CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	g = Glyph.new()
	g.font = load("res://Assets/Fonts/EastSeaDokdo-Regular.ttf")
	g.set_anchors_preset(Control.PRESET_FULL_RECT)

	layer.add_child(g)
	await process_frame
	g.size = root.get_visible_rect().size
	print("glyph ", g.size, " ", g.is_visible_in_tree())
	for which in (OS.get_cmdline_user_args() if OS.get_cmdline_user_args().size() > 0 else ["cut", "draw", "guard", "parry", "step", "flick"]):
		await call("_" + which)
		sheet.save_png("res://Experiments/Arena/lessons/%s.png" % which)
		print(which, " ", frame)
	quit()

func _scene(fight: int, z: float):
	s.encounters[0].foes[0] = load("res://Experiments/Arena/data/dummy.tres")
	s.encounters[2].foes[0] = load("res://Experiments/Arena/data/spar.tres")
	s.start(fight)
	s.feel.spill(true)
	s.hint.visible = false
	s.get_node("SwordPicker").kept_away = true
	for i in 20: await _tick()
	s.passage._state = 4
	s.feel.blood.on_blade = 0.0
	p.cursor = Vector2.ZERO
	p.global_position = Vector3(0, p.global_position.y, 2.0)
	var foe = s.foes[0]
	foe.reset_at(Vector3(0, 0, z))
	foe.brain.wait(false)
	foe.arm.reset()
	for i in 45: await _tick()
	g.mouse = true
	g.left = false
	g.right = false
	g.wheel = 0.0
	g.key = ""
	g.key_down = false
	g.arrow = Vector2.ZERO
	g.off = Vector2.ZERO
	sheet = Image.create(W * 6, H * 6, false, Image.FORMAT_RGB8)
	frame = 0
	ticks = 0
	rolling = true
	return foe

# One sixtieth.
func _tick():
	await process_frame
	if not rolling: return
	g.queue_redraw()
	ticks += 1
	if ticks * 18 / 60 > frame and frame < 36:
		await RenderingServer.frame_post_draw
		var im = root.get_viewport().get_texture().get_image()
		var w = im.get_width()
		var h = im.get_height()
		var tall = mini(h, int(w * 9.0 / 16.0))
		var wide = int(tall * 16.0 / 9.0)
		im = im.get_region(Rect2i((w - wide) / 2, (h - tall) / 2, wide, tall))
		# The middle of it, where it happens, with the mouse laid over.
		im.resize(W, H, Image.INTERPOLATE_LANCZOS)
		im.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(im, Rect2i(0, 0, W, H), Vector2i((frame % 6) * W, (frame / 6) * H))
		frame += 1

func _go(n): for i in n: await _tick()

func _finish():
	while frame < 36: await _tick()
	rolling = false

func _swipe(way: Vector2, n: int):
	g.arrow = Vector2(way.x, -way.y)
	for i in n:
		g.off = Vector2(way.x, -way.y) * sin(PI * 0.5 * (i + 1) / n)
		await _tick()

func _aim(way):
	p.aim = way.normalized()
	p.flick = p.aim * 150.0

func _cut():
	await _scene(0, 0.35)
	for way in [Vector2(1, -0.35), Vector2(-0.9, -0.5)]:
		s.foes[0].reset_at(Vector3(0, 0, 0.35))
		s.foes[0].brain.wait(false)
		s.foes[0].arm.reset()
		_aim(way)
		await _swipe(way.normalized(), 14)
		g.left = true
		p.cursor = Vector2(0, -0.12)
		_aim(way)
		s.swordsman.attack(false)
		await _go(8)
		g.left = false
		await _go(26)
		g.arrow = Vector2.ZERO
		g.off = Vector2.ZERO
		await _go(10)
	await _finish()

func _draw():
	await _scene(0, 0.35)
	await _go(8)
	p.cursor = Vector2(-0.26, 0.06)
	g.left = true
	s.swordsman.start_drawing()
	var pts := [Vector2(-0.26, 0.06), Vector2(-0.05, -0.14), Vector2(0.1, 0.02), Vector2(0.28, -0.12)]
	for k in 3:
		for i in 11:
			var t = (i + 1) / 11.0
			p.cursor = pts[k].lerp(pts[k + 1], t)
			g.off = Vector2(p.cursor.x, -p.cursor.y) * 5.0
			await _tick()
	await _go(4)
	g.left = false
	s.swordsman.finish_drawing()
	await _finish()

func _blow(foe, d):
	var st = load("res://Experiments/Arena/fighter/strike.gd").new()
	st.direction = d
	st.windup = 0.7
	st.release = 0.24
	foe.arm.begin(st)
	return st

func _guard():
	var foe = await _scene(2, 0.2)
	for d in [Vector2(-0.75, -0.66), Vector2(0.75, -0.66)]:
		var st = _blow(foe, d)
		await _go(14)
		var side: Vector2 = st.comes_from()
		g.right = true
		p.aim = side.normalized()
		s.swordsman._guard_held = true
		s.swordsman.guard()
		await _swipe(side.normalized(), 10)
		while foe.arm.phase in [1, 2]:
			p.aim = side.normalized()
			await _tick()
		await _go(6)
		g.right = false
		g.arrow = Vector2.ZERO
		g.off = Vector2.ZERO
		s.swordsman._guard_held = false
		p.arm.lower_guard()
		foe.reset_at(Vector3(0, 0, 0.2))
		foe.brain.wait(false)
		foe.arm.reset()
		await _go(4)
	await _finish()

func _parry():
	var foe = await _scene(2, 0.2)
	var st = _blow(foe, Vector2(-0.75, -0.66))
	p.aim = st.comes_from()
	g.arrow = Vector2(st.comes_from().x, -st.comes_from().y)
	while foe.arm.time_to_land() > 0.07: await _tick()
	g.right = true
	p.aim = st.comes_from()
	s.swordsman._guard_held = true
	s.swordsman.guard()
	await _go(12)
	g.right = false
	g.arrow = Vector2.ZERO
	s.swordsman._guard_held = false
	p.arm.lower_guard()
	await _go(14)
	_aim(Vector2(1, -0.1))
	await _swipe(Vector2(1, -0.1), 8)
	g.left = true
	p.cursor = Vector2(0, -0.02)
	_aim(Vector2(1, -0.1))
	s.swordsman.attack(false)
	await _go(8)
	g.left = false
	await _finish()

func _step():
	var foe = await _scene(2, 0.2)
	g.mouse = false
	for side in ["right", "left"]:
		_blow(foe, Vector2(0, -1))
		g.key = "Space + " + ("D" if side == "right" else "A")
		while foe.arm.time_to_land() > 0.13: await _tick()
		g.key_down = true
		Input.action_press(side)
		p.dodge()
		await _go(10)
		Input.action_release(side)
		g.key_down = false
		await _go(18)
		foe.reset_at(p.global_position + (foe.global_position - p.global_position).normalized() * 1.8)
		foe.brain.wait(false)
		foe.arm.reset()
	await _finish()

func _flick():
	await _scene(0, -3.0)
	s.feel.blood.stain_blade(true)
	s.feel.blood.on_blade = 0.75
	s.feel.blood._clean = 0.0
	await _go(26)
	g.wheel = 1.0
	s.sword.flick_clean()
	await _go(16)
	g.wheel = 0.0
	await _finish()

func _lock():
	await _scene(0, -0.2)
	p.locked = false
	g.mouse = false
	g.key = "Q"
	p.head.rotation.y = 0.0
	p._pitch = 0.0
	for i in 24:
		p.head.rotation.y = lerpf(0.0, 0.5, smoothstep(0.0, 1.0, i / 23.0))
		p._look_pitch(0.004)
		await _tick()
	g.key_down = true
	p.locked = true
	await _go(10)
	g.key_down = false
	await _go(14)
	g.key = "Q   A"
	Input.action_press("left")
	await _go(34)
	Input.action_release("left")
	g.key = "Q   D"
	Input.action_press("right")
	await _go(30)
	Input.action_release("right")
	await _finish()
