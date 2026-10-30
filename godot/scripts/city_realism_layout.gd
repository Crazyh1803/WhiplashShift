class_name CityRealismLayout
extends RefCounted

const GLOBAL_BUDGET := 900000
const QUARTER_BUDGET := 240000
const NEAR_BUDGET := 320000
const SURFACE_BUDGET := 160
const CHUNK_LENGTH := 48.0
const DISTRICTS: Array[String] = ["Market boulevard", "Freight and service", "Utility works", "Housing and transit"]
const FAMILY_ORDER := [["market_habitat", "habitation_workshop", "redline_shop", "row_workshop"], ["freight_depot", "transit_depot", "row_workshop", "service_tenement"], ["utility_substation", "freight_depot", "habitation_workshop", "row_workshop"], ["service_tenement", "market_habitat", "transit_depot", "habitation_workshop"]]
var course: CourseDefinition
var placements: Array[Dictionary] = []
var reservations: Array[AABB] = []
var rejected: Array[Dictionary] = []
var solids: Array[PackedVector2Array] = []
var triangles := 0
var quarter_triangles: Array[int] = [0, 0, 0, 0]


func _init(input: CourseDefinition) -> void:
	course = input.geometry()


func populate() -> void:
	var quarter := course.total_length / 4.0
	for station in 8:
		for q in 4:
			for side: float in [-1.0, 1.0]:
				var s := quarter * (q + (station + 0.55) / 8.0)
				var family: String = FAMILY_ORDER[q][(station + int(side > 0)) % 4]
				_place(family, s, side, "building", 9.5)
	for index in int(course.total_length / 8.0):
		var s := 5.0 + 8.0 * index
		for side: float in [-1.0, 1.0]:
			_ground(s, side)
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


func transform_at(s: float, side: float, lateral: float) -> Transform3D:
	var at := CityDistrict.sample(course, s)
	var direction: Vector3 = at["dir"]
	var normal := Vector3(-direction.z, 0.0, direction.x) * side
	return Transform3D(Basis.looking_at(-normal, Vector3.UP), at["pos"] + normal * lateral)


func _ground(s: float, side: float) -> void:
	if not CityRealismCatalog.meshes.has("sidewalk_panel"):
		return
	var mesh: Mesh = CityRealismCatalog.meshes["sidewalk_panel"]
	var bounds := mesh.get_aabb()
	var at := CityDistrict.sample(course, s)
	var edge := float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	var xf := transform_at(s, side, edge + 6.75)
	xf.basis = xf.basis.scaled_local(Vector3(8.0 / bounds.size.x, 1.0, 5.5 / bounds.size.z))
	_try_add("sidewalk_panel", s, side, "ground", xf, false)


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
	if clearance(polygon, course) < CityScenery.ROAD_CLEARANCE:
		reason = "road_clearance"
	elif triangles + cost > GLOBAL_BUDGET or quarter_triangles[q] + cost > QUARTER_BUDGET:
		reason = "triangle_budget"
	if reason.is_empty() and solid:
		for other: PackedVector2Array in solids:
			if not Geometry2D.intersect_polygons(polygon, other).is_empty():
				reason = "solid_overlap"
				break
	var record := {"id": id, "s": s, "side": side, "quarter": q, "district": DISTRICTS[q], "role": role, "transform": xf, "bounds": xf * mesh.get_aabb(), "polygon": polygon, "tris": cost, "chunk": int(s / CHUNK_LENGTH)}
	if reason.is_empty() and role == "building" and not _fits_visible(record):
		reason = "visible_budget"
	if not reason.is_empty():
		rejected.append({"id": id, "s": s, "side": side, "reason": reason})
		return false
	placements.append(record)
	triangles += cost
	quarter_triangles[q] += cost
	if solid:
		solids.append(polygon)
		var bounds: AABB = record["bounds"]
		reservations.append(AABB(Vector3(bounds.position.x, 0.0, bounds.position.z), Vector3(bounds.size.x, 1.0, bounds.size.z)).grow(0.3))
	return true


func _fits_visible(candidate: Dictionary) -> bool:
	var buildings := placements.filter(func(p: Dictionary) -> bool: return p["role"] == "building")
	buildings.append(candidate)
	for s in range(0, int(course.total_length), 10):
		var at: Vector3 = CityDistrict.sample(course, float(s))["pos"]
		var cost := 0
		var surfaces := 0
		for p: Dictionary in buildings:
			var distance := at.distance_to((p["bounds"] as AABB).get_center())
			var radius := (p["bounds"] as AABB).size.length() * 0.5
			var far := distance - radius > 140.0
			if distance - radius > 450.0:
				continue
			var stats: Dictionary = CityRealismCatalog.costs[p["id"] + ("@far" if far else "")]
			cost += int(stats["tris"])
			surfaces += int(stats["surfaces"])
		if cost > NEAR_BUDGET - 40000 or surfaces > SURFACE_BUDGET - 32:
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
