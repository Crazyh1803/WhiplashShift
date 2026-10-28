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
	var gravel := 0
	for i in course.points.size():
		if int(course.points[i]["s"]) == Surfaces.Id.GRAVEL:
			gravel = i
			break
	var point: Dictionary = course.points[(gravel - 25 + course.points.size()) % course.points.size()]
	dir = point["dir"]
	camera.global_position = point["pos"] + Vector3.UP * 1.5
	camera.look_at(point["pos"] + dir * 90.0 + Vector3.UP * 3.0, Vector3.UP)
	await _capture(camera, path.path_join("service-district.png"))
	var crown: Node3D = city.get_node("Crown")
	camera.global_position = origin["pos"] - (origin["dir"] as Vector3) * 60.0 + Vector3.UP * 2.0
	camera.look_at(crown.global_position + Vector3.UP * 110.0, Vector3.UP)
	await _capture(camera, path.path_join("skyline.png"))
	var open_air: Environment = TrackMaterials.environment()
	open_air.fog_enabled = false
	environment.environment = open_air
	camera.far = 3500
	camera.global_position = Vector3(0, 1250, 700)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await _capture(camera, path.path_join("overview.png"))


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
