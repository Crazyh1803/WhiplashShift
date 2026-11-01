## Roadside QA: builds the converted city, plans the camera views (CityRoadsideViews) and, only with --capture, renders each one to
## assets/previews/city_roadside/<name>.png (needs a real display, e.g. Vulkan). Without --capture it checks the plan headless and writes nothing.
## `--only=<kind>` limits captures to one view kind, `--selftest-fail` proves the exit-code contract.
extends Node3D

var _failures: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var capturing := "--capture" in args
	var only := ""
	for arg in args:
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var course := BlockCircuitData.build_course()
	var env := WorldEnvironment.new()
	env.environment = TrackMaterials.environment()
	add_child(env)
	TrackBuilder.build(self, course.points)
	TrackBuilder.build_guard_rails(self, course.points)
	TrackScenery.build_guidance(self, course)
	var city := CityScenery.build(self, course)
	var roadside := city.get_node_or_null("CityRoadside") as Node3D
	if roadside == null:
		push_error("Roadside layer unavailable: " + CityRoadsideCatalog.error)
		get_tree().quit(1)
		return
	var views := CityRoadsideViews.plan(roadside, course)
	_check(views.size() >= 36, "view plan is complete (%d views)" % views.size())
	_check(not "--selftest-fail" in args, "requested self-test failure")
	for view in views:
		var subject: AABB = view["subject"]
		_check(CityRoadsideViews.frames(view, subject.get_center()), "%s frames its subject" % view["name"])
		var problem := CityRoadsideViews.subject_problem(roadside, view)
		_check(problem == "", "%s subject geometry is active at its eye: %s" % [view["name"], problem])
	var peaks := CityRoadside.measure(city, course)
	print("CITY_ROADSIDE_RENDER_WINDOW ", peaks)
	_check(peaks["addon_tris"] <= CityRoadside.ADDON_NEAR_BUDGET and peaks["addon_surfaces"] <= CityRoadside.ADDON_SURFACE_BUDGET, "add-on window within its caps")
	_check(peaks["base_tris"] <= CityRealismLayout.NEAR_BUDGET and peaks["base_surfaces"] <= CityRealismLayout.SURFACE_BUDGET, "base window within the unchanged caps")
	if capturing:
		var path := ProjectSettings.globalize_path("res://../assets/previews/city_roadside")
		DirAccess.make_dir_recursive_absolute(path)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -25, 0)
		sun.light_energy = 0.6
		add_child(sun)
		var camera := Camera3D.new()
		camera.far = 2500.0
		add_child(camera)
		camera.current = true
		var headlight := OmniLight3D.new()
		headlight.light_energy = 1.5
		headlight.omni_range = 40.0
		camera.add_child(headlight)
		var lights: CityRealismLighting = city.get_node("CityRealism/LocalLighting")
		for view in views:
			if only != "" and view["kind"] != only:
				continue
			camera.position = view["eye"]
			camera.fov = view["fov"]
			camera.look_at(view["target"])
			lights._refresh(camera.position)
			_check(CityRoadsideViews.subject_problem(roadside, view) == "", "%s subject geometry active in the capture" % view["name"])
			await _capture(path.path_join(String(view["name"]) + ".png"))
	var report := "CITY_ROADSIDE_QA: %d failures" % _failures.size()
	print(report)
	for failure in _failures:
		print("  FAIL ", failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _capture(file: String) -> void:
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var low := 1.0
	var high := 0.0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var v := image.get_pixel(x, y).get_luminance()
			low = minf(low, v)
			high = maxf(high, v)
	_check(high - low > 0.04, "%s is not a flat image" % file.get_file())
	image.save_png(file)
	print("CITY_ROADSIDE_CAPTURE ", file.get_file(), " ", image.get_size())


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
