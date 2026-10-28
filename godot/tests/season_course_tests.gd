extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await _captures()
		get_tree().quit(1 if _fail else 0)
		return
	if "--city-only" in OS.get_cmdline_user_args():
		await _test_city_driving()
		get_tree().quit(1 if _fail else 0)
		return
	_test_catalog()
	await _test_garage()
	await _test_scene_rules("split_shift")
	await _test_scene_rules("block_circuit")
	await _test_city_driving()
	GameSession.set_course("split_shift")
	print("SEASON_COURSES: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_catalog() -> void:
	_check("unknown course falls back to Split Shift", CourseCatalog.sanitize("missing") == "split_shift")
	var old := TrackData.build_course()
	var expected := old.points.slice(16) + old.points.slice(0, 16)
	var actual := CourseCatalog.build_course("split_shift")
	_check("Split Shift points and start remain identical", expected == actual.points and actual.total_length == old.total_length)
	for id: String in CourseCatalog.IDS:
		var course := CourseCatalog.build_course(id)
		_check(id + " validates with three laps", course.validate().is_empty() and course.default_laps == 3)
		for gap: int in [14, 4, 9]:
			var index := course.points.size() - gap
			_check(id + " grid faces line on dry straight", course.points[index]["s"] == Surfaces.Id.TARMAC
				and (course.points[index]["dir"] as Vector3).dot(course.points[0]["dir"]) > 0.999)


func _test_garage() -> void:
	var path := "user://season_course_test.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	garage.profile_path = path
	add_child(garage)
	await get_tree().process_frame
	_check("new garage profile offers Block Circuit", GameSession.course_id == "block_circuit"
		and garage._course.get_item_metadata(garage._course.selected) == "block_circuit")
	garage._course.select(1)
	garage._course.item_selected.emit(1)
	var config := ConfigFile.new()
	_check("course choice persists", config.load(path) == OK and config.get_value("profile", "course") == "split_shift")
	var previous_callsign: String = garage._callsign.text
	garage._callsign.clear()
	garage._course.select(0)
	garage._course.item_selected.emit(0)
	config.load(path)
	_check("switching course preserves callsign while field is blank", config.get_value("profile", "callsign") == previous_callsign.strip_edges().to_upper())
	garage._load_profile()
	_check("City choice reloads", GameSession.course_id == "block_circuit" and garage._course.selected == 0)
	config.set_value("profile", "course", "invalid")
	config.save(path)
	garage._load_profile()
	_check("invalid saved selection falls back safely", GameSession.course_id == "split_shift" and garage._course.selected == 1)
	garage.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(path)


func _test_scene_rules(id: String) -> void:
	GameSession.set_course(id)
	GameSession.configure("COURSE TEST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	_check(id + " scene loads selected course", scene.course.course_id == id)
	_check(id + " scenery matches selected world", scene.has_node("CityScenery") == (id == "block_circuit"))
	var proving := false
	for child in scene.get_children():
		proving = proving or String(child.name).begins_with("Proving_")
	_check(id + " proving ground is course specific", proving == (id == "split_shift"))
	scene.set_physics_process(false)
	for racer: Vehicle in [scene.car, scene.cpu_cars[0], scene.cpu_cars[1]]:
		racer.freeze = true
	for driver: CpuDriver in scene.cpu_drivers:
		driver.enabled = false
	scene.race.tick(3.0)
	var tracker: TrackProgress = scene.player_progress
	for i in range(tracker.index, scene.course.points.size()):
		tracker.update(scene.course.points[i]["pos"])
	tracker.update(scene.course.points[0]["pos"])
	_check(id + " grid crossing does not award a lap", tracker.lap == 0)
	for lap in 3:
		for i in range(1, scene.course.points.size()):
			tracker.update(scene.course.points[i]["pos"])
		tracker.update(scene.course.points[0]["pos"])
		scene.race.tick(60.0)
	_check(id + " ordered checkpoints complete three laps", tracker.lap == 3 and scene.race.state == RaceDirector.State.RESULTS)
	scene.restart_race()
	_check(id + " retry preserves course and resets race", scene.course.course_id == id
		and tracker.lap == 0 and scene.race.state == RaceDirector.State.COUNTDOWN
		and scene.car.position.is_equal_approx(scene._spawn.origin))
	scene.queue_free()
	await get_tree().process_frame


func _test_city_driving() -> void:
	GameSession.set_course("block_circuit")
	GameSession.set_cpu_difficulty("medium")
	GameSession.configure("CITY PILOT", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	scene.items.rng.seed = 20261028
	scene.items.reset()
	var pilot := CpuDriver.new()
	pilot.setup(scene.car, scene.course, scene._grid_indices[0])
	pilot.skill = 0.9
	pilot.peers.assign([scene.car] + scene.cpu_cars)
	pilot.process_physics_priority = 200
	pilot.enabled = false
	scene.add_child(pilot)
	var wrong := [0, 0]
	var ticks := 0
	while scene.race.state != RaceDirector.State.RESULTS and ticks < 64800:
		await get_tree().physics_frame
		pilot.enabled = scene.race.state == RaceDirector.State.RACING
		if ticks < 7560:
			for i in 2:
				if scene.cpu_drivers[i].progress.wrong_way:
					wrong[i] += 1
		if ticks == 7560:
			for i in 2:
				var driver: CpuDriver = scene.cpu_drivers[i]
				print("CITY_CPU %d progress=%.1f recoveries=%d wrong_ticks=%d" % [i, driver.progress.total_distance, driver.recoveries, wrong[i]])
				_check("City CPU %d makes sustained progress" % i, driver.progress.total_distance >= 300.0
					and driver.recoveries <= 1 and wrong[i] <= 240)
		if ticks % 7200 == 0:
			print("CITY_TRACE t=%.1f lap=%d cp=%d/%d distance=%.1f off=%.1f pilot_lap=%d pilot_distance=%.1f speed=%.1f end=%s" % [scene.race.elapsed, scene.player_progress.lap, scene.player_progress._next_checkpoint, scene.course.checkpoints.size(), scene.player_progress.total_distance, scene.player_progress.off_line, pilot.progress.lap, pilot.progress.total_distance, scene.car.speed, scene.car.active_end])
		ticks += 1
	pilot.enabled = false
	_check("City physical pilot completes three laps", scene.race.state == RaceDirector.State.RESULTS and scene.player_progress.lap == 3)
	_check("City pilot stays finite with bounded recovery", scene.car.position.is_finite() and pilot.recoveries <= 3)
	_check("City pilot and player trackers agree", scene.player_progress.lap == pilot.progress.lap)
	print("CITY_RACE elapsed=%.2f recoveries=%d" % [scene.race.elapsed, pilot.recoveries])
	scene.restart_race()
	_check("City physical retry resets grid", scene.race.state == RaceDirector.State.COUNTDOWN and scene.player_progress.lap == 0)
	scene.queue_free()
	await get_tree().process_frame


func _captures() -> void:
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	garage.profile_path = "user://season_capture_unused.cfg"
	add_child(garage)
	await _capture("garage")
	garage.queue_free()
	await get_tree().process_frame
	GameSession.set_course("block_circuit")
	GameSession.configure("ROADGHOST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	for frame in 180:
		await get_tree().physics_frame
	await _capture("gameplay")
	scene.queue_free()
	await get_tree().process_frame


func _capture(label: String) -> void:
	var directory := ProjectSettings.globalize_path("res://../.ai/captures/city")
	DirAccess.make_dir_recursive_absolute(directory)
	for frame in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(label + " capture saved", get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK)


func _check(label: String, ok: bool) -> void:
	_pass += int(ok)
	_fail += int(not ok)
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
