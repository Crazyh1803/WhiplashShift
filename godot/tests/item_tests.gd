extends Node3D

var _pass := 0
var _fail := 0
var scene: Node3D
var items: RaceItems
var race: RaceDirector


func _ready() -> void:
	_test_odds()
	await _run()
	print("ITEMS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_odds() -> void:
	var counts := {}
	for i in 10000:
		var id := ItemCatalog.roll((float(i) + 0.5) / 10000.0)
		counts[id] = int(counts.get(id, 0)) + 1
	for id: String in ItemCatalog.IDS:
		_check(id + " has configured pickup odds", int(counts.get(id, 0)) == int(ItemCatalog.DATA[id]["weight"]) * 100)
	_check("homing is rare at exactly one percent", counts["homing"] == 100)
	_check("roll boundaries are safe", ItemCatalog.roll(-1.0) == "shield" and ItemCatalog.roll(1.0) == "homing")


func _run() -> void:
	scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	items = scene.items
	race = scene.race
	_check("course has rows of three pickups", items.pickups.size() >= 9 and items.pickups.size() % 3 == 0)
	items.held[0] = "rockets"
	_check("countdown blocks activation", not items.fire(0) and items.held[0] == "rockets")
	race.tick(3.0)
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	for car: Vehicle in items.cars:
		car.gravity_scale = 0.0
		car.freeze = false
		car.linear_velocity = Vector3.ZERO
	# Elevated isolated road for collision, blast and oil tests.
	var road := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(250, 2, 250)
	shape.shape = box
	road.add_child(shape)
	add_child(road)
	road.position = Vector3(1100, 7, 1100)
	await _fixture()
	var pickup: Dictionary = items.pickups[0]
	items.cars[0].global_position = pickup["pos"]
	items.previous_positions[0] = pickup["pos"]
	items.tick(0.01)
	_check("pickup grants a random valid item", ItemCatalog.IDS.has(items.held[0]) and float(pickup["cooldown"]) > 0.0)
	var second: Dictionary = items.pickups[1]
	items.cars[0].global_position = second["pos"]
	items.previous_positions[0] = second["pos"]
	items.tick(0.01)
	_check("held slot leaves other pickups untouched", float(second["cooldown"]) == 0.0)
	items.held[0] = "machine_guns"
	_check("E starts automatic weapon and consumes inventory", items.fire(0) and items.held[0].is_empty()
		and items.active[0] == "machine_guns" and items.shots.size() == 1)
	items._collect(0.01)
	_check("active item prevents inventory stacking", items.held[0].is_empty() and float(second["cooldown"]) == 0.0)
	_check("repeat E cannot restart timer", not items.fire(0) and items.remaining[0] == 6.0)
	items._tick_active(0, 0.5)
	_check("guns keep firing without more input", items.shots.size() == 4 and is_equal_approx(items.remaining[0], 5.5))
	items._tick_active(0, 20.0)
	_check("long frame expires guns without a catch-up barrage", items.active[0].is_empty() and items.shots.size() == 8)
	for id: String in ["rockets", "grenades"]:
		await _fixture()
		items.held[0] = id
		items.fire(0)
		items._tick_active(0, float(ItemCatalog.DATA[id]["interval"]) + 0.01)
		_check(id + " fire repeatedly after one activation", items.shots.size() == 2)
		if id == "grenades":
			_check("grenades launch in an arc", Vector3(items.shots[0]["velocity"]).y > 0.0)
		items._tick_active(0, 20.0)
		_check(id + " expire automatically", items.active[0].is_empty())
	await _fixture()
	items.held[0] = "rockets"
	items.fire(0)
	items.cars[1].linear_velocity = Vector3(0, 0, -20)
	await get_tree().physics_frame
	items._tick_shots(0.3)
	_check("swept rockets hit between ticks", items.shots.is_empty() and items.protection[1] > 0.0)
	await get_tree().physics_frame
	_check("weapon hit reduces real speed", items.cars[1].linear_velocity.length() < 18.0 and items.cars[1].linear_velocity.length() > 10.0)
	items.cars[0].active_end = "B"
	items.reset_racer(0)
	items.held[0] = "rockets"
	items.fire(0)
	_check("swap redirects automatic fire to active end", Vector3(items.shots[0]["velocity"]).z > 0.0)
	await _fixture()
	items.held[1] = "shield"
	items.fire(1)
	items._apply_hit(1, 0, "rockets")
	items._apply_hit(1, 0, "machine_guns")
	_check("shield blocks multiple hits for entire duration", items.protection[1] == 0.0 and items.active[1] == "shield" and items._shields[1].visible)
	items._tick_active(1, 4.9)
	_check("shield persists until its deadline", items.active[1] == "shield")
	items._tick_active(1, 0.11)
	items._apply_hit(1, 0, "rockets")
	_check("expired shield no longer blocks", items.active[1].is_empty() and not items._shields[1].visible and items.protection[1] > 0.0)
	await _fixture()
	items.held[0] = "machine_guns"
	items.fire(0)
	for step in 120:
		items._tick_active(0, 0.05)
	_check("normal timer cadence emits forty bullets over six seconds", items.shots.size() == 40 and items.active[0].is_empty())
	var tracker: TrackProgress = race.entrants[1]["progress"]
	tracker.route_distance += 400.0
	_check("adjacent track sections cannot be missile targets", items._target(0) < 0)
	# Wall stops direct rockets and their splash on its far side.
	await _fixture()
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(30, 20, 1)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	add_child(wall)
	wall.position = Vector3(1100, 10, 1083)
	await get_tree().physics_frame
	items.held[0] = "rockets"
	items.fire(0)
	items._tick_shots(0.3)
	_check("wall blocks projectiles and splash", items.shots.is_empty() and items.protection[1] == 0.0 and items._target(0) < 0)
	wall.queue_free()
	await _fixture()
	items.held[0] = "grenades"
	items.fire(0)
	var shot := items.shots[0]
	items._impact(shot, items.cars[1].global_position + Vector3.RIGHT * 4.0, Vector3.UP, null)
	_check("grenade blast hits nearby car without direct collision", items.protection[1] > 0.0)
	await _fixture()
	items.held[0] = "homing"
	items.cars[1].global_position.x += 10.0
	await get_tree().physics_frame
	_check("homing locks a visible target", items.fire(0))
	_check("homing emits exactly one missile with no active timer", items.shots.size() == 1 and items.active[0].is_empty() and items.held[0].is_empty())
	var initial: Vector3 = items.shots[0]["velocity"]
	items._tick_shots(0.02)
	_check("homing steers towards locked target", Vector3(items.shots[0]["velocity"]).x > initial.x)
	items._tick_active(0, 10.0)
	_check("homing cannot auto-repeat", items.shots.size() == 1 and not items.fire(0))
	await _fixture()
	items.cars[1].global_position = Vector3(1200, 10, 1100)
	await get_tree().physics_frame
	items.held[0] = "homing"
	_check("no lock preserves rare missile", not items.fire(0) and items.held[0] == "homing")
	await _fixture()
	items.held[0] = "smoke"
	items.fire(0)
	_check("smoke deploys behind the active end", items.hazards.size() == 1 and Vector3(items.hazards[0]["pos"]).z > items.cars[0].global_position.z)
	items._tick_active(0, 1.01)
	_check("smoke continues deploying automatically", items.hazards.size() == 3)
	var cloud: Vector3 = items.hazards[0]["pos"]
	_check("smoke obstructs targeting", items._smoke_blocks(cloud - Vector3.FORWARD * 10, cloud + Vector3.FORWARD * 10))
	items.cars[1].global_position = cloud
	items._tick_hazards(0.01)
	_check("car inside smoke has obscured status", items.obscured[1])
	items.cars[0].active_end = "B"
	items.cars[1].global_position = items.cars[0].global_position + Vector3.BACK * 25.0
	await get_tree().physics_frame
	_check("smoke prevents an otherwise visible missile lock", items._target(0) < 0)
	items._tick_hazards(10.0)
	_check("missile lock returns after smoke expires", items._target(0) == 1)
	_check("deployed smoke expires", items.hazards.is_empty())
	await _fixture()
	items.held[0] = "oil"
	items.fire(0)
	_check("oil creates a road patch", items.hazards.size() == 1 and items.hazards[0]["id"] == "oil")
	var oil: Vector3 = items.hazards[0]["pos"]
	items.cars[1].global_position = oil + Vector3.UP * 1.5
	items.previous_positions[1] = items.cars[1].global_position
	items.tick(0.01)
	_check("oil reduces grip temporarily", items.oil_time[1] > 0.0 and items.cars[1].item_grip_multiplier == RaceItems.OIL_GRIP)
	items.held[1] = "shield"
	items.fire(1)
	items.tick(0.01)
	_check("shield clears oil and blocks reapplication", items.oil_time[1] == 0.0 and items.cars[1].item_grip_multiplier == 1.0)
	items._stop(1)
	items.tick(0.01)
	items.cars[1].global_position.x += 30.0
	items.previous_positions[1] = items.cars[1].global_position
	items.tick(1.3)
	_check("grip returns after leaving oil", items.cars[1].item_grip_multiplier == 1.0)
	await _fixture()
	items.cars[1].active_end = "B"
	items.held[1] = "rockets"
	items.tick(0.01)
	_check("CPU activates collected weapon under same rules", items.held[1].is_empty() and items.active[1] == "rockets")
	items._tick_active(1, 1.1)
	_check("CPU weapon also auto-fires", items.shots.size() >= 2)
	items.held[2] = "shield"
	items.tick(0.01)
	_check("CPU can activate defensive items", items.active[2] == "shield")
	items.cars[1].item_grip_multiplier = 0.35
	scene.cpu_drivers[0]._recover()
	_check("recovery cancels active weapon and restores grip", items.active[1].is_empty() and items.cars[1].item_grip_multiplier == 1.0 and items.protection[1] > 0.0)
	for projectile: Dictionary in items.shots:
		_check("recovery removes owner's shots", projectile["owner"] != 1)
	race.entrants[2]["finish_time"] = 12.0
	items.tick(0.01)
	_check("finish cancels active shield", items.active[2].is_empty() and not items._shields[2].visible)
	race.state = RaceDirector.State.RESULTS
	items.tick(0.01)
	_check("results clear all combat objects and grip effects", items.shots.is_empty() and items.hazards.is_empty()
		and items.effects.is_empty() and items.cars[0].item_grip_multiplier == 1.0 and not items.fire(0))
	scene.restart_race()
	_check("retry resets all item timers and inventory", race.state == RaceDirector.State.COUNTDOWN
		and items.held[0].is_empty() and items.active[0].is_empty() and items.remaining[0] == 0.0)
	items.setup(race, items.cars.duplicate())
	_check("repeat setup preserves racer array sizes", items.held.size() == 3 and items.active.size() == 3
		and items.oil_time.size() == 3 and items._shields.size() == 3)
	_check("repeat setup does not duplicate pickup rows", items.pickups.size() % 3 == 0 and items.pickups.size() < 40)
	if OS.get_cmdline_user_args().has("--capture-items"):
		await _capture()
	items.cars[0].item_grip_multiplier = RaceItems.OIL_GRIP
	scene.remove_child(items)
	_check("leaving item scene restores grip", scene.car.item_grip_multiplier == 1.0)
	items.free()
	scene.queue_free()


func _fixture() -> void:
	items.reset()
	race.state = RaceDirector.State.RACING
	for i in items.cars.size():
		var car := items.cars[i]
		car.global_position = Vector3(1100 + (50.0 if i == 2 else 0.0), 10, 1150.0 if i == 2 else 1100.0 - i * 20.0)
		car.global_basis = Basis.IDENTITY
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.active_end = "A"
		car.freeze = false
		items.previous_positions[i] = car.global_position
		race.entrants[i]["finish_time"] = -1.0
		var tracker: TrackProgress = race.entrants[i]["progress"]
		tracker.route_distance = float(i) * 20.0
	await get_tree().physics_frame


func _capture() -> void:
	race.state = RaceDirector.State.RACING
	var point: Dictionary = race.course.points[80]
	scene.car.global_position = point["pos"] + Vector3.UP * 1.4
	scene.car.global_basis = Basis(Vector3.UP, atan2(-Vector3(point["dir"]).x, -Vector3(point["dir"]).z))
	items.previous_positions[0] = scene.car.global_position
	items.held[0] = "shield"
	items.fire(0)
	scene.rig.reset_follow()
	for frame in 10:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../.ai/captures"))
	get_viewport().get_texture().get_image().save_png("res://../.ai/captures/timed-shield.png")
	for id: String in ["machine_guns", "rockets", "grenades", "smoke", "oil", "homing"]:
		items.reset_racer(0)
		items.held[0] = id
		if id == "homing":
			scene.cpu_cars[0].global_position = scene.car.global_position + items._fire_direction(0) * 30.0
			scene.cpu_cars[0].freeze = false
			await get_tree().physics_frame
		items.fire(0)
		items._tick_shots(0.06)
		for frame in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://../.ai/captures/timed-%s.png" % id)



func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
