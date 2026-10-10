extends Node3D

var camera: Camera3D


func _ready() -> void:
	_build_studio()
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, .10, 20)
	collision.shape = shape
	collision.position.y = -.05
	ground.add_child(collision)
	add_child(ground)
	var vehicle := preload("res://tests/blackjack_refined_preview_vehicle.gd").new()
	vehicle.tuning = TuningProfile.new()
	var spec := preload("res://tests/blackjack_refined_fixture.gd").spec()
	var paint := VehicleCatalog.default_customization("blackjack")
	paint["primary_color"] = "90999e"
	paint["secondary_color"] = "3b4647"
	paint["accent_color"] = "b5b9bb"
	paint["parts"]["hood_engine"] = "supercharger"
	spec["customization"] = paint
	vehicle.apply_vehicle_spec(spec)
	vehicle.position.y = .85
	add_child(vehicle)
	for i in range(180):
		await get_tree().physics_frame
	vehicle.freeze = true
	var model := vehicle.get_node("VisualRoot/ProductionModel") as Node3D
	for wheel: Wheel in vehicle.wheels:
		print("REFINED_WHEEL_SEAT %s center=%s radius=%f" % [wheel.name, model.to_local(wheel.get_node("ModularWheelVisual").global_position), wheel.radius / model.scale.x])
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.3
	await _capture("res://assets/vehicles/models/blackjack/blackjack_refined_godot_side.png", Vector3(7, 1.1, 0), Vector3(0, 1.1, 0))
	await _capture("res://assets/vehicles/models/blackjack/blackjack_refined_godot_three_quarter.png", Vector3(5, 3.1, -5.2), Vector3(0, .95, 0))
	if not "--inspect" in OS.get_cmdline_user_args():
		get_tree().quit()


func _build_studio() -> void:
	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color("55616b")
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("f2f6f9")
	world.ambient_light_energy = 1.45
	world.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.environment = world
	add_child(environment)
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("343b41")
	material.roughness = .82
	ground_mesh.material_override = material
	add_child(ground_mesh)
	for light_spec: Array in [[Vector3(-48, -32, -24), 1.8], [Vector3(-32, 145, 18), .95]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_spec[0]
		light.light_energy = light_spec[1]
		light.shadow_enabled = true
		add_child(light)
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)


func _capture(path: String, position: Vector3, target: Vector3) -> void:
	camera.position = position
	camera.look_at(target, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Unable to save QA image %s: %s" % [path, error_string(error)])
		get_tree().quit(1)
