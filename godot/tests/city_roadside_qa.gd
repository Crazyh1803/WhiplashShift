## Roadside QA: builds the converted city, plans the camera views (CityRoadsideViews) and, only with --capture, renders each one to
## assets/previews/city_roadside/<name>.png (needs a real display, e.g. Vulkan). Without --capture it checks the plan headless and writes nothing.
## `--only=<kind>` limits captures to one view kind, `--selftest-fail` proves the exit-code contract.
extends Node3D

const Probe := preload("res://tests/city_roadside_probe.gd")
## Smallest share of the frame each subject kind's isolated render must cover.
const MIN_COVERAGE := {"tower": 0.02, "podium": 0.02, "landmark": 0.01, "landmark_detail": 0.01, "boards": 0.002, "camp": 0.003, "barrel": 0.001, "driver": 0.0005}

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
			var image := await _capture(path.path_join(String(view["name"]) + ".png"))
			await _check_subject(roadside, view, image)
		for id in CityRoadsideCatalog.TOWERS:
			var entry: Dictionary = CityRoadsideCatalog.entries[id]
			var problems := await Probe.rendered_aperture_problems(self, CityRoadsideCatalog.meshes[id], entry["apertures"], entry["masonry"])
			for problem in problems:
				print("  RENDERED APERTURE: ", id, " ", problem)
			_check(problems.is_empty(), "%s material-ID pixels at its recessed openings are glass/doors/shutters (%d problems)" % [id, problems.size()])
	var report := "CITY_ROADSIDE_QA: %d failures" % _failures.size()
	print(report)
	for failure in _failures:
		print("  FAIL ", failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


## Isolated subject readback: only copies of the roadside nodes overlapping the view's subject are drawn from the view's camera against black. The subject
## must cover real pixels with real (non-black) shading, and the same pixels in the full-scene capture must not be black (a missing draw) either.
func _check_subject(roadside: Node3D, view: Dictionary, scene_image: Image) -> void:
	var subject := await Probe.render_subject(self, roadside, view)
	var kind := String(view["kind"])
	var name := String(view["name"])
	if kind == "driver" and int(subject["copies"]) == 0:
		return
	var floor_coverage: float = MIN_COVERAGE.get(kind, 0.002)
	print("CITY_ROADSIDE_SUBJECT %s copies=%d coverage=%.4f mean=%.3f" % [name, subject["copies"], subject["coverage"], subject["mean"]])
	_check(int(subject["copies"]) > 0 and float(subject["coverage"]) >= floor_coverage, "%s isolated subject covers %.3f%% of the frame (needs %.3f%%)" % [name, float(subject["coverage"]) * 100.0, floor_coverage * 100.0])
	_check(float(subject["mean"]) >= 0.03, "%s isolated subject is shaded, not black (mean luminance %.3f)" % [name, subject["mean"]])
	var mask: Image = subject["image"]
	var scale := Vector2(float(scene_image.get_width()) / mask.get_width(), float(scene_image.get_height()) / mask.get_height())
	var samples := 0
	var dark := 0
	for y in range(0, mask.get_height(), 3):
		for x in range(0, mask.get_width(), 3):
			if mask.get_pixel(x, y).get_luminance() > 0.012:
				samples += 1
				if scene_image.get_pixel(mini(int(x * scale.x), scene_image.get_width() - 1), mini(int(y * scale.y), scene_image.get_height() - 1)).get_luminance() < 0.01:
					dark += 1
	_check(samples == 0 or float(dark) / float(samples) < 0.35, "%s subject pixels are drawn in the scene capture (%d of %d black)" % [name, dark, samples])


func _capture(file: String) -> Image:
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
	return image


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
