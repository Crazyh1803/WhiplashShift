## Read-only route information for advance terrain warnings.
class_name CourseCues
extends RefCounted

const BOARD_LEAD := 80.0
var course: CourseDefinition
var events: Array[Dictionary] = []
var corners: Array[Dictionary] = []
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
	_build_corners()


func _build_corners() -> void:
	corners.clear()
	var n := course.points.size()
	var turns: Array[float] = []
	var signs: Array[int] = []
	for i in n:
		var a: Vector3 = course.points[i]["dir"]
		var b: Vector3 = course.points[(i + 1) % n]["dir"]
		var angle := atan2(-a.cross(b).y, a.dot(b))
		turns.append(angle)
	var smoothed := _smooth_turns(turns)
	for i in n:
		turns[i] = smoothed[i] * float(course.points[i]["dist"])
		signs.append(0 if absf(smoothed[i]) < 0.004 else (1 if smoothed[i] > 0.0 else -1))
	# Start at a sign boundary so a turn crossing index zero remains one run.
	var start := 0
	for i in n:
		if signs[i] != signs[posmod(i - 1, n)]:
			start = i
			break
	var consumed := 0
	while consumed < n:
		var first := (start + consumed) % n
		var side := signs[first]
		var length := 0.0
		var angle := 0.0
		var max_curvature := 0.0
		var surfaces: Array[int] = []
		while consumed < n and signs[(start + consumed) % n] == side:
			var index := (start + consumed) % n
			var segment_length := float(course.points[index]["dist"])
			length += segment_length
			angle += turns[index]
			max_curvature = maxf(max_curvature, absf(turns[index]) / maxf(segment_length, 0.001))
			var sid := int(course.points[index]["s"])
			if not surfaces.has(sid):
				surfaces.append(sid)
			consumed += 1
		if side == 0 or length < 15.0 or absf(angle) < deg_to_rad(25.0):
			continue
		var severity := "BEND"
		if absf(angle) >= deg_to_rad(150.0) and max_curvature >= 1.0 / 75.0:
			severity = "HAIRPIN"
		elif max_curvature >= 0.012 or absf(angle) >= deg_to_rad(100.0):
			severity = "TIGHT TURN"
		corners.append({"index": first, "distance": _cumulative[first], "length": length,
			"curvature": max_curvature, "surfaces": surfaces,
			"label": severity + (" RIGHT" if side > 0 else " LEFT")})


func _smooth_turns(turns: Array[float]) -> Array[float]:
	var result: Array[float] = []
	for i in turns.size():
		var angle := turns[i]
		var length := float(course.points[i]["dist"])
		for step: int in [-1, 1]:
			var remaining := 8.0
			var index := posmod(i + step, turns.size())
			var visited := 0
			while remaining > 0.0 and visited < turns.size() - 1:
				var segment_length := float(course.points[index]["dist"])
				var used := minf(remaining, segment_length)
				angle += turns[index] * used / maxf(segment_length, 0.001)
				length += used
				remaining -= used
				index = posmod(index + step, turns.size())
				visited += 1
		result.append(angle / maxf(length, 0.001))
	return result


func corner_advice(distance: float, vehicle: Vehicle) -> Dictionary:
	var nearest: Dictionary = {}
	var best := INF
	var current_sid := int(course.points[_index_at(distance)]["s"])
	for corner: Dictionary in corners:
		var through := fposmod(distance - float(corner["distance"]), course.total_length)
		var inside := through < float(corner["length"])
		var ahead := 0.0 if inside else fposmod(float(corner["distance"]) - distance, course.total_length)
		var mu := INF
		var top_speed := INF
		var low_grip := false
		for sid: int in corner["surfaces"]:
			mu = minf(mu, vehicle.tuning.tire_grip(vehicle.active_end) * vehicle.grip_multiplier
				* Surfaces.GRIP[sid] * Surfaces.mod_grip(vehicle.active_end, sid))
			top_speed = minf(top_speed, vehicle.tuning.top_speed(vehicle.active_end) * vehicle.top_speed_multiplier * Surfaces.mod_top(vehicle.active_end, sid))
			low_grip = low_grip or sid in [Surfaces.Id.ICE, Surfaces.Id.OIL]
		var target_speed := minf(top_speed, sqrt(maxf(0.0, mu) * 9.81 / float(corner["curvature"])) * 0.8)
		var brake_mu := minf(vehicle.tuning.tire_grip("A") * Surfaces.mod_grip("A", current_sid),
			vehicle.tuning.tire_grip("B") * Surfaces.mod_grip("B", current_sid)) * vehicle.grip_multiplier * Surfaces.GRIP[current_sid]
		var deceleration := maxf(0.05, minf(vehicle.tuning.brake_force(vehicle.active_end)
			* vehicle.brake_multiplier / maxf(vehicle.mass, 1.0), brake_mu * 9.81) * 0.65)
		var braking_distance := maxf(0.0, (vehicle.speed * vehicle.speed - target_speed * target_speed) / (2.0 * deceleration))
		var lead := braking_distance + vehicle.speed * 1.0 + 10.0
		var horizon := maxf(90.0, maxf(vehicle.speed * 4.0, lead))
		if ahead <= horizon and ahead < best:
			best = ahead
			nearest = {"label": corner["label"], "metres": ahead, "inside": inside,
				"speed": target_speed, "low_grip": low_grip, "braking_lead": lead,
				"slow": vehicle.speed > target_speed + 1.5 and (inside or ahead <= lead)}
	return nearest


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
	var i := _index_at(distance)
	var length := float(course.points[i]["dist"])
	var a: Vector3 = course.points[i]["pos"]
	var b: Vector3 = course.points[(i + 1) % course.points.size()]["pos"]
	var t := clampf((wrapped - _cumulative[i]) / maxf(length, 0.0001), 0.0, 1.0)
	return {"index": i, "position": a.lerp(b, t), "direction": (b - a).normalized(), "width": course.points[i]["w"]}


func _index_at(distance: float) -> int:
	var wrapped := fposmod(distance, course.total_length)
	var low := 0
	var high := _cumulative.size() - 1
	while low < high:
		var middle := low + ((high - low + 1) >> 1)
		if _cumulative[middle] <= wrapped:
			low = middle
		else:
			high = middle - 1
	return low
