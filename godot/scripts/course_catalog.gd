class_name CourseCatalog
extends RefCounted

const IDS: Array[String] = ["block_circuit", "split_shift"]
const LABELS := {"block_circuit": "Block Circuit // City", "split_shift": "Split Shift // Proving Ground"}


static func sanitize(id: String) -> String:
	return id if IDS.has(id) else "split_shift"


static func build_course(id: String, reverse: bool = false, laps: int = 0) -> CourseDefinition:
	var base: CourseDefinition
	if sanitize(id) == "block_circuit":
		base = BlockCircuitData.build_course()
	else:
		base = TrackData.build_course()
		base.configure(base.course_id, base.display_name, base.theme_id,
			base.default_laps, base.points.slice(16) + base.points.slice(0, 16))
	var count := clampi(laps, 1, 99) if laps != 0 else base.default_laps
	if not reverse:
		base.default_laps = count
		return base
	var points := reverse_points(base.points)
	var start := 0
	while start < points.size() and not grid_clear(points, start):
		start += 1
	if start == points.size():
		push_error("Course has no safe reverse grid: " + base.course_id)
		return null
	points = points.slice(start) + points.slice(0, start)
	var reversed := CourseDefinition.new().configure(base.course_id,
		base.display_name + " (Reverse)", base.theme_id, count, points)
	reversed.geometry_source = base
	reversed.is_reverse = true
	return reversed


static func build_scenery(parent: Node3D, course: CourseDefinition) -> void:
	var geometry := course.geometry()
	if course.course_id == "block_circuit":
		CityScenery.build(parent, geometry)
	else:
		TrackScenery.build(parent, geometry)
		TrackScenery.build_deposits(parent, geometry)
		TrackBuilder.build_proving_ground(parent, Vector3(-620.0, 0.0, 0.0))
	TrackScenery.build_guidance(parent, course)


static func reverse_points(forward: Array) -> Array:
	var out: Array = []
	var count := forward.size()
	for i in count:
		var vertex := posmod(-i, count)
		var edge := posmod(vertex - 1, count)
		var point: Dictionary = forward[vertex].duplicate(true)
		point["dir"] = -forward[vertex]["dir"]
		point["dist"] = forward[edge]["dist"]
		point["s"] = forward[edge]["s"]
		point.erase("relief")
		if forward[edge].has("relief"):
			point["relief"] = forward[edge]["relief"].duplicate(true)
		out.append(point)
	return out


static func grid_clear(points: Array, start: int) -> bool:
	var direction: Vector3 = points[start]["dir"]
	for offset in range(-18, 8):
		var point: Dictionary = points[posmod(start + offset, points.size())]
		if int(point["s"]) != Surfaces.Id.TARMAC or point.has("relief"):
			return false
		if direction.angle_to(point["dir"]) > deg_to_rad(8.0) or float(point["w"]) < 22.0:
			return false
	return true
