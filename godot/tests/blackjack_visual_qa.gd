extends Node3D

const OUTPUT_SIDE := "res://assets/vehicles/models/blackjack/blackjack_production_v2_godot_side.png"
const OUTPUT_THREE_QUARTER := "res://assets/vehicles/models/blackjack/blackjack_production_v2_godot_three_quarter.png"

var camera: Camera3D


func _ready() -> void:
	_build_studio()
	var vehicle := Vehicle.new()
	vehicle.tuning = TuningProfile.new()
	var spec := VehicleCatalog.get_vehicle("blackjack")
	spec["customization"] = VehicleCatalog.default_customization("blackjack")
	vehicle.apply_vehicle_spec(spec)
	vehicle.freeze = true
	vehicle.position = Vector3(0.0, 0.85, 0.0)
	add_child(vehicle)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture(OUTPUT_SIDE, Vector3(5.8, 2.0, 0.0), Vector3(0.0, 1.0, 0.0))
	await _capture(OUTPUT_THREE_QUARTER, Vector3(5.0, 3.1, 5.2), Vector3(0.0, 0.9, 0.0))
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

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("343b41")
	floor_material.roughness = 0.82
	floor.material_override = floor_material
	add_child(floor)

	for light_spec: Array in [
		[Vector3(-48.0, -32.0, -24.0), 1.8],
		[Vector3(-32.0, 145.0, 18.0), 0.95],
	]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_spec[0]
		light.light_energy = light_spec[1]
		light.shadow_enabled = true
		add_child(light)

	camera = Camera3D.new()
	camera.fov = 39.0
	camera.current = true
	add_child(camera)


func _capture(path: String, position: Vector3, target: Vector3) -> void:
	camera.position = position
	camera.look_at(target, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Unable to save visual QA image %s: %s" % [path, error_string(error)])
		get_tree().quit(1)
