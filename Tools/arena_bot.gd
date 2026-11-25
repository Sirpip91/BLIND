extends SceneTree
# A simple bot that plays one fight three times and says how it went:
#   godot --headless --fixed-fps 60 --path . -s res://Tools/arena_bot.gd -- <index in encounters>
var s
var p
func _initialize():
	var args = OS.get_cmdline_user_args()
	s = (load("res://Experiments/Arena/arena.tscn") as PackedScene).instantiate()
	root.add_child(s)
	current_scene = s
	create_timer(900.0, true, false, true).timeout.connect(quit)
	for i in 60: await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p = s.player
	var only = int(args[0]) if args.size() > 0 else -1
	var counts := {}
	s.judged.connect(func(a, r):
		var k = ("my " if a == p else "his ") + r
		counts[k] = counts.get(k, 0) + 1)
	for which in s.encounters.size():
		if only >= 0 and which != only: continue
		for round in 3:
			s.start(which)
			counts.clear()
			var most := 0
			var plan := {}
			var hold := 0.0
			var clock := 0.0
			var wait := 0.0
			for tick in 60 * 60:
				await physics_frame
				clock += 1.0 / 60.0
				if s._over or s._standing().is_empty(): break
				if p.global_position.z > 8.0: Input.action_press("up"); p.locked = false
				var going := 0
				var soonest = null
				for foe in s.foes:
					if foe.vitals.dead: continue
					if foe.brain.is_engaged(): going += 1
					if foe.arm.time_to_land() < 1.5 and (soonest == null or foe.arm.time_to_land() < soonest.arm.time_to_land()): soonest = foe
				most = maxi(most, going)
				hold -= 1.0 / 60.0
				wait -= 1.0 / 60.0
				Input.action_release("up")
				var rival = p.rival
				var d = p.global_position.distance_to(rival.global_position)
				if d > 2.3: Input.action_press("up")
				if soonest:
					var key = soonest.arm.strike
					if not plan.has(soonest) or plan[soonest][0] != key or soonest.arm._t < plan[soonest][2]:
						plan[soonest] = [key, randf_range(0.04, 0.16) if randf() < 0.85 else -1.0, 0.0]
					plan[soonest][2] = soonest.arm._t
					if plan[soonest][1] > 0.0 and soonest.arm.time_to_land() <= plan[soonest][1]:
						plan[soonest][1] = -1.0
						p.aim = soonest.arm.strike.comes_from() if not soonest.arm.strike.is_thrust() else Vector2.UP
						if p.arm.phase == 4: p.arm.lower_guard()
						s.swordsman._guard_held = true
						s.swordsman.guard()
						hold = 0.16
				if hold <= 0.0 and s.swordsman._guard_held:
					s.swordsman._guard_held = false
					p.arm.lower_guard()
				if hold <= 0.0 and wait <= 0.0 and d < 2.2 and p.arm.is_open_to_act() and (soonest == null or s.swordsman.has_opening()):
					wait = randf_range(0.3, 0.7)
					p.aim = Vector2(1, 0).rotated(randf() * TAU)
					p.flick = p.aim * 140.0
					p.cursor = Vector2(randf_range(-0.05, 0.05), randf_range(-0.1, 0.25))
					s.swordsman.attack(false)
			var left = s.foes.filter(func(f): return not f.vitals.dead).size()
			print("%s: %s %.0f s  left %d  me %.1f  most at once %d  %s" % [s.encounters[which].label, "lost" if p.vitals.dead else ("won" if left == 0 else "unfinished"), clock, left, p.vitals.health, most, counts])
	quit()
