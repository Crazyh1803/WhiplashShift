## Extrudes the authored centreline into a 3D ribbon.
##
## One StaticBody3D per surface run, each carrying a `surface_type` metadata that
## the wheel raycast reads. That is the 3D replacement for the web build's baked
## surface raster, and it gives per-wheel sampling for free.
class_name TrackBuilder
extends RefCounted

const RAIL_OFFSET := 0.8

## Materials share one seamless noise map; collider surface ids stay authoritative.
static func _material(sid: int) -> ShaderMaterial:
	return TrackMaterials.surface(sid)


static func build(parent: Node3D, pts: Array, relief: bool = true) -> void:
	var n := pts.size()
	var i := 0
	var run_index := 0
	var distance := 0.0
	while i < n:
		var sid: int = pts[i]["s"]
		var j := i
		while j + 1 < n and pts[j + 1]["s"] == sid:
			j += 1
		# carry one node into the next run so the seam has no gap
		var run: Array = []
		for k in range(i, mini(j + 2, n)):
			run.append(pts[k])
		if j + 1 >= n:
			run.append(pts[0])
		_build_run(parent, run, sid, run_index, distance, relief)
		for k in range(i, j + 1):
			distance += float(pts[k]["dist"])
		run_index += 1
		i = j + 1


## A single collision body follows both edges of the circuit. Keeping the whole
## barrier in one concave shape is substantially cheaper than making a static
## body for every 3.5 m centreline sample, and the metadata gives impact audio a
## stable target regardless of which triangle was hit.
static func build_guard_rails(parent: Node3D, pts: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "GuardRails"
	body.set_meta("guard_rail", true)

	var collision_verts := PackedVector3Array()
	var visual_verts := PackedVector3Array()
	var visual_normals := PackedVector3Array()
	var n := pts.size()
	for i in n:
		var a: Dictionary = pts[i]
		var b: Dictionary = pts[(i + 1) % n]
		for side: float in [-1.0, 1.0]:
			var an := Vector3(-a["dir"].z, 0.0, a["dir"].x) * side
			var bn := Vector3(-b["dir"].z, 0.0, b["dir"].x) * side
			var ac: Vector3 = a["pos"] + an * (a["w"] * 0.5 + RAIL_OFFSET)
			var bc: Vector3 = b["pos"] + bn * (b["w"] * 0.5 + RAIL_OFFSET)

			# The invisible collision panel reaches the ground, while the visible
			# steel beam is raised like a conventional roadside guard rail.
			var a0 := ac + Vector3.UP * 0.04
			var a1 := ac + Vector3.UP * 1.35
			var b0 := bc + Vector3.UP * 0.04
			var b1 := bc + Vector3.UP * 1.35
			collision_verts.append_array([a0, b0, a1, a1, b0, b1])

			var va0 := ac + Vector3.UP * 0.58
			var va1 := ac + Vector3.UP * 1.14
			var vb0 := bc + Vector3.UP * 0.58
			var vb1 := bc + Vector3.UP * 1.14
			visual_verts.append_array([va0, vb0, va1, va1, vb0, vb1])
			var face_normal := (-an).normalized()
			for _v in 6:
				visual_normals.append(face_normal)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = visual_verts
	arrays[Mesh.ARRAY_NORMAL] = visual_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a8a08e")
	material.metallic = 0.1
	material.roughness = 0.42
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "RailMesh"
	mi.mesh = mesh
	mi.material_override = material
	body.add_child(mi)

	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(collision_verts)
	concave.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.name = "RailCollision"
	cs.shape = concave
	body.add_child(cs)
	parent.add_child(body, true)
	return body


## Primitive approach boards sit beyond the rails and never affect collisions.
static func build_approach_boards(parent: Node3D, cues: CourseCues) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainWarnings"
	parent.add_child(root)
	var panel_material := StandardMaterial3D.new()
	panel_material.albedo_color = Color("121b26")
	panel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for event: Dictionary in cues.events:
		var sample := cues.sample_at(float(event["distance"]) - float(event["lead"]))
		var direction: Vector3 = sample["direction"]
		var right := Vector3(-direction.z, 0.0, direction.x)
		var sid := int(event["surface"])
		for side: float in [-1.0, 1.0]:
			var board := Node3D.new()
			board.name = "Warning_%d_%s" % [int(event["index"]), "L" if side < 0.0 else "R"]
			board.position = sample["position"] + right * side * (float(sample["width"]) * 0.5 + 5.0) + Vector3.UP * 4.2
			if not _warning_clearance(board.position, cues.course.points):
				board.free()
				continue
			board.rotation.y = atan2(-direction.x, -direction.z)
			board.set_meta("surface", sid)
			root.add_child(board)
			var panel := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(6.0, 2.4, 0.18)
			panel.mesh = box
			panel.material_override = panel_material
			board.add_child(panel)
			for x: float in [-2.4, 2.4]:
				var post := MeshInstance3D.new()
				var post_mesh := BoxMesh.new()
				post_mesh.size = Vector3(0.15, 3.0, 0.15)
				post.mesh = post_mesh
				post.material_override = panel_material
				post.position = Vector3(x, -2.7, 0.0)
				board.add_child(post)
			var text := Label3D.new()
			text.name = "WarningText"
			text.text = "%dm  %s\n%s" % [roundi(float(event["lead"])), Surfaces.NAMES[sid], CourseCues.board_advice(sid)]
			text.font_size = 48
			text.pixel_size = 0.008
			text.outline_size = 8
			text.double_sided = false
			text.modulate = Color("ffdc80") if sid in [Surfaces.Id.ICE, Surfaces.Id.OIL] else Color("e7f1ff")
			text.position.z = 0.10
			board.add_child(text)
	return root


static func _warning_clearance(position: Vector3, points: Array) -> bool:
	var flat := Vector3(position.x, 0.0, position.z)
	for i in points.size():
		var a: Vector3 = points[i]["pos"]
		var b: Vector3 = points[(i + 1) % points.size()]["pos"]
		var segment := b - a
		var t := clampf((flat - a).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		# Reserve the full panel half-width plus the rail and a small margin,
		# including against other branches of this looping course.
		if flat.distance_to(a + segment * t) < float(points[i]["w"]) * 0.5 + RAIL_OFFSET + 3.2:
			return false
	return true


static func _build_run(parent: Node3D, run: Array, sid: int, index: int, start_distance: float = 0.0, relief: bool = true) -> void:
	if run.size() < 2:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var distance := start_distance
	var run_length := 0.0
	for k in range(run.size() - 1):
		run_length += float(run[k]["dist"])

	for k in range(run.size() - 1):
		var a: Dictionary = run[k]
		var b: Dictionary = run[k + 1]
		if relief and TrackRelief.enabled(sid):
			TrackRelief.append_quad(verts, normals, uvs, uv2s, a, b, sid, distance, start_distance, run_length, index)
			distance += float(a["dist"])
			continue
		var an: Vector3 = Vector3(-a["dir"].z, 0.0, a["dir"].x) * (a["w"] * 0.5)
		var bn: Vector3 = Vector3(-b["dir"].z, 0.0, b["dir"].x) * (b["w"] * 0.5)
		var al: Vector3 = a["pos"] + an
		var ar: Vector3 = a["pos"] - an
		var bl: Vector3 = b["pos"] + bn
		var br: Vector3 = b["pos"] - bn
		# Wound for Godot's convention: the other order builds a surface a
		# downward ray passes straight through.
		verts.append_array([al, ar, bl, bl, ar, br])
		var next_distance := distance + float(a["dist"])
		uvs.append_array([Vector2(0, distance), Vector2(1, distance), Vector2(0, next_distance),
			Vector2(0, next_distance), Vector2(1, distance), Vector2(1, next_distance)])
		uv2s.append_array([Vector2(a["w"], 0), Vector2(a["w"], 0), Vector2(b["w"], 0),
			Vector2(b["w"], 0), Vector2(a["w"], 0), Vector2(b["w"], 0)])
		distance = next_distance
		for _t in 6:
			normals.append(Vector3.UP)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var body := StaticBody3D.new()
	# unique, or add_child quietly swaps it for "@StaticBody3D@31" on collision
	body.name = "Run_%02d_%s" % [index, Surfaces.KEYS[sid]]
	body.set_meta("surface_type", Surfaces.KEYS[sid])

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "RoadMesh"
	mi.material_override = TrackMaterials.surface(sid, true)
	# lift the ribbon a hair above the ground plane so they don't z-fight
	mi.position = Vector3(0.0, 0.02, 0.0)
	body.add_child(mi)

	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(verts)
	# solid from underneath too: cheap insurance against dropping through the
	# ribbon at 180 km/h
	concave.backface_collision = true
	shape.shape = concave
	shape.position = Vector3(0.0, 0.02, 0.0)
	body.add_child(shape)
	if relief:
		# Visual-only, parented below the road mesh so body children stay mesh + collider.
		TrackViscera.attach(mi, run, sid, index, run_length)

	parent.add_child(body, true)


## Flat strips of each surface plus a ramp: where a handling problem gets isolated
## when the circuit makes it ambiguous.
static func build_proving_ground(parent: Node3D, origin: Vector3) -> void:
	var strips := [
		Surfaces.Id.TARMAC, Surfaces.Id.GRAVEL, Surfaces.Id.MUD,
		Surfaces.Id.ICE, Surfaces.Id.BOULDER, Surfaces.Id.WATER,
	]
	var w := 34.0
	for k in strips.size():
		var body := StaticBody3D.new()
		body.name = "Proving_%s" % Surfaces.KEYS[strips[k]]
		body.set_meta("surface_type", Surfaces.KEYS[strips[k]])
		var box := BoxShape3D.new()
		box.size = Vector3(w, 1.0, 420.0)
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = Vector3(0.0, -0.48, 0.0)
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		mi.position = cs.position
		mi.material_override = _material(strips[k])
		body.add_child(mi)
		body.position = origin + Vector3(k * (w + 1.0), 0.0, 0.0)
		parent.add_child(body, true)

	# a launch ramp, so wheels leaving the ground is testable on purpose
	var ramp := StaticBody3D.new()
	ramp.name = "Proving_ramp"
	ramp.set_meta("surface_type", "tarmac")
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(20.0, 1.0, 26.0)
	var rcs := CollisionShape3D.new()
	rcs.shape = rbox
	ramp.add_child(rcs)
	var rmi := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = rbox.size
	rmi.mesh = rbm
	rmi.material_override = _material(Surfaces.Id.TARMAC)
	ramp.add_child(rmi)
	ramp.position = origin + Vector3(0.0, 1.0, -150.0)
	ramp.rotation = Vector3(deg_to_rad(-9.0), 0.0, 0.0)
	parent.add_child(ramp, true)
