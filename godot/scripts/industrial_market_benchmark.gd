class_name IndustrialMarketBenchmark
extends Node3D

const DIRECTORY := "res://assets/city/candidates/industrial_market/"
const MANIFEST := DIRECTORY + "benchmark_manifest.json"
const IDS: Array[String] = ["redline_shop", "ramen_vendor", "ramen_customer"]
# Candidate-only limits; the unchanged catalog vehicle is measured separately.
const TRIANGLE_CAP := 120000
const SURFACE_CAP := 20

var errors: Array[String] = []
var manifest: Dictionary = {}
var models: Dictionary = {}
var mesh_bounds: Dictionary = {}
var reference_vehicle: Vehicle
var vehicle_bounds := AABB()
var triangle_count := 0
var surface_count := 0
var vehicle_triangle_count := 0
var vehicle_surface_count := 0


func build() -> bool:
	if not get_children().is_empty():
		return _fail("Benchmark must be built into an empty node")
	if not FileAccess.file_exists(MANIFEST):
		return _fail("Industrial market assets have not been generated")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var issues := manifest_errors(raw)
	if not issues.is_empty():
		errors.append_array(issues)
		return false
	manifest = raw
	for placement: Variant in manifest["placements"]:
		var id: String = placement["asset"]
		if not ResourceLoader.exists(DIRECTORY + id + ".glb"):
			return _fail("Missing benchmark asset: " + id)
		var packed := load(DIRECTORY + id + ".glb") as PackedScene
		if packed == null:
			return _fail("Cannot load benchmark asset: " + id)
		var model := packed.instantiate() as Node3D
		if model == null:
			return _fail("Benchmark asset must have a spatial root: " + id)
		model.name = id
		var position_data: Array = placement["position"]
		model.position = Vector3(position_data[0], position_data[1], position_data[2])
		model.rotation.y = deg_to_rad(float(placement["yaw_degrees"]))
		add_child(model)
		if not model.find_children("*", "CollisionObject3D", true, false).is_empty() or not model.find_children("*", "Light3D", true, false).is_empty():
			return _fail("Benchmark assets must contain visual geometry only: " + id)
		var found: Array[Dictionary] = []
		CityKit.collect_static_meshes(model, Transform3D.IDENTITY, found)
		if found.is_empty():
			return _fail("Benchmark asset has no mesh: " + id)
		var first := true
		var bounds := AABB()
		for record: Dictionary in found:
			var mesh: Mesh = record["mesh"]
			var box: AABB = record["transform"] * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			triangle_count += count_triangles(mesh)
			surface_count += mesh.get_surface_count()
		var instances := model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			instances.append(model)
		for instance: MeshInstance3D in instances:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_skin_materials(instance)
		models[id] = model
		mesh_bounds[id] = bounds
	if models.size() != IDS.size() or triangle_count > TRIANGLE_CAP or surface_count > SURFACE_CAP:
		return _fail("Incomplete or over-budget industrial market")
	_add_vehicle()
	return true


func _add_vehicle() -> void:
	var spec := VehicleCatalog.get_vehicle("blackjack")
	spec["customization"] = VehicleCatalog.default_customization("blackjack")
	reference_vehicle = preload("res://scripts/vehicle_factory.gd").create(spec)
	reference_vehicle.name = "ReferenceBlackjackX17"
	reference_vehicle.tuning = TuningProfile.new()
	reference_vehicle.freeze = true
	reference_vehicle.collision_layer = 0
	reference_vehicle.collision_mask = 0
	reference_vehicle.process_mode = Node.PROCESS_MODE_DISABLED
	reference_vehicle.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reference_vehicle.rotation.y = PI * 0.5
	if reference_vehicle.has_method("configure_static_preview"):
		reference_vehicle.call("configure_static_preview")
	reference_vehicle.position += Vector3(-3.0, 0.0, -7.5)
	add_child(reference_vehicle)
	for body: CollisionObject3D in reference_vehicle.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0
	for shape: CollisionShape3D in reference_vehicle.find_children("*", "CollisionShape3D", true, false):
		shape.disabled = true
	for ray: RayCast3D in reference_vehicle.find_children("*", "RayCast3D", true, false):
		ray.enabled = false
	for player: Node in reference_vehicle.find_children("*", "", true, false):
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
			player.call("stop")
	var first := true
	for mesh: MeshInstance3D in reference_vehicle.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		vehicle_triangle_count += count_triangles(mesh.mesh)
		vehicle_surface_count += mesh.mesh.get_surface_count()
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point := mesh.global_transform * vertex
				vehicle_bounds = AABB(point, Vector3.ZERO) if first else vehicle_bounds.expand(point)
				first = false
	set_meta("vehicle_reference", {"id": "blackjack", "rig": spec["visual"]["rig"], "scene": spec["visual"]["scene"], "customization": spec["customization"]})


func _skin_materials(instance: MeshInstance3D) -> void:
	if instance.mesh == null:
		return
	for surface in instance.mesh.get_surface_count():
		var material := instance.get_active_material(surface) as BaseMaterial3D
		if material == null or not "skin" in material.resource_name.to_lower():
			continue
		var skin := material.duplicate() as BaseMaterial3D
		skin.subsurf_scatter_enabled = true
		skin.subsurf_scatter_skin_mode = true
		skin.subsurf_scatter_strength = 0.08
		instance.set_surface_override_material(surface, skin)


func target(key: String) -> Vector3:
	var raw: Variant = manifest["review_targets"][key]
	if raw is Dictionary:
		raw = raw.get("cladding_main", raw.values()[0])
	var value: Array = raw
	return Vector3(value[0], value[1], value[2])


static func is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) < 1000.0


static func manifest_errors(value: Variant) -> Array[String]:
	if not value is Dictionary or value.get("version") != 1 or not value.get("assets") is Array or not value.get("placements") is Array:
		return ["Invalid industrial market manifest"]
	var assets := {}
	for entry: Variant in value["assets"]:
		if not entry is Dictionary or not entry.get("id") is String or entry["id"] not in IDS or assets.has(entry["id"]):
			return ["Invalid or duplicate benchmark asset id"]
		if entry.get("glb") != entry["id"] + ".glb":
			return ["Benchmark GLBs must use their approved plain filenames"]
		assets[entry["id"]] = true
	if assets.size() != IDS.size():
		return ["Benchmark requires the shop, vendor and customer"]
	var placed := {}
	for placement: Variant in value["placements"]:
		if not placement is Dictionary or placement.get("asset") not in IDS or placed.has(placement["asset"]):
			return ["Invalid or duplicate benchmark placement"]
		if not is_vector(placement.get("position")) or not is_number(placement.get("yaw_degrees")):
			return ["Benchmark placement requires a finite position and yaw"]
		placed[placement["asset"]] = true
	if placed.size() != IDS.size():
		return ["Benchmark requires all three placements"]
	var targets: Variant = value.get("review_targets")
	if not targets is Dictionary:
		return ["Benchmark requires review targets"]
	for key: String in ["counter", "vendor_face", "customer_face", "support", "sign"]:
		if not is_vector(targets.get(key)):
			return ["Missing or invalid benchmark review target: " + key]
	var material_targets: Variant = targets.get("materials")
	if not material_targets is Dictionary or material_targets.is_empty() or not material_targets.values().all(is_vector):
		return ["Benchmark requires finite material inspection targets"]
	return []


static func is_vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(is_number)


static func count_triangles(mesh: Mesh) -> int:
	var result := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		result += indices.size() / 3 if indices is PackedInt32Array and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
	return result


func _fail(message: String) -> bool:
	errors.append(message)
	return false
