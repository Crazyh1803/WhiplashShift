## Deterministic roadside placements: one detailed skyscraper per quarter (two types), boarded hosts, four camps, burning barrels.
## Every new footprint (tower body, camp, barrel effect volume) is tested against the road clearance, the realism solids, the district landmarks, the crown
## and everything placed before it, with retries over s, side and setback. Overlays (landmark details, boards) deliberately overlap only their own host.
class_name CityRoadsideLayout
extends RefCounted

const TOWER_SETBACKS: Array[float] = [9.5, 11.0, 13.0, 16.0, 20.0, 25.0, 31.0, 38.0]
const CAMP_SETBACKS: Array[float] = [8.0, 9.5, 11.0, 13.0, 16.0, 20.0, 26.0]
const BARREL_SETBACKS: Array[float] = [6.4, 7.5, 9.0, 11.0, 14.0, 18.0]
const SEARCH_STEP := 4.0
const GAP := 1.0
const CAMP_CLEARANCE := 6.0
const BARREL_CLEARANCE := 4.5
## The volume a burning barrel may touch: its warm ground pool and the bounded smoke column.
const EFFECT_RADIUS := 2.0
const EFFECT_HEIGHT := 5.8
const TOWERS_PER_QUARTER := 1
const BOARD_HOSTS_PER_QUARTER := 2
const SEPARATE_BARRELS_PER_QUARTER := 1

var course: CourseDefinition
var quarter_length := 0.0
var obstacles: Array[AABB] = []
var towers: Array[Dictionary] = []
var camps: Array[Dictionary] = []
var barrels: Array[Dictionary] = []
var boards: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var reservations: Array[AABB] = []
var rejected: Dictionary = {}
var _hosts: Array[Dictionary] = []
var _attempts := 0


func _init(p_course: CourseDefinition, realism_placements: Array, reserved: Array[AABB], landmark_placements: Array, extra: Array[AABB] = []) -> void:
	course = p_course.geometry()
	quarter_length = course.total_length / 4.0
	for box in reserved:
		obstacles.append(_flat(box))
	for placement: Dictionary in landmark_placements:
		obstacles.append(_flat(placement["bounds"]).grow(GAP))
	for box in extra:
		obstacles.append(_flat(box))
	for placement: Dictionary in realism_placements:
		if placement["role"] == "building":
			_hosts.append(placement)


func populate(landmark_batches: Array = []) -> void:
	if CityRoadsideCatalog.has_group("landmarks"):
		for placement: Dictionary in landmark_batches:
			var id := String(placement["asset"])
			if id in CityRoadsideCatalog.LANDMARKS:
				landmarks.append({"kind": "landmark", "id": id + "_detail", "asset": id, "s": placement["s"], "side": placement["side"], "transform": placement["transform"],
						"bounds": (placement["transform"] as Transform3D) * CityRoadsideCatalog.bounds(id + "_detail"), "host_bounds": placement["bounds"]})
	if CityRoadsideCatalog.has_group("towers"):
		for q in 4:
			for k in TOWERS_PER_QUARTER:
				_place_tower(q, (q + k) % 2)
	if CityRoadsideCatalog.has_group("camps"):
		for q in 4:
			_place_camp(q)
	if CityRoadsideCatalog.has_group("boards"):
		for q in 4:
			_pick_hosts(q)
	if CityRoadsideCatalog.has_group("barrels"):
		for camp in camps:
			_place_camp_barrel(camp)
		for q in 4:
			for k in SEPARATE_BARRELS_PER_QUARTER:
				_place_free_barrel(q, k)


# ------------------------------------------------------------------------------------------------ towers
func _place_tower(q: int, kind: int) -> void:
	var id := CityRoadsideCatalog.TOWERS[kind]
	var box := CityRoadsideCatalog.bounds(id)
	var preferred := 1.0 if (q + kind) % 2 == 0 else -1.0
	for setback in TOWER_SETBACKS:
		for s in _centre_out(q, box.size.x * 0.5 + 6.0):
			for side: float in [preferred, -preferred]:
				var xf := _transform(s, side, setback - box.position.z)
				if not _straight(s, box.size.x):
					_count("tower_curve")
					continue
				var world := xf * box
				var reason := _blocked(world, CityScenery.ROAD_CLEARANCE, GAP)
				if reason.is_empty():
					_add_tower(id, q, s, side, setback, xf, world)
					return
				_count("tower_" + reason)
	push_warning("Roadside could not place a skyscraper in quarter %d" % q)


func _add_tower(id: String, q: int, s: float, side: float, setback: float, xf: Transform3D, world: AABB) -> void:
	towers.append({"kind": "tower", "id": id, "lod1": id + "_lod1", "quarter": q, "s": s, "side": side, "setback": setback, "transform": xf, "bounds": world, "flat": _flat(world)})
	_reserve(world, 0.3)


# ------------------------------------------------------------------------------------------------ camps and barrels
func _place_camp(q: int) -> void:
	var id := CityRoadsideCatalog.CAMPS[q % 4]
	var box := CityRoadsideCatalog.bounds(id)
	var preferred := -1.0 if q % 2 == 0 else 1.0
	for setback in CAMP_SETBACKS:
		for s in _centre_out(q, box.size.x * 0.5 + 8.0):
			for side: float in [preferred, -preferred]:
				if not _straight(s, box.size.x + 4.0):
					continue
				var xf := _transform(s, side, setback - box.position.z)
				var world := xf * box
				if _blocked(world, CAMP_CLEARANCE, GAP).is_empty():
					camps.append({"kind": "camp", "id": id, "quarter": q, "s": s, "side": side, "setback": setback, "transform": xf, "bounds": world, "flat": _flat(world), "reserved": _flat(world).grow(0.3)})
					_reserve(world, 0.3)
					return
				_count("camp_blocked")
	push_warning("Roadside could not place camp %s" % id)


func _place_camp_barrel(camp: Dictionary) -> void:
	var box := CityRoadsideCatalog.bounds(camp["id"])
	var xf: Transform3D = camp["transform"]
	var variant := CityRoadsideCatalog.BARRELS[camp["quarter"] % 2]
	var own: AABB = camp["reserved"]
	# beside the camp, near its street edge: try the right then the left flank, then further out
	for dx in [1.4, 2.0, 3.0]:
		for side_x in [1.0, -1.0]:
			var local_x: float = (box.end.x + dx) if side_x > 0.0 else (box.position.x - dx)
			var origin: Vector3 = xf * Vector3(local_x, 0.0, box.position.z + 0.9)
			if _try_barrel(variant, origin, xf.basis, camp["quarter"], float(camp["s"]), float(camp["side"]), own, int(camp["quarter"])):
				barrels[-1]["camp"] = camp["id"]
				return
	push_warning("Roadside could not place the barrel for %s" % camp["id"])


func _place_free_barrel(q: int, k: int) -> void:
	var variant := CityRoadsideCatalog.BARRELS[(q + 1) % 2]
	var preferred := 1.0 if q % 2 == 0 else -1.0
	var taken: Array[float] = []
	for camp in camps:
		if camp["quarter"] == q:
			taken.append(camp["s"])
	for setback in BARREL_SETBACKS:
		for s in _centre_out(q, 14.0, 0.5 + 0.17 * k):
			if taken.any(func(t: float) -> bool: return absf(t - s) < 30.0):
				continue
			for side: float in [preferred, -preferred]:
				var xf := _transform(s, side, setback)
				if _try_barrel(variant, xf.origin, xf.basis, q, s, side, AABB(), -1):
					return
	push_warning("Roadside could not place a free barrel in quarter %d" % q)


func _try_barrel(variant: String, origin: Vector3, basis: Basis, q: int, s: float, side: float, own: AABB, camp_quarter: int) -> bool:
	var effect := AABB(origin + Vector3(-EFFECT_RADIUS, 0.0, -EFFECT_RADIUS), Vector3(EFFECT_RADIUS * 2.0, EFFECT_HEIGHT, EFFECT_RADIUS * 2.0))
	var reason := _blocked(effect, BARREL_CLEARANCE, 0.0, own)
	if not reason.is_empty():
		_count("barrel_" + reason)
		return false
	var xf := Transform3D(basis, origin)
	var body := xf * CityRoadsideCatalog.bounds(variant)
	var anchor := CityRoadsideCatalog.fire_anchor(variant)
	var base: Array = anchor.get("base", [0.0, 0.7, 0.0])
	barrels.append({"kind": "barrel", "id": variant, "quarter": q, "s": s, "side": side, "transform": xf, "bounds": body, "effect": effect, "flat": _flat(effect),
			"coal_height": float(base[1]), "camp": ""})
	_reserve(effect, 0.0)
	return true


# ------------------------------------------------------------------------------------------------ boards
func _pick_hosts(q: int) -> void:
	var usable: Array[Dictionary] = []
	for placement in _hosts:
		if placement["quarter"] == q and placement["id"] in CityRoadsideCatalog.BOARD_FAMILIES and CityRoadsideCatalog.meshes.has("boards_" + String(placement["id"])):
			if (CityRoadsideCatalog.costs["boards_" + String(placement["id"])]["tris"] as int) >= 1500:
				usable.append(placement)
	usable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]) or (float(a["s"]) == float(b["s"]) and int(a["side"]) < int(b["side"])))
	if usable.is_empty():
		push_warning("Roadside found no boardable frontage in quarter %d" % q)
		return
	var chosen: Array[Dictionary] = []
	var seen_families := {}
	var stride := maxi(1, usable.size() / (BOARD_HOSTS_PER_QUARTER + 1))
	for pass_index in 2:
		for i in usable.size():
			var candidate: Dictionary = usable[(stride * (chosen.size() + 1) + i) % usable.size()]
			if chosen.size() >= BOARD_HOSTS_PER_QUARTER:
				break
			if chosen.has(candidate) or (pass_index == 0 and seen_families.has(candidate["id"])):
				continue
			chosen.append(candidate)
			seen_families[candidate["id"]] = true
	for host in chosen:
		var id := "boards_" + String(host["id"])
		boards.append({"kind": "boards", "id": id, "host": host["id"], "quarter": q, "s": host["s"], "side": host["side"], "transform": host["transform"],
				"host_bounds": host["bounds"], "bounds": (host["transform"] as Transform3D) * CityRoadsideCatalog.bounds(id)})


# ------------------------------------------------------------------------------------------------ helpers
func _blocked(world: AABB, clearance: float, gap: float, ignore: AABB = AABB()) -> String:
	if absf(world.position.x) > CityScenery.WORLD_LIMIT or absf(world.end.x) > CityScenery.WORLD_LIMIT or absf(world.position.z) > CityScenery.WORLD_LIMIT or absf(world.end.z) > CityScenery.WORLD_LIMIT:
		return "world"
	if CityScenery.road_clearance(world, course) < clearance:
		return "road"
	var flat := _flat(world).grow(gap)
	for other in obstacles:
		if ignore.size != Vector3.ZERO and other == ignore:
			continue
		if flat.intersects(other):
			return "overlap"
	return ""


func _reserve(world: AABB, grow: float) -> void:
	var flat := _flat(world).grow(grow)
	obstacles.append(flat)
	reservations.append(flat)


func _transform(s: float, side: float, lateral_setback: float) -> Transform3D:
	var at := CityDistrict.sample(course, s)
	var direction: Vector3 = at["dir"]
	var normal := Vector3(-direction.z, 0.0, direction.x) * side
	var edge := float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	return Transform3D(Basis.looking_at(-normal, Vector3.UP), (at["pos"] as Vector3) + normal * (edge + lateral_setback))


func _straight(s: float, width: float) -> bool:
	var from := CityDistrict.sample(course, maxf(0.0, s - width * 0.5))
	var to := CityDistrict.sample(course, minf(course.total_length - 0.001, s + width * 0.5))
	return (from["dir"] as Vector3).angle_to(to["dir"]) < deg_to_rad(6.0)


## Distances along the route inside quarter q, nearest the quarter's chosen fraction first, alternating forward and back.
func _centre_out(q: int, margin: float, fraction: float = 0.5) -> Array[float]:
	var lo := quarter_length * q + margin
	var hi := quarter_length * (q + 1) - margin
	var centre := quarter_length * (q + fraction)
	var result: Array[float] = []
	var offset := 0.0
	while centre - offset >= lo or centre + offset <= hi:
		if centre + offset <= hi:
			result.append(centre + offset)
		if offset > 0.0 and centre - offset >= lo:
			result.append(centre - offset)
		offset += SEARCH_STEP
	return result


func _flat(box: AABB) -> AABB:
	return AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 1.0, box.size.z))


func _count(reason: String) -> void:
	rejected[reason] = int(rejected.get(reason, 0)) + 1
