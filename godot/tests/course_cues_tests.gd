extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	var course := TrackData.build_course()
	var original := course.points.duplicate(true)
	var original_checkpoints := course.checkpoints.duplicate(true)
	var original_length := course.total_length
	var cues := CourseCues.new()
	cues.setup(course)
	_check("cue setup preserves course data", course.points == original
		and course.checkpoints == original_checkpoints and course.total_length == original_length)
	var mud: Dictionary = {}
	var ice: Dictionary = {}
	var no_rumble := true
	for event: Dictionary in cues.events:
		no_rumble = no_rumble and int(event["surface"]) != Surfaces.Id.RUMBLE
		if int(event["surface"]) == Surfaces.Id.MUD and mud.is_empty():
			mud = event
		if int(event["surface"]) == Surfaces.Id.ICE:
			ice = event
	_check("rumble warnings do not hide meaningful destinations", no_rumble and not mud.is_empty() and not ice.is_empty())
	var before := float(mud["distance"]) - 60.0
	var cue := cues.upcoming(before, 20.0)
	_check("mud cue reports route distance", int(cue.get("surface", -1)) == Surfaces.Id.MUD
		and is_equal_approx(float(cue.get("metres", -1.0)), 60.0))
	_check("high-speed lookahead gives preparation time", not cues.upcoming(float(mud["distance"]) - 160.0, 45.0).is_empty())
	_check("slow lookahead does not announce distant terrain", cues.upcoming(float(mud["distance"]) - 160.0, 5.0).is_empty())
	_check("current boundary is not announced as upcoming", int(cues.upcoming(float(mud["distance"]), 5.0).get("surface", -1)) != Surfaces.Id.MUD)
	_check("mud suggests B while keeping B ready", "PREPARE END B" in CourseCues.advice(Surfaces.Id.MUD, "A")
		and CourseCues.advice(Surfaces.Id.MUD, "B") == "END B READY")
	_check("tarmac suggests A", "PREPARE END A" in CourseCues.advice(Surfaces.Id.TARMAC, "B"))
	_check("ice advises low grip and holds either active end", CourseCues.advice(Surfaces.Id.ICE, "B") == "LOW GRIP — HOLD END B"
		and CourseCues.advice(Surfaces.Id.ICE, "A") == "LOW GRIP — HOLD END A")
	_check("oil advice avoids unnecessary turnaround", CourseCues.board_advice(Surfaces.Id.OIL) == "LOW GRIP")
	var one_surface := course.points.duplicate(true)
	for point: Dictionary in one_surface:
		point["s"] = Surfaces.Id.TARMAC
	var plain := CourseDefinition.new().configure("plain", "plain", "plain", 3, one_surface)
	var plain_cues := CourseCues.new()
	plain_cues.setup(plain)
	_check("single surface course has no warnings", plain_cues.events.is_empty() and plain_cues.upcoming(0.0, 50.0).is_empty())
	one_surface[10]["s"] = Surfaces.Id.RUMBLE
	plain_cues.setup(plain)
	_check("same surface either side of rumble produces no warning", plain_cues.events.is_empty())
	var ordered := true
	for i in cues.events.size():
		var event: Dictionary = cues.events[i]
		var previous: Dictionary = cues.events[posmod(i - 1, cues.events.size())]
		var gap := fposmod(float(event["distance"]) - float(previous["distance"]), course.total_length)
		ordered = ordered and float(event["lead"]) > 0.0 and float(event["lead"]) <= CourseCues.BOARD_LEAD
		ordered = ordered and float(event["lead"]) < gap
	_check("warning boards stay after the previous terrain boundary", ordered)
	var at_zero := cues.sample_at(0.0)
	var at_wrap := cues.sample_at(course.total_length)
	_check("sampling wraps at finish", at_zero["position"].is_equal_approx(at_wrap["position"]))
	# Put a real transition at index zero, exercising next-lap approach advice.
	var pivot := int(mud["index"])
	var rotated := CourseDefinition.new().configure("test", "test", "test", 3,
		course.points.slice(pivot) + course.points.slice(0, pivot))
	var seam := CourseCues.new()
	seam.setup(rotated)
	var seam_cue := seam.upcoming(rotated.total_length - 40.0, 20.0)
	_check("next-lap transition is announced across finish seam", int(seam_cue.get("surface", -1)) == Surfaces.Id.MUD
		and is_equal_approx(float(seam_cue.get("metres", -1.0)), 40.0))
	await _test_scene()
	print("COURSE_CUES: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_scene() -> void:
	GameSession.configure("CUE TEST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	for car: Vehicle in [scene.car] + scene.cpu_cars:
		car.freeze = true
	var boards: Node3D = scene.get_node("TerrainWarnings")
	_check("every transition has paired roadside signs", boards.get_child_count() == scene.course_cues.events.size() * 2)
	_check("approach signs add no collisions", boards.find_children("*", "CollisionObject3D", true, false).is_empty())
	var facing := true
	var readable_fronts := true
	for i in scene.course_cues.events.size():
		var event: Dictionary = scene.course_cues.events[i]
		var sample: Dictionary = scene.course_cues.sample_at(float(event["distance"]) - float(event["lead"]))
		for side in 2:
			var board: Node3D = boards.get_child(i * 2 + side)
			facing = facing and board.basis.z.dot(-sample["direction"]) > 0.99
			readable_fronts = readable_fronts and not board.get_node("WarningText").double_sided
	_check("sign text faces approaching traffic", facing)
	_check("sign text does not show mirrored through the back", readable_fronts)
	var event: Dictionary = scene.course_cues.events[0]
	var sample: Dictionary = scene.course_cues.sample_at(float(event["distance"]) - 60.0)
	scene.player_progress.reset()
	# Walk the tracker to the approach without teleporting its route anchor.
	for point: Dictionary in scene.track:
		if point["pos"].distance_to(sample["position"]) < 5.0:
			break
		scene.player_progress.update(point["pos"])
	scene.player_progress.update(sample["position"])
	scene.car.speed = 20.0
	scene.race.state = RaceDirector.State.RACING
	scene.hud._process(0.0)
	_check("racing HUD shows advance surface advice", not scene.hud._upcoming.text.is_empty())
	var active: String = scene.car.active_end
	var velocity: Vector3 = scene.car.linear_velocity
	scene.hud._process(0.0)
	_check("advice never swaps or changes velocity", scene.car.active_end == active and scene.car.linear_velocity == velocity)
	await get_tree().process_frame
	_check("cue fits viewport above controls", get_viewport().get_visible_rect().encloses(scene.hud._upcoming.get_global_rect())
		and not scene.hud._upcoming.get_global_rect().intersects(scene.hud._hint.get_global_rect()))
	scene.player_progress.wrong_way = true
	scene.hud._process(0.0)
	_check("wrong-way suppresses forward advice", scene.hud._upcoming.text.is_empty())
	scene.player_progress.wrong_way = false
	scene.player_progress.off_line = float(scene.track[scene.player_progress.index]["w"]) * 0.65
	scene.hud._process(0.0)
	_check("off-course suppresses route advice", scene.hud._upcoming.text.is_empty())
	scene.player_progress.off_line = 0.0
	scene.race.state = RaceDirector.State.COUNTDOWN
	scene.hud._process(0.0)
	_check("countdown suppresses race advice", scene.hud._upcoming.text.is_empty())
	scene.race.state = RaceDirector.State.RESULTS
	scene.hud._process(0.0)
	_check("results suppress race advice", scene.hud._upcoming.text.is_empty())
	scene.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
