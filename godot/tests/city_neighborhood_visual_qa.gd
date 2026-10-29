# Standalone art study on canonical Block Circuit geometry; this scene does not alter race scenery.
extends Node3D

const MODEL_DIRECTORY := "res://assets/city/candidates/neighborhood/"
const SLOTS := [
	{"id": "habitation_workshop", "s": 45.0, "side": -1.0},
	{"id": "market_habitat", "s": 105.0, "side": 1.0},
	{"id": "service_tenement", "s": 165.0, "side": -1.0},
	{"id": "freight_depot", "s": 225.0, "side": 1.0},
]
var _course: CourseDefinition
var _camera: Camera3D
var _environment: WorldEnvironment
var _world: Node3D
var _catalog: Dictionary = {}
var _boxes: Array[AABB] = []
var _overview := AABB()
var _lamps: Array[Light3D] = []
var _capture_directory := ""
var _fail := 0
var _building_count := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Neighborhood visual study requires a rendering device")
		get_tree().quit(1)
		return
	_capture_directory = ProjectSettings.globalize_path("res://").path_join("../.ai/captures/city-neighborhood/street-study").simplify_path()
	if DirAccess.make_dir_recursive_absolute(_capture_directory) != OK:
		push_error("Cannot create neighborhood capture directory: " + _capture_directory)
		get_tree().quit(1)
		return
	for path: String in [MODEL_DIRECTORY + "neighborhood_manifest.json", "res://assets/city/candidates/habitation_workshop_manifest.json"]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or not data.get("assets") is Array:
			push_error("Invalid neighborhood study manifest: " + path)
			get_tree().quit(1)
			return
		for entry: Variant in data["assets"]:
			if entry is Dictionary and entry.get("id") is String:
				_catalog[entry["id"]] = entry
	_course = BlockCircuitData.build_course().geometry()
	_world = Node3D.new()
	add_child(_world)
	if not TrackBuilder.build(_world, _course.points):
		push_error("Cannot build canonical road for neighborhood review")
		get_tree().quit(1)
		return
	TrackBuilder.build_guard_rails(_world, _course.points)
	TrackScenery.build_guidance(_world, _course)
	for slot: Dictionary in SLOTS:
		_place_building(slot)
	if _building_count != SLOTS.size():
		push_error("Neighborhood study requires all four buildings")
		get_tree().quit(1)
		return
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600.0, 1600.0)
	ground.mesh = plane
	ground.position.y = -0.06
	var pavement := StandardMaterial3D.new()
	pavement.albedo_color = Color("171b22")
	pavement.roughness = 0.9
	ground.material_override = pavement
	_world.add_child(ground)
	_environment = WorldEnvironment.new()
	add_child(_environment)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 1800.0
	add_child(_camera)
	_camera.current = true
	await _views()
	print("NEIGHBORHOOD_STUDY buildings=%d placed_bounds=%d failures=%d" % [_building_count, _boxes.size(), _fail])
	get_tree().quit(1 if _fail else 0)


func _place_building(slot: Dictionary) -> void:
	var id: String = slot["id"]
	if not _catalog.has(id):
		push_error("Neighborhood study is missing building: " + id)
		_fail += 1
		return
	var entry: Dictionary = _catalog[id]
	if not _valid_bounds(entry.get("aabb")):
		push_error("Invalid neighborhood bounds: " + id)
		_fail += 1
		return
	var low: Array = entry["aabb"]["min"]
	var high: Array = entry["aabb"]["max"]
	var local := AABB(Vector3(low[0], low[1], low[2]), Vector3(high[0] - low[0], high[1] - low[1], high[2] - low[2]))
	var sample := CityDistrict.sample(_course, float(slot["s"]))
	var direction: Vector3 = sample["dir"]
	var normal := Vector3(-direction.z, 0.0, direction.x) * float(slot["side"])
	var basis := Basis.looking_at(-normal, Vector3.UP)
	var offset := float(sample["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET + 12.0 - local.position.z
	var transform := Transform3D(basis, sample["pos"] + normal * offset)
	var path := MODEL_DIRECTORY + id + ".glb" if id != "habitation_workshop" else "res://assets/city/candidates/habitation_workshop.glb"
	if not _place_model(path, transform, id):
		return
	_building_count += 1
	var center := local.get_center()
	for level: float in [0.25, 0.55, 0.8]:
		_lamp(transform * Vector3(center.x - local.size.x * 0.12, maxf(3.0, local.size.y * level), local.position.z + 2.0), Color("ffc17c"), 4.0, 21.0, level == 0.25)
	_lamp(transform * Vector3(local.position.x - 2.0, 7.0, center.z), Color("44c6dd"), 2.5, 24.0)
	for index in 2:
		var prop_id := "cargo_crate" if index == 0 else "service_cabinet"
		var prop_offset := Vector3(center.x + local.size.x * (-0.43 if index == 0 else 0.43), 0.0, local.position.z - 4.0)
		_place_model("res://assets/city/kit/" + prop_id + ".glb", transform * Transform3D(Basis.IDENTITY, prop_offset), id + ":" + prop_id)


func _place_model(path: String, transform: Transform3D, id: String) -> bool:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Cannot load neighborhood model: " + path)
		_fail += 1
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		push_error("Neighborhood model root is not Node3D: " + path)
		_fail += 1
		return false
	model.transform = transform
	_world.add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	var first := true
	var box := AABB()
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null:
			continue
		var actual: AABB = mesh.global_transform * mesh.get_aabb()
		box = actual if first else box.merge(actual)
		first = false
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if colors is PackedColorArray and not colors.is_empty() and material != null and not material.vertex_color_use_as_albedo:
				material = material.duplicate() as BaseMaterial3D
				material.vertex_color_use_as_albedo = true
				mesh.set_surface_override_material(surface, material)
	if first or CityScenery.road_clearance(box, _course) < CityScenery.ROAD_CLEARANCE:
		push_error("Neighborhood study model has missing geometry or insufficient road clearance: " + id)
		_fail += 1
		model.free()
		return false
	var footprint := AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 1.0, box.size.z)).grow(0.3)
	for previous: AABB in _boxes:
		var other := AABB(Vector3(previous.position.x, 0.0, previous.position.z), Vector3(previous.size.x, 1.0, previous.size.z))
		if footprint.intersects(other):
			push_error("Neighborhood study footprints overlap: " + id)
			_fail += 1
			model.free()
			return false
	_overview = box if _boxes.is_empty() else _overview.merge(box)
	_boxes.append(box)
	print("NEIGHBORHOOD_PLACED %s clearance=%.2f bounds=%s" % [id, CityScenery.road_clearance(box, _course), box])
	return true


func _lamp(position: Vector3, color: Color, energy: float, radius: float, shadows: bool = false) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = position
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = radius
	lamp.shadow_enabled = shadows
	_world.add_child(lamp)
	_lamps.append(lamp)


func _valid_bounds(raw: Variant) -> bool:
	if not raw is Dictionary or not raw.get("min") is Array or not raw.get("max") is Array:
		return false
	if raw["min"].size() != 3 or raw["max"].size() != 3:
		return false
	for component: Variant in raw["min"] + raw["max"]:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
	for axis in 3:
		if float(raw["max"][axis]) <= float(raw["min"][axis]):
			return false
	return true


func _views() -> void:
	var studio := TrackMaterials.environment()
	studio.fog_enabled = false
	studio.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	studio.ambient_light_color = Color("aab5c9")
	studio.ambient_light_energy = 0.35
	_environment.environment = studio
	for lamp: Light3D in _lamps:
		lamp.visible = false
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	key.light_energy = 1.0
	key.shadow_enabled = true
	add_child(key)
	_camera.position = _overview.get_center() + Vector3(-0.75, 0.9, 0.6).normalized() * _overview.size.length() * 0.9
	_camera.look_at(_overview.get_center(), Vector3.UP)
	await _capture("neighborhood-overview-studio")
	_view_along(85.0, false)
	await _capture("neighborhood-street-studio")
	key.free()
	_environment.environment = TrackMaterials.environment()
	_environment.environment.ambient_light_energy = 0.0
	for lamp: Light3D in _lamps:
		lamp.visible = true
	var headlight := OmniLight3D.new()
	headlight.light_energy = 2.0
	headlight.omni_range = 45.0
	_camera.add_child(headlight)
	for distance: float in [0.0, 80.0, 170.0]:
		_view_along(distance, false)
		await _capture("neighborhood-night-%03d" % int(distance))
	_view_along(245.0, true)
	await _capture("neighborhood-night-reverse")


func _view_along(distance: float, reverse: bool) -> void:
	var at := CityDistrict.sample(_course, distance)
	var ahead := CityDistrict.sample(_course, maxf(0.0, distance + (-55.0 if reverse else 55.0)))
	_camera.position = at["pos"] + Vector3.UP * 1.6
	_camera.look_at(ahead["pos"] + Vector3.UP * 2.0, Vector3.UP)


func _capture(label: String) -> void:
	for frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	var path := _capture_directory.path_join(label + ".png")
	if frame == null or frame.save_png(path) != OK:
		_fail += 1
		push_error("Cannot save neighborhood review capture: " + path)
	print("NEIGHBORHOOD_CAPTURE ", path)
