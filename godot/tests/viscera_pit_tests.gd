## MUD runs get batched, collision-free guts/organs/blood; every other surface stays bare.
extends Node3D

var _pass := 0
var _fail := 0
var _space: PhysicsDirectSpaceState3D
var _rendered := false
var _quads: Array = []
var _last_quad := 0


func _ready() -> void:
	var course := TrackData.build_course()
	var first := _build(course)
	var second := _build(course)
	# Static colliders enter the physics space on the first step; pool ray checks need them.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_viewport().world_3d.direct_space_state
	_rendered = DisplayServer.get_name() != "headless"
	var mud := 0
	var instances := 0
	var triangles := 0
	for body: StaticBody3D in first.get_children():
		var sid := Surfaces.id_from_key(body.get_meta("surface_type"))
		var road: MeshInstance3D = body.get_node("RoadMesh")
		var pit := road.get_node_or_null("VisceraPit")
		if sid != Surfaces.Id.MUD:
			_check(String(body.name) + " has no viscera", pit == null)
			continue
		mud += 1
		_check(String(body.name) + " has viscera pit", pit != null)
		if pit == null:
			continue
		_check(String(body.name) + " keeps mesh + collider children", body.get_child_count() == 2
			and body.get_child(0) == road and body.get_child(1) is CollisionShape3D)
		_check(String(body.name) + " keeps surface metadata", body.get_meta("surface_type") == "mud")
		_check(String(body.name) + " adds no collision", _collision_free(pit))
		var counts := _inspect(body, pit, course.points)
		instances += counts[0]
		triangles += counts[1]
		var twin: Node = second.get_node(NodePath(String(body.name))).get_node("RoadMesh/VisceraPit")
		_check(String(body.name) + " builds deterministically", _digest(pit) == _digest(twin))
	_check("course has mud runs", mud > 0)
	print("VISCERA_BUDGET: %d instances, %d decor triangles, mesh tris coil %d organ %d pool %d" % [
		instances, triangles, TrackViscera.triangles("Coils"), TrackViscera.triangles("Organs"), TrackViscera.triangles("Pools")])
	_check("cached meshes are shared", TrackViscera.mesh_for("Coils") == TrackViscera.mesh_for("Coils"))
	var flat := Node3D.new()
	add_child(flat)
	TrackBuilder.build(flat, course.points, false)
	var flat_bare := true
	for body: StaticBody3D in flat.get_children():
		flat_bare = flat_bare and body.get_node("RoadMesh").get_node_or_null("VisceraPit") == null
	_check("flat control builds are undecorated", flat_bare)
	print("VISCERA_PIT: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _build(course: CourseDefinition) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	TrackBuilder.build(root, course.points)
	return root


func _collision_free(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return false
	for child in node.get_children():
		if not _collision_free(child):
			return false
	return true


## The headless renderer returns identity transforms and an empty buffer, so hash the CPU copy.
func _digest(pit: Node) -> String:
	var floats := PackedFloat32Array()
	for child in pit.get_children():
		for xf: Transform3D in _cpu_transforms(child):
			floats.append_array([xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y,
				xf.basis.y.z, xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z])
		for color: Color in _cpu_colors(child):
			floats.append_array([color.r, color.g, color.b, color.a])
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(floats.to_byte_array())
	return context.finish().hex_encode()


func _cpu_transforms(batch: Node) -> Array:
	return batch.get_meta("cpu_transforms", [])


func _cpu_colors(batch: Node) -> Array:
	return batch.get_meta("cpu_colors", [])


## With a real renderer the MultiMesh data must match the CPU copy it was built from.
func _check_gpu_readback(label: String, batch: MultiMeshInstance3D) -> void:
	var multi := batch.multimesh
	var transforms := _cpu_transforms(batch)
	var colors := _cpu_colors(batch)
	var same := transforms.size() == multi.instance_count and colors.size() == multi.instance_count
	for i in mini(multi.instance_count, transforms.size()):
		var xf: Transform3D = transforms[i]
		same = same and multi.get_instance_transform(i).is_equal_approx(xf) \
			and multi.get_instance_color(i).is_equal_approx(colors[i])
	_check(label + " GPU readback matches CPU transforms and colours", same)


## Returns [instance count, triangle count] after validating shape, bounds and variety.
func _inspect(body: StaticBody3D, pit: Node3D, points: Array) -> Array:
	var count := 0
	var tris := 0
	var names := {}
	for child: MultiMeshInstance3D in pit.get_children():
		names[String(child.name)] = true
		var multi := child.multimesh
		var mesh_tris := TrackViscera.triangles(String(child.name))
		var transforms := _cpu_transforms(child)
		_check(String(body.name) + " " + String(child.name) + " keeps CPU transforms and colours",
			transforms.size() == multi.instance_count and _cpu_colors(child).size() == multi.instance_count)
		if _rendered:
			_check_gpu_readback(String(body.name) + " " + String(child.name), child)
		count += multi.instance_count
		tris += multi.instance_count * mesh_tris
		_check(String(body.name) + " " + String(child.name) + " stays in budget", multi.instance_count > 20
			and multi.instance_count <= 500)
		var verts: PackedVector3Array = multi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var valid_faces := true
		for triangle in range(0, verts.size(), 3):
			valid_faces = valid_faces and (verts[triangle + 1] - verts[triangle]).cross(verts[triangle + 2] - verts[triangle]).length_squared() > 0.00000001
		_check(String(child.name) + " has no degenerate mesh faces", valid_faces)
		if String(child.name) == "Pools":
			_check("blood pool mesh covers its centre", verts.has(Vector3(0, 0.012, 0)))
		var tops: Array[float] = []
		var yaws := {}
		var scales := {}
		var inside := true
		var low := true
		var tall := 0.0
		var buried := 0.0
		var centre_gap := INF
		for i in mini(multi.instance_count, transforms.size()):
			var xf: Transform3D = transforms[i]
			yaws[snappedf(xf.basis.orthonormalized().get_euler().y, 0.05)] = true
			scales[snappedf(xf.basis.get_scale().x, 0.05)] = true
			var top := -INF
			var bottom := INF
			for v in verts.size():
				var w := xf * verts[v]
				top = maxf(top, w.y)
				bottom = minf(bottom, w.y)
				if i % 6 == 0:
					inside = inside and _quad_margin(w, points) > 0.0
			if String(child.name) == "Pools" and i % 3 == 0:
				# Compare against the real collision mesh, which is the rendered road surface.
				var gaps := _pool_gaps(body, xf, verts)
				buried = minf(buried, gaps[0])
				centre_gap = minf(centre_gap, gaps[1])
			tops.append(top)
			low = low and top <= TrackRelief.MAX_HEIGHTS[Surfaces.Id.MUD] + MAX_TISSUE and bottom >= -0.04
			tall = maxf(tall, top)
		_check(String(body.name) + " " + String(child.name) + " stays low enough for tyres", low)
		_check(String(body.name) + " " + String(child.name) + " is inside ribbon", inside)
		_check(String(body.name) + " " + String(child.name) + " varies yaw and size", yaws.size() > 12 and scales.size() > 5)
		if String(child.name) != "Pools":
			_check(String(body.name) + " " + String(child.name) + " really protrudes", tall >= 0.1 and _spread(tops) > 0.01)
		else:
			_check(String(body.name) + " pools are thin blood beds", tall > 0.005 and tall < 0.08)
			_check(String(body.name) + " pools clear the road at their centres (%.3f)" % centre_gap, centre_gap > 0.012)
			_check(String(body.name) + " pool rims are not buried in sloped relief (%.3f)" % buried, buried > -0.045)
	_check(String(body.name) + " has all three batches", names.size() == 3)
	return [count, tris]


const MAX_TISSUE := 0.24


func _spread(values: Array[float]) -> float:
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


## Largest inward XZ distance from `point` to the edges of any rendered ribbon quad
## (the exact left/right/end edges TrackBuilder extrudes); positive means inside one.
## Projecting onto centreline segments misjudges the wedge-shaped gaps on curves.
func _quad_margin(point: Vector3, points: Array) -> float:
	if _quads.is_empty():
		for i in points.size():
			var a: Dictionary = points[i]
			var b: Dictionary = points[(i + 1) % points.size()]
			var an: Vector3 = Vector3(-a["dir"].z, 0.0, a["dir"].x) * (float(a["w"]) * 0.5)
			var bn: Vector3 = Vector3(-b["dir"].z, 0.0, b["dir"].x) * (float(b["w"]) * 0.5)
			var corners: Array[Vector2] = []
			for p: Vector3 in [a["pos"] + an, b["pos"] + bn, b["pos"] - bn, a["pos"] - an]:
				corners.append(Vector2(p.x, p.z))
			var area := 0.0
			for k in 4:
				area += corners[k].cross(corners[(k + 1) % 4])
			_quads.append({"corners": corners, "sign": 1.0 if area >= 0.0 else -1.0, "centre": corners[0].lerp(corners[2], 0.5)})
	var at := Vector2(point.x, point.z)
	var best := -INF
	# Neighbouring probes land in the same or adjacent quad, so start from the last hit.
	var start_quad := _last_quad
	for n in _quads.size():
		var slot := (start_quad + n) % _quads.size()
		var quad: Dictionary = _quads[slot]
		if at.distance_squared_to(quad["centre"]) > 1600.0:
			continue
		var corners: Array[Vector2] = quad["corners"]
		var margin := INF
		for k in 4:
			var edge := corners[(k + 1) % 4] - corners[k]
			margin = minf(margin, float(quad["sign"]) * edge.cross(at - corners[k]) / maxf(edge.length(), 0.0001))
		if margin > best:
			best = margin
			_last_quad = slot
		if best > 0.0:
			break
	return best


## [lowest vertex height above the collision road, centre height above it] for one pool.
func _pool_gaps(body: StaticBody3D, xf: Transform3D, verts: PackedVector3Array) -> Array:
	var lowest := INF
	var centre := INF
	var probes: Array[Vector3] = [Vector3.ZERO]
	for v in range(0, verts.size(), 7):
		probes.append(verts[v])
	for local: Vector3 in probes:
		# Pit sits under the road mesh, which is lifted 0.02 m like its collider.
		var w := xf * local + Vector3(0.0, 0.02, 0.0)
		var query := PhysicsRayQueryParameters3D.create(w + Vector3(0, 4, 0), w - Vector3(0, 4, 0))
		var hit := _space.intersect_ray(query)
		# The twin build overlaps this one exactly, so match by run name rather than identity.
		if hit.is_empty() or (hit["collider"] as Node).name != body.name:
			continue
		var gap: float = w.y - float(hit["position"].y)
		if local == Vector3.ZERO:
			# The lens crown rises 0.012 m above the instance origin.
			centre = minf(centre, gap + 0.012)
		lowest = minf(lowest, gap)
	return [minf(lowest, 0.0) if lowest < INF else 0.0, centre if centre < INF else 1.0]


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)
