## CityKit and CityDistrict regression suite; headless, no rendering.
extends Node3D

const LANDMARKS: Array[String] = ["relay_tower", "exchange_hall", "pump_citadel"]
const VALID_REJECTIONS: Array[String] = ["road_clearance", "prop_overlap", "triangle_budget", "quarter_boundary"]
const FATAL_REJECTIONS: Array[String] = ["unknown_asset", "missing_mesh"]
const GAP_EPSILON := 0.005
const BOUNDS_TOLERANCE := 0.01
const SURFACE_DRAW_LIMIT := 64
const KIT_BATCH_LIMIT := 14
const LEGACY_BATCH_LIMIT := 12
const QUARTER_MARGIN := 40.0
const START_LINE_MARGIN := 1.0
const TRIANGLE_LIMIT := 150000

var _pass := 0
var _fail := 0


func _ready() -> void:
	var course := BlockCircuitData.build_course()
	var before := var_to_str(course.points)
	_test_assets()
	var host := Node3D.new()
	add_child(host)
	var legacy := CityScenery.build(host, course)
	var district := legacy.get_node_or_null("CityKit") as Node3D
	_check("district root exists beside legacy scenery", district != null and district.get_parent() == legacy)
	if district != null:
		_test_placements(course, district)
		_test_footprints(course, legacy, district)
		_test_budget(district)
		_test_determinism(course, district)
		_test_legacy_preserved(course, legacy)
	_check("course points are unmodified by scenery build", var_to_str(course.points) == before)
	host.free()
	print("CITY_KIT: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_assets() -> void:
	var entries := CityKit.entries()
	var ids: Array = entries.keys()
	ids.sort()
	var expected: Array = CityKit.EXPECTED_IDS.duplicate()
	expected.sort()
	_check("manifest lists exactly the 14 kit assets (%d)" % ids.size(), ids == expected and ids.size() == 14)
	var surfaces := 0
	for id: String in CityKit.EXPECTED_IDS:
		var entry: Dictionary = entries.get(id, {})
		var mesh := CityKit.mesh(id)
		_check("%s loads as a mesh" % id, mesh != null and not entry.is_empty())
		if mesh == null or entry.is_empty():
			continue
		surfaces += mesh.get_surface_count()
		_check("%s surface count matches manifest" % id, mesh.get_surface_count() == (entry["surfaces"] as Array).size())
		var materials_ok := true
		for i in mesh.get_surface_count():
			materials_ok = materials_ok and mesh.surface_get_material(i) == CityKit.material(String(entry["surfaces"][i]))
		_check("%s surfaces carry their semantic materials" % id, materials_ok)
		_check("%s mesh is reused from cache" % id, CityKit.mesh(id) == mesh)
		var measured := _surface_stats(mesh)
		_check("%s surface arrays are readable" % id, measured["tris"] > 0)
		_check("%s measured triangles (%d) match manifest (%d)" % [id, measured["tris"], entry["tris"]], measured["tris"] == int(entry["tris"]))
		var box: AABB = measured["bounds"]
		var declared := CityKit.bounds(id)
		_check("%s measured vertex bounds %s match manifest %s" % [id, box, declared], _aabb_close(box, declared, BOUNDS_TOLERANCE))
		_check("%s stands on the ground plane" % id, absf(box.position.y) < BOUNDS_TOLERANCE)
		_check("%s custom_aabb covers its vertices" % id, mesh.custom_aabb.grow(BOUNDS_TOLERANCE).encloses(box))
		_check_scene_clean(id, String(entry["glb"]))
	_check("kit surfaces total %d of %d draws" % [surfaces, SURFACE_DRAW_LIMIT], surfaces <= SURFACE_DRAW_LIMIT)
	_check("unknown asset has empty bounds", CityKit.bounds("no_such_asset") == AABB())


func _check_scene_clean(id: String, glb: String) -> void:
	var packed := load(CityKit.DIRECTORY + glb) as PackedScene
	_check("%s scene loads" % id, packed != null)
	if packed == null:
		return
	var scene := packed.instantiate()
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		meshes.append(scene)
	_check("%s has exactly one mesh instance" % id, meshes.size() == 1)
	var extras := scene.find_children("*", "CollisionObject3D", true, false)
	extras.append_array(scene.find_children("*", "CollisionShape3D", true, false))
	extras.append_array(scene.find_children("*", "Camera3D", true, false))
	extras.append_array(scene.find_children("*", "Light3D", true, false))
	extras.append_array(scene.find_children("*", "AnimationPlayer", true, false))
	_check("%s source scene has no collision, camera, light or animation" % id, extras.is_empty()
		and not (scene is CollisionObject3D or scene is Camera3D or scene is Light3D))
	scene.free()


func _surface_stats(mesh: ArrayMesh) -> Dictionary:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var triangles := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		triangles += (indices as PackedInt32Array).size() / 3 if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty() else vertices.size() / 3
		for vertex in vertices:
			low = Vector3(minf(low.x, vertex.x), minf(low.y, vertex.y), minf(low.z, vertex.z))
			high = Vector3(maxf(high.x, vertex.x), maxf(high.y, vertex.y), maxf(high.z, vertex.z))
	return {"tris": triangles, "bounds": AABB(low, high - low) if triangles > 0 else AABB()}


func _aabb_close(a: AABB, b: AABB, tolerance: float) -> bool:
	return a.position.distance_to(b.position) <= tolerance and a.end.distance_to(b.end) <= tolerance


func _test_placements(course: CourseDefinition, district: Node3D) -> void:
	var placements: Array = district.get_meta("placements", [])
	var rejected: Array = district.get_meta("rejected_slots", [])
	var quarter := course.total_length * CityDistrict.FRACTION
	_check("quarter length meta matches 25 percent", is_equal_approx(float(district.get_meta("quarter_length", 0.0)), quarter))
	_check("district places a substantive set (%d)" % placements.size(), placements.size() >= 60)
	var counts := {}
	for placement: Dictionary in placements:
		counts[placement["asset"]] = int(counts.get(placement["asset"], 0)) + 1
	for id in CityKit.EXPECTED_IDS:
		_check("%s is placed at least once" % id, int(counts.get(id, 0)) >= 1)
	for id in LANDMARKS:
		_check("landmark %s is placed exactly once (%d)" % [id, int(counts.get(id, 0))], int(counts.get(id, 0)) == 1)
	for id in CityDistrict.PROPS:
		_check("prop %s is placed repeatedly (%d)" % [id, int(counts.get(id, 0))], int(counts.get(id, 0)) >= 2)
	var unexpected := {}
	for slot: Dictionary in rejected:
		var reason := String(slot["reason"])
		_check("rejection %s for %s is not a load failure" % [reason, slot["asset"]], not reason in FATAL_REJECTIONS)
		if not reason in VALID_REJECTIONS:
			unexpected[reason] = int(unexpected.get(reason, 0)) + 1
		_check_once(CityKit.EXPECTED_IDS.has(String(slot["asset"])), "rejected slot names a kit asset", rejected.find(slot))
	_check("only documented rejection reasons occur %s" % unexpected, unexpected.is_empty())
	var batch_total := 0
	var batches := district.find_children("*", "MultiMeshInstance3D", false, false)
	for batch: MultiMeshInstance3D in batches:
		var id := String(batch.get_meta("asset_id", ""))
		var recorded: Array = batch.get_meta("city_transforms", [])
		batch_total += recorded.size()
		_check("%s batch keeps one transform per instance" % id, recorded.size() == batch.multimesh.instance_count and recorded.size() == int(counts.get(id, 0)))
		_check("%s batch uses the cached kit mesh and local bounds" % id, batch.multimesh.mesh == CityKit.mesh(id) and batch.get_meta("city_local_aabb") == CityKit.bounds(id))
		var matched := 0
		for placement: Dictionary in placements:
			matched += int(placement["asset"] == id and recorded.has(placement["transform"]))
		_check("%s recorded transforms equal placements" % id, matched == recorded.size())
		var routes: Array = batch.get_meta("city_route_s", [])
		_check("%s keeps a route distance per instance" % id, routes.size() == recorded.size())
	_check("one batch per placed asset (%d)" % batches.size(), batches.size() == counts.size() and batches.size() <= KIT_BATCH_LIMIT)
	_check("batches hold every placement", batch_total == placements.size())
	var upright := true
	var projected := true
	var clear := true
	var worst := INF
	var disagreements := 0
	for placement: Dictionary in placements:
		var xf: Transform3D = placement["transform"]
		upright = upright and xf.basis.y.is_equal_approx(Vector3.UP) and xf.basis.is_conformal()
		var local := CityKit.bounds(placement["asset"])
		var world := _world_box(xf, local)
		_check_once(_aabb_close(world, placement["bounds"], 0.01), "%s recorded bounds equal the transformed local bounds" % placement["asset"], int(placement["s"]))
		for corner in 8:
			var s := _projected_distance(course, _corner(world, corner))
			projected = projected and s >= 0.0 and s / course.total_length < CityDistrict.FRACTION
		var gap := CityScenery.road_clearance(world, course)
		worst = minf(worst, gap)
		clear = clear and gap >= CityScenery.ROAD_CLEARANCE
		if not _gap_agrees(world, gap, course):
			disagreements += 1
	_check("every placement is upright and rigid", upright)
	_check("every AABB corner projects into forward 0..25 percent", projected)
	_check("every placement clears the road by %.1f m (worst %.2f)" % [CityScenery.ROAD_CLEARANCE, worst], clear)
	_check("independent world-corner sampling agrees with clearance (%d disagreements)" % disagreements, disagreements == 0)
	_check("clearance is measured rather than slack (worst %.1f m)" % worst, worst < 40.0)
	_check("no scenery is placed beyond the world limit", placements.all(func(p: Dictionary) -> bool: return not _outside(_world_box(p["transform"], CityKit.bounds(p["asset"])))))
	_check("kit has no collision, camera or light nodes", district.find_children("*", "CollisionObject3D", true, false).is_empty()
		and district.find_children("*", "CollisionShape3D", true, false).is_empty()
		and district.find_children("*", "Camera3D", true, false).is_empty()
		and district.find_children("*", "Light3D", true, false).is_empty())


func _test_footprints(course: CourseDefinition, legacy: Node3D, district: Node3D) -> void:
	var placements: Array = district.get_meta("placements", [])
	var rects: Array[Rect2] = []
	for placement: Dictionary in placements:
		rects.append(_flat(_world_box(placement["transform"], CityKit.bounds(placement["asset"]))))
	var worst := INF
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var gap := _rect_gap(rects[i], rects[j])
			worst = minf(worst, gap)
			overlaps += int(gap < CityDistrict.GAP - GAP_EPSILON)
	_check("placements keep a %.1f m flat gap (%d pairs closer, worst %.2f)" % [CityDistrict.GAP, overlaps, worst], overlaps == 0)
	var obstacles: Array[Rect2] = []
	var crown := legacy.get_node_or_null("Crown") as Node3D
	var crown_rect := Rect2()
	if crown != null:
		crown_rect = Rect2(crown.position.x - 48.0, crown.position.z - 48.0, 96.0, 96.0)
		obstacles.append(crown_rect)
	for batch: MultiMeshInstance3D in legacy.find_children("*", "MultiMeshInstance3D", true, false):
		if district.is_ancestor_of(batch):
			continue
		var local: AABB = batch.get_meta("city_local_aabb", CityScenery.UNIT_BOX)
		for xf: Transform3D in batch.get_meta("city_transforms", []):
			obstacles.append(_flat(_world_box(batch.global_transform * xf, local)))
	for mesh: MeshInstance3D in legacy.find_children("*", "MeshInstance3D", true, false):
		obstacles.append(_flat(_world_box(mesh.global_transform, _primitive_bounds(mesh.mesh))))
	_check("legacy obstacles were collected (%d)" % obstacles.size(), obstacles.size() > 50)
	var hits := 0
	var tightest := INF
	for rect in rects:
		for obstacle in obstacles:
			var gap := _rect_gap(rect, obstacle)
			tightest = minf(tightest, gap)
			hits += int(gap < CityDistrict.GAP - GAP_EPSILON)
	_check("kit stays clear of legacy obstacles (%d conflicts, tightest %.2f)" % [hits, tightest], hits == 0)
	_check("legacy Crown exists as a 96 m obstacle", crown != null)
	if crown != null:
		var crown_hits := 0
		for rect in rects:
			crown_hits += int(rect.intersects(crown_rect))
		_check("no kit footprint enters the 96 m Crown square (%d)" % crown_hits, crown_hits == 0)


func _test_budget(district: Node3D) -> void:
	var placements: Array = district.get_meta("placements", [])
	var entries := CityKit.entries()
	var manifest := 0
	var measured := 0
	var draws := 0
	for placement: Dictionary in placements:
		manifest += int(entries[placement["asset"]]["tris"])
	for batch: MultiMeshInstance3D in district.find_children("*", "MultiMeshInstance3D", false, false):
		var mesh := batch.multimesh.mesh as ArrayMesh
		measured += _surface_stats(mesh)["tris"] * batch.multimesh.instance_count
		draws += mesh.get_surface_count()
	_check("placed triangles (%d) stay within %d" % [manifest, TRIANGLE_LIMIT], manifest <= TRIANGLE_LIMIT and TRIANGLE_LIMIT == CityDistrict.TRIANGLE_BUDGET)
	_check("district triangle meta equals placed manifest total", int(district.get_meta("triangle_count", -1)) == manifest and int(district.get_meta("triangle_budget", 0)) == TRIANGLE_LIMIT)
	_check("measured instance triangles (%d) equal manifest total (%d)" % [measured, manifest], measured == manifest)
	_check("kit surface draws stay within %d (%d)" % [SURFACE_DRAW_LIMIT, draws], draws <= SURFACE_DRAW_LIMIT)
	_check("kit shadows stay off", district.find_children("*", "MultiMeshInstance3D", false, false).all(func(b: MultiMeshInstance3D) -> bool: return b.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))


func _test_determinism(course: CourseDefinition, district: Node3D) -> void:
	var first := _placement_signature(district)
	var repeat_host := Node3D.new()
	add_child(repeat_host)
	var repeat := CityScenery.build(repeat_host, course).get_node("CityKit") as Node3D
	_check("repeated build produces identical placements", first == _placement_signature(repeat))
	_check("repeated build produces identical rejections", var_to_str(district.get_meta("rejected_slots")) == var_to_str(repeat.get_meta("rejected_slots")))
	repeat_host.free()
	var reversed := CourseCatalog.build_course("block_circuit", true)
	_check("reverse course reuses canonical geometry", reversed != null and reversed.is_reverse and reversed.geometry() != reversed and reversed.geometry().total_length == course.total_length)
	var reverse_host := Node3D.new()
	add_child(reverse_host)
	var reverse_district := CityScenery.build(reverse_host, reversed).get_node("CityKit") as Node3D
	_check("reverse-direction canonical world is identical", first == _placement_signature(reverse_district))
	reverse_host.free()


func _placement_signature(district: Node3D) -> Array:
	var out: Array = []
	for placement: Dictionary in district.get_meta("placements", []):
		out.append(var_to_str([placement["asset"], placement["s"], placement["side"], placement["transform"], placement["bounds"]]))
	for child in district.get_children():
		if child is MultiMeshInstance3D:
			out.append(var_to_str([child.name, child.multimesh.instance_count, child.get_meta("city_transforms")]))
	return out


func _test_legacy_preserved(course: CourseDefinition, legacy: Node3D) -> void:
	var old_host := Node3D.new()
	add_child(old_host)
	var old_root := CityScenery.build(old_host, course, false)
	_check("flag controls authored quarter metadata", old_root.get_meta("authored_quarter") == false and legacy.get_meta("authored_quarter") == true and old_root.get_node_or_null("CityKit") == null)
	var quarter := course.total_length * CityDistrict.FRACTION
	var old_batches := _batches(old_root, null)
	var new_batches := _batches(legacy, legacy.get_node("CityKit"))
	_check("legacy batch count stays within %d (old %d, new %d)" % [LEGACY_BATCH_LIMIT, old_batches.size(), new_batches.size()], old_batches.size() <= LEGACY_BATCH_LIMIT and new_batches.size() <= LEGACY_BATCH_LIMIT)
	_check("legacy batch names are unchanged", old_batches.keys() == new_batches.keys())
	var untouched: Array[String] = ["Wall", "Post", "Skyline", "Windows", "CrownRib"]
	for batch_name: String in old_batches:
		var old_set := _counts(old_batches[batch_name])
		var new_set := _counts(new_batches.get(batch_name, []))
		var subset := true
		for key: String in new_set:
			subset = subset and int(old_set.get(key, 0)) >= int(new_set[key])
		_check("%s keeps only transforms the old build produced (RNG preserved)" % batch_name, subset)
		if batch_name in untouched:
			_check("%s is identical outside the replaced quarter" % batch_name, old_set == new_set)
			continue
		var removed := 0
		var removed_ok := true
		var kept_ok := true
		for xf: Transform3D in old_batches[batch_name]:
			var route := _projected_distance(course, xf.origin)
			if (new_batches.get(batch_name, []) as Array).has(xf):
				kept_ok = kept_ok and (route >= quarter - QUARTER_MARGIN or route < START_LINE_MARGIN)
			else:
				removed += 1
				removed_ok = removed_ok and route < quarter + QUARTER_MARGIN
		_check("%s removals (%d) all fall at the replaced quarter" % [batch_name, removed], removed_ok)
		if batch_name in ["Body", "Rib", "Sinew"]:
			_check("%s survivors all lie outside the replaced quarter" % batch_name, kept_ok)
		if batch_name == "Body":
			_check("old Body towers occupied the replaced quarter (%d removed)" % removed, removed > 0)
	var old_lights := _light_signature(old_root)
	_check("legacy lights are unchanged (%d)" % old_lights.size(), old_lights == _light_signature(legacy))
	var old_crown := old_root.get_node_or_null("Crown") as Node3D
	var new_crown := legacy.get_node_or_null("Crown") as Node3D
	_check("legacy Crown is unchanged", old_crown != null and new_crown != null and old_crown.position == new_crown.position and old_crown.get_child_count() == new_crown.get_child_count())
	old_host.free()


func _batches(root: Node, exclude: Node) -> Dictionary:
	var out := {}
	for batch: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		if exclude != null and exclude.is_ancestor_of(batch):
			continue
		out[String(batch.name)] = batch.get_meta("city_transforms", [])
	return out


func _counts(transforms: Array) -> Dictionary:
	var out := {}
	for xf: Transform3D in transforms:
		var key := var_to_str(xf)
		out[key] = int(out.get(key, 0)) + 1
	return out


func _light_signature(root: Node) -> Array:
	var out: Array = []
	for light: OmniLight3D in root.find_children("*", "OmniLight3D", true, false):
		out.append(var_to_str([light.position, light.light_color, light.omni_range]))
	return out


func _projected_distance(course: CourseDefinition, position: Vector3) -> float:
	var flat := Vector2(position.x, position.z)
	var best := INF
	var result := 0.0
	var along := 0.0
	var count := course.points.size()
	for i in count:
		var a3: Vector3 = course.points[i]["pos"]
		var b3: Vector3 = course.points[(i + 1) % count]["pos"]
		var a := Vector2(a3.x, a3.z)
		var delta := Vector2(b3.x, b3.z) - a
		var t := clampf((flat - a).dot(delta) / maxf(delta.length_squared(), 0.0001), 0.0, 1.0)
		var distance := flat.distance_squared_to(a + delta * t)
		if distance < best:
			best = distance
			result = along + float(course.points[i]["dist"]) * t
		along += float(course.points[i]["dist"])
	return result


func _corner(box: AABB, corner: int) -> Vector3:
	return box.position + Vector3(box.size.x * float(corner & 1), box.size.y * float((corner >> 1) & 1), box.size.z * float((corner >> 2) & 1))


func _world_box(xf: Transform3D, local: AABB) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for corner in 8:
		var w := xf.basis * _corner(local, corner) + xf.origin
		low = Vector3(minf(low.x, w.x), minf(low.y, w.y), minf(low.z, w.z))
		high = Vector3(maxf(high.x, w.x), maxf(high.y, w.y), maxf(high.z, w.z))
	return AABB(low, high - low)


func _primitive_bounds(mesh: Mesh) -> AABB:
	var cube := mesh as BoxMesh
	if cube:
		return AABB(-cube.size * 0.5, cube.size)
	var tube := mesh as CylinderMesh
	if tube:
		var r := maxf(tube.top_radius, tube.bottom_radius)
		return AABB(Vector3(-r, -tube.height * 0.5, -r), Vector3(r * 2.0, tube.height, r * 2.0))
	var ball := mesh as SphereMesh
	if ball:
		return AABB(Vector3(-ball.radius, -ball.height * 0.5, -ball.radius), Vector3(ball.radius * 2.0, ball.height, ball.radius * 2.0))
	return mesh.get_aabb()


func _flat(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return Vector2(dx, dy).length()


func _outside(world: AABB) -> bool:
	return absf(world.position.x) > CityScenery.WORLD_LIMIT or absf(world.end.x) > CityScenery.WORLD_LIMIT or absf(world.position.z) > CityScenery.WORLD_LIMIT or absf(world.end.z) > CityScenery.WORLD_LIMIT


func _gap_agrees(world: AABB, gap: float, course: CourseDefinition) -> bool:
	var low := Vector2(world.position.x, world.position.z)
	var high := Vector2(world.end.x, world.end.z)
	var sampled := INF
	for point: Dictionary in course.points:
		var p: Vector3 = point["pos"]
		var out := Vector2(maxf(maxf(low.x - p.x, 0.0), p.x - high.x), maxf(maxf(low.y - p.z, 0.0), p.z - high.y))
		sampled = minf(sampled, out.length() - float(point["w"]) * 0.5 - TrackBuilder.RAIL_OFFSET)
	return gap <= sampled + 0.001 and gap >= sampled - 2.3


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
