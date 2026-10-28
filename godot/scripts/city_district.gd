class_name CityDistrict
extends RefCounted

# Authored for Block Circuit's non-crossing geometry; other tracks reuse CityKit assets with their own layout.
const FRACTION := 0.25
const TRIANGLE_BUDGET := 150000
const GAP := 0.8
const BUILDINGS: Array[String] = ["shutter_workshop", "utility_midrise", "ribbed_stack"]
const PROPS: Array[String] = ["pipe_rack", "exhaust_stack", "service_cabinet", "transformer", "cargo_crate", "barrier_segment", "beacon_post", "conduit_pillar"]


static func build(parent: Node3D, input_course: CourseDefinition) -> Node3D:
	var course := input_course.geometry()
	var root := Node3D.new()
	root.name = "CityKit"
	parent.add_child(root)
	_Placer.new(course, parent).populate(root)
	return root


static func sample(course: CourseDefinition, distance: float) -> Dictionary:
	var target := clampf(distance, 0.0, course.total_length - 0.001)
	var along := 0.0
	for i in course.points.size():
		var a: Dictionary = course.points[i]
		var length := float(a["dist"])
		if along + length >= target:
			var b: Dictionary = course.points[(i + 1) % course.points.size()]
			var t := clampf((target - along) / maxf(length, 0.0001), 0.0, 1.0)
			return {"pos": (a["pos"] as Vector3).lerp(b["pos"], t), "dir": (a["dir"] as Vector3).lerp(b["dir"], t).normalized(), "w": lerpf(float(a["w"]), float(b["w"]), t), "s": target}
		along += length
	return {}


static func route_distance(course: CourseDefinition, position: Vector3) -> float:
	var flat := Vector3(position.x, 0.0, position.z)
	var best := INF
	var result := 0.0
	var along := 0.0
	for i in course.points.size():
		var a: Vector3 = course.points[i]["pos"]
		var b: Vector3 = course.points[(i + 1) % course.points.size()]["pos"]
		a.y = 0.0
		b.y = 0.0
		var delta := b - a
		var t := clampf((flat - a).dot(delta) / maxf(delta.length_squared(), 0.0001), 0.0, 1.0)
		var distance := flat.distance_squared_to(a + delta * t)
		if distance < best:
			best = distance
			result = along + float(course.points[i]["dist"]) * t
		along += float(course.points[i]["dist"])
	return result


class _Placer extends RefCounted:
	var course: CourseDefinition
	var quarter := 0.0
	var entries: Dictionary
	var obstacles: Array[AABB] = []
	var transforms: Dictionary = {}
	var distances: Dictionary = {}
	var placements: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	var triangles := 0

	func _init(p_course: CourseDefinition, legacy: Node3D) -> void:
		course = p_course
		quarter = course.total_length * CityDistrict.FRACTION
		entries = CityKit.entries()
		_collect_obstacles(legacy)

	func populate(root: Node3D) -> void:
		_place_landmark("relay_tower", [[145.0, -1.0, 12.0], [150.0, 1.0, 16.0], [175.0, -1.0, 22.0]])
		_place_landmark("exchange_hall", [[345.0, 1.0, 15.0], [325.0, 1.0, 24.0], [305.0, -1.0, 28.0]])
		_place_landmark("pump_citadel", [[455.0, -1.0, 20.0], [440.0, -1.0, 30.0], [425.0, 1.0, 30.0]])
		for station in 35:
			var s := 18.0 + 14.0 * station
			_place(CityDistrict.PROPS[station % CityDistrict.PROPS.size()], s, -1.0 if station % 2 == 0 else 1.0, 9.0)
		for station in 18:
			var s := 26.0 + 26.0 * station
			_place(CityDistrict.PROPS[(station + 3) % CityDistrict.PROPS.size()], s, 1.0 if station % 2 == 0 else -1.0, 9.0)
		for station in 11:
			var s := 38.0 + 44.0 * station
			for side: float in [-1.0, 1.0]:
				var index := (station + int(side > 0.0)) % CityDistrict.BUILDINGS.size()
				_place(CityDistrict.BUILDINGS[index], s, side, 12.0 + float(station % 3) * 2.0)
		for station in 4:
			var s := 85.0 + 110.0 * station
			for side: float in [-1.0, 1.0]:
				_place(CityDistrict.BUILDINGS[(station + 1) % CityDistrict.BUILDINGS.size()], s, side, 46.0)
		for id: String in transforms:
			_batch(root, id)
		root.set_meta("quarter_length", quarter)
		root.set_meta("placements", placements)
		root.set_meta("rejected_slots", rejected)
		root.set_meta("triangle_count", triangles)
		root.set_meta("triangle_budget", CityDistrict.TRIANGLE_BUDGET)

	func _place_landmark(id: String, slots: Array) -> void:
		for slot: Array in slots:
			if _place(id, float(slot[0]), float(slot[1]), float(slot[2])):
				return
		push_error("City district could not place landmark: " + id)

	func _place(id: String, s: float, side: float, setback: float) -> bool:
		if not entries.has(id):
			rejected.append({"asset": id, "s": s, "side": side, "reason": "unknown_asset"})
			return false
		if s <= 0.0 or s >= quarter:
			rejected.append({"asset": id, "s": s, "side": side, "reason": "out_of_quarter"})
			return false
		if CityKit.mesh(id) == null:
			rejected.append({"asset": id, "s": s, "side": side, "reason": "missing_mesh"})
			return false
		var entry: Dictionary = entries[id]
		var local := CityKit.bounds(id)
		var at := CityDistrict.sample(course, s)
		var direction: Vector3 = at["dir"]
		var normal := Vector3(-direction.z, 0.0, direction.x) * side
		var basis := Basis.looking_at(-normal, Vector3.UP)
		var offset := float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET + setback - local.position.z
		var transform := Transform3D(basis, at["pos"] + normal * offset)
		var world: AABB = transform * local
		var reason := _reject_reason(world, int(entry["tris"]))
		if not reason.is_empty():
			rejected.append({"asset": id, "s": s, "side": side, "reason": reason})
			return false
		if not transforms.has(id):
			transforms[id] = []
			distances[id] = []
		transforms[id].append(transform)
		distances[id].append(s)
		obstacles.append(_flat(world))
		triangles += int(entry["tris"])
		placements.append({"asset": id, "s": s, "side": side, "transform": transform, "bounds": world})
		return true

	func _reject_reason(world: AABB, cost: int) -> String:
		if triangles + cost > CityDistrict.TRIANGLE_BUDGET:
			return "triangle_budget"
		if CityScenery.road_clearance(world, course) < CityScenery.ROAD_CLEARANCE:
			return "road_clearance"
		if absf(world.position.x) > CityScenery.WORLD_LIMIT or absf(world.end.x) > CityScenery.WORLD_LIMIT or absf(world.position.z) > CityScenery.WORLD_LIMIT or absf(world.end.z) > CityScenery.WORLD_LIMIT:
			return "world_bounds"
		for corner in 8:
			var s := CityDistrict.route_distance(course, world.get_endpoint(corner))
			if s < 1.0 or s >= quarter:
				return "quarter_boundary"
		var footprint := _flat(world).grow(CityDistrict.GAP)
		for other: AABB in obstacles:
			if footprint.intersects(other):
				return "prop_overlap"
		return ""

	func _flat(box: AABB) -> AABB:
		return AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 1.0, box.size.z))

	func _collect_obstacles(legacy: Node3D) -> void:
		var crown := legacy.get_node_or_null("Crown") as Node3D
		if crown != null:
			obstacles.append(AABB(crown.position - Vector3(48.0, 0.0, 48.0), Vector3(96.0, 1.0, 96.0)))
		for node: Node in legacy.find_children("*", "MultiMeshInstance3D", true, false):
			var local: AABB = node.get_meta("city_local_aabb", CityScenery.UNIT_BOX)
			for transform: Transform3D in node.get_meta("city_transforms", []):
				obstacles.append(_flat(transform * local))
		for node: Node in legacy.find_children("*", "MeshInstance3D", true, false):
			var transform: Transform3D = Transform3D.IDENTITY
			var cursor: Node = node
			while cursor != legacy and cursor is Node3D:
				transform = cursor.transform * transform
				cursor = cursor.get_parent()
			obstacles.append(_flat(transform * node.get_aabb()))

	func _batch(root: Node3D, id: String) -> void:
		var mesh := CityKit.mesh(id)
		if mesh == null:
			return
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms[id].size()
		for i in multimesh.instance_count:
			multimesh.set_instance_transform(i, transforms[id][i])
		var batch := MultiMeshInstance3D.new()
		batch.name = id
		batch.multimesh = multimesh
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.set_meta("city_transforms", transforms[id])
		batch.set_meta("city_route_s", distances[id])
		batch.set_meta("city_local_aabb", CityKit.bounds(id))
		batch.set_meta("asset_id", id)
		root.add_child(batch)
