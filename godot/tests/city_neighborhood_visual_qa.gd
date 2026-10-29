# Review the production street block, using the same scenery builder as the race.
extends Node3D

var _course: CourseDefinition
var _camera: Camera3D
var _environment: WorldEnvironment
var _capture_directory := ""
var _fail := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Street block visual review requires a rendering device")
		get_tree().quit(1)
		return
	_capture_directory = ProjectSettings.globalize_path("res://../.ai/captures/city-street-block").simplify_path()
	if DirAccess.make_dir_recursive_absolute(_capture_directory) != OK:
		get_tree().quit(1)
		return
	_course = BlockCircuitData.build_course().geometry()
	if not TrackBuilder.build(self, _course.points):
		get_tree().quit(1)
		return
	TrackBuilder.build_guard_rails(self, _course.points)
	TrackScenery.build_guidance(self, _course)
	var city := CityScenery.build(self, _course)
	var block := city.get_node_or_null("CityStreetBlock")
	if block == null:
		push_error("Street review requires the complete production block, not fallback scenery")
		get_tree().quit(1)
		return
	print("STREET_BLOCK_REVIEW triangles=%d placements=%d lights=%d" % [block.get_meta("triangle_count"), block.get_meta("placements").size(), block.get_meta("light_count")])
	_environment = WorldEnvironment.new()
	add_child(_environment)
	_camera = Camera3D.new()
	_camera.fov = 65.0
	_camera.far = 2500.0
	add_child(_camera)
	_camera.current = true
	await _views()
	print("STREET_BLOCK_VISUAL_QA failures=%d" % _fail)
	get_tree().quit(1 if _fail else 0)


func _views() -> void:
	var neutral := TrackMaterials.environment()
	neutral.fog_enabled = false
	neutral.background_color = Color("242b33")
	neutral.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	neutral.ambient_light_color = Color("b6c2d1")
	neutral.ambient_light_energy = 0.45
	_environment.environment = neutral
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	add_child(key)
	_view(138.0, 1.0, 160.0, 110.0, 138.0, 0.0, 7.0)
	await _capture("block-overview-neutral")
	_driver(70.0, false)
	await _capture("driver-neutral")
	_view(94.0, 1.0, 7.0, 1.75, 110.0, 24.0, 5.0)
	await _capture("market-sidewalk-neutral")
	_view(25.0, -1.0, 7.0, 1.75, 46.0, 23.0, 6.0)
	await _capture("workshop-frontage-neutral")
	_view(73.0, 1.0, 8.0, 1.75, 75.0, 47.0, 2.5)
	await _capture("service-alley-neutral")
	_view(210.0, 1.0, 56.0, 2.0, 225.0, 34.0, 4.0)
	await _capture("freight-yard-neutral")
	key.free()
	_environment.environment = TrackMaterials.environment()
	var headlight := OmniLight3D.new()
	headlight.light_energy = 2.0
	headlight.omni_range = 45.0
	_camera.add_child(headlight)
	_driver(70.0, false)
	await _capture("driver-night")
	_view(94.0, 1.0, 7.0, 1.75, 110.0, 24.0, 5.0)
	await _capture("market-sidewalk-night")
	_driver(260.0, true)
	await _capture("reverse-night")


func _point(s: float, side: float, lateral: float, height: float) -> Vector3:
	var at := CityDistrict.sample(_course, s)
	var dir: Vector3 = at["dir"]
	var normal := Vector3(-dir.z, 0.0, dir.x) * side
	var edge := (float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET) if side != 0.0 else 0.0
	return at["pos"] + normal * (edge + lateral) + Vector3.UP * height


func _view(s: float, side: float, lateral: float, height: float, target_s: float, target_lateral: float, target_height: float) -> void:
	_camera.position = _point(s, side, lateral, height)
	_camera.look_at(_point(target_s, side if target_lateral != 0.0 else 0.0, target_lateral, target_height), Vector3.UP)


func _driver(s: float, reverse: bool) -> void:
	_camera.position = _point(s, 0.0, 0.0, 1.6)
	_camera.look_at(_point(s + (-65.0 if reverse else 65.0), 0.0, 0.0, 2.0), Vector3.UP)


func _capture(label: String) -> void:
	for frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	var path := _capture_directory.path_join(label + ".png")
	if screenshot == null or screenshot.save_png(path) != OK:
		_fail += 1
		push_error("Cannot save street block capture: " + path)
	print("STREET_BLOCK_CAPTURE ", path)
