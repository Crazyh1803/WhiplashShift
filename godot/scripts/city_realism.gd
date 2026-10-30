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
				var direction := _vector(anchor.get("direction", anchor.get("dir", [0, -1, 0.01])))
				if direction == Vector3.INF or direction.is_zero_approx():
					direction = Vector3(0, -1, 0.01)
				lights.anchors.append({"position": xf * _vector(anchor.get("pos", anchor.get("position"))), "direction": xf.basis * direction, "color": Color("ffd2a0") if id != "utility_substation" else Color("b4d3e0"), "energy": minf(4.0, float(anchor.get("energy", 1.0)) * 2.0), "range": maxf(8.0, float(anchor.get("range_m", 16.0))), "shadow": false})
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
	root.set_meta("ground_fabric", layout.ground_enabled)
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
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.visibility_range_begin_margin = 10.0 if far else 0.0
	instance.visibility_range_end_margin = 10.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)


static func _actors(root: Node3D, buildings: Array, lights: CityRealismLighting) -> void:
	var count := 0
	for placement: Dictionary in buildings:
		if count >= 2:
			break
		if placement["id"] != "redline_shop":
			continue
		var sockets: Variant = CityRealismCatalog.entries["redline_shop"].get("actor_sockets", {})
		if not sockets is Dictionary or not sockets.has("vendor") or not sockets.has("customer"):
			continue
		var models := _actor_models(sockets)
		if models.size() != 2:
			continue
		var group := Node3D.new()
		group.name = "ShopLife%d" % count
		group.transform = placement["transform"]
		for role: String in ["vendor", "customer"]:
			var model: Node3D = models[role]
			model.position = _vector(sockets[role].get("position", [0, 0.15, 0]))
			model.rotation.y = deg_to_rad(float(sockets[role].get("yaw_degrees", 0)))
			for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				IndustrialMarketBenchmark.prepare_materials(instance)
				instance.visibility_range_end = 60.0
			group.add_child(model)
		root.add_child(group)
		var xf: Transform3D = placement["transform"]
		var anchor: Dictionary = sockets["light"]
		lights.anchors.append({"position": xf * _vector(anchor["position"]), "direction": xf.basis * _vector(anchor["direction"]), "shadow": true, "energy": 5.0, "range": 10.0})
		count += 1
	root.set_meta("actor_pairs", count)


static func _actor_models(sockets: Dictionary) -> Dictionary:
	var models := {}
	for role: String in ["vendor", "customer"]:
		var path := IndustrialMarketBenchmark.DIRECTORY + "ramen_" + role + ".glb"
		var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
		var model := packed.instantiate() as Node3D if packed != null else null
		if model == null or not sockets.get(role) is Dictionary or _vector(sockets[role].get("position")) == Vector3.INF or not IndustrialMarketBenchmark.is_number(sockets[role].get("yaw_degrees")):
			if model != null:
				model.free()
			for previous: Node3D in models.values():
				previous.free()
			push_warning("Skipping shop actors: missing imported actor or invalid socket")
			return {}
		models[role] = model
	var light: Variant = sockets.get("light")
	if not light is Dictionary or _vector(light.get("position")) == Vector3.INF or _vector(light.get("direction")) == Vector3.INF:
		for model: Node3D in models.values():
			model.free()
		return {}
	return models


static func _vector(raw: Variant) -> Vector3:
	if not raw is Array or raw.size() != 3:
		return Vector3.INF
	for component: Variant in raw:
		if not IndustrialMarketBenchmark.is_number(component):
			return Vector3.INF
	return Vector3(raw[0], raw[1], raw[2])
