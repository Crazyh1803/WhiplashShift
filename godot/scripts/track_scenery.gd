## Code-native visual sample. Geometry is decorative; no physics bodies are added.
class_name TrackScenery
extends RefCounted

const SAMPLE_LENGTH := 720.0
const PROP_MARGIN := 3.0


static func build(parent: Node3D, course: CourseDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "TrackVisualSample"
	root.set_meta("sample_length", SAMPLE_LENGTH)
	parent.add_child(root)
	var soil := TrackMaterials.surface(Surfaces.Id.OFF)
	var steel := _material(Color("181b22"), 0.35, 0.8)
	var rust := _material(Color("a8a08e"), 0.1, 0.45)
	var concrete := _material(Color("d8d3c4"), 0.1, 0.45)
	var dark := _material(Color("050508"), 0.1, 0.95)
	var shoulder_verts := PackedVector3Array()
	var shoulder_normals := PackedVector3Array()
	var posts: Array[Transform3D] = []
	var distance := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 93217
	for i in course.points.size() - 1:
		var point: Dictionary = course.points[i]
		if distance > SAMPLE_LENGTH:
			break
		var next: Dictionary = course.points[i + 1]
		for side: float in [-1.0, 1.0]:
			var an: Vector3 = Vector3(-point["dir"].z, 0, point["dir"].x) * side
			var bn: Vector3 = Vector3(-next["dir"].z, 0, next["dir"].x) * side
			var a: Vector3 = point["pos"] + an * (float(point["w"]) * 0.5) + Vector3.UP * 0.008
			var b: Vector3 = next["pos"] + bn * (float(next["w"]) * 0.5) + Vector3.UP * 0.008
			var outer_a := a + an * 2.8
			var outer_b := b + bn * 2.8
			shoulder_verts.append_array([a, outer_a, b, b, outer_a, outer_b])
			for vertex in 6:
				shoulder_normals.append(Vector3.UP)
			if i % 3 == 0:
				var pos: Vector3 = point["pos"] + an * (float(point["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET)
				posts.append(Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.55))
			if i % 11 == 0:
				var pos: Vector3 = point["pos"] + an * (float(point["w"]) * 0.5 + rng.randf_range(9, 22))
				var prop := _prop(root, "SpineColumn", pos, 3.0, course)
				if prop != null:
					_cylinder(prop, Vector3(0, 10, 0), 0.8, 20.0, steel)
					for rib in 10:
						_box(prop, Vector3(0, 1.0 + rib * 2.0, 0), Vector3(2.8, 0.65, 2.4), concrete)
					# Opaque fixed geometry: no LOD swaps or alpha-fade silhouettes.
					if i % 22 == 0:
						for tendon in 3:
							_sphere(prop, Vector3(-0.5 + tendon * 0.5, 2.5, -1.1), Vector3(0.3, 2.4, 0.4), TrackMaterials.flesh())

		distance += float(point["dist"])
	_ribbon(root, shoulder_verts, shoulder_normals, soil)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, 1.1, 0.18)
	_instances(root, "RailPosts", posts, post_mesh, steel)
	# A service yard establishes the palette alongside the opening straight.
	var p: Dictionary = course.points[mini(30, course.points.size() - 1)]
	var side := Vector3(-p["dir"].z, 0, p["dir"].x)
	var yard := _prop(root, "ServiceYard", p["pos"] + side * 78.0, 37.0, course)
	if yard != null:
		_box(yard, Vector3(0, 0.2, 0), Vector3(56, 0.4, 40), concrete)
		_box(yard, Vector3(0, 8, 8), Vector3(42, 16, 20), steel)
		_box(yard, Vector3(0, 16.3, 8), Vector3(45, 0.6, 23), dark)
		for x: float in [-15, -5, 5, 15]:
			_box(yard, Vector3(x, 5, -2.1), Vector3(7.5, 9, 0.12), dark)
			_box(yard, Vector3(x, 11.5, -2.25), Vector3(8, 0.25, 0.18), rust)
		for x: float in [-21, 21]:
			_box(yard, Vector3(x, 8, -2.3), Vector3(0.4, 16, 0.5), rust)
		for pipe in 3:
			var conduit := _cylinder(yard, Vector3(-12 + pipe * 5, 3.0, -10), 1.7, 12, steel)
			conduit.rotation.x = PI * 0.5
			for z: float in [-15, -11, -7]:
				_box(yard, Vector3(-12 + pipe * 5, 3.0, z), Vector3(4.0, 4.0, 0.5), concrete)
			_sphere(yard, Vector3(-12 + pipe * 5, 3.0, -3.4), Vector3(1.25, 1.0, 1.5), TrackMaterials.flesh())
		var sign := Label3D.new()
		sign.text = "BYDO-GRID  //  CONDUIT 07"
		sign.font_size = 64
		sign.pixel_size = 0.025
		sign.modulate = Color("ffb703")
		sign.position = Vector3(0, 14, -2.5)
		sign.rotation.y = PI
		yard.add_child(sign)
	p = course.points[mini(85, course.points.size() - 1)]
	side = Vector3(-p["dir"].z, 0, p["dir"].x)
	var tanks := _prop(root, "StorageTanks", p["pos"] - side * 58.0, 19.0, course)
	if tanks != null:
		for x: float in [-9, 9]:
			_cylinder(tanks, Vector3(x, 6, 0), 6, 12, steel)
			_cylinder(tanks, Vector3(x, 12.25, 0), 6.3, 0.5, rust)
			_cylinder(tanks, Vector3(x, 0.5, 0), 6.5, 1, concrete)
			_box(tanks, Vector3(x, 6, -6.1), Vector3(0.22, 12, 0.22), dark)
	p = course.points[mini(155, course.points.size() - 1)]
	side = Vector3(-p["dir"].z, 0, p["dir"].x)
	var plant := _prop(root, "CornerLandmark", p["pos"] - side * 70.0, 21.0, course)
	if plant != null:
		_box(plant, Vector3(0, 3, 0), Vector3(28, 6, 22), concrete)
		for x: float in [-8, 8]:
			_cylinder(plant, Vector3(x, 19, 0), 2.8, 32, rust)
			_cylinder(plant, Vector3(x, 29, 0), 2.85, 4.0, concrete)
			_cylinder(plant, Vector3(x, 35.1, 0), 3.1, 0.4, dark)
			for rib in 12:
				_box(plant, Vector3(x, 7.0 + rib * 2.4, 0), Vector3(7.4, 0.8, 6.8), concrete)
	# Distant low-detail landforms; conservative radii keep them off all branches.
	for data: Array in [[Vector3(10, 0, -660), Vector3(150, 55, 95)],
			[Vector3(510, 0, -450), Vector3(135, 75, 100)],
			[Vector3(560, 0, 170), Vector3(120, 50, 110)]]:
		var hill := _prop(root, "DistantRidge", data[0], maxf(data[1].x, data[1].z), course)
		if hill != null:
			_cylinder(hill, Vector3(0, 35, 0), 5.0, 70.0, steel)
			var uplight := SpotLight3D.new()
			uplight.position = Vector3(0, 1, -14)
			uplight.rotation_degrees = Vector3(65.0, 180.0, 0)
			uplight.light_color = Color("ffb703")
			uplight.light_energy = 12.0
			uplight.spot_range = 90.0
			uplight.spot_angle = 35.0
			hill.add_child(uplight)
			for rib in 16:
				_box(hill, Vector3(0, 4.0 + rib * 4.0, 0), Vector3(15, 1.5, 12), concrete)
	return root


static func clear_of_course(pos: Vector3, radius: float, course: CourseDefinition) -> bool:
	var flat := Vector3(pos.x, 0, pos.z)
	# Reserve the separate proving-ground lanes, including their ramp approach.
	if flat.x + radius > -642 and flat.x - radius < -420 and absf(flat.z) < 230 + radius:
		return false
	for i in course.points.size():
		var a: Dictionary = course.points[i]
		var b: Dictionary = course.points[(i + 1) % course.points.size()]
		var nearest := Geometry3D.get_closest_point_to_segment(flat, a["pos"], b["pos"])
		if nearest.distance_to(flat) < maxf(float(a["w"]), float(b["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET + PROP_MARGIN + radius:
			return false
	return true


static func _prop(root: Node3D, label: String, pos: Vector3, radius: float, course: CourseDefinition) -> Node3D:
	if not clear_of_course(pos, radius, course):
		return null
	var prop := Node3D.new()
	prop.name = label
	prop.position = pos
	prop.set_meta("clearance_radius", radius)
	root.add_child(prop, true)
	return prop


static func _ribbon(root: Node3D, verts: PackedVector3Array, normals: PackedVector3Array, material: Material) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = "SampleShoulders"
	visual.mesh = mesh
	visual.material_override = material
	root.add_child(visual)


static func _instances(root: Node3D, label: String, transforms: Array[Transform3D], mesh: Mesh, material: Material) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for i in transforms.size():
		batch.set_instance_transform(i, transforms[i])
	var visual := MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = batch
	visual.material_override = material
	root.add_child(visual)


static func _box(root: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(root, pos, mesh, material)


static func _cylinder(root: Node3D, pos: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	return _mesh(root, pos, mesh, material)


static func _sphere(root: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var visual := _mesh(root, pos, mesh, material)
	visual.scale = size
	return visual


static func _mesh(root: Node3D, pos: Vector3, mesh: Mesh, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.position = pos
	visual.mesh = mesh
	visual.material_override = material
	root.add_child(visual)
	return visual


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


## Full-loop guidance is independent of the bounded scenery sample.
static func build_guidance(parent: Node3D, course: CourseDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "BydoGuidance"
	parent.add_child(root)
	var colors := [Color("00f0ff"), Color("ffb703")]
	var materials: Array[StandardMaterial3D] = []
	var batches: Array = [[], []]
	for color: Color in colors:
		var material := _material(color, 0.0, 0.3)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 5.0
		materials.append(material)
	var distance := 0.0
	var next_beacon := 0.0
	var station := 0
	for point: Dictionary in course.points:
		if distance >= next_beacon:
			for side: float in [-1.0, 1.0]:
				var color_index := station % 2
				var normal := Vector3(-point["dir"].z, 0, point["dir"].x) * side
				var pos: Vector3 = point["pos"] + normal * (float(point["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET) + Vector3.UP * 1.65
				batches[color_index].append(Transform3D(Basis.IDENTITY, pos))
				var light := OmniLight3D.new()
				light.position = pos
				light.light_color = colors[color_index]
				light.light_energy = 6.0
				light.omni_range = 27.0
				light.omni_attenuation = 1.2
				light.distance_fade_enabled = true
				light.distance_fade_begin = 95.0
				light.distance_fade_length = 25.0
				# Tiny beads use unshadowed local pools; player cones cast shadows.
				root.add_child(light)
			station += 1
			next_beacon = distance + 18.0
		distance += float(point["dist"])
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 12
	sphere.rings = 6
	for index in 2:
		var transforms: Array[Transform3D] = []
		transforms.assign(batches[index])
		_instances(root, "CyanBeads" if index == 0 else "AmberBeads", transforms, sphere, materials[index])
	return root


## Large deposits beyond the rails make terrain changes legible before entry.
static func build_deposits(parent: Node3D, course: CourseDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainDeposits"
	parent.add_child(root)
	var bone := _material(Color("a8a08e"), 0.1, 0.58)
	var transforms: Dictionary = {}
	for sid in [Surfaces.Id.GRAVEL, Surfaces.Id.MUD, Surfaces.Id.BOULDER, Surfaces.Id.WATER]:
		transforms[sid] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 70193
	for i in course.points.size():
		var point: Dictionary = course.points[i]
		var sid := int(point["s"])
		if not transforms.has(sid):
			continue
		var entry := int(course.points[posmod(i - 1, course.points.size())]["s"]) != sid
		if not entry and i % 5 != 0:
			continue
		for side: float in [-1.0, 1.0]:
			var normal := Vector3(-point["dir"].z, 0, point["dir"].x) * side
			var radius := 2.7
			var pos: Vector3 = point["pos"] + normal * (float(point["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET + PROP_MARGIN + radius + 0.2)
			if not clear_of_course(pos, radius, course):
				continue
			var tall := 1.35 if entry else rng.randf_range(0.65, 1.05)
			var basis := Basis(Vector3.UP, atan2(point["dir"].x, point["dir"].z) + rng.randf_range(-0.35, 0.35))
			basis = basis.scaled(Vector3(1.4, tall, 2.0))
			transforms[sid].append(Transform3D(basis, pos + Vector3.UP * tall * 0.65))
	var names := {Surfaces.Id.GRAVEL: "ChitinHeaps", Surfaces.Id.MUD: "TendonBanks",
		Surfaces.Id.BOULDER: "ArmorOutcrops", Surfaces.Id.WATER: "EffluentBanks"}
	for sid: int in transforms:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 6 if sid != Surfaces.Id.MUD else 12
		mesh.rings = 3 if sid != Surfaces.Id.MUD else 6
		var batch: Array[Transform3D] = []
		batch.assign(transforms[sid])
		var material: Material = TrackMaterials.flesh() if sid == Surfaces.Id.MUD else bone
		if sid == Surfaces.Id.WATER:
			material = _material(Color("3f5550"), 0.0, 0.7)
		_instances(root, names[sid], batch, mesh, material)
		var visual: MultiMeshInstance3D = root.get_child(-1)
		visual.set_meta("clearance_radius", 2.7)
	return root
