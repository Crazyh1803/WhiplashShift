class_name CityStreetBlock
extends RefCounted

const STREET_DIRECTORY := "res://assets/city/streets/"
const STREET_IDS: Array[String] = ["sidewalk_panel", "curb_segment", "drain_cover", "street_lamp", "bollard", "bench_planter", "refuse_station", "alley_conduit"]
const SLOTS := [
	{"id": "habitation_workshop", "s": 45.0, "side": -1.0},
	{"id": "market_habitat", "s": 105.0, "side": 1.0},
	{"id": "service_tenement", "s": 165.0, "side": -1.0},
	{"id": "freight_depot", "s": 225.0, "side": 1.0},
]
const START := 6.0
const END := 282.0
const ALLEYS: Array[float] = [75.0, 189.0]
const TRIANGLE_BUDGET := 190000
const MAX_LIGHTS := 8
const INFILL := [
	[15.0, -1.0, "shutter_workshop"], [117.0, -1.0, "shutter_workshop"],
	[249.0, -1.0, "shutter_workshop"], [45.0, 1.0, "shutter_workshop"],
	[159.0, 1.0, "shutter_workshop"], [270.0, 1.0, "ribbed_stack"],
	[93.0, -1.0, "ribbed_stack"],
]
const GROUND_SHADER := preload("res://shaders/city_ground.gdshader")
static var _catalog: Dictionary = {}
static var _meshes: Dictionary = {}


static func build(parent: Node3D, input_course: CourseDefinition) -> Node3D:
	var course := input_course.geometry()
	if course.course_id != "block_circuit" or not _load_assets():
		return null
	var root := Node3D.new()
	root.name = "CityStreetBlock"
	var builder := _Builder.new(course)
	if not builder.populate(root):
		root.free()
		push_warning("Street block failed layout checks; using the existing City district")
		return null
	parent.add_child(root)
	return root


static func _load_assets() -> bool:
	if not _meshes.is_empty():
		return true
	var catalog := {}
	for path: String in [STREET_DIRECTORY + "street_kit_manifest.json", "res://assets/city/candidates/neighborhood/neighborhood_manifest.json", "res://assets/city/candidates/habitation_workshop_manifest.json"]:
		if not FileAccess.file_exists(path):
			return false
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or data.get("version") != 1 or not data.get("assets") is Array:
			return false
		for raw: Variant in data["assets"]:
			if not raw is Dictionary or not raw.get("id") is String:
				return false
			catalog[raw["id"]] = raw
	var ids: Array[String] = STREET_IDS.duplicate()
	for slot: Dictionary in SLOTS:
		ids.append(slot["id"])
	var meshes := {}
	for id: String in ids:
		if not catalog.has(id):
			return false
		var directory := STREET_DIRECTORY if id in STREET_IDS else "res://assets/city/candidates/neighborhood/"
		if id == "habitation_workshop":
			directory = "res://assets/city/candidates/"
		var packed := load(directory + id + ".glb") as PackedScene
		if packed == null:
			return false
		var model := packed.instantiate()
		var found: Array[Dictionary] = []
		CityKit.collect_static_meshes(model, Transform3D.IDENTITY, found)
		if found.size() != 1:
			model.free()
			return false
		var source: Mesh = found[0]["mesh"]
		var transform: Transform3D = found[0]["transform"]
		var mesh := ArrayMesh.new()
		for surface in source.get_surface_count():
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.append_from(source, surface, transform)
			tool.commit(mesh)
			var original := source.surface_get_material(surface) as BaseMaterial3D
			if original == null:
				model.free()
				return false
			var material := original.duplicate() as BaseMaterial3D
			material.vertex_color_use_as_albedo = true
			# A small material fill keeps worn forms readable in the sunless city.
			if not material.emission_enabled:
				material.emission_enabled = true
				material.emission = material.albedo_color
				material.emission_energy_multiplier = 0.12
			mesh.surface_set_material(surface, material)
		model.free()
		meshes[id] = mesh
	for id: String in ["shutter_workshop", "ribbed_stack"]:
		var mesh := CityKit.mesh(id)
		if mesh == null:
			return false
		meshes[id] = mesh
		catalog[id] = CityKit.entries()[id]
	_catalog = catalog
	_meshes = meshes
	return true


class _Builder extends RefCounted:
	var course: CourseDefinition
	var placements: Array[Dictionary] = []
	var solid_boxes: Array[AABB] = []
	var transforms: Dictionary = {}
	var mesh_sources: Dictionary = {}
	var triangles := 0
	var lights := 0
	var failed := false
	var reservations: Array[AABB] = []
	var rejected: Array[Dictionary] = []

	func _init(p_course: CourseDefinition) -> void:
		course = p_course

	func populate(root: Node3D) -> bool:
		for slot: Dictionary in CityStreetBlock.SLOTS:
			var id: String = slot["id"]
			var local: AABB = CityStreetBlock._meshes[id].get_aabb()
			var at := CityDistrict.sample(course, float(slot["s"]))
			var edge := float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
			_place(id, _xf(float(slot["s"]), float(slot["side"]), edge + 12.0 - local.position.z), "building")
		for side: float in [-1.0, 1.0]:
			_ground(side)
			_frontage(root, side)
			_service_yards(side)
		for slot: Array in CityStreetBlock.INFILL:
			var id: String = slot[2]
			var local: AABB = CityStreetBlock._meshes[id].get_aabb()
			_place(id, _xf(float(slot[0]), float(slot[1]), _edge() + 13.0 - local.position.z), "building", false)
		if failed or triangles > CityStreetBlock.TRIANGLE_BUDGET:
			return false
		for id: String in transforms:
			_batch(root, id)
		root.set_meta("placements", placements)
		root.set_meta("reserved_bounds", reservations)
		root.set_meta("triangle_count", triangles)
		root.set_meta("triangle_budget", CityStreetBlock.TRIANGLE_BUDGET)
		root.set_meta("light_count", lights)
		root.set_meta("alleys", CityStreetBlock.ALLEYS)
		root.set_meta("rejected_slots", rejected)
		return true

	func _xf(s: float, side: float, lateral: float, height: float = 0.0) -> Transform3D:
		var at := CityDistrict.sample(course, s)
		var d: Vector3 = at["dir"]
		var normal := Vector3(-d.z, 0.0, d.x) * side
		return Transform3D(Basis.looking_at(-normal, Vector3.UP), at["pos"] + normal * lateral + Vector3.UP * height)

	func _edge() -> float:
		return float(course.points[0]["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET

	func _near_alley(s: float, margin: float) -> bool:
		for alley: float in CityStreetBlock.ALLEYS:
			if absf(s - alley) < 4.5 + margin:
				return true
		return false

	func _place(id: String, transform: Transform3D, kind: String, required: bool = true) -> bool:
		var mesh: Mesh = CityStreetBlock._meshes[id]
		var box: AABB = transform * mesh.get_aabb()
		var solid := kind in ["building", "furniture"]
		var cost := int(CityStreetBlock._catalog[id]["tris"])
		var reason := "road_clearance" if CityScenery.road_clearance(box, course) < CityScenery.ROAD_CLEARANCE else ""
		if solid:
			for previous: AABB in solid_boxes:
				if _flat(box).grow(0.2).intersects(_flat(previous)):
					reason = "solid_overlap"
		if triangles + cost > CityStreetBlock.TRIANGLE_BUDGET:
			reason = "triangle_budget"
		if not reason.is_empty():
			rejected.append({"asset": id, "transform": transform, "reason": reason})
			if required:
				failed = true
			return false
		if solid:
			solid_boxes.append(box)
		if not transforms.has(id):
			transforms[id] = []
			mesh_sources[id] = mesh
		transforms[id].append(transform)
		triangles += cost
		placements.append({"asset": id, "kind": kind, "transform": transform, "bounds": box, "tris": cost})
		return true

	func _flat(box: AABB) -> AABB:
		return AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 1.0, box.size.z))

	func _surface(label: String, s: float, side: float, length: float, near: float, far: float, top: float, style: int, rise: float = 0.0) -> void:
		var id := "ground_" + label
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		var local := AABB(-Vector3.ONE * 0.5, Vector3.ONE)
		var xf := _xf(s, side, _edge() + (near + far) * 0.5, top - 0.03)
		xf.basis = (xf.basis * Basis(Vector3.RIGHT, -atan2(rise, far - near))).scaled_local(Vector3(length, 0.06, Vector2(far - near, rise).length()))
		var world: AABB = xf * local
		if CityScenery.road_clearance(world, course) < CityScenery.ROAD_CLEARANCE:
			failed = true
			return
		if not transforms.has(id):
			transforms[id] = []
			var material := ShaderMaterial.new()
			material.shader = CityStreetBlock.GROUND_SHADER
			material.set_shader_parameter("surface_style", style)
			if label in ["alley", "rear_lane", "yard"]:
				material.set_shader_parameter("surface_scale", Vector2(length, far - near))
			material.set_shader_parameter("lane_axis", 1 if label == "alley" else (2 if label == "rear_lane" else 0))
			material.set_shader_parameter("parking_bays", label == "yard")
			mesh.material = material
			mesh_sources[id] = mesh
		transforms[id].append(xf)
		triangles += 12
		placements.append({"asset": id, "kind": "ground", "transform": xf, "bounds": world, "tris": 12})

	func _ground(side: float) -> void:
		var mid := (CityStreetBlock.START + CityStreetBlock.END) * 0.5
		var length := CityStreetBlock.END - CityStreetBlock.START
		# Split the surface bands so none are coplanar overlays.
		_surface("gutter", mid, side, length, 3.6, 4.4, 0.015, 0)
		var from := CityStreetBlock.START
		for to: float in [CityStreetBlock.ALLEYS[0] - 4.0, CityStreetBlock.ALLEYS[1] - 4.0, CityStreetBlock.END]:
			_surface("walk_base", (from + to) * 0.5, side, to - from, 4.62, 8.62, 0.16, 1)
			from = to + 8.0
		_surface("front_path", mid, side, length, 8.62, 12.0, 0.18, 1)
		_surface("yard", mid, side, length, 12.0, 51.0, -0.015, 2)
		_surface("rear_lane", mid, side, length, 51.0, 59.0, -0.005, 0)
		_surface("rear_verge", mid, side, length, 59.0, 63.0, 0.02, 3)
		var reserve_xf := _xf(mid, side, _edge() + 33.3)
		reservations.append(_flat(reserve_xf * AABB(Vector3(-length * 0.5, 0.0, -29.7), Vector3(length, 1.0, 59.4))))
		for alley: float in CityStreetBlock.ALLEYS:
			# Lane insets rise above the yard, with short slopes over the pedestrian strip.
			_surface("alley", alley, side, 8.0, 8.62, 59.0, 0.195, 0)
			_surface("alley_entry", alley, side, 8.0, 3.6, 8.62, 0.1075, 0, 0.175)

	func _frontage(root: Node3D, side: float) -> void:
		var edge := _edge()
		for index in 46:
			var s := 9.0 + index * 6.0
			if _near_alley(s, 3.0):
				continue
			var detailed_frontage := false
			for slot: Dictionary in CityStreetBlock.SLOTS:
				var bounds: AABB = CityStreetBlock._meshes[slot["id"]].get_aabb()
				detailed_frontage = detailed_frontage or (float(slot["side"]) == side and absf(s - float(slot["s"])) < bounds.size.x * 0.5 + 3.0)
			if detailed_frontage:
				_place("sidewalk_panel", _xf(s, side, edge + 6.62), "paving")
			_place("curb_segment", _xf(s, side, edge + 4.51), "paving")
		for s: float in [21.0, 57.0, 111.0, 147.0, 225.0, 261.0]:
			_place("drain_cover", _xf(s, side, edge + 3.95, 0.02), "paving")
		for s: float in [27.0, 99.0, 171.0, 255.0]:
			var at := _xf(s, side, edge + 5.5, 0.18)
			if _place("street_lamp", at, "furniture"):
				var lamp := OmniLight3D.new()
				lamp.position = at * Vector3(0.0, 7.45, -1.65)
				lamp.light_color = Color("ffd5a0") if side < 0.0 else Color("8bbfc7")
				lamp.light_energy = 5.5
				lamp.omni_range = 33.0
				lamp.omni_attenuation = 1.1
				lamp.distance_fade_enabled = true
				lamp.distance_fade_begin = 150.0
				lamp.distance_fade_length = 35.0
				root.add_child(lamp)
				lights += 1
		for s: float in [39.0, 117.0, 159.0, 237.0]:
			_place("bench_planter", _xf(s, side, edge + 7.0, 0.18), "furniture")
		for alley: float in CityStreetBlock.ALLEYS:
			for offset: float in [-5.0, 5.0]:
				_place("bollard", _xf(alley + offset, side, edge + 5.5, 0.18), "furniture")

	func _service_yards(side: float) -> void:
		for alley: float in CityStreetBlock.ALLEYS:
			_place("alley_conduit", _xf(alley, side, _edge() + 35.0), "overhead")
			_place("refuse_station", _xf(alley + 9.0, side, _edge() + 26.0), "furniture", false)
			_place("drain_cover", _xf(alley, side, _edge() + 48.0, 0.2), "paving")
		for slot: Dictionary in CityStreetBlock.SLOTS:
			if float(slot["side"]) != side:
				continue
			var id: String = slot["id"]
			var bounds: AABB = CityStreetBlock._meshes[id].get_aabb()
			var front := 12.0 + float(CityStreetBlock._catalog[id].get("front_setback_m", 0.0))
			_surface("entry_apron", float(slot["s"]), side, bounds.size.x + 2.0, 12.0, maxf(12.1, front), 0.025, 2)

	func _batch(root: Node3D, id: String) -> void:
		var mesh: Mesh = mesh_sources[id]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms[id].size()
		for index in multimesh.instance_count:
			multimesh.set_instance_transform(index, transforms[id][index])
		var batch := MultiMeshInstance3D.new()
		batch.name = id
		batch.multimesh = multimesh
		batch.visibility_range_end = 420.0 if id in ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot"] or id.begins_with("ground_") else 230.0
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.set_meta("city_transforms", transforms[id])
		batch.set_meta("city_local_aabb", mesh.get_aabb())
		batch.set_meta("street_block_piece", true)
		root.add_child(batch)
