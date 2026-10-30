class_name CityRealismCatalog
extends RefCounted

const DIRECTORY := "res://assets/city/realism/"
const MANIFEST := DIRECTORY + "city_families_manifest.json"
const FAMILIES: Array[String] = ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot", "redline_shop", "row_workshop", "utility_substation", "transit_depot"]
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
	if not data is Dictionary or data.get("version") != 2 or not data.get("assets") is Array:
		return _fail("Invalid city realism manifest")
	var library: Variant = data.get("materials", {})
	var definitions: Array = library.values() if library is Dictionary else library if library is Array else []
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
				return false
			meshes[key] = mesh
			costs[key] = {"tris": IndustrialMarketBenchmark.count_triangles(mesh), "surfaces": mesh.get_surface_count()}
	entries = catalog
	return true


static func _safe_path(value: Variant) -> bool:
	return value is String and not value.is_empty() and not value.is_absolute_path() and not ":" in value and not "\\" in value and not ".." in value.split("/")


static func _material(id: String, definition: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = id
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic = 1.0
	var textures: Dictionary = definition.get("textures", definition)
	for slot: String in ["albedo", "orm", "normal"]:
		var path: Variant = textures.get(slot)
		if not _safe_path(path) or not ResourceLoader.exists(DIRECTORY + String(path)):
			_fail("Missing shared city texture: " + id + "/" + slot)
			return null
		var texture := load(DIRECTORY + String(path)) as Texture2D
		if texture == null:
			_fail("Unreadable shared city texture: " + id + "/" + slot)
			return null
		match slot:
			"albedo": material.albedo_texture = texture
			"orm":
				material.roughness_texture = texture
				material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				material.metallic_texture = texture
				material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			"normal":
				material.normal_enabled = true
				material.normal_texture = texture
				material.normal_scale = float(definition.get("normal_strength", 0.5))
	if id in ["sign_atlas", "lamp_glass"]:
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_texture = material.albedo_texture
		material.emission_energy_multiplier = float(definition.get("emission_strength", 2.0))
	return material


static func _load_mesh(path: String) -> ArrayMesh:
	if not ResourceLoader.exists(path):
		_fail("Missing converted city GLB: " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
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
