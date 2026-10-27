extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	var straight: Array[float] = []
	for i in 100:
		straight.append(0.0)
	var plain := _cues(_heading_course(straight, 2.0))
	_check("straight headings produce no corner", plain.corners.is_empty())
	for i in straight.size():
		straight[i] = 3.0 if i % 2 == 0 else -3.0
	_check("short alternating heading noise produces no corner", _cues(_heading_course(straight, 2.0)).corners.is_empty())
	var right := _cues(_stadium(60.0, 3.5, 1.0))
	var left := _cues(_stadium(60.0, 3.5, -1.0))
	_check("right semicircles are right hairpins", right.corners.size() == 2
		and right.corners[0]["label"] == "HAIRPIN RIGHT" and right.corners[1]["label"] == "HAIRPIN RIGHT")
	_check("mirrored semicircles are left hairpins", left.corners.size() == 2 and left.corners[0]["label"] == "HAIRPIN LEFT")
	var fine := _cues(_stadium(60.0, 1.0, 1.0))
	var coarse := _cues(_stadium(60.0, 5.0, 1.0))
	_check("arc sampling density preserves labels and curvature", fine.corners[0]["label"] == coarse.corners[0]["label"]
		and absf(float(fine.corners[0]["curvature"]) / float(coarse.corners[0]["curvature"]) - 1.0) < 0.1)
	var pivot := (int(right.corners[0]["index"]) + 15) % right.course.points.size()
	var rotated := CourseDefinition.new().configure("seam", "seam", "test", 3,
		right.course.points.slice(pivot) + right.course.points.slice(0, pivot))
	var seam := _cues(rotated)
	_check("hairpin through finish remains a single run", seam.corners.size() == right.corners.size())
	var s_bend: Array[float] = [0, 0, 0, 15, 30, 45, 60, 75, 90, 90, 75, 60, 45, 30, 15, 0, 0, 0]
	var s_cues := _cues(_heading_course(s_bend, 10.0))
	var directions := PackedStringArray()
	for corner: Dictionary in s_cues.corners:
		directions.append("RIGHT" if "RIGHT" in corner["label"] else "LEFT")
	_check("S bend splits opposite turn directions", directions.has("RIGHT") and directions.has("LEFT"))
	var car := Vehicle.new()
	car.tuning = TuningProfile.new()
	car.freeze = true
	add_child(car)
	car.speed = 35.0
	var approach := float(right.corners[0]["distance"]) - 40.0
	var advice := right.corner_advice(approach, car)
	_check("overspeed approach asks for early braking", advice["slow"] and not advice["inside"])
	_check("advisory is a finite positive speed", is_finite(float(advice["speed"])) and float(advice["speed"]) > 0.0)
	car.grip_multiplier = 0.5
	var low := right.corner_advice(approach, car)
	_check("lower grip lowers advisory speed", float(low["speed"]) < float(advice["speed"]))
	car.grip_multiplier = 1.0
	car.brake_multiplier = 0.1
	var weak := right.corner_advice(approach, car)
	_check("weaker brakes increase required approach lead", float(weak["braking_lead"]) > float(advice["braking_lead"]))
	car.brake_multiplier = 1.0
	car.mass *= 2.0
	_check("heavier vehicle increases braking lead", float(right.corner_advice(approach, car)["braking_lead"]) > float(advice["braking_lead"]))
	car.mass *= 0.5
	car.active_end = "B"
	var b_advice := right.corner_advice(approach, car)
	_check("swap changes speed advice without changing turn label", b_advice["label"] == advice["label"] and b_advice["speed"] != advice["speed"])
	_check("advisory does not exceed end-specific top speed", float(b_advice["speed"]) <= car.tuning.top_speed("B") * Surfaces.mod_top("B", Surfaces.Id.TARMAC))
	car.speed = 2.0
	_check("slow approach does not request braking", not right.corner_advice(approach, car)["slow"])
	var middle := float(right.corners[0]["distance"]) + float(right.corners[0]["length"]) * 0.5
	_check("corner label remains active through bend", right.corner_advice(middle, car)["inside"])
	var after := float(right.corners[0]["distance"]) + float(right.corners[0]["length"]) + 5.0
	var exited := right.corner_advice(after, car)
	_check("corner releases after its exit", exited.is_empty() or not exited["inside"])
	var snapshot := [car.active_end, car.mass, car.linear_velocity, car.angular_velocity,
		car.throttle, car.brake, car.steer, car.handbrake, car.tuning.a_tire_grip, car.tuning.a_brake]
	right.corner_advice(approach, car)
	_check("advice leaves controls physics and tuning unchanged", snapshot == [car.active_end, car.mass, car.linear_velocity, car.angular_velocity,
		car.throttle, car.brake, car.steer, car.handbrake, car.tuning.a_tire_grip, car.tuning.a_brake])
	var icy := _cues(_stadium(60.0, 3.5, 1.0, Surfaces.Id.ICE))
	_check("icy turn is explicitly marked low grip", icy.corner_advice(float(icy.corners[0]["distance"]) - 30.0, car)["low_grip"])
	car.queue_free()
	await _test_hud()
	print("CORNERS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_hud() -> void:
	GameSession.configure("CORNER TEST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
		driver.target.freeze = true
	scene.car.freeze = true
	_check("real course has its right-hand hairpin", scene.course_cues.corners.any(func(c: Dictionary) -> bool: return c["label"] == "HAIRPIN RIGHT"))
	var corner: Dictionary = scene.course_cues.corners[0]
	var sample: Dictionary = scene.course_cues.sample_at(float(corner["distance"]) - 50.0)
	scene.player_progress.reset(int(sample["index"]))
	scene.player_progress.update(sample["position"])
	scene.race.state = RaceDirector.State.RACING
	scene.car.speed = 50.0
	scene.hud._process(0.0)
	_check("real HUD shows turn and advisory braking", "ADVISORY" in scene.hud._upcoming.text and "BRAKE BEFORE TURN" in scene.hud._upcoming.text)
	_check("corner advice carries no terrain prediction", not ("PREPARE END" in scene.hud._upcoming.text) and not ("HOLD END" in scene.hud._upcoming.text)
		and not (" READY" in scene.hud._upcoming.text))
	await get_tree().process_frame
	_check("expanded cue fits above controls and inside viewport", get_viewport().get_visible_rect().encloses(scene.hud._upcoming.get_global_rect())
		and not scene.hud._upcoming.get_global_rect().intersects(scene.hud._hint.get_global_rect()))
	scene.player_progress.wrong_way = true
	scene.hud._process(0.0)
	_check("wrong-way hides corner and terrain advice", scene.hud._upcoming.text.is_empty())
	scene.player_progress.wrong_way = false
	scene.race.state = RaceDirector.State.RESULTS
	scene.hud._process(0.0)
	_check("results hide corner advice", scene.hud._upcoming.text.is_empty())
	scene.queue_free()
	await get_tree().process_frame


func _cues(course: CourseDefinition) -> CourseCues:
	var cues := CourseCues.new()
	cues.setup(course)
	return cues


func _heading_course(headings: Array[float], step: float, sid: int = Surfaces.Id.TARMAC) -> CourseDefinition:
	var points: Array = []
	var position := Vector3.ZERO
	for degrees: float in headings:
		var direction := Vector3(sin(deg_to_rad(degrees)), 0.0, -cos(deg_to_rad(degrees)))
		points.append({"pos": position, "dir": direction, "dist": step, "w": 26.0, "s": sid})
		position += direction * step
	return CourseDefinition.new().configure("test", "test", "test", 3, points)


func _stadium(radius: float, step: float, side: float, sid: int = Surfaces.Id.TARMAC) -> CourseDefinition:
	var points: Array = []
	var position := Vector3.ZERO
	var count := ceili(PI * radius / step)
	for half in 2:
		for i in ceili(120.0 / step):
			var direction := Vector3(sin(half * PI), 0.0, -cos(half * PI))
			points.append({"pos": position, "dir": direction, "dist": step, "w": 26.0, "s": sid})
			position += direction * step
		for i in count:
			var angle := side * (half * PI + float(i) / count * PI)
			var direction := Vector3(sin(angle), 0.0, -cos(angle))
			var length := PI * radius / count
			points.append({"pos": position, "dir": direction, "dist": length, "w": 26.0, "s": sid})
			position += direction * length
	return CourseDefinition.new().configure("stadium", "stadium", "test", 3, points)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
