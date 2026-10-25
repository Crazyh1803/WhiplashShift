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
	items.grant_item(0, "rockets")
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
	_check("collected crate hides its model but retains respawn pad", not pickup["model"].visible and pickup["visual"].visible)
	items._collect(0.01)
	_check("empty crate shows a respawn countdown", String(pickup["label"].text).begins_with("RESPAWN"))
	var second: Dictionary = items.pickups[1]
	items.cars[0].global_position = second["pos"]
	items.previous_positions[0] = second["pos"]
	items.tick(0.01)
	_check("held slot leaves other pickups untouched", float(second["cooldown"]) == 0.0)
	items.grant_item(0, "machine_guns")
	_check("gun crate grants thirty rounds", items.ammo[0] == 30)
	_check("E spends three rounds and starts one burst", items.fire(0) and items.ammo[0] == 27 and items.shots.size() == 1 and items.active[0].is_empty())
	scene.hud._process(0.0)
	_check("HUD shows remaining rounds and the per-press burst action", scene.hud._item_status.text.contains("27 LEFT") and scene.hud._item_status.text.contains("3-ROUND BURST"))
	items._collect(0.01)
	_check("loaded weapon prevents inventory stacking", items.held[0] == "machine_guns" and float(second["cooldown"]) == 0.0)
	_check("pressing during a burst cannot spend more ammo", not items.fire(0) and items.ammo[0] == 27)
	items._tick_weapon(0, 0.064)
	_check("burst rounds are spaced rather than simultaneous", items.shots.size() == 1)
	_check("gun tracer originates at its barrel rather than the car center", Vector3(items.shots[0].pos).distance_to(items.cars[0].global_position) > items.cars[0].tuning.body_length * 0.45)
	items._tick_weapon(0, 0.002)
	items._tick_weapon(0, 0.065)
	_check("one press releases exactly three bullets", items.shots.size() == 3 and items.ammo[0] == 27)
	items._tick_weapon(0, 20.0)
	_check("waiting never auto-fires or expires ammunition", items.shots.size() == 3 and items.ammo[0] == 27 and items.held[0] == "machine_guns")
	for i in range(9):
		items.fire(0)
		items._tick_weapon(0, 0.3)
	_check("ten presses exhaust thirty rounds with no free final burst", items.ammo[0] == 0 and items.shots.size() == 30 and items.held[0].is_empty() and not items.fire(0))
	for id: String in ["rockets", "grenades"]:
		await _fixture()
		items.grant_item(0, id)
		var count := items.ammo[0]
		items.fire(0)
		_check(id + " press spends exactly one shot", items.ammo[0] == count - 1 and items.shots.size() == 1)
		_check(id + " rapid press respects cooldown without spending", not items.fire(0) and items.ammo[0] == count - 1)
		items._tick_active(0, 20.0)
		_check(id + " do not auto-fire or expire", items.shots.size() == 1 and items.held[0] == id)
		if id == "grenades":
			_check("grenades launch in an arc", Vector3(items.shots[0]["velocity"]).y > 0.0)
		for i in range(count - 1):
			items._tick_weapon(0, 1.0)
			items.fire(0)
		_check(id + " crate has a finite count", items.shots.size() == count and items.ammo[0] == 0 and items.held[0].is_empty())
	await _fixture()
	items.grant_item(0, "rockets")
	items.fire(0)
	items.cars[1].linear_velocity = Vector3(0, 0, -20)
	await get_tree().physics_frame
	items._tick_shots(0.3)
	_check("swept rockets hit between ticks", items.shots.is_empty() and items.protection[1] > 0.0)
	await get_tree().physics_frame
	_check("weapon hit reduces real speed", items.cars[1].linear_velocity.length() < 18.0 and items.cars[1].linear_velocity.length() > 10.0)
	items.cars[0].active_end = "B"
	items.reset_racer(0)
	items.grant_item(0, "rockets")
	items.fire(0)
	_check("swap redirects the next shot to active end", Vector3(items.shots[0]["velocity"]).z > 0.0)
	await _fixture()
	items.grant_item(1, "shield")
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
	items.grant_item(0, "machine_guns")
	var echo := InputEventKey.new()
	echo.keycode = KEY_E
	echo.pressed = true
	echo.echo = true
	scene._unhandled_key_input(echo)
	_check("holding E keyboard repeat does not spend ammo", items.ammo[0] == 30 and items.shots.is_empty())
	items.fire(0)
	items.reset_racer(0)
	items._tick_weapon(0, 1.0)
	_check("recovery cancels pending burst rounds and ammunition", items.shots.is_empty() and items.ammo[0] == 0 and items.burst_left[0] == 0)
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
	wall.position = Vector3(1100, 10, 1098)
	await get_tree().physics_frame
	items.grant_item(0, "machine_guns")
	items.fire(0)
	_check("barrel relocation cannot spawn a tracer through a nearby wall", items.shots.is_empty())
	items.reset_racer(0)
	wall.position.z = 1083
	await get_tree().physics_frame
	items.grant_item(0, "rockets")
	items.fire(0)
	items._tick_shots(0.3)
	_check("wall blocks projectiles and splash", items.shots.is_empty() and items.protection[1] == 0.0 and items._target(0) < 0)
	wall.queue_free()
	await _fixture()
	items.grant_item(0, "grenades")
	items.fire(0)
	var shot := items.shots[0]
	items._impact(shot, items.cars[1].global_position + Vector3.RIGHT * 4.0, Vector3.UP, null)
	_check("grenade blast hits nearby car without direct collision", items.protection[1] > 0.0)
	await _fixture()
	items.grant_item(0, "homing")
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
	items.grant_item(0, "homing")
	_check("no lock preserves rare missile", not items.fire(0) and items.held[0] == "homing")
	await _fixture()
	items.grant_item(0, "smoke")
	items.fire(0)
	_check("smoke deploys behind the active end", items.hazards.size() == 1 and Vector3(items.hazards[0]["pos"]).z > items.cars[0].global_position.z)
	items._tick_active(0, 1.01)
	_check("stationary smoke stays continuous without stacking duplicate hazards", items.hazards.size() == 1)
	items.cars[0].global_position.x += 3.1
	items._tick_active(0, 0.01)
	_check("moving smoke leaves overlapping deposits", items.hazards.size() == 2 and Vector3(items.hazards[0].pos).distance_to(items.hazards[1].pos) < 10.0)
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
	items.grant_item(0, "oil")
	items.fire(0)
	_check("oil creates a road patch", items.hazards.size() == 1 and items.hazards[0]["id"] == "oil")
	var oil: Vector3 = items.hazards[0]["pos"]
	items.cars[1].global_position = oil + Vector3.UP * 1.5
	items.previous_positions[1] = items.cars[1].global_position
	items.tick(0.01)
	_check("oil reduces grip temporarily", items.oil_time[1] > 0.0 and items.cars[1].item_grip_multiplier == RaceItems.OIL_GRIP)
	items.grant_item(1, "shield")
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
	items.grant_item(1, "rockets")
	items._cpu_wait[1] = 0
	items.tick(0.01)
	_check("CPU fires one round under the same ammo rules", items.held[1] == "rockets" and items.ammo[1] == 3 and items.active[1].is_empty())
	items._tick_weapon(1, 0.6)
	items._cpu_wait[1] = 0
	items.tick(0.01)
	_check("CPU subsequent trigger also spends one round", items.ammo[1] == 2)
	items.grant_item(2, "shield")
	items._cpu_wait[2] = 0
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
	for i in range(12):
		items.art.burst(Vector3.ZERO, Color.ORANGE, 12, true)
	_check("race explosions use bounded textured effects", items.art.particles.size() <= 240 and not items.art.particles.is_empty())
	for i in range(300):
		items.art.tick(1.0 / 60.0)
	_check("race smoke and explosion effects expire", items.art.particles.is_empty())
	items.art.muzzle(Vector3.ZERO, false)
	race.state = RaceDirector.State.RESULTS
	items.tick(0.01)
	_check("results clear all combat objects and grip effects", items.shots.is_empty() and items.hazards.is_empty()
		and items.effects.is_empty() and items.art.particles.is_empty() and items.cars[0].item_grip_multiplier == 1.0 and not items.fire(0))
	scene.restart_race()
	_check("retry resets all item timers and inventory", race.state == RaceDirector.State.COUNTDOWN
		and items.held[0].is_empty() and items.active[0].is_empty() and items.remaining[0] == 0.0)
	items.setup(race, items.cars.duplicate())
	_check("repeat setup preserves racer array sizes", items.held.size() == 3 and items.active.size() == 3
		and items.oil_time.size() == 3 and items._shields.size() == 3)
	_check("repeat setup does not duplicate pickup rows", items.pickups.size() % 3 == 0 and items.pickups.size() < 40)
	await _test_crate_pool()
	await _test_streams()
	await _test_presentation()
	if OS.get_cmdline_user_args().has("--capture-items"):
		await _capture()
	items.cars[0].item_grip_multiplier = RaceItems.OIL_GRIP
	scene.remove_child(items)
	_check("leaving item scene restores grip", scene.car.item_grip_multiplier == 1.0)
	items.free()
	scene.queue_free()


func _test_crate_pool() -> void:
	await _fixture()
	for lane in range(3):
		var pickup: Dictionary = items.pickups[lane]
		for id: String in ItemCatalog.IDS:
			var seed_value := 0
			var trial := RandomNumberGenerator.new()
			while true:
				trial.seed = seed_value
				if ItemCatalog.roll(trial.randf()) == id:
					break
				seed_value += 1
			items.rng.seed = seed_value
			items._roll_pickup(pickup)
			_check("lane %d conceals %s before collection" % [lane + 1, id], pickup.label.text == "MYSTERY ITEM" and pickup.icon.text == "?" and pickup.label.modulate == Color("ffe49b") and pickup.icon.modulate == Color("ffe49b"))
			items.held[0] = ""
			items.ammo[0] = 0
			items.active[0] = ""
			pickup.cooldown = 0
			items.cars[0].global_position = pickup.pos
			items.previous_positions[0] = pickup.pos
			items._collect(0.001)
			_check("lane %d reveals %s and its quantity only on collection" % [lane + 1, id], items.held[0] == id and items.ammo[0] == int(ItemCatalog.DATA[id].get("ammo", 0)) and items.feedback.contains(ItemCatalog.supply_label(id)))
			items._collect(6.1)
			_check("lane %d respawn rerolls while keeping contents concealed" % [lane + 1], ItemCatalog.IDS.has(pickup.item) and pickup.label.text == "MYSTERY ITEM" and pickup.icon.text == "?")


func _test_streams() -> void:
	for id in ["smoke", "oil"]:
		await _fixture()
		items.grant_item(0, id)
		items.fire(0)
		items.art.sync_streams(items.cars, items.active)
		_check(id + " emitter produces a continuous stream", items.art.streams[0][id].emitting and items.art.streams[0][id].explosiveness == 0)
		for i in range(12):
			items.cars[0].global_position.x += 1.0
			items._tick_active(0, 0.02)
		var connected := items.hazards.size() > 1
		for i in range(1, items.hazards.size()):
			connected = connected and Vector3(items.hazards[i - 1].pos).distance_to(items.hazards[i].pos) < float(items.hazards[i].radius) * 2
		_check(id + " deposits have no gaps at driving speed", connected)
		items._tick_active(0, 6.0)
		_check(id + " expiry stops the stream", not items.art.streams[0][id].emitting and items.active[0].is_empty())


func _test_presentation() -> void:
	var heard := {}
	items.audio.cue.connect(func(id: String) -> void: heard[id] = int(heard.get(id, 0)) + 1)
	for id: String in ItemAudio.DURATIONS:
		var wav := ItemAudio.make_sound(id)
		var peak := 0
		for i in range(0, wav.data.size(), 62):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		_check(id + " audio has non-silent bounded PCM", wav.mix_rate == 22050 and peak > 500 and peak <= 29492)
	var pickup_sound := ItemAudio.make_sound("pickup")
	var stereo_difference := 0.0
	var mono_energy := 0.0
	for offset in range(0, pickup_sound.data.size(), 4):
		var left := float(pickup_sound.data.decode_s16(offset)) / 32768.0
		var right := float(pickup_sound.data.decode_s16(offset + 2)) / 32768.0
		stereo_difference += absf(left - right)
		mono_energy += absf((left + right) * 0.5)
	_check("pickup has distinct stereo channels and remains audible in mono", pickup_sound.stereo and stereo_difference > 100.0 and mono_energy > 100.0)
	_check("pickup PCM contains complete stereo frames", pickup_sound.data.size() == int(float(ItemAudio.DURATIONS["pickup"]) * ItemAudio.RATE) * 4)
	for id in ["machine_guns", "rockets", "grenades", "homing"]:
		await _fixture()
		items.grant_item(0, id)
		_check(id + " activation triggers its distinct sound", items.fire(0) and heard.has(id))
	await _fixture()
	items.grant_item(0, "machine_guns")
	items.fire(0)
	_check("machine guns display the driving-end mount and a soft tracer", items._gun_mounts[0]["A"].visible
		and not items._gun_mounts[0]["B"].visible and items.shots[0].visual.get_child_count() == 3)
	items.cars[0].active_end = "B"
	items.tick(0.01)
	_check("swapping moves the visible gun mount to the active end", items._gun_mounts[0]["B"].visible and not items._gun_mounts[0]["A"].visible)
	items.reset_racer(0)
	_check("recovery hides both gun mounts", not items._gun_mounts[0]["A"].visible and not items._gun_mounts[0]["B"].visible)
	await _fixture()
	items.grant_item(0, "shield")
	items.fire(0)
	_check("shield activation has a shader and power-up sound", items._shields[0].visible and items._shields[0].material_override is ShaderMaterial and heard.has("shield_on"))
	items._apply_hit(0, 1, "rockets")
	_check("shield blocks trigger audio and a visible impact pulse", heard.has("shield_hit") and items._shields[0].get_meta("impact") == 1.0)
	items.art.update_shield(items._shields[0], items.cars[0].global_position, 0.2)
	_check("shield impact pulse decays", float(items._shields[0].get_meta("impact")) < 1.0)
	items._tick_active(0, 5.1)
	_check("shield expiry powers down with audio", heard.has("shield_off") and not items._shields[0].visible)
	for id in ["smoke", "oil"]:
		await _fixture()
		items.grant_item(0, id)
		items.fire(0)
		_check(id + " deploys a visual hazard and sound", items.hazards.size() == 1 and heard.has(id))
		var root: Node3D = items.hazards[0].visual
		if id == "smoke":
			_check("smoke screen uses textured billboards", root.get_child_count() >= 3 and root.get_child(0).mesh is QuadMesh)
		else:
			_check("oil uses a surface plane and iridescent material", root.get_child(0).mesh is PlaneMesh and root.get_child(0).material_override is ShaderMaterial)
		items.tick(0.01)
	await _fixture()
	items._apply_hit(1, 0, "rockets")
	_check("player hits have an audible confirmation", heard.has("hit"))
	items._emit(0, "rockets")
	items._impact(items.shots.back(), items.cars[0].global_position, Vector3.UP, null)
	_check("explosions trigger a blast sound", heard.has("explosion"))
	_check("shield and smoke sustain use looped audio", ItemAudio.make_sound("shield_hum").loop_mode == AudioStreamWAV.LOOP_FORWARD
		and ItemAudio.make_sound("smoke_loop").loop_mode == AudioStreamWAV.LOOP_FORWARD)
	items.reset()


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
	items.grant_item(0, "shield")
	items.fire(0)
	scene.rig.reset_follow()
	for frame in 10:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../.ai/captures"))
	get_viewport().get_texture().get_image().save_png("res://../.ai/captures/timed-shield.png")
	for id: String in ["machine_guns", "rockets", "grenades", "smoke", "oil", "homing"]:
		items.reset_racer(0)
		items.grant_item(0, id)
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
