extends Node3D

const TICK_CAP := 43200
const TRACE_EVERY := 7200
const PROGRESS_TICK := 7560
const WORLD_PREFIXES: Array[String] = ["Ground", "GuardRails", "CityScenery", "Run_", "Proving_", "TrackVisualSample", "TerrainDeposits"]

var _pass := 0
var _fail := 0


func _ready() -> void:
	var saved_course := GameSession.course_id
	var saved_laps := GameSession.race_laps
	var saved_reverse := GameSession.race_reverse
	var saved_setup := GameSession.race_setup_active
	var saved_season: SeasonRun = GameSession.season
	var saved_difficulty := GameSession.cpu_difficulty
	for id: String in CourseCatalog.IDS:
		await _test_reverse_course(id)
	GameSession.course_id = saved_course
	GameSession.race_laps = saved_laps
	GameSession.race_reverse = saved_reverse
	GameSession.race_setup_active = saved_setup
	GameSession.season = saved_season
	GameSession.cpu_difficulty = saved_difficulty
	print("REVERSE_RACE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _spawn(id: String, reverse: bool) -> Variant:
	GameSession.season = null
	GameSession.begin_single(id, 1, reverse)
	GameSession.set_cpu_difficulty("medium")
	GameSession.configure("REVERSE PILOT", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	return scene


func _world_signature(scene: Node) -> Dictionary:
	var signature := {}
	for child in scene.get_children():
		var child_name := String(child.name)
		var wanted := false
		for prefix: String in WORLD_PREFIXES:
			wanted = wanted or child_name.begins_with(prefix)
		if not wanted:
			continue
		var count := 0
		var bounds := AABB()
		var seeded := false
		var stack: Array[Node] = [child]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			count += 1
			stack.append_array(node.get_children())
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var box: AABB = (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
				bounds = box if not seeded else bounds.merge(box)
				seeded = true
		signature[child_name] = {"nodes": count, "bounds": bounds}
	return signature


func _same_world(a: Dictionary, b: Dictionary) -> bool:
	if a.keys() != b.keys():
		return false
	for key: String in a:
		if a[key]["nodes"] != b[key]["nodes"]:
			return false
		var left: AABB = a[key]["bounds"]
		var right: AABB = b[key]["bounds"]
		if not left.position.is_equal_approx(right.position) or not left.size.is_equal_approx(right.size):
			return false
	return true


func _test_reverse_course(id: String) -> void:
	var forward: Variant = await _spawn(id, false)
	await get_tree().physics_frame
	var forward_world := _world_signature(forward)
	var forward_start: Vector3 = forward.course.points[0]["pos"]
	forward.queue_free()
	await get_tree().process_frame
	var scene: Variant = await _spawn(id, true)
	await get_tree().physics_frame
	_check(id + " reverse scene loads a reverse course", scene.course.course_id == id and scene.course.is_reverse and scene.course.default_laps == 1)
	_check(id + " reverse scene keeps the forward world measurably identical", not forward_world.is_empty() and _same_world(forward_world, _world_signature(scene)))
	_check(id + " reverse scene has a safe grid", scene.course.validate().is_empty() and scene.car.global_position.is_finite()
		and scene.car.global_position.y > -1.0)
	_check(id + " reverse grid faces along the reversed road", (-scene.car.global_basis.z).dot(scene.course.points[scene._grid_indices[0]]["dir"]) > 0.95)
	print("REVERSE_WORLD %s forward_start=%s reverse_start=%s" % [id, forward_start, scene.course.points[0]["pos"]])
	scene.items.rng.seed = 20261028
	scene.items.reset()
	var pilot := CpuDriver.new()
	pilot.setup(scene.car, scene.course, scene._grid_indices[0])
	pilot.set_difficulty("hard")
	pilot.peers.assign([scene.car] + scene.cpu_cars)
	pilot.process_physics_priority = 200
	pilot.enabled = false
	scene.add_child(pilot)
	var wrong := [0, 0]
	var ticks := 0
	while scene.race.state != RaceDirector.State.RESULTS and ticks < TICK_CAP:
		await get_tree().physics_frame
		pilot.enabled = scene.race.state == RaceDirector.State.RACING
		if ticks < PROGRESS_TICK:
			for i in 2:
				if scene.cpu_drivers[i].progress.wrong_way:
					wrong[i] += 1
		if ticks == PROGRESS_TICK:
			for i in 2:
				var driver: CpuDriver = scene.cpu_drivers[i]
				print("REVERSE_CPU %s %d progress=%.1f recoveries=%d wrong_ticks=%d" % [id, i, driver.progress.total_distance, driver.recoveries, wrong[i]])
				_check("%s reverse CPU %d makes sustained progress" % [id, i], driver.progress.total_distance >= 300.0
					and driver.recoveries <= 1 and wrong[i] <= 240 and driver.target.global_position.is_finite())
		if ticks % TRACE_EVERY == 0:
			print("REVERSE_TRACE %s t=%.1f lap=%d cp=%d/%d distance=%.1f off=%.1f pilot_lap=%d pilot_distance=%.1f speed=%.1f recoveries=%d state=%d" % [
				id, scene.race.elapsed, scene.player_progress.lap, scene.player_progress._next_checkpoint, scene.course.checkpoints.size(),
				scene.player_progress.total_distance, scene.player_progress.off_line, pilot.progress.lap, pilot.progress.total_distance,
				scene.car.speed, pilot.recoveries, scene.race.state])
		ticks += 1
	pilot.enabled = false
	print("REVERSE_RACE %s ticks=%d elapsed=%.2f recoveries=%d" % [id, ticks, scene.race.elapsed, pilot.recoveries])
	_check(id + " reverse physical pilot completes one lap", scene.race.state == RaceDirector.State.RESULTS and scene.player_progress.lap == 1)
	_check(id + " reverse pilot stays finite with bounded recovery", scene.car.position.is_finite() and pilot.recoveries <= 3)
	_check(id + " reverse pilot and player trackers agree", scene.player_progress.lap == pilot.progress.lap)
	for i in 2:
		_check("%s reverse CPU %d ends finite" % [id, i], scene.cpu_cars[i].global_position.is_finite() and scene.cpu_drivers[i].progress.total_distance > 0.0)
	scene.restart_race()
	_check(id + " reverse retry resets the grid and keeps the direction", scene.race.state == RaceDirector.State.COUNTDOWN
		and scene.player_progress.lap == 0 and scene.course.is_reverse and GameSession.race_reverse)
	scene.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	_pass += int(ok)
	_fail += int(not ok)
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
