## Geometry invariants run headless; --capture also exercises the Vulkan shader.
extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_geometry()
	await _test_relief_contacts()
	if DisplayServer.get_name() == "headless":
		await _test_relief_driving()
	if "--capture" in OS.get_cmdline_user_args():
		await _captures()
	print("TRACK_VISUALS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_geometry() -> void:
	var course := TrackData.build_course()
	course.configure(course.course_id, course.display_name, course.theme_id, 3, course.points.slice(16) + course.points.slice(0, 16))
	var original := course.points.duplicate(true)
	var root := Node3D.new()
	add_child(root)
	TrackBuilder.build(root, course.points)
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/track_collision.json"))
	_check("same surface-run count as original renderer", root.get_child_count() == golden.size())
	var previous_end := 0.0
	for body: StaticBody3D in root.get_children():
		var visual: MeshInstance3D = body.get_node("RoadMesh")
		var collision: CollisionShape3D = body.get_child(1)
		var faces: PackedVector3Array = collision.shape.get_faces()
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(faces.to_byte_array())
		var record: Dictionary = golden[String(body.name)]
		var sid := Surfaces.id_from_key(body.get_meta("surface_type"))
		var digest := context.finish().hex_encode()
		if not TrackRelief.enabled(sid):
			_check(String(body.name) + " smooth collider bytes match original", digest == record["sha256"])
		else:
			var raised := false
			var bounded := true
			var upward := true
			for vertex in faces:
				raised = raised or vertex.y > 0.005
				bounded = bounded and vertex.y >= 0.0 and vertex.y <= TrackRelief.MAX_HEIGHTS[sid] + 0.00001
			for triangle in range(0, faces.size(), 3):
				var normal := (faces[triangle + 2] - faces[triangle]).cross(faces[triangle + 1] - faces[triangle]).normalized()
				upward = upward and normal.y >= 0.995
			_check(String(body.name) + " has bounded real relief", raised and bounded)
			_check(String(body.name) + " has safe slopes and positive area", upward)
		_check(String(body.name) + " keeps physical surface metadata", body.get_meta("surface_type") == record["surface"])
		_check(String(body.name) + " keeps original collision height", collision.position == Vector3(0, 0.02, 0) and visual.position == collision.position)
		var arrays: Array = visual.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var widths: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		_check(String(body.name) + " visual matches collision vertices", arrays[Mesh.ARRAY_VERTEX] == faces and uvs.size() == faces.size())
		_check(String(body.name) + " metre UVs continue across runs", is_equal_approx(uvs[0].y, previous_end) and uvs[-1].y > uvs[0].y)
		previous_end = uvs[-1].y
		_check(String(body.name) + " carries road width for paint", widths.size() == faces.size() and widths[0].x >= 20.0)
		var height_map_matches := true
		for vertex in faces.size():
			var normalized_height := widths[vertex].y
			height_map_matches = height_map_matches and normalized_height >= 0.0 and normalized_height <= 1.0
			var maximum: float = TrackRelief.MAX_HEIGHTS.get(sid, 0.0)
			height_map_matches = height_map_matches and is_equal_approx(faces[vertex].y, normalized_height * maximum)
		_check(String(body.name) + " material elevation matches visible and collision heights", height_map_matches)
	_check("UV distance covers full closed course", is_equal_approx(previous_end, course.total_length))
	var flat_control := Node3D.new()
	root.add_child(flat_control)
	TrackBuilder.build(flat_control, course.points, false)
	var matches_original := true
	for body: StaticBody3D in flat_control.get_children():
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(body.get_child(1).shape.get_faces().to_byte_array())
		matches_original = matches_original and context.finish().hex_encode() == golden[String(body.name)]["sha256"]
	_check("flat benchmark control retains every original collider hash", matches_original)
	flat_control.free()
	_check("building visuals leaves authored course data unchanged", original == course.points)
	_check("road material instances are cached", TrackMaterials.surface(0, true) == TrackMaterials.surface(0, true))
	var map: Texture2D = TrackMaterials.surface(0).get_shader_parameter("surface_noise")
	for sid in Surfaces.KEYS.size():
		var material := TrackMaterials.surface(sid)
		_check(Surfaces.KEYS[sid] + " uses matching shader id and shared noise", material.get_shader_parameter("surface_id") == sid
			and material.get_shader_parameter("surface_noise") == map)
	var env := TrackMaterials.environment()
	_check("void background and depth fog", env.background_color == Color("050508") and env.fog_enabled
		and env.fog_mode == Environment.FOG_MODE_DEPTH and env.fog_depth_end > env.fog_depth_begin)
	_check("no sky ambient or reflections", env.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED
		and env.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED)
	_check("bloom restricted to HDR highlights", env.glow_hdr_threshold > 2.0 and env.glow_bloom == 0.0)
	var flesh := TrackMaterials.flesh()
	_check("flesh has active SSS and dedicated maps", flesh.subsurf_scatter_enabled and flesh.subsurf_scatter_strength > 0.0
		and flesh.normal_enabled and flesh.normal_texture != null and flesh.roughness_texture != null)
	var viscera := TrackMaterials.surface(Surfaces.Id.MUD, true)
	_check("viscera road shares dedicated sinew normal map", viscera.get_shader_parameter("sinew_normal") == flesh.normal_texture)
	_check("viscera road shares calibrated wet roughness map", viscera.get_shader_parameter("sinew_roughness") == flesh.roughness_texture)
	var rough_map := flesh.roughness_texture.get_image()
	var calibrated := true
	for y in rough_map.get_height():
		for x in rough_map.get_width():
			var value := rough_map.get_pixel(x, y).r
			calibrated = calibrated and value >= 0.095 and value <= 0.255
	_check("flesh roughness map stays wet 0.1 to 0.25", calibrated)
	var guidance := TrackScenery.build_guidance(root, course)
	_check("guidance is visual only", guidance.find_children("*", "CollisionObject3D", true, false).is_empty())
	_check("both bead palettes cover the loop", guidance.get_node("CyanBeads").multimesh.instance_count > 50
		and guidance.get_node("AmberBeads").multimesh.instance_count > 50)
	var local_lights := guidance.find_children("*", "OmniLight3D", true, false)
	_check("bounded light count and no sun", local_lights.size() > 100 and local_lights.size() < 1000
		and guidance.find_children("*", "DirectionalLight3D", true, false).is_empty())
	var max_gap := 0.0
	for index in range(2, local_lights.size(), 2):
		max_gap = maxf(max_gap, local_lights[index].position.distance_to(local_lights[index - 2].position))
	max_gap = maxf(max_gap, local_lights[0].position.distance_to(local_lights[-2].position))
	_check("bead stations leave no large gaps including loop closure", max_gap < 28.0)
	var scenery := TrackScenery.build(root, course)
	_check("scenery adds no collision objects", scenery.find_children("*", "CollisionObject3D", true, false).is_empty())
	_check("sample has service-yard landmark", scenery.has_node("ServiceYard"))
	_check("sample has tank landmark", scenery.has_node("StorageTanks"))
	_check("sample has corner landmark", scenery.has_node("CornerLandmark"))
	var spine_count := 0
	for child: Node in scenery.get_children():
		if String(child.name).begins_with("SpineColumn"):
			spine_count += 1
			_check("spine retains opaque segmented geometry", child.get_child_count() >= 11
				and child.get_child(1).material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				and child.get_child(1).visibility_range_end == 0.0)
	_check("sample contains ribbed spines", spine_count >= 8)
	var prop_count := 0
	for prop: Node3D in scenery.get_children():
		if prop.has_meta("clearance_radius"):
			prop_count += 1
			_check(String(prop.name) + " clears every track branch", TrackScenery.clear_of_course(prop.position, float(prop.get_meta("clearance_radius")), course))
	_check("sample has a bounded prop count", prop_count >= 12 and prop_count < 70)
	var posts: MultiMeshInstance3D = scenery.get_node("RailPosts")
	_check("rail posts are batched", posts.multimesh.instance_count >= 100 and posts.multimesh.instance_count < 200)
	var shoulders: MeshInstance3D = scenery.get_node("SampleShoulders")
	var vertices: PackedVector3Array = shoulders.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var valid := true
	for i in range(0, vertices.size(), 3):
		valid = valid and (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).length() > 0.01
	_check("shoulder triangles have positive area", valid)
	_check("shoulder geometry stays within sample budget", vertices.size() < 3000)
	_check("clearance rejects road center", not TrackScenery.clear_of_course(course.points[20]["pos"], 2.0, course))
	_check("clearance reserves proving ground", not TrackScenery.clear_of_course(Vector3(-550, 0, 0), 5.0, course))
	var deposits := TrackScenery.build_deposits(root, course)
	_check("terrain banks are outside racing collision", deposits.find_children("*", "CollisionObject3D", true, false).is_empty())
	var deposit_count := 0
	var clear := true
	for batch: MultiMeshInstance3D in deposits.get_children():
		for instance in batch.multimesh.instance_count:
			deposit_count += 1
			var transform := batch.multimesh.get_instance_transform(instance)
			clear = clear and TrackScenery.clear_of_course(transform.origin, batch.get_meta("clearance_radius"), course)
	_check("large terrain deposits clear every branch", clear and deposit_count >= 20 and deposit_count < 1000)
	root.free()


func _test_relief_contacts() -> void:
	var root := Node3D.new()
	add_child(root)
	var profiles_valid := true
	for sid: int in TrackRelief.MAX_HEIGHTS:
		for step in 600:
			var s := float(step) * 0.1
			for lateral in range(-120, 121):
				var u := float(lateral) * 0.1
				var h := TrackRelief.height(sid, s, u, 24.0, 60.0, 2)
				var ds := (TrackRelief.height(sid, s + 0.01, u, 24.0, 60.0, 2) - h) / 0.01
				var du := (TrackRelief.height(sid, s, u + 0.01, 24.0, 60.0, 2) - h) / 0.01
				profiles_valid = profiles_valid and h >= 0.0 and h <= TrackRelief.MAX_HEIGHTS[sid] and Vector2(ds, du).length() <= 0.08
		_check("relief fades exactly to flat edges and joins", TrackRelief.height(sid, 0, 0, 24, 60) == 0.0
			and TrackRelief.height(sid, 60, 0, 24, 60) == 0.0 and TrackRelief.height(sid, 30, 12, 24, 60) == 0.0)
	_check("all relief profiles have conservative height and gradient bounds", profiles_valid)
	var points: Array = []
	for i in 21:
		points.append({"pos": Vector3(0, 0, -i * 3.5), "dir": Vector3.FORWARD, "w": 24.0, "dist": 3.5, "s": Surfaces.Id.BOULDER})
	TrackBuilder._build_run(root, points, Surfaces.Id.BOULDER, 0)
	var first: PackedVector3Array = root.get_child(0).get_child(1).shape.get_faces()
	# Equal seed/run index must rebuild byte-identically.
	var duplicate := Node3D.new()
	root.add_child(duplicate)
	TrackBuilder._build_run(duplicate, points, Surfaces.Id.BOULDER, 0)
	_check("relief rebuild is deterministic", first == duplicate.get_child(0).get_child(1).shape.get_faces())
	duplicate.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var hits := true
	var raised := false
	for step in 281:
		var from := Vector3(0, 1, -float(step) * 0.25)
		var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 2.0)
		var hit := space.intersect_ray(query)
		hits = hits and not hit.is_empty()
		if not hit.is_empty():
			raised = raised or hit["position"].y > 0.04
			hits = hits and hit["collider"].get_meta("surface_type") == "boulder"
	_check("downward contacts cross relief without holes and retain surface ID", hits and raised)
	root.free()


func _test_relief_driving() -> void:
	for sid: int in TrackRelief.MAX_HEIGHTS:
		var root := Node3D.new()
		add_child(root)
		var points: Array = []
		for i in 101:
			points.append({"pos": Vector3(0, 0, -i * 3.5), "dir": Vector3.FORWARD, "w": 24.0, "dist": 3.5})
		TrackBuilder._build_run(root, points, sid, 0)
		for end: String in ["A", "B"]:
			var car := Vehicle.new()
			car.tuning = TuningProfile.new()
			car.active_end = end
			car.position = Vector3(0, 1.4, -30)
			car.rotation.y = PI if end == "B" else 0.0
			root.add_child(car)
			for frame in 120:
				await get_tree().physics_frame
			var start_z := car.position.z
			PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(0, 0, -50))
			var gaps: Array[int] = [0, 0, 0, 0]
			var max_gap := 0
			var max_roll := 0.0
			var min_pitch := 10.0
			var max_pitch := -10.0
			var max_yaw_rate := 0.0
			var max_airborne := 0
			var airborne := 0
			var max_drift := 0.0
			for frame in 240:
				await get_tree().physics_frame
				for wheel in car.wheels.size():
					gaps[wheel] = 0 if car.wheels[wheel].contact else gaps[wheel] + 1
					max_gap = maxi(max_gap, gaps[wheel])
				max_roll = maxf(max_roll, absf(car.rotation.z))
				min_pitch = minf(min_pitch, car.rotation.x)
				max_pitch = maxf(max_pitch, car.rotation.x)
				max_yaw_rate = maxf(max_yaw_rate, absf(car.angular_velocity.y))
				airborne = airborne + 1 if car.wheels.all(func(wheel): return not wheel.contact) else 0
				max_airborne = maxi(max_airborne, airborne)
				max_drift = maxf(max_drift, absf(car.position.x))
			_check("%s on %s stays supported at 50m/s entry" % [end, Surfaces.KEYS[sid]], max_gap <= 2
				and max_roll < deg_to_rad(5) and max_drift < 0.3 and car.position.z < start_z - 15.0)
			print("  RELIEF_DRIVE %s %s gap=%d roll=%.3f drift=%.3f travel=%.1f" % [end, Surfaces.KEYS[sid], max_gap, rad_to_deg(max_roll), max_drift, start_z - car.position.z])
			print("  RELIEF_MOTION pitch_range=%.3f yaw_rate=%.4f all_airborne=%d" % [rad_to_deg(max_pitch - min_pitch), max_yaw_rate, max_airborne])
			car.free()
		root.free()
		await get_tree().physics_frame


func _captures() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	_check("driving world has no directional lights", scene.find_children("*", "DirectionalLight3D", true, false).is_empty())
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
		driver.enabled = false
	for car: Vehicle in [scene.car] + scene.cpu_cars:
		car.freeze = true
	scene.race.state = RaceDirector.State.RACING
	scene.race.elapsed = 30.0
	var camera := Camera3D.new()
	camera.fov = 62
	camera.far = 1800
	scene.add_child(camera)
	camera.current = true
	var noise: NoiseTexture2D = TrackMaterials.surface(0).get_shader_parameter("surface_noise")
	if noise.get_image() == null:
		await noise.changed
	_check("seamless noise is ready for rendered capture", noise.get_image() != null)
	var path := ProjectSettings.globalize_path("res://../.ai/captures/track-sample")
	DirAccess.make_dir_recursive_absolute(path)
	var mud := 0
	for i in scene.course.points.size():
		if int(scene.course.points[i]["s"]) == Surfaces.Id.MUD:
			mud = i
			break
	var views := {"straight": 40, "mud-entry": mud, "mud-corner": mud + 24}
	for surface in [Surfaces.Id.GRAVEL, Surfaces.Id.BOULDER, Surfaces.Id.WATER]:
		for index in scene.course.points.size():
			if int(scene.course.points[index]["s"]) == surface:
				views[Surfaces.KEYS[surface] + "-depth"] = index + 8
				break
	for label: String in views:
		var index := int(views[label])
		var point: Dictionary = scene.course.points[index]
		var dir: Vector3 = point["dir"]
		var side := Vector3(-dir.z, 0, dir.x)
		var end := "B" if label == "mud-corner" else "A"
		var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.z) + (PI if end == "B" else 0.0))
		scene._place_player(Transform3D(basis, point["pos"] + Vector3.UP * 1.4), end)
		scene.player_progress.index = index
		camera.global_position = point["pos"] - dir * 24.0 + side * 10.0 + Vector3.UP * 9.0
		camera.look_at(point["pos"] + dir * 36.0 + Vector3.UP, Vector3.UP)
		await _capture(camera, path.path_join(label + ".png"))
		# Low chase-height views make repetition and road readability inspectable.
		if label != "mud-entry":
			camera.global_position = point["pos"] - dir * 13.0 + Vector3.UP * 2.5
			camera.look_at(point["pos"] + dir * 25.0 + Vector3.UP, Vector3.UP)
			await _capture(camera, path.path_join(label + "-driver.png"))
	var center: Vector3 = scene.course.points[90]["pos"]
	camera.global_position = center + Vector3(-105, 155, -220)
	camera.look_at(center + Vector3(20, 0, 65), Vector3.UP)
	await _capture(camera, path.path_join("sample-overview.png"))
	scene.queue_free()
	for frame in 4:
		await get_tree().process_frame
	await _material_gallery()
	var deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## Every surface gets identical neutral/local lighting for useful visual comparison.
func _material_gallery() -> void:
	var gallery := Node3D.new()
	add_child(gallery)
	var environment := WorldEnvironment.new()
	environment.environment = TrackMaterials.environment()
	gallery.add_child(environment)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-12, 0, 36), Vector3(12, 0, 36), Vector3(-12, 0, -36),
		Vector3(-12, 0, -36), Vector3(12, 0, 36), Vector3(12, 0, -36)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 72), Vector2(0, 72), Vector2(1, 0), Vector2(1, 72)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(24, 0), Vector2(24, 0), Vector2(24, 0), Vector2(24, 0), Vector2(24, 0), Vector2(24, 0)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var road := MeshInstance3D.new()
	road.mesh = mesh
	gallery.add_child(road)
	for data: Array in [[Vector3(0, 10, 0), Color("d8d3c4"), 9.0, 65.0],
			[Vector3(-12, 3, -8), Color("00f0ff"), 1.2, 28.0],
			[Vector3(12, 3, -8), Color("ffb703"), 1.2, 28.0]]:
		var light := OmniLight3D.new()
		light.position = data[0]
		light.light_color = data[1]
		light.light_energy = data[2]
		light.omni_range = data[3]
		gallery.add_child(light)
	var camera := Camera3D.new()
	gallery.add_child(camera)
	camera.position = Vector3(0, 3.2, 22)
	camera.look_at(Vector3(0, 0, -8))
	camera.current = true
	var path := ProjectSettings.globalize_path("res://../.ai/captures/bydo-surfaces")
	DirAccess.make_dir_recursive_absolute(path)
	var labels := ["ceramic", "hazard-curb", "chitin-rubble", "viscera", "spinal-armor", "vitrified-coolant", "reactor-effluent", "black-ichor", "carbon-debris"]
	for sid in labels.size():
		road.mesh = mesh
		if TrackRelief.enabled(sid):
			var source := Node3D.new()
			gallery.add_child(source)
			var points: Array = []
			for sample in 25:
				points.append({"pos": Vector3(0, 0, 36 - sample * 3.0), "dir": Vector3.FORWARD, "w": 24.0, "dist": 3.0})
			TrackBuilder._build_run(source, points, sid, 0)
			road.mesh = source.get_child(0).get_node("RoadMesh").mesh
			source.free()
		road.material_override = TrackMaterials.surface(sid, true)
		await _capture(camera, path.path_join(labels[sid] + ".png"))
	gallery.free()


func _capture(camera: Camera3D, path: String) -> void:
	_check(path.get_file() + " camera is current", camera.is_current())
	for frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(path)
	_check(path.get_file() + " saved", result == OK)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
