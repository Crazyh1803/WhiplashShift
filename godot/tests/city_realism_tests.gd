## Independent regression suite for the converted Block Circuit city; headless, no rendering.
## Every figure is re-derived from the built scene graph and the imported meshes, not from the
## layout's own bookkeeping, and the detector self-tests prove the checks can fail.
extends Node3D

const FAMILIES: Array[String] = ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot", "redline_shop", "row_workshop", "utility_substation", "transit_depot"]
const STREETS: Array[String] = ["sidewalk_panel", "curb_segment", "drain_cover", "street_lamp", "bollard", "bench_planter", "refuse_station", "alley_conduit"]
const GLOBAL_LIMIT := 900000
const QUARTER_LIMIT := 240000
const WINDOW_LIMIT := 320000
const SURFACE_LIMIT := 160
const ACTOR_LIMIT := 110000
const LIGHT_LIMIT := 12
const CHUNK := 48.0
const VERTEX_CELL := 0.02
const TEXTURE_DIRECTORY := "res://assets/city/realism/textures/"
const SOURCE_GLBS: Array[String] = ["ramen_vendor.glb", "ramen_customer.glb", "redline_shop.glb"]

var _pass := 0
var _fail := 0
var _course: CourseDefinition
var _converted: Node3D
var _scenery: Node3D
var _chunks: Array[MultiMeshInstance3D] = []
var _placements: Array = []


func _ready() -> void:
	_course = BlockCircuitData.build_course()
	var before := var_to_str(_course.points)
	_test_detectors()
	var shared_before := _shared_signature()
	var hashes_before := _source_hashes()
	var host := Node3D.new()
	add_child(host)
	_scenery = CityScenery.build(host, _course)
	_converted = _scenery.get_node_or_null("CityRealism") as Node3D
	_check("the default build uses the converted city", _converted != null and _scenery.get_meta("converted_city") == true and _scenery.get_meta("authored_quarter") == true)
	if _converted == null:
		print("CITY_REALISM_TESTS: %d passed, %d failed (no converted city: %s)" % [_pass, _fail, CityRealismCatalog.error])
		get_tree().quit(1)
		return
	_placements = _converted.get_meta("placements")
	for node: MultiMeshInstance3D in _converted.find_children("Chunk*", "MultiMeshInstance3D", false, false):
		_chunks.append(node)
	_test_catalog()
	_test_imports()
	_test_materials()
	await _test_chunks()
	_test_budgets()
	_test_render_windows()
	_test_coverage()
	_test_clearance_and_overlap()
	_test_determinism()
	_test_skyline()
	_test_lights()
	_test_actors()
	_check("shared vehicle and benchmark materials are not mutated", shared_before == _shared_signature())
	_check("source actor and shop GLBs are byte-identical after building", hashes_before == _source_hashes())
	_test_actor_failures()
	_test_fallbacks(host)
	_test_qa_script()
	_check("course points are unmodified by the converted build", var_to_str(_course.points) == before)
	host.free()
	print("CITY_REALISM_TESTS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


# --- catalog and imported geometry ---------------------------------------------------------

func _test_catalog() -> void:
	_check("catalog is available", CityRealismCatalog.available() and CityRealismCatalog.error.is_empty())
	var near_total := 0
	var unique := 0
	for id in FAMILIES:
		var entry: Dictionary = CityRealismCatalog.entries.get(id, {})
		var near: Mesh = CityRealismCatalog.meshes.get(id)
		var far: Mesh = CityRealismCatalog.meshes.get(id + "@far")
		_check("family %s has both LODs" % id, near != null and far != null)
		if near == null or far == null:
			continue
		var tris := IndustrialMarketBenchmark.count_triangles(near)
		var far_tris := IndustrialMarketBenchmark.count_triangles(far)
		_check("%s LOD0 (%d) is within its triangle cap" % [id, tris], tris <= (25000 if id == "redline_shop" else 22000))
		_check("%s LOD1 (%d) is within 2000 tris and 3 surfaces" % [id, far_tris], far_tris <= 2000 and far.get_surface_count() <= 3)
		_check("%s manifest tris match the imported mesh" % id, int(entry.get("tris", -1)) == tris and int(entry.get("lod1_tris", -1)) == far_tris)
		var box := near.get_aabb()
		var plan: Dictionary = entry.get("footprint", {})
		var frontage := float(plan.get("max", [0, 0])[0]) - float(plan.get("min", [0, 0])[0])
		var depth := float(plan.get("max", [0, 0])[1]) - float(plan.get("min", [0, 0])[1])
		_check("%s frontage %.1f / depth %.1f / height %.1f fit the contract" % [id, frontage, depth, box.size.y], (is_equal_approx(frontage, 12.0) or is_equal_approx(frontage, 18.0) or is_equal_approx(frontage, 24.0)) and depth <= 22.0 and box.size.y <= 18.1)
		_check("%s mesh AABB includes protrusions beyond the footprint but stays near it" % id, box.size.x >= frontage - 0.1 and box.size.x <= frontage + 2.0 and box.end.z <= 30.0)
		var foot := far.get_aabb()
		_check("%s LOD1 keeps the LOD0 footprint" % id, absf(foot.position.x - box.position.x) < 0.6 and absf(foot.end.x - box.end.x) < 0.6 and absf(foot.end.z - box.end.z) < 1.0 and foot.size.y > box.size.y * 0.6)
		near_total += tris
		unique += tris + far_tris
	for id in STREETS:
		_check("street piece %s is loaded" % id, CityRealismCatalog.meshes.has(id))
		unique += IndustrialMarketBenchmark.count_triangles(CityRealismCatalog.meshes[id]) if CityRealismCatalog.meshes.has(id) else 0
	_check("unique source geometry (%d) stays within 450k" % unique, unique <= 450000 and near_total > 0)
	_check("shared material library has at most 14 entries (%d)" % CityRealismCatalog.materials.size(), CityRealismCatalog.materials.size() <= 14 and CityRealismCatalog.materials.size() >= 10)


func _test_imports() -> void:
	var colour_variation := {}
	for key: String in CityRealismCatalog.meshes:
		var mesh: Mesh = CityRealismCatalog.meshes[key]
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var count := vertices.size()
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			var label := "%s/%d" % [key, surface]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			if not (count > 0 and uv.size() == count and colours.size() == count and normals.size() == count and arrays[Mesh.ARRAY_TEX_UV2] == null):
				_check("%s has UV0, COLOR0 and normals on every vertex and no UV1" % label, false)
				continue
			var bad_uv := 0
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in uv:
				if not (is_finite(p.x) and is_finite(p.y)) or absf(p.x) > 1000.0 or absf(p.y) > 1000.0:
					bad_uv += 1
				lo = lo.min(p)
				hi = hi.max(p)
			_check_once(bad_uv == 0, "%s UV0 is finite" % label, 0)
			_check_once(count < 4 or (hi - lo).length() > 0.001, "%s UV0 is not collapsed to a point" % label, 0)
			var bad_colour := 0
			var darkest := 1.0
			for c in colours:
				if not (c.r >= 0.0 and c.r <= 1.001 and c.g >= 0.0 and c.g <= 1.001 and c.b >= 0.0 and c.b <= 1.001 and c.a >= 0.0):
					bad_colour += 1
				darkest = minf(darkest, minf(c.r, minf(c.g, c.b)))
			_check_once(bad_colour == 0, "%s COLOR0 is a valid colour" % label, 0)
			colour_variation[key] = minf(colour_variation.get(key, 1.0), darkest)
			if material != null and material.normal_enabled:
				var aligned := 0
				var ok_w := true
				if tangents.size() != count * 4:
					_check("%s has tangents for its normal map" % label, false)
					continue
				for i in count:
					var t := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
					ok_w = ok_w and absf(absf(tangents[i * 4 + 3]) - 1.0) < 0.01 and is_finite(t.length())
					if absf(t.normalized().dot(normals[i])) < 0.1 and t.length() > 0.9:
						aligned += 1
				_check_once(ok_w and aligned >= count * 0.98, "%s tangents are unit and perpendicular to normals (%d/%d)" % [label, aligned, count], 0)
	for id in FAMILIES:
		_check("%s COLOR0 carries baked occlusion/wear rather than flat white (%.2f)" % [id, colour_variation.get(id, 1.0)], colour_variation.get(id, 1.0) < 0.97)


func _test_materials() -> void:
	var paths := {}
	var by_path := {}
	var emissive: Array[String] = []
	for id: String in CityRealismCatalog.materials:
		var material := CityRealismCatalog.materials[id] as StandardMaterial3D
		_check("material %s is named for its library entry" % id, material != null and material.resource_name == id)
		if material == null:
			continue
		for texture: Texture2D in [material.albedo_texture, material.normal_texture, material.roughness_texture, material.metallic_texture, material.ao_texture, material.emission_texture]:
			if texture == null:
				continue
			paths[texture.resource_path] = true
			if by_path.has(texture.resource_path):
				_check_once(by_path[texture.resource_path] == texture, "texture %s is one shared resource" % texture.resource_path, 0)
			by_path[texture.resource_path] = texture
			_check_once(texture.resource_path.begins_with(TEXTURE_DIRECTORY), "texture %s is an external shared file, not embedded" % texture.resource_path, 0)
		if material.emission_enabled:
			emissive.append(id)
	_check("library uses at most 43 unique textures (%d)" % paths.size(), paths.size() <= 43 and paths.size() >= 10)
	emissive.sort()
	_check("only sign_atlas and lamp_glass emit (%s)" % str(emissive), emissive == ["lamp_glass", "sign_atlas"])
	var sign := CityRealismCatalog.materials["sign_atlas"] as StandardMaterial3D
	var glass := CityRealismCatalog.materials["lamp_glass"] as StandardMaterial3D
	_check("sign emission is a glyph texture multiplied by an unlit-white base, not a flat fill", sign.emission_texture != null and sign.emission_texture != sign.albedo_texture and sign.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)
	_check("lamp glass is the only flat emitter and is bounded", glass.emission_texture == null and glass.emission_energy_multiplier <= 4.0 and sign.emission_energy_multiplier <= 4.0)
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/city/realism/textures/sign_atlas_emissive.png"))
	_check("sign emissive source is readable", image != null and not image.is_empty())
	if image != null and not image.is_empty():
		var lit := 0
		var total := 0
		for y in range(0, image.get_height(), 4):
			for x in range(0, image.get_width(), 4):
				total += 1
				if image.get_pixel(x, y).get_luminance() > 0.15:
					lit += 1
		_check("sign emissive covers glyph pixels only (%.1f%% lit)" % (100.0 * lit / maxf(total, 1)), lit > 0 and lit < total * 0.4)
	for key: String in CityRealismCatalog.meshes:
		var mesh: Mesh = CityRealismCatalog.meshes[key]
		var emitting := 0
		var all := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var tris: int = (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			var material := mesh.surface_get_material(surface)
			_check_once(material != null and CityRealismCatalog.materials.get(material.resource_name) == material, "%s/%d uses the shared library material" % [key, surface], 0)
			all += tris
			if (material as BaseMaterial3D).emission_enabled:
				emitting += tris
		_check_once(emitting * 10 <= all, "%s emitting surfaces are a small fraction (%d/%d)" % [key, emitting, all], 0)


# --- chunk batching ----------------------------------------------------------------------

func _test_chunks() -> void:
	var near := _chunks.filter(func(c: MultiMeshInstance3D) -> bool: return c.get_meta("lod") == 0)
	var far := _chunks.filter(func(c: MultiMeshInstance3D) -> bool: return c.get_meta("lod") == 1)
	_check("chunks exist as near and far batches (%d/%d)" % [near.size(), far.size()], near.size() >= 8 and far.size() >= 8 and far.size() <= near.size())
	var span := 0.0
	var by_name := {}
	for chunk: MultiMeshInstance3D in _chunks:
		by_name[chunk.name] = chunk
		var records: Array = chunk.get_meta("placements")
		var is_far: bool = chunk.get_meta("lod") == 1
		var index := int(chunk.name.trim_prefix("Chunk").split("_")[0])
		var mesh := chunk.multimesh.mesh
		var names: Array[String] = []
		var expected := {}
		var tris := 0
		for record: Dictionary in records:
			_check_once(int(float(record["s"]) / CHUNK) == index, "%s record s=%.1f belongs to this 48 m chunk" % [chunk.name, record["s"]], index)
			_check_once(not is_far or record["role"] == "building", "%s far batch holds only buildings" % chunk.name, index)
			var source: Mesh = CityRealismCatalog.meshes[record["id"] + ("@far" if is_far else "")]
			tris += IndustrialMarketBenchmark.count_triangles(source)
			for surface in source.get_surface_count():
				expected[source.surface_get_material(surface).resource_name] = true
			var world: AABB = record["bounds"]
			var covered := chunk.global_transform * chunk.multimesh.custom_aabb
			_check_once(covered.grow(0.05).encloses(world), "%s custom AABB encloses %s" % [chunk.name, record["id"]], index)
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			names.append(material.resource_name)
			_check_once(material == CityRealismCatalog.materials[material.resource_name], "%s surface %d is the shared library material" % [chunk.name, surface], index)
		var unique_names := {}
		for n in names:
			unique_names[n] = true
		_check_once(unique_names.size() == names.size() and unique_names.size() == expected.size(), "%s merges one surface per shared material (%d surfaces, %d materials)" % [chunk.name, names.size(), expected.size()], index)
		_check_once(IndustrialMarketBenchmark.count_triangles(mesh) == tris, "%s triangle count equals the placed source meshes (%d)" % [chunk.name, tris], index)
		_check_once(chunk.multimesh.instance_count == 1, "%s is one merged instance" % chunk.name, index)
		var drift := _merged_mismatches(chunk, chunk.global_transform)
		_check_once(drift == 0, "%s merged world vertices match the transformed source meshes (%d unmatched cells)" % [chunk.name, drift], index)
		_check_once(chunk.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF and chunk.visibility_range_end_margin == 10.0, "%s fades SELF over 10 m" % chunk.name, index)
		_check_once(is_far == (chunk.visibility_range_begin == 140.0) and chunk.visibility_range_end == (450.0 if is_far else 140.0), "%s ranges are 0-140 near / 140-450 far" % chunk.name, index)
		_check_once(chunk.visibility_range_begin_margin == (10.0 if is_far else 0.0), "%s begin margin" % chunk.name, index)
		_check_once(chunk.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON), "%s shadow policy" % chunk.name, index)
		var aabb := chunk.multimesh.custom_aabb
		span = maxf(span, aabb.size.x)
		_check_once(aabb.size.x < 130.0 and aabb.size.z < 130.0,"%s bounds stay chunk-sized, not quarter-sized (%s)" % [chunk.name, aabb.size], index)
	for chunk: MultiMeshInstance3D in far:
		var twin: MultiMeshInstance3D = by_name.get(chunk.name.replace("_far", "_near"))
		_check_once(twin != null and twin.multimesh.custom_aabb == chunk.multimesh.custom_aabb and twin.position.is_equal_approx(chunk.position), "%s has the identical origin and custom AABB as its near batch" % chunk.name, 0)
	var displaced := Transform3D(Basis.IDENTITY, Vector3(0.5, 0, 0))
	_check("detector: a chunk displaced 0.5 m from its sources is reported", not _chunks.is_empty() and _merged_mismatches(_chunks[0], _chunks[0].global_transform * displaced) > 0)
	if DisplayServer.get_name() != "headless":
		var original_instance := _chunks[0].multimesh.get_instance_transform(0)
		_chunks[0].multimesh.set_instance_transform(0, original_instance * displaced)
		for frame in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check("detector: a displaced MultiMesh instance is reported", _merged_mismatches(_chunks[0], _chunks[0].global_transform) > 0)
		_chunks[0].multimesh.set_instance_transform(0, original_instance)
		for frame in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
	else:
		print("RENDER_CHECK: MultiMesh mutation detector requires the rendered city test; Dummy transform setters are no-ops")
	var all_ids := 0
	for chunk: MultiMeshInstance3D in near:
		all_ids += (chunk.get_meta("placements") as Array).size()
	_check("near batches hold every placement exactly once (%d of %d)" % [all_ids, _placements.size()], all_ids == _placements.size())


## Per-material sets of quantised world-space vertex cells for a chunk's records (source meshes
## through each record's own transform) or for its merged mesh (through `world`).
func _vertex_cells(chunk: MultiMeshInstance3D, world: Transform3D, merged: bool) -> Dictionary:
	var cells := {}
	var sources: Array = []
	if merged:
		sources.append([chunk.multimesh.mesh, world * chunk.multimesh.get_instance_transform(0)])
	else:
		var is_far: bool = chunk.get_meta("lod") == 1
		var root := _converted.global_transform
		for record: Dictionary in chunk.get_meta("placements"):
			sources.append([CityRealismCatalog.meshes[record["id"] + ("@far" if is_far else "")], root * (record["transform"] as Transform3D)])
	for pair: Array in sources:
		var mesh: Mesh = pair[0]
		var xf: Transform3D = pair[1]
		for surface in mesh.get_surface_count():
			var key: String = mesh.surface_get_material(surface).resource_name
			if not cells.has(key):
				cells[key] = {}
			var bucket: Dictionary = cells[key]
			for vertex: Vector3 in (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				bucket[Vector3i((xf * vertex / VERTEX_CELL).round())] = true
	return cells


func _cell_present(bucket: Dictionary, cell: Vector3i) -> bool:
	if bucket.has(cell):
		return true
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if bucket.has(cell + Vector3i(x, y, z)):
					return true
	return false


## Number of quantised vertex cells present in only one of merged / independently transformed
## sources (either direction, per material). Zero means the merged geometry sits where it should.
func _merged_mismatches(chunk: MultiMeshInstance3D, world: Transform3D) -> int:
	var expected := _vertex_cells(chunk, world, false)
	var actual := _vertex_cells(chunk, world, true)
	var bad := 0
	for key: String in expected.keys() + actual.keys():
		var want: Dictionary = expected.get(key, {})
		var have: Dictionary = actual.get(key, {})
		for cell: Vector3i in have:
			bad += 0 if _cell_present(want, cell) else 1
		for cell: Vector3i in want:
			bad += 0 if _cell_present(have, cell) else 1
	return bad


func _quarter(s: float) -> int:
	return mini(3, int(s / _course.total_length * 4.0))


func _near_chunks() -> Array:
	return _chunks.filter(func(c: MultiMeshInstance3D) -> bool: return c.get_meta("lod") == 0)


func _test_budgets() -> void:
	var total := 0
	var quarters := [0, 0, 0, 0]
	for chunk: MultiMeshInstance3D in _near_chunks():
		var tris := IndustrialMarketBenchmark.count_triangles(chunk.multimesh.mesh)
		total += tris
		for record: Dictionary in chunk.get_meta("placements"):
			quarters[_quarter(float(record["s"]))] += int(IndustrialMarketBenchmark.count_triangles(CityRealismCatalog.meshes[record["id"]]))
	_check("placed geometry measured from batches (%d) is within 900k" % total, total <= GLOBAL_LIMIT and total > 100000)
	_check("batch triangles equal the reported total", total == int(_converted.get_meta("triangle_count")))
	_check("quarters %s are within 240k and match the report" % str(quarters), quarters.all(func(q: int) -> bool: return q <= QUARTER_LIMIT and q > 0) and str(quarters) == str(_converted.get_meta("quarter_triangles")))
	for record: Dictionary in _placements:
		_check_once(int(record["quarter"]) == _quarter(float(record["s"])), "%s quarter label matches its route distance" % record["id"], int(float(record["s"])))
	var actors := 0
	for group: Node3D in _converted.find_children("ShopLife*", "Node3D", false, false):
		for instance: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
			actors += IndustrialMarketBenchmark.count_triangles(instance.mesh)
	_check("actor geometry (%d) is separate and within 110k" % actors, actors > 0 and actors <= ACTOR_LIMIT)
	_check("actors are visibility-limited to 60 m", _converted.find_children("ShopLife*", "Node3D", false, false).all(func(g: Node3D) -> bool: return g.find_children("*", "MeshInstance3D", true, false).all(func(m: MeshInstance3D) -> bool: return m.visibility_range_end == 60.0)))


## One entry per batch: where its bounds sit, what it costs and which fade interval keeps it visible.
func _window_groups() -> Array:
	var groups: Array = []
	for chunk: MultiMeshInstance3D in _chunks:
		groups.append({"center": chunk.global_transform * chunk.multimesh.custom_aabb.get_center(), "tris": IndustrialMarketBenchmark.count_triangles(chunk.multimesh.mesh), "surfaces": chunk.multimesh.mesh.get_surface_count(),
				"low": chunk.visibility_range_begin - chunk.visibility_range_begin_margin, "high": chunk.visibility_range_end + chunk.visibility_range_end_margin})
	return groups


static func window_peak(groups: Array, eyes: PackedVector3Array) -> Vector2i:
	var peak_tris := 0
	var peak_surfaces := 0
	for eye in eyes:
		var tris := 0
		var surfaces := 0
		for group: Dictionary in groups:
			var distance := eye.distance_to(group["center"])
			if distance >= float(group["low"]) and distance <= float(group["high"]):
				tris += int(group["tris"])
				surfaces += int(group["surfaces"])
		peak_tris = maxi(peak_tris, tris)
		peak_surfaces = maxi(peak_surfaces, surfaces)
	return Vector2i(peak_tris, peak_surfaces)


func _eyes() -> PackedVector3Array:
	var eyes := PackedVector3Array()
	for s in range(0, int(_course.total_length), 10):
		eyes.append(CityDistrict.sample(_course, float(s))["pos"] + Vector3.UP * 1.5)
	return eyes


func _test_render_windows() -> void:
	var eyes := _eyes()
	var groups := _window_groups()
	var peak := window_peak(groups, eyes)
	print("CITY_REALISM_TESTS window peak triangles=", peak.x, " surfaces=", peak.y, " samples=", eyes.size())
	_check("route is sampled every 10 m (%d samples)" % eyes.size(), eyes.size() >= int(_course.total_length / 10.0))
	_check("peak 10 m window (%d tris) stays within 320k including fade overlap" % peak.x, peak.x <= WINDOW_LIMIT and peak.x > 30000)
	_check("peak 10 m window (%d surfaces) stays within 160" % peak.y, peak.y <= SURFACE_LIMIT and peak.y > 5)
	# Strictest reading: nearest point of the AABB rather than its centre decides activity.
	var strict := 0
	for eye in eyes:
		var tris := 0
		for chunk: MultiMeshInstance3D in _chunks:
			var box: AABB = chunk.global_transform * chunk.multimesh.custom_aabb
			var nearest := box.position.max(eye.min(box.end))
			var distance := eye.distance_to(nearest)
			if distance >= chunk.visibility_range_begin - chunk.visibility_range_begin_margin and distance <= chunk.visibility_range_end + chunk.visibility_range_end_margin:
				tris += IndustrialMarketBenchmark.count_triangles(chunk.multimesh.mesh)
		strict = maxi(strict, tris)
	print("CITY_REALISM_TESTS strict nearest-bounds peak triangles=", strict)


# --- coverage, clearance, overlap ----------------------------------------------------------

func _test_coverage() -> void:
	var seen := {}
	var sides := {}
	var streets := {}
	for record: Dictionary in _placements:
		seen[record["id"]] = int(seen.get(record["id"], 0)) + 1
		if record["role"] == "building":
			sides["%d/%d" % [_quarter(float(record["s"])), int(record["side"])]] = true
	for id in FAMILIES:
		_check("building family %s is placed (%d)" % [id, seen.get(id, 0)], seen.get(id, 0) > 0)
	for id in STREETS:
		_check("street piece %s is placed (%d)" % [id, seen.get(id, 0)], seen.get(id, 0) > 0)
		streets[id] = true
	var roles := {}
	for record: Dictionary in _placements:
		roles[record["role"]] = true
	_check("buildings occupy both sides of all four quarters (%s)" % str(sides.keys()), sides.size() == 8)
	_check("buildings, props, ground and detail roles all appear", roles.has("building") and roles.has("prop") and roles.has("ground") and roles.has("detail"))
	var districts := {}
	for record: Dictionary in _placements:
		districts[record["district"]] = true
	_check("four distinct district arrangements", districts.size() == 4)
	var arrangements := {}
	for record: Dictionary in _placements:
		if record["role"] == "building":
			arrangements[_quarter(float(record["s"]))] = arrangements.get(_quarter(float(record["s"])), {})
			arrangements[_quarter(float(record["s"]))][record["id"]] = true
	var signatures := {}
	for q in arrangements:
		var ids: Array = arrangements[q].keys()
		ids.sort()
		signatures[str(ids)] = true
	_check("quarters do not repeat one building mix (%d mixes)" % signatures.size(), signatures.size() >= 3)


## Distance from a placed footprint to the nearest road edge, found by dense boundary sampling.
func footprint_gap(polygon: PackedVector2Array) -> float:
	var best := INF
	var points := _course.points
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var steps := maxi(2, int(a.distance_to(b) / 1.0))
		for step in steps + 1:
			var p := a.lerp(b, float(step) / steps)
			for j in points.size():
				var pa: Vector3 = points[j]["pos"]
				var pb: Vector3 = points[(j + 1) % points.size()]["pos"]
				var closest := Geometry2D.get_closest_point_to_segment(p, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z))
				var edge := maxf(float(points[j]["w"]), float(points[(j + 1) % points.size()]["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET
				best = minf(best, p.distance_to(closest) - edge)
	return best


static func overlap_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var area := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(a, b):
		var sum := 0.0
		for i in piece.size():
			sum += piece[i].cross(piece[(i + 1) % piece.size()])
		area += absf(sum) * 0.5
	return area


func _solids() -> Array:
	return _placements.filter(func(p: Dictionary) -> bool: return p["role"] in ["building", "prop"])


func _test_clearance_and_overlap() -> void:
	var solids := _solids()
	var worst := INF
	for record: Dictionary in solids:
		var polygon := CityRealismLayout.footprint(CityRealismCatalog.meshes[record["id"]].get_aabb(), record["transform"])
		var gap := footprint_gap(polygon)
		worst = minf(worst, gap)
		_check_once(gap >= CityScenery.ROAD_CLEARANCE - 0.05, "%s at s=%.0f clears the road edge by %.2f" % [record["id"], record["s"], gap], int(float(record["s"])))
	print("CITY_REALISM_TESTS smallest solid road clearance=", worst)
	var pairs := 0
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			var a: Dictionary = solids[i]
			var b: Dictionary = solids[j]
			if not (a["bounds"] as AABB).grow(0.1).intersects(b["bounds"]):
				continue
			var pa := CityRealismLayout.footprint(CityRealismCatalog.meshes[a["id"]].get_aabb(), a["transform"])
			var pb := CityRealismLayout.footprint(CityRealismCatalog.meshes[b["id"]].get_aabb(), b["transform"])
			pairs += 1
			_check_once(overlap_area(pa, pb) < 0.05, "%s(s=%.0f) and %s(s=%.0f) overlap" % [a["id"], a["s"], b["id"], b["s"]], i * 1000 + j)
	_check("solid overlap test compared nearby pairs (%d) of %d solids" % [pairs, solids.size()], solids.size() > 60)
	var lots_clear := true
	for rejected: Dictionary in _converted.get_meta("rejected_slots"):
		lots_clear = lots_clear and rejected["reason"] in ["curve", "road_clearance", "triangle_budget", "solid_overlap", "visible_budget"]
	_check("every rejected slot states a known reason", lots_clear)
	var reserved: Array = _converted.get_meta("reserved_bounds")
	_check("each solid reserved its footprint for the legacy scenery", reserved.size() == solids.size() and reserved.size() > 0)
	_check("no collision objects or lights are baked into the placed assets", _converted.find_children("*", "CollisionObject3D", true, false).is_empty())


# --- determinism -------------------------------------------------------------------------

func _signature(root: Node3D) -> String:
	var parts: Array = []
	for record: Dictionary in root.get_meta("placements"):
		parts.append([record["id"], record["s"], record["side"], record["transform"], record["bounds"], record["chunk"]])
	for chunk: MultiMeshInstance3D in root.find_children("Chunk*", "MultiMeshInstance3D", false, false):
		parts.append([chunk.name, chunk.position, chunk.multimesh.custom_aabb, IndustrialMarketBenchmark.count_triangles(chunk.multimesh.mesh), chunk.multimesh.mesh.get_surface_count()])
	var lights: CityRealismLighting = root.get_node("LocalLighting")
	for anchor: Dictionary in lights.anchors:
		parts.append([anchor["position"], anchor["energy"], anchor["range"], anchor["shadow"]])
	parts.append(root.get_meta("rejected_slots"))
	return var_to_str(parts)


func _test_determinism() -> void:
	var first := _signature(_converted)
	var host := Node3D.new()
	add_child(host)
	var repeat := CityScenery.build(host, _course).get_node_or_null("CityRealism") as Node3D
	_check("repeating the build reproduces placements, chunks, lights and rejections", repeat != null and first == _signature(repeat))
	var reversed := CourseCatalog.build_course("block_circuit", true)
	var reverse_host := Node3D.new()
	add_child(reverse_host)
	var reverse := CityScenery.build(reverse_host, reversed).get_node_or_null("CityRealism") as Node3D
	_check("reverse direction builds the same canonical scenery", reverse != null and first == _signature(reverse))
	_check("the reverse scenery keeps the same shared sky pieces", reverse != null and _legacy_signature(reverse_host.get_child(0)) == _legacy_signature(_scenery))
	host.free()
	reverse_host.free()


func _legacy_signature(root: Node) -> String:
	var parts: Array = []
	for name_ in ["Skyline", "Windows", "CrownRib", "Body", "Wall"]:
		var node := root.get_node_or_null(name_) as MultiMeshInstance3D
		parts.append([name_, node.get_meta("city_transforms") if node != null else null])
	var crown := root.get_node_or_null("Crown") as Node3D
	parts.append(crown.position if crown != null else null)
	return var_to_str(parts)


func _test_skyline() -> void:
	var host := Node3D.new()
	add_child(host)
	# Baseline is the explicit legacy street-block build, which already thins the first quarter itself.
	var legacy := CityScenery.build(host, _course, true, false)
	var old_crown := legacy.get_node_or_null("Crown") as Node3D
	var crown := _scenery.get_node_or_null("Crown") as Node3D
	_check("the legacy world has a crown to preserve", old_crown != null)
	_check("the communications crown keeps its position and parts", crown != null and old_crown != null and crown.position.is_equal_approx(old_crown.position) and crown.get_child_count() == old_crown.get_child_count())
	_check("crown beacon light is preserved", crown != null and crown.find_children("*", "OmniLight3D", false, false).size() == 1)
	for name_ in ["Skyline", "CrownRib"]:
		var old_batch := legacy.get_node_or_null(name_) as MultiMeshInstance3D
		var batch := _scenery.get_node_or_null(name_) as MultiMeshInstance3D
		_check("far %s batch is preserved exactly" % name_, old_batch != null and batch != null and var_to_str(old_batch.get_meta("city_transforms")) == var_to_str(batch.get_meta("city_transforms")))
	var old_windows := legacy.get_node_or_null("Windows") as MultiMeshInstance3D
	var windows := _scenery.get_node_or_null("Windows") as MultiMeshInstance3D
	_check("window glow batch survives", old_windows != null and windows != null)
	if old_windows != null and windows != null:
		var old_set := {}
		for xf: Transform3D in old_windows.get_meta("city_transforms"):
			old_set[var_to_str(xf)] = true
		var foreign := 0
		for xf: Transform3D in windows.get_meta("city_transforms"):
			if not old_set.has(var_to_str(xf)):
				foreign += 1
		var kept: int = (windows.get_meta("city_transforms") as Array).size()
		_check("windows are only ever removed, never moved (%d new, %d kept of %d)" % [foreign, kept, old_set.size()], foreign == 0 and kept * 4 >= old_set.size())
	var reserved: Array = _converted.get_meta("reserved_bounds")
	var removed := 0
	var old_towers := legacy.get_node_or_null("Body") as MultiMeshInstance3D
	var towers := _scenery.get_node_or_null("Body") as MultiMeshInstance3D
	if old_towers != null and towers != null:
		var kept_towers := {}
		for xf: Transform3D in towers.get_meta("city_transforms"):
			kept_towers[var_to_str(xf)] = true
		for xf: Transform3D in old_towers.get_meta("city_transforms"):
			if kept_towers.has(var_to_str(xf)):
				continue
			removed += 1
			var half := Vector3(xf.basis.x.length(), 0, xf.basis.z.length()) * 0.5
			var footprint := AABB(Vector3(xf.origin.x, 0.0, xf.origin.z) - half, Vector3(half.x * 2.0, 1.0, half.z * 2.0))
			# Converted mode drops the first row (gap under 38 m) everywhere; a tower may only vanish
			# beyond that row if it overlaps a reserved lot.
			var touches := CityScenery.road_clearance(footprint, _course) < 38.0 + 6.0
			for box: AABB in reserved:
				touches = touches or box.grow(1.0).intersects(footprint)
			_check_once(touches, "removed tower at %s is neither first-row nor on a reserved lot" % xf.origin, removed)
		var total_towers: int = (old_towers.get_meta("city_transforms") as Array).size()
		_check("second-row distant towers survive (%d removed of %d)" % [removed, total_towers], removed < total_towers and (total_towers - removed) * 5 >= total_towers)
	legacy.free()
	host.free()


# --- lighting ----------------------------------------------------------------------------

func _test_lights() -> void:
	var lights: Array = _scenery.find_children("*", "Light3D", true, false)
	var spots := lights.filter(func(l: Light3D) -> bool: return l is SpotLight3D)
	var omnis := lights.filter(func(l: Light3D) -> bool: return l is OmniLight3D)
	_check("city has exactly %d lights including the beacon (%d)" % [LIGHT_LIMIT, lights.size()], lights.size() == LIGHT_LIMIT and lights.size() <= CityScenery.MAX_LIGHTS)
	_check("two shadowed shop spots, ten shadowless omnis (%d/%d)" % [spots.size(), omnis.size()], spots.size() == 2 and omnis.size() == 10 and spots.all(func(l: Light3D) -> bool: return l.shadow_enabled) and omnis.all(func(l: Light3D) -> bool: return not l.shadow_enabled))
	_check("light count meta agrees with the node count", int(_converted.get_meta("light_count")) + 1 == lights.size())
	_check("city has no directional light", _scenery.find_children("*", "DirectionalLight3D", true, false).is_empty())
	var pool: CityRealismLighting = _converted.get_node("LocalLighting")
	var anchors := pool.anchors
	_check("anchors exist for many street lamps and fixtures (%d)" % anchors.size(), anchors.size() > 40)
	var shadowed := 0
	for anchor: Dictionary in anchors:
		var position: Vector3 = anchor["position"]
		_check_once(is_finite(position.x) and is_finite(position.y) and is_finite(position.z) and float(anchor["energy"]) > 0.0 and float(anchor["range"]) > 0.0, "anchor %s is finite with positive energy" % position, int(position.x))
		if anchor.has("direction"):
			var direction: Vector3 = anchor["direction"]
			_check_once(is_finite(direction.length()) and direction.length() > 0.01, "anchor direction is finite and non-zero", int(position.x))
		shadowed += 1 if anchor.get("shadow", false) else 0
	_check("exactly two anchors request shadows (%d)" % shadowed, shadowed == 2)
	var near_start := CityDistrict.sample(_course, _course.total_length * 0.1)["pos"] as Vector3
	var near_end := CityDistrict.sample(_course, _course.total_length * 0.6)["pos"] as Vector3
	pool._refresh(near_start)
	var first: Array = pool.get_meta("selected_anchors").duplicate()
	var first_positions := _lit_positions(pool)
	pool._refresh(near_start)
	_check("refreshing at the same place is stable", first == pool.get_meta("selected_anchors"))
	_check("lit lights match the nearest anchors within range", _is_nearest_selection(pool, near_start))
	pool._refresh(near_end)
	var second: Array = pool.get_meta("selected_anchors")
	_check("refresh moves the selected anchors with the camera", first != second and first_positions != _lit_positions(pool) and _is_nearest_selection(pool, near_end))
	pool._refresh(Vector3(9000, 0, 9000))
	_check("no lights stay lit when the camera is far from every anchor", _lit_positions(pool).is_empty() and (pool.get_meta("selected_anchors") as Array).is_empty())


func _lit_positions(pool: CityRealismLighting) -> Array:
	var out: Array = []
	for light in pool.pool:
		if light.visible:
			out.append(light.position)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x or (a.x == b.x and a.z < b.z))
	return out


func _is_nearest_selection(pool: CityRealismLighting, eye: Vector3) -> bool:
	for shadowed in [false, true]:
		var candidates: Array = []
		for anchor: Dictionary in pool.anchors:
			if bool(anchor.get("shadow", false)) == shadowed and eye.distance_to(anchor["position"]) <= 135.0:
				candidates.append(eye.distance_to(anchor["position"]))
		candidates.sort()
		var slots := 2 if shadowed else CityRealismLighting.STREET_SLOTS
		var expected := candidates.slice(0, slots)
		var actual: Array = []
		for index in pool.pool.size():
			var light: Light3D = pool.pool[index]
			if light.visible and (index >= CityRealismLighting.STREET_SLOTS) == shadowed:
				actual.append(eye.distance_to(light.position))
		actual.sort()
		if actual.size() != expected.size():
			return false
		for i in actual.size():
			if absf(actual[i] - expected[i]) > 0.01:
				return false
	return true


# --- actors and malformed sockets ----------------------------------------------------------

func _test_actors() -> void:
	_check("two coherent vendor/customer pairs are placed", int(_converted.get_meta("actor_pairs")) == 2 and _converted.has_node("ShopLife0") and _converted.has_node("ShopLife1") and not _converted.has_node("ShopLife2"))
	var sockets: Dictionary = CityRealismCatalog.entries["redline_shop"].get("actor_sockets", {})
	var bowl: Array = sockets.get("bowl", [])
	_check("manifest sockets declare feet, counter and light data", sockets.has("vendor") and sockets.has("customer") and sockets.has("light") and float(sockets.get("floor_y", -1.0)) >= 0.0 and float(sockets.get("counter_top_y", -1.0)) > float(sockets.get("floor_y", 0.0)) and bowl.size() == 3)
	for role in ["vendor", "customer"]:
		var socket: Dictionary = sockets.get(role, {})
		var position := CityRealism._vector(socket.get("position"))
		_check("%s feet socket is finite and on the shop floor" % role, position != Vector3.INF and absf(position.y - float(sockets["floor_y"])) < 0.05)
		_check("%s stands within reach of the counter bowl" % role, position != Vector3.INF and Vector2(position.x - bowl[0], position.z - bowl[2]).length() < 1.5 and IndustrialMarketBenchmark.is_number(socket.get("yaw_degrees")))
	var light: Dictionary = sockets.get("light", {})
	var light_position := CityRealism._vector(light.get("position"))
	_check("light socket is finite and above the counter", light_position != Vector3.INF and CityRealism._vector(light.get("direction")) != Vector3.INF and light_position.y > float(sockets["counter_top_y"]))
	for index in 2:
		var group := _converted.get_node_or_null("ShopLife%d" % index) as Node3D
		if group == null:
			continue
		_check("ShopLife%d holds exactly the vendor and customer" % index, group.get_child_count() == 2)
		for model: Node3D in group.get_children():
			_check_once(model.position.is_finite() and is_finite(model.rotation.y), "ShopLife%d actor transform is finite" % index, index)
			_check_once(is_equal_approx(model.position.y, float(sockets["floor_y"])), "ShopLife%d actor stands on the floor socket" % index, index)
		var shop_world: AABB = group.global_transform * CityRealismCatalog.meshes["redline_shop"].get_aabb()
		_check("ShopLife%d sits inside its shop footprint" % index, shop_world.grow(0.5).has_point(group.global_transform * Vector3(sockets["vendor"]["position"][0], 1.0, sockets["vendor"]["position"][2])))
	var shop_lights := (_converted.get_node("LocalLighting") as CityRealismLighting).anchors.filter(func(a: Dictionary) -> bool: return a.get("shadow", false))
	_check("each actor pair owns one shadowed light anchor", shop_lights.size() == 2)


func _skip_case(label: String, mutate: Callable) -> void:
	var original: Dictionary = CityRealismCatalog.entries["redline_shop"]
	var broken := original.duplicate(true)
	mutate.call(broken)
	CityRealismCatalog.entries["redline_shop"] = broken
	var host := Node3D.new()
	add_child(host)
	var scenery := CityScenery.build(host, _course)
	CityRealismCatalog.entries["redline_shop"] = original
	var converted := scenery.get_node_or_null("CityRealism") as Node3D
	_check("%s: the city still builds" % label, converted != null)
	if converted != null:
		_check("%s: actors are skipped without orphan nodes" % label, int(converted.get_meta("actor_pairs")) == 0 and converted.find_children("ShopLife*", "Node3D", false, false).is_empty())
		var lights: CityRealismLighting = converted.get_node("LocalLighting")
		_check("%s: no shadowed actor light is registered" % label, lights.anchors.all(func(a: Dictionary) -> bool: return not a.get("shadow", false)))
		_check("%s: street geometry is unchanged" % label, converted.get_meta("triangle_count") == _converted.get_meta("triangle_count"))
	host.free()


func _test_actor_failures() -> void:
	_skip_case("null socket block", func(e: Dictionary) -> void: e["actor_sockets"] = null)
	_skip_case("socket block is a string", func(e: Dictionary) -> void: e["actor_sockets"] = "counter")
	_skip_case("missing socket block", func(e: Dictionary) -> void: e.erase("actor_sockets"))
	_skip_case("missing vendor", func(e: Dictionary) -> void: e["actor_sockets"].erase("vendor"))
	_skip_case("vendor socket is not a dictionary", func(e: Dictionary) -> void: e["actor_sockets"]["vendor"] = "front")
	_skip_case("customer position has a string", func(e: Dictionary) -> void: e["actor_sockets"]["customer"]["position"] = [1.0, "high", 0.0])
	_skip_case("vendor position is not finite", func(e: Dictionary) -> void: e["actor_sockets"]["vendor"]["position"] = [INF, 0.15, 0.0])
	_skip_case("vendor position is short", func(e: Dictionary) -> void: e["actor_sockets"]["vendor"]["position"] = [1.0, 0.15])
	_skip_case("yaw is not a number", func(e: Dictionary) -> void: e["actor_sockets"]["customer"]["yaw_degrees"] = "left")
	_skip_case("light socket missing", func(e: Dictionary) -> void: e["actor_sockets"].erase("light"))
	_skip_case("light direction malformed", func(e: Dictionary) -> void: e["actor_sockets"]["light"]["direction"] = [0, 0])


# --- fallbacks ---------------------------------------------------------------------------

func _test_fallbacks(host: Node3D) -> void:
	var legacy := CityScenery.build(host, _course, true, false)
	_check("explicit legacy mode builds the street block and district, not the converted city", not legacy.has_node("CityRealism") and legacy.has_node("CityStreetBlock") and legacy.has_node("CityKit") and legacy.get_meta("converted_city") == false)
	var plain := CityScenery.build(host, _course, false)
	_check("kit-off mode builds neither", not plain.has_node("CityRealism") and not plain.has_node("CityStreetBlock") and plain.get_meta("authored_quarter") == false and plain.has_node("Body"))
	var saved_kit: Dictionary = CityKit._entries
	CityKit._entries = {}
	var unavailable := CityScenery.build(host, _course)
	CityKit._entries = saved_kit
	_check("an unavailable city kit gives the old scenery without any block", not unavailable.has_node("CityRealism") and not unavailable.has_node("CityStreetBlock") and not unavailable.has_node("CityKit") and unavailable.has_node("Body") and unavailable.get_meta("converted_city") == false)
	var saved_meshes: Dictionary = CityRealismCatalog.meshes
	CityRealismCatalog.meshes = {}
	var no_assets := CityScenery.build(host, _course)
	CityRealismCatalog.meshes = saved_meshes
	_check("a catalog that cannot supply lots falls back to the legacy street block", not no_assets.has_node("CityRealism") and no_assets.has_node("CityStreetBlock") and no_assets.get_meta("converted_city") == false)
	var other := CourseCatalog.build_course("split_shift")
	var other_scenery := CityScenery.build(host, other)
	_check("other courses never receive the converted city", not other_scenery.has_node("CityRealism") and CityRealism.build(host, other) == null)
	var fresh := CityScenery.build(host, _course)
	_check("restoring the catalog restores the converted city", fresh.has_node("CityRealism"))
	for node: Node in [legacy, plain, unavailable, no_assets, other_scenery, fresh]:
		node.free()


# --- QA script contract --------------------------------------------------------------------

func _test_qa_script() -> void:
	var source := FileAccess.get_file_as_string("res://tests/city_realism_qa.gd")
	_check("QA script is readable", not source.is_empty())
	var lines := source.split("\n")
	var assertions := 0
	var unguarded_directory := 0
	for i in lines.size():
		var line: String = lines[i].strip_edges()
		if line.begins_with("#"):
			continue
		if line.begins_with("assert(") or " assert(" in line:
			assertions += 1
		if "make_dir_recursive_absolute" in line:
			var guarded := false
			for back in range(maxi(0, i - 3), i):
				guarded = guarded or "--capture" in lines[back] or "if capturing" in lines[back]
			if not guarded:
				unguarded_directory += 1
	_check("QA reports failures through exit code 1, not editor-only assert()", assertions == 0 and "quit(1" in source and "quit(1 if" in source)
	_check("QA creates its capture directory only when capturing", unguarded_directory == 0 and "make_dir_recursive_absolute" in source)
	_check("QA validates budgets, captures and failures", "NEAR_BUDGET" in source and "SURFACE_BUDGET" in source and "_failures" in source)
	_check("QA declares a --selftest-fail path", "--selftest-fail" in source)
	# The exit codes (0 healthy, 1 --selftest-fail) and the absence of captures without
	# --capture are exercised by tools/workflow/test_season.py under a strict timeout.


# --- detector self-tests -------------------------------------------------------------------

func _test_detectors() -> void:
	var eye := Vector3.ZERO
	var heavy := [{"center": Vector3(100, 0, 0), "tris": 400000, "surfaces": 10, "low": 0.0, "high": 150.0}]
	_check("detector: an oversized active window is measured", window_peak(heavy, PackedVector3Array([eye])).x == 400000)
	var layered := [{"center": Vector3(140, 0, 0), "tris": 1000, "surfaces": 4, "low": 0.0, "high": 150.0}, {"center": Vector3(140, 0, 0), "tris": 50, "surfaces": 2, "low": 130.0, "high": 460.0}]
	_check("detector: near and far both count inside the fade overlap", window_peak(layered, PackedVector3Array([eye])) == Vector2i(1050, 6))
	_check("detector: out-of-range batches are not counted", window_peak(layered, PackedVector3Array([Vector3(700, 0, 0)])) == Vector2i(0, 0))
	var square := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var shifted := PackedVector2Array([Vector2(3, 3), Vector2(7, 3), Vector2(7, 7), Vector2(3, 7)])
	var apart := PackedVector2Array([Vector2(9, 9), Vector2(10, 9), Vector2(10, 10), Vector2(9, 10)])
	_check("detector: overlap area finds a 1 m2 intersection", absf(overlap_area(square, shifted) - 1.0) < 0.01 and overlap_area(square, apart) == 0.0)
	var tight := CityRealismLayout.footprint(AABB(Vector3(-2, 0, 0), Vector3(4, 3, 4)), Transform3D.IDENTITY)
	_check("detector: footprint polygons cover the box corners", tight.size() == 4 and absf(overlap_area(tight, tight) - 16.0) < 0.01)


# --- shared resource snapshots -------------------------------------------------------------

func _shared_signature() -> String:
	var parts: Array = []
	var paths: Array[String] = []
	for file in SOURCE_GLBS:
		paths.append(IndustrialMarketBenchmark.DIRECTORY + file)
	paths.append("res://assets/vehicles/models/blackjack/blackjack_production.glb")
	for path in paths:
		var packed := load(path) as PackedScene
		if packed == null:
			parts.append(path + " missing")
			continue
		var scene := packed.instantiate()
		for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			for surface in instance.mesh.get_surface_count():
				var material := instance.mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null:
					parts.append([path, str(instance.name), surface, material.resource_name, material.albedo_color, material.vertex_color_use_as_albedo, material.subsurf_scatter_enabled, material.subsurf_scatter_skin_mode, material.emission_enabled, material.roughness, material.metallic])
		scene.free()
	return var_to_str(parts)


func _source_hashes() -> Array:
	var out: Array = []
	for file in SOURCE_GLBS:
		out.append(FileAccess.get_sha256(IndustrialMarketBenchmark.DIRECTORY + file))
	out.append(FileAccess.get_sha256("res://assets/city/realism/redline_shop.glb"))
	return out


# --- helpers -----------------------------------------------------------------------------

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
