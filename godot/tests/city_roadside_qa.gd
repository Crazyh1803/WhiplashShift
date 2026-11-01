## Roadside QA: builds the converted city, plans the camera views (CityRoadsideViews) and, only with --capture, renders each one to
## assets/previews/city_roadside/<name>.png (needs a real display, e.g. Vulkan). Without --capture it checks the plan headless and writes nothing.
## `--only=<kind>` limits captures to one view kind, `--selftest-fail` proves the exit-code contract.
extends Node3D

const Probe := preload("res://tests/city_roadside_probe.gd")
## Smallest share of the frame each subject kind's isolated render must cover.
const MIN_COVERAGE := {"tower": 0.02, "podium": 0.02, "landmark": 0.01, "landmark_detail": 0.01, "boards": 0.002, "camp": 0.003, "barrel": 0.001, "driver": 0.0005}

## With/without contribution: smallest number of changed pixels (inside the subject's projected box) between the real scene with and without the subject.
## The flame and above-barrel numbers are only taken inside the upper flame / drum-opening boxes, so the ground pool and smoke cannot satisfy them.
const MIN_CHANGED := {"tower": 15000, "podium": 40000, "landmark": 1500, "landmark_detail": 4000, "boards": 2000, "camp": 4000, "barrel": 4000, "flame": 400, "driver": 10000}
const CHANGE_THRESHOLD := 0.04
const NOISE_FACTOR := 3
const NODE_KINDS := {"tower": ["tower"], "podium": ["tower"], "landmark": ["landmark"], "landmark_detail": ["landmark"], "boards": ["boards"], "camp": ["camp"],
		"barrel": ["barrel"], "driver": ["tower", "tower_lod1", "landmark", "boards", "camp", "barrel"]}

var _failures: Array[String] = []
## `--selftest-hide=body|flame|subject`: the named subject is removed from the "with" render, so its with/without check must fail (the run then exits 1).
var _hide := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var capturing := "--capture" in args
	var only := ""
	for arg in args:
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		if arg.begins_with("--selftest-hide="):
			_hide = arg.trim_prefix("--selftest-hide=")
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
			await _check_contribution(roadside, view, camera)
		await _check_above_barrels(roadside, camera, lights)
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


## Real-scene comparison. A = scene as built, B = the same scene with the subject nodes hidden, A2 = A again (animation noise floor: flames and smoke are
## driven by shader TIME, which cannot be pinned, so the changed-pixel count must beat both a fixed minimum and NOISE_FACTOR x the A/A2 difference).
## Barrels get two checks: the drum body (fire left on) and the flame alone (fire hidden vs. a flame-surface-only copy, counted only above the drum rim).
func _check_contribution(roadside: Node3D, view: Dictionary, camera: Camera3D) -> void:
	var kind := String(view["kind"])
	var name := String(view["name"])
	var nodes: Array[MultiMeshInstance3D] = []
	for node in Probe.subject_nodes(roadside, view):
		if String(node.get_meta("roadside_kind", "")) in NODE_KINDS.get(kind, []):
			nodes.append(node)
	if nodes.is_empty():
		_check(kind == "driver", "%s has subject nodes to compare with and without" % name)
		return
	var box := (nodes[0].custom_aabb as AABB)
	for node in nodes:
		box = box.merge(node.custom_aabb)
	if _hide == "body" and kind == "barrel" or _hide == "subject":
		_show(nodes, false)
	var with_subject := await _capture("")
	var roi := _roi(camera, box, with_subject)
	var again := await _capture("")
	_show(nodes, false)
	var without := await _capture("")
	_show(nodes, true)
	if _hide == "body" and kind == "barrel" or _hide == "subject":
		_show(nodes, false)
	var changed := _changed(with_subject, without, roi)
	var noise := _changed(with_subject, again, roi)
	var need: int = MIN_CHANGED[kind]
	print("CITY_ROADSIDE_CONTRIBUTION %s kind=%s nodes=%d roi=%s changed=%d noise=%d need=%d" % [name, kind, nodes.size(), roi, changed, noise, need])
	_check(changed >= need and changed >= NOISE_FACTOR * noise, "%s scene differs with vs without its subject (%d changed pixels, needs %d, noise %d)" % [name, changed, need, noise])
	_show(nodes, true)
	if kind == "barrel":
		await _check_flame(roadside, view, camera)


func _check_flame(roadside: Node3D, view: Dictionary, camera: Camera3D) -> void:
	var name := String(view["name"])
	var centre := (view["subject"] as AABB).get_center()
	var fire: MultiMeshInstance3D
	var best := INF
	for node: MultiMeshInstance3D in roadside.find_children("*", "MultiMeshInstance3D", true, false):
		if String(node.get_meta("roadside_kind", "")) != "fire":
			continue
		var origin := (node.get_meta("city_transforms") as Array)[0].origin as Vector3
		var d := Vector2(origin.x - centre.x, origin.z - centre.z).length()
		if d < best:
			best = d
			fire = node
	if fire == null or best > 0.5:
		_check(false, "%s has its fire node" % name)
		return
	var origin: Vector3 = (fire.get_meta("city_transforms") as Array)[0].origin
	var coal: float = fire.get_meta("fire_coal")
	var rim := origin.y + coal
	for node in Probe.subject_nodes(roadside, view):
		if String(node.get_meta("roadside_kind", "")) == "barrel" and (node.custom_aabb as AABB).grow(0.1).has_point(origin + Vector3(0.0, 0.3, 0.0)):
			rim = (node.custom_aabb as AABB).end.y
	# upper flame only: from just above the drum rim to the flame tip, one flame width around the axis
	var upper := AABB(Vector3(origin.x - 0.3, rim + 0.03, origin.z - 0.3), Vector3(0.6, maxf(origin.y + coal + CityRoadsideFx.FLAME_HEIGHT * 1.02 - rim - 0.03, 0.05), 0.6))
	var flame_only := _flame_only_copy(fire)
	flame_only.visible = false
	roadside.add_child(flame_only)
	var all_fire: Array[MultiMeshInstance3D] = []
	for node: MultiMeshInstance3D in roadside.find_children("*", "MultiMeshInstance3D", true, false):
		if String(node.get_meta("roadside_kind", "")) == "fire":
			all_fire.append(node)
	_show(all_fire, false)
	var without := await _capture("")
	var roi := _roi(camera, upper, without)
	flame_only.visible = _hide != "flame" and _hide != "subject"
	var with_flame := await _capture("")
	flame_only.visible = false
	var again := await _capture("")
	_show(all_fire, true)
	roadside.remove_child(flame_only)
	flame_only.free()
	var changed := _changed(without, with_flame, roi)
	var noise := _changed(without, again, roi)
	print("CITY_ROADSIDE_FLAME %s roi=%s changed=%d noise=%d need=%d" % [name, roi, changed, noise, MIN_CHANGED["flame"]])
	_check(changed >= int(MIN_CHANGED["flame"]) and changed >= NOISE_FACTOR * noise, "%s flame surface alone changes the upper-flame pixels (%d changed, needs %d, noise %d; pool and smoke excluded)" % [name, changed, MIN_CHANGED["flame"], noise])


## Same node data as the real fire, but only surface 0 (the flame quads) of the shared fire mesh: no ground pool, no smoke.
func _flame_only_copy(fire: MultiMeshInstance3D) -> MultiMeshInstance3D:
	var source := CityRoadsideFx.mesh()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(0))
	mesh.surface_set_material(0, source.surface_get_material(0))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, fire.multimesh.get_instance_transform(0))
	multimesh.set_instance_custom_data(0, fire.multimesh.get_instance_custom_data(0))
	var copy := MultiMeshInstance3D.new()
	copy.multimesh = multimesh
	copy.custom_aabb = fire.custom_aabb
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return copy


## Real top-down captures of the first barrel of each drum variant. The drum opening must show warm glowing coal rather than a steel hoop, in the render.
func _check_above_barrels(roadside: Node3D, camera: Camera3D, lights: CityRealismLighting) -> void:
	var path := ProjectSettings.globalize_path("res://../assets/previews/city_roadside")
	var seen := {}
	for barrel: Dictionary in roadside.get_meta("barrels", []):
		if seen.has(barrel["id"]):
			continue
		seen[barrel["id"]] = true
		var xf: Transform3D = barrel["transform"]
		var anchor := CityRoadsideCatalog.fire_anchor(barrel["id"])
		var coal_top := xf.origin + Vector3(0.0, float(anchor["base"][1]), 0.0)
		camera.fov = 40.0
		camera.look_at_from_position(coal_top + Vector3(0.0, 1.5, 0.0), coal_top, Vector3.FORWARD)
		lights._refresh(camera.position)
		var image := await _capture(path.path_join("barrel-above-%s.png" % barrel["id"]))
		var radius := float(anchor["radius"])
		var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
		var centre := camera.unproject_position(coal_top) * scale
		var edge := camera.unproject_position(coal_top + Vector3(radius * 0.8, 0.0, 0.0)) * scale
		var pixel_radius := int(centre.distance_to(edge))
		var warm := 0
		var total := 0
		for y in range(int(centre.y) - pixel_radius, int(centre.y) + pixel_radius + 1):
			for x in range(int(centre.x) - pixel_radius, int(centre.x) + pixel_radius + 1):
				if Vector2(x, y).distance_to(centre) > pixel_radius or x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
					continue
				var c := image.get_pixel(x, y)
				total += 1
				warm += int((c.r > 0.3 and c.r > c.b * 1.5) or c.get_luminance() > 0.6)   # glowing coal is warm or blown out to near white; steel is neither
		print("CITY_ROADSIDE_ABOVE %s radius_px=%d warm=%d of %d" % [barrel["id"], pixel_radius, warm, total])
		_check(total > 100 and float(warm) / float(total) >= 0.3, "%s seen from above shows glowing coal in its opening (%d of %d warm pixels)" % [barrel["id"], warm, total])


func _show(nodes: Array[MultiMeshInstance3D], visible: bool) -> void:
	for node in nodes:
		node.visible = visible


## Screen rectangle of a world box (whole viewport when a corner is behind the camera), clamped to the viewport.
func _roi(camera: Camera3D, box: AABB, image: Image) -> Rect2i:
	var size := Vector2(image.get_size())
	var scale := size / get_viewport().get_visible_rect().size   # unproject_position is in visible-rect units, captures are in texture pixels
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in 8:
		var point := box.position + Vector3(box.size.x * float(corner & 1), box.size.y * float((corner >> 1) & 1), box.size.z * float((corner >> 2) & 1))
		if camera.is_position_behind(point):
			return Rect2i(Vector2i.ZERO, Vector2i(size))
		var p := camera.unproject_position(point) * scale
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	low = low.clamp(Vector2.ZERO, size)
	high = high.clamp(Vector2.ZERO, size)
	return Rect2i(Vector2i(low), Vector2i(high - low))


## Pixels inside `roi` whose colour differs by more than CHANGE_THRESHOLD in any channel.
func _changed(a: Image, b: Image, roi: Rect2i) -> int:
	var count := 0
	for y in range(roi.position.y, mini(roi.end.y, mini(a.get_height(), b.get_height()))):
		for x in range(roi.position.x, mini(roi.end.x, mini(a.get_width(), b.get_width()))):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) > CHANGE_THRESHOLD:
				count += 1
	return count


func _capture(file: String) -> Image:
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if file == "":
		return image
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
