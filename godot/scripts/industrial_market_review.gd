extends Node3D

const VIEWS: Array[String] = ["Car and shop", "Driver approach", "Sidewalk", "Counter", "Vendor face", "Customer face", "Support", "Materials"]
var benchmark: IndustrialMarketBenchmark
var camera: Camera3D
var environment: WorldEnvironment
var key: DirectionalLight3D
var local_lights: Array[Light3D] = []
var lighting_label: Label
var view_index := 0
var night := false
var focus := Vector3(0.0, 1.5, -1.0)
var distance := 13.0
var yaw := -0.55
var pitch := 0.18
var _capture_mode := false
var _out := ""


func _ready() -> void:
	_capture_mode = "--capture" in OS.get_cmdline_user_args()
	_out = ProjectSettings.globalize_path("res://../.ai/captures/industrial-market").simplify_path()
	benchmark = _create_benchmark()
	add_child(benchmark)
	if not benchmark.build():
		var message := "Industrial market review: " + "; ".join(benchmark.errors)
		if _capture_mode:
			push_error(message)
			get_tree().quit(1)
		else:
			GameSession.menu_error = message
			_back.call_deferred()
		return
	_build_world()
	_build_controls()
	_set_lighting(false)
	_set_view(0)
	if _capture_mode:
		var success := await _captures()
		get_tree().quit(0 if success else 1)


func _create_benchmark() -> IndustrialMarketBenchmark:
	return IndustrialMarketBenchmark.new()


func _build_world() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(36.0, 36.0)
	ground.mesh = plane
	ground.position.y = 0.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("252a2c")
	material.roughness = 0.88
	ground.material_override = material
	add_child(ground)
	environment = WorldEnvironment.new()
	add_child(environment)
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.04
	camera.far = 120.0
	camera.current = true
	add_child(camera)
	key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-46.0, -35.0, 0.0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	add_child(key)
	var counter := benchmark.target("counter")
	_spot(Vector3(0.6, 3.55, -1.2), counter, Color("ffd5a0"), 9.0, 7.0)
	_spot(Vector3(2.5, 5.2, -7.0), Vector3(-2.0, 0.6, -5.0), Color("b4cfda"), 4.0, 15.0)
	_omni(counter + Vector3(2.0, 1.9, -0.3), Color("ffc987"), 2.0, 7.0)
	_omni(counter + Vector3(-3.8, 1.4, -2.8), Color("8eb9c9"), 1.3, 10.0)


func _spot(position: Vector3, target: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := SpotLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.spot_range = radius
	light.spot_angle = 55.0
	light.shadow_enabled = true
	light.shadow_bias = 0.02
	light.shadow_normal_bias = 0.08
	add_child(light)
	light.look_at(target, Vector3.UP)
	local_lights.append(light)


func _omni(position: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	add_child(light)
	local_lights.append(light)


func _set_lighting(value: bool) -> void:
	night = value
	var env: Environment
	if night:
		env = TrackMaterials.environment()
		env.fog_enabled = false
		var night_sky := Sky.new()
		var panorama := preload("res://scripts/blackjack_studio_finish.gd").reflection_sky().sky_material.duplicate() as PanoramaSkyMaterial
		panorama.energy_multiplier = 0.12
		night_sky.sky_material = panorama
		env.sky = night_sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
	else:
		env = preload("res://scripts/blackjack_studio_finish.gd").environment(Color("30383e"))
		env.ambient_light_energy = 0.8
	env.ssao_enabled = true
	env.ssao_radius = 0.25
	env.ssao_intensity = 1.25
	environment.environment = env
	key.visible = not night
	for light: Light3D in local_lights:
		light.visible = night
	if lighting_label != null:
		lighting_label.text = "NIGHT // proposed street-light study" if night else "NEUTRAL // diagnostic inspection"


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReviewControls"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "REDLINE RAMEN // VEHICLE-MATCHED STUDY"
	column.add_child(title)
	var reference := Label.new()
	reference.text = "Reference: BLACKJACK X-17 (catalog vehicle)"
	column.add_child(reference)
	var views := OptionButton.new()
	views.name = "ReviewView"
	for label: String in VIEWS:
		views.add_item(label)
	views.item_selected.connect(_set_view)
	column.add_child(views)
	var lighting := CheckButton.new()
	lighting.name = "NightLighting"
	lighting.text = "Night street lighting"
	lighting.toggled.connect(_set_lighting)
	column.add_child(lighting)
	lighting_label = Label.new()
	lighting_label.name = "LightingSetup"
	column.add_child(lighting_label)
	var hint := Label.new()
	hint.text = "Right-drag to orbit • Wheel to zoom • Esc to menu"
	column.add_child(hint)
	var back := Button.new()
	back.text = "BACK TO MENU"
	back.pressed.connect(_back)
	column.add_child(back)


func _set_view(index: int) -> void:
	view_index = clampi(index, 0, VIEWS.size() - 1)
	var at := Vector3(0.0, 1.5, -1.8)
	var from := Vector3(-10.0, 4.5, -14.0)
	match view_index:
		0:
			at = Vector3(-0.8, 1.2, -3.0)
		1:
			from = Vector3(-7.5, 1.6, -11.0)
		2:
			from = Vector3(6.5, 1.75, -7.5)
			at = benchmark.target("counter") + Vector3(0.0, 0.6, 0.0)
		3:
			at = benchmark.target("counter") + Vector3(0.0, 0.2, 0.0)
			from = at + Vector3(-1.5, 0.4, -2.6)
		4, 5:
			at = benchmark.target("vendor_face" if view_index == 4 else "customer_face")
			from = at + (Vector3(-0.7, 0.05, -1.8) if view_index == 4 else Vector3(0.45, 0.05, 1.8))
		6:
			at = benchmark.target("support")
			from = at + Vector3(1.7, 0.6, -3.0)
		7:
			at = benchmark.target("materials")
			from = at + Vector3(0.6, 0.3, -1.8)
	focus = at
	var direction := from - at
	distance = direction.length()
	yaw = atan2(direction.x, direction.z)
	pitch = asin(direction.y / distance)
	_update_camera()


func _update_camera() -> void:
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.position.y = maxf(0.12, camera.position.y)
	camera.look_at(focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode or camera == null:
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006, -0.15, 1.25)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0.6, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(35.0, distance / 0.9)
		_update_camera()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _captures() -> bool:
	if DisplayServer.get_name() == "headless" or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("Rendered industrial market capture requires a display and writable output")
		return false
	get_node("ReviewControls").hide()
	for dark: bool in [false, true]:
		_set_lighting(dark)
		for index in VIEWS.size():
			_set_view(index)
			for frame in 20:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var label := ("night-" if dark else "neutral-") + VIEWS[index].to_lower().replace(" ", "-")
			var path := _out.path_join(label + ".png")
			if get_viewport().get_texture().get_image().save_png(path) != OK:
				push_error("Cannot save industrial market image: " + path)
				return false
			print("INDUSTRIAL_MARKET_CAPTURE ", path)
	var shadows := local_lights.filter(func(light: Light3D) -> bool: return light.shadow_enabled).size()
	print("INDUSTRIAL_MARKET_REVIEW candidate_triangles=%d surfaces=%d vehicle_triangles=%d vehicle_surfaces=%d reference=%s lights=%d shadows=%d" % [benchmark.triangle_count, benchmark.surface_count, benchmark.vehicle_triangle_count, benchmark.vehicle_surface_count, benchmark.get_meta("vehicle_reference"), local_lights.size(), shadows])
	return true
