extends Node3D

const EXPECTED_CAPTURES := 17

var _failures: Array[String] = []
var _captured := 0

func _ready() -> void:
	var capturing := "--capture" in OS.get_cmdline_user_args()
	var course := BlockCircuitData.build_course()
	var env := WorldEnvironment.new()
	env.environment = TrackMaterials.environment()
	add_child(env)
	TrackBuilder.build(self, course.points)
	TrackBuilder.build_guard_rails(self, course.points)
	TrackScenery.build_guidance(self, course)
	var city := CityScenery.build(self, course)
	var converted := city.get_node_or_null("CityRealism")
	if converted == null:
		push_error("Converted city unavailable: " + CityRealismCatalog.error)
		get_tree().quit(1)
		return
	var families := {}
	var roles := {}
	var reasons := {}
	for p: Dictionary in converted.get_meta("placements"):
		families[p["id"]] = int(families.get(p["id"], 0)) + 1
		roles[p["role"]] = int(roles.get(p["role"], 0)) + 1
	for p: Dictionary in converted.get_meta("rejected_slots"):
		reasons[p["reason"]] = int(reasons.get(p["reason"], 0)) + 1
	print("CITY_REALISM_COUNTS ", families, " roles=", roles, " rejected=", reasons, " tris=", converted.get_meta("triangle_count"), " quarters=", converted.get_meta("quarter_triangles"))
	var camera := Camera3D.new()
	camera.fov = 70
	camera.far = 2500
	add_child(camera)
	camera.current = true
	var headlight := OmniLight3D.new()
	headlight.light_energy = 2.0
	headlight.omni_range = 45.0
	camera.add_child(headlight)
	var lights: CityRealismLighting = converted.get_node("LocalLighting")
	var peak_tris := 0
	var peak_surfaces := 0
	for s in range(0, int(course.total_length), 10):
		var eye: Vector3 = CityDistrict.sample(course, s)["pos"] + Vector3.UP * 1.5
		var tris := 0
		var surfaces := 0
		for instance: MultiMeshInstance3D in converted.find_children("*", "MultiMeshInstance3D", true, false):
			var distance := eye.distance_to(instance.global_transform * instance.get_aabb().get_center())
			if distance > instance.visibility_range_end + 10 or distance < instance.visibility_range_begin - 10:
				continue
			tris += IndustrialMarketBenchmark.count_triangles(instance.multimesh.mesh) * instance.multimesh.instance_count
			surfaces += instance.multimesh.mesh.get_surface_count()
		peak_tris = maxi(peak_tris, tris)
		peak_surfaces = maxi(peak_surfaces, surfaces)
	print("CITY_RENDER_WINDOW peak_triangles=", peak_tris, " peak_surfaces=", peak_surfaces)
	_check(peak_tris > 0 and peak_tris <= CityRealismLayout.NEAR_BUDGET, "peak window triangles %d within %d" % [peak_tris, CityRealismLayout.NEAR_BUDGET])
	_check(peak_surfaces > 0 and peak_surfaces <= CityRealismLayout.SURFACE_BUDGET, "peak window surfaces %d within %d" % [peak_surfaces, CityRealismLayout.SURFACE_BUDGET])
	_check(converted.get_meta("triangle_count") <= CityRealismLayout.GLOBAL_BUDGET, "global triangles within budget")
	_check(converted.get_meta("actor_pairs") == 2, "two shop actor pairs")
	_check(not "--selftest-fail" in OS.get_cmdline_user_args(), "requested self-test failure")
	for count: int in converted.get_meta("quarter_triangles"):
		_check(count <= CityRealismLayout.QUARTER_BUDGET, "quarter triangles %d within %d" % [count, CityRealismLayout.QUARTER_BUDGET])
	var path := ProjectSettings.globalize_path("res://../assets/previews/city_realism/in_game")
	if capturing:
		DirAccess.make_dir_recursive_absolute(path)
	for quarter in 4:
		for view in 2:
			var s := course.total_length * (quarter + (0.17 if view == 0 else 0.65)) / 4.0
			var at := CityDistrict.sample(course, s)
			camera.position = at["pos"] + Vector3.UP * 1.5
			camera.look_at((at["pos"] as Vector3) + (at["dir"] as Vector3) * 85 + Vector3.UP * 2.5)
			lights._refresh(camera.position)
			if capturing:
				await _capture(path.path_join("quarter-%d-driver-%d.png" % [quarter + 1, view + 1]))
		if capturing:
			for placement: Dictionary in converted.get_meta("placements"):
				if placement["quarter"] == quarter and placement["role"] == "building":
					var xf: Transform3D = placement["transform"]
					camera.position = xf * Vector3(-12, 2.5, -20)
					camera.look_at(xf * Vector3(0, 3.5, 1))
					lights._refresh(camera.position)
					await _capture(path.path_join("quarter-%d-sidewalk-night.png" % (quarter + 1)))
					break
	if capturing:
		_check(converted.has_node("ShopLife0"), "ShopLife0 exists for the hand-off capture")
	if capturing and converted.has_node("ShopLife0"):
		var xf: Transform3D = (converted.get_node("ShopLife0") as Node3D).global_transform
		camera.position = xf * Vector3(-0.5, 1.8, -4.5)
		camera.look_at(xf * Vector3(1.35, 1.6, 0.2))
		lights._refresh(camera.position)
		await _capture(path.path_join("ramen-handoff-night.png"))
	if capturing:
		var sunlight := DirectionalLight3D.new()
		sunlight.rotation_degrees = Vector3(-50, -25, 0)
		sunlight.light_energy = 0.8
		add_child(sunlight)
		env.environment.fog_enabled = false
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.65, 0.7, 0.8)
		env.environment.ambient_light_energy = 0.5
		for quarter in 4:
			for p: Dictionary in converted.get_meta("placements"):
				if p["quarter"] == quarter and p["role"] == "building":
					var xf: Transform3D = p["transform"]
					camera.position = xf * Vector3(-12, 3, -20)
					camera.look_at(xf * Vector3(0, 4, 1))
					await _capture(path.path_join("quarter-%d-sidewalk-neutral.png" % (quarter + 1)))
					break
		_check(_captured == EXPECTED_CAPTURES, "captured %d of %d expected images" % [_captured, EXPECTED_CAPTURES])
	city.queue_free()
	for i in 4:
		await get_tree().process_frame
	print("CITY_REALISM_QA: %d failures" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
		push_error("CITY_REALISM_QA FAIL: " + label)

func _capture(path: String) -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(path)
	print("CITY_CAPTURE ", path, " result=", result)
	_check(result == OK and FileAccess.file_exists(path), "capture saved: " + path)
	# A blank or single-colour frame means the view never rendered the city.
	var darkest := 1.0
	var brightest := 0.0
	for y in range(0, image.get_height(), 16):
		for x in range(0, image.get_width(), 16):
			var luminance := image.get_pixel(x, y).get_luminance()
			darkest = minf(darkest, luminance)
			brightest = maxf(brightest, luminance)
	_check(image.get_width() > 0 and brightest - darkest > 0.02, "capture has visible content: " + path)
	_captured += 1
