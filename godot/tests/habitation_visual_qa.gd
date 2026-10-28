# Manual art-review captures. Success confirms geometry and image output, not artistic quality.
extends Node3D

const MODEL := "res://assets/city/candidates/habitation_workshop.glb"
var _camera: Camera3D
var _environment: WorldEnvironment
var _box := AABB()
var _directory := ""
var _fail := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Habitation visual QA requires a rendering device")
		get_tree().quit(1)
		return
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var folder := "city-habitation-baseline" if baseline else "city-habitation"
	_directory = ProjectSettings.globalize_path("res://").path_join("../.ai/captures/" + folder).simplify_path()
	var directory_error := DirAccess.make_dir_recursive_absolute(_directory)
	if directory_error != OK:
		push_error("Cannot create capture directory %s: %s" % [_directory, error_string(directory_error)])
		get_tree().quit(1)
		return
	var model_path := "res://assets/city/kit/shutter_workshop.glb" if baseline else MODEL
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("Cannot load habitation review model: " + model_path)
		get_tree().quit(1)
		return
	var model := packed.instantiate() as Node3D
	add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	var first := true
	var triangles := 0
	var colored_vertices := 0
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null:
			push_error("Review model contains an empty MeshInstance3D: " + String(mesh.name))
			_fail += 1
			continue
		var world: AABB = mesh.global_transform * mesh.get_aabb()
		_box = world if first else _box.merge(world)
		first = false
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3 if indices is PackedInt32Array and not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			if colors is PackedColorArray and not colors.is_empty():
				colored_vertices += colors.size()
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				if material != null and not material.vertex_color_use_as_albedo:
					push_error("Imported material discards authored vertex-color detail")
					_fail += 1
	if first or triangles <= 0 or triangles > 30000:
		push_error("Habitation candidate geometry is missing or over budget")
		get_tree().quit(1)
		return
	print("HABITATION_GEOMETRY meshes=%d triangles=%d colored_vertices=%d bounds=%s" % [meshes.size(), triangles, colored_vertices, _box])
	_environment = WorldEnvironment.new()
	add_child(_environment)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = 48.0
	_camera.far = 500.0
	add_child(_camera)
	_camera.current = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(_box.size.x, _box.size.z) * 4.0
	ground.mesh = plane
	ground.position = Vector3(_box.get_center().x, -0.03, _box.get_center().z)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("161a20")
	ground_material.roughness = 0.9
	ground.material_override = ground_material
	add_child(ground)
	await _studio()
	await _night()
	print("HABITATION_VISUAL_QA failures=%d" % _fail)
	get_tree().quit(1 if _fail else 0)


func _studio() -> void:
	var environment := TrackMaterials.environment()
	environment.fog_enabled = false
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("242a33")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aab5c9")
	environment.ambient_light_energy = 0.3
	_environment.environment = environment
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	key.light_energy = 1.15
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 150.0, 0.0)
	fill.light_color = Color("bacade")
	fill.light_energy = 0.35
	add_child(fill)
	_fit(Vector3(0.9, 0.5, -1.0))
	await _capture("studio-front")
	_fit(Vector3(-0.9, 0.5, 1.0))
	await _capture("studio-rear")
	_fit(Vector3(0.3, 1.4, -0.5))
	await _capture("studio-roof")
	_street()
	await _capture("studio-street-1.6m")
	var front_z := _box.position.z
	var center := _box.get_center()
	var entry := Vector3(center.x + _box.size.x * 0.27, 3.0, front_z)
	_camera.position = entry + Vector3(4.0, 1.0, -9.0)
	_camera.look_at(entry, Vector3.UP)
	await _capture("studio-entry-detail")
	var habitation := Vector3(center.x - _box.size.x * 0.1, _box.size.y * 0.67, front_z + 1.0)
	_camera.position = habitation + Vector3(-5.0, 1.0, -11.0)
	_camera.look_at(habitation, Vector3.UP)
	await _capture("studio-habitation-detail")
	key.free()
	fill.free()


func _night() -> void:
	_environment.environment = TrackMaterials.environment()
	var center := _box.get_center()
	for side: float in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(center.x + side * _box.size.x * 0.3, 6.5, _box.position.z - 2.0)
		lamp.light_color = Color("ffb35c")
		lamp.light_energy = 3.0
		lamp.omni_range = 27.0
		lamp.shadow_enabled = true
		add_child(lamp)
	var service := OmniLight3D.new()
	service.position = Vector3(_box.position.x - 3.0, 8.0, center.z)
	service.light_color = Color("44c6dd")
	service.light_energy = 2.4
	service.omni_range = 24.0
	service.shadow_enabled = true
	add_child(service)
	var headlight := OmniLight3D.new()
	headlight.light_energy = 2.0
	headlight.omni_range = 45.0
	_camera.add_child(headlight)
	print("QA_NIGHT project environment; three local yard lamps plus camera headlight; no ambient or sun")
	_street()
	await _capture("night-street-1.6m")
	_fit(Vector3(0.9, 0.4, -1.0))
	await _capture("night-front")
	_fit(Vector3(-0.9, 0.4, 1.0))
	await _capture("night-service")


func _fit(direction: Vector3) -> void:
	direction = direction.normalized()
	var orientation := Basis.looking_at(-direction, Vector3.UP)
	var tangent := tan(deg_to_rad(_camera.fov * 0.5))
	var aspect := float(get_viewport().get_visible_rect().size.x) / get_viewport().get_visible_rect().size.y
	var distance := 0.0
	for i in 8:
		var local: Vector3 = orientation.transposed() * (_box.get_endpoint(i) - _box.get_center())
		distance = maxf(distance, local.z + maxf(absf(local.y) / tangent, absf(local.x) / (tangent * aspect)))
	_camera.position = _box.get_center() + direction * distance * 1.12
	_camera.look_at(_box.get_center(), Vector3.UP)


func _street() -> void:
	_camera.position = Vector3(_box.get_center().x + _box.size.x * 0.45, 1.6, _box.position.z - _box.size.x * 1.3)
	_camera.look_at(Vector3(_box.get_center().x, _box.size.y * 0.35, _box.get_center().z), Vector3.UP)


func _capture(label: String) -> void:
	for frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _directory.path_join(label + ".png")
	var frame := get_viewport().get_texture().get_image()
	if frame == null or frame.save_png(path) != OK:
		_fail += 1
		push_error("Cannot save habitation review capture: " + path)
	print("HABITATION_CAPTURE ", path)
