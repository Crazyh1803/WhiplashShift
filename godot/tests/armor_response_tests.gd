## Fractured spinal armor uses the production contact/camera fixture.
extends "res://tests/viscera_response_tests.gd"


func _ready() -> void:
	_test_armor()
	_test_headlight_roster()
	await _test_lighting_and_recovery()
	if "--capture" in OS.get_cmdline_user_args():
		await _test_rendered_headlights()
		if not "--lighting-only" in OS.get_cmdline_user_args():
			await _captures(Surfaces.Id.BOULDER, "spinal-armor-response")
	print("ARMOR_RESPONSE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _armor_wheels() -> Array:
	var wheels := _wheels()
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.BOULDER
	return wheels


func _test_armor() -> void:
	var wheels := _armor_wheels()
	var right := VisceraResponse.response(wheels, "B", 10, 1)
	var wrong := VisceraResponse.response(wheels, "A", 10, 1)
	_check("wrong end has stronger armor bursts and impacts", wrong.armor_rate > right.armor_rate * 2
		and wrong.impact > right.impact * 7 and wrong.armor_power > right.armor_power * 2)
	_check("armor has discrete impacts without mud sinking or gravel rattle", wrong.impact > 0 and wrong.sink == 0 and wrong.rattle == 0)
	var still := VisceraResponse.response(wheels, "A", 0, 1)
	_check("stationary unspinning armor has no impact or debris", still.impact == 0 and still.armor_rate == 0)
	wheels[0].spin = 1
	_check("wheelspin can eject armor", VisceraResponse.response(wheels, "A", 0, 1).armor_rate > 0)
	wheels[0].spin = 0
	for wheel: Wheel in wheels:
		wheel.contact = false
	_check("airborne armor cannot jolt the chassis", VisceraResponse.response(wheels, "A", 10, 1).impact == 0)
	for wheel: Wheel in wheels:
		wheel.contact = true
	var car := Vehicle.new()
	car.freeze = true
	add_child(car)
	var fx: VisceraResponse = car.get_node("VisceraResponse")
	fx.set_process(false)
	var visual: Node3D = car.get_node("VisualRoot")
	var body_transform := car.transform
	var mounts: Array[Transform3D] = []
	for wheel: Wheel in car.wheels:
		mounts.append(wheel.transform)
	var collider: Node3D = car.get_child(0)
	var collision_transform := collider.transform
	var seen := 0
	var flat_changes := 0
	var previous := visual.basis
	for frame in 360:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
		if frame >= 120 and not visual.basis.is_equal_approx(previous):
			flat_changes += 1
		previous = visual.basis
		var total := 0
		for kind in VisceraResponse.FRAGMENT_NAMES.size():
			var count: int = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count
			total += count
			if count > 0:
				seen |= 1 << kind
		assert(total == fx.active_count and total <= VisceraResponse.CAPACITY)
	_check("armor emits plates and broken ribs exclusively within shared capacity", seen == 192)
	_check("flat equal settled boulder contacts stop changing pose and never lift", flat_changes == 0 and visual.position.is_zero_approx())
	var uneven := _armor_wheels()
	uneven[0].compression = 0.04
	uneven[3].compression = 0.01
	var uneven_changes := 0
	for frame in 30:
		fx.advance(1.0 / 60, uneven, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
		if not visual.basis.is_equal_approx(previous):
			uneven_changes += 1
		previous = visual.basis
	_check("real unequal boulder contacts move the pose", uneven_changes > 10 and not visual.basis.is_equal_approx(Basis.IDENTITY))
	for wheel: Wheel in uneven:
		wheel.free()
	for frame in 360:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	_check("pose settles again once contacts equalize", visual.basis.is_equal_approx(Basis.IDENTITY))
	var untouched := car.transform == body_transform and collider.transform == collision_transform
	for index in car.wheels.size():
		untouched = untouched and car.wheels[index].transform == mounts[index]
	_check("impacts never write body velocity collider or wheel transforms", untouched and car.linear_velocity == Vector3.ZERO and car.angular_velocity == Vector3.ZERO)
	_check("armor has no added collision geometry", fx.find_children("*", "CollisionObject3D", true, false).is_empty())
	for kind in [6, 7]:
		var batch: MultiMeshInstance3D = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind])
		var vertices: PackedVector3Array = batch.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var valid := vertices.size() > 0 and vertices.size() <= 480
		for i in range(0, vertices.size(), 3):
			valid = valid and vertices[i].is_finite() and (vertices[i+1] - vertices[i]).cross(vertices[i+2] - vertices[i]).length_squared() > 0.0000001
		_check("armor mesh %d has bounded nondegenerate geometry" % kind, valid and batch.material_override.roughness > 0.65 and not batch.material_override.emission_enabled)
	fx.reset_effect()
	wheels[0].surface_id = Surfaces.Id.MUD
	wheels[1].surface_id = Surfaces.Id.GRAVEL
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	_check("mixed terrain blends all three responses in one controller", fx.sink > 0 and fx.rattle > 0 and fx.impact > 0 and fx.impact < wrong.impact)
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.TARMAC
	var emitted := fx.emitted_total
	for frame in 180:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	_check("leaving armor restores the body and clears debris", fx.emitted_total == emitted and fx.active_count == 0 and fx.impact < 0.0001 and visual.position.length() < 0.0001)
	car.free()
	for wheel: Wheel in wheels:
		wheel.free()


func _test_headlight_roster() -> void:
	for spec: Dictionary in VehicleCatalog.VEHICLES:
		var car := preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle(spec["id"]))
		car.freeze = true
		add_child(car)
		TrackMaterials.attach_driving_light(car)
		TrackMaterials.attach_driving_light(car)
		var headlights: Node3D = car.get_node("DrivingHeadlights")
		var valid: bool = not headlights._lens_materials.is_empty()
		for end: String in ["A", "B"]:
			car.active_end = end
			for material: ShaderMaterial in headlights._lens_materials:
				valid = valid and material.get_shader_parameter("active_sign") == (-1.0 if end == "A" else 1.0)
			for lamp: SpotLight3D in headlights.get_node("End" + end).get_children():
				valid = valid and lamp.position.is_finite() and absf(lamp.position.x) > 0.1 and absf(lamp.position.z) > 1.0
		_check("%s has mounted beams and switching lens emission without duplicate lights" % spec["id"],
			valid and car.find_children("*", "SpotLight3D", true, false).size() == 4)
		car.free()


func _test_lighting_and_recovery() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	for car: Vehicle in [scene.car] + scene.cpu_cars:
		var headlights: Node3D = car.get_node("DrivingHeadlights")
		_check("%s has only paired directional headlights" % car.name,
			car.find_children("*", "OmniLight3D", true, false).is_empty()
			and headlights.find_children("*", "SpotLight3D", true, false).size() == 4)
		_check("%s starts with only End A illuminated" % car.name,
			headlights.get_node("EndA").visible and not headlights.get_node("EndB").visible)
		car.swap_ends()
		_check("%s swap immediately switches the headlights" % car.name,
			not headlights.get_node("EndA").visible and headlights.get_node("EndB").visible)
		car.active_end = "A"
		_check("%s recovery immediately restores End A headlights" % car.name,
			headlights.get_node("EndA").visible and not headlights.get_node("EndB").visible)
		for end: String in ["A", "B"]:
			for lamp: SpotLight3D in headlights.get_node("End" + end).get_children():
				var forward := -lamp.transform.basis.z
				_check("%s %s beam points outward and down" % [car.name, end],
					forward.y < 0 and forward.z * (-1 if end == "A" else 1) > 0.9
					and lamp.position.z * (-1 if end == "A" else 1) > 1.0
					and lamp.shadow_enabled and lamp.spot_angle < 45)
	_check("void remains free of global sun lighting", scene.find_children("*", "DirectionalLight3D", true, false).is_empty()
		and TrackMaterials.environment().ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED)
	var wheels := _armor_wheels()
	var fx: VisceraResponse = scene.car.get_node("VisceraResponse")
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene._place_player(scene._spawn, "A")
	_check("player recovery clears armor impacts", fx.impact == 0 and fx.active_count == 0)
	var cpu_fx: VisceraResponse = scene.cpu_cars[0].get_node("VisceraResponse")
	cpu_fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene.cpu_drivers[0].reset(scene._grid_indices[1])
	_check("CPU recovery clears armor impacts", cpu_fx.impact == 0 and cpu_fx.active_count == 0)
	for wheel: Wheel in wheels:
		wheel.free()
	scene.queue_free()
	for frame in 3:
		await get_tree().process_frame


func _test_rendered_headlights() -> void:
	# A neutral receiver isolates forward beams from street lights and textures.
	var root := Node3D.new()
	add_child(root)
	var environment := WorldEnvironment.new()
	environment.environment = TrackMaterials.environment()
	root.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48, 48)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)
	material.roughness = 1.0
	floor_mesh.material_override = material
	root.add_child(floor_mesh)
	var car := preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle("blackjack"))
	car.freeze = true
	car.position.y = 1.0
	root.add_child(car)
	TrackMaterials.attach_driving_light(car)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 48
	camera.position = Vector3(0, 30, 0)
	camera.rotation.x = -PI / 2
	root.add_child(camera)
	camera.make_current()
	for frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image()
	for end: String in ["A", "B"]:
		car.active_end = end
		for frame in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		rendered = get_viewport().get_texture().get_image()
		var brightness: Array[float] = []
		for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			var screen := camera.unproject_position(direction * 12.0)
			var pixel := Vector2i(screen * Vector2(rendered.get_size()) / get_viewport().get_visible_rect().size)
			var color := rendered.get_pixelv(pixel)
			brightness.append(color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722)
		var front := 0 if end == "A" else 1
		var rear := 1 - front
		print("HEADLIGHTS end=%s front=%.3f rear=%.3f sides=%.3f,%.3f" % [end, brightness[front], brightness[rear], brightness[2], brightness[3]])
		_check("End %s lights the road ahead without a surrounding pool" % end,
			brightness[front] > 0.02 and brightness[front] > brightness[rear] + 0.02
			and brightness[front] > maxf(brightness[2], brightness[3]) + 0.02)
	root.free()
	await get_tree().process_frame
