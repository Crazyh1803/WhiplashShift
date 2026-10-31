class_name CityRealismLayout
extends RefCounted

const BASE_GLOBAL_BUDGET := 900000
const BASE_QUARTER_BUDGET := 240000
const GLOBAL_BUDGET := 1500000
const QUARTER_BUDGET := 400000
const NEAR_BUDGET := 320000
const SURFACE_BUDGET := 160
const CHUNK_LENGTH := 48.0
const DISTRICTS: Array[String] = ["Market boulevard", "Freight and service", "Utility works", "Housing and transit"]
const INFILL_PITCH := 3.0
const INFILL_GAP := 0.9
const INFILL_WIDTHS := [1.0, 0.92, 1.08, 0.96, 1.12]
const INFILL_HEIGHTS := [1.0, 1.1, 0.92, 1.05]
const INFILL_SETBACKS := [9.5, 11.0, 10.2]
## Compositions reuse full-detail catalogue meshes: [family, extra setback, width scale, height scale].
const COMPOSITIONS := {
	"shop_terrace": [["row_workshop", 0.0, 0.65, 0.94], ["redline_shop", 0.0, 0.95, 1.1]],
	"tenement_court": [["service_tenement", 0.0, 0.7, 1.08], ["row_workshop", 3.2, 0.5, 0.9], ["service_tenement", 0.0, 0.7, 1.0]],
}
const FAMILY_ORDER := [["market_habitat", "habitation_workshop", "redline_shop", "row_workshop"], ["freight_depot", "transit_depot", "row_workshop", "service_tenement"], ["utility_substation", "freight_depot", "habitation_workshop", "row_workshop"], ["service_tenement", "market_habitat", "transit_depot", "habitation_workshop"]]
var course: CourseDefinition
var placements: Array[Dictionary] = []
var reservations: Array[AABB] = []
var rejected: Array[Dictionary] = []
var solids: Array[PackedVector2Array] = []
var rendering_groups: Dictionary = {}
var sample_positions := PackedVector3Array()
var ground_enabled := false
var triangles := 0
var quarter_triangles: Array[int] = [0, 0, 0, 0]
var infill_rejections: Dictionary = {}
var _quiet := false
var _side_triangle_limit := QUARTER_BUDGET
var _tag: Dictionary = {}


func _init(input: CourseDefinition) -> void:
	course = input.geometry()
	for s in range(0, int(course.total_length), 10):
		sample_positions.append(CityDistrict.sample(course, float(s))["pos"] + Vector3.UP * 1.5)


## `dense` adds the deterministic infill pass after the original 64 slots; false reproduces the baseline.
func populate(use_ground: bool = true, dense: bool = true) -> void:
	ground_enabled = use_ground and CityRealismCatalog.ground_available()
	var quarter := course.total_length / 4.0
	for index in int(course.total_length / 16.0):
		var s := 8.0 + 16.0 * index
		for side: float in [-1.0, 1.0]:
			_ground(s, side)
			if not ground_enabled or index % 6 == 0:
				_curb(s, side)
			if ground_enabled:
				_street_fabric(s, side)
			if index % 5 == 1:
				_place("street_lamp", s, side, "prop", 4.5)
			if index % 9 == 4:
				_place("refuse_station" if index % 2 == 0 else "bench_planter", s, side, "prop", 8.5)
			if index % 7 == 2:
				_place("bollard", s, side, "prop", 4.1)
			if index % 6 == 3:
				_place("drain_cover", s, side, "detail", 5.0)
			if index % 17 == 8:
				_place("alley_conduit", s, side, "prop", 11.0)

	if ground_enabled:
		var covered := float(int(course.total_length / 16.0)) * 16.0
		var remainder := course.total_length - covered
		if remainder > 0.5:
			for side: float in [-1.0, 1.0]:
				_ground(covered + remainder * 0.5, side, remainder)
				_street_fabric(covered + remainder * 0.5, side, remainder)

	for station in 8:
		for q in 4:
			for side: float in [-1.0, 1.0]:
				var s := quarter * (q + (station + 0.55) / 8.0)
				var family: String = FAMILY_ORDER[q][(station + int(side > 0)) % 4]
				_place(family, s, side, "building", 9.5)
	if dense:
		_infill(quarter)


## Walks every quarter side at a fixed pitch, trying compositions then single frontages with
## retries over families and setbacks. Failures are counted, never added to `rejected`.
func _infill(quarter: float) -> void:
	_quiet = true
	_side_triangle_limit = QUARTER_BUDGET
	var cells: Array[Dictionary] = []
	for q in 4:
		for side: float in [-1.0, 1.0]:
			cells.append({"q": q, "side": side, "s": quarter * q + 4.0, "end": quarter * (q + 1) - 4.0, "count": 0, "previous": ""})
	# Round robin: each pass gives every quarter/side one placement step, so no cell can
	# exhaust the shared quarter, global or visible budgets before the others start.
	var round_index := 0
	var open := true
	while open:
		open = false
		for i in cells.size():
			var cell: Dictionary = cells[(i + round_index) % cells.size()]
			if float(cell["s"]) < float(cell["end"]):
				_infill_step(cell)
				open = open or float(cell["s"]) < float(cell["end"])
		round_index += 1
	_tag = {}
	_quiet = false


## One placement attempt for a cell: a composition on every third slot, else a retried single frontage.
func _infill_step(cell: Dictionary) -> void:
	var q: int = cell["q"]
	var side: float = cell["side"]
	var s: float = cell["s"]
	var count: int = cell["count"]
	var seed_value := (q * 7 + int(side > 0.0) * 3 + count * 5) % 11
	var advance := INFILL_PITCH
	var placed_end := _infill_composition(q, side, s, count) if count % 3 == 0 else -1.0
	if placed_end > 0.0:
		advance = placed_end - s + INFILL_GAP
		cell["previous"] = ""
		cell["count"] = count + 1
	else:
		var order: Array = FAMILY_ORDER[q]
		for attempt in 4:
			var family: String = order[(count + attempt + int(side > 0.0) * 2) % 4]
			if family == cell["previous"]:
				continue
			_tag = {"variant": seed_value, "composition": ""}
			var setback: float = INFILL_SETBACKS[(seed_value + attempt) % 3]
			var scale := Vector2(INFILL_WIDTHS[seed_value % 5], INFILL_HEIGHTS[(seed_value + attempt) % 4])
			var before := placements.size()
			_place_scaled(family, s, side, setback, scale)
			if placements.size() > before:
				var width: float = (CityRealismCatalog.meshes[family] as Mesh).get_aabb().size.x * scale.x
				advance = width * 0.5 + INFILL_GAP + 3.0
				cell["previous"] = family
				cell["count"] = count + 1
				break
	cell["s"] = s + advance


## Places a contiguous frontage atomically; returns the far end distance, or -1.0 after rollback.
func _infill_composition(q: int, side: float, s: float, count: int) -> float:
	var name: String = COMPOSITIONS.keys()[(q + int(side > 0.0) + count / 5) % COMPOSITIONS.size()]
	var snapshot := _snapshot()
	var cursor := s
	var variant := (q * 5 + int(side > 0.0)) % 11
	for part: Array in COMPOSITIONS[name]:
		var family: String = part[0]
		if not CityRealismCatalog.meshes.has(family):
			_restore(snapshot)
			return -1.0
		var width: float = (CityRealismCatalog.meshes[family] as Mesh).get_aabb().size.x * float(part[2])
		cursor += width * 0.5
		_tag = {"variant": variant, "composition": name}
		var before := placements.size()
		_place_scaled(family, cursor, side, 9.5 + float(part[1]), Vector2(part[2], part[3]))
		if placements.size() == before:
			_restore(snapshot)
			return -1.0
		cursor += width * 0.5 + INFILL_GAP
	return cursor


func _snapshot() -> Dictionary:
	return {"placements": placements.size(), "reservations": reservations.size(), "solids": solids.size(), "triangles": triangles, "quarters": quarter_triangles.duplicate(), "groups": rendering_groups.duplicate(true)}


func _restore(snapshot: Dictionary) -> void:
	placements.resize(snapshot["placements"])
	reservations.resize(snapshot["reservations"])
	solids.resize(snapshot["solids"])
	triangles = snapshot["triangles"]
	quarter_triangles = snapshot["quarters"]
	rendering_groups = snapshot["groups"]


func _place_scaled(id: String, s: float, side: float, setback: float, scale: Vector2) -> void:
	if not CityRealismCatalog.meshes.has(id):
		return
	var bounds: AABB = CityRealismCatalog.meshes[id].get_aabb()
	var from := CityDistrict.sample(course, maxf(0.0, s - bounds.size.x * scale.x * 0.5))
	var to := CityDistrict.sample(course, minf(course.total_length - 0.001, s + bounds.size.x * scale.x * 0.5))
	if (from["dir"] as Vector3).angle_to(to["dir"]) > deg_to_rad(10.0):
		_count_rejection("curve")
		return
	var edge := float(CityDistrict.sample(course, s)["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	var xf := transform_at(s, side, edge + setback - bounds.position.z)
	xf.basis = xf.basis.scaled_local(Vector3(scale.x, scale.y, 1.0))
	_try_add(id, s, side, "building", xf, true)


func _count_rejection(reason: String) -> void:
	infill_rejections[reason] = int(infill_rejections.get(reason, 0)) + 1


func transform_at(s: float, side: float, lateral: float) -> Transform3D:
	var at := CityDistrict.sample(course, s)
	var direction: Vector3 = at["dir"]
	var normal := Vector3(-direction.z, 0.0, direction.x) * side
	return Transform3D(Basis.looking_at(-normal, Vector3.UP), at["pos"] + normal * lateral)


func _ground(s: float, side: float, length: float = 16.1) -> void:
	if not CityRealismCatalog.meshes.has("sidewalk_panel"):
		return
	var mesh: Mesh = CityRealismCatalog.meshes["sidewalk_panel"]
	var bounds := mesh.get_aabb()
	var at := CityDistrict.sample(course, s)
	var edge := float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	var xf := transform_at(s, side, edge + 6.75)
	xf.basis = xf.basis.scaled_local(Vector3(length / bounds.size.x, 1.0, 5.5 / bounds.size.z))
	_try_add("sidewalk_panel", s, side, "ground", xf, false)


func _curb(s: float, side: float) -> void:
	if not CityRealismCatalog.meshes.has("curb_segment"):
		return
	var mesh: Mesh = CityRealismCatalog.meshes["curb_segment"]
	var bounds := mesh.get_aabb()
	var at := CityDistrict.sample(course, s)
	var edge := float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	var xf := transform_at(s, side, edge + 4.05)
	xf.basis = xf.basis.scaled_local(Vector3(16.1 / bounds.size.x, 1, 1))
	_try_add("curb_segment", s, side, "ground", xf, false)


func _street_fabric(s: float, side: float, length: float = 16.0) -> void:
	var edge := float(CityDistrict.sample(course, s)["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	_apron(s, side, length)
	_flat_tile("service_lane", s, side, edge + 9.5 + float(CityRealismCatalog.GROUND_DEPTHS["service_lane"]) * 0.5, length)
	var quarter := mini(3, int(s / course.total_length * 4.0))
	var yard := "loading_yard" if quarter in [1, 2] else "utility_verge"
	_flat_tile(yard, s, side, edge + 9.5 + float(CityRealismCatalog.GROUND_DEPTHS["service_lane"]) + float(CityRealismCatalog.GROUND_DEPTHS[yard]) * 0.5, length)


func _apron(s: float, side: float, length: float) -> void:
	var edge := float(CityDistrict.sample(course, s)["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	var lateral := edge + 0.12 + float(CityRealismCatalog.GROUND_DEPTHS["road_apron"]) * 0.5
	var rejection_count := rejected.size()
	if _flat_tile("road_apron", s, side, lateral, length, "apron"):
		return
	if length > 2.0 and rejected.size() > rejection_count and rejected.back()["reason"] == "road_clearance":
		for offset: float in [-0.25, 0.25]:
			_apron(s + offset * length, side, length * 0.5)


func _flat_tile(id: String, s: float, side: float, lateral: float, length: float = 16.0, role: String = "ground") -> bool:
	var mesh: Mesh = CityRealismCatalog.meshes[id]
	var bounds := mesh.get_aabb()
	var xf := transform_at(s, side, lateral)
	xf.basis = xf.basis.scaled_local(Vector3(length / bounds.size.x, 1, 1))
	return _try_add(id, s, side, role, xf, false)


func _place(id: String, s: float, side: float, role: String, setback: float) -> void:
	if not CityRealismCatalog.meshes.has(id):
		return
	var bounds: AABB = CityRealismCatalog.meshes[id].get_aabb()
	if role == "building":
		var from := CityDistrict.sample(course, maxf(0.0, s - bounds.size.x * 0.5))
		var to := CityDistrict.sample(course, minf(course.total_length - 0.001, s + bounds.size.x * 0.5))
		if (from["dir"] as Vector3).angle_to(to["dir"]) > deg_to_rad(10.0):
			rejected.append({"id": id, "s": s, "reason": "curve"})
			return
	var at := CityDistrict.sample(course, s)
	var edge := float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	_try_add(id, s, side, role, transform_at(s, side, edge + setback - bounds.position.z), role in ["building", "prop"])


func _try_add(id: String, s: float, side: float, role: String, xf: Transform3D, solid: bool) -> bool:
	var mesh: Mesh = CityRealismCatalog.meshes[id]
	var polygon := footprint(mesh.get_aabb(), xf)
	var q := mini(3, int(s / course.total_length * 4.0))
	var cost := int(CityRealismCatalog.costs[id]["tris"])
	var reason := ""
	var required_clearance := 0.05 if id == "road_apron" and role == "apron" else CityScenery.ROAD_CLEARANCE
	var over_budget := triangles + cost > (GLOBAL_BUDGET if _quiet else BASE_GLOBAL_BUDGET) or quarter_triangles[q] + cost > (_side_triangle_limit if _quiet else BASE_QUARTER_BUDGET)
	if _quiet and over_budget:
		reason = "triangle_budget"  # cheap check first on infill retries
	elif clearance(polygon, course) < required_clearance:
		reason = "road_clearance"
	elif over_budget:
		reason = "triangle_budget"
	if reason.is_empty() and solid:
		for other: PackedVector2Array in solids:
			if not Geometry2D.intersect_polygons(polygon, other).is_empty():
				reason = "solid_overlap"
				break
	var record := {"variant": 0, "composition": ""}
	record.merge(_tag, true)
	record.merge({"id": id, "s": s, "side": side, "quarter": q, "district": DISTRICTS[q], "role": role, "transform": xf, "bounds": xf * mesh.get_aabb(), "polygon": polygon, "tris": cost, "chunk": int(s / CHUNK_LENGTH)}, true)
	if reason.is_empty() and role == "building" and not _fits_visible(record):
		reason = "visible_budget"
	if not reason.is_empty():
		if _quiet:
			_count_rejection(reason)
		else:
			rejected.append({"id": id, "s": s, "side": side, "reason": reason})
		return false
	placements.append(record)
	_add_group(rendering_groups, record)
	triangles += cost
	quarter_triangles[q] += cost
	if solid:
		solids.append(polygon)
		var bounds: AABB = record["bounds"]
		reservations.append(AABB(Vector3(bounds.position.x, 0.0, bounds.position.z), Vector3(bounds.size.x, 1.0, bounds.size.z)).grow(0.3))
	return true


func _add_group(groups: Dictionary, p: Dictionary) -> void:
	for far: bool in ([false, true] if p["role"] == "building" else [false]):
		var key := Vector2i(int(p["chunk"]), int(far))
		var stats: Dictionary = CityRealismCatalog.costs[p["id"] + ("@far" if far else "")]
		if not groups.has(key):
			groups[key] = {"bounds": p["bounds"], "tris": 0, "materials": {}}
		var group: Dictionary = groups[key]
		group["bounds"] = (group["bounds"] as AABB).merge(p["bounds"])
		group["tris"] += stats["tris"]
		for material: String in stats["materials"]:
			group["materials"][material] = true


func _fits_visible(candidate: Dictionary) -> bool:
	var groups := rendering_groups.duplicate(true)
	_add_group(groups, candidate)
	for eye: Vector3 in sample_positions:
		var cost := 0
		var surfaces := 0
		for key: Vector2i in groups:
			var group: Dictionary = groups[key]
			var bounds: AABB = groups[Vector2i(key.x, 0)]["bounds"]
			var distance := eye.distance_to(bounds.get_center())
			if distance > (460.0 if key.y == 1 else 150.0) or (key.y == 1 and distance < 130.0):
				continue
			cost += int(group["tris"])
			surfaces += group["materials"].size()
		if cost > NEAR_BUDGET or surfaces > SURFACE_BUDGET:
			return false
	return true


static func footprint(bounds: AABB, xf: Transform3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner: Vector3 in [bounds.position, Vector3(bounds.end.x, 0, bounds.position.z), bounds.end, Vector3(bounds.position.x, 0, bounds.end.z)]:
		var p := xf * corner
		points.append(Vector2(p.x, p.z))
	return points


static func clearance(polygon: PackedVector2Array, course: CourseDefinition) -> float:
	var best := INF
	var centre := Vector2.ZERO
	for p in polygon:
		centre += p / polygon.size()
	var radius := 0.0
	for p in polygon:
		radius = maxf(radius, centre.distance_to(p))
	for i in course.points.size():
		var a: Vector3 = course.points[i]["pos"]
		var b: Vector3 = course.points[(i + 1) % course.points.size()]["pos"]
		var pa := Vector2(a.x, a.z)
		var pb := Vector2(b.x, b.z)
		var edge := maxf(float(course.points[i]["w"]), float(course.points[(i + 1) % course.points.size()]["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET
		if centre.distance_to(Geometry2D.get_closest_point_to_segment(centre, pa, pb)) - radius - edge >= best:
			continue
		var distance := INF
		if Geometry2D.is_point_in_polygon(pa, polygon) or Geometry2D.is_point_in_polygon(pb, polygon):
			distance = 0.0
		for j in polygon.size():
			var c := polygon[j]
			var d := polygon[(j + 1) % polygon.size()]
			if Geometry2D.segment_intersects_segment(pa, pb, c, d) != null:
				distance = 0.0
			for pair: Array in [[pa, c, d], [pb, c, d], [c, pa, pb], [d, pa, pb]]:
				distance = minf(distance, pair[0].distance_to(Geometry2D.get_closest_point_to_segment(pair[0], pair[1], pair[2])))
		best = minf(best, distance - edge)
	return best
