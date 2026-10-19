extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	_check("render interpolation enabled without lowering physics rate", get_tree().physics_interpolation
		and Engine.physics_ticks_per_second == 120)
	GameSession.configure("CAMERA TEST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
		driver.target.freeze = true
	var car: Vehicle = scene.car
	var rig: CameraRig = scene.rig
	rig.set_process(false)
	car.freeze = true
	_check("frame-driven camera opts out of double interpolation",
		rig.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
		and not rig.cam.is_physics_interpolated())
	# Move the body on actual physics boundaries, then compare camera aim with
	# the engine's rendered pose rather than the newer raw physics position.
	var distinct_poses := false
	var aim_matches := true
	for tick in 24:
		await get_tree().physics_frame
		car.global_position += Vector3(0.5, 0.0, 0.0)
		await get_tree().process_frame
		var rendered := car.get_global_transform_interpolated()
		distinct_poses = distinct_poses or rendered.origin.distance_to(car.global_position) > 0.001
		rig._process(1.0 / 144.0)
		var expected := (rendered.origin + Vector3.UP * 0.75 - rig.cam.global_position).normalized()
		aim_matches = aim_matches and (-rig.cam.global_basis.z).dot(expected) > 0.99999
	_check("test exercises distinct physical and rendered poses", distinct_poses)
	_check("camera aim follows the rendered body", aim_matches)
	var basis_before := car.basis
	var velocity_before := car.linear_velocity
	car.swap_ends()
	for rate: float in [30.0, 60.0, 144.0]:
		for frame in int(rate):
			rig._process(1.0 / rate)
	_check("swap orbit remains finite and preserves body state", rig.global_transform.is_finite()
		and rig.cam.global_transform.is_finite() and car.basis == basis_before and car.linear_velocity == velocity_before)
	rig.toggle_mode()
	rig._process(1.0 / 60.0)
	var f := car.get_global_transform_interpolated().basis * Vector3.FORWARD * car.forward_sign()
	_check("snap mode follows the active end", absf(wrapf(rig._yaw - atan2(-f.x, -f.z), -PI, PI)) < 0.0001)
	var destination := Transform3D(Basis(Vector3.UP, 0.7), Vector3(-620.0, 1.4, 80.0))
	scene._place_player(destination, "A")
	_check("recovery snaps the camera instead of flying across the course", rig.global_position.distance_to(destination.origin) < 0.001)
	# Godot 4.7 caches rendered transforms. Observe the next display frame,
	# after its queued interpolation reset has been processed.
	await get_tree().process_frame
	var reset_pose := car.get_global_transform_interpolated()
	_check("player teleport clears old rendered pose", reset_pose.origin.distance_to(destination.origin) < 0.001)
	var driver: CpuDriver = scene.cpu_drivers[0]
	driver.target.get_global_transform_interpolated()
	driver.reset(80)
	await get_tree().process_frame
	var cpu_pose := driver.target.get_global_transform_interpolated()
	_check("CPU reset clears old rendered pose", cpu_pose.origin.distance_to(driver.target.global_position) < 0.001)
	scene.race.state = RaceDirector.State.RESULTS
	scene.restart_race()
	_check("retry snaps camera to the new grid", rig.global_position.distance_to(scene._spawn.origin) < 0.001)
	await get_tree().process_frame
	_check("retry renders at the new grid", car.get_global_transform_interpolated().origin.distance_to(scene._spawn.origin) < 0.02)
	scene.queue_free()
	await get_tree().process_frame
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	garage._open_customization()
	_check("garage turntable and orbit remain frame-driven", garage._preview_vehicle.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
		and garage._preview_camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF)
	garage.queue_free()
	await get_tree().process_frame
	print("CAMERA: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
