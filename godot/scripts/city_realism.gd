class_name CityRealism
extends RefCounted


static func build(parent: Node3D, input: CourseDefinition) -> Node3D:
	var course := input.geometry()
	if course.course_id != "block_circuit" or not CityRealismCatalog.available():
		return null
	var layout := CityRealismLayout.new(course)
	layout.populate()
	var buildings := layout.placements.filter(func(p: Dictionary) -> bool: return p["role"] == "building")
	var covered := {}
	for building: Dictionary in buildings:
		covered["%d/%d" % [building["quarter"], building["side"]]] = true
	if buildings.size() < 8 or covered.size() != 8:
		push_warning("Converted city has insufficient safe lots; retaining the legacy city")
		return null
	var root := Node3D.new()
	root.name = "CityRealism"
	var lights := CityRealismLighting.new()
	lights.name = "LocalLighting"
	var batches := {}
	for placement: Dictionary in layout.placements:
		var id: String = placement["id"]
		var chunk := int(placement["chunk"])
		var key := str(chunk)
		if not batches.has(key):
			batches[key] = []
		batches[key].append(placement)
		var entry: Dictionary = CityRealismCatalog.entries[id]
		for anchor: Variant in entry.get("light_anchors", []):
			if anchor is Dictionary and _vector(anchor.get("pos", anchor.get("position"))) != Vector3.INF:
				var xf: Transform3D = placement["transform"]
				var direction := _vector(anchor.get("dir", [0, -1, 0.01]))
				lights.anchors.append({"position": xf * _vector(anchor.get("pos", anchor.get("position"))), "direction": xf.basis * direction, "color": Color("ffd2a0") if id != "utility_substation" else Color("b4d3e0"), "energy": 5.0, "range": 25.0, "shadow": false})
		if id == "street_lamp" and entry.get("light_anchors", []).is_empty():
			lights.anchors.append({"position": (placement["transform"] as Transform3D) * Vector3(0, 5.5, 0), "energy": 6.0, "range": 26.0, "shadow": false})
	for key: String in batches:
		var records: Array = batches[key]
		var bounds: AABB = records[0]["bounds"]
		for record: Dictionary in records:
			bounds = bounds.merge(record["bounds"])
		_batch(root, records, false, bounds)
		var far_records := records.filter(func(p: Dictionary) -> bool: return p["role"] == "building")
		if not far_records.is_empty():
			_batch(root, far_records, true, bounds)
	_actors(root, buildings, lights)
	root.add_child(lights)
	root.set_meta("placements", layout.placements)
	root.set_meta("reserved_bounds", layout.reservations)
	root.set_meta("rejected_slots", layout.rejected)
	root.set_meta("triangle_count", layout.triangles)
	root.set_meta("quarter_triangles", layout.quarter_triangles)
	root.set_meta("triangle_budget", CityRealismLayout.GLOBAL_BUDGET)
	root.set_meta("light_count", CityRealismLighting.STREET_SLOTS + 2)
	root.set_meta("districts", CityRealismLayout.DISTRICTS)
	parent.add_child(root)
	return root


static func _batch(root: Node3D, records: Array, far: bool, bounds: AABB) -> void:
	var origin := bounds.get_center()
	var tools := {}
	for record: Dictionary in records:
		var mesh: Mesh = CityRealismCatalog.meshes[record["id"] + ("@far" if far else "")]
		var xf: Transform3D = record["transform"]
		xf.origin -= origin
		for surface in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(surface)
			var id := material.resource_name
			if not tools.has(id):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[id] = tool
			tools[id].append_from(mesh, surface, xf)
	var combined := ArrayMesh.new()
	for id: String in tools:
		tools[id].commit(combined)
		combined.surface_set_material(combined.get_surface_count() - 1, CityRealismCatalog.materials[id])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = combined
	multimesh.custom_aabb = AABB(bounds.position - origin, bounds.size)
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Chunk%d_%s" % [int(records[0]["chunk"]), "far" if far else "near"]
	instance.position = origin
	instance.multimesh = multimesh
	instance.set_meta("placements", records)
	instance.set_meta("lod", 1 if far else 0)
	instance.visibility_range_begin = 140.0 if far else 0.0
	instance.visibility_range_end = 450.0 if far else 140.0
	instance.visibility_range_begin_margin = 0.0
	instance.visibility_range_end_margin = 0.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)


static func _actors(root: Node3D, buildings: Array, lights: CityRealismLighting) -> void:
	var adapter := IndustrialMarketBenchmark.new()
	var count := 0
	for placement: Dictionary in buildings:
		if count >= 2:
			break
		if placement["id"] != "redline_shop":
			continue
		var sockets: Dictionary = CityRealismCatalog.entries["redline_shop"].get("actor_sockets", {})
		if not sockets.has("vendor") or not sockets.has("customer"):
			continue
		var group := Node3D.new()
		group.name = "ShopLife%d" % count
		group.transform = placement["transform"]
		for role: String in ["vendor", "customer"]:
			var path := IndustrialMarketBenchmark.DIRECTORY + "ramen_" + role + ".glb"
			var model := (load(path) as PackedScene).instantiate() as Node3D
			model.position = _vector(sockets[role].get("position", [0, 0.15, 0]))
			model.rotation.y = deg_to_rad(float(sockets[role].get("yaw_degrees", 0)))
			for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				adapter._prepare_materials(instance)
				instance.visibility_range_end = 60.0
			group.add_child(model)
		root.add_child(group)
		var xf: Transform3D = placement["transform"]
		lights.anchors.append({"position": xf * _vector(sockets.get("light", [0, 3.5, -1])), "direction": xf.basis * Vector3(0, -1, 0.15), "shadow": true, "energy": 9.0, "range": 12.0})
		count += 1
	adapter.free()
	root.set_meta("actor_pairs", count)


static func _vector(raw: Variant) -> Vector3:
	if not raw is Array or raw.size() != 3:
		return Vector3.INF
	for component: Variant in raw:
		if not IndustrialMarketBenchmark.is_number(component):
			return Vector3.INF
	return Vector3(raw[0], raw[1], raw[2])
