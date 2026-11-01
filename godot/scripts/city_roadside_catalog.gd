## Roadside detail library: landmark overlays, two skyscrapers (+LOD1), board overlays, camps and burning barrels.
## Geometry-only GLBs bound to the same canonical material library as the converted city (CityRealismCatalog), so nothing here adds a texture.
## Every group is optional: a missing or invalid file leaves that group unavailable and the rest of the city builds exactly as before.
class_name CityRoadsideCatalog
extends RefCounted

const DIRECTORY := "res://assets/city/roadside/"
const MANIFEST := DIRECTORY + "roadside_manifest.json"
const LANDMARKS: Array[String] = ["exchange_hall", "pump_citadel"]
const TOWERS: Array[String] = ["tower_a", "tower_b"]
const CAMPS: Array[String] = ["camp_a", "camp_b", "camp_c", "camp_d"]
const BARRELS: Array[String] = ["barrel_fire_a", "barrel_fire_b"]
const BOARD_FAMILIES: Array[String] = ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot", "row_workshop", "utility_substation", "transit_depot"]
## Per-asset triangle ceilings; the measured library sits well inside them.
const TRIANGLE_CAPS := {"landmark": 40000, "tower": 70000, "tower_lod1": 9000, "boards": 20000, "camp": 6000, "barrel": 3000}
const KIT_DIRECTORY := "res://assets/city/kit/"
static var entries: Dictionary = {}
static var meshes: Dictionary = {}
static var costs: Dictionary = {}
static var protected_hashes: Dictionary = {}
static var error := ""
## Test hook: makes the whole optional library appear missing so the clean fallback can be rehearsed.
static var disabled := false


static func asset_ids() -> Array[String]:
	var ids: Array[String] = []
	for landmark in LANDMARKS:
		ids.append(landmark + "_detail")
	for id in TOWERS:
		ids.append(id)
		ids.append(id + "_lod1")
	for id in CAMPS + BARRELS:
		ids.append(id)
	for family in BOARD_FAMILIES:
		ids.append("boards_" + family)
	return ids


## True when the manifest and every library asset loaded; individual groups can still be queried with has_group.
static func available() -> bool:
	if disabled:
		return false
	if not entries.is_empty():
		return true
	error = ""
	if not CityRealismCatalog.available():
		error = "Converted city library is unavailable"
		return false
	if not FileAccess.file_exists(MANIFEST):
		error = "Roadside manifest is missing"
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary or not IndustrialMarketBenchmark.is_number(data.get("version")) or data["version"] != 1 or not data.get("assets") is Dictionary:
		error = "Invalid roadside manifest"
		return false
	var loaded := {}
	var loaded_meshes := {}
	var loaded_costs := {}
	for id: String in asset_ids():
		var raw: Variant = data["assets"].get(id)
		if not raw is Dictionary or raw.get("glb") != id + ".glb" or not CityRealismCatalog._safe_path(raw.get("glb")):
			push_warning("Roadside asset missing from manifest: " + id)
			continue
		var cap: int = TRIANGLE_CAPS[_role(id)]
		var mesh := CityRealismCatalog._load_mesh(DIRECTORY + String(raw["glb"]))
		if mesh == null:
			push_warning("Roadside asset unavailable: " + id + " (" + CityRealismCatalog.error + ")")
			CityRealismCatalog.error = ""
			continue
		var tris := IndustrialMarketBenchmark.count_triangles(mesh)
		var box := mesh.get_aabb()
		if tris <= 0 or tris > cap or not box.position.is_finite() or not box.size.is_finite() or box.size.length() < 0.5:
			push_warning("Roadside asset exceeds its contract: " + id)
			continue
		var names: Array[String] = []
		for surface in mesh.get_surface_count():
			names.append(mesh.surface_get_material(surface).resource_name)
		loaded[id] = raw
		loaded_meshes[id] = mesh
		loaded_costs[id] = {"tris": tris, "surfaces": mesh.get_surface_count(), "materials": names}
	if loaded.is_empty():
		error = "No roadside asset could be loaded"
		return false
	protected_hashes = data.get("protected_sources", {})
	meshes = loaded_meshes
	costs = loaded_costs
	entries = loaded
	return true


static func _role(id: String) -> String:
	if id.ends_with("_detail"):
		return "landmark"
	if id.ends_with("_lod1"):
		return "tower_lod1"
	if id.begins_with("tower_"):
		return "tower"
	if id.begins_with("boards_"):
		return "boards"
	return "camp" if id.begins_with("camp_") else "barrel"


## A group is usable only when all of its assets loaded.
static func has_group(group: String) -> bool:
	var ids: Array[String] = []
	match group:
		"landmarks":
			for id in LANDMARKS:
				ids.append(id + "_detail")
		"towers":
			for id in TOWERS:
				ids.append(id)
				ids.append(id + "_lod1")
		"camps":
			ids.assign(CAMPS)
		"barrels":
			ids.assign(BARRELS)
		"boards":
			for family in BOARD_FAMILIES:
				ids.append("boards_" + family)
	return not ids.is_empty() and ids.all(func(id: String) -> bool: return meshes.has(id))


static func bounds(id: String) -> AABB:
	return (meshes[id] as Mesh).get_aabb() if meshes.has(id) else AABB()


static func fire_anchor(id: String) -> Dictionary:
	var fire: Variant = entries.get(id, {}).get("fire")
	return fire if fire is Dictionary else {}


## Test hook: drop everything so a fallback can be rehearsed (the next available() reloads).
static func reset() -> void:
	entries = {}
	meshes = {}
	costs = {}
	protected_hashes = {}
	error = ""
