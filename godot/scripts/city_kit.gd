class_name CityKit
extends RefCounted

const DIRECTORY := "res://assets/city/kit/"
const MANIFEST := DIRECTORY + "city_kit_manifest.json"
const SURFACE_SHADER := preload("res://shaders/city_kit.gdshader")
const EXPECTED_IDS: Array[String] = ["relay_tower", "exchange_hall", "pump_citadel", "shutter_workshop", "utility_midrise", "ribbed_stack", "pipe_rack", "exhaust_stack", "service_cabinet", "transformer", "cargo_crate", "barrier_segment", "beacon_post", "conduit_pillar"]
const COLORS := {"steel": "3a4652", "ceramic": "b8b09a", "cavity": "050508", "machinery": "404b54", "trim": "8d928c"}
static var _entries: Dictionary = {}
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _loaded := false


static func is_available() -> bool:
	var catalog := entries()
	if catalog.size() != EXPECTED_IDS.size():
		return false
	for id: String in EXPECTED_IDS:
		if not catalog.has(id) or mesh(id) == null:
			return false
	return true


static func entries() -> Dictionary:
	if not _loaded:
		_loaded = true
		if not FileAccess.file_exists(MANIFEST):
			push_error("City kit manifest is missing: " + MANIFEST)
			return {}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if not data is Dictionary or data.get("version") != 1 or not data.get("assets") is Array:
			push_error("City kit manifest is invalid")
			return {}
		for item: Variant in data["assets"]:
			if not item is Dictionary or not item.get("id") is String or not item.get("surfaces") is Array or not item.get("aabb") is Dictionary or not item.get("glb") is String:
				push_error("City kit manifest contains an invalid asset")
				_entries.clear()
				return {}
			_entries[item["id"]] = item
	return _entries.duplicate(true)


static func bounds(id: String) -> AABB:
	if not _loaded:
		entries()
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return AABB()
	var low: Array = entry["aabb"]["min"]
	var high: Array = entry["aabb"]["max"]
	var origin := Vector3(float(low[0]), float(low[1]), float(low[2]))
	return AABB(origin, Vector3(float(high[0]), float(high[1]), float(high[2])) - origin)


static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	if not _loaded:
		entries()
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		push_error("Unknown city kit asset: " + id)
		_meshes[id] = null
		return null
	var packed := load(DIRECTORY + String(entry["glb"])) as PackedScene
	if packed == null:
		push_error("Could not load city asset: " + id)
		_meshes[id] = null
		return null
	var scene := packed.instantiate()
	var found: Array[Dictionary] = []
	_collect_meshes(scene, Transform3D.IDENTITY, found)
	if found.size() != 1:
		push_error("City asset must contain one static mesh: " + id)
		scene.free()
		_meshes[id] = null
		return null
	var source: Mesh = found[0]["mesh"]
	if entry["surfaces"].size() != source.get_surface_count():
		push_error("City asset surface manifest does not match mesh: " + id)
		scene.free()
		_meshes[id] = null
		return null
	var transform: Transform3D = found[0]["transform"]
	var combined := source.duplicate(true) as ArrayMesh
	if combined == null:
		push_error("City asset requires an ArrayMesh: " + id)
		scene.free()
		_meshes[id] = null
		return null
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		combined = ArrayMesh.new()
		for i in source.get_surface_count():
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.append_from(source, i, transform)
			tool.commit(combined)
	for i in combined.get_surface_count():
		combined.surface_set_material(i, material(String(entry["surfaces"][i])))
	combined.custom_aabb = bounds(id)
	scene.free()
	_meshes[id] = combined
	return combined


static func _collect_meshes(node: Node, parent: Transform3D, found: Array[Dictionary]) -> void:
	var transform: Transform3D = parent * (node.transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D and node.mesh != null:
		found.append({"mesh": node.mesh, "transform": transform})
	for child in node.get_children():
		_collect_meshes(child, transform, found)


static func material(semantic: String) -> Material:
	if _materials.has(semantic):
		return _materials[semantic]
	var result: Material
	if semantic in ["glow_cyan", "glow_amber"]:
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color("00f0ff") if semantic == "glow_cyan" else Color("ffb703")
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		glow.emission_enabled = true
		glow.emission = glow.albedo_color
		glow.emission_energy_multiplier = 3.0
		result = glow
	elif semantic == "sinew":
		var flesh := TrackMaterials.flesh().duplicate() as StandardMaterial3D
		flesh.cull_mode = BaseMaterial3D.CULL_DISABLED
		flesh.emission_enabled = true
		flesh.emission = Color("35100e")
		result = flesh
	else:
		var panel := ShaderMaterial.new()
		panel.shader = SURFACE_SHADER
		panel.set_shader_parameter("base_color", Color(COLORS.get(semantic, "3a4652")))
		panel.set_shader_parameter("metalness", 0.1 if semantic == "ceramic" else 0.35)
		panel.set_shader_parameter("surface_roughness", 0.48 if semantic == "trim" else 0.65)
		panel.set_shader_parameter("readability", 0.25 if semantic == "ceramic" else 0.45)
		result = panel
	_materials[semantic] = result
	return result
