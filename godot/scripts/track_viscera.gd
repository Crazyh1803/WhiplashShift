## Visual-only guts, organ mounds and blood pools scattered over MUD runs.
## Three cached low-poly meshes, one MultiMesh each per run, no collision.
class_name TrackViscera
extends RefCounted

const COIL_PER_METRE := 1.1
const ORGAN_PER_METRE := 1.2
const POOL_PER_METRE := 0.5
const MAX_COILS := 500
const MAX_ORGANS := 500
const MAX_POOLS := 220
const END_MARGIN := 2.0
const EDGE_MARGIN := 1.5
const MIN_HEIGHT := 0.08
const MAX_HEIGHT := 0.24
const ROAD_LIFT := 0.02

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


static func enabled(sid: int) -> bool:
	return sid == Surfaces.Id.MUD


## Triangle count of one instance of each cached mesh, for budget checks.
static func triangles(kind: String) -> int:
	var verts: PackedVector3Array = _mesh(kind).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return verts.size() / 3


static func mesh_for(kind: String) -> ArrayMesh:
	return _mesh(kind)


## Adds a "VisceraPit" node under `parent` (the road mesh, which already carries the
## shared 0.02 m ribbon lift). Positions are sampled inside the ribbon described by `run`.
static func attach(parent: Node3D, run: Array, sid: int, index: int, run_length: float) -> Node3D:
	if not enabled(sid) or run.size() < 2 or run_length < END_MARGIN * 4.0:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + index * 7919
	var cumulative := PackedFloat32Array([0.0])
	for k in range(run.size() - 1):
		cumulative.append(cumulative[k] + float(run[k]["dist"]))
	var root := Node3D.new()
	root.name = "VisceraPit"
	var counts := {"Pools": mini(int(run_length * POOL_PER_METRE), MAX_POOLS),
		"Coils": mini(int(run_length * COIL_PER_METRE), MAX_COILS),
		"Organs": mini(int(run_length * ORGAN_PER_METRE), MAX_ORGANS)}
	for kind: String in ["Pools", "Coils", "Organs"]:
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		for _n in int(counts[kind]):
			_sample(rng, run, cumulative, run_length, sid, index, kind, transforms, colors)
		_add_batch(root, kind, transforms, colors)
	parent.add_child(root)
	return root


static func _sample(rng: RandomNumberGenerator, run: Array, cumulative: PackedFloat32Array,
		run_length: float, sid: int, index: int, kind: String,
		transforms: Array[Transform3D], colors: Array[Color]) -> void:
	# Always consume the same random draws so results never depend on rejection.
	var s := rng.randf_range(END_MARGIN, run_length - END_MARGIN)
	var cx_roll := rng.randf()
	var yaw := rng.randf() * TAU
	var size_roll := rng.randf()
	var tone := rng.randf()
	var stretch := rng.randf()
	var k := 0
	while k < run.size() - 2 and cumulative[k + 1] < s:
		k += 1
	var a: Dictionary = run[k]
	var b: Dictionary = run[k + 1]
	var t := clampf((s - cumulative[k]) / maxf(float(a["dist"]), 0.0001), 0.0, 1.0)
	var width := lerpf(float(a["w"]), float(b["w"]), t)
	var margin := EDGE_MARGIN + (1.2 if kind == "Pools" else 0.0)
	var half := width * 0.5 - margin
	if half <= 0.5:
		return
	var across := (cx_roll * 2.0 - 1.0) * half
	var cx := across / width + 0.5
	var an: Vector3 = Vector3(-a["dir"].z, 0.0, a["dir"].x) * (float(a["w"]) * 0.5)
	var bn: Vector3 = Vector3(-b["dir"].z, 0.0, b["dir"].x) * (float(b["w"]) * 0.5)
	var al: Vector3 = a["pos"] + an
	var ar: Vector3 = a["pos"] - an
	var bl: Vector3 = b["pos"] + bn
	var br: Vector3 = b["pos"] - bn
	var p := al.lerp(ar, cx).lerp(bl.lerp(br, cx), t)
	p.y += TrackRelief.height(sid, s, (cx - 0.5) * width, width, run_length, index)
	# Smaller toward both run ends and the ribbon edges, so nothing ends in a seam.
	var fade := smoothstep(END_MARGIN, TrackRelief.END_FADE + END_MARGIN, minf(s, run_length - s)) \
		* smoothstep(0.0, TrackRelief.EDGE_FADE, half - absf(across))
	if fade < 0.2:
		return
	var scale := 0.6 + fade * 0.4
	var basis := Basis(Vector3.UP, yaw)
	var color := Color.WHITE
	if kind == "Pools":
		var wide := 0.9 + size_roll * 0.9
		basis = _surface_tilt(sid, s, across, width, run_length, index, a, b) * basis \
			* Basis.from_scale(Vector3(wide * scale, 1.0, wide * scale * (0.55 + stretch * 0.5)))
		p.y += 0.014
		color = Color(0.5 + tone * 0.5, 0.45 + tone * 0.4, 0.45 + tone * 0.4)
	elif kind == "Coils":
		var big := 0.7 + size_roll * 0.6
		basis = basis * Basis.from_scale(Vector3(big * scale, (0.8 + stretch * 0.5) * (0.7 + scale * 0.3), big * scale))
		p.y -= 0.01
		color = Color(0.78 + tone * 0.22, 0.6 + tone * 0.4, 0.55 + tone * 0.35)
	else:
		var big := 0.7 + size_roll * 0.9
		basis = basis * Basis.from_scale(Vector3(big * scale, (0.7 + stretch * 0.7) * (0.7 + scale * 0.3), big * scale * (0.7 + tone * 0.5)))
		p.y -= 0.015
		color = Color(0.45 + tone * 0.55, 0.3 + tone * 0.5, 0.3 + tone * 0.5)
	transforms.append(Transform3D(basis, p))
	colors.append(color)


## Rotation taking world up onto the relief plane under a pool, from centred height gradients,
## so the lens rests flat on sloped mud instead of burying its uphill rim.
static func _surface_tilt(sid: int, s: float, across: float, width: float, run_length: float,
		index: int, a: Dictionary, b: Dictionary) -> Basis:
	var along: Vector3 = b["pos"] - a["pos"]
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return Basis.IDENTITY
	along = along.normalized()
	var across_axis := Vector3(along.z, 0.0, -along.x)
	var grade_s := (TrackRelief.height(sid, s + 1.0, across, width, run_length, index)
		- TrackRelief.height(sid, s - 1.0, across, width, run_length, index)) * 0.5
	var grade_c := (TrackRelief.height(sid, s, across + 1.0, width, run_length, index)
		- TrackRelief.height(sid, s, across - 1.0, width, run_length, index)) * 0.5
	var normal := (across_axis + Vector3.UP * grade_c).cross(along + Vector3.UP * grade_s)
	if normal.y < 0.0:
		normal = -normal
	return Basis(Quaternion(Vector3.UP, normal.normalized()))


static func _add_batch(root: Node3D, kind: String, transforms: Array[Transform3D], colors: Array[Color]) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _mesh(kind)
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		multi.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = kind
	node.multimesh = multi
	node.material_override = _material(kind)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The headless renderer stores no MultiMesh data, so tests read this CPU copy instead.
	node.set_meta("cpu_transforms", transforms)
	node.set_meta("cpu_colors", colors)
	root.add_child(node)


static func _material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind == "Pools":
		m.albedo_color = Color(0.2, 0.012, 0.02)
		m.roughness = 0.06
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.05
	elif kind == "Coils":
		m.albedo_color = Color(0.74, 0.36, 0.34)
		m.roughness = 0.22
		m.clearcoat_enabled = true
		m.clearcoat = 0.6
		m.clearcoat_roughness = 0.12
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.5
	else:
		m.albedo_color = Color(0.5, 0.075, 0.1)
		m.roughness = 0.3
		m.clearcoat_enabled = true
		m.clearcoat = 0.7
		m.clearcoat_roughness = 0.1
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.6
	_materials[kind] = m
	return m


static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	match kind:
		"Coils":
			_build_coil(verts, normals)
		"Organs":
			_build_organ(verts, normals)
		_:
			_build_pool(verts, normals)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[kind] = mesh
	return mesh


## Two overlapping looped tube turns (a prolate cycloid), crossing at different heights.
static func _build_coil(verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	var segs := 20
	var sides := 5
	var base := 0.052
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	for i in segs + 1:
		var t := float(i) / segs * TAU * 2.0
		var r := base * (1.0 + 0.18 * sin(t * 2.5))
		centres.append(Vector3(0.08 * (t - TAU) - 0.5 * sin(t), base * 1.15 + base * 0.85 * (0.5 + 0.5 * sin(t * 0.5 + 0.6)) + r * 0.2, 0.46 * (1.0 - cos(t)) - 0.46))
		radii.append(r)
	var rings: Array = []
	for i in segs + 1:
		var tangent := (centres[mini(i + 1, segs)] - centres[maxi(i - 1, 0)]).normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		var up := side.cross(tangent).normalized()
		var ring: Array[Vector3] = []
		for j in sides:
			var ang := float(j) / sides * TAU
			ring.append(side * cos(ang) + up * sin(ang))
		rings.append(ring)
	for i in segs:
		for j in sides:
			var j2 := (j + 1) % sides
			var n00: Vector3 = rings[i][j]
			var n01: Vector3 = rings[i][j2]
			var n10: Vector3 = rings[i + 1][j]
			var n11: Vector3 = rings[i + 1][j2]
			var p00 := centres[i] + n00 * radii[i]
			var p01 := centres[i] + n01 * radii[i]
			var p10 := centres[i + 1] + n10 * radii[i + 1]
			var p11 := centres[i + 1] + n11 * radii[i + 1]
			_tri(verts, normals, p00, p10, p01, n00, n10, n01)
			_tri(verts, normals, p01, p10, p11, n01, n10, n11)


## Several overlapping lumpy domes of differing size, like a heap of organs.
static func _build_organ(verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	var lobes := [[Vector3(0.0, 0.0, 0.0), 0.34, 0.17], [Vector3(0.3, 0.0, 0.12), 0.24, 0.13],
		[Vector3(-0.2, 0.0, 0.22), 0.22, 0.15], [Vector3(-0.04, 0.0, -0.28), 0.25, 0.11]]
	for lobe: Array in lobes:
		var centre: Vector3 = lobe[0]
		_dome(verts, normals, centre, float(lobe[1]), float(lobe[2]))


static func _dome(verts: PackedVector3Array, normals: PackedVector3Array, centre: Vector3, radius: float, height: float) -> void:
	var segs := 8
	var rings := 3
	for r in rings:
		var a0 := float(r) / rings * PI * 0.5
		var a1 := float(r + 1) / rings * PI * 0.5
		for s in segs:
			var u0 := float(s) / segs * TAU
			var u1 := float(s + 1) / segs * TAU
			var w0 := 1.0 + 0.12 * sin(u0 * 3.0 + radius * 20.0)
			var w1 := 1.0 + 0.12 * sin(u1 * 3.0 + radius * 20.0)
			var p00 := _dome_point(centre, radius * w0, height, a0, u0)
			var p01 := _dome_point(centre, radius * w1, height, a0, u1)
			var p10 := _dome_point(centre, radius * w0, height, a1, u0)
			var p11 := _dome_point(centre, radius * w1, height, a1, u1)
			var n00 := _dome_normal(radius, height, a0, u0)
			var n01 := _dome_normal(radius, height, a0, u1)
			var n10 := _dome_normal(radius, height, a1, u0)
			var n11 := _dome_normal(radius, height, a1, u1)
			_tri(verts, normals, p00, p10, p01, n00, n10, n01)
			if r < rings - 1:
				_tri(verts, normals, p01, p10, p11, n01, n10, n11)


static func _dome_point(centre: Vector3, radius: float, height: float, polar: float, azimuth: float) -> Vector3:
	return centre + Vector3(cos(azimuth) * cos(polar) * radius, sin(polar) * height - 0.01, sin(azimuth) * cos(polar) * radius)


static func _dome_normal(radius: float, height: float, polar: float, azimuth: float) -> Vector3:
	return Vector3(cos(azimuth) * cos(polar) / radius, sin(polar) / height, sin(azimuth) * cos(polar) / radius).normalized()


## Irregular thin lens whose rim sinks below the road, so the pool has no visible edge.
static func _build_pool(verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	var segs := 14
	var rings := 2
	for r in rings:
		for s in segs:
			var corners: Array[Vector3] = []
			for dr in 2:
				for ds in 2:
					var f := float(r + dr) / rings
					var u := float(s + ds) / segs * TAU
					var wobble := 1.0 + 0.28 * sin(u * 3.0 + 1.3) + 0.14 * sin(u * 5.0 + 0.4)
					corners.append(Vector3(cos(u) * f * wobble, 0.012 * (1.0 - f * f) - 0.02 * f * f * f, sin(u) * f * wobble))
			if r > 0:
				_tri(verts, normals, corners[0], corners[2], corners[1], Vector3.UP, Vector3.UP, Vector3.UP)
			_tri(verts, normals, corners[1], corners[2], corners[3], Vector3.UP, Vector3.UP, Vector3.UP)


## Godot's front face is clockwise, so wind outward-facing triangles accordingly.
static func _tri(verts: PackedVector3Array, normals: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var face := (c - a).cross(b - a)
	if face.dot(na + nb + nc) < 0.0:
		verts.append_array([a, c, b])
		normals.append_array([na, nc, nb])
	else:
		verts.append_array([a, b, c])
		normals.append_array([na, nb, nc])
