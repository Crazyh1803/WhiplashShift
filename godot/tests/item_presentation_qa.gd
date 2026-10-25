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
		_equip(0, id)
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
		elif id == "oil":
			await _oil_views(camera)
	await _impact_views(camera)
	await _deployment_views(camera)
	for end in ["A", "B"]:
		for id in ["machine_guns", "rockets"]:
			scene.items.reset()
			scene.race.state = RaceDirector.State.RACING
			scene.car.active_end = end
			_equip(0, id)
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
	_check("industrial crate has no floating text", scene.items.pickups.all(func(pickup: Dictionary) -> bool: return pickup["visual"].find_children("*", "Label3D", true, false).is_empty()))
	_check("industrial crate screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join("industrial-crates.png")) == OK)
	var supply: Dictionary = scene.items.pickups[1]
	for fraction in [1.0, 0.5]:
		scene.items.art.update_supply(supply, fraction, 0.0)
		for frame in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check("non-text respawn charge screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join("crate-respawn-%d.png" % int(fraction * 100))) == OK)
	scene.items.art.update_supply(supply, 0.0, 0.0)
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
	await get_tree().create_timer(0.25).timeout
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
	var original_mask := camera.cull_mask
	camera.cull_mask = scene.rig.cam.cull_mask
	_check("owner stream is visible to the chase camera", (scene.items.art.streams[0]["smoke"].layers & camera.cull_mask) != 0)
	_check("rival stream stays visible to the chase camera", (scene.items.art.streams[1]["smoke"].layers & camera.cull_mask) != 0)
	for hazard: Dictionary in scene.items.hazards:
		hazard["visual"].hide()
	for pair: Dictionary in scene.items.art.streams:
		for emitter: CPUParticles3D in pair.values():
			emitter.hide()
	for end in ["A", "B"]:
		scene.car.active_end = end
		var rear := Vector3.BACK if end == "A" else Vector3.FORWARD
		camera.global_position = scene.car.global_position + rear * 9 + Vector3.UP * 4.2
		camera.look_at(scene.car.global_position + Vector3.UP * 0.75)
		for frame in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var baseline: Image = get_viewport().get_texture().get_image()
		var changes: Array[Vector2] = []
		for owner_index in [0, 1]:
			var cloud: Node3D = scene.items.art.hazard(scene.car.global_position + rear * 4 + Vector3.UP * 2, "smoke", Vector3.UP, owner_index)
			scene.items.art.tick(0.0)
			for frame in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var sample: Image = get_viewport().get_texture().get_image()
			var label := "smoke-owner-view-" if owner_index == 0 else "smoke-rival-view-"
			_check(label + end + " screenshot saves", sample.save_png(output.path_join(label + end + ".png")) == OK)
			changes.append(Vector2(_image_change(baseline, sample, Rect2i(480, 250, 320, 270)), _image_change(baseline, sample, Rect2i(80, 120, 1120, 520))))
			_check(label + end + " is actually rendered", cloud.get_children().any(func(puff: MeshInstance3D) -> bool: return (puff.layers & camera.cull_mask) != 0))
			cloud.queue_free()
			await get_tree().process_frame
		_check("owner plume stays visibly present on end " + end, changes[0].y > 0.005)
		_check("owner sightline stays clearer than dense rival smoke on end " + end, changes[1].x > 0.02 and changes[0].x < changes[1].x * 0.8)
	for hazard: Dictionary in scene.items.hazards:
		hazard["visual"].show()
	for pair: Dictionary in scene.items.art.streams:
		for emitter: CPUParticles3D in pair.values():
			emitter.show()
	scene.car.active_end = "A"
	scene.items.art.sync_streams(scene.items.cars, scene.items.active)
	camera.global_position = scene.car.global_position + Vector3(7, 3.5, 8)
	camera.look_at(scene.car.global_position + Vector3.BACK * 4)
	for frame in 12:
		scene.items.art.tick(0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check("full smoke spray screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join("smoke-full-spray.png")) == OK)
	camera.cull_mask = original_mask


func _image_change(a: Image, b: Image, rect: Rect2i) -> float:
	rect = rect.intersection(Rect2i(Vector2i.ZERO, a.get_size())).intersection(Rect2i(Vector2i.ZERO, b.get_size()))
	var total := 0.0
	var count := 0
	for y in range(rect.position.y, rect.end.y, 8):
		for x in range(rect.position.x, rect.end.x, 8):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			count += 1
	return total / maxf(1, count)


func _impact_views(camera: Camera3D) -> void:
	var original_fov := camera.fov
	scene.items.reset()
	scene.race.state = RaceDirector.State.RACING
	var pos: Vector3 = scene.car.global_position + Vector3(0, -0.85, -7)
	camera.fov = 60
	for id in ["machine_guns", "rockets"]:
		scene.items.art.clear()
		camera.global_position = pos + Vector3(5.5, 3, 7)
		camera.look_at(pos + Vector3.UP * 0.5)
		scene.items._impact({"id": id, "owner": 0}, pos, Vector3.UP, null)
		var elapsed := 0.0
		for age in [0.025, 0.12, 0.5]:
			scene.items.art.tick(age - elapsed)
			elapsed = age
			for frame in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_check(id + " impact sequence screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join("impact-%s-%03d.png" % [id, int(age * 1000)])) == OK)
	scene.items.art.clear()
	camera.fov = original_fov


func _oil_views(camera: Camera3D) -> void:
	var old_fov := camera.fov
	camera.fov = 52
	var oil: Array = scene.items.hazards.filter(func(hazard: Dictionary) -> bool: return hazard["id"] == "oil")
	_check("glancing views have an oil hazard", not oil.is_empty())
	if oil.is_empty():
		camera.fov = old_fov
		return
	var target: Vector3 = oil[int(oil.size() / 2)]["pos"]
	var offsets: Array[Vector3] = [Vector3(3.8, 1.3, 4.7), Vector3(-3.8, 1.5, -4.7)]
	for angle in offsets.size():
		camera.global_position = target + offsets[angle]
		camera.look_at(target)
		_check("oil surface is inside the glancing view", camera.is_position_in_frustum(target))
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		_check("viscous oil glancing view screenshot saves", get_viewport().get_texture().get_image().save_png(output.path_join("oil-close-%d.png" % angle)) == OK)
	camera.fov = old_fov


func _equip(index: int, id: String) -> void:
	scene.items.grant_item(index, id)
	ItemWeaponMounts.tick(scene.items._gun_mounts[index], 2.0)


func _deployment_views(camera: Camera3D) -> void:
	var old_fov := camera.fov
	var body_states: Array[Dictionary] = []
	for car: Vehicle in scene.items.cars:
		body_states.append({"car": car, "freeze": car.freeze, "gravity": car.gravity_scale})
	camera.fov = 52
	scene.items.reset()
	scene.race.state = RaceDirector.State.RACING
	scene.car.active_end = "A"
	for car: Vehicle in scene.items.cars:
		car.freeze = false
		car.gravity_scale = 0
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
	camera.global_position = scene.car.global_position + Vector3(6, 3.5, 3)
	camera.look_at(scene.car.global_position + Vector3.UP * 0.2)
	var frames_dir := output.path_join("deployment-frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	for frame in 120:
		if frame == 0:
			scene.items.grant_item(0, "machine_guns")
			scene.items.ammo[0] = 3
			_check("deployment accepts one buffered trigger", scene.items.fire(0) and scene.items.shots.is_empty() and scene.items.ammo[0] == 3)
		elif frame == 42:
			scene.items.grant_item(0, "rockets")
		elif frame == 66:
			scene.car.active_end = "B"
		elif frame == 96:
			scene.items.ammo[0] = 1
			_check("deployed opposite-end launcher fires its last round", scene.items.fire(0))
		scene.items._tick_mounts(0, 1.0 / 30.0)
		scene.items._tick_weapon(0, 1.0 / 30.0)
		scene.items._tick_shots(1.0 / 30.0)
		scene.items.art.tick(1.0 / 30.0)
		var shown: String = "machine_guns" if scene.items.burst_left[0] > 0 else scene.items.held[0]
		ItemWeaponMounts.show_weapon(scene.items._gun_mounts[0], scene.car.active_end, shown)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var result := get_viewport().get_texture().get_image().save_png(frames_dir.path_join("frame-%04d.png" % frame))
		if result != OK:
			_check("deployment frame saves", false)
	_check("empty weapon rigs finish retracting", not scene.items._gun_mounts[0]["A"].visible and not scene.items._gun_mounts[0]["B"].visible)
	for state: Dictionary in body_states:
		state["car"].freeze = state["freeze"]
		state["car"].gravity_scale = state["gravity"]
	camera.fov = old_fov
