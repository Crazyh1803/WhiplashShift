## Builds Block Circuit with its City kit; --capture saves review PNGs to .ai/captures/city.
extends Node3D

var _fail := 0


func _ready() -> void:
	var course := BlockCircuitData.build_course()
	var world := Node3D.new()
	add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = TrackMaterials.environment()
	world.add_child(environment)
	_check("track builds", TrackBuilder.build(world, course.points))
	TrackBuilder.build_guard_rails(world, course.points)
	TrackScenery.build_guidance(world, course)
	var city := CityScenery.build(world, course)
	_check("city scenery built", city.get_child_count() > 8)
	var camera := Camera3D.new()
	camera.fov = 70
	camera.far = 2500
	world.add_child(camera)
	var headlight := OmniLight3D.new()
	headlight.light_energy = 2.0
	headlight.omni_range = 45.0
	camera.add_child(headlight)
	camera.current = true
	if "--capture" in OS.get_cmdline_user_args():
		await _captures(course, city, camera, environment)
	world.queue_free()
	for frame in 4:
		await get_tree().process_frame
	print("CITY_VISUAL_QA failures=%d" % _fail)
	get_tree().quit(1 if _fail else 0)


func _captures(course: CourseDefinition, city: Node3D, camera: Camera3D, environment: WorldEnvironment) -> void:
	var path := ProjectSettings.globalize_path("res://../.ai/captures/city")
	DirAccess.make_dir_recursive_absolute(path)
	var origin: Dictionary = course.points[0]
	var dir: Vector3 = origin["dir"]
	camera.global_position = origin["pos"] - dir * 30.0 + Vector3.UP * 1.4
	camera.look_at(origin["pos"] + dir * 120.0 + Vector3.UP * 5.0, Vector3.UP)
	await _capture(camera, path.path_join("opening-driver.png"))
	var count := course.points.size()
	var corner := 0
	while corner < count and _bend_ahead(course, corner) < 0.12:
		corner += 1
	_view_along(course, camera, (corner - _steps(course, 40.0) + count) % count, 40.0 + 70.0, 1.2)
	await _capture(camera, path.path_join("first-corner-driver.png"))
	var gravel := 0
	for i in count:
		if int(course.points[i]["s"]) == Surfaces.Id.GRAVEL:
			gravel = i
			break
	_view_along(course, camera, (gravel - _steps(course, 12.0) + count) % count, 12.0 + 70.0, 1.6)
	await _capture(camera, path.path_join("service-district.png"))
	var crown: Node3D = city.get_node("Crown")
	camera.global_position = origin["pos"] - (origin["dir"] as Vector3) * 60.0 + Vector3.UP * 2.0
	camera.look_at(crown.global_position + Vector3.UP * 110.0, Vector3.UP)
	await _capture(camera, path.path_join("skyline.png"))
	var open_air: Environment = TrackMaterials.environment()
	open_air.fog_enabled = false
	# QA lighting: neutral, overview.png only, so the route shape reads. The game has no sun or ambient.
	open_air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	open_air.ambient_light_color = Color(0.75, 0.78, 0.85)
	open_air.ambient_light_energy = 1.0
	var qa_light := DirectionalLight3D.new()
	qa_light.name = "QaLightingOverviewOnly"
	qa_light.rotation_degrees = Vector3(-60, 30, 0)
	qa_light.light_energy = 0.8
	camera.get_parent().add_child(qa_light)
	print("QA_LIGHTING overview.png uses neutral QA-only illumination, not game lighting")
	environment.environment = open_air
	camera.far = 3500
	camera.global_position = Vector3(0, 1250, 700)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await _capture(camera, path.path_join("overview.png"))


func _steps(course: CourseDefinition, metres: float) -> int:
	return maxi(1, roundi(metres / (course.total_length / float(course.points.size()))))


func _bend_ahead(course: CourseDefinition, index: int) -> float:
	var count := course.points.size()
	var ahead: Dictionary = course.points[(index + _steps(course, 40.0)) % count]
	return absf((course.points[index]["dir"] as Vector3).signed_angle_to(ahead["dir"], Vector3.UP))


## Camera at a route point, aimed at the route point `metres` further along (not the tangent).
func _view_along(course: CourseDefinition, camera: Camera3D, index: int, metres: float, height: float) -> void:
	var count := course.points.size()
	var from: Vector3 = course.points[index]["pos"]
	var to: Vector3 = course.points[(index + _steps(course, metres)) % count]["pos"]
	camera.global_position = from + Vector3.UP * height
	camera.look_at(to + Vector3.UP * (height * 0.8), Vector3.UP)


func _capture(camera: Camera3D, path: String) -> void:
	_check(path.get_file() + " camera is current", camera.is_current())
	for frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(path.get_file() + " saved", get_viewport().get_texture().get_image().save_png(path) == OK)


func _check(label: String, condition: bool) -> void:
	if not condition:
		_fail += 1
		push_error("FAIL: " + label)
	print("QA_%s %s" % ["PASS" if condition else "FAIL", label])
