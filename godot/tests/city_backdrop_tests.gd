## Converted-city backdrop regression suite; runs headless, and on a real renderer also reads back
## every MultiMesh instance transform.
## Everything is measured from the built scene: stored batch transforms are turned into world
## corners here, then compared with the realism reservations, the road and the visible towers.
extends Node3D

const MIN_BUILDINGS := 120
const MIN_PER_QUARTER := 20
const MIN_PER_QUARTER_SIDE := 8
const SAMPLE_EVERY := 7
const LIMIT := 1100.0

var _pass := 0
var _fail := 0
var _course: CourseDefinition


func _ready() -> void:
	_course = BlockCircuitData.build_course()
	var before := var_to_str(_course.points)
	_test_detectors()
	var host := Node3D.new()
	add_child(host)
	var scenery := CityScenery.build(host, _course)
	var backdrop := scenery.get_node_or_null("CityBackdrop") as Node3D
	_check("converted city carries a backdrop container", backdrop != null and scenery.get_meta("converted_city") == true)
	if backdrop != null:
		var instances := _instances(backdrop)
		_test_counts(scenery, backdrop, instances)
		_test_clearance(instances)
		_test_reservations(scenery, backdrop, instances)
		_test_coverage(backdrop, instances)
		_test_no_extras(scenery, backdrop)
		_test_shader(backdrop)
		await _test_renderer_transforms(backdrop)
		_test_preserved(host, scenery)
		_test_determinism(host, scenery)
	_test_fallbacks(host)
	_check("course points are unmodified by the backdrop build", var_to_str(_course.points) == before)
	host.free()
	print("CITY_BACKDROP: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


## [{"name", "xf", "world": AABB}] for every stored backdrop instance.
func _instances(backdrop: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for batch: MultiMeshInstance3D in backdrop.find_children("*", "MultiMeshInstance3D", false, false):
		for xf: Transform3D in batch.get_meta("city_transforms", []):
			out.append({"name": String(batch.name), "xf": xf, "world": _world_box(xf, AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))})
	return out


func _test_counts(scenery: Node3D, backdrop: Node3D, instances: Array[Dictionary]) -> void:
	var body := backdrop.get_node_or_null("BackdropBody") as MultiMeshInstance3D
	var rib := backdrop.get_node_or_null("BackdropRib") as MultiMeshInstance3D
	_check("backdrop uses exactly one body batch and one trim batch", body != null and rib != null and backdrop.get_child_count() == 2)
	var stored := instances.size()
	var counted: int = body.multimesh.instance_count + rib.multimesh.instance_count
	_check("every stored transform is a real instance (%d)" % stored, stored == counted and stored == int(backdrop.get_meta("instance_count")))
	_check("body batch carries per-instance data, trim does not", body.multimesh.use_custom_data and not rib.multimesh.use_custom_data)
	var buildings := int(backdrop.get_meta("building_count"))
	var triangles := int(backdrop.get_meta("triangle_count"))
	_check("building count is meaningful (%d)" % buildings, buildings >= MIN_BUILDINGS and (backdrop.get_meta("records") as Array).size() == buildings)
	_check("building cap holds with room to spare (%d of %d)" % [buildings, CityScenery.BACKDROP_MAX_BUILDINGS], buildings < CityScenery.BACKDROP_MAX_BUILDINGS)
	_check("instance cap holds with room to spare (%d of %d)" % [stored, CityScenery.BACKDROP_MAX_INSTANCES], stored < CityScenery.BACKDROP_MAX_INSTANCES)
	var box := body.multimesh.mesh as BoxMesh
	var per_box := _triangles(box)
	_check("triangles equal instances times the real box mesh (%d x %d)" % [stored, per_box], per_box == CityScenery.BACKDROP_TRIANGLES_PER_BOX and triangles == stored * per_box)
	_check("triangle cap holds (%d of %d)" % [triangles, CityScenery.BACKDROP_TRIANGLE_CAP], triangles < CityScenery.BACKDROP_TRIANGLE_CAP and triangles == int(backdrop.get_meta("triangle_count")))
	var rest := 0
	for batch: MultiMeshInstance3D in scenery.find_children("*", "MultiMeshInstance3D", true, false):
		if not backdrop.is_ancestor_of(batch) and not batch.name.begins_with("Chunk"):
			rest += batch.multimesh.instance_count
	print("BACKDROP_COUNTS: buildings=%d instances=%d triangles=%d (legacy batches without backdrop: %d instances)" % [buildings, stored, triangles, rest])


func _triangles(mesh: Mesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


func _test_clearance(instances: Array[Dictionary]) -> void:
	var worst := INF
	var outside := 0
	var disagreements := 0
	var sampled := 0
	for index in instances.size():
		var world: AABB = instances[index]["world"]
		var gap := CityScenery.road_clearance(world, _course)
		worst = minf(worst, gap)
		if gap < CityScenery.ROAD_CLEARANCE:
			outside += 1
		if absf(world.position.x) > LIMIT or absf(world.end.x) > LIMIT or absf(world.position.z) > LIMIT or absf(world.end.z) > LIMIT:
			outside += 1
		if index % SAMPLE_EVERY == 0:
			sampled += 1
			if not _oriented_clear(instances[index]["xf"]):
				disagreements += 1
	_check("every backdrop box clears the road by %.1f m (worst %.2f, %d violations)" % [CityScenery.ROAD_CLEARANCE, worst, outside], outside == 0)
	_check("independent oriented-footprint sampling agrees (%d sampled, %d too close)" % [sampled, disagreements], disagreements == 0)


## Sample the real rotated footprint and measure each point against the centreline segments.
func _oriented_clear(xf: Transform3D) -> bool:
	var count := _course.points.size()
	for gx in 5:
		for gz in 5:
			var local := Vector3(float(gx) / 4.0 - 0.5, 0.0, float(gz) / 4.0 - 0.5)
			var world := xf.basis * local + xf.origin
			var p := Vector2(world.x, world.z)
			for k in count:
				var a: Dictionary = _course.points[k]
				var b: Dictionary = _course.points[(k + 1) % count]
				var closest := Geometry2D.get_closest_point_to_segment(p, Vector2(a["pos"].x, a["pos"].z), Vector2(b["pos"].x, b["pos"].z))
				var edge := maxf(float(a["w"]), float(b["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET
				if p.distance_to(closest) - edge < CityScenery.ROAD_CLEARANCE - 0.01:
					return false
	return true


## A building's main block is the body instance standing on the ground; setbacks and plant sit higher.
func _is_main(entry: Dictionary) -> bool:
	var xf: Transform3D = entry["xf"]
	return entry["name"] == "BackdropBody" and xf.basis.x.length() >= 14.0 and absf(xf.origin.y - xf.basis.y.length() * 0.5) < 0.01


func _flat(box: AABB) -> AABB:
	return AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 1.0, box.size.z))


func _test_reservations(scenery: Node3D, backdrop: Node3D, instances: Array[Dictionary]) -> void:
	var realism := scenery.get_node("CityRealism") as Node3D
	var reserved: Array = realism.get_meta("reserved_bounds")
	var district := scenery.get_node("CityKit") as Node3D
	var landmarks: Array[AABB] = []
	for placement: Dictionary in district.get_meta("placements", []):
		landmarks.append(_flat(placement["bounds"]))
	var hits := 0
	var landmark_hits := 0
	var crown_hits := 0
	var crown := scenery.get_node_or_null("Crown") as Node3D
	var crown_box := AABB(crown.position - Vector3(48, 0, 48), Vector3(96, 1, 96)) if crown != null else AABB()
	for entry: Dictionary in instances:
		var flat := _flat(entry["world"])
		for box: AABB in reserved:
			if flat.intersects(box):
				hits += 1
				break
		for box: AABB in landmarks:
			if flat.intersects(box):
				landmark_hits += 1
				break
		if crown != null and flat.intersects(crown_box):
			crown_hits += 1
	_check("reservation set is real (%d lots, %d landmarks)" % [reserved.size(), landmarks.size()], reserved.size() > 50 and landmarks.size() >= 3)
	_check("no backdrop part overlaps a reserved solid lot (%d hits)" % hits, hits == 0)
	_check("no backdrop part overlaps a district landmark (%d hits)" % landmark_hits, landmark_hits == 0)
	_check("no backdrop part overlaps the crown (%d hits)" % crown_hits, crown_hits == 0)
	# Visible legacy towers and decks (converted mode keeps these) must not be shared with the backdrop.
	var shared := 0
	for name_ in ["Body", "Wall"]:
		var batch := scenery.get_node_or_null(name_) as MultiMeshInstance3D
		if batch == null:
			continue
		for xf: Transform3D in batch.get_meta("city_transforms"):
			var tower := _flat(_world_box(xf, AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)))
			for entry: Dictionary in instances:
				if tower.intersects(_flat(entry["world"])):
					shared += 1
					break
	_check("backdrop does not overlap the visible original towers (%d)" % shared, shared == 0)
	# The reserved-overlap bypass for far towers is gone: no visible legacy body sits on a lot.
	var body := scenery.get_node_or_null("Body") as MultiMeshInstance3D
	var on_lot := 0
	if body != null:
		for xf: Transform3D in body.get_meta("city_transforms"):
			var tower := _flat(_world_box(xf, AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)))
			for box: AABB in reserved:
				if tower.intersects(box):
					on_lot += 1
					break
	_check("no visible legacy tower body overlaps a reserved lot (%d)" % on_lot, on_lot == 0)
	var own := 0
	for i in instances.size():
		if not _is_main(instances[i]):
			continue
		for j in range(i + 1, instances.size()):
			if _is_main(instances[j]) and _flat(instances[i]["world"]).intersects(_flat(instances[j]["world"])):
				own += 1
	_check("backdrop main blocks do not overlap each other (%d)" % own, own == 0)


func _test_coverage(backdrop: Node3D, instances: Array[Dictionary]) -> void:
	var quarter := PackedInt32Array([0, 0, 0, 0])
	var sides := {}
	var rear_first := 0
	for entry: Dictionary in instances:
		var xf: Transform3D = entry["xf"]
		if not _is_main(entry):
			continue
		var s := CityDistrict.route_distance(_course, xf.origin)
		var q := mini(3, int(s / _course.total_length * 4.0))
		quarter[q] += 1
		var at := CityDistrict.sample(_course, s)
		var lateral := (xf.origin - (at["pos"] as Vector3)).dot(Vector3(-(at["dir"] as Vector3).z, 0.0, (at["dir"] as Vector3).x))
		var key := "%d/%d" % [q, 1 if lateral > 0.0 else -1]
		sides[key] = int(sides.get(key, 0)) + 1
		if q == 0 and CityScenery.road_clearance(entry["world"], _course) > 30.0:
			rear_first += 1
	for q in 4:
		_check("quarter %d has backdrop coverage (%d main blocks)" % [q, quarter[q]], quarter[q] >= MIN_PER_QUARTER)
		for side in [-1, 1]:
			_check("quarter %d side %d has backdrop coverage (%d)" % [q, side, int(sides.get("%d/%d" % [q, side], 0))], int(sides.get("%d/%d" % [q, side], 0)) >= MIN_PER_QUARTER_SIDE)
	_check("first quarter has a rear row beyond 30 m (%d)" % rear_first, rear_first >= 4)
	var records: Array = backdrop.get_meta("records")
	var rows := {}
	for record: Dictionary in records:
		rows[int(record["row"])] = true
	_check("backdrop builds layered rows (%d)" % rows.size(), rows.size() >= 3)
	var heights := PackedFloat32Array()
	for entry: Dictionary in instances:
		if _is_main(entry):
			heights.append((entry["xf"] as Transform3D).basis.y.length())
	heights.sort()
	_check("heights vary across the midground (%.0f to %.0f m)" % [heights[0], heights[heights.size() - 1]], heights[heights.size() - 1] - heights[0] > 30.0)


func _test_no_extras(scenery: Node3D, backdrop: Node3D) -> void:
	_check("backdrop adds no lights", backdrop.find_children("*", "Light3D", true, false).is_empty())
	_check("backdrop adds no collision objects", backdrop.find_children("*", "CollisionObject3D", true, false).is_empty())
	_check("scenery has no collision objects", scenery.find_children("*", "CollisionObject3D", true, false).is_empty())
	var lights := scenery.find_children("*", "Light3D", true, false)
	var realism_lights := int(scenery.get_node("CityRealism").get_meta("light_count"))
	_check("city keeps its existing light budget: realism %d + crown beacon (%d)" % [realism_lights, lights.size()], lights.size() == realism_lights + 1 and lights.size() <= CityScenery.MAX_LIGHTS)
	_check("backdrop casts no shadows", backdrop.find_children("*", "GeometryInstance3D", true, false).all(func(n: GeometryInstance3D) -> bool: return n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))


func _test_shader(backdrop: Node3D) -> void:
	var body := backdrop.get_node("BackdropBody") as MultiMeshInstance3D
	var material := body.material_override as ShaderMaterial
	_check("backdrop body uses the dedicated shader", material != null and material.shader == CityScenery.BACKDROP_SHADER)
	var code := CityScenery.BACKDROP_SHADER.code
	_check("shader is deterministic and texture-free (no TIME, no samplers)", code.find("TIME") == -1 and code.find("sampler2D") == -1 and code.find("texture(") == -1)
	_check("shader is unshaded so it adds no light dependence", code.find("render_mode unshaded") != -1)
	_check("shader stays within the sparse-window rule", code.find("step(0.93, lit_roll)") != -1)
	_check("shader exposure keeps the facade dark behind the detailed fronts", code.find("const float EXPOSURE = 0.22;") != -1)
	var rib := (backdrop.get_node("BackdropRib") as MultiMeshInstance3D).material_override as StandardMaterial3D
	_check("trim is dark (albedo %.3f)" % rib.albedo_color.v, rib != null and rib.albedo_color.v <= 0.05)


## Every transform the renderer holds must equal the stored one; a deliberately displaced real
## instance must be rejected, then restored. The Dummy server ignores transform setters, so the
## readback and mutation only run with a real display server.
func _test_renderer_transforms(backdrop: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		print("RENDER_CHECK: MultiMesh readback and mutation detector require the Vulkan backdrop run; Dummy transform setters are no-ops")
		return
	var total := 0
	var drift := 0
	for batch: MultiMeshInstance3D in backdrop.find_children("*", "MultiMeshInstance3D", false, false):
		drift += _transform_mismatches(batch)
		total += batch.multimesh.instance_count
	_check("every real MultiMesh instance matches its stored transform (%d instances, %d mismatches)" % [total, drift], total > 0 and drift == 0)
	var body := backdrop.get_node("BackdropBody") as MultiMeshInstance3D
	var original := body.multimesh.get_instance_transform(0)
	body.multimesh.set_instance_transform(0, Transform3D(original.basis, original.origin + Vector3(0.5, 0.0, 0.0)))
	await _settle()
	_check("detector: a displaced real MultiMesh instance is reported", _transform_mismatches(body) == 1)
	body.multimesh.set_instance_transform(0, original)
	await _settle()
	_check("detector: the restored instance matches again", _transform_mismatches(body) == 0)


func _settle() -> void:
	for frame in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _transform_mismatches(batch: MultiMeshInstance3D) -> int:
	var stored: Array = batch.get_meta("city_transforms", [])
	var bad := 0 if stored.size() == batch.multimesh.instance_count else 1
	for index in mini(stored.size(), batch.multimesh.instance_count):
		if not batch.multimesh.get_instance_transform(index).is_equal_approx(stored[index]):
			bad += 1
	return bad


func _test_preserved(host: Node3D, scenery: Node3D) -> void:
	var legacy := CityScenery.build(host, _course, true, false)
	for name_ in ["Skyline", "CrownRib"]:
		var old_batch := legacy.get_node_or_null(name_) as MultiMeshInstance3D
		var batch := scenery.get_node_or_null(name_) as MultiMeshInstance3D
		_check("far %s batch is untouched by the backdrop" % name_, old_batch != null and batch != null and var_to_str(old_batch.get_meta("city_transforms")) == var_to_str(batch.get_meta("city_transforms")))
	var old_crown := legacy.get_node_or_null("Crown") as Node3D
	var crown := scenery.get_node_or_null("Crown") as Node3D
	_check("crown keeps its position and parts", old_crown != null and crown != null and crown.position.is_equal_approx(old_crown.position) and crown.get_child_count() == old_crown.get_child_count())
	_check("legacy fallback has no backdrop", not legacy.has_node("CityBackdrop"))
	var realism := scenery.get_node("CityRealism") as Node3D
	var alone_host := Node3D.new()
	add_child(alone_host)
	var alone := CityRealism.build(alone_host, _course.geometry())
	_check("detailed buildings and ground are unchanged (%d tris)" % int(realism.get_meta("triangle_count")),
			alone != null and int(alone.get_meta("triangle_count")) == int(realism.get_meta("triangle_count")) and (alone.get_meta("placements") as Array).size() == (realism.get_meta("placements") as Array).size())
	alone_host.free()
	legacy.get_parent().remove_child(legacy)
	legacy.free()


func _signature(scenery: Node3D) -> String:
	var backdrop := scenery.get_node("CityBackdrop") as Node3D
	var parts: Array = []
	for batch: MultiMeshInstance3D in backdrop.find_children("*", "MultiMeshInstance3D", false, false):
		parts.append([batch.name, batch.get_meta("city_transforms")])
	parts.append([backdrop.get_meta("building_count"), backdrop.get_meta("instance_count"), backdrop.get_meta("quarter_side_counts")])
	return var_to_str(parts)


func _test_determinism(host: Node3D, scenery: Node3D) -> void:
	var repeat := CityScenery.build(host, _course)
	_check("rebuilding places identical backdrop batches", _signature(scenery) == _signature(repeat))
	var reverse := CityScenery.build(host, CourseCatalog.build_course("block_circuit", true))
	_check("reverse direction also builds a backdrop", reverse.has_node("CityBackdrop") and int(reverse.get_node("CityBackdrop").get_meta("building_count")) >= MIN_BUILDINGS)
	for built: Node in [repeat, reverse]:
		built.get_parent().remove_child(built)
		built.free()


func _test_fallbacks(host: Node3D) -> void:
	var legacy := CityScenery.build(host, _course, true, false)
	var plain := CityScenery.build(host, _course, false)
	_check("legacy and kit-off scenery build no backdrop", not legacy.has_node("CityBackdrop") and not plain.has_node("CityBackdrop"))
	for built: Node in [legacy, plain]:
		built.get_parent().remove_child(built)
		built.free()


func _test_detectors() -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.5) * Basis.from_scale(Vector3(10, 20, 10)), Vector3(100, 10, 50))
	var world := _world_box(xf, AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))
	_check("detector: a rotated box is wider than its scale", world.size.x > 10.0 and is_equal_approx(world.size.y, 20.0))
	_check("detector: an overlapping lot is reported", _flat(world).intersects(AABB(Vector3(104, 0, 52), Vector3(4, 1, 4))))
	_check("detector: a clear lot is not reported", not _flat(world).intersects(AABB(Vector3(200, 0, 50), Vector3(4, 1, 4))))
	_check("detector: a road-centre box fails the oriented clearance", not _oriented_clear(Transform3D(Basis.from_scale(Vector3(6, 6, 6)), _course.points[40]["pos"])))


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
