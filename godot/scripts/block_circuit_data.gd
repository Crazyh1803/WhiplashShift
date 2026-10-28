## Season one, race 1.1: a rounded four-corner city loop, authored with TrackData's pieces.
##
## The route is built as a turtle walk: two straights are solved at runtime so the
## loop closes exactly, then the nodes are rotated so index 0 sits 110 m into the
## grid boulevard and centred on the origin.
class_name BlockCircuitData
extends RefCounted

const WIDTH := 26.0
const LINE_OFFSET := 110.0


static func build_course() -> CourseDefinition:
	return CourseDefinition.new().configure("block_circuit", "Block Circuit", "city_stacks", 3, author())


static func author() -> Array:
	var closing := _walk(0.0, 0.0)
	var end: Vector2 = closing["end"]
	var nodes: Array = _walk(end.x, -end.y)["nodes"]
	nodes.pop_back()   # last node coincides with the first
	var origin: Vector2 = nodes[0]["p"]
	var line := 0
	while line < nodes.size() and (nodes[line]["p"] as Vector2).distance_to(origin) < LINE_OFFSET:
		line += 1
	return finalize(nodes.slice(line) + nodes.slice(0, line))


## Same point format as TrackData.author(), but centred on the nodes' bounding box.
static func finalize(nodes: Array) -> Array:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for node: Dictionary in nodes:
		var p: Vector2 = node["p"]
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	var centre := (low + high) * 0.5
	var out: Array = []
	var n := nodes.size()
	for i in n:
		var here: Vector2 = nodes[i]["p"] - centre
		var nxt: Vector2 = nodes[(i + 1) % n]["p"] - centre
		var prv: Vector2 = nodes[(i - 1 + n) % n]["p"] - centre
		var tangent := (nxt - prv).normalized()
		out.append({
			"pos": Vector3(here.x, 0.0, here.y),
			"dir": Vector3(tangent.x, 0.0, tangent.y),
			"w": nodes[i]["w"],
			"s": nodes[i]["s"],
			"dist": here.distance_to(nxt),
		})
	return out


## `after_chicane` and `return_run` are the two straights that close the loop.
static func _walk(after_chicane: float, return_run: float) -> Dictionary:
	var out: Array = []
	var t := {"p": Vector2.ZERO, "h": 0.0}
	var tarmac := Surfaces.Id.TARMAC
	var rumble := Surfaces.Id.RUMBLE
	var gravel := Surfaces.Id.GRAVEL
	_run(out, t, 400.0, tarmac)             # grid boulevard
	_turn(out, t, 130.0, -90.0, tarmac)     # broad right sweeper
	_run(out, t, 140.0, tarmac)             # service straight
	_run(out, t, 48.0, rumble)
	_run(out, t, 65.0, gravel)
	_turn(out, t, 45.0, -90.0, gravel)      # tighter return bend on gravel
	_run(out, t, 50.0, gravel)
	_run(out, t, 48.0, rumble)
	_run(out, t, after_chicane, tarmac)
	_turn(out, t, 80.0, 35.0, tarmac)       # utility district chicane
	_turn(out, t, 80.0, -35.0, tarmac)
	_run(out, t, 40.0, tarmac)
	_turn(out, t, 90.0, -90.0, tarmac)
	_run(out, t, return_run, tarmac)
	_turn(out, t, 160.0, -90.0, tarmac)     # wide return onto the grid
	return {"nodes": out, "end": t["p"]}


static func _run(out: Array, t: Dictionary, length: float, sid: int) -> void:
	if length <= 0.0:
		return
	var from: Vector2 = t["p"]
	var to := from + Vector2.from_angle(t["h"]) * length
	TrackData._straight(out, from.x, from.y, to.x, to.y, WIDTH, sid)
	t["p"] = to


## Positive degrees turn left, negative turn right (in the walk's own frame).
static func _turn(out: Array, t: Dictionary, radius: float, degrees: float, sid: int) -> void:
	var heading: float = t["h"]
	var side := 1.0 if degrees > 0.0 else -1.0
	var from: Vector2 = t["p"]
	var centre := from + Vector2(-sin(heading), cos(heading)) * radius * side
	var a0 := heading - side * PI * 0.5
	var a1 := a0 + deg_to_rad(degrees)
	TrackData._arc(out, centre.x, centre.y, radius, a0, a1, WIDTH, sid)
	t["p"] = centre + Vector2.from_angle(a1) * radius
	t["h"] = heading + deg_to_rad(degrees)
