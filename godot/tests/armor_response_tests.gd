## Fractured spinal armor uses the production contact/camera fixture.
extends "res://tests/viscera_response_tests.gd"


func _ready() -> void:
	_test_armor()
	await _test_lighting_and_recovery()
	if "--capture" in OS.get_cmdline_user_args():
		await _test_rendered_light_pool()
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
	_check("wrong end has stronger armor bursts and impacts", wrong.armor_rate >= right.armor_rate * 5
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
	var peak := 0.0
	var max_step := 0.0
	var previous := 0.0
	var quiet_frames := 0
	for frame in 360:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
		peak = maxf(peak, visual.position.y)
		max_step = maxf(max_step, absf(visual.position.y - previous))
		previous = visual.position.y
		if absf(visual.position.y) < 0.003:
			quiet_frames += 1
		var total := 0
		for kind in VisceraResponse.FRAGMENT_NAMES.size():
			var count: int = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count
			total += count
			if count > 0:
				seen |= 1 << kind
		assert(total == fx.active_count and total <= VisceraResponse.CAPACITY)
	_check("armor emits plates and broken ribs exclusively within shared capacity", seen == 192)
	_check("heavy impacts have bounded lift and quiet gaps", peak > 0.035 and peak < 0.066 and quiet_frames > 100 and max_step < 0.025)
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


func _test_lighting_and_recovery() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	var lamp: OmniLight3D = scene.car.get_node("DrivingLightPool")
	_check("production local illumination has no opposed cone masks", scene.car.find_children("*", "SpotLight3D", false, false).is_empty()
		and lamp.omni_range >= 60 and lamp.omni_attenuation > 1 and lamp.light_energy > 0 and not lamp.shadow_enabled)
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


func _test_rendered_light_pool() -> void:
	# Sample a neutral receiver to detect dark side wedges independently of texture.
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
	TrackMaterials.attach_driving_light(root)
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
	for radius: float in [9.0, 18.0]:
		var low := 1.0
		var high := 0.0
		for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var screen := camera.unproject_position(direction * radius)
			# Camera coordinates use the logical viewport; captures use output pixels.
			var pixel := Vector2i(screen * Vector2(rendered.get_size()) / get_viewport().get_visible_rect().size)
			var color := rendered.get_pixelv(pixel)
			var brightness := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			low = minf(low, brightness)
			high = maxf(high, brightness)
		print("LIGHT_POOL radius=%.0fm min=%.3f max=%.3f" % [radius, low, high])
		_check("local light reaches both sides and both ends at %.0fm" % radius, low > 0.02 and high - low < 0.025)
	root.free()
	await get_tree().process_frame
