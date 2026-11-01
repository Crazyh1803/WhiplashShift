## The roadside detail layer of the converted city: weathered landmarks with detail overlays, two detailed skyscrapers, boarded frontages, camps and
## burning barrels. Built after the district and before the generic backdrop; adds no lights, no collision and no textures. Original records, the 66
## frontage placements, the actor pairs and every source asset are untouched; if the optional library is missing nothing is built.
class_name CityRoadside
extends RefCounted

const WEATHER_SHADER := preload("res://shaders/city_landmark_weather.gdshader")
## Visibility windows (metres). Near detail pops out early; the tower silhouette LOD carries the skyline.
const TOWER_NEAR_END := 170.0
const TOWER_FAR_BEGIN := 160.0
const TOWER_FAR_END := 520.0
const LANDMARK_DETAIL_END := 210.0
const BOARDS_END := 140.0
const CAMP_END := 120.0
const BARREL_END := 120.0
const MARGIN := 10.0
## Add-on budgets on top of the unchanged realism budgets (CityRealismLayout.NEAR_BUDGET / SURFACE_BUDGET). The add-on is the new content only; the landmark
## base meshes are measured as their own term. Values are set from the measured library (see CityRoadside.measure and the test log), not guessed.
const ADDON_NEAR_BUDGET := 175000
const ADDON_SURFACE_BUDGET := 80
## Whole-street ceilings at one eye: realism base (<= 320k / 160) + landmark bases + the shop actors + the add-on. Measured peak 573k / 247 (see the budget log line).
const COMBINED_NEAR_BUDGET := 625000
const COMBINED_SURFACE_BUDGET := 265
const LANDMARK_RANGE := 460.0
const WEATHERED: Array[String] = ["exchange_hall", "pump_citadel", "relay_tower"]
const RUST := {"steel": 0.5, "machinery": 0.55, "trim": 0.35, "ceramic": 0.12, "cavity": 0.0}


## Returns the CityRoadside node, or null when the optional library is unavailable (the city then builds exactly as before).
static func build(parent: Node3D, input: CourseDefinition, realism: Node3D, district: Node3D) -> Node3D:
	if realism == null or district == null or not CityRoadsideCatalog.available():
		return null
	var course := input.geometry()
	var reserved: Array[AABB] = []
	reserved.assign(realism.get_meta("reserved_bounds", []))
	var extra: Array[AABB] = []
	var crown := parent.get_node_or_null("Crown") as Node3D
	if crown != null:
		extra.append(AABB(crown.position - Vector3(48.0, 0.0, 48.0), Vector3(96.0, 1.0, 96.0)))
	var layout := CityRoadsideLayout.new(course, realism.get_meta("placements", []), reserved, district.get_meta("placements", []), extra)
	layout.populate(district.get_meta("placements", []))
	var root := Node3D.new()
	root.name = "CityRoadside"
	_towers(root, layout)
	_landmarks(root, layout)
	_boards(root, layout)
	_props(root, layout, layout.camps, "Camp")
	_barrels(root, layout)
	_weather(district)
	var flat_reservations: Array[AABB] = []
	flat_reservations.assign(layout.reservations)
	root.set_meta("towers", layout.towers)
	root.set_meta("camps", layout.camps)
	root.set_meta("barrels", layout.barrels)
	root.set_meta("boards", layout.boards)
	root.set_meta("landmarks", layout.landmarks)
	root.set_meta("reserved_bounds", flat_reservations)
	root.set_meta("rejected", layout.rejected)
	root.set_meta("light_count", 0)
	parent.add_child(root)
	return root


## One MultiMeshInstance3D per placement (shared Mesh, one transform). Godot applies visibility ranges per GeometryInstance, measured to the node's merged
## bounds, so a node must never span distant placements. The explicit custom_aabb is that placement's exact world box.
static func _batch(root: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D], begin: float, end: float, kind: String, shadows: bool = false) -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for i in transforms.size():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = 1
		multimesh.set_instance_transform(0, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = label if transforms.size() == 1 else "%s_%d" % [label, i]
		instance.multimesh = multimesh
		instance.custom_aabb = world_box(transforms[i], mesh.get_aabb())
		var placed: Array[Transform3D] = [transforms[i]]
		instance.set_meta("city_transforms", placed)
		instance.set_meta("roadside_kind", kind)
		instance.set_meta("roadside_label", label)
		instance.visibility_range_begin = begin
		instance.visibility_range_end = end
		instance.visibility_range_begin_margin = MARGIN if begin > 0.0 else 0.0
		instance.visibility_range_end_margin = MARGIN
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
		nodes.append(instance)
	return nodes


## World-space box of a local box under a transform.
static func world_box(xf: Transform3D, local: AABB) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for corner in 8:
		var c := local.position + Vector3(local.size.x * float(corner & 1), local.size.y * float((corner >> 1) & 1), local.size.z * float((corner >> 2) & 1))
		var w := xf * c
		low = Vector3(minf(low.x, w.x), minf(low.y, w.y), minf(low.z, w.z))
		high = Vector3(maxf(high.x, w.x), maxf(high.y, w.y), maxf(high.z, w.z))
	return AABB(low, high - low)


static func _towers(root: Node3D, layout: CityRoadsideLayout) -> void:
	for id in CityRoadsideCatalog.TOWERS:
		var transforms: Array[Transform3D] = []
		for tower in layout.towers:
			if tower["id"] == id:
				transforms.append(tower["transform"])
		_batch(root, "Roadside_" + id, CityRoadsideCatalog.meshes[id], transforms, 0.0, TOWER_NEAR_END, "tower")
		_batch(root, "Roadside_" + id + "_lod1", CityRoadsideCatalog.meshes[id + "_lod1"], transforms, TOWER_FAR_BEGIN, TOWER_FAR_END, "tower_lod1")


static func _landmarks(root: Node3D, layout: CityRoadsideLayout) -> void:
	for placement in layout.landmarks:
		var transforms: Array[Transform3D] = [placement["transform"]]
		_batch(root, "Roadside_" + String(placement["id"]), CityRoadsideCatalog.meshes[placement["id"]], transforms, 0.0, LANDMARK_DETAIL_END, "landmark")


static func _boards(root: Node3D, layout: CityRoadsideLayout) -> void:
	for family in CityRoadsideCatalog.BOARD_FAMILIES:
		var id := "boards_" + family
		var transforms: Array[Transform3D] = []
		for board in layout.boards:
			if board["id"] == id:
				transforms.append(board["transform"])
		if CityRoadsideCatalog.meshes.has(id):
			_batch(root, "Roadside_" + id, CityRoadsideCatalog.meshes[id], transforms, 0.0, BOARDS_END, "boards")


static func _props(root: Node3D, layout: CityRoadsideLayout, placements: Array[Dictionary], label: String) -> void:
	for placement in placements:
		var transforms: Array[Transform3D] = [placement["transform"]]
		_batch(root, "Roadside_%s_%s" % [label, placement["id"]], CityRoadsideCatalog.meshes[placement["id"]], transforms, 0.0, CAMP_END, "camp")


static func _barrels(root: Node3D, layout: CityRoadsideLayout) -> void:
	var bases: Array[Vector3] = []
	var coals: Array[float] = []
	var yaws: Array[float] = []
	for id in CityRoadsideCatalog.BARRELS:
		var transforms: Array[Transform3D] = []
		for barrel in layout.barrels:
			if barrel["id"] == id:
				transforms.append(barrel["transform"])
		if not transforms.is_empty():
			_batch(root, "Roadside_" + id, CityRoadsideCatalog.meshes[id], transforms, 0.0, BARREL_END, "barrel")
	for barrel in layout.barrels:
		bases.append((barrel["transform"] as Transform3D).origin)
		coals.append(barrel["coal_height"])
		yaws.append(float(barrel["s"]) * 0.7)
	CityRoadsideFx.build(root, bases, coals, yaws)


## Converted-mode landmark treatment: the original (unmodified) kit meshes are drawn with a deterministic weathering shader instead of the clean panel look.
static func _weather(district: Node3D) -> void:
	var entries := CityKit.entries()
	for id in WEATHERED:
		var instance := district.get_node_or_null(id) as MultiMeshInstance3D
		if instance == null or not entries.has(id) or instance.multimesh.mesh == null:
			continue
		var source := instance.multimesh.mesh as ArrayMesh
		var weathered := source.duplicate() as ArrayMesh
		var surfaces: Array = entries[id]["surfaces"]
		for i in mini(weathered.get_surface_count(), surfaces.size()):
			weathered.surface_set_material(i, weather_material(String(surfaces[i])))
		instance.multimesh.mesh = weathered
		instance.set_meta("roadside_weathered", true)


static func weather_material(semantic: String) -> Material:
	var base := CityKit.material(semantic)
	if not base is ShaderMaterial:
		return base
	var material := ShaderMaterial.new()
	material.shader = WEATHER_SHADER
	for key in ["base_color", "metalness", "surface_roughness", "readability"]:
		material.set_shader_parameter(key, (base as ShaderMaterial).get_shader_parameter(key))
	material.set_shader_parameter("rust", float(RUST.get(semantic, 0.3)))
	return material


# ------------------------------------------------------------------------------------------------ measurement
## Peak visible cost over eyes every 10 m at 1.5 m. Terms are reported separately and combined at each eye: realism base (unchanged chunks), landmark
## base meshes, the add-on layer, and the two shop-actor pairs. Instance distance uses each instance's own AABB centre and its visibility window.
static func measure(scenery: Node3D, course: CourseDefinition) -> Dictionary:
	var realism := scenery.get_node_or_null("CityRealism") as Node3D
	var roadside := scenery.get_node_or_null("CityRoadside") as Node3D
	var district := scenery.get_node_or_null("CityKit") as Node3D
	var peaks := {"base_tris": 0, "base_surfaces": 0, "landmark_tris": 0, "addon_tris": 0, "addon_surfaces": 0, "actor_tris": 0, "combined_tris": 0, "combined_surfaces": 0, "eyes": 0}
	if realism == null:
		return peaks
	var base_items: Array[Dictionary] = _items(realism.find_children("*", "MultiMeshInstance3D", true, false), scenery)
	var addon_items: Array[Dictionary] = _items(roadside.find_children("*", "MultiMeshInstance3D", true, false), scenery) if roadside != null else []
	var landmark_items: Array[Dictionary] = []
	if district != null:
		for instance: MultiMeshInstance3D in district.find_children("*", "MultiMeshInstance3D", true, false):
			if String(instance.get_meta("asset_id", "")) in CityRoadsideCatalog.LANDMARKS + ["relay_tower"]:
				landmark_items.append_array(_items([instance], scenery))
	var actor_items: Array[Dictionary] = []
	for group: Node in realism.get_children():
		if String(group.name).begins_with("ShopLife"):
			for mesh_instance: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
				actor_items.append({"center": _world(mesh_instance, scenery) * mesh_instance.get_aabb().get_center(), "begin": 0.0, "end": mesh_instance.visibility_range_end, "tris": IndustrialMarketBenchmark.count_triangles(mesh_instance.mesh), "surfaces": mesh_instance.mesh.get_surface_count(), "key": mesh_instance.get_instance_id()})
	for s in range(0, int(course.total_length), 10):
		var eye: Vector3 = CityDistrict.sample(course, float(s))["pos"] + Vector3.UP * 1.5
		var base := _sum(base_items, eye, 0.0)
		var landmarks := _sum(landmark_items, eye, LANDMARK_RANGE)
		var addon := _sum(addon_items, eye, 0.0)
		var actors := _sum(actor_items, eye, 0.0)
		peaks["base_tris"] = maxi(peaks["base_tris"], base["tris"])
		peaks["base_surfaces"] = maxi(peaks["base_surfaces"], base["surfaces"])
		peaks["landmark_tris"] = maxi(peaks["landmark_tris"], landmarks["tris"])
		peaks["addon_tris"] = maxi(peaks["addon_tris"], addon["tris"])
		peaks["addon_surfaces"] = maxi(peaks["addon_surfaces"], addon["surfaces"])
		peaks["actor_tris"] = maxi(peaks["actor_tris"], actors["tris"])
		peaks["combined_tris"] = maxi(peaks["combined_tris"], int(base["tris"]) + int(landmarks["tris"]) + int(addon["tris"]) + int(actors["tris"]))
		peaks["combined_surfaces"] = maxi(peaks["combined_surfaces"], int(base["surfaces"]) + int(landmarks["surfaces"]) + int(addon["surfaces"]) + int(actors["surfaces"]))
		peaks["eyes"] += 1
	return peaks


## Items follow how nodes really cull: a node with a finite visibility range is ONE item at the centre of its merged instance bounds and carries every
## instance it contains. Only range-free nodes (landmark district batches, bounded by `hard_range`) are counted per instance.
static func _items(instances: Array, scenery: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for instance: MultiMeshInstance3D in instances:
		var mesh := instance.multimesh.mesh
		if mesh == null:
			continue
		var tris := IndustrialMarketBenchmark.count_triangles(mesh)
		var local_box := mesh.get_aabb()
		var local := local_box.get_center()
		var anchor := _world(instance, scenery)
		var transforms: Array = instance.get_meta("city_transforms", [])
		if transforms.is_empty():
			out.append({"center": anchor * local, "begin": instance.visibility_range_begin, "end": instance.visibility_range_end, "tris": tris * instance.multimesh.instance_count, "surfaces": mesh.get_surface_count(), "key": instance.get_instance_id()})
			continue
		if instance.visibility_range_end > 0.0 or instance.visibility_range_begin > 0.0:
			var merged := AABB()
			for i in transforms.size():
				var box := world_box(anchor * (transforms[i] as Transform3D), local_box)
				merged = box if i == 0 else merged.merge(box)
			out.append({"center": merged.get_center(), "begin": instance.visibility_range_begin, "end": instance.visibility_range_end, "tris": tris * transforms.size(), "surfaces": mesh.get_surface_count(), "key": instance.get_instance_id()})
			continue
		for xf: Transform3D in transforms:
			out.append({"center": anchor * (xf * local), "begin": 0.0, "end": instance.visibility_range_end, "tris": tris, "surfaces": mesh.get_surface_count(), "key": instance.get_instance_id()})
	return out


## Triangles one add-on node draws at `eye` under the same rule the whole-street measurement uses (its own merged bounds and visibility window).
static func active_tris(instance: MultiMeshInstance3D, scenery: Node3D, eye: Vector3) -> int:
	return int(_sum(_items([instance], scenery), eye, 0.0)["tris"])


static func _sum(items: Array[Dictionary], eye: Vector3, hard_range: float) -> Dictionary:
	var tris := 0
	var seen := {}
	var surfaces := 0
	for item in items:
		var distance := eye.distance_to(item["center"])
		var end: float = hard_range if hard_range > 0.0 else (item["end"] + MARGIN if item["end"] > 0.0 else INF)
		if distance > end or distance < float(item["begin"]) - MARGIN:
			continue
		tris += int(item["tris"])
		if not seen.has(item["key"]):
			seen[item["key"]] = true
			surfaces += int(item["surfaces"])
	return {"tris": tris, "surfaces": surfaces}


static func _world(node: Node3D, stop: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != stop and cursor is Node3D:
		xf = (cursor as Node3D).transform * xf
		cursor = cursor.get_parent()
	return xf
