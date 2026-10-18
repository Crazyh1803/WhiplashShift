## Centreline projection and measured travel; recovery never awards progress.
class_name TrackProgress
extends RefCounted

var course: CourseDefinition
var index: int = 0
var lap: int = 0
var distance: float = 0.0
var total_distance: float = 0.0
## Unwrapped route position for standings, including backwards checkpoint recovery.
var route_distance: float = 0.0
var off_line: float = 0.0
var wrong_way: bool = false
var _cumulative := PackedFloat64Array()
var _lap_travel: float = 0.0
var _reverse_travel: float = 0.0
var _next_checkpoint: int = 1


func setup(p_course: CourseDefinition, start_index: int = 0) -> void:
	course = p_course
	_cumulative.clear()
	var metres := 0.0
	for point: Dictionary in course.points:
		_cumulative.append(metres)
		metres += float(point["dist"])
	reset(start_index)


func reset(start_index: int = 0) -> void:
	lap = 0
	total_distance = 0.0
	_lap_travel = 0.0
	_next_checkpoint = 1
	distance = _cumulative[posmod(start_index, course.points.size())]
	route_distance = distance
	recover(start_index)


func recover(start_index: int) -> void:
	index = posmod(start_index, course.points.size())
	var retreat := minf(0.0, wrapf(_cumulative[index] - distance,
		-course.total_length * 0.5, course.total_length * 0.5))
	route_distance += retreat
	_lap_travel = maxf(0.0, _lap_travel + retreat)
	distance = _cumulative[index]
	off_line = 0.0
	wrong_way = false
	_reverse_travel = 0.0


func update(position: Vector3) -> void:
	var flat := Vector3(position.x, 0.0, position.z)
	var best_index := index
	var best_t := 0.0
	var best_sq := INF
	var n := course.points.size()
	for offset in range(-35, 36):
		var candidate := posmod(index + offset, n)
		var a: Vector3 = course.points[candidate]["pos"]
		var b: Vector3 = course.points[(candidate + 1) % n]["pos"]
		a.y = 0.0
		b.y = 0.0
		var segment := b - a
		var t := clampf((flat - a).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var sq := flat.distance_squared_to(a + segment * t)
		if sq < best_sq:
			best_sq = sq
			best_index = candidate
			best_t = t
	off_line = sqrt(best_sq)
	var next_distance: float = _cumulative[best_index] + float(course.points[best_index]["dist"]) * best_t
	next_distance = fposmod(next_distance, course.total_length)
	var delta := wrapf(next_distance - distance, -course.total_length * 0.5, course.total_length * 0.5)
	# Keep the last valid route anchor when a car leaves the ribbon. Otherwise
	# nearest-point drift could move its recovery checkpoint forwards for free.
	if absf(delta) >= 100.0 or off_line >= float(course.points[best_index]["w"]) * 0.65:
		return
	if absf(delta) < 100.0:
		total_distance += delta
		route_distance += delta
		_lap_travel = maxf(0.0, _lap_travel + delta)
		if delta < -0.02:
			_reverse_travel += -delta
		elif delta > 0.02:
			_reverse_travel = maxf(0.0, _reverse_travel - delta)
		wrong_way = _reverse_travel > 3.0
		if delta > 0.0:
			var crosses_line := next_distance < distance
			while _next_checkpoint < course.checkpoints.size():
				var checkpoint_distance := float(course.checkpoints[_next_checkpoint]["distance"])
				if checkpoint_distance <= distance or (not crosses_line and checkpoint_distance > next_distance):
					break
				_next_checkpoint += 1
			if crosses_line:
				if _lap_travel > course.total_length * 0.9 and _next_checkpoint == course.checkpoints.size():
					lap += 1
				_lap_travel = 0.0
				_next_checkpoint = 1
	index = best_index
	distance = next_distance


func point_ahead(metres: float) -> int:
	var result := index
	var travelled := 0.0
	for _step in course.points.size():
		if travelled >= metres:
			break
		travelled += float(course.points[result]["dist"])
		result = (result + 1) % course.points.size()
	return result


func checkpoint_index() -> int:
	var result := 0
	for checkpoint: Dictionary in course.checkpoints:
		if float(checkpoint["distance"]) > distance:
			break
		result = int(checkpoint["index"])
	return result
