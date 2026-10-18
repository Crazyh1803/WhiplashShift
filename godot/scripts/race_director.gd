## Race rules shared by the driving scene and headless tests.
class_name RaceDirector
extends RefCounted

enum State { COUNTDOWN, RACING, RESULTS }

const COUNTDOWN_SECONDS := 3.0
var state: State = State.COUNTDOWN
var countdown: float = COUNTDOWN_SECONDS
var elapsed: float = 0.0
var course: CourseDefinition
var entrants: Array[Dictionary] = []
var finish_order: Array[int] = []


func setup(p_course: CourseDefinition, names: Array[String], trackers: Array[TrackProgress]) -> void:
	course = p_course
	entrants.clear()
	finish_order.clear()
	state = State.COUNTDOWN
	countdown = COUNTDOWN_SECONDS
	elapsed = 0.0
	for i in trackers.size():
		entrants.append({"name": names[i], "progress": trackers[i], "finish_time": -1.0,
			"previous_distance": trackers[i].route_distance})


func tick(delta: float) -> void:
	if state == State.RESULTS:
		return
	if state == State.COUNTDOWN:
		countdown = maxf(0.0, countdown - delta)
		if countdown <= 0.00001:
			countdown = 0.0
			state = State.RACING
		return
	elapsed += delta
	var finishers: Array[int] = []
	# Interpolate line crossings within this tick; entrant index breaks exact ties.
	for i in entrants.size():
		var entry := entrants[i]
		if float(entry["finish_time"]) >= 0.0:
			continue
		var tracker: TrackProgress = entry["progress"]
		if tracker.lap >= course.default_laps:
			var previous := float(entry["previous_distance"])
			var line := (course.default_laps + 1) * course.total_length
			var fraction := clampf((line - previous) / maxf(tracker.route_distance - previous, 0.0001), 0.0, 1.0)
			entry["finish_time"] = elapsed - delta + delta * fraction
			finishers.append(i)
		entry["previous_distance"] = tracker.route_distance
	finishers.sort_custom(func(a: int, b: int) -> bool:
		var a_time := float(entrants[a]["finish_time"])
		var b_time := float(entrants[b]["finish_time"])
		return a_time < b_time if a_time != b_time else a < b)
	finish_order.append_array(finishers)
	if not entrants.is_empty() and float(entrants[0]["finish_time"]) >= 0.0:
		state = State.RESULTS


func standings() -> Array[int]:
	var order: Array[int] = finish_order.duplicate()
	var unfinished: Array[int] = []
	for i in entrants.size():
		if not order.has(i):
			unfinished.append(i)
	unfinished.sort_custom(func(a: int, b: int) -> bool:
		var a_score := _score(a)
		var b_score := _score(b)
		return a_score > b_score if a_score != b_score else a < b)
	order.append_array(unfinished)
	return order


func _score(index: int) -> float:
	var tracker: TrackProgress = entrants[index]["progress"]
	return tracker.route_distance


func player_position() -> int:
	return standings().find(0) + 1


static func clock_text(seconds: float) -> String:
	var centiseconds := maxi(0, int(seconds * 100.0))
	return "%02d:%02d.%02d" % [centiseconds / 6000, (centiseconds / 100) % 60, centiseconds % 100]
