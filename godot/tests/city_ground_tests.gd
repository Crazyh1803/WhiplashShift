## Independent regression suite for the optional connected street-fabric ground kit; headless.
## Figures are re-derived from the imported meshes, raw GLB bytes and the built scene graph, never from
## the layout's own polygons or costs. The rendered MultiMesh mutation detector stays in city_realism_tests.
extends Node3D

const GROUND: Array[String] = ["road_apron", "service_lane", "loading_yard", "utility_verge"]
const DEPTH := {"road_apron": 3.8, "service_lane": 10.0, "loading_yard": 14.0, "utility_verge": 14.0}
const TRI_CAP := {"road_apron": 24, "service_lane": 40, "loading_yard": 64, "utility_verge": 64}
const WIDTH := 16.1
const HEIGHT := 0.03
const GLOBAL_LIMIT := 900000
const QUARTER_LIMIT := 240000
const SOLID_SETBACK := 3.5
const APRON_CLEARANCE := 0.05
const VERTEX_CELL := 0.02
const REALISM_DIRECTORY := "res://assets/city/realism/"
const GROUND_DIRECTORY := "res://assets/city/ground/"
const TEXTURE_DIRECTORY := REALISM_DIRECTORY + "textures/"
const FAMILIES: Array[String] = ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot", "redline_shop", "row_workshop", "utility_substation", "transit_depot"]

var _pass := 0
var _fail := 0
var _course: CourseDefinition
var _converted: Node3D
var _scenery: Node3D
var _placements: Array = []


func _ready() -> void:
	_course = BlockCircuitData.build_course()
	var points_before := var_to_str(_course.points)
	var bytes_before := _asset_hashes()
	var host := Node3D.new()
	add_child(host)
	_test_detectors()
	_scenery = CityScenery.build(host, _course)
	_converted = _scenery.get_node_or_null("CityRealism") as Node3D
	_check("the default build uses the converted city", _converted != null)
	if _converted == null:
		print("CITY_GROUND_TESTS: %d passed, %d failed (no converted city: %s)" % [_pass, _fail, CityRealismCatalog.error])
		get_tree().quit(1)
		return
	_placements = _converted.get_meta("placements")
	_test_kit_geometry()
	_test_kit_materials()
	_test_layout_coverage()
	_test_rail_envelope()
	_test_budgets_and_actors()
	_test_merged_ground()
	_test_no_colliders_or_lights()
	_test_determinism()
	_test_fallback(host)
	_check("base family, people GLBs and shared texture PNG bytes are unchanged (%d files)" % bytes_before.size(), bytes_before.size() > 40 and bytes_before == _asset_hashes())
	_check("course points are unmodified by the ground build", var_to_str(_course.points) == points_before)
	host.free()
	print("CITY_GROUND_TESTS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


# --- kit geometry -----------------------------------------------------------------------------

func _test_kit_geometry() -> void:
	_check("ground kit is available through the catalog", CityRealismCatalog.ground_available())
	for id in GROUND:
		var mesh: Mesh = CityRealismCatalog.meshes.get(id)
		_check("%s mesh is loaded" % id, mesh != null)
		if mesh == null:
			continue
		var tris := 0
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var asset_lo := 1.0
		var asset_hi := 0.0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := vertices.size()
			tris += (indices.size() if indices.size() > 0 else count) / 3
			for v in vertices:
				lo = lo.min(v)
				hi = hi.max(v)
			var label := "%s/%d" % [id, surface]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			_check("%s has UV0, COLOR0, normals and tangents on all %d vertices and no UV1" % [label, count], count > 0 and uv.size() == count and colours.size() == count and normals.size() == count and tangents.size() == count * 4 and arrays[Mesh.ARRAY_TEX_UV2] == null)
			if tangents.size() != count * 4 or normals.size() != count or uv.size() != count or colours.size() != count:
				continue
			var bad_tangent := 0
			var bad_normal := 0
			var bad_uv := 0
			var uv_lo := Vector2(INF, INF)
			var uv_hi := Vector2(-INF, -INF)
			var colour_lo := 1.0
			var colour_hi := 0.0
			for i in count:
				var t := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
				if absf(t.length() - 1.0) > 0.02 or absf(t.dot(normals[i])) > 0.1 or absf(absf(tangents[i * 4 + 3]) - 1.0) > 0.01:
					bad_tangent += 1
				if normals[i].y < 0.99:
					bad_normal += 1
				if not (is_finite(uv[i].x) and is_finite(uv[i].y)):
					bad_uv += 1
				uv_lo = uv_lo.min(uv[i])
				uv_hi = uv_hi.max(uv[i])
				for channel in [colours[i].r, colours[i].g, colours[i].b]:
					colour_lo = minf(colour_lo, channel)
					colour_hi = maxf(colour_hi, channel)
			_check("%s tangents are unit and perpendicular to normals (%d bad)" % [label, bad_tangent], bad_tangent == 0)
			_check("%s normals face up (%d bad)" % [label, bad_normal], bad_normal == 0)
			_check("%s UV0 is finite with a real span %s" % [label, uv_hi - uv_lo], bad_uv == 0 and minf((uv_hi - uv_lo).x, (uv_hi - uv_lo).y) > 0.1)
			asset_lo = minf(asset_lo, colour_lo)
			asset_hi = maxf(asset_hi, colour_hi)
		_check("%s COLOR0 carries wear/paint variation (%.2f..%.2f)" % [id, asset_lo, asset_hi], asset_hi - asset_lo >= 0.25)
		var size := hi - lo
		_check("%s footprint %.3f x %.3f is %.1f x %.1f, centred on XZ" % [id, size.x, size.z, WIDTH, DEPTH[id]], absf(size.x - WIDTH) < 0.002 and absf(size.z - DEPTH[id]) < 0.002 and absf(lo.x + hi.x) < 0.002 and absf(lo.z + hi.z) < 0.002)
		_check("%s stands on y=0 and tops out at %.4f <= %.2f" % [id, hi.y, HEIGHT], absf(lo.y) < 1e-4 and hi.y <= HEIGHT + 1e-5)
		_check("%s has %d tris within cap %d (catalog cost agrees: %d)" % [id, tris, TRI_CAP[id], CityRealismCatalog.costs[id]["tris"]], tris > 0 and tris <= TRI_CAP[id] and tris == int(CityRealismCatalog.costs[id]["tris"]))
		_check("%s uses at most 3 surfaces (%d)" % [id, mesh.get_surface_count()], mesh.get_surface_count() >= 1 and mesh.get_surface_count() <= 3)
		var entry: Dictionary = CityRealismCatalog.entries.get(id, {})
		_check("%s manifest tris match the export" % id, int(entry.get("tris", -1)) == tris)
		_check("%s AABB from the catalog matches the vertices" % id, mesh.get_aabb().size.is_equal_approx(size) or (mesh.get_aabb().size - size).length() < 0.002)
		_check_raw_glb(id)


## Raw GLB JSON must hold geometry and material stubs only: no images, textures, samplers, lights or colliders.
func _check_raw_glb(id: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(GROUND_DIRECTORY + id + ".glb")
	var json_length := bytes.decode_u32(12)
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	_check("%s GLB is a readable glTF container" % id, bytes.size() > 100 and bytes.slice(0, 4).get_string_from_ascii() == "glTF" and parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var js: Dictionary = parsed
	_check("%s GLB has no images, textures, samplers or cameras" % id, not js.has("images") and not js.has("textures") and not js.has("samplers") and not js.has("cameras"))
	_check("%s GLB declares no punctual lights" % id, not js.get("extensionsUsed", []).has("KHR_lights_punctual") and not js.has("extensions"))
	var stubs_ok := true
	for material: Dictionary in js.get("materials", []):
		var pbr: Dictionary = material.get("pbrMetallicRoughness", {})
		stubs_ok = stubs_ok and not pbr.has("baseColorTexture") and not pbr.has("metallicRoughnessTexture") and not material.has("normalTexture") and not material.has("emissiveTexture") and not material.has("occlusionTexture")
		stubs_ok = stubs_ok and material.get("extras", {}).get("library_binding") == material.get("name")
	_check("%s material stubs are texture-free and bound to their library name" % id, stubs_ok and js.get("materials", []).size() > 0)
	_check("%s GLB has a single mesh node (%d)" % [id, js.get("meshes", []).size()], js.get("meshes", []).size() == 1)


# --- material and texture reuse ---------------------------------------------------------------

func _test_kit_materials() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(REALISM_DIRECTORY + "city_families_manifest.json"))
	var library: Dictionary = manifest["materials"]
	_check("realism library is still 14 materials (%d)" % library.size(), library.size() == 14 and CityRealismCatalog.materials.size() == 14)
	var textures := {}
	for id: String in CityRealismCatalog.materials:
		var material := CityRealismCatalog.materials[id] as StandardMaterial3D
		for texture: Texture2D in [material.albedo_texture, material.normal_texture, material.roughness_texture, material.metallic_texture, material.ao_texture, material.emission_texture]:
			if texture != null:
				textures[texture.resource_path] = texture
	_check("realism library is still 39 unique textures (%d)" % textures.size(), textures.size() == 39)
	var used := {}
	for id in GROUND:
		var mesh: Mesh = CityRealismCatalog.meshes[id]
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			used[material.resource_name] = true
			_check("%s/%d uses library material %s by identity" % [id, surface, material.resource_name], library.has(material.resource_name) and material == CityRealismCatalog.materials[material.resource_name])
			var base := material as BaseMaterial3D
			for texture: Texture2D in [base.albedo_texture, base.normal_texture, base.roughness_texture, base.metallic_texture, base.ao_texture, base.emission_texture]:
				if texture != null:
					_check_once(textures.get(texture.resource_path) == texture and texture.resource_path.begins_with(TEXTURE_DIRECTORY), "%s/%d texture %s is the library resource" % [id, surface, texture.resource_path], 0)
			_check_once(not base.emission_enabled, "%s/%d does not emit" % [id, surface], 0)
	_check("kit surfaces use only existing materials (%s)" % str(used.keys()), used.keys().all(func(k: String) -> bool: return library.has(k)) and not used.is_empty())
	_check("ground added no entry to the material library", CityRealismCatalog.materials.keys().all(func(k: String) -> bool: return library.has(k)))
	var directory := DirAccess.open(GROUND_DIRECTORY)
	var extras: Array[String] = []
	for file in directory.get_files():
		if file.get_extension() in ["png", "jpg", "jpeg", "webp", "tres", "res", "tscn"]:
			extras.append(file)
	_check("ground directory holds no texture or resource files (%s)" % str(extras), extras.is_empty())


# --- layout -----------------------------------------------------------------------------------

func _quarter(s: float) -> int:
	return mini(3, int(s / _course.total_length * 4.0))


func _test_layout_coverage() -> void:
	_check("layout reports ground_fabric true", _converted.get_meta("ground_fabric") == true)
	var seen := {}
	for record: Dictionary in _placements:
		if record["id"] in GROUND:
			var key := "%s/%d/%d" % [record["id"], _quarter(float(record["s"])), int(record["side"])]
			seen[key] = int(seen.get(key, 0)) + 1
		if record["id"] in GROUND:
			_check_once(int(record["quarter"]) == _quarter(float(record["s"])), "%s quarter label matches distance" % record["id"], int(float(record["s"])))
	var missing: Array[String] = []
	for q in 4:
		for side in [-1, 1]:
			for id in ["road_apron", "service_lane", "loading_yard" if q in [1, 2] else "utility_verge"]:
				if not seen.has("%s/%d/%d" % [id, q, side]):
					missing.append("%s/%d/%d" % [id, q, side])
	_check("apron and lane on both sides of all 4 quarters, freight/utility yards and market/housing verges (missing: %s)" % str(missing), missing.is_empty())
	var wrong: Array[String] = []
	for key: String in seen:
		var parts := key.split("/")
		if (parts[0] == "loading_yard" and int(parts[1]) not in [1, 2]) or (parts[0] == "utility_verge" and int(parts[1]) not in [0, 3]):
			wrong.append(key)
	_check("yards sit only in freight/utility quarters and verges only in market/housing quarters (%s)" % str(wrong), wrong.is_empty())
	var counts := {}
	for record: Dictionary in _placements:
		counts[record["id"]] = int(counts.get(record["id"], 0)) + 1
	print("CITY_GROUND_TESTS placement counts: ", counts)
	for id in GROUND:
		_check("%s is placed (%d)" % [id, counts.get(id, 0)], counts.get(id, 0) > 0)
	var aprons := _placements.filter(func(p: Dictionary) -> bool: return p["id"] == "road_apron")
	_check("every apron placement carries the apron role, nothing else does", aprons.all(func(p: Dictionary) -> bool: return p["role"] == "apron") and _placements.all(func(p: Dictionary) -> bool: return p["role"] != "apron" or p["id"] == "road_apron"))
	_check("lane and yard placements are plain ground role", _placements.all(func(p: Dictionary) -> bool: return not (p["id"] in ["service_lane", "loading_yard", "utility_verge"]) or p["role"] == "ground"))
	var curbs := _placements.filter(func(p: Dictionary) -> bool: return p["id"] == "curb_segment").size()
	var panels := _placements.filter(func(p: Dictionary) -> bool: return p["id"] == "sidewalk_panel").size()
	_check("curb_segment is retained at intervals only (%d curbs vs %d sidewalk panels)" % [curbs, panels], curbs > 0 and curbs * 3 < panels)
	var sidewalk_top := (CityRealismCatalog.meshes["sidewalk_panel"] as Mesh).get_aabb().end.y
	for id in GROUND:
		_check_once((CityRealismCatalog.meshes[id] as Mesh).get_aabb().end.y < sidewalk_top, "%s sits below the sidewalk top (%.3f)" % [id, sidewalk_top], 0)
	var buildings := _placements.filter(func(p: Dictionary) -> bool: return p["role"] == "building")
	var families := {}
	for record: Dictionary in buildings:
		families[record["id"]] = true
	_check("at least 29 buildings across all 8 families remain (%d / %d)" % [buildings.size(), families.size()], buildings.size() >= 29 and families.size() == 8 and FAMILIES.all(func(f: String) -> bool: return families.has(f)))
	var sides := {}
	for record: Dictionary in buildings:
		sides["%d/%d" % [record["quarter"], int(record["side"])]] = true
	_check("buildings still occupy both sides of all four quarters", sides.size() == 8)
	var reasons := {}
	for rejected: Dictionary in _converted.get_meta("rejected_slots"):
		if rejected["id"] in GROUND:
			reasons[rejected["reason"]] = int(reasons.get(rejected["reason"], 0)) + 1
	print("CITY_GROUND_TESTS ground rejections: ", reasons)
	_check("ground rejections state only known reasons", reasons.keys().all(func(r: String) -> bool: return r in ["road_clearance", "triangle_budget"]))


## Smallest distance from a footprint polygon's boundary to the road edge, measured against the course.
func _gap(polygon: PackedVector2Array) -> float:
	var best := INF
	var points := _course.points
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var steps := maxi(2, int(a.distance_to(b) / 0.5))
		for step in steps + 1:
			var p := a.lerp(b, float(step) / steps)
			for j in points.size():
				var pa: Vector3 = points[j]["pos"]
				var pb: Vector3 = points[(j + 1) % points.size()]["pos"]
				var closest := Geometry2D.get_closest_point_to_segment(p, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z))
				var edge := maxf(float(points[j]["w"]), float(points[(j + 1) % points.size()]["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET
				best = minf(best, p.distance_to(closest) - edge)
	return best


## Same measure over the transformed mesh vertices themselves rather than the AABB corners.
func _vertex_gap(mesh: Mesh, xf: Transform3D) -> float:
	var best := INF
	var points := _course.points
	for surface in mesh.get_surface_count():
		for vertex: Vector3 in (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var w := xf * vertex
			var p := Vector2(w.x, w.z)
			for j in points.size():
				var pa: Vector3 = points[j]["pos"]
				var pb: Vector3 = points[(j + 1) % points.size()]["pos"]
				var closest := Geometry2D.get_closest_point_to_segment(p, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z))
				var edge := maxf(float(points[j]["w"]), float(points[(j + 1) % points.size()]["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET
				best = minf(best, p.distance_to(closest) - edge)
	return best


func _test_rail_envelope() -> void:
	var apron_worst := INF
	var other_worst := INF
	var ground_worst := INF
	var checked := 0
	for record: Dictionary in _placements:
		if record["role"] in ["building", "prop"]:
			continue
		var id: String = record["id"]
		var mesh: Mesh = CityRealismCatalog.meshes[id]
		var xf: Transform3D = record["transform"]
		var polygon := CityRealismLayout.footprint(mesh.get_aabb(), xf)
		var boundary := _gap(polygon)
		var inside := false
		for point in _course.points:
			var pos: Vector3 = point["pos"]
			inside = inside or Geometry2D.is_point_in_polygon(Vector2(pos.x, pos.z), polygon)
		var vertices := _vertex_gap(mesh, xf)
		var gap := minf(boundary, vertices)
		checked += 1
		_check_once(not inside, "%s at s=%.0f does not enclose a road point" % [id, record["s"]], int(float(record["s"])))
		if id == "road_apron" and record["role"] == "apron":
			apron_worst = minf(apron_worst, gap)
			_check_once(gap >= APRON_CLEARANCE - 0.01, "apron at s=%.0f stays %.3f m outside the rail envelope" % [record["s"], gap], int(float(record["s"])))
		else:
			other_worst = minf(other_worst, gap)
			if id in GROUND:
				ground_worst = minf(ground_worst, gap)
			_check_once(gap >= SOLID_SETBACK - 0.05, "%s (%s) at s=%.0f keeps the %.1f m setback (%.2f)" % [id, record["role"], record["s"], SOLID_SETBACK, gap], int(float(record["s"])))
	print("CITY_GROUND_TESTS rail clearance: apron=%.3f other ground=%.3f lane/yard=%.3f over %d non-solid/ground records" % [apron_worst, other_worst, ground_worst, checked])
	_check("aprons exist and measure at least 0.05 m clear (%.3f)" % apron_worst, apron_worst >= APRON_CLEARANCE - 0.01 and apron_worst < INF)
	_check("all other ground keeps the 3.5 m setback (%.2f)" % other_worst, other_worst >= SOLID_SETBACK - 0.05)
	_check("service lanes and yards keep the 3.5 m setback (%.2f)" % ground_worst, ground_worst >= SOLID_SETBACK - 0.05)
	var solids_worst := INF
	for record: Dictionary in _placements.filter(func(p: Dictionary) -> bool: return p["role"] in ["building", "prop"]):
		solids_worst = minf(solids_worst, _gap(CityRealismLayout.footprint(CityRealismCatalog.meshes[record["id"]].get_aabb(), record["transform"])))
	_check("existing solid setback is unchanged by the exception (%.2f)" % solids_worst, solids_worst >= CityScenery.ROAD_CLEARANCE - 0.05)
	_check("ROAD_CLEARANCE constant is still 3.5", is_equal_approx(CityScenery.ROAD_CLEARANCE, SOLID_SETBACK))
	# Bend handling: half-length aprons are 8 m pieces; every apron scale must be 16 or 8 m.
	var lengths := {}
	for record: Dictionary in _placements.filter(func(p: Dictionary) -> bool: return p["id"] == "road_apron"):
		var xf: Transform3D = record["transform"]
		var length := snappedf(xf.basis.x.length() * WIDTH, 0.01)
		lengths[length] = int(lengths.get(length, 0)) + 1
	print("CITY_GROUND_TESTS apron lengths: ", lengths)
	_check("aprons are full (16 m) or half-length (8 m) pieces only", lengths.keys().all(func(l: float) -> bool: return is_equal_approx(l, 16.0) or is_equal_approx(l, 8.0)))


# --- budgets, actors, lights ------------------------------------------------------------------

func _test_budgets_and_actors() -> void:
	var total := 0
	var quarters := [0, 0, 0, 0]
	var ground_tris := 0
	for record: Dictionary in _placements:
		var tris := IndustrialMarketBenchmark.count_triangles(CityRealismCatalog.meshes[record["id"]])
		total += tris
		quarters[_quarter(float(record["s"]))] += tris
		if record["id"] in GROUND:
			ground_tris += tris
	_check("source-mesh triangles (%d) are within 900k and equal the report" % total, total <= GLOBAL_LIMIT and total == int(_converted.get_meta("triangle_count")))
	_check("quarters %s are within 240k and equal the report" % str(quarters), quarters.all(func(q: int) -> bool: return q <= QUARTER_LIMIT) and str(quarters) == str(_converted.get_meta("quarter_triangles")))
	var chunk_total := 0
	for chunk: MultiMeshInstance3D in _converted.find_children("Chunk*", "MultiMeshInstance3D", false, false):
		if chunk.get_meta("lod") == 0:
			chunk_total += IndustrialMarketBenchmark.count_triangles(chunk.multimesh.mesh)
	_check("merged near batches (%d) carry exactly the placed source triangles" % chunk_total, chunk_total == total)
	print("CITY_GROUND_TESTS triangles total=%d quarters=%s ground=%d" % [total, str(quarters), ground_tris])
	_check("ground adds geometry (%d tris)" % ground_tris, ground_tris > 0)
	_check("two actor pairs remain", int(_converted.get_meta("actor_pairs")) == 2 and _converted.has_node("ShopLife0") and _converted.has_node("ShopLife1") and not _converted.has_node("ShopLife2"))
	var lights: Array = _scenery.find_children("*", "Light3D", true, false)
	_check("city keeps exactly 12 lights (%d)" % lights.size(), lights.size() == 12)
	for id in GROUND:
		_check_once(CityRealismCatalog.entries[id].get("light_anchors", []).is_empty(), "%s declares no light anchors" % id, 0)


## Every ground record's transformed source vertices must be present in the merged chunk mesh, per material.
func _test_merged_ground() -> void:
	var chunk_by_index := {}
	for chunk: MultiMeshInstance3D in _converted.find_children("Chunk*", "MultiMeshInstance3D", false, false):
		if chunk.get_meta("lod") == 0:
			chunk_by_index[int(chunk.name.trim_prefix("Chunk").split("_")[0])] = chunk
	var records := 0
	var missing := 0
	var holders := {}
	for chunk_index: int in chunk_by_index:
		var chunk: MultiMeshInstance3D = chunk_by_index[chunk_index]
		var world := chunk.global_transform * chunk.multimesh.get_instance_transform(0)
		var buckets := {}
		var merged := chunk.multimesh.mesh
		for surface in merged.get_surface_count():
			var bucket := {}
			for vertex: Vector3 in (merged.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				bucket[Vector3i((world * vertex / VERTEX_CELL).round())] = true
			buckets[merged.surface_get_material(surface).resource_name] = bucket
		var root := _converted.global_transform
		for record: Dictionary in chunk.get_meta("placements"):
			if record["id"] not in GROUND:
				continue
			records += 1
			holders[record["id"]] = true
			var xf: Transform3D = root * (record["transform"] as Transform3D)
			var source: Mesh = CityRealismCatalog.meshes[record["id"]]
			for surface in source.get_surface_count():
				var bucket: Dictionary = buckets.get(source.surface_get_material(surface).resource_name, {})
				for vertex: Vector3 in (source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					if not _near_cell(bucket, Vector3i((xf * vertex / VERTEX_CELL).round())):
						missing += 1
	var placed := _placements.filter(func(p: Dictionary) -> bool: return p["id"] in GROUND).size()
	_check("every ground record (%d of %d) sits in exactly its 48 m chunk and the merge keeps its vertices (%d missing)" % [records, placed, missing], records == placed and placed > 0 and missing == 0)
	_check("all four ground meshes were merged", holders.size() == 4)
	var far_ground := 0
	for chunk: MultiMeshInstance3D in _converted.find_children("Chunk*", "MultiMeshInstance3D", false, false):
		if chunk.get_meta("lod") == 1:
			far_ground += (chunk.get_meta("placements") as Array).filter(func(p: Dictionary) -> bool: return p["id"] in GROUND).size()
	_check("far silhouette batches hold no ground", far_ground == 0)


func _near_cell(bucket: Dictionary, cell: Vector3i) -> bool:
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if bucket.has(cell + Vector3i(x, y, z)):
					return true
	return false


func _test_no_colliders_or_lights() -> void:
	_check("ground kit adds no collision objects to the city", _converted.find_children("*", "CollisionObject3D", true, false).is_empty())
	_check("no light node is parented to a ground record", _converted.find_children("*", "Light3D", true, false).all(func(l: Light3D) -> bool: return not (l.name as String).to_lower().contains("ground") and not (l.name as String).to_lower().contains("apron")))
	var reserved: Array = _converted.get_meta("reserved_bounds")
	var solids := _placements.filter(func(p: Dictionary) -> bool: return p["role"] in ["building", "prop"])
	_check("ground reserves nothing: reservations equal solid footprints (%d)" % reserved.size(), reserved.size() == solids.size())
	_check("ground never counts as a light anchor source", (_converted.get_node("LocalLighting") as CityRealismLighting).anchors.size() > 40)


# --- determinism ------------------------------------------------------------------------------

func _ground_signature(root: Node3D) -> String:
	var parts: Array = []
	for record: Dictionary in root.get_meta("placements"):
		if record["id"] in GROUND or record["id"] in ["curb_segment", "sidewalk_panel"]:
			parts.append([record["id"], record["role"], record["s"], record["side"], record["transform"], record["bounds"], record["chunk"]])
	parts.append((root.get_meta("rejected_slots") as Array).filter(func(r: Dictionary) -> bool: return r["id"] in GROUND))
	parts.append(root.get_meta("ground_fabric"))
	return var_to_str(parts)


func _test_determinism() -> void:
	var first := _ground_signature(_converted)
	var host := Node3D.new()
	add_child(host)
	var repeat := CityScenery.build(host, _course).get_node_or_null("CityRealism") as Node3D
	_check("repeating the build reproduces the ground layout", repeat != null and first == _ground_signature(repeat))
	var reverse_host := Node3D.new()
	add_child(reverse_host)
	var reverse := CityScenery.build(reverse_host, CourseCatalog.build_course("block_circuit", true)).get_node_or_null("CityRealism") as Node3D
	_check("reverse direction yields the identical ground layout", reverse != null and first == _ground_signature(reverse))
	_check("repeat and reverse keep ground_fabric true", repeat != null and reverse != null and repeat.get_meta("ground_fabric") == true and reverse.get_meta("ground_fabric") == true)
	host.free()
	reverse_host.free()


# --- fallback ---------------------------------------------------------------------------------

func _test_fallback(host: Node3D) -> void:
	var saved_meshes: Dictionary = {}
	var saved_costs: Dictionary = {}
	for id in GROUND:
		saved_meshes[id] = CityRealismCatalog.meshes[id]
		saved_costs[id] = CityRealismCatalog.costs[id]
	var baseline := CityRealismLayout.new(_course)
	baseline.populate(false)
	for id in GROUND:
		CityRealismCatalog.meshes.erase(id)
		CityRealismCatalog.costs.erase(id)
	var unavailable := not CityRealismCatalog.ground_available()
	var layout := CityRealismLayout.new(_course)
	layout.populate()
	var fallback := CityRealism.build(host, _course)
	var restored_ok := true
	for id in GROUND:
		CityRealismCatalog.meshes[id] = saved_meshes[id]
		CityRealismCatalog.costs[id] = saved_costs[id]
		restored_ok = restored_ok and CityRealismCatalog.meshes[id] == saved_meshes[id]
	_check("erasing the four ground mesh and cost entries marks the kit unavailable", unavailable)
	_check("fallback layout disables the ground fabric", not layout.ground_enabled)
	_check("fallback places no ground-kit piece", layout.placements.all(func(p: Dictionary) -> bool: return p["id"] not in GROUND and p["role"] != "apron"))
	var curbs := layout.placements.filter(func(p: Dictionary) -> bool: return p["id"] == "curb_segment").size()
	var panels := layout.placements.filter(func(p: Dictionary) -> bool: return p["id"] == "sidewalk_panel").size()
	_check("fallback retains the full curb run, only bend slots rejected (%d curbs / %d panels)" % [curbs, panels], curbs * 10 >= panels * 9 and curbs <= panels + 4)
	var fallback_lights := 0 if fallback == null else fallback.find_children("*", "Light3D", true, false).size()
	_check("fallback has the same light count as the ground build (%d)" % fallback_lights, fallback != null and fallback_lights == _converted.find_children("*", "Light3D", true, false).size())
	_check("fallback layout equals the explicit pavement/curb layout", var_to_str(layout.placements) == var_to_str(baseline.placements) and var_to_str(layout.rejected) == var_to_str(baseline.rejected) and layout.triangles == baseline.triangles)
	_check("fallback build succeeds with ground_fabric false", fallback != null and fallback.get_meta("ground_fabric") == false)
	_check("fallback still places >= 29 buildings of all 8 families and 2 actor pairs", fallback != null and (fallback.get_meta("placements") as Array).filter(func(p: Dictionary) -> bool: return p["role"] == "building").size() >= 29 and int(fallback.get_meta("actor_pairs")) == 2)
	_check("fallback stays within the global and quarter budgets", fallback != null and int(fallback.get_meta("triangle_count")) <= GLOBAL_LIMIT and (fallback.get_meta("quarter_triangles") as Array).all(func(q: int) -> bool: return q <= QUARTER_LIMIT))
	if fallback != null:
		fallback.free()
	_check("restoring the cache restores the ground kit", restored_ok and CityRealismCatalog.ground_available())
	var again := CityRealism.build(host, _course)
	_check("a rebuild after restoring has the ground fabric again", again != null and again.get_meta("ground_fabric") == true and _ground_signature(again) == _ground_signature(_converted))
	if again != null:
		again.free()


# --- hashes and detectors ---------------------------------------------------------------------

func _asset_hashes() -> Dictionary:
	var out := {}
	for directory in [REALISM_DIRECTORY, TEXTURE_DIRECTORY, IndustrialMarketBenchmark.DIRECTORY]:
		var dir := DirAccess.open(directory)
		if dir == null:
			continue
		for file in dir.get_files():
			if file.get_extension() in ["glb", "png"]:
				out[directory + file] = FileAccess.get_sha256(directory + file)
	return out


func _test_detectors() -> void:
	_check("detector: _near_cell tolerates one cell of drift and rejects two", _near_cell({Vector3i(1, 1, 1): true}, Vector3i(2, 1, 1)) and not _near_cell({Vector3i(1, 1, 1): true}, Vector3i(3, 1, 1)))
	_check("detector: footprint polygon corners map through the transform", CityRealismLayout.footprint(AABB(Vector3(-1, 0, -1), Vector3(2, 1, 2)), Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))[0].is_equal_approx(Vector2(4, -1)))


# --- helpers ----------------------------------------------------------------------------------

func _check_once(condition: bool, label: String, index: int) -> void:
	if not condition:
		_check("%s at %d" % [label, index], false)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
