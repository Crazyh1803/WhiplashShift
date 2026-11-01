## Roadside detail layer regression suite (headless safe). Measured from the built scene: placements, world boxes, clearances, geometry shares, effect
## volumes, budgets, source hashes, determinism and the optional-asset fallbacks. Real renders of the planned views live in city_roadside_qa.tscn
## (run with --capture on a Vulkan display); here the same plan is checked for framing, and on a real display each view is also rendered and read back.
extends Node3D

const LIMIT := 1100.0
const MIN_TOWERS := 4
const MIN_BOARD_HOSTS := 6
const MIN_CAMPS := 4
const MIN_BARRELS := 8

var _pass := 0
var _fail := 0
var _course: CourseDefinition


func _ready() -> void:
	_course = BlockCircuitData.build_course()
	var before := var_to_str(_course.points)
	var host := Node3D.new()
	add_child(host)
	var scenery := CityScenery.build(host, _course)
	var roadside := scenery.get_node_or_null("CityRoadside") as Node3D
	_check("converted city carries the roadside layer", roadside != null and scenery.get_meta("converted_city") == true)
	if roadside != null:
		_test_catalog()
		_test_sources()
		_test_counts(roadside)
		_test_clearances(scenery, roadside)
		_test_layering(scenery, roadside)
		_test_towers(roadside)
		_test_landmarks(scenery, roadside)
		_test_boards(scenery, roadside)
		_test_camps_and_barrels(roadside)
		_test_effects(scenery, roadside)
		_test_distant_transforms(scenery)
		_test_lights(scenery, roadside)
		_test_budget(scenery, roadside)
		_test_originals(host, scenery)
		await _test_views(scenery, roadside)
		_test_determinism(host, scenery)
		_test_fallbacks(host)
	_check("course points are unmodified by the roadside build", var_to_str(_course.points) == before)
	host.free()
	print("CITY_ROADSIDE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


# ------------------------------------------------------------------------------------------------ catalog
func _test_catalog() -> void:
	var ids := CityRoadsideCatalog.asset_ids()
	_check("library holds every required asset (%d)" % ids.size(), ids.size() == 19 and ids.all(func(id: String) -> bool: return CityRoadsideCatalog.meshes.has(id)))
	for group in ["landmarks", "towers", "camps", "barrels", "boards"]:
		_check("group %s is complete" % group, CityRoadsideCatalog.has_group(group))
	var bad_material := 0
	var untextured := 0
	var no_uv := 0
	var no_colour := 0
	var missing_tangent := 0
	var roles := {}
	for id: String in ids:
		var mesh: ArrayMesh = CityRoadsideCatalog.meshes[id]
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if material == null or not CityRealismCatalog.materials.has(material.resource_name) or material != CityRealismCatalog.materials[material.resource_name]:
				bad_material += 1
			var arrays := mesh.surface_get_arrays(surface)
			if (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty():
				no_uv += 1
			if (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty():
				no_colour += 1
			if material != null and (material as StandardMaterial3D).normal_enabled and (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).is_empty():
				missing_tangent += 1
		roles[id] = CityRoadsideCatalog.costs[id]["tris"]
	_check("every surface is bound to the canonical library material (%d unbound)" % bad_material, bad_material == 0)
	_check("every surface has UV0 (%d without)" % no_uv, no_uv == 0)
	_check("every surface carries COLOR_0 wear/AO (%d without)" % no_colour, no_colour == 0)
	_check("every normal-mapped surface carries tangents (%d without)" % missing_tangent, missing_tangent == 0)
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(CityRoadsideCatalog.MANIFEST)) as Dictionary
	_check("build recorded no GLB problems", (manifest["problems"] as Array).is_empty())
	print("ROADSIDE_ASSETS: ", roles)
	var pngs := 0
	for file_name in DirAccess.get_files_at("res://assets/city/roadside/"):
		pngs += int(file_name.ends_with(".png"))
	_check("detail reuses the existing PBR library with no new textures (%d new PNG)" % pngs, pngs == 0)


func _test_sources() -> void:
	var hashes: Dictionary = CityRoadsideCatalog.protected_hashes
	_check("manifest protects the original kit and frontage sources (%d files)" % hashes.size(), hashes.size() >= 12 and hashes.has("godot/assets/city/kit/exchange_hall.glb") and hashes.has("godot/assets/city/kit/pump_citadel.glb"))
	var changed := 0
	for rel: String in hashes:
		var path := "res://" + rel.trim_prefix("godot/")
		if FileAccess.get_sha256(path) != hashes[rel]:
			changed += 1
			print("CHANGED: ", rel)
	_check("original sources are byte-identical to their recorded hashes (%d changed)" % changed, changed == 0)


# ------------------------------------------------------------------------------------------------ counts and clearance
func _test_counts(roadside: Node3D) -> void:
	var towers: Array = roadside.get_meta("towers")
	var quarters := {}
	var types := {}
	for tower: Dictionary in towers:
		quarters[tower["quarter"]] = true
		types[tower["id"]] = true
	_check("four detailed skyscrapers cover all four quarters (%d towers, %d quarters)" % [towers.size(), quarters.size()], towers.size() >= MIN_TOWERS and quarters.size() == 4)
	_check("both skyscraper types are used", types.size() == 2)
	var hosts := {}
	var host_quarters := {}
	for board: Dictionary in roadside.get_meta("boards"):
		hosts[var_to_str([board["s"], board["side"]])] = true
		host_quarters[board["quarter"]] = true
	_check("six or more frontages are boarded, spread over all quarters (%d hosts, %d quarters)" % [hosts.size(), host_quarters.size()], hosts.size() >= MIN_BOARD_HOSTS and host_quarters.size() == 4)
	var camp_ids := {}
	for camp: Dictionary in roadside.get_meta("camps"):
		camp_ids[camp["id"]] = true
	_check("four distinct camps (%d)" % camp_ids.size(), (roadside.get_meta("camps") as Array).size() >= MIN_CAMPS and camp_ids.size() == 4)
	var barrels: Array = roadside.get_meta("barrels")
	var beside := barrels.filter(func(b: Dictionary) -> bool: return String(b["camp"]) != "").size()
	_check("burning barrels: several, some beside camps and some separate (%d total, %d beside camps)" % [barrels.size(), barrels.size() - (barrels.size() - beside)], barrels.size() >= MIN_BARRELS and beside >= 4 and barrels.size() - beside >= 4)
	_check("both landmarks carry a detail overlay", (roadside.get_meta("landmarks") as Array).size() == 2)
	for kind in ["towers", "camps", "barrels", "boards", "landmarks"]:
		for item: Dictionary in roadside.get_meta(kind):
			print("  PLACED %s %s q=%s s=%.1f side=%d setback=%s road=%.1f" % [kind, item["id"], item.get("quarter", "-"), item["s"], item["side"], item.get("setback", "-"), CityScenery.road_clearance(item["bounds"], _course)])
	print("ROADSIDE_COUNTS: towers=%d boards=%d camps=%d barrels=%d (beside camps %d) landmarks=%d rejected=%s" % [towers.size(), (roadside.get_meta("boards") as Array).size(), (roadside.get_meta("camps") as Array).size(), barrels.size(), beside, (roadside.get_meta("landmarks") as Array).size(), roadside.get_meta("rejected")])


func _flat(box: AABB) -> AABB:
	return AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 1.0, box.size.z))


func _solids(scenery: Node3D) -> Dictionary:
	var realism := scenery.get_node("CityRealism") as Node3D
	var district := scenery.get_node("CityKit") as Node3D
	var landmarks: Array[AABB] = []
	for placement: Dictionary in district.get_meta("placements"):
		landmarks.append(_flat(placement["bounds"]))
	var crown := scenery.get_node_or_null("Crown") as Node3D
	var crown_box := AABB(crown.position - Vector3(48, 0, 48), Vector3(96, 1, 96)) if crown != null else AABB()
	return {"reserved": realism.get_meta("reserved_bounds"), "landmarks": landmarks, "crown": crown_box, "placements": realism.get_meta("placements")}


func _test_clearances(scenery: Node3D, roadside: Node3D) -> void:
	var solids := _solids(scenery)
	var worst_road := INF
	var road_bad := 0
	var solid_hits := 0
	var landmark_hits := 0
	var crown_hits := 0
	var world_bad := 0
	var own_hits := 0
	var items: Array[Dictionary] = []
	for kind in ["towers", "camps"]:
		for item: Dictionary in roadside.get_meta(kind):
			items.append({"box": item["bounds"], "clear": CityScenery.ROAD_CLEARANCE if kind == "towers" else CityRoadsideLayout.CAMP_CLEARANCE, "label": item["id"]})
	for barrel: Dictionary in roadside.get_meta("barrels"):
		items.append({"box": barrel["effect"], "clear": CityScenery.ROAD_CLEARANCE, "label": "effect"})
		items.append({"box": barrel["bounds"], "clear": CityScenery.ROAD_CLEARANCE, "label": "barrel"})
	for i in items.size():
		var box: AABB = items[i]["box"]
		var gap := CityScenery.road_clearance(box, _course)
		worst_road = minf(worst_road, gap)
		road_bad += int(gap < float(items[i]["clear"]))
		world_bad += int(absf(box.position.x) > LIMIT or absf(box.end.x) > LIMIT or absf(box.position.z) > LIMIT or absf(box.end.z) > LIMIT)
		var flat := _flat(box)
		var effect: bool = items[i]["label"] in ["effect", "barrel"]
		for reserved: AABB in solids["reserved"]:
			if flat.intersects(reserved):
				solid_hits += 1
				break
		for landmark: AABB in solids["landmarks"]:
			if flat.intersects(landmark):
				landmark_hits += 1
				break
		if (solids["crown"] as AABB).size != Vector3.ZERO and flat.intersects(solids["crown"]):
			crown_hits += 1
		for j in range(i + 1, items.size()):
			var other := _flat(items[j]["box"])
			# a barrel body sits inside its own effect volume, and a beside-camp effect may reach its own camp
			if items[i]["label"] in ["effect", "barrel"] and items[j]["label"] in ["effect", "barrel"] and (items[i]["label"] != items[j]["label"]):
				continue
			if flat.intersects(other) and not (effect or items[j]["label"] in ["effect", "barrel"]):
				own_hits += 1
	_check("every tower, camp, barrel and effect box clears the road by its limit (worst %.2f m, %d violations)" % [worst_road, road_bad], road_bad == 0)
	_check("all roadside boxes stay inside the world limit", world_bad == 0)
	_check("no roadside box overlaps a realism solid lot (%d)" % solid_hits, solid_hits == 0)
	_check("no roadside box overlaps a landmark (%d)" % landmark_hits, landmark_hits == 0)
	_check("no roadside box overlaps the crown (%d)" % crown_hits, crown_hits == 0)
	_check("towers and camps do not overlap one another (%d)" % own_hits, own_hits == 0)
	var effect_overlap := 0
	var barrels: Array = roadside.get_meta("barrels")
	for i in barrels.size():
		for j in range(i + 1, barrels.size()):
			if _flat(barrels[i]["effect"]).intersects(_flat(barrels[j]["effect"])):
				effect_overlap += 1
	_check("barrel effect volumes do not overlap one another (%d)" % effect_overlap, effect_overlap == 0)
	var disagreements := 0
	for tower: Dictionary in roadside.get_meta("towers"):
		disagreements += int(not _oriented_clear(tower["transform"], CityRoadsideCatalog.bounds(tower["id"])))
	_check("independent oriented footprint sampling agrees for every tower (%d too close)" % disagreements, disagreements == 0)


func _oriented_clear(xf: Transform3D, local: AABB) -> bool:
	var count := _course.points.size()
	for gx in 5:
		for gz in 5:
			var p3 := xf * (local.position + Vector3(local.size.x * float(gx) / 4.0, 0.0, local.size.z * float(gz) / 4.0))
			var p := Vector2(p3.x, p3.z)
			for k in count:
				var a: Dictionary = _course.points[k]
				var b: Dictionary = _course.points[(k + 1) % count]
				var closest := Geometry2D.get_closest_point_to_segment(p, Vector2(a["pos"].x, a["pos"].z), Vector2(b["pos"].x, b["pos"].z))
				var edge := maxf(float(a["w"]), float(b["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET
				if p.distance_to(closest) - edge < CityScenery.ROAD_CLEARANCE - 0.01:
					return false
	return true


func _test_layering(scenery: Node3D, roadside: Node3D) -> void:
	var backdrop := scenery.get_node("CityBackdrop") as Node3D
	var reserved: Array = roadside.get_meta("reserved_bounds")
	var hits := 0
	for batch: MultiMeshInstance3D in backdrop.find_children("*", "MultiMeshInstance3D", false, false):
		for xf: Transform3D in batch.get_meta("city_transforms"):
			var world := _world_box(xf, AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))
			for box: AABB in reserved:
				if _flat(world).intersects(box):
					hits += 1
					break
	_check("the roadside lots are reserved before the generic backdrop: no backdrop part touches them (%d, %d lots)" % [hits, reserved.size()], hits == 0 and reserved.size() >= 16)
	var generic := 0
	for batch: MultiMeshInstance3D in scenery.find_children("*", "MultiMeshInstance3D", true, false):
		if not backdrop.is_ancestor_of(batch) and String(batch.name) in ["Body", "Rib", "Cyan", "Amber", "Sinew", "Wall", "Post"]:
			generic += batch.multimesh.instance_count
	_check("no generic foreground geometry bypasses the layering (%d)" % generic, generic == 0)
	var deepest := 0.0
	var nearest_front := INF
	for tower: Dictionary in roadside.get_meta("towers"):
		nearest_front = minf(nearest_front, CityScenery.road_clearance(tower["bounds"], _course))
		deepest = maxf(deepest, CityScenery.road_clearance(tower["bounds"], _course))
	_check("towers stand in the detailed band in front of the backdrop (nearest %.1f m, setback limit %.0f m)" % [nearest_front, CityScenery.GENERIC_SETBACK], nearest_front < CityScenery.GENERIC_SETBACK)
	var backdrop_nearest := INF
	for record: Dictionary in backdrop.get_meta("records"):
		backdrop_nearest = minf(backdrop_nearest, CityScenery.road_clearance(record["bounds"], _course))
	_check("the generic setback and depth rows are intact (nearest %.1f m)" % backdrop_nearest, backdrop_nearest >= CityScenery.GENERIC_SETBACK)


# ------------------------------------------------------------------------------------------------ towers
func _surface_tris(mesh: ArrayMesh, region: AABB) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var centre := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
			if region.has_point(centre):
				count += 1
	return count


func _test_towers(roadside: Node3D) -> void:
	var boxes := {}
	for id in CityRoadsideCatalog.TOWERS:
		var mesh: ArrayMesh = CityRoadsideCatalog.meshes[id]
		var box := mesh.get_aabb()
		boxes[id] = box
		var tris: int = CityRoadsideCatalog.costs[id]["tris"]
		var lod: int = CityRoadsideCatalog.costs[id + "_lod1"]["tris"]
		_check("%s is a genuinely detailed skyscraper (%d tris, %d surfaces, %.0f m high)" % [id, tris, mesh.get_surface_count(), box.size.y], tris >= 40000 and mesh.get_surface_count() >= 10 and box.size.y >= 55.0)
		_check("%s keeps a cheaper distance LOD that is not a placeholder (%d tris, %d surfaces)" % [id, lod, CityRoadsideCatalog.costs[id + "_lod1"]["surfaces"]], lod >= 2500 and lod * 6 <= tris)
		# street-facing: the podium front (glTF -z half, below 12 m) is far denser than the back of the same block
		var depth := box.end.z - maxf(box.position.z, 0.0)
		var front := AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 12.0, 7.0 - box.position.z))
		var back := AABB(Vector3(box.position.x, 0.0, box.end.z - 7.0), Vector3(box.size.x, 12.0, 7.0))
		var front_tris := _surface_tris(mesh, front)
		var back_tris := _surface_tris(mesh, back)
		_check("%s podium detail faces the street (front %d vs back %d tris below 12 m)" % [id, front_tris, back_tris], front_tris >= 6000 and front_tris >= back_tris * 2)
		var entry: Dictionary = CityRoadsideCatalog.entries[id]
		var entrances: Array = entry.get("entrances", [])
		var usable := entrances.filter(func(e: Dictionary) -> bool: return float(e["position"][2]) <= 0.6 and float(e["height"]) >= 2.0 and float(e["width"]) >= 0.8)
		_check("%s lists usable street entrances (%d)" % [id, usable.size()], usable.size() >= 3)
		var materials: Array = CityRoadsideCatalog.costs[id]["materials"]
		_check("%s uses windows, signs, service steel and roof-membrane materials" % id, "glass_window" in materials and "sign_atlas" in materials and "equipment_steel" in materials and "roof_membrane" in materials)
	var a: AABB = boxes["tower_a"]
	var b: AABB = boxes["tower_b"]
	_check("the two skyscrapers have distinct silhouettes (%.0fx%.0fx%.0f vs %.0fx%.0fx%.0f)" % [a.size.x, a.size.y, a.size.z, b.size.x, b.size.y, b.size.z], absf(a.size.y - b.size.y) > 3.0 and (absf(a.size.x - b.size.x) > 1.0 or absf(a.size.z - b.size.z) > 1.0))
	var sides := {}
	for tower: Dictionary in roadside.get_meta("towers"):
		var batch := _node_at(roadside, "Roadside_" + String(tower["id"]), (tower["transform"] as Transform3D).origin)
		_check("%s near mesh has its own single-transform node with a bounded window" % tower["id"], batch != null and batch.multimesh.instance_count == 1 and batch.visibility_range_end == CityRoadside.TOWER_NEAR_END)
		sides[int(tower["side"])] = true
		var facing := -(tower["transform"] as Transform3D).basis.z
		var at := CityDistrict.sample(_course, tower["s"])
		var lateral := (((tower["transform"] as Transform3D).origin) - (at["pos"] as Vector3))
		_check("tower q%d faces the road" % (int(tower["quarter"]) + 1), facing.dot(lateral.normalized()) < -0.85)


# ------------------------------------------------------------------------------------------------ landmarks
func _test_landmarks(scenery: Node3D, roadside: Node3D) -> void:
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(CityRoadsideCatalog.MANIFEST)) as Dictionary
	for placement: Dictionary in roadside.get_meta("landmarks"):
		var id: String = placement["id"]
		var overlay: AABB = CityRoadsideCatalog.bounds(id)
		var source: Array = manifest["assets"][id]["source_aabb"]
		var low := Vector3(source[0][0], source[0][1], source[0][2])
		var high := Vector3(source[1][0], source[1][1], source[1][2])
		var kit := AABB(low, high - low).grow(0.05)
		_check("%s overlay lies inside the original landmark box (no new protrusion)" % id, kit.encloses(overlay))
		var tris: int = CityRoadsideCatalog.costs[id]["tris"]
		_check("%s adds real functional detail (%d tris, %d materials)" % [id, tris, (CityRoadsideCatalog.costs[id]["materials"] as Array).size()], tris >= 20000 and (CityRoadsideCatalog.costs[id]["materials"] as Array).size() >= 6)
		var base_bounds: AABB = placement["host_bounds"]
		_check("%s overlay uses the landmark's own transform (same placement bounds)" % id, (placement["bounds"] as AABB).intersects(base_bounds) and base_bounds.grow(0.2).encloses(placement["bounds"]))
		var doors: Array = (CityRoadsideCatalog.entries[id].get("entrances", []) as Array)
		_check("%s overlay has working door fixtures (%d)" % [id, doors.size()], doors.size() >= 1)
	var district := scenery.get_node("CityKit") as Node3D
	var weathered := 0
	for id in CityRoadside.WEATHERED:
		var instance := district.get_node_or_null(id) as MultiMeshInstance3D
		if instance == null:
			continue
		var mesh := instance.multimesh.mesh as ArrayMesh
		var shaded := 0
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			shaded += int(material is ShaderMaterial and (material as ShaderMaterial).shader == CityRoadside.WEATHER_SHADER)
		weathered += int(instance.has_meta("roadside_weathered") and shaded >= 3)
		_check("%s receives the converted-mode weathering (%d of %d surfaces)" % [id, shaded, mesh.get_surface_count()], instance.has_meta("roadside_weathered") and shaded >= 3)
		_check("%s keeps its original mesh geometry" % id, IndustrialMarketBenchmark.count_triangles(mesh) == IndustrialMarketBenchmark.count_triangles(CityKit.mesh(id)) and mesh.get_aabb().is_equal_approx(CityKit.mesh(id).get_aabb()))
	var steel := CityKit.material("steel") as ShaderMaterial
	_check("the shared original kit materials are not altered", steel != null and steel.shader == CityKit.SURFACE_SHADER)
	var code := CityRoadside.WEATHER_SHADER.code
	_check("weathering is deterministic and texture-free (no TIME, no samplers)", code.find("TIME") == -1 and code.find("sampler2D") == -1 and code.find("texture(") == -1)
	_check("weathering carries splash, streak, rust and seam terms", code.find("rust_mask") != -1 and code.find("streak") != -1 and code.find("seam") != -1 and code.find("grime") != -1)


# ------------------------------------------------------------------------------------------------ boards, camps, barrels
func _test_boards(scenery: Node3D, roadside: Node3D) -> void:
	var solids := _solids(scenery)
	var placements: Array = solids["placements"]
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(CityRoadsideCatalog.MANIFEST)) as Dictionary
	var windows := 0
	var doors := 0
	var stray := 0
	var protruding := 0
	var actor_hosts := 0
	var seen := {}
	for board: Dictionary in roadside.get_meta("boards"):
		var host: AABB = board["host_bounds"]
		var overlay: AABB = board["bounds"]
		seen[board["host"]] = true
		actor_hosts += int(board["host"] == "redline_shop")
		# the overlay may only overlap its own host; it is within 0.35 m of it on every side
		protruding += int(not host.grow(0.35).encloses(overlay))
		for p: Dictionary in placements:
			if p["role"] == "building" and (p["bounds"] as AABB) != host and _flat(overlay).intersects(_flat(p["bounds"])) and not _flat(host).intersects(_flat(p["bounds"])):
				stray += 1
		var record: Dictionary = manifest["assets"][board["id"]]
		windows += int(record.get("windows_boarded", 0))
		doors += int(record.get("doors_barricaded", 0))
	_check("boards overlap only their own host and stay within 0.35 m of it (%d protruding, %d stray)" % [protruding, stray], protruding == 0 and stray == 0)
	_check("boarded hosts never include the actor shop family (%d)" % actor_hosts, actor_hosts == 0)
	_check("boards are fitted to measured windows and doors (%d windows, %d doors, %d families)" % [windows, doors, seen.size()], windows >= 40 and doors >= 3 and seen.size() >= 3)
	var varied := 0
	for id in CityRoadsideCatalog.BOARD_FAMILIES:
		if CityRoadsideCatalog.costs["boards_" + id]["tris"] >= 1500:
			varied += (CityRoadsideCatalog.costs["boards_" + id]["materials"] as Array).size() >= 4 as int
	_check("boards use varied board, sheet, fastener and trim materials (%d families)" % varied, varied >= 4)


func _test_camps_and_barrels(roadside: Node3D) -> void:
	var by_quarter := {}
	for camp: Dictionary in roadside.get_meta("camps"):
		by_quarter[camp["quarter"]] = true
		var cost: Dictionary = CityRoadsideCatalog.costs[camp["id"]]
		_check("%s is a real encampment (%d tris, %d materials)" % [camp["id"], cost["tris"], (cost["materials"] as Array).size()], cost["tris"] >= 1200 and (cost["materials"] as Array).size() >= 7)
	_check("camps are spread over all four quarters", by_quarter.size() == 4)
	var near := 0
	for barrel: Dictionary in roadside.get_meta("barrels"):
		if String(barrel["camp"]) != "":
			for camp: Dictionary in roadside.get_meta("camps"):
				if camp["id"] == barrel["camp"]:
					near += int((barrel["transform"] as Transform3D).origin.distance_to((camp["transform"] as Transform3D).origin) < 8.0)
	_check("camp barrels stand beside their camp (%d)" % near, near >= 4)
	for id in CityRoadsideCatalog.BARRELS:
		var cost: Dictionary = CityRoadsideCatalog.costs[id]
		_check("%s is a detailed battered drum (%d tris)" % [id, cost["tris"]], cost["tris"] >= 800 and "lamp_glass" in cost["materials"])
		_check("%s documents its fire anchor" % id, CityRoadsideCatalog.fire_anchor(id).has("base"))


func _test_effects(scenery: Node3D, roadside: Node3D) -> void:
	var fires: Array[Node] = roadside.find_children("BarrelFire_*", "MultiMeshInstance3D", false, false)
	var barrels: Array = roadside.get_meta("barrels")
	var fire := fires[0] as MultiMeshInstance3D if not fires.is_empty() else null
	_check("one single-transform fire node per barrel (%d)" % barrels.size(), fire != null and fires.size() == barrels.size() and fires.all(func(n: MultiMeshInstance3D) -> bool: return n.multimesh.instance_count == 1) and barrels.size() <= CityRoadsideFx.MAX_BARRELS)
	var phases := {}
	for i in fires.size():
		var data := Color((fires[i] as MultiMeshInstance3D).get_meta("fire_phase"), (fires[i] as MultiMeshInstance3D).get_meta("fire_coal"), 0.0)
		phases[snappedf(data.r, 0.0001)] = true
		_check("fire %d keeps its deterministic phase and coal height" % i, is_equal_approx(data.r, fposmod(float(i) * 0.37 + 0.11, 1.0)) and is_equal_approx(data.g, float(barrels[i]["coal_height"])))
		_check("fire %d sits at its barrel with its exact world bounds" % i, ((fires[i] as MultiMeshInstance3D).get_meta("city_transforms")[0] as Transform3D).origin.is_equal_approx((barrels[i]["transform"] as Transform3D).origin) and (fires[i] as MultiMeshInstance3D).custom_aabb.grow(0.01).encloses(barrels[i]["effect"]))
	_check("fire phases are de-synchronised (%d distinct)" % phases.size(), phases.size() == fires.size())
	var mesh := fire.multimesh.mesh as ArrayMesh
	_check("fire mesh is flame + ground pool + smoke", mesh.get_surface_count() == 3)
	var puff_verts := (mesh.surface_get_arrays(2)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_check("smoke is bounded: %d puffs per barrel, %d puffs in the city" % [CityRoadsideFx.PUFFS, CityRoadsideFx.PUFFS * barrels.size()], puff_verts == CityRoadsideFx.PUFFS * 4 and CityRoadsideFx.PUFFS * barrels.size() <= 96)
	_check("effect mesh bounds equal the reserved effect box", mesh.custom_aabb.size.is_equal_approx(Vector3(CityRoadsideLayout.EFFECT_RADIUS * 2.0, CityRoadsideLayout.EFFECT_HEIGHT, CityRoadsideLayout.EFFECT_RADIUS * 2.0)))
	for barrel: Dictionary in barrels:
		var effect: AABB = barrel["effect"]
		var placed := AABB((barrel["transform"] as Transform3D).origin + mesh.custom_aabb.position, mesh.custom_aabb.size)
		_check("barrel effect box matches the drawn volume", effect.position.is_equal_approx(placed.position) and effect.size.is_equal_approx(placed.size))
	var smoke: String = CityRoadsideFx.SMOKE_SHADER.code
	var flame: String = CityRoadsideFx.FLAME_SHADER.code
	var height := _constant(smoke, "HEIGHT")
	var radius := _constant(smoke, "RADIUS")
	var coal := 0.0
	for id in CityRoadsideCatalog.BARRELS:
		coal = maxf(coal, float(CityRoadsideCatalog.fire_anchor(id)["base"][1]))
	_check("smoke rise %.1f + coal %.2f + puff %.2f stays inside the %.1f m effect height" % [height, coal, 0.5, CityRoadsideLayout.EFFECT_HEIGHT], height > 0.0 and height + coal + 0.5 <= CityRoadsideLayout.EFFECT_HEIGHT)
	_check("smoke drift %.1f + puff radius stays inside the %.1f m effect radius" % [radius, CityRoadsideLayout.EFFECT_RADIUS], radius > 0.0 and radius + 0.5 <= CityRoadsideLayout.EFFECT_RADIUS and smoke.find("clamp(") != -1)
	_check("flame pool radius fits the effect box (%.1f m)" % CityRoadsideFx.POOL_RADIUS, CityRoadsideFx.POOL_RADIUS <= CityRoadsideLayout.EFFECT_RADIUS and CityRoadsideFx.FLAME_HEIGHT + coal <= CityRoadsideLayout.EFFECT_HEIGHT)
	_check("effects are additive/soft, unshaded and texture-free", flame.find("blend_add") != -1 and flame.find("unshaded") != -1 and smoke.find("blend_mix") != -1 and smoke.find("sampler2D") == -1 and flame.find("sampler2D") == -1)
	_check("effects animate by shader time (flame flickers, smoke loops)", flame.find("TIME") != -1 and smoke.find("TIME") != -1)
	_check("the scene contains no particle systems", scenery.find_children("*", "GPUParticles3D", true, false).is_empty() and scenery.find_children("*", "CPUParticles3D", true, false).is_empty())
	_check("the fire is distance-bounded", fire.visibility_range_end > 0.0 and fire.visibility_range_end <= 200.0)


## The single-transform node of a placed asset (label "Roadside_<id>") whose instance sits at `origin`.
func _node_at(roadside: Node3D, label: String, origin: Vector3) -> MultiMeshInstance3D:
	for instance: MultiMeshInstance3D in roadside.find_children("*", "MultiMeshInstance3D", false, false):
		if instance.get_meta("roadside_label", "") == label and (instance.get_meta("city_transforms")[0] as Transform3D).origin.is_equal_approx(origin):
			return instance
	return null


## Regression for the rendered culling defect: Godot culls a node by its own merged bounds, so two distant copies of one asset must never share a ranged node.
## Two copies 1200 m apart; an eye beside either must draw that copy's full detail (and only it), and the far LOD must follow each copy's own distance.
func _test_distant_transforms(scenery: Node3D) -> void:
	var host := Node3D.new()
	add_child(host)
	var tower_mesh: Mesh = CityRoadsideCatalog.meshes["tower_a"]
	var lod_mesh: Mesh = CityRoadsideCatalog.meshes["tower_a_lod1"]
	var a := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0))
	var b := Transform3D(Basis.IDENTITY, Vector3(1200.0, 0.0, 0.0))
	var pair: Array[Transform3D] = [a, b]
	var near := CityRoadside._batch(host, "T", tower_mesh, pair, 0.0, CityRoadside.TOWER_NEAR_END, "tower")
	var far := CityRoadside._batch(host, "T_lod1", lod_mesh, pair, CityRoadside.TOWER_FAR_BEGIN, CityRoadside.TOWER_FAR_END, "tower_lod1")
	_check("distant copies get one node each, none spans both", near.size() == 2 and far.size() == 2 and near.all(func(n: MultiMeshInstance3D) -> bool: return n.multimesh.instance_count == 1 and n.custom_aabb.size.x < 400.0))
	var box_a := near[0].custom_aabb
	var eyes := {"beside A": Vector3(0.0, 1.7, -40.0), "beside B": Vector3(1200.0, 1.7, -40.0), "far LOD range of A": Vector3(0.0, 1.7, -300.0), "far LOD range of B": Vector3(1200.0, 1.7, -300.0)}
	for label: String in eyes:
		var eye: Vector3 = eyes[label]
		var which := 0 if eye.x < 600.0 else 1
		var other := 1 - which
		var full: bool = label.begins_with("beside")
		var drawn := {}
		for node: MultiMeshInstance3D in near + far:
			drawn[node.name] = CityRoadside.active_tris(node, host, eye) > 0
		_check("%s: own full detail %s, own far LOD %s" % [label, full, not full], drawn[near[which].name] == full and drawn[far[which].name] == not full)
		_check("%s: the other copy draws nothing" % label, not drawn[near[other].name] and not drawn[far[other].name])
	# the old merged node would have been centred between the copies, 600 m from both: neither near mesh could ever be drawn
	var merged := box_a.merge(near[1].custom_aabb)
	_check("a merged node would sit %.0f m from either copy, beyond the %.0f m near window" % [merged.get_center().x, CityRoadside.TOWER_NEAR_END], merged.get_center().distance_to(Vector3(0.0, 1.7, -40.0)) > CityRoadside.TOWER_NEAR_END + CityRoadside.MARGIN)
	# the same holds for the fires: two barrels far apart, an eye beside either sees its own flames only
	var bases: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(1200.0, 0.0, 0.0)]
	var coals: Array[float] = [0.8, 0.9]
	var yaws: Array[float] = [0.0, 0.7]
	var fires := CityRoadsideFx.build(host, bases, coals, yaws)
	_check("two distant barrels get two fire nodes", fires.size() == 2)
	_check("an eye beside either fire draws its own flames only", CityRoadside.active_tris(fires[0], host, Vector3(3.0, 1.7, -3.0)) > 0 and CityRoadside.active_tris(fires[1], host, Vector3(3.0, 1.7, -3.0)) == 0 and CityRoadside.active_tris(fires[1], host, Vector3(1203.0, 1.7, -3.0)) > 0 and CityRoadside.active_tris(fires[0], host, Vector3(1203.0, 1.7, -3.0)) == 0)
	host.free()
	# the real scene: at every planned view the subject geometry is the active geometry
	_check("the real scene keeps its roadside nodes single-transform (no ranged node spans placements)", (scenery.get_node("CityRoadside") as Node3D).find_children("*", "MultiMeshInstance3D", true, false).all(func(n: MultiMeshInstance3D) -> bool: return n.multimesh.instance_count == 1))


func _constant(code: String, name_: String) -> float:
	var regex := RegEx.new()
	regex.compile("const float %s\\s*=\\s*([0-9.]+)" % name_)
	var found := regex.search(code)
	return float(found.get_string(1)) if found != null else -1.0


# ------------------------------------------------------------------------------------------------ lights and budgets
func _test_lights(scenery: Node3D, roadside: Node3D) -> void:
	_check("roadside layer adds no lights", roadside.find_children("*", "Light3D", true, false).is_empty() and int(roadside.get_meta("light_count")) == 0)
	_check("roadside layer adds no collision objects", roadside.find_children("*", "CollisionObject3D", true, false).is_empty())
	var lights := scenery.find_children("*", "Light3D", true, false)
	var realism_lights := int(scenery.get_node("CityRealism").get_meta("light_count"))
	_check("city keeps its light budget: realism %d + crown beacon (%d of %d)" % [realism_lights, lights.size(), CityScenery.MAX_LIGHTS], lights.size() == realism_lights + 1 and lights.size() <= CityScenery.MAX_LIGHTS)
	_check("roadside meshes cast no shadows", roadside.find_children("*", "GeometryInstance3D", true, false).all(func(n: GeometryInstance3D) -> bool: return n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))


func _test_budget(scenery: Node3D, roadside: Node3D) -> void:
	var peaks := CityRoadside.measure(scenery, _course)
	var static_tris := 0
	var static_surfaces := 0
	for instance: MultiMeshInstance3D in roadside.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh := instance.multimesh.mesh
		static_tris += IndustrialMarketBenchmark.count_triangles(mesh) * instance.multimesh.instance_count
		static_surfaces += mesh.get_surface_count()
	print("ROADSIDE_BUDGET: base_tris=%d base_surfaces=%d landmark_tris=%d actor_tris=%d addon_tris=%d addon_surfaces=%d combined_tris=%d combined_surfaces=%d static_tris=%d static_surfaces=%d eyes=%d" % [peaks["base_tris"], peaks["base_surfaces"], peaks["landmark_tris"], peaks["actor_tris"], peaks["addon_tris"], peaks["addon_surfaces"], peaks["combined_tris"], peaks["combined_surfaces"], static_tris, static_surfaces, peaks["eyes"]])
	_check("the base frontage budget is unchanged (%d tris of %d, %d surfaces of %d)" % [peaks["base_tris"], CityRealismLayout.NEAR_BUDGET, peaks["base_surfaces"], CityRealismLayout.SURFACE_BUDGET], CityRealismLayout.NEAR_BUDGET == 320000 and CityRealismLayout.SURFACE_BUDGET == 160 and peaks["base_tris"] > 0 and peaks["base_tris"] <= CityRealismLayout.NEAR_BUDGET and peaks["base_surfaces"] <= CityRealismLayout.SURFACE_BUDGET)
	_check("add-on visible triangles are capped explicitly (%d of %d)" % [peaks["addon_tris"], CityRoadside.ADDON_NEAR_BUDGET], peaks["addon_tris"] > 0 and peaks["addon_tris"] <= CityRoadside.ADDON_NEAR_BUDGET)
	_check("add-on visible surfaces are capped explicitly (%d of %d)" % [peaks["addon_surfaces"], CityRoadside.ADDON_SURFACE_BUDGET], peaks["addon_surfaces"] > 0 and peaks["addon_surfaces"] <= CityRoadside.ADDON_SURFACE_BUDGET)
	_check("landmark bases are counted in the combined measurement (%d tris)" % peaks["landmark_tris"], peaks["landmark_tris"] >= 10000)
	_check("combined peak stays inside the explicit whole-street caps (%d of %d tris, %d of %d surfaces)" % [peaks["combined_tris"], CityRoadside.COMBINED_NEAR_BUDGET, peaks["combined_surfaces"], CityRoadside.COMBINED_SURFACE_BUDGET],
			peaks["combined_tris"] <= CityRoadside.COMBINED_NEAR_BUDGET and peaks["combined_surfaces"] <= CityRoadside.COMBINED_SURFACE_BUDGET)
	_check("the whole-street caps equal base + landmarks + actors + add-on terms at their measured peaks", CityRoadside.COMBINED_NEAR_BUDGET <= CityRealismLayout.NEAR_BUDGET + CityRoadside.ADDON_NEAR_BUDGET + int(peaks["landmark_tris"]) + int(peaks["actor_tris"]) + 40000)
	_check("static roadside triangles are accounted (%d)" % static_tris, static_tris > 0 and static_tris <= 600000)


# ------------------------------------------------------------------------------------------------ originals, determinism, fallbacks
func _test_originals(host: Node3D, scenery: Node3D) -> void:
	var realism := scenery.get_node("CityRealism") as Node3D
	var alone_host := Node3D.new()
	add_child(alone_host)
	var alone := CityRealism.build(alone_host, _course.geometry())
	var a: Array = alone.get_meta("placements")
	var b: Array = realism.get_meta("placements")
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and a[i]["id"] == b[i]["id"] and var_to_str(a[i]["transform"]) == var_to_str(b[i]["transform"]) and var_to_str(a[i]["bounds"]) == var_to_str(b[i]["bounds"])
	var buildings := b.filter(func(p: Dictionary) -> bool: return p["role"] == "building").size()
	_check("every original frontage record is unchanged (%d records, %d buildings)" % [b.size(), buildings], same and buildings >= 66)
	_check("both actor pairs remain intact", realism.get_meta("actor_pairs") == 2 and realism.has_node("ShopLife0") and realism.has_node("ShopLife1"))
	_check("realism triangle total is unchanged (%d)" % int(realism.get_meta("triangle_count")), int(alone.get_meta("triangle_count")) == int(realism.get_meta("triangle_count")))
	alone_host.free()
	var district := scenery.get_node("CityKit") as Node3D
	_check("district landmark placements are unchanged (%d)" % (district.get_meta("placements") as Array).size(), (district.get_meta("placements") as Array).size() >= 3)


func _signature(scenery: Node3D) -> String:
	var roadside := scenery.get_node("CityRoadside") as Node3D
	var parts: Array = []
	for key in ["towers", "camps", "barrels", "boards", "landmarks"]:
		for item: Dictionary in roadside.get_meta(key):
			parts.append([key, item["id"], item["transform"], item["bounds"]])
	parts.append(roadside.get_meta("reserved_bounds"))
	return var_to_str(parts)


func _test_determinism(host: Node3D, scenery: Node3D) -> void:
	var repeat := CityScenery.build(host, _course)
	_check("rebuilding places identical roadside content", _signature(scenery) == _signature(repeat))
	var reverse := CityScenery.build(host, CourseCatalog.build_course("block_circuit", true))
	var rr := reverse.get_node_or_null("CityRoadside") as Node3D
	_check("reverse direction also builds the roadside layer", rr != null and (rr.get_meta("towers") as Array).size() >= MIN_TOWERS)
	for built: Node in [repeat, reverse]:
		built.get_parent().remove_child(built)
		built.free()


func _test_fallbacks(host: Node3D) -> void:
	# optional group missing: that group is skipped, the rest builds, nothing errors
	var saved: Dictionary = CityRoadsideCatalog.meshes.duplicate()
	CityRoadsideCatalog.meshes.erase("camp_a")
	var partial := CityScenery.build(host, _course)
	var partial_roadside := partial.get_node_or_null("CityRoadside") as Node3D
	_check("a missing camp asset skips the camps only", partial_roadside != null and (partial_roadside.get_meta("camps") as Array).is_empty() and (partial_roadside.get_meta("towers") as Array).size() >= MIN_TOWERS and partial.has_node("CityBackdrop"))
	CityRoadsideCatalog.meshes = saved
	partial.get_parent().remove_child(partial)
	partial.free()
	# whole library missing: the city builds exactly as before the layer existed
	var held_entries := CityRoadsideCatalog.entries
	var held_meshes := CityRoadsideCatalog.meshes
	var held_costs := CityRoadsideCatalog.costs
	CityRoadsideCatalog.entries = {}
	CityRoadsideCatalog.meshes = {}
	CityRoadsideCatalog.costs = {}
	CityRoadsideCatalog.disabled = true
	var bare := CityScenery.build(host, _course)
	_check("without the library there is no roadside node and the backdrop still builds", not bare.has_node("CityRoadside") and bare.has_node("CityBackdrop") and bare.has_node("CityRealism") and int(bare.get_node("CityBackdrop").get_meta("building_count")) >= 120)
	var bare_lights := bare.find_children("*", "Light3D", true, false).size()
	_check("the library-free city keeps its light budget (%d)" % bare_lights, bare_lights <= CityScenery.MAX_LIGHTS)
	bare.get_parent().remove_child(bare)
	bare.free()
	CityRoadsideCatalog.disabled = false
	CityRoadsideCatalog.entries = held_entries
	CityRoadsideCatalog.meshes = held_meshes
	CityRoadsideCatalog.costs = held_costs
	var legacy := CityScenery.build(host, _course, true, false)
	var plain := CityScenery.build(host, _course, false)
	_check("legacy and kit-off scenery build no roadside layer", not legacy.has_node("CityRoadside") and not plain.has_node("CityRoadside"))
	for built: Node in [legacy, plain]:
		built.get_parent().remove_child(built)
		built.free()


# ------------------------------------------------------------------------------------------------ views
func _test_views(scenery: Node3D, roadside: Node3D) -> void:
	var views := CityRoadsideViews.plan(roadside, _course)
	var kinds := {}
	for view in views:
		kinds[view["kind"]] = int(kinds.get(view["kind"], 0)) + 1
	_check("QA plan covers driver, landmark, tower, podium, boards, camp and barrel views %s" % [kinds], kinds.get("driver", 0) == 4 and kinds.get("landmark", 0) == 2 and kinds.get("landmark_detail", 0) == 2 and kinds.get("tower", 0) >= 4 and kinds.get("podium", 0) >= 4 and kinds.get("boards", 0) >= 6 and kinds.get("camp", 0) == 4 and kinds.get("barrel", 0) >= 8)
	var unframed := 0
	var inside := 0
	var names := {}
	for view in views:
		names[view["name"]] = true
		var subject: AABB = view["subject"]
		var points: Array[Vector3] = [subject.get_center(), view["target"]]
		if view["kind"] == "tower":
			points.clear()
			for corner in 8:
				points.append(subject.get_endpoint(corner))
		if not points.all(func(p: Vector3) -> bool: return CityRoadsideViews.frames(view, p)):
			unframed += 1
			print("UNFRAMED: ", view["name"])
		# the eye must not sit inside any solid: it has to be outside every roadside box except its own subject
		for kind in ["towers", "camps"]:
			for item: Dictionary in roadside.get_meta(kind):
				if (item["bounds"] as AABB).has_point(view["eye"]) and item["bounds"] != subject:
					inside += 1
	_check("every planned view frames its subject (%d unframed, %d eyes inside solids)" % [unframed, inside], unframed == 0 and inside == 0)
	_check("view names are unique (%d)" % names.size(), names.size() == views.size())
	var inactive := 0
	for view in views:
		var problem := CityRoadsideViews.subject_problem(roadside, view)
		if problem != "":
			inactive += 1
			print("SUBJECT NOT ACTIVE: ", view["name"], " ", problem)
	_check("every planned view has its subject geometry active at its eye (%d inactive)" % inactive, inactive == 0)
	if DisplayServer.get_name() == "headless":
		print("RENDER_CHECK: captured-pixel verification needs a real display; headless run checked the framing plan only")
		return
	await _render_views(scenery, roadside, views)


## On a real renderer: draw each planned view and require a non-flat image, so content that fails to draw is caught.
func _render_views(scenery: Node3D, roadside: Node3D, views: Array[Dictionary]) -> void:
	var env := WorldEnvironment.new()
	env.environment = TrackMaterials.environment()
	add_child(env)
	var cam := Camera3D.new()
	cam.far = 2500.0
	add_child(cam)
	cam.current = true
	var flat_views := 0
	for view in views:
		cam.position = view["eye"]
		cam.fov = view["fov"]
		cam.look_at(view["target"])
		for frame in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var low := 1.0
		var high := 0.0
		for y in range(0, image.get_height(), 16):
			for x in range(0, image.get_width(), 16):
				var v := image.get_pixel(x, y).get_luminance()
				low = minf(low, v)
				high = maxf(high, v)
		if high - low < 0.04:
			flat_views += 1
			print("FLAT VIEW: ", view["name"])
	_check("every planned view renders non-flat pixels (%d flat of %d)" % [flat_views, views.size()], flat_views == 0)
	cam.queue_free()
	env.queue_free()


func _world_box(xf: Transform3D, local: AABB) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for corner in 8:
		var c := local.position + Vector3(local.size.x * float(corner & 1), local.size.y * float((corner >> 1) & 1), local.size.z * float((corner >> 2) & 1))
		var w := xf.basis * c + xf.origin
		low = Vector3(minf(low.x, w.x), minf(low.y, w.y), minf(low.z, w.z))
		high = Vector3(maxf(high.x, w.x), maxf(high.y, w.y), maxf(high.z, w.z))
	return AABB(low, high - low)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
