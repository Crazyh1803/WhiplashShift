## Block Circuit layout and City scenery invariants; headless, no rendering.
extends Node3D

const ROUTE_EXCLUSION := 120.0
const LIMIT := 1100.0

var _pass := 0
var _fail := 0


func _ready() -> void:
	var course := BlockCircuitData.build_course()
	_test_identity(course)
	_test_loop(course)
	_test_envelopes(course)
	_test_grid(course)
	_test_surfaces(course)
	_test_scenery(course)
	print("BLOCK_CIRCUIT: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_identity(course: CourseDefinition) -> void:
	_check("course validates", course.validate().is_empty())
	_check("identity", course.course_id == "block_circuit" and course.theme_id == "city_stacks" and course.default_laps == 3)
	_check("checkpoint zero is point zero", course.checkpoints[0]["index"] == 0)
	_check("length 1400-2200 m (%.0f)" % course.total_length, course.total_length >= 1400.0 and course.total_length <= 2200.0)
	var again := BlockCircuitData.build_course()
	_check("course is deterministic", again.points == course.points and again.total_length == course.total_length)


func _test_loop(course: CourseDefinition) -> void:
	var points := course.points
	var count := points.size()
	var finite := true
	var inside := true
	var summed := 0.0
	var turning := 0.0
	var worst_turn := 0.0
	var worst_tangent := 0.0
	var worst_curvature := 0.0
	for i in count:
		var p: Vector3 = points[i]["pos"]
		var d: Vector3 = points[i]["dir"]
		finite = finite and p.is_finite() and d.is_finite() and is_finite(float(points[i]["dist"]))
		inside = inside and absf(p.x) <= LIMIT and absf(p.z) <= LIMIT and p.y == 0.0
		var nxt: Vector3 = points[(i + 1) % count]["pos"]
		var prv: Vector3 = points[(i - 1 + count) % count]["pos"]
		var expected := (nxt - prv).normalized()
		worst_tangent = maxf(worst_tangent, d.angle_to(expected))
		_check_once(absf(d.length() - 1.0) < 0.0001 and d.y == 0.0, "unit flat tangents", i)
		var next_dir: Vector3 = points[(i + 1) % count]["dir"]
		var turn := d.signed_angle_to(next_dir, Vector3.UP)
		turning += turn
		worst_turn = maxf(worst_turn, absf(turn))
		worst_curvature = maxf(worst_curvature, absf(turn) / maxf(float(points[i]["dist"]), 0.1))
		summed += float(points[i]["dist"])
		_check_once(absf(float(points[i]["w"]) - BlockCircuitData.WIDTH) < 0.001, "constant width", i)
	_check("all points finite", finite)
	_check("coordinates inside +/-1100", inside)
	_check("dist sums to total_length", is_equal_approx(summed, course.total_length))
	_check("closing step matches sample spacing", float(points[count - 1]["dist"]) > 2.5 and float(points[count - 1]["dist"]) < 4.5)
	_check("loop turns exactly once (%.2f rad)" % turning, absf(absf(turning) - TAU) < 0.05)
	_check("tangents follow the centreline (%.4f rad)" % worst_tangent, worst_tangent < 0.02)
	_check("turn per sample stays smooth (%.3f rad)" % worst_turn, worst_turn < deg_to_rad(6.0))
	_check("no corner tighter than 35 m radius (1/%.0f)" % (1.0 / maxf(worst_curvature, 0.0001)), worst_curvature < 1.0 / 35.0)


func _route_gap(a: int, b: int, cumulative: PackedFloat32Array, total: float) -> float:
	var gap := absf(cumulative[a] - cumulative[b])
	return minf(gap, total - gap)


func _cumulative(course: CourseDefinition) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var run := 0.0
	for point: Dictionary in course.points:
		out.append(run)
		run += float(point["dist"])
	return out


func _test_envelopes(course: CourseDefinition) -> void:
	var points := course.points
	var count := points.size()
	var cumulative := _cumulative(course)
	var needed := BlockCircuitData.WIDTH + 2.0 * TrackBuilder.RAIL_OFFSET + 3.0
	var tightest := INF
	for i in count:
		var p := Vector2(points[i]["pos"].x, points[i]["pos"].z)
		for j in count:
			if _route_gap(i, j, cumulative, course.total_length) < ROUTE_EXCLUSION:
				continue
			var a := Vector2(points[j]["pos"].x, points[j]["pos"].z)
			var next: Dictionary = points[(j + 1) % count]
			var b := Vector2(next["pos"].x, next["pos"].z)
			tightest = minf(tightest, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	_check("distant road never nears itself (%.1f m >= %.1f)" % [tightest, needed], tightest >= needed)


func _test_grid(course: CourseDefinition) -> void:
	var points := course.points
	var count := points.size()
	var origin: Dictionary = points[0]
	var behind := 0.0
	var index := count - 1
	while _straight_tarmac(points[index], origin) and behind < 400.0:
		behind += float(points[index]["dist"])
		index = (index - 1 + count) % count
	var ahead := 0.0
	index = 0
	while _straight_tarmac(points[index], origin) and ahead < 600.0:
		ahead += float(points[index]["dist"])
		index = (index + 1) % count
	_check("at least 80 m of straight tarmac behind the line (%.0f)" % behind, behind >= 80.0)
	_check("at least 120 m of straight tarmac after the line (%.0f)" % ahead, ahead >= 120.0)
	_check("grid straight is 26 m wide", BlockCircuitData.WIDTH >= 26.0)


func _straight_tarmac(point: Dictionary, reference: Dictionary) -> bool:
	return int(point["s"]) == Surfaces.Id.TARMAC and (point["dir"] as Vector3).angle_to(reference["dir"]) < 0.005


func _test_surfaces(course: CourseDefinition) -> void:
	var points := course.points
	var count := points.size()
	var allowed := [Surfaces.Id.TARMAC, Surfaces.Id.RUMBLE, Surfaces.Id.GRAVEL]
	var clean := true
	var start := 0
	for i in count:
		clean = clean and allowed.has(int(points[i]["s"])) and not points[i].has("relief")
		if int(points[i]["s"]) != int(points[(i - 1 + count) % count]["s"]):
			start = i
	_check("only tarmac, rumble and gravel with no relief authoring", clean)
	var shortest := INF
	var gravel := 0.0
	var gravel_turn := 0.0
	var run := 0.0
	var run_turn := 0.0
	var current := int(points[start]["s"])
	for step in count:
		var i := (start + step) % count
		var sid := int(points[i]["s"])
		if sid != current:
			shortest = minf(shortest, run)
			if current == Surfaces.Id.GRAVEL:
				gravel = maxf(gravel, run)
				gravel_turn = maxf(gravel_turn, run_turn)
			current = sid
			run = 0.0
			run_turn = 0.0
		run += float(points[i]["dist"])
		run_turn += absf((points[i]["dir"] as Vector3).signed_angle_to(points[(i + 1) % count]["dir"], Vector3.UP))
	shortest = minf(shortest, run)
	_check("every surface run exceeds 40 m (%.1f)" % shortest, shortest > 40.0)
	_check("one gravel section lasts at least 100 m (%.0f)" % gravel, gravel >= 100.0)
	_check("gravel runs through a deliberate turn (%.0f deg)" % rad_to_deg(gravel_turn), rad_to_deg(gravel_turn) >= 60.0)
	var straights := 0
	var straight := 0.0
	for step in count:
		var i := (start + step) % count
		var bend := absf((points[i]["dir"] as Vector3).signed_angle_to(points[(i + 1) % count]["dir"], Vector3.UP))
		if bend < 0.0005 and int(points[i]["s"]) == Surfaces.Id.TARMAC:
			straight += float(points[i]["dist"])
		else:
			if straight >= 250.0:
				straights += 1
			straight = 0.0
	if straight >= 250.0:
		straights += 1
	_check("two tarmac overtaking straights of 250 m+ (%d)" % straights, straights >= 2)


func _test_scenery(course: CourseDefinition) -> void:
	var host := Node3D.new()
	add_child(host)
	var scenery := CityScenery.build(host, course)
	var second_host := Node3D.new()
	add_child(second_host)
	var repeat := CityScenery.build(second_host, course)
	_check("scenery has no collision objects", scenery.find_children("*", "CollisionObject3D", true, false).is_empty())
	var lights := scenery.find_children("*", "OmniLight3D", true, false)
	_check("light budget stays 6-12 and shadowless (%d)" % lights.size(), lights.size() >= 6 and lights.size() <= CityScenery.MAX_LIGHTS
		and lights.all(func(light: OmniLight3D) -> bool: return not light.shadow_enabled)
		and scenery.find_children("*", "DirectionalLight3D", true, false).is_empty() and scenery.find_children("*", "SpotLight3D", true, false).is_empty())
	var meshes := scenery.find_children("*", "MeshInstance3D", true, false)
	var batches := scenery.find_children("*", "MultiMeshInstance3D", true, false)
	var district := scenery.get_node_or_null("CityKit") as Node3D
	var instances := 0
	var street := scenery.get_node_or_null("CityStreetBlock") as Node3D
	var legacy_batches := 0
	var street_batches := 0
	for batch: MultiMeshInstance3D in batches:
		instances += batch.multimesh.instance_count
		street_batches += int(street != null and street.is_ancestor_of(batch))
		legacy_batches += int((district == null or not district.is_ancestor_of(batch)) and (street == null or not street.is_ancestor_of(batch)))
	var kit_batches := batches.size() - legacy_batches - street_batches
	_check("street block exists with its own separate draw budget", street != null and street_batches >= 20)
	_check("draw nodes bounded (%d meshes, %d legacy + %d kit + %d street batches)" % [meshes.size(), legacy_batches, kit_batches, street_batches],
		meshes.size() <= 24 and legacy_batches <= 12 and kit_batches <= 14 and street_batches <= 24)
	_check("instance count bounded (%d)" % instances, instances >= 300 and instances <= 4500)
	_check("has crown, skyline, towers and street kit", scenery.has_node("Crown") and scenery.has_node("Skyline")
		and scenery.has_node("Body") and scenery.has_node("Rib") and scenery.has_node("Wall") and scenery.has_node("Cyan") and scenery.has_node("Amber"))
	_check("sinew is sparing", not scenery.has_node("Sinew") or scenery.get_node("Sinew").multimesh.instance_count <= 12)
	var worst := INF
	var nearest_wall := INF
	var outside := false
	var boxes := 0
	var disagreements := 0
	var moved := 0
	for batch: MultiMeshInstance3D in batches:
		var placed: Array = _placed(batch)
		_check("%s keeps one transform record per instance" % batch.name, placed.size() == batch.multimesh.instance_count)
		for i in placed.size():
			var world := _world_box(batch.global_transform * (placed[i] as Transform3D), batch.get_meta("city_local_aabb", CityScenery.UNIT_BOX))
			var gap := CityScenery.road_clearance(world, course)
			worst = minf(worst, gap)
			if batch.name == "Wall":
				nearest_wall = minf(nearest_wall, gap)
			outside = outside or _outside(world)
			boxes += 1
			moved += int((placed[i] as Transform3D).origin != Vector3.ZERO)
			if i % 5 == 0 and not _gap_agrees(world, gap, course):
				disagreements += 1
	for mesh: MeshInstance3D in meshes:
		var world := _world_box(mesh.global_transform, _mesh_local(mesh.mesh))
		var gap := CityScenery.road_clearance(world, course)
		worst = minf(worst, gap)
		outside = outside or _outside(world)
		boxes += 1
		if not _gap_agrees(world, gap, course):
			disagreements += 1
	_check("recorded placements are real, not identity (%d of %d)" % [moved, boxes], moved >= boxes - meshes.size() - 1)
	_check("every world AABB (%d) clears the full road envelope (%.1f m)" % [boxes, worst], worst >= 3.0)
	_check("street walls hug the road, proving clearance is measured (%.1f m)" % nearest_wall, nearest_wall >= 3.5 and nearest_wall < 12.0)
	_check("clearance matches independent point sampling (%d disagreements)" % disagreements, disagreements == 0)
	_check("scenery stays inside +/-1100", not outside)
	_check("independent centreline sampling agrees for towers and crown", _sampled_clear(course, scenery))
	_check("clearance rejects road centre", CityScenery.road_clearance(AABB(course.points[40]["pos"] - Vector3(2, 0, 2), Vector3(4, 10, 4)), course) < 0.0)
	_check("clearance accepts distant ground", CityScenery.road_clearance(AABB(Vector3(900, 0, 900), Vector3(4, 10, 4)), course) > 100.0)
	_test_clearance_bounds(course)
	_check("rebuild places identical batches", _signature(scenery) == _signature(repeat))
	_test_authored_district(scenery, course, district)
	host.free()
	second_host.free()


func _outside(world: AABB) -> bool:
	return absf(world.position.x) > LIMIT or absf(world.end.x) > LIMIT or absf(world.position.z) > LIMIT or absf(world.end.z) > LIMIT


func _placed(batch: MultiMeshInstance3D) -> Array:
	return batch.get_meta("city_transforms", [])


## Corner-by-corner world bounds, independent of AABB/Transform3D multiplication.
func _world_box(xf: Transform3D, local: AABB) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for corner in 8:
		var c := local.position + Vector3(local.size.x * float(corner & 1), local.size.y * float((corner >> 1) & 1), local.size.z * float((corner >> 2) & 1))
		var w := xf.basis * c + xf.origin
		low = Vector3(minf(low.x, w.x), minf(low.y, w.y), minf(low.z, w.z))
		high = Vector3(maxf(high.x, w.x), maxf(high.y, w.y), maxf(high.z, w.z))
	return AABB(low, high - low)


func _mesh_local(mesh: Mesh) -> AABB:
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


## Centreline samples are at most 4.5 m apart, so segment clearance lies within 2.3 m below the sample gap.
func _gap_agrees(world: AABB, gap: float, course: CourseDefinition) -> bool:
	var low := Vector2(world.position.x, world.position.z)
	var high := Vector2(world.end.x, world.end.z)
	var sampled := INF
	for point: Dictionary in course.points:
		var p: Vector3 = point["pos"]
		var out := Vector2(maxf(maxf(low.x - p.x, 0.0), p.x - high.x), maxf(maxf(low.y - p.z, 0.0), p.z - high.y))
		sampled = minf(sampled, out.length() - float(point["w"]) * 0.5 - TrackBuilder.RAIL_OFFSET)
	return gap <= sampled + 0.001 and gap >= sampled - 2.3


func _test_clearance_bounds(course: CourseDefinition) -> void:
	var at: Dictionary = course.points[0]
	var pos: Vector3 = at["pos"]
	var side: Vector3 = (at["dir"] as Vector3).cross(Vector3.UP)
	var edge: float = float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	var near_reject := 0.0
	var near_accept := 0.0
	for gap: float in [1.0, 3.0, 4.0, 6.0]:
		var centre := pos + side * (edge + gap + 0.1)
		var measured := CityScenery.road_clearance(AABB(centre - Vector3(0.1, 0, 0.1), Vector3(0.2, 8, 0.2)), course)
		_check("clearance %.1f m from the rail reads %.2f" % [gap, measured], absf(measured - gap) < 0.2)
		if gap == 1.0:
			near_reject = measured
		if gap == 4.0:
			near_accept = measured
	_check("near-road box is rejected below %.1f m and one past it accepted" % CityScenery.ROAD_CLEARANCE,
			near_reject < CityScenery.ROAD_CLEARANCE and near_accept >= CityScenery.ROAD_CLEARANCE)
	var straddle := pos + side * (edge - 5.0)
	_check("box overlapping the rail reads negative", CityScenery.road_clearance(AABB(straddle - Vector3(1, 0, 1), Vector3(2, 8, 2)), course) < 0.0)


func _sampled_clear(course: CourseDefinition, scenery: Node3D) -> bool:
	var body: MultiMeshInstance3D = scenery.get_node("Body")
	var local: AABB = body.get_meta("city_local_aabb", CityScenery.UNIT_BOX)
	var count := course.points.size()
	var placed := _placed(body)
	for i in placed.size():
		var world := _world_box(body.global_transform * (placed[i] as Transform3D), local)
		var centre := Vector2(world.get_center().x, world.get_center().z)
		var half := Vector2(world.size.x, world.size.z) * 0.5
		for k in count:
			var p: Vector3 = course.points[k]["pos"]
			var offset := Vector2(maxf(absf(p.x - centre.x) - half.x, 0.0), maxf(absf(p.z - centre.y) - half.y, 0.0))
			if offset.length() < float(course.points[k]["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET + 1.5:
				return false
	return true


func _test_authored_district(scenery: Node3D, course: CourseDefinition, district: Node3D) -> void:
	_check("opening quarter is an authored district", district != null and scenery.get_meta("authored_quarter") == true)
	if district == null:
		return
	var placements: Array = district.get_meta("placements", [])
	var assets := {}
	for placement: Dictionary in placements:
		assets[placement["asset"]] = true
	# The street block reserves the near quarter, so only the remaining quarter carries the older kit.
	_check("authored district places a reduced set across all roles (%d)" % placements.size(), placements.size() >= CityKit.EXPECTED_IDS.size() and placements.size() <= 40)
	_check("authored district uses all %d kit assets (%d)" % [CityKit.EXPECTED_IDS.size(), assets.size()], assets.size() == CityKit.EXPECTED_IDS.size())
	_check("authored district stays inside its triangle budget (%d)" % int(district.get_meta("triangle_count")),
		int(district.get_meta("triangle_count")) > 0 and int(district.get_meta("triangle_count")) <= CityDistrict.TRIANGLE_BUDGET)
	var quarter := course.total_length * CityDistrict.FRACTION
	var legacy_inside := 0
	for transform: Transform3D in _placed(scenery.get_node("Body")):
		legacy_inside += int(CityDistrict.route_distance(course, transform.origin) < quarter - 40.0)
	_check("legacy towers no longer fill the authored quarter (%d)" % legacy_inside, legacy_inside == 0)
	_check("legacy towers still line the rest of the circuit", _placed(scenery.get_node("Body")).size() >= 100)


func _signature(scenery: Node3D) -> Array:
	var out: Array = []
	for child in scenery.get_children():
		if child is MultiMeshInstance3D:
			out.append([child.name, child.multimesh.instance_count, _placed(child)])
		elif child is OmniLight3D:
			out.append([child.position, child.light_color])
		elif child is Node3D:
			out.append([child.name, child.position, child.get_child_count()])
	return out


func _check_once(condition: bool, label: String, index: int) -> void:
	if not condition:
		_check("%s at point %d" % [label, index], false)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
