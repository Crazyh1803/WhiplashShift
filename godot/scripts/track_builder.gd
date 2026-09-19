## Extrudes the authored centreline into a 3D ribbon.
##
## One StaticBody3D per surface run, each carrying a `surface_type` metadata that
## the wheel raycast reads. That is the 3D replacement for the web build's baked
## surface raster, and it gives per-wheel sampling for free.
class_name TrackBuilder
extends RefCounted

## Grey-box palette: readable, not pretty. Comedy needs legible, not photoreal.
static func _material(sid: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Surfaces.COLORS[sid]
	m.roughness = 0.95 if sid != Surfaces.Id.ICE else 0.15
	m.metallic = 0.0
	# greybox ribbon is a single-sided strip; don't let winding decide whether
	# you can see the track you are driving on
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func build(parent: Node3D, pts: Array) -> void:
	var n := pts.size()
	var i := 0
	var run_index := 0
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
		_build_run(parent, run, sid, run_index)
		run_index += 1
		i = j + 1


static func _build_run(parent: Node3D, run: Array, sid: int, index: int) -> void:
	if run.size() < 2:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	for k in range(run.size() - 1):
		var a: Dictionary = run[k]
		var b: Dictionary = run[k + 1]
		var an: Vector3 = Vector3(-a["dir"].z, 0.0, a["dir"].x) * (a["w"] * 0.5)
		var bn: Vector3 = Vector3(-b["dir"].z, 0.0, b["dir"].x) * (b["w"] * 0.5)
		var al: Vector3 = a["pos"] + an
		var ar: Vector3 = a["pos"] - an
		var bl: Vector3 = b["pos"] + bn
		var br: Vector3 = b["pos"] - bn
		# Wound for Godot's convention: the other order builds a surface a
		# downward ray passes straight through.
		verts.append_array([al, ar, bl, bl, ar, br])
		for _t in 6:
			normals.append(Vector3.UP)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var body := StaticBody3D.new()
	# unique, or add_child quietly swaps it for "@StaticBody3D@31" on collision
	body.name = "Run_%02d_%s" % [index, Surfaces.KEYS[sid]]
	body.set_meta("surface_type", Surfaces.KEYS[sid])

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(sid)
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
