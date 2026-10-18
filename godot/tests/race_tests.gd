extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_rules()
	_test_progress()
	await _test_scene()
	await _test_driven_race()
	print("RACE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_rules() -> void:
	var course := TrackData.build_course()
	var trackers: Array[TrackProgress] = []
	for gap: int in [14, 4, 9]:
		var tracker := TrackProgress.new()
		tracker.setup(course, course.points.size() - gap)
		trackers.append(tracker)
	var director := RaceDirector.new()
	director.setup(course, ["PLAYER", "CPU ONE", "CPU TWO"], trackers)
	_check("grid standings follow staggered route position", director.standings() == [1, 2, 0])
	director.tick(2.0)
	_check("countdown does not advance the race clock", director.state == RaceDirector.State.COUNTDOWN and director.elapsed == 0.0)
	director.tick(1.0)
	_check("GO opens the race with a zero clock", director.state == RaceDirector.State.RACING and director.elapsed == 0.0)
	for tracker: TrackProgress in trackers:
		for i in range(tracker.index, course.points.size()):
			tracker.update(course.points[i]["pos"])
		tracker.update(course.points[0]["pos"])
	_check("crossing from the grid does not complete a lap", trackers[0].lap == 0 and trackers[1].lap == 0)
	_check("line crossing keeps standings continuous", absf(trackers[0].route_distance - course.total_length) < 0.01)
	for lap in 2:
		_drive_lap(trackers[0])
		director.tick(60.0)
	_check("two full laps do not finish a three-lap race", trackers[0].lap == 2 and director.state == RaceDirector.State.RACING)
	# Two CPUs cross on one tick. Their crossing fractions determine their order.
	var finish_line := course.total_length * 4.0
	for i in [1, 2]:
		trackers[i].route_distance = finish_line - 10.0
	director.tick(1.0)
	trackers[1].lap = 3
	trackers[2].lap = 3
	trackers[1].route_distance = finish_line + 1.0
	trackers[2].route_distance = finish_line + 10.0
	director.tick(1.0)
	_check("same-tick finishers sort by crossing time", director.finish_order == [2, 1])
	_check("CPU finish leaves the player racing", director.state == RaceDirector.State.RACING)
	_drive_lap(trackers[0])
	director.tick(60.0)
	_check("third full lap produces player results", director.state == RaceDirector.State.RESULTS and director.player_position() == 3)
	var order := director.standings()
	var time := director.elapsed
	trackers[0].route_distance += 1000.0
	director.tick(50.0)
	_check("results clock and finish order are immutable", director.elapsed == time and director.standings() == order)
	_check("clock renders minutes seconds and hundredths", RaceDirector.clock_text(65.25) == "01:05.25")
	# A player win must not fabricate rival finish times.
	for tracker: TrackProgress in trackers:
		tracker.reset(course.points.size() - 4)
	director.setup(course, ["PLAYER", "CPU ONE", "CPU TWO"], trackers)
	director.tick(3.0)
	trackers[0].lap = 3
	trackers[0].route_distance = finish_line
	director.tick(1.0)
	_check("player win leaves unfinished rivals without times", director.player_position() == 1
		and float(director.entrants[1]["finish_time"]) == -1.0)
	for tracker: TrackProgress in trackers:
		tracker.reset(course.points.size() - 4)
	director.setup(course, ["PLAYER", "CPU ONE", "CPU TWO"], trackers)
	director.tick(3.0)
	for tracker: TrackProgress in trackers:
		tracker.lap = 3
		tracker.route_distance = finish_line
	director.tick(1.0)
	_check("exact finish ties use stable entrant order", director.finish_order == [0, 1, 2])


func _test_progress() -> void:
	var course := TrackData.build_course()
	var tracker := TrackProgress.new()
	tracker.setup(course)
	for i in 81:
		tracker.update(course.points[i]["pos"])
	var original := tracker.route_distance
	var checkpoint := tracker.checkpoint_index()
	tracker.recover(checkpoint)
	_check("recovery moves standings back to the checkpoint", tracker.route_distance <= original)
	for i in range(checkpoint, 81):
		tracker.update(course.points[i]["pos"])
	_check("redriving recovered ground cannot inflate standings", is_equal_approx(tracker.route_distance, original))
	tracker.reset()
	for i in range(course.points.size() - 1, course.points.size() - 10, -1):
		tracker.update(course.points[i]["pos"])
	_check("reverse across finish moves standings backwards", tracker.route_distance < 0.0 and tracker.lap == 0 and tracker.wrong_way)
	# A forward recovery must not stand in for passing the intervening checkpoints.
	tracker.reset()
	tracker.recover(int(course.checkpoints[2]["index"]))
	for i in range(tracker.index, course.points.size()):
		tracker.update(course.points[i]["pos"])
	tracker.update(course.points[0]["pos"])
	_check("skipped checkpoints prevent a lap award", tracker.lap == 0)
	_drive_lap(tracker)
	_check("a clean lap after skipped checkpoints counts normally", tracker.lap == 1)


func _drive_lap(tracker: TrackProgress) -> void:
	for i in tracker.course.points.size():
		tracker.update(tracker.course.points[i]["pos"])
	tracker.update(tracker.course.points[0]["pos"])


func _test_scene() -> void:
	GameSession.configure("RACE TEST", "deadbolt", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	var initial: Vector3 = scene.car.position
	Input.parse_input_event(_key(KEY_W, true))
	_send(scene, KEY_SPACE)
	_send(scene, KEY_R)
	for frame in 120:
		await get_tree().physics_frame
	_check("countdown locks player throttle and swap", scene.car.throttle == 0.0 and scene.car.active_end == "A")
	_check("countdown holds all CPU controls", not scene.cpu_drivers[0].enabled and scene.cpu_cars[0].throttle == 0.0)
	var settled: Vector3 = scene.car.position
	_check("grid suspension settles before GO", settled.y < initial.y and Vector2(settled.x, settled.z).distance_to(Vector2(initial.x, initial.z)) < 1.0)
	Input.parse_input_event(_key(KEY_W, false))
	for frame in 250:
		await get_tree().physics_frame
	_check("countdown starts both CPU opponents", scene.race.state == RaceDirector.State.RACING and scene.cpu_drivers[0].enabled and scene.cpu_drivers[1].enabled)
	_send(scene, KEY_SPACE)
	_check("swap becomes available during racing", scene.car.active_end == "B")
	# Isolate rule/input integration from autonomous motion for deterministic checks.
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	for entrant: Vehicle in [scene.car] + scene.cpu_cars:
		entrant.freeze = true
	for i in 81:
		scene.player_progress.update(scene.track[i]["pos"])
	var cpu_index: int = scene.cpu_drivers[0].progress.index
	var cpu_position: Vector3 = scene.cpu_cars[0].position
	var before: float = scene.player_progress.route_distance
	_send(scene, KEY_R)
	_check("R recovers only the player without awarding progress", scene.player_progress.route_distance <= before
		and scene.cpu_drivers[0].progress.index == cpu_index and scene.cpu_cars[0].position == cpu_position
		and scene.car.linear_velocity == Vector3.ZERO)
	# Finish a rival first; it must no longer obstruct or influence the other CPU.
	scene.cpu_drivers[0].progress.lap = 3
	scene.cpu_drivers[0].progress.route_distance = scene.course.total_length * 4.0
	scene._physics_process(0.1)
	_check("finished CPU is retired from collisions and peer braking", scene.cpu_cars[0].collision_layer == 0
		and scene.cpu_cars[0].collision_mask == 0 and not scene.cpu_drivers[1].peers.has(scene.cpu_cars[0])
		and scene.cpu_cars[0].freeze and not scene.cpu_drivers[0].enabled)
	_send(scene, KEY_F2)
	_check("debug CPU toggle cannot revive a finisher", not scene.cpu_drivers[0].enabled)
	scene.player_progress.lap = 3
	scene.player_progress.route_distance = scene.course.total_length * 4.0
	scene._physics_process(0.1)
	scene.hud._process(0.0)
	_check("player finish freezes field and shows standings", scene.race.state == RaceDirector.State.RESULTS
		and scene.car.freeze and scene.car.throttle == 0.0 and scene.hud._results.visible
		and "UNFINISHED" in scene.hud._results_text.text and scene.race.player_position() == 2)
	var end: String = scene.car.active_end
	var finished_position: Vector3 = scene.car.position
	_send(scene, KEY_SPACE)
	_send(scene, KEY_R)
	_check("results block swap and recovery", scene.car.active_end == end and scene.car.position == finished_position)
	var retry: Button = scene.hud._results.find_child("RetryButton", true, false)
	retry.pressed.emit()
	scene.hud._process(0.0)
	_check("retry button returns same roster to a fresh countdown", scene.race.state == RaceDirector.State.COUNTDOWN
		and scene.race.elapsed == 0.0 and scene.race.finish_order.is_empty() and scene.player_progress.lap == 0
		and scene.car.vehicle_id == "deadbolt" and scene.cpu_cars[0].vehicle_id == "boilerfang"
		and scene.cpu_cars[1].vehicle_id == "ramjet" and not scene.hud._results.visible)
	_check("retry restores collisions visibility and grid control locks", scene.cpu_cars[0].collision_layer > 0
		and scene.cpu_cars[0].visible and not scene.car.freeze and not scene.cpu_drivers[0].enabled
		and scene.car.position.is_equal_approx(scene._spawn.origin) and scene.car.active_end == "A"
		and scene.cpu_drivers[0].peers.has(scene.car) and scene.car._pending.is_empty())
	# Both keyboard retry and the garage result button are wired without focus shortcuts.
	scene.race.state = RaceDirector.State.RESULTS
	_send(scene, KEY_ENTER)
	_check("Enter retries results", scene.race.state == RaceDirector.State.COUNTDOWN)
	var menu: Button = scene.hud._results.find_child("GarageButton", true, false)
	_check("result actions do not steal keyboard focus", retry.focus_mode == Control.FOCUS_NONE and menu.focus_mode == Control.FOCUS_NONE)
	scene.hud.main_menu_requested.disconnect(scene._return_to_menu)
	var called := [false]
	scene.hud.main_menu_requested.connect(func() -> void: called[0] = true)
	menu.pressed.emit()
	_check("result garage button emits menu action and preserves selection", called[0] and GameSession.selected_vehicle_id == "deadbolt")
	scene.queue_free()
	await get_tree().process_frame


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _test_driven_race() -> void:
	# A real physical race: a test-only CPU supplies the player's inputs after
	# the scene reads the keyboard. Production progress/rules/HUD stay enabled.
	GameSession.configure("AUTOPILOT TEST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	var pilot := CpuDriver.new()
	pilot.setup(scene.car, scene.course, scene._grid_indices[0])
	pilot.skill = 0.9
	pilot.peers.assign([scene.car] + scene.cpu_cars)
	pilot.process_physics_priority = 200
	pilot.enabled = false
	scene.add_child(pilot)
	var ticks := 0
	while scene.race.state != RaceDirector.State.RESULTS and ticks < 86400:
		await get_tree().physics_frame
		pilot.enabled = scene.race.state == RaceDirector.State.RACING
		ticks += 1
	pilot.enabled = false
	_check("physical player completes three full laps and reaches results", scene.race.state == RaceDirector.State.RESULTS
		and scene.player_progress.lap == 3 and scene.car.position.is_finite())
	_check("physical finish records a plausible race time", float(scene.race.entrants[0]["finish_time"]) > 60.0
		and float(scene.race.entrants[0]["finish_time"]) <= scene.race.elapsed)
	print("  Driven race: %.2fs, position %d, pilot recoveries %d" % [scene.race.elapsed, scene.race.player_position(), pilot.recoveries])
	_check("physical race requires bounded recovery", pilot.recoveries <= 6)
	scene.restart_race()
	pilot.progress.reset(scene._grid_indices[0])
	for frame in 7560:
		await get_tree().physics_frame
		pilot.enabled = scene.race.state == RaceDirector.State.RACING
	pilot.enabled = false
	_check("physical retry starts driving a fresh race", scene.race.state == RaceDirector.State.RACING
		and scene.race.elapsed > 59.0 and scene.race.elapsed < 61.0
		and scene.player_progress.total_distance > 200.0 and scene.car.position.is_finite()
		and scene.race.finish_order.is_empty())
	scene.queue_free()
	await get_tree().process_frame


func _send(scene: Node, code: Key) -> void:
	scene._unhandled_key_input(_key(code))


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
