class_name CityRealismCatalog
extends RefCounted

const DIRECTORY := "res://assets/city/realism/"
const MANIFEST := DIRECTORY + "city_families_manifest.json"
const FAMILIES: Array[String] = ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot", "redline_shop", "row_workshop", "utility_substation", "transit_depot"]
const STREETS: Array[String] = ["sidewalk_panel", "curb_segment", "drain_cover", "street_lamp", "bollard", "bench_planter", "refuse_station", "alley_conduit"]
const GROUND_DIRECTORY := "res://assets/city/ground/"
const GROUND_CAPS := {"road_apron": 24, "service_lane": 40, "loading_yard": 64, "utility_verge": 64}
const GROUND: Array[String] = ["road_apron", "service_lane", "loading_yard", "utility_verge"]
static var entries: Dictionary = {}
static var materials: Dictionary = {}
static var meshes: Dictionary = {}
static var costs: Dictionary = {}
static var error := ""


static func available() -> bool:
	if not entries.is_empty():
		return true
	error = ""
	if not FileAccess.file_exists(MANIFEST):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary or not IndustrialMarketBenchmark.is_number(data.get("version")) or data.get("version") != 2 or not data.get("assets") is Array:
		return _fail("Invalid city realism manifest")
	var library: Variant = data.get("materials", {})
	var definitions: Array = []
	if library is Dictionary:
		for key: String in library:
			if not library[key] is Dictionary:
				return _fail("Invalid city material library")
			var definition: Dictionary = library[key].duplicate()
			definition["id"] = key
			definitions.append(definition)
	var prepared := {}
	for definition: Variant in definitions:
		if not definition is Dictionary:
			return _fail("Invalid city material definition")
		var id := String(definition.get("id", definition.get("name", "")))
		if id.is_empty() or prepared.has(id):
			return _fail("Missing or duplicate city material id")
		var material := _material(id, definition)
		if material == null:
			return false
		prepared[id] = material
	var catalog := {}
	for raw: Variant in data["assets"]:
		if not raw is Dictionary or not raw.get("id") is String or not _safe_path(raw.get("glb")):
			return _fail("Invalid city asset entry")
		if catalog.has(raw["id"]):
			return _fail("Duplicate city asset id")
		catalog[raw["id"]] = raw
	for id: String in FAMILIES:
		if not catalog.has(id) or not _safe_path(catalog[id].get("lod1_glb")):
			return _fail("Missing city family or silhouette: " + id)
	for id: String in STREETS:
		if not catalog.has(id):
			return _fail("Missing city street piece: " + id)
	materials = prepared
	for id: String in catalog:
		var entry: Dictionary = catalog[id]
		for far: bool in ([false, true] if id in FAMILIES else [false]):
			var key := id + ("@far" if far else "")
			var path: String = entry["lod1_glb" if far else "glb"]
			var mesh := _load_mesh(DIRECTORY + path)
			if mesh == null:
				materials.clear()
				meshes.clear()
				costs.clear()
				return false
			meshes[key] = mesh
			var names: Array[String] = []
			for surface in mesh.get_surface_count():
				names.append(mesh.surface_get_material(surface).resource_name)
			costs[key] = {"tris": IndustrialMarketBenchmark.count_triangles(mesh), "surfaces": mesh.get_surface_count(), "materials": names}
	entries = catalog
	_load_ground()
	return true


static func ground_available() -> bool:
	return GROUND.all(func(id: String) -> bool: return entries.has(id) and meshes.has(id) and costs.has(id))


static func _load_ground() -> void:
	var path := GROUND_DIRECTORY + "city_ground_manifest.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not IndustrialMarketBenchmark.is_number(data.get("version")) or data["version"] != 1 or not data.get("assets") is Array:
		return
	var additions := {}
	for raw: Variant in data["assets"]:
		if not raw is Dictionary or not raw.get("id") is String or raw["id"] not in GROUND or additions.has(raw["id"]) or raw.get("glb") != raw["id"] + ".glb":
			return
		additions[raw["id"]] = raw
	if additions.size() != GROUND.size():
		return
	var prepared := {}
	for id: String in GROUND:
		var mesh := _load_mesh(GROUND_DIRECTORY + String(additions[id]["glb"]))
		if mesh == null:
			push_warning("Optional ground kit unavailable: " + error)
			error = ""
			return
		var box := mesh.get_aabb()
		var depth := 3.8 if id == "road_apron" else 10.0 if id == "service_lane" else 14.0
		var centred := absf(box.position.x + 8.05) < 0.02 and absf(box.end.x - 8.05) < 0.02 and absf(box.position.z + depth * 0.5) < 0.02 and absf(box.end.z - depth * 0.5) < 0.02
		if not centred or not box.position.is_finite() or not box.size.is_finite() or box.size.x < 0.01 or box.size.z < 0.01 or box.position.y < -0.001 or box.end.y > 0.035 or mesh.get_surface_count() > 3 or IndustrialMarketBenchmark.count_triangles(mesh) > GROUND_CAPS[id]:
			return
		prepared[id] = mesh
	for id: String in GROUND:
		var mesh: ArrayMesh = prepared[id]
		var names: Array[String] = []
		for surface in mesh.get_surface_count():
			names.append(mesh.surface_get_material(surface).resource_name)
		entries[id] = additions[id]
		meshes[id] = mesh
		costs[id] = {"tris": IndustrialMarketBenchmark.count_triangles(mesh), "surfaces": mesh.get_surface_count(), "materials": names}


static func _safe_path(value: Variant) -> bool:
	return value is String and not value.is_empty() and not value.is_absolute_path() and not ":" in value and not "\\" in value and not ".." in value.split("/")


static func _material(id: String, definition: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = id
	material.vertex_color_use_as_albedo = true
	var raw: Variant = definition.get("factors", {})
	if not raw is Dictionary or CityRealism._vector(raw.get("base_color")) == Vector3.INF:
		_fail("Invalid city material factors: " + id)
		return null
	var factors: Dictionary = raw
	for value: Variant in [factors.get("roughness"), factors.get("metallic"), definition.get("normal_strength", 0.5)]:
		if not IndustrialMarketBenchmark.is_number(value):
			_fail("Invalid city material strength: " + id)
			return null
	var base: Array = factors["base_color"]
	material.albedo_color = Color(base[0], base[1], base[2])
	material.roughness = float(factors.get("roughness", 1.0))
	material.metallic = float(factors.get("metallic", 0.0))
	for slot: String in ["albedo", "orm", "normal", "emissive"]:
		if not definition.has(slot):
			continue
		var path: Variant = definition[slot]
		if not _safe_path(path) or not ResourceLoader.exists(DIRECTORY + String(path)):
			_fail("Missing shared city texture: " + id + "/" + slot)
			return null
		var texture := load(DIRECTORY + String(path)) as Texture2D
		if texture == null:
			_fail("Unreadable shared city texture: " + id + "/" + slot)
			return null
		match slot:
			"albedo":
				material.albedo_texture = texture
				material.albedo_color = Color.WHITE
			"orm":
				material.roughness = 1.0
				material.metallic = 1.0
				material.roughness_texture = texture
				material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				material.metallic_texture = texture
				material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
				material.ao_enabled = true
				material.ao_texture = texture
				material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			"normal":
				material.normal_enabled = true
				material.normal_texture = texture
				material.normal_scale = float(definition.get("normal_strength", 0.5))
			"emissive":
				if id == "sign_atlas":
					material.emission_texture = texture
	if id in ["sign_atlas", "lamp_glass"]:
		material.emission_enabled = true
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission = material.albedo_color
		material.emission_energy_multiplier = float(definition.get("emission", {}).get("strength", 2.0))
	return material


static func _load_mesh(path: String) -> ArrayMesh:
	if not ResourceLoader.exists(path):
		_fail("Missing converted city GLB: " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("Unreadable city GLB: " + path)
		return null
	var source := packed.instantiate()
	if not source.find_children("*", "CollisionObject3D", true, false).is_empty() or not source.find_children("*", "Light3D", true, false).is_empty():
		source.free()
		_fail("City assets must contain visual geometry only")
		return null
	var records: Array[Dictionary] = []
	CityKit.collect_static_meshes(source, Transform3D.IDENTITY, records)
	var mesh := ArrayMesh.new()
	for record: Dictionary in records:
		var original: Mesh = record["mesh"]
		for surface in original.get_surface_count():
			var source_material := original.surface_get_material(surface)
			if source_material == null or not materials.has(source_material.resource_name):
				source.free()
				_fail("Unbound city material in " + path)
				return null
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.append_from(original, surface, record["transform"])
			tool.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[source_material.resource_name])
	source.free()
	if mesh.get_surface_count() == 0:
		_fail("Empty converted city asset")
		return null
	return mesh


static func _fail(message: String) -> bool:
	error = message
	return false
