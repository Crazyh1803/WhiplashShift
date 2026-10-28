extends Node3D

var _camera: Camera3D
var _directory := ""
var _fail := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("City kit visual QA requires the rendering device")
		get_tree().quit(1)
		return
	_directory = ProjectSettings.globalize_path("res://").path_join("../.ai/captures/city-kit").simplify_path()
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		get_tree().quit(1)
		return
	var environment := WorldEnvironment.new()
	environment.environment = TrackMaterials.environment()
	add_child(environment)
	_camera = Camera3D.new()
	_camera.far = 2500.0
	_camera.fov = 70.0
	add_child(_camera)
	_camera.current = true
	var headlight := OmniLight3D.new()
	headlight.light_energy = 2.0
	headlight.omni_range = 45.0
	_camera.add_child(headlight)
	await _gallery(environment)
	var course := BlockCircuitData.build_course().geometry()
	var world := Node3D.new()
	add_child(world)
	TrackBuilder.build(world, course.points)
	TrackBuilder.build_guard_rails(world, course.points)
	TrackScenery.build_guidance(world, course)
	var city := CityScenery.build(world, course)
	var district := city.get_node("CityKit")
	for placement: Dictionary in district.get_meta("placements", []):
		print("CITY_KIT_PLACED %s s=%.1f side=%.0f" % [placement["asset"], placement["s"], placement["side"]])
	var rejected: Dictionary = {}
	for slot: Dictionary in district.get_meta("rejected_slots", []):
		rejected[slot["reason"]] = int(rejected.get(slot["reason"], 0)) + 1
	print("CITY_KIT_REJECTED ", rejected)
	print("CITY_KIT_TRIANGLES ", district.get_meta("triangle_count"))
	for distance: float in [0.0, 100.0, 220.0, 320.0, 410.0, 500.0, 560.0]:
		for reverse: bool in [false, true]:
			var at := CityDistrict.sample(course, maxf(distance, 1.0))
			var target := CityDistrict.sample(course, clampf(distance + (-55.0 if reverse else 55.0), 0.0, course.total_length - 1.0))
			_camera.position = at["pos"] + Vector3.UP * 1.6
			_camera.look_at(target["pos"] + Vector3.UP * 1.4, Vector3.UP)
			await _capture("route-%03d-%s" % [int(distance), "reverse" if reverse else "forward"])
	for placement: Dictionary in district.get_meta("placements", []):
		if not placement["asset"] in ["relay_tower", "exchange_hall", "pump_citadel"]:
			continue
		var box: AABB = placement["bounds"]
		var xf: Transform3D = placement["transform"]
		_camera.position = box.get_center() + xf.basis * Vector3(box.size.length() * 0.5, box.size.y * 0.2, -box.size.length() * 0.8)
		_camera.look_at(box.get_center(), Vector3.UP)
		await _capture("in-world-" + String(placement["asset"]))
	world.free()
	environment.free()
	_camera.current = false
	await _gameplay()
	print("CITY_KIT_VISUAL_QA failures=%d" % _fail)
	get_tree().quit(1 if _fail else 0)


func _gallery(environment: WorldEnvironment) -> void:
	var studio := TrackMaterials.environment()
	studio.fog_enabled = false
	studio.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	studio.ambient_light_color = Color("a0aabd")
	studio.ambient_light_energy = 0.5
	environment.environment = studio
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	key.light_energy = 0.8
	add_child(key)
	print("QA_STUDIO gallery uses neutral inspection lighting; route captures use game lighting")
	for id: String in CityKit.EXPECTED_IDS:
		var mesh := CityKit.mesh(id)
		if mesh == null:
			_fail += 1
			continue
		var model := MeshInstance3D.new()
		model.mesh = mesh
		add_child(model)
		var box := CityKit.bounds(id)
		var radius := box.size.length() * 0.5
		for reverse: bool in [false, true]:
			var side := -1.0 if reverse else 1.0
			_camera.position = box.get_center() + Vector3(0.65 * side, 0.35, -1.0 * side).normalized() * radius * 2.7
			_camera.look_at(box.get_center(), Vector3.UP)
			await _capture("gallery-%s-%s" % [id, "back" if reverse else "front"])
		model.free()
	key.free()
	environment.environment = TrackMaterials.environment()


func _capture(label: String) -> void:
	for frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _directory.path_join(label + ".png")
	if get_viewport().get_texture().get_image().save_png(path) != OK:
		_fail += 1
	print("CITY_KIT_CAPTURE ", path)


func _gameplay() -> void:
	GameSession.set_course("block_circuit")
	GameSession.configure("SCENERY REVIEW", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	for frame in 30:
		await get_tree().physics_frame
	scene.set_physics_process(false)
	for car: Vehicle in [scene.car, scene.cpu_cars[0], scene.cpu_cars[1]]:
		car.freeze = true
	for driver: CpuDriver in scene.cpu_drivers:
		driver.enabled = false
	await _capture("gameplay-grid")
	scene.queue_free()
	for frame in 4:
		await get_tree().process_frame
