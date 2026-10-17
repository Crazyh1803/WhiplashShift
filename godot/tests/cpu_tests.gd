## Real physics integration: multiple laps, swaps, and recoveries on guardrails.
extends Node3D

var _pass := 0
var _fail := 0
var _momentum_preserved := true


func _ready() -> void:
	_test_progress()
	# Exercise the authored-rig CPU paths with a reproducible roster.
	GameSession.configure("CPU TEST", "blackjack", ["deadbolt", "nightshift"])
	var packed: PackedScene = load("res://scenes/proving_ground.tscn")
	var scene: Node3D = packed.instantiate()
	add_child(scene)
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
	var stable := true
	for seconds in 420:
		for _frame in 120:
			await get_tree().physics_frame
		for driver: CpuDriver in drivers:
			var p := driver.target.global_position
			var v := driver.target.linear_velocity
			stable = stable and p.is_finite() and v.is_finite()
		if seconds % 30 == 29:
			for driver: CpuDriver in drivers:
				print("t=%d %s lap=%d idx=%d speed=%.1f swaps=%d recoveries=%d off=%.1f" % [
					seconds + 1, driver.target.name, driver.progress.lap, driver.progress.index,
					driver.target.speed, driver.swaps, driver.recoveries, driver.progress.off_line])
	_check("CPU simulation remains finite", stable)
	_check("every CPU swap preserves body momentum and basis", _momentum_preserved)
	for driver: CpuDriver in drivers:
		_check("%s completes two laps" % driver.target.name, driver.progress.lap >= 2)
		_check("%s performs surface swaps" % driver.target.name, driver.swaps >= 4)
		_check("%s drives with limited recoveries" % driver.target.name, driver.recoveries <= 4,
			"%d recoveries" % driver.recoveries)
	await _test_recovery(drivers[0])
	_test_peer_braking(drivers[1], player)
	scene.queue_free()
	await get_tree().process_frame
	print("\nCPU: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


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
