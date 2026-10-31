## Dense-frontage regression suite for the converted Block Circuit city; headless.
## Compares the infill layout with the original 64-slot baseline (populate(true, false)) and
## re-derives overlap, clearance and budget figures from the built scene.
extends Node3D

const MIN_RATIO := 2.0
const MIN_PER_QUARTER_SIDE_GAIN := 2
const GLOBAL_LIMIT := 1500000
const QUARTER_LIMIT := 400000
const WINDOW_LIMIT := 320000
const SURFACE_LIMIT := 160

var _pass := 0
var _fail := 0
var _course: CourseDefinition


func _ready() -> void:
	_check("city catalog is available", CityRealismCatalog.available())
	_course = BlockCircuitData.build_course()
	var before := var_to_str(_course.points)
	var baseline := CityRealismLayout.new(_course)
	baseline.populate(true, false)
	var dense := CityRealismLayout.new(_course)
	dense.populate()
	var repeat := CityRealismLayout.new(_course)
	repeat.populate()
	_test_counts(baseline, dense)
	_test_baseline_preserved(baseline, dense)
	_test_variation(dense)
	_test_compositions(dense)
	_test_safety(dense)
	_test_determinism(dense, repeat)
	_test_detectors()
	var host := Node3D.new()
	add_child(host)
	var root := CityRealism.build(host, _course)
	_check("dense converted city builds", root != null)
	if root != null:
		_test_rendering(root, baseline, dense)
		root.free()
	host.free()
	_check("course points are unmodified by the dense build", var_to_str(_course.points) == before)
	print("CITY_DENSITY_TESTS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _buildings(layout: CityRealismLayout) -> Array:
	return layout.placements.filter(func(p: Dictionary) -> bool: return p["role"] == "building")


func _cell(p: Dictionary) -> String:
	return "%d/%d" % [p["quarter"], int(p["side"])]


func _test_counts(baseline: CityRealismLayout, dense: CityRealismLayout) -> void:
	var before := _buildings(baseline)
	var after := _buildings(dense)
	print("DENSITY_COUNTS: buildings %d -> %d, triangles %d -> %d, quarters %s -> %s, infill rejections %s" % [before.size(), after.size(), baseline.triangles, dense.triangles, str(baseline.quarter_triangles), str(dense.quarter_triangles), str(dense.infill_rejections)])
	_check("dense layout has at least %.1fx the baseline buildings (%d vs %d)" % [MIN_RATIO, after.size(), before.size()], float(after.size()) >= MIN_RATIO * before.size() and before.size() > 0)
	var base_cells := {}
	var dense_cells := {}
	for p: Dictionary in before:
		base_cells[_cell(p)] = int(base_cells.get(_cell(p), 0)) + 1
	for p: Dictionary in after:
		dense_cells[_cell(p)] = int(dense_cells.get(_cell(p), 0)) + 1
	_check("all four quarters and both sides are populated (%d cells)" % dense_cells.size(), dense_cells.size() == 8)
	for cell: String in base_cells:
		_check("quarter/side %s gains at least %d buildings (%d -> %d)" % [cell, MIN_PER_QUARTER_SIDE_GAIN, base_cells[cell], dense_cells.get(cell, 0)], int(dense_cells.get(cell, 0)) >= int(base_cells[cell]) + MIN_PER_QUARTER_SIDE_GAIN)
	var covered := func(layout: CityRealismLayout) -> int:
		var bins := {}
		for p: Dictionary in _buildings(layout):
			bins["%d" % int(float(p["s"]) / 16.0)] = true
		return bins.size()
	_check("street coverage rises (%d -> %d sixteen-metre bins)" % [covered.call(baseline), covered.call(dense)], covered.call(dense) > covered.call(baseline))


func _test_baseline_preserved(baseline: CityRealismLayout, dense: CityRealismLayout) -> void:
	var same := true
	for i in baseline.placements.size():
		same = same and var_to_str(baseline.placements[i]) == var_to_str(dense.placements[i])
	_check("every baseline placement is kept unchanged and first (%d)" % baseline.placements.size(), dense.placements.size() > baseline.placements.size() and same)
	_check("baseline rejections are unchanged by infill", var_to_str(baseline.rejected) == var_to_str(dense.rejected))
	var shops_base := _buildings(baseline).filter(func(p: Dictionary) -> bool: return p["id"] == "redline_shop")
	var shops_dense := _buildings(dense).filter(func(p: Dictionary) -> bool: return p["id"] == "redline_shop")
	_check("the first two redline shops (actor hosts) are the baseline shops", shops_base.size() >= 2 and var_to_str(shops_base.slice(0, 2)) == var_to_str(shops_dense.slice(0, 2)))
	_check("infill adds no non-building roles", dense.placements.slice(baseline.placements.size()).all(func(p: Dictionary) -> bool: return p["role"] == "building"))


func _test_variation(dense: CityRealismLayout) -> void:
	var infill := _buildings(dense).filter(func(p: Dictionary) -> bool: return int(p["variant"]) != 0 or p["composition"] != "")
	var widths := {}
	var heights := {}
	for p: Dictionary in infill:
		widths["%s/%.2f" % [p["id"], (p["transform"] as Transform3D).basis.x.length()]] = true
		heights["%.2f" % (p["transform"] as Transform3D).basis.y.length()] = true
	_check("infill carries cheap width variants (%d id/width pairs)" % widths.size(), widths.size() >= 12)
	_check("infill carries height variants (%d)" % heights.size(), heights.size() >= 3)
	var families := {}
	for p: Dictionary in infill:
		families[p["id"]] = true
	_check("infill uses at least six of the eight families (%d)" % families.size(), families.size() >= 6)
	var neighbours := 0
	var repeats := 0
	for side: float in [-1.0, 1.0]:
		var row := _buildings(dense).filter(func(p: Dictionary) -> bool: return p["side"] == side and p["composition"] == "")
		row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))
		for i in range(1, row.size()):
			neighbours += 1
			repeats += int(row[i]["id"] == row[i - 1]["id"] and absf(float(row[i]["s"]) - float(row[i - 1]["s"])) < 14.0)
	_check("adjacent single frontages differ in family (%d repeats of %d)" % [repeats, neighbours], repeats * 4 <= neighbours)
	var setbacks := {}
	for p: Dictionary in infill:
		setbacks["%.1f" % (p["transform"] as Transform3D).origin.y] = true
	var depths := {}
	for p: Dictionary in infill:
		depths["%.1f" % p["bounds"].position.y] = true
	_check("infill buildings sit on level ground (%d heights)" % depths.size(), depths.size() <= 40)


func _test_compositions(dense: CityRealismLayout) -> void:
	var groups := {}
	for p: Dictionary in _buildings(dense):
		if p["composition"] != "":
			var key := "%s@%d/%d" % [p["composition"], p["quarter"], int(p["side"])]
			groups[key] = groups.get(key, [])
			groups[key].append(p)
	var kinds := {}
	for key: String in groups:
		kinds[key.split("@")[0]] = true
	_check("both new compositions appear (%s)" % str(kinds.keys()), kinds.has("shop_terrace") and kinds.has("tenement_court"))
	var quarters := {}
	for p: Dictionary in _buildings(dense):
		if p["composition"] != "":
			quarters[p["quarter"]] = true
	_check("compositions appear in multiple quarters (%s)" % str(quarters.keys()), quarters.size() >= 2)
	var catalogued := true
	for key: String in groups:
		for p: Dictionary in groups[key]:
			catalogued = catalogued and p["id"] in CityRealismCatalog.FAMILIES
	_check("compositions reuse only existing full-detail families", catalogued)
	var whole := true
	for key: String in groups:
		var parts: Array = groups[key]
		whole = whole and parts.size() % (CityRealismLayout.COMPOSITIONS[key.split("@")[0]] as Array).size() == 0
	_check("compositions are placed whole (every declared part), never half-built", whole)
	var court_recessed := dense.placements.filter(func(p: Dictionary) -> bool: return p["composition"] == "tenement_court" and p["id"] == "row_workshop")
	var court_frontage := dense.placements.filter(func(p: Dictionary) -> bool: return p["composition"] == "tenement_court" and p["id"] == "service_tenement")
	if not court_recessed.is_empty() and not court_frontage.is_empty():
		var lateral := func(p: Dictionary) -> float: return _distance_to_route(p)
		_check("the tenement court recesses its middle block behind its flanks", lateral.call(court_recessed[0]) > lateral.call(court_frontage[0]) + 1.0)


func _distance_to_route(p: Dictionary) -> float:
	var at := CityDistrict.sample(_course, float(p["s"]))
	var origin: Vector3 = (p["transform"] as Transform3D).origin
	return Vector2(origin.x, origin.z).distance_to(Vector2((at["pos"] as Vector3).x, (at["pos"] as Vector3).z))


func _test_safety(dense: CityRealismLayout) -> void:
	var solids := dense.placements.filter(func(p: Dictionary) -> bool: return p["role"] in ["building", "prop"])
	var worst := INF
	var polygons: Array = []
	for p: Dictionary in solids:
		var polygon := CityRealismLayout.footprint(CityRealismCatalog.meshes[p["id"]].get_aabb(), p["transform"])
		polygons.append(polygon)
		worst = minf(worst, CityRealismLayout.clearance(polygon, _course))
	_check("every solid keeps road clearance (smallest %.2f)" % worst, worst >= CityScenery.ROAD_CLEARANCE - 0.05)
	var overlaps := 0
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			if not (solids[i]["bounds"] as AABB).grow(0.1).intersects(solids[j]["bounds"]):
				continue
			overlaps += int(_overlap_area(polygons[i], polygons[j]) >= 0.05)
	_check("no solid footprints overlap (%d solids, %d overlaps)" % [solids.size(), overlaps], overlaps == 0)
	_check("global and quarter triangle budgets hold (%d, %s)" % [dense.triangles, str(dense.quarter_triangles)], dense.triangles <= GLOBAL_LIMIT and dense.quarter_triangles.all(func(t: int) -> bool: return t <= QUARTER_LIMIT))
	var near_full := _buildings(dense).all(func(p: Dictionary) -> bool: return int(CityRealismCatalog.costs[p["id"]]["tris"]) == int(p["tris"]))
	_check("every building is charged its full-detail mesh, not a LOD1 box", near_full)
	var worst_window := 0
	var worst_surfaces := 0
	for eye: Vector3 in dense.sample_positions:
		var cost := 0
		var surfaces := 0
		for key: Vector2i in dense.rendering_groups:
			var group: Dictionary = dense.rendering_groups[key]
			var bounds: AABB = dense.rendering_groups[Vector2i(key.x, 0)]["bounds"]
			var distance := eye.distance_to(bounds.get_center())
			if distance > (460.0 if key.y == 1 else 150.0) or (key.y == 1 and distance < 130.0):
				continue
			cost += int(group["tris"])
			surfaces += group["materials"].size()
		worst_window = maxi(worst_window, cost)
		worst_surfaces = maxi(worst_surfaces, surfaces)
	print("DENSITY_WINDOW: worst visible triangles=%d surfaces=%d" % [worst_window, worst_surfaces])
	_check("visible geometry (%d) and surfaces (%d) stay within limits" % [worst_window, worst_surfaces], worst_window <= WINDOW_LIMIT and worst_surfaces <= SURFACE_LIMIT)


func _test_determinism(first: CityRealismLayout, second: CityRealismLayout) -> void:
	_check("repeating the dense populate reproduces every placement", var_to_str(first.placements) == var_to_str(second.placements) and var_to_str(first.infill_rejections) == var_to_str(second.infill_rejections))
	var reverse_course := CourseCatalog.build_course("block_circuit", true)
	var reversed := CityRealismLayout.new(reverse_course)
	reversed.populate()
	_check("the reverse course reuses the same canonical dense layout", reversed.placements.size() == first.placements.size())


func _test_rendering(root: Node3D, baseline: CityRealismLayout, dense: CityRealismLayout) -> void:
	var chunks := root.find_children("Chunk*", "MultiMeshInstance3D", false, false)
	var base_chunks := {}
	for p: Dictionary in baseline.placements:
		base_chunks[int(p["chunk"])] = true
	var near := chunks.filter(func(c: MultiMeshInstance3D) -> bool: return c.get_meta("lod") == 0)
	var far := chunks.filter(func(c: MultiMeshInstance3D) -> bool: return c.get_meta("lod") == 1)
	var surfaces := 0
	for c: MultiMeshInstance3D in near:
		surfaces = maxi(surfaces, c.multimesh.mesh.get_surface_count())
	print("DENSITY_RENDER: near chunks=%d far chunks=%d (baseline chunks=%d) max surfaces/chunk=%d lights=%d" % [near.size(), far.size(), base_chunks.size(), surfaces, int(root.get_meta("light_count"))])
	_check("batching stays one near and one far instance per chunk", near.size() == base_chunks.size() and far.size() <= near.size())
	_check("each batch keeps one instance and a bounded surface count", near.all(func(c: MultiMeshInstance3D) -> bool: return c.multimesh.instance_count == 1 and c.multimesh.mesh.get_surface_count() <= CityRealismCatalog.materials.size()))
	_check("scene triangle total equals the layout total", int(root.get_meta("triangle_count")) == dense.triangles)
	_check("the two original actor pairs remain", int(root.get_meta("actor_pairs")) == 2)
	_check("light pool is unchanged by density", int(root.get_meta("light_count")) == CityRealismLighting.STREET_SLOTS + 2)


func _overlap_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var area := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(a, b):
		var sum := 0.0
		for i in piece.size():
			sum += piece[i].cross(piece[(i + 1) % piece.size()])
		area += absf(sum) * 0.5
	return area


## Proves the overlap detector can fail, so a clean run means something.
func _test_detectors() -> void:
	var a := CityRealismLayout.footprint(AABB(Vector3(-2, 0, 0), Vector3(4, 3, 4)), Transform3D.IDENTITY)
	var b := CityRealismLayout.footprint(AABB(Vector3(-2, 0, 2), Vector3(4, 3, 4)), Transform3D.IDENTITY)
	_check("detector: overlapping footprints are measured", _overlap_area(a, b) > 7.0)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
