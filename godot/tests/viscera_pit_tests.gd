## MUD runs get batched, collision-free guts/organs/blood; every other surface stays bare.
extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	var course := TrackData.build_course()
	var first := _build(course)
	var second := _build(course)
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


func _digest(pit: Node) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for child in pit.get_children():
		var multi: MultiMesh = child.multimesh
		context.update(multi.buffer.to_byte_array())
	return context.finish().hex_encode()


## Returns [instance count, triangle count] after validating shape, bounds and variety.
func _inspect(body: StaticBody3D, pit: Node3D, points: Array) -> Array:
	var count := 0
	var tris := 0
	var names := {}
	for child: MultiMeshInstance3D in pit.get_children():
		names[String(child.name)] = true
		var multi := child.multimesh
		var mesh_tris := TrackViscera.triangles(String(child.name))
		count += multi.instance_count
		tris += multi.instance_count * mesh_tris
		_check(String(body.name) + " " + String(child.name) + " stays in budget", multi.instance_count > 20
			and multi.instance_count <= 500)
		var verts: PackedVector3Array = multi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var tops: Array[float] = []
		var yaws := {}
		var scales := {}
		var inside := true
		var low := true
		var tall := 0.0
		for i in multi.instance_count:
			var xf := multi.get_instance_transform(i)
			yaws[snappedf(xf.basis.orthonormalized().get_euler().y, 0.05)] = true
			scales[snappedf(xf.basis.get_scale().x, 0.05)] = true
			var top := -INF
			var bottom := INF
			for v in verts.size():
				var w := xf * verts[v]
				top = maxf(top, w.y)
				bottom = minf(bottom, w.y)
				if i % 6 == 0:
					inside = inside and _lateral_margin(w + Vector3(0, 0.02, 0), points) > 0.0
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


## Positive when the XZ point lies within the ribbon of some centreline segment.
func _lateral_margin(point: Vector3, points: Array) -> float:
	var best := -INF
	for i in points.size():
		var a: Dictionary = points[i]
		var b: Dictionary = points[(i + 1) % points.size()]
		if absf(point.x - a["pos"].x) > 40.0 or absf(point.z - a["pos"].z) > 40.0:
			continue
		var seg: Vector3 = b["pos"] - a["pos"]
		seg.y = 0.0
		var rel: Vector3 = point - a["pos"]
		var t := rel.dot(seg) / maxf(seg.length_squared(), 0.0001)
		if t < 0.0 or t > 1.0:
			continue
		var side := Vector3(-seg.z, 0.0, seg.x).normalized()
		var half := lerpf(float(a["w"]), float(b["w"]), t) * 0.5
		best = maxf(best, half - absf(rel.dot(side)))
	return best


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)
