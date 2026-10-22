## Real physics integration: multiple laps, swaps, and recoveries on guardrails.
extends Node3D

var _pass := 0
var _fail := 0
var _momentum_preserved := true


func _ready() -> void:
	_test_progress()
	_test_difficulty_settings()
	_test_braking_plan()
	var distances: Array[float] = []
	var tiers: Array[String] = ["hard", "medium", "easy"]
	if "--hard-only" in OS.get_cmdline_user_args() or "--probe" in OS.get_cmdline_user_args():
		tiers = ["hard"]
	for difficulty: String in tiers:
		distances.append(await _test_difficulty_race(difficulty))
	if tiers.size() == 3:
		_check("each difficulty gains at least 10% race progress over the same time",
			distances[0] > distances[1] * 1.10 and distances[1] > distances[2] * 1.10, str(distances))
	else:
		print("Single-tier race progress: ", distances)
	if "--probe" not in OS.get_cmdline_user_args():
		# Historical opponent timing was measured on the flat course. Keep that
		# control, and separately bound the effect of the actual uneven track.
		var flat_distance := await _test_difficulty_race("hard", true)
		_check("live relief keeps Hard field within 2% of flat control", distances[0] >= flat_distance * 0.98)
	await _test_garage_difficulty()
	print("\nCPU: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_difficulty_settings() -> void:
	_check("CPU difficulty defaults to Medium", GameSession.cpu_difficulty == "medium")
	GameSession.set_cpu_difficulty("invalid")
	_check("unknown CPU difficulty falls back to Medium", GameSession.cpu_difficulty == "medium")
	GameSession.set_cpu_difficulty("hard")
	GameSession.configure("RETRY", "blackjack", ["ramjet", "boilerfang"])
	_check("race configuration preserves CPU difficulty", GameSession.cpu_difficulty == "hard")
	var driver := CpuDriver.new()
	driver.set_difficulty("invalid")
	_check("unknown driver preset uses Medium", is_equal_approx(driver.skill, 0.81))
	driver.free()


func _test_braking_plan() -> void:
	var course := TrackData.build_course()
	var car := Vehicle.new()
	car.tuning = TuningProfile.new()
	car.freeze = true
	add_child(car)
	car.speed = 25.0
	var driver := CpuDriver.new()
	driver.set_difficulty("hard")
	driver.setup(car, course)
	var straight_speed := driver._speed_limit()
	driver.progress.reset(130)
	var approach_speed := driver._speed_limit()
	_check("Hard carries speed on a clear straight and brakes near the transition",
		straight_speed > 40.0 and approach_speed < straight_speed - 10.0 and approach_speed > 10.0,
		"straight=%.1f approach=%.1f" % [straight_speed, approach_speed])
	driver.progress.reset(160)
	car.active_end = "B"
	var full_grip := driver._speed_limit()
	car.tuning.a_tire_grip *= 0.5
	_check("corner planning respects the inactive axle's grip", driver._speed_limit() < full_grip)
	driver.free()
	car.free()


func _test_difficulty_race(difficulty: String, flat_control: bool = false) -> float:
	print("CPU DIFFICULTY: ", difficulty, " FLAT CONTROL" if flat_control else " LIVE RELIEF")
	GameSession.set_cpu_difficulty(difficulty)
	# Exercise the authored-rig CPU paths with a reproducible roster.
	GameSession.configure("CPU TEST", "blackjack", ["boilerfang", "ramjet"])
	var packed: PackedScene = load("res://scenes/proving_ground.tscn")
	var scene: Node3D = packed.instantiate()
	add_child(scene)
	if flat_control:
		# Rebuild only the ribbon. Keep the roster, tuning, route and all race
		# systems identical, using the original flat triangles for comparison.
		for child in scene.get_children():
			if child is StaticBody3D and String(child.name).begins_with("Run_"):
				scene.remove_child(child)
				child.free()
		TrackBuilder.build(scene, scene.get("course").points, false)
	await get_tree().physics_frame
	while scene.get("race").state == RaceDirector.State.COUNTDOWN:
		await get_tree().physics_frame
	scene.set_physics_process(false)
	var player: Vehicle = scene.get("car")
	player.freeze = true
	player.global_position = Vector3(-620.0, 2.0, 0.0)
	var drivers: Array[CpuDriver] = scene.get("cpu_drivers")
	for driver: CpuDriver in drivers:
		driver.target.swapped.connect(_observe_swap)
	_check("two CPU drivers use the player's tuning", drivers.size() == 2
		and drivers[0].target.tuning == player.tuning and drivers[1].target.tuning == player.tuning)
	_check("race applies selected difficulty to both CPU racers",
		is_equal_approx(drivers[0].skill, CpuDriver.DIFFICULTIES[difficulty]["pace"] - 0.04)
		and is_equal_approx(drivers[1].skill, CpuDriver.DIFFICULTIES[difficulty]["pace"] + 0.04))
	var first_laps: Array[float] = [-1.0, -1.0]
	var samples: Array[Dictionary] = [{}, {}]
	var stable := true
	var probe := "--probe" in OS.get_cmdline_user_args()
	for seconds in (180 if probe else 420):
		for _frame in 120:
			await get_tree().physics_frame
		for driver: CpuDriver in drivers:
			var p := driver.target.global_position
			var v := driver.target.linear_velocity
			stable = stable and p.is_finite() and v.is_finite()
		for i in drivers.size():
			var driver: CpuDriver = drivers[i]
			var sid := driver.target.surface_under
			var sample: Dictionary = samples[i].get(sid, {"seconds": 0, "speed": 0.0, "requested": 0.0, "turning": 0, "braking": 0})
			sample["seconds"] += 1
			sample["speed"] += driver.target.speed
			sample["requested"] += driver.target_speed
			sample["turning"] += 1 if driver._turning else 0
			sample["braking"] += 1 if driver.target.brake > 0.1 else 0
			samples[i][sid] = sample
			if drivers[i].progress.lap >= 1 and first_laps[i] < 0.0:
				first_laps[i] = float(seconds + 1)
		if seconds % 30 == 29:
			for driver: CpuDriver in drivers:
				print("t=%d %s lap=%d idx=%d speed=%.1f swaps=%d recoveries=%d off=%.1f" % [
					seconds + 1, driver.target.name, driver.progress.lap, driver.progress.index,
					driver.target.speed, driver.swaps, driver.recoveries, driver.progress.off_line])
	_check("CPU simulation remains finite", stable)
	_check("every CPU swap preserves body momentum and basis", _momentum_preserved)
	for driver: CpuDriver in drivers:
		_check("%s completes laps on %s" % [driver.target.name, difficulty], driver.progress.lap >= (1 if probe else 2))
		_check("%s performs surface swaps" % driver.target.name, driver.swaps >= (2 if probe else 4))
		_check("%s drives with limited recoveries" % driver.target.name, driver.recoveries <= (1 if difficulty == "hard" else 4),
			"%d recoveries" % driver.recoveries)
	var distance := drivers[0].progress.total_distance + drivers[1].progress.total_distance
	print("BENCHMARK %s distance=%.2f first_laps=%s" % [difficulty, distance, first_laps])
	for i in samples.size():
		for sid: int in samples[i]:
			var sample: Dictionary = samples[i][sid]
			print("PROFILE %s cpu=%d %s seconds=%d speed=%.1f requested=%.1f turning=%d braking=%d" % [difficulty,
				i, Surfaces.NAMES[sid], sample["seconds"], sample["speed"] / sample["seconds"],
				sample["requested"] / sample["seconds"], sample["turning"], sample["braking"]])
	if flat_control and not probe:
		# Winning requires beating the lead rival, while the whole field must
		# also improve. Compare against the previous fixed-roster benchmark.
		var leading_distance := maxf(drivers[0].progress.total_distance, drivers[1].progress.total_distance)
		_check("Hard leader beats previous opponent pace by at least 20%", leading_distance > (15215.05 / 2.0) * 1.20, str(leading_distance))
		_check("Hard field improves average pace by at least 15%", distance > 15215.05 * 1.15, str(distance))
	await _test_recovery(drivers[0])
	_test_peer_braking(drivers[1], player)
	scene.queue_free()
	await get_tree().process_frame
	return distance


func _test_garage_difficulty() -> void:
	# Preserve the user's profile, including a missing-file first launch.
	var profile_path := "user://profile.cfg"
	var existed := FileAccess.file_exists(profile_path)
	var original := FileAccess.get_file_as_bytes(profile_path) if existed else PackedByteArray()
	DirAccess.remove_absolute(profile_path)
	GameSession.set_cpu_difficulty("medium")
	var garage: Control = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	_check("garage offers three tiers with Medium selected", garage._difficulty.item_count == 3
		and garage._difficulty.get_item_metadata(garage._difficulty.selected) == "medium")
	garage._difficulty.select(2)
	garage._difficulty.item_selected.emit(2)
	_check("garage selection updates CPU difficulty", GameSession.cpu_difficulty == "hard"
		and "Fast pace" in garage._difficulty.tooltip_text)
	for _frame in 2:
		await get_tree().process_frame
	var visible := get_viewport().get_visible_rect()
	_check("difficulty and ignition fit the garage",
		visible.encloses(garage._difficulty.get_global_rect())
		and visible.encloses(garage._start_button.get_global_rect()))
	garage.free()
	GameSession.set_cpu_difficulty("easy")
	garage = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	_check("garage reload restores saved difficulty", GameSession.cpu_difficulty == "hard"
		and garage._difficulty.get_item_metadata(garage._difficulty.selected) == "hard")
	garage.free()
	var legacy := ConfigFile.new()
	legacy.set_value("profile", "callsign", "LEGACY")
	legacy.save(profile_path)
	garage = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	_check("existing callsign-only profiles default to Medium", GameSession.cpu_difficulty == "medium"
		and garage._callsign.text == "LEGACY")
	garage.free()
	legacy.set_value("profile", "cpu_difficulty", "unknown")
	legacy.save(profile_path)
	garage = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	_check("invalid saved difficulty falls back to Medium", GameSession.cpu_difficulty == "medium"
		and garage._difficulty.get_item_metadata(garage._difficulty.selected) == "medium")
	garage.free()
	if existed:
		var file := FileAccess.open(profile_path, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(profile_path)
	GameSession.set_cpu_difficulty("medium")
	await get_tree().process_frame


func _test_progress() -> void:
	var course := TrackData.build_course()
	var tracker := TrackProgress.new()
	tracker.setup(course, course.points.size() - 2)
	tracker.update(course.points[0]["pos"])
	_check("partial seam crossing does not award a lap", tracker.lap == 0)
	tracker.reset()
	for i in course.points.size():
		tracker.update(course.points[i]["pos"])
	tracker.update(course.points[0]["pos"])
	_check("complete ordered circuit awards one lap", tracker.lap == 1)
	var before_lap := tracker.lap
	var before_distance := tracker.total_distance
	tracker.recover(int(course.checkpoints[10]["index"]))
	_check("checkpoint recovery cannot add lap or distance",
		tracker.lap == before_lap and tracker.total_distance == before_distance)
	tracker.reset()
	for i in range(course.points.size() - 1, course.points.size() - 10, -1):
		tracker.update(course.points[i]["pos"])
	_check("backwards driving detects wrong-way without awarding a lap",
		tracker.lap == 0 and tracker.wrong_way)
	tracker.reset(100)
	var anchor := tracker.index
	var checkpoint := tracker.checkpoint_index()
	for _step in 20:
		tracker.update(Vector3(1500.0, 0.0, 1500.0))
	_check("off-course projection cannot advance the recovery anchor",
		tracker.index == anchor and tracker.checkpoint_index() == checkpoint
		and tracker.total_distance == 0.0)


func _observe_swap(record: Dictionary) -> void:
	_momentum_preserved = _momentum_preserved and record["pre_lin"] == record["post_lin"] \
		and record["pre_ang"] == record["post_ang"] and bool(record["basis_unchanged"])


func _test_recovery(driver: CpuDriver) -> void:
	var before_lap := driver.progress.lap
	var before_distance := driver.progress.total_distance
	var before_recoveries := driver.recoveries
	var lost := driver.target.global_transform
	lost.origin += Vector3(1000.0, 2.0, 1000.0)
	driver.target.global_transform = lost
	driver.target.linear_velocity = Vector3.ZERO
	driver.target.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(driver.target.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, lost)
	PhysicsServer3D.body_set_state(driver.target.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(driver.target.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	for _frame in 600:
		await get_tree().physics_frame
		if driver.recoveries > before_recoveries:
			break
	_check("off-course CPU returns to a checkpoint", driver.recoveries == before_recoveries + 1
		and driver.progress.off_line < 1.0)
	_check("physical recovery awards no race progress",
		driver.progress.lap == before_lap and driver.progress.total_distance <= before_distance + 0.1)


func _test_peer_braking(driver: CpuDriver, peer: Vehicle) -> void:
	driver.reset(40)
	driver.set_physics_process(false)
	driver._settle_time = 0.0
	driver.target.speed = 15.0
	var forward := driver.target.forward_vector()
	peer.global_position = driver.target.global_position + forward * 8.0
	peer.linear_velocity = Vector3.ZERO
	driver.tick(1.0 / 120.0)
	_check("CPU brakes for a stopped vehicle ahead",
		driver.target.throttle == 0.0 and driver.target.brake > 0.5)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s %s" % ["pass" if ok else "FAIL", label, detail])
