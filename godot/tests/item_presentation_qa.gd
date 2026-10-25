## Rendered end-to-end checks: actual item activation, positional audio and material compilation.
extends Node

var _pass := 0
var _fail := 0
var scene: Node3D
var output := ProjectSettings.globalize_path("res://../.ai/captures/item-effects")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run item_presentation_qa with a rendering display and audio driver (Dummy is supported).")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output)
	var vehicle_id := "helix" if "--helix" in OS.get_cmdline_user_args() else "blackjack"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--vehicle="):
			vehicle_id = argument.trim_prefix("--vehicle=")
	output = output.path_join(vehicle_id)
	DirAccess.make_dir_recursive_absolute(output)
	GameSession.configure("ITEM FX QA", vehicle_id, ["ramjet", "boilerfang"])
	scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	scene.set_physics_process(false)
	scene.rig.set_process(false)
	scene.hud.hide()
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	var road := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(180, 2, 180)
	shape.shape = box
	road.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	floor_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("293843")
	floor_mesh.material_override = mat
	road.add_child(floor_mesh)
	add_child(road)
	road.position = Vector3(1100, 7, 1100)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.8
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	for id in ["shield", "smoke", "oil", "machine_guns", "rockets", "grenades", "homing"]:
		scene.items.reset()
		scene.race.state = RaceDirector.State.RACING
		for i in scene.items.cars.size():
			var car: Vehicle = scene.items.cars[i]
			car.freeze = false
			car.gravity_scale = 0
			car.global_position = Vector3(1100, 9.0, 1100 - i * 35)
			car.global_basis = Basis.IDENTITY
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car.active_end = "A"
			scene.items.previous_positions[i] = car.global_position
			scene.race.entrants[i]["finish_time"] = -1.0
			var progress: TrackProgress = scene.race.entrants[i]["progress"]
			progress.route_distance = i * 35
		await get_tree().physics_frame
		await get_tree().physics_frame
		scene.items.grant_item(0, id)
		_check(id + " activates through RaceItems.fire", scene.items.fire(0))
		_check(id + " starts a positional audio voice", scene.items.audio._voices.any(func(voice: AudioStreamPlayer3D) -> bool: return voice.playing))
		scene.items.audio.sync(scene.items.cars, scene.items.active)
		scene.items.art.sync_streams(scene.items.cars, scene.items.active)
		if id in ["shield", "smoke", "oil"]:
			_check(id + " sustain loop is playing", scene.items.audio._loops[0].playing)
		if id in ["machine_guns", "rockets", "homing", "grenades"]:
			scene.items._tick_shots(0.04)
		for car: Vehicle in scene.items.cars:
			car.freeze = true
		if id in ["smoke", "oil"]:
			for step in range(16):
				scene.car.global_position.z -= 0.7
				scene.items._tick_active(0, 0.03)
				scene.items.art.sync_streams(scene.items.cars, scene.items.active)
			_check(id + " continuous emitter is active", scene.items.art.streams[0][id].emitting)
			scene.car.reset_physics_interpolation()
		for hazard: Dictionary in scene.items.hazards:
			scene.items.art.animate_hazard(hazard)
		var target: Vector3 = scene.car.global_position
		if id in ["smoke", "oil"]:
			target = (Vector3(scene.items.hazards[0].pos) + Vector3(scene.items.hazards.back().pos)) * 0.5
		camera.global_position = target + Vector3(10, 7 if id == "oil" else 4.5, 12)
		camera.look_at(target + Vector3.UP * 0.5)
		for frame in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check(id + " screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join(id + ".png")) == OK)
		if id == "smoke":
			await _smoke_views(camera)
	for end in ["A", "B"]:
		for id in ["machine_guns", "rockets"]:
			scene.items.reset()
			scene.race.state = RaceDirector.State.RACING
			scene.car.active_end = end
			scene.items.grant_item(0, id)
			ItemWeaponMounts.show_weapon(scene.items._gun_mounts[0], end, id)
			camera.global_position = scene.car.global_position + Vector3(4.2, 2.6, -5.0 if end == "A" else 5.0)
			camera.look_at(scene.car.global_position + Vector3.UP * 0.2)
			camera.fov = 46
			for frame in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_check("attachment " + end + " " + id + " screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join("mount-" + end + "-" + id + ".png")) == OK)
	scene.items.reset()
	var left: Vector3 = scene.items.pickups[0].pos
	var center: Vector3 = scene.items.pickups[1].pos
	var right: Vector3 = scene.items.pickups[2].pos
	var forward := (right - left).normalized().cross(Vector3.UP)
	camera.global_position = center + forward * 12 + Vector3.UP * 4
	camera.look_at(center + Vector3.UP)
	for frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check("mystery crate screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join("mystery-crates.png")) == OK)
	_check("item bus has a limiter", AudioServer.get_bus_effect_count(AudioServer.get_bus_index("ItemFX")) == 1)
	for i in range(32):
		scene.items.audio.play("machine_guns", scene.car.global_position)
	_check("rapid effects respect voice limit", scene.items.audio._voices.size() <= ItemAudio.MAX_VOICES)
	scene.items.audio.play("pickup", scene.car.global_position)
	var pickup_voice: AudioStreamPlayer = scene.items.audio._pickup_voice
	_check("pickup plays its stereo stream without positional downmix", pickup_voice.playing and pickup_voice.stream.stereo and pickup_voice.bus == "ItemFX")
	scene.items.audio.play("pickup", scene.car.global_position)
	_check("repeat pickup reuses its bounded feedback voice", scene.items.audio._pickup_voice == pickup_voice)
	scene.items.audio.stop_all()
	_check("cleanup stops every one-shot and sustain loop", scene.items.audio._voices.all(func(v: AudioStreamPlayer3D) -> bool: return not v.playing)
		and not pickup_voice.playing
		and scene.items.audio._loops.values().all(func(v: AudioStreamPlayer3D) -> bool: return not v.playing))
	for id in ["pickup", "hit", "machine_guns", "impact", "explosion", "shield_hit", "smoke", "oil", "shield_on"]:
		ItemAudio.make_sound(id).save_to_wav(output.path_join(id + ".wav"))
	scene.queue_free()
	for frame in 3:
		await get_tree().process_frame
	print("ITEM PRESENTATION: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("PASS: " + label)
	else:
		_fail += 1
		push_error("FAIL: " + label)


func _smoke_views(camera: Camera3D) -> void:
	camera.cull_mask = scene.rig.cam.cull_mask
	camera.global_position = scene.car.global_position + Vector3(0, 4.2, 9)
	camera.look_at(scene.car.global_position + Vector3.UP * 0.75)
	for owner in [0, 1]:
		var cloud := scene.items.art.hazard(scene.car.global_position + Vector3(0, 2, 4), "smoke", Vector3.UP, owner)
		for frame in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var label := "smoke-owner-view" if owner == 0 else "smoke-rival-view"
		_check(label + " screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)
		cloud.queue_free()
		await get_tree().process_frame
	camera.cull_mask = (1 << 20) - 1
