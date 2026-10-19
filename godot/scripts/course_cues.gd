## Read-only route information for advance terrain warnings.
class_name CourseCues
extends RefCounted

const BOARD_LEAD := 80.0
var course: CourseDefinition
var events: Array[Dictionary] = []
var _cumulative := PackedFloat64Array()


func setup(p_course: CourseDefinition) -> void:
	course = p_course
	events.clear()
	_cumulative.clear()
	var metres := 0.0
	for i in course.points.size():
		_cumulative.append(metres)
		var sid := int(course.points[i]["s"])
		var previous := int(course.points[posmod(i - 1, course.points.size())]["s"])
		var back := 1
		while previous == Surfaces.Id.RUMBLE and back < course.points.size():
			back += 1
			previous = int(course.points[posmod(i - back, course.points.size())]["s"])
		if sid != previous and sid != Surfaces.Id.RUMBLE:
			events.append({"index": i, "distance": metres, "surface": sid})
		metres += float(course.points[i]["dist"])
	for i in events.size():
		var previous: Dictionary = events[posmod(i - 1, events.size())]
		var gap := fposmod(float(events[i]["distance"]) - float(previous["distance"]), course.total_length)
		if events.size() == 1:
			gap = course.total_length
		events[i]["lead"] = minf(BOARD_LEAD, gap * 0.5)


func upcoming(distance: float, speed: float) -> Dictionary:
	var horizon := clampf(maxf(0.0, speed) * 4.0, 90.0, 200.0)
	var nearest: Dictionary = {}
	var best := INF
	for event: Dictionary in events:
		var ahead := fposmod(float(event["distance"]) - distance, course.total_length)
		# At the boundary the new surface is already current, not upcoming.
		if ahead > 0.5 and ahead <= horizon and ahead < best:
			nearest = event
			best = ahead
	return {} if nearest.is_empty() else {"surface": nearest["surface"], "metres": best}


static func advice(surface: int, active_end: String) -> String:
	if surface == Surfaces.Id.ICE or surface == Surfaces.Id.OIL:
		return "LOW GRIP — HOLD END %s" % active_end
	var preferred: String = Surfaces.PREFERRED[surface]
	return "END %s READY" % preferred if preferred == active_end else "PREPARE END %s  [SPACE]" % preferred


static func board_advice(surface: int) -> String:
	if surface == Surfaces.Id.ICE or surface == Surfaces.Id.OIL:
		return "LOW GRIP"
	return "END " + Surfaces.PREFERRED[surface]


func sample_at(distance: float) -> Dictionary:
	var wrapped := fposmod(distance, course.total_length)
	for i in course.points.size():
		var length := float(course.points[i]["dist"])
		if wrapped <= _cumulative[i] + length or i == course.points.size() - 1:
			var a: Vector3 = course.points[i]["pos"]
			var b: Vector3 = course.points[(i + 1) % course.points.size()]["pos"]
			var t := clampf((wrapped - _cumulative[i]) / maxf(length, 0.0001), 0.0, 1.0)
			return {"index": i, "position": a.lerp(b, t), "direction": (b - a).normalized(), "width": course.points[i]["w"]}
	return {}
