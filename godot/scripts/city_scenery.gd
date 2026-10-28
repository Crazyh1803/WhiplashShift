## Code-native "Stacks" city kit: ribbed mid-rise towers, street walls, a stepped skyline
## and one communications crown. Every repeated piece is a MultiMesh batch, nothing
## here has collision, and each piece's real world bounds are kept clear of the road.
class_name CityScenery
extends RefCounted

const SEED := 4207
const MAX_LIGHTS := 12
const ROAD_CLEARANCE := 3.5
const DETAIL_BEHIND := 100.0
const DETAIL_AHEAD := 350.0
const WORLD_LIMIT := 1100.0
const FACADE_SHADER := preload("res://shaders/city_facade.gdshader")
const UNIT_BOX := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


static func build(parent: Node3D, course: CourseDefinition, use_city_kit: bool = true) -> Node3D:
	course = course.geometry()
	var root := Node3D.new()
	root.name = "CityScenery"
	parent.add_child(root)
	_Kit.new(course, use_city_kit).populate(root)
	root.set_meta("authored_quarter", use_city_kit)
	if use_city_kit:
		CityDistrict.build(root, course)
	return root


## Smallest XZ gap between a world AABB and the road's rail edge; negative means overlap.
static func road_clearance(box: AABB, course: CourseDefinition) -> float:
	var low := Vector2(box.position.x, box.position.z)
	var high := Vector2(box.end.x, box.end.z)
	var best := INF
	var count := course.points.size()
	for i in count:
		var a: Dictionary = course.points[i]
		var b: Dictionary = course.points[(i + 1) % count]
		var pa := Vector2(a["pos"].x, a["pos"].z)
		var pb := Vector2(b["pos"].x, b["pos"].z)
		var edge := maxf(float(a["w"]), float(b["w"])) * 0.5 + TrackBuilder.RAIL_OFFSET
		var near := minf(_rect_point_distance(low, high, pa), _rect_point_distance(low, high, pb))
		if near - edge > best + 40.0:
			continue
		best = minf(best, _rect_segment_distance(low, high, pa, pb) - edge)
	return best


static func _rect_point_distance(low: Vector2, high: Vector2, p: Vector2) -> float:
	return Vector2(maxf(maxf(low.x - p.x, 0.0), p.x - high.x), maxf(maxf(low.y - p.y, 0.0), p.y - high.y)).length()


static func _rect_segment_distance(low: Vector2, high: Vector2, a: Vector2, b: Vector2) -> float:
	if _rect_point_distance(low, high, a) == 0.0 or _rect_point_distance(low, high, b) == 0.0:
		return 0.0
	var corners := [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(corners[i], corners[(i + 1) % 4], a, b) != null:
			return 0.0
	var best := minf(_rect_point_distance(low, high, a), _rect_point_distance(low, high, b))
	for corner: Vector2 in corners:
		best = minf(best, corner.distance_to(Geometry2D.get_closest_point_to_segment(corner, a, b)))
	return best


class _Kit extends RefCounted:
	var course: CourseDefinition
	var replace_first_quarter: bool
	var rng := RandomNumberGenerator.new()
	var cumulative := PackedFloat32Array()
	var total := 0.0
	var pieces := {}
	var footprints: Array[AABB] = []
	var lights := 0
	var sinew_count := 0
	var materials := {}
	var box := BoxMesh.new()

	func _init(p_course: CourseDefinition, use_city_kit: bool) -> void:
		course = p_course
		replace_first_quarter = use_city_kit
		rng.seed = CityScenery.SEED
		for key in ["body", "rib", "wall", "post", "cyan", "amber", "sinew", "skyline", "windows", "crown_rib"]:
			pieces[key] = []
		for point: Dictionary in course.points:
			cumulative.append(total)
			total += float(point["dist"])

	func populate(root: Node3D) -> void:
		_make_materials()
		_street_dressing(root)
		_towers(root)
		_service_decks()
		_skyline()
		_crown(root)
		var meshes := {"body": "steel", "rib": "cream", "wall": "ceramic", "post": "cream",
				"cyan": "cyan", "amber": "amber", "sinew": "sinew", "skyline": "skyline",
				"windows": "windows", "crown_rib": "crown_cream"}
		for key: String in ["body", "rib", "wall", "post", "cyan", "amber", "sinew", "skyline", "windows", "crown_rib"]:
			_batch(root, key.capitalize().replace(" ", ""), pieces[key], materials[meshes[key]], key == "windows")

	func _make_materials() -> void:
		var facade := ShaderMaterial.new()
		facade.shader = CityScenery.FACADE_SHADER
		materials["steel"] = facade
		materials["cream"] = _material(Color(0.80, 0.76, 0.64), 0.1, 0.6)
		materials["ceramic"] = _material(Color(0.50, 0.48, 0.42), 0.05, 0.7)
		materials["cyan"] = _glow(Color("00f0ff"), false)
		materials["amber"] = _glow(Color("ffb703"), false)
		materials["sinew"] = TrackMaterials.flesh()
		# Beyond the road fog (280 m), distant silhouettes stay readable by ignoring it.
		materials["skyline"] = _flat(Color(0.07, 0.08, 0.115))
		materials["windows"] = _glow(Color.WHITE, true)
		materials["crown_steel"] = _flat(Color(0.10, 0.11, 0.15))
		materials["crown_cream"] = _flat(Color(0.46, 0.43, 0.36))
		materials["crown_cyan"] = _glow(Color("00f0ff"), true)
		materials["crown_amber"] = _glow(Color("ffb703"), true)

	func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = roughness
		return material

	func _flat(color: Color) -> StandardMaterial3D:
		var material := _material(color, 0.0, 1.0)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.disable_fog = true
		return material

	func _glow(color: Color, far: bool) -> StandardMaterial3D:
		var material := _material(color, 0.0, 0.3)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = color == Color.WHITE
		if color != Color.WHITE:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 5.0
		material.disable_fog = far
		return material

	func _sample(distance: float) -> Dictionary:
		var s := fposmod(distance, total)
		var index := clampi(cumulative.bsearch(s) - 1, 0, course.points.size() - 1)
		var a: Dictionary = course.points[index]
		var b: Dictionary = course.points[(index + 1) % course.points.size()]
		var t := clampf((s - cumulative[index]) / maxf(float(a["dist"]), 0.0001), 0.0, 1.0)
		var dir: Vector3 = (a["dir"] as Vector3).lerp(b["dir"], t).normalized()
		return {"pos": (a["pos"] as Vector3).lerp(b["pos"], t), "dir": dir, "w": float(a["w"]), "s": int(a["s"])}

	func _basis(dir: Vector3) -> Basis:
		return Basis(dir, Vector3.UP, dir.cross(Vector3.UP))

	func _part(key: String, basis: Basis, origin: Vector3, local: Vector3, size: Vector3) -> Array:
		return [key, Transform3D(basis * Basis.from_scale(size), origin + basis * local)]

	func _bounds(parts: Array) -> AABB:
		var merged: AABB = parts[0][1] * CityScenery.UNIT_BOX
		for part: Array in parts:
			merged = merged.merge(part[1] * CityScenery.UNIT_BOX)
		return merged

	func _accept(parts: Array, own_overlap: bool = true, emit_geometry: bool = true) -> bool:
		var bounds := _bounds(parts)
		if absf(bounds.position.x) > CityScenery.WORLD_LIMIT or absf(bounds.end.x) > CityScenery.WORLD_LIMIT \
				or absf(bounds.position.z) > CityScenery.WORLD_LIMIT or absf(bounds.end.z) > CityScenery.WORLD_LIMIT:
			return false
		if CityScenery.road_clearance(bounds, course) < CityScenery.ROAD_CLEARANCE:
			return false
		var flat := AABB(Vector3(bounds.position.x, 0, bounds.position.z), Vector3(bounds.size.x, 1, bounds.size.z)).grow(1.0)
		if own_overlap:
			for other in footprints:
				if other.intersects(flat):
					return false
			footprints.append(flat)
		if emit_geometry:
			for part: Array in parts:
				pieces[part[0]].append(part[1])
		return true

	func _in_detail(raw: float) -> bool:
		return raw <= CityScenery.DETAIL_AHEAD

	# Street walls, pillars and small guide fixtures flank the opening boulevard and first bend.
	func _street_dressing(root: Node3D) -> void:
		var raw := -CityScenery.DETAIL_BEHIND
		var station := 0
		while raw <= CityScenery.DETAIL_AHEAD:
			var at := _sample(raw)
			var basis := _basis(at["dir"])
			for side: float in [-1.0, 1.0]:
				var offset: float = float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET + 6.5
				var origin: Vector3 = at["pos"] + basis * Vector3(0, 0, offset * side)
				var parts: Array = [_part("wall", basis, origin, Vector3(0, 0.65, 0), Vector3(7.4, 1.3, 0.6)),
						_part("post", basis, origin, Vector3(3.9, 1.3, 0), Vector3(0.8, 2.6, 0.8))]
				var accent := "cyan" if (station + int(side > 0.0)) % 2 == 0 else "amber"
				parts.append(_part(accent, basis, origin, Vector3(3.9, 2.8, 0), Vector3(0.4, 0.4, 0.4)))
				_accept(parts, false)
				if station % 10 == 0 and (station / 10 + int(side > 0.0)) % 2 == 0 and lights < CityScenery.MAX_LIGHTS - 3:
					_light(root, origin + basis * Vector3(3.9, 3.4, 0), accent, 18.0)
			raw += 8.0
			station += 1

	func _light(root: Node3D, pos: Vector3, accent: String, range_m: float) -> void:
		var light := OmniLight3D.new()
		light.position = pos
		light.light_color = Color("00f0ff") if accent == "cyan" else Color("ffb703")
		light.light_energy = 4.0
		light.omni_range = range_m
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		root.add_child(light)
		lights += 1

	func _towers(root: Node3D) -> void:
		var raw := -CityScenery.DETAIL_BEHIND
		var index := 0
		while raw < total - CityScenery.DETAIL_BEHIND:
			var detailed := _in_detail(raw)
			var at := _sample(raw)
			var emit_geometry := not replace_first_quarter or fposmod(raw, total) >= total * CityDistrict.FRACTION
			for side: float in [-1.0, 1.0]:
				index += 1
				if rng.randf() < 0.12:
					continue
				_place_tower(at, side, rng.randf_range(11.0, 19.0), detailed, index, rng.randf_range(32.0, 68.0), emit_geometry)
				if index % 2 == 0:
					_place_tower(at, side, rng.randf_range(38.0, 52.0), false, index, rng.randf_range(55.0, 96.0), emit_geometry)
			raw += 30.0 if detailed else 50.0

	func _place_tower(at: Dictionary, side: float, gap: float, detailed: bool, index: int, height: float, emit_geometry: bool) -> void:
		var fx := rng.randf_range(15.0, 26.0)
		var fz := rng.randf_range(15.0, 24.0)
		var basis := _basis(at["dir"])
		var offset: float = float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET + gap + fz * 0.5
		_accept(_tower_parts(basis, at["pos"] + basis * Vector3(0, 0, offset * side), side, fx, fz, height, detailed, index), true, emit_geometry)

	func _tower_parts(basis: Basis, origin: Vector3, side: float, fx: float, fz: float, h: float, detailed: bool, index: int) -> Array:
		var parts: Array = [_part("body", basis, origin, Vector3(0, h * 0.5, 0), Vector3(fx, h, fz)),
				_part("body", basis, origin, Vector3(fx * 0.08, h * 1.15, 0), Vector3(fx * 0.72, h * 0.3, fz * 0.72))]
		if h > 50.0:
			parts.append(_part("body", basis, origin, Vector3(-fx * 0.05, h * 1.4, 0), Vector3(fx * 0.45, h * 0.2, fz * 0.45)))
		var front := -side * (fz * 0.5 + 0.15)
		var ribs := int(fx / 3.2) if detailed else 3
		for i in ribs:
			var x := -fx * 0.5 + (float(i) + 0.5) * fx / float(ribs)
			parts.append(_part("rib", basis, origin, Vector3(x, h * 0.5, front), Vector3(0.55, h, 0.6)))
		if detailed:
			for level in range(1, int(h / 14.0) + 1):
				parts.append(_part("rib", basis, origin, Vector3(0, level * 14.0, 0), Vector3(fx + 0.9, 0.45, fz + 0.9)))
			parts.append(_part("rib", basis, origin, Vector3(0, h, 0), Vector3(fx + 0.9, 0.5, fz + 0.9)))
			parts.append(_part("cyan", basis, origin, Vector3(-fx * 0.25, 3.4, front * 1.0 - side * 0.3), Vector3(0.5, 0.35, 0.35)))
			parts.append(_part("amber", basis, origin, Vector3(fx * 0.25, 3.4, front * 1.0 - side * 0.3), Vector3(0.5, 0.35, 0.35)))
			if index % 4 == 1 and sinew_count < 12:
				sinew_count += 1
				parts.append(_part("sinew", basis, origin, Vector3(fx * 0.5 + 0.2, h * 0.4, 0), Vector3(0.3, h * 0.55, 0.3)))
		else:
			parts.append(_part("cyan" if index % 2 == 0 else "amber", basis, origin, Vector3(0, 3.4, front - side * 0.3), Vector3(0.5, 0.35, 0.35)))
		return parts

	# Low loading decks line the gravel service section on both sides.
	func _service_decks() -> void:
		var first := -1
		var last := -1
		for i in course.points.size():
			if int(course.points[i]["s"]) == Surfaces.Id.GRAVEL:
				first = i if first < 0 else first
				last = i
		if first < 0:
			return
		var raw := cumulative[first] - 20.0
		while raw < cumulative[last] + 30.0:
			var at := _sample(raw)
			for side: float in [-1.0, 1.0]:
				var basis := _basis(at["dir"])
				var offset: float = float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET + 9.0 + 6.0
				var parts := _tower_parts(basis, at["pos"] + basis * Vector3(0, 0, offset * side), side, 22.0, 12.0, 6.0, false, int(raw))
				parts.append(_part("amber", basis, at["pos"] + basis * Vector3(0, 0, offset * side), Vector3(0, 6.6, 0), Vector3(0.5, 0.5, 0.5)))
				_accept(parts)
			raw += 42.0

	# A ring of stepped silhouettes with scattered window lights, outside any plausible road.
	func _skyline() -> void:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for point: Dictionary in course.points:
			low = Vector2(minf(low.x, point["pos"].x), minf(low.y, point["pos"].z))
			high = Vector2(maxf(high.x, point["pos"].x), maxf(high.y, point["pos"].z))
		var centre := (low + high) * 0.5
		var palette := [Color("00f0ff"), Color("ffb703"), Color(0.35, 0.42, 0.5)]
		var count := 64
		for k in count:
			var angle := TAU * (float(k) + rng.randf_range(-0.3, 0.3)) / float(count)
			var radius := rng.randf_range(640.0, 960.0)
			var at := centre + Vector2.from_angle(angle) * radius
			var origin := Vector3(at.x, 0, at.y)
			var inward := Vector3(-cos(angle), 0, -sin(angle))
			var basis := _basis(Vector3(-inward.z, 0, inward.x))
			var width := rng.randf_range(40.0, 90.0)
			var depth := rng.randf_range(40.0, 80.0)
			var height := rng.randf_range(90.0, 260.0)
			var parts: Array = []
			var base := 0.0
			for step in 3:
				var scale := 1.0 - 0.28 * float(step)
				var step_h := height * (0.5 if step == 0 else 0.3 if step == 1 else 0.2)
				parts.append(_part("skyline", basis, origin, Vector3(0, base + step_h * 0.5, 0), Vector3(width * scale, step_h, depth * scale)))
				for dot in 3:
					var spot := Vector3(rng.randf_range(-0.4, 0.4) * width * scale, base + rng.randf_range(0.15, 0.85) * step_h, -depth * scale * 0.5 - 0.3)
					var colour: Color = palette[rng.randi() % 3]
					var window := _part("windows", basis, origin, spot, Vector3(2.2, 2.6, 0.4))
					window.append(colour)
					parts.append(window)
				base += step_h
			_accept_skyline(parts)

	func _accept_skyline(parts: Array) -> void:
		var bounds := _bounds(parts)
		if CityScenery.road_clearance(bounds, course) < CityScenery.ROAD_CLEARANCE:
			return
		if absf(bounds.position.x) > CityScenery.WORLD_LIMIT or absf(bounds.end.x) > CityScenery.WORLD_LIMIT \
				or absf(bounds.position.z) > CityScenery.WORLD_LIMIT or absf(bounds.end.z) > CityScenery.WORLD_LIMIT:
			return
		for part: Array in parts:
			pieces[part[0]].append([part[1], part[2]] if part[0] == "windows" else part[1])

	func _crown(root: Node3D) -> void:
		var origin := Vector3.ZERO
		var found := false
		var start: Dictionary = course.points[0]
		for ahead: float in [560.0, 520.0, 610.0, 480.0]:
			for lateral: float in [0.0, 40.0, -40.0, 90.0, -90.0]:
				var basis := _basis(start["dir"])
				origin = start["pos"] + basis * Vector3(ahead, 0, lateral)
				if CityScenery.road_clearance(AABB(origin - Vector3(48, 0, 48), Vector3(96, 1, 96)), course) >= CityScenery.ROAD_CLEARANCE + 20.0:
					found = true
					break
			if found:
				break
		if not found:
			return
		var crown := Node3D.new()
		crown.name = "Crown"
		crown.position = origin
		root.add_child(crown)
		var steel: Material = materials["crown_steel"]
		var cream: Material = materials["crown_cream"]
		_crown_mesh(crown, "Podium", _box_mesh(Vector3(44, 14, 44)), steel, Vector3(0, 7, 0), Vector3.ZERO)
		_crown_mesh(crown, "PodiumRim", _box_mesh(Vector3(46, 1.2, 46)), cream, Vector3(0, 14.2, 0), Vector3.ZERO)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 7.0
		shaft.bottom_radius = 11.0
		shaft.height = 120.0
		shaft.radial_segments = 8
		_crown_mesh(crown, "Shaft", shaft, steel, Vector3(0, 74, 0), Vector3.ZERO)
		for i in 8:
			var a := TAU * float(i) / 8.0 + PI / 8.0
			var lean := Vector3(cos(a), 0, sin(a))
			var xf := Transform3D(Basis(Vector3.UP, -a).scaled_local(Vector3(1.4, 120.0, 0.9)), origin + lean * 8.7 + Vector3(0, 74, 0))
			pieces["crown_rib"].append(xf)
		_crown_mesh(crown, "TierRing", _cylinder(14.0, 14.0, 9.0), steel, Vector3(0, 139, 0), Vector3.ZERO)
		_crown_mesh(crown, "TierBlock", _box_mesh(Vector3(22, 9, 22)), steel, Vector3(0, 148, 0), Vector3(0, 22, 0))
		_crown_mesh(crown, "TierRib", _box_mesh(Vector3(24, 1.0, 24)), cream, Vector3(0, 153, 0), Vector3(0, 22, 0))
		_crown_mesh(crown, "CyanBand", _cylinder(11.6, 11.6, 0.8), materials["crown_cyan"], Vector3(0, 100, 0), Vector3.ZERO)
		_crown_mesh(crown, "Mast", _cylinder(1.2, 1.6, 60.0), steel, Vector3(0, 184, 0), Vector3.ZERO)
		_crown_mesh(crown, "SpireA", _box_mesh(Vector3(2.6, 62.0, 2.6)), steel, Vector3(8, 183, 0), Vector3(0, 0, -14))
		_crown_mesh(crown, "SpireB", _box_mesh(Vector3(2.6, 46.0, 2.6)), steel, Vector3(-6, 175, 6), Vector3(10, 0, 12))
		_crown_mesh(crown, "SpireBroken", _box_mesh(Vector3(2.6, 24.0, 2.6)), steel, Vector3(-3, 166, -8), Vector3(-16, 0, 6))
		_crown_mesh(crown, "Dish", _cylinder(9.0, 9.0, 1.4), cream, Vector3(0, 168, 0), Vector3(38, 20, 0))
		var beacon := SphereMesh.new()
		beacon.radius = 2.2
		beacon.height = 4.4
		_crown_mesh(crown, "Beacon", beacon, materials["crown_amber"], Vector3(0, 217, 0), Vector3.ZERO)
		var glow := OmniLight3D.new()
		glow.position = Vector3(0, 217, 0)
		glow.light_color = Color("ffb703")
		glow.light_energy = 3.0
		glow.omni_range = 60.0
		glow.shadow_enabled = false
		crown.add_child(glow)
		lights += 1

	func _box_mesh(size: Vector3) -> BoxMesh:
		var mesh := BoxMesh.new()
		mesh.size = size
		return mesh

	func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
		var mesh := CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = bottom
		mesh.height = height
		mesh.radial_segments = 12
		return mesh

	func _crown_mesh(parent: Node3D, label: String, mesh: Mesh, material: Material, pos: Vector3, degrees: Vector3) -> void:
		var instance := MeshInstance3D.new()
		instance.name = label
		instance.mesh = mesh
		instance.material_override = material
		instance.position = pos
		instance.rotation_degrees = degrees
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)

	func _batch(root: Node3D, label: String, transforms: Array, material: Material, coloured: bool) -> void:
		if transforms.is_empty():
			return
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = coloured
		multimesh.mesh = box
		multimesh.instance_count = transforms.size()
		var placed: Array[Transform3D] = []
		for i in transforms.size():
			var item = transforms[i]
			placed.append(item[0] if coloured else item)
			if coloured:
				multimesh.set_instance_transform(i, item[0])
				multimesh.set_instance_color(i, item[1])
			else:
				multimesh.set_instance_transform(i, item)
		var instance := MultiMeshInstance3D.new()
		instance.name = label
		instance.multimesh = multimesh
		# Headless rendering returns identity from MultiMesh reads, so tests use this record.
		instance.set_meta("city_transforms", placed)
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
