extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_policy()
	_test_pool_and_pose()
	await _test_race_lifecycle()
	if "--capture" in OS.get_cmdline_user_args():
		await _captures()
	print("VISCERA_RESPONSE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _wheels() -> Array:
	var result: Array = []
	for index in 4:
		var wheel := Wheel.new()
		wheel.end = "A" if index < 2 else "B"
		wheel.side = -1 if index % 2 == 0 else 1
		wheel.contact = true
		wheel.contact_normal = Vector3.UP
		wheel.contact_point = Vector3(wheel.side, 0, -2 if index < 2 else 2)
		wheel.surface_id = Surfaces.Id.MUD
		result.append(wheel)
	return result


func _test_policy() -> void:
	var wheels := _wheels()
	var right := VisceraResponse.response(wheels, "B", 10, 1)
	var wrong := VisceraResponse.response(wheels, "A", 10, 1)
	_check("wrong end throws substantially more viscera at matched speed", wrong.rate > right.rate * 4)
	_check("wrong end sinks deeper and throws higher/larger clumps", wrong.sink > right.sink * 4 and wrong.power > right.power * 2)
	_check("stationary unspinning tyres do not spray", VisceraResponse.response(wheels, "A", 0, 1).rate == 0)
	wheels[0].spin = 1.0
	_check("stuck driven wheelspin can churn viscera", VisceraResponse.response(wheels, "A", 0, 1).rate > 0)
	for wheel: Wheel in wheels:
		wheel.contact = false
	_check("airborne wheels cannot generate contact response", VisceraResponse.response(wheels, "A", 15, 1).wet == 0)
	for wheel: Wheel in wheels:
		wheel.contact = true
		wheel.surface_id = Surfaces.Id.TARMAC
	_check("smooth terrain does not produce viscera immersion", VisceraResponse.response(wheels, "A", 15, 1).sink == 0)
	wheels[0].surface_id = Surfaces.Id.MUD
	_check("seams blend immersion by actual wet-wheel coverage", is_equal_approx(VisceraResponse.response(wheels, "A", 10, 1).sink, wrong.sink * 0.25))
	for wheel: Wheel in wheels:
		wheel.free()


func _test_pool_and_pose() -> void:
	var car := Vehicle.new()
	car.freeze = true
	add_child(car)
	var fx: VisceraResponse = car.get_node("VisceraResponse")
	fx.set_process(false)
	var body_transform := car.transform
	var wheel_transforms: Array[Transform3D] = []
	for wheel: Wheel in car.wheels:
		wheel_transforms.append(wheel.transform)
	var collision_transform: Transform3D = car.get_node("ChassisCollision_0").transform if car.has_node("ChassisCollision_0") else car.get_child(0).transform
	var visual: Node3D = car.get_node("VisualRoot")
	var rest := visual.transform
	var wheels := _wheels()
	var kinds_seen := 0
	for frame in 240:
		fx.advance(1.0 / 60.0, wheels, "A", Vector3(0, 0, -10), 1.0, Basis.IDENTITY)
		for kind in VisceraResponse.FRAGMENT_NAMES.size():
			if fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count > 0:
				kinds_seen |= 1 << kind
	_check("pool has active clumps and is bounded", fx.active_count > 0 and fx.active_count <= VisceraResponse.CAPACITY
		and fx.get_node("ThrownViscera").multimesh.instance_count == VisceraResponse.CAPACITY)
	var visible_total := 0
	var valid_geometry := true
	for label in VisceraResponse.FRAGMENT_NAMES:
		var batch: MultiMeshInstance3D = fx.get_node(label)
		visible_total += batch.multimesh.visible_instance_count
		var faces := batch.multimesh.mesh.get_faces()
		valid_geometry = valid_geometry and faces.size() > 0 and faces.size() / 3 <= 160
		for triangle in range(0, faces.size(), 3):
			valid_geometry = valid_geometry and (faces[triangle + 1] - faces[triangle]).cross(faces[triangle + 2] - faces[triangle]).length() > 0.00001
	_check("all viscera kinds are emitted while sharing the terrain budget", kinds_seen == 7 and visible_total == fx.active_count and visible_total <= VisceraResponse.CAPACITY)
	_check("anatomical meshes have nondegenerate triangles within budget", valid_geometry)
	var entrails: MultiMeshInstance3D = fx.get_node("ThrownEntrails")
	var bounds := entrails.multimesh.mesh.get_aabb().size
	_check("entrails have a narrow elongated silhouette", bounds.z > bounds.x * 2.5)
	_check("wrong-end body has bounded cosmetic immersion", visual.position.y < -0.10 and fx.sink <= 0.12001)
	_check("effect never creates collision objects", fx.find_children("*", "CollisionObject3D", true, false).is_empty())
	var untouched := car.transform == body_transform and car.linear_velocity == Vector3.ZERO and car.angular_velocity == Vector3.ZERO
	for index in car.wheels.size():
		untouched = untouched and car.wheels[index].transform == wheel_transforms[index]
	var collider: Node3D = car.get_node("ChassisCollision_0") if car.has_node("ChassisCollision_0") else car.get_child(0)
	_check("body, wheel hardpoints and collider stay unchanged", untouched and collider.transform == collision_transform)
	for wheel: Wheel in wheels:
		wheel.contact = false
	var emitted := fx.emitted_total
	for frame in 120:
		fx.advance(1.0 / 60.0, wheels, "A", Vector3(0, 0, -10), 1.0, Basis.IDENTITY)
	_check("airborne transition stops spray and drains particles", fx.emitted_total == emitted and fx.active_count == 0)
	_check("body returns to its original pose after leaving viscera", absf(visual.position.y - rest.origin.y) < 0.0001)
	fx.reset_effect()
	for wheel: Wheel in wheels:
		wheel.contact = true
	fx.advance(0.05, wheels, "A", Vector3.ZERO, 0, Basis.IDENTITY)
	var standing_geometry := 0
	for batch: MultiMeshInstance3D in fx.find_children("*", "MultiMeshInstance3D", true, false):
		standing_geometry += batch.multimesh.visible_instance_count
	_check("stationary wet tyres have no surrounding platforms or standing geometry", standing_geometry == 0)
	for wheel: Wheel in wheels:
		wheel.contact = true
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	car.apply_customization({})
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	car.reset_terrain_response()
	_check("model rebuild and reset restore the new visual root", car.get_node("VisualRoot").transform == Transform3D.IDENTITY and fx.active_count == 0)
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	fx._process(1.0 / 60.0)
	_check("freeze clears lingering spray and immersion", fx.active_count == 0 and fx.sink == 0)
	car.freeze = false
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	car.global_position += Vector3(30, 0, 0)
	fx._process(1.0 / 60.0)
	_check("unexpected teleport clears the world-space trail", fx.active_count == 0 and fx.sink == 0)
	_check("particle root does not inherit vehicle movement", fx.top_level and fx.global_transform == Transform3D.IDENTITY)
	for wheel: Wheel in wheels:
		wheel.free()
	car.free()


func _test_race_lifecycle() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	_check("player and CPUs each own one response effect", scene.car.has_node("VisceraResponse")
		and scene.cpu_cars.all(func(car): return car.has_node("VisceraResponse")))
	var wheels := _wheels()
	var fx: VisceraResponse = scene.car.get_node("VisceraResponse")
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene._place_player(scene._spawn, "A")
	_check("player recovery clears the response immediately", fx.active_count == 0 and fx.sink == 0)
	var cpu_fx: VisceraResponse = scene.cpu_cars[0].get_node("VisceraResponse")
	cpu_fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene.cpu_drivers[0].reset(scene._grid_indices[1])
	_check("CPU recovery clears its response immediately", cpu_fx.active_count == 0 and cpu_fx.sink == 0)
	scene.restart_race()
	_check("retry retains exactly one effect per car", scene.car.find_children("VisceraResponse", "Node3D", false, false).size() == 1)
	for wheel: Wheel in wheels:
		wheel.free()
	scene.queue_free()
	for frame in 3:
		await get_tree().process_frame


func _captures(sid: int = Surfaces.Id.MUD, folder: String = "viscera-fragments-chase") -> void:
	var root := Node3D.new()
	add_child(root)
	var environment := WorldEnvironment.new()
	environment.environment = TrackMaterials.environment()
	root.add_child(environment)
	var points: Array = []
	for index in 81:
		points.append({"pos": Vector3(0, 0, -index * 3.5), "dir": Vector3.FORWARD, "w": 24.0, "dist": 3.5})
	TrackBuilder._build_run(root, points, sid, 0)
	var path := ProjectSettings.globalize_path("res://../.ai/captures/" + folder)
	DirAccess.make_dir_recursive_absolute(path)
	for end: String in [Surfaces.PREFERRED[sid], "A" if Surfaces.PREFERRED[sid] == "B" else "B"]:
		var car := preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle("blackjack"))
		car.tuning = TuningProfile.new()
		car.active_end = end
		car.position = Vector3(0, 1.4, -30)
		car.rotation.y = PI if end == "B" else 0.0
		root.add_child(car)
		TrackMaterials.attach_driving_light(car)
		var rig := CameraRig.new()
		rig.target = car
		root.add_child(rig)
		_check("comparison uses the gameplay chase camera", rig.cam.fov == 72.0 and is_equal_approx(rig.cam.position.y, 4.2))
		for frame in 120:
			await get_tree().physics_frame
		PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(2.5 if sid in [Surfaces.Id.ICE, Surfaces.Id.OIL] else 0.0, 0, -10))
		car.steer = 0.16 if sid in [Surfaces.Id.ICE, Surfaces.Id.OIL] else 0.0
		car.throttle = 0.8
		var fx: VisceraResponse = car.get_node("VisceraResponse")
		var label := ("correct-" if end == Surfaces.PREFERRED[sid] else "wrong-") + end
		var emitted := fx.emitted_total
		var capture_start := 30 if sid in [Surfaces.Id.ICE, Surfaces.Id.OIL] else 120
		var peak_skid := 0.0
		var peak_oil_slide := 0.0
		for frame in 180:
			await get_tree().physics_frame
			if frame >= capture_start and frame < capture_start + 60:
				peak_skid = maxf(peak_skid, absf(fx.skid))
				peak_oil_slide = maxf(peak_oil_slide, absf(fx.oil_slide))
			if frame >= capture_start and frame < capture_start + 60 and frame % 5 == 0:
				await RenderingServer.frame_post_draw
				var capture := get_viewport().get_texture().get_image()
				capture.save_png(path.path_join("%s-%02d.png" % [label, (frame - capture_start) / 5]))
		await RenderingServer.frame_post_draw
		_check(label + " rendered actual contact-driven clumps", fx.emitted_total > emitted and fx.active_count > 0)
		if sid == Surfaces.Id.ICE:
			_check(label + " shows an actual lateral skid during capture", peak_skid > (0.03 if end == "A" else 0.15))
		if sid == Surfaces.Id.OIL:
			_check(label + " shows an actual oil slide during capture", peak_oil_slide > (0.03 if end == "A" else 0.2))
		print("TERRAIN_CAPTURE %s %s speed=%.2f sink=%.3f rattle=%.3f impact=%.3f skid=%.3f wash=%.3f peak_skid=%.3f peak_oil_slide=%.3f live=%d emitted=%d" % [Surfaces.KEYS[sid], label, car.speed, fx.sink, fx.rattle, fx.impact, fx.skid, fx.wash, peak_skid, peak_oil_slide, fx.active_count, fx.emitted_total - emitted])
		rig.free()
		car.free()
		await get_tree().process_frame
	root.free()


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
