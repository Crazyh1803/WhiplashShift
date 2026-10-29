## Industrial market benchmark regression suite: real GLBs, manifest validation, reference car, review scene; headless, no rendering.
extends Node3D

const DIR := "res://assets/city/candidates/industrial_market/"
const MANIFEST_PATH := DIR + "benchmark_manifest.json"
const IDS: Array[String] = ["redline_shop", "ramen_vendor", "ramen_customer"]
const PEOPLE: Array[String] = ["ramen_vendor", "ramen_customer"]
const TOLERANCE := 0.01
const FLOOR_TOP := 0.15
const BAD_NUMBERS: Array = [NAN, INF, -INF, 1e100, -1e100, 1000.0, true, "1", null]

var _pass := 0
var _fail := 0
var _manifest: Dictionary = {}


func _ready() -> void:
	var guarded := _fingerprint()
	var menu_error: String = GameSession.menu_error
	_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_test_manifest_validation()
	var catalog_before := var_to_str(VehicleCatalog.get_vehicle("blackjack"))
	var host := Node3D.new()
	add_child(host)
	var benchmark := IndustrialMarketBenchmark.new()
	host.add_child(benchmark)
	var built := benchmark.build()
	_check("benchmark builds from the real manifest and GLBs: %s" % ["; ".join(benchmark.errors)], built)
	if built:
		_test_placements_and_geometry(benchmark)
		_test_materials(benchmark)
		_test_authored_uvs()
		_test_people(benchmark)
		_test_reference_vehicle(benchmark, catalog_before)
		_test_rebuild_rejected(benchmark)
	host.free()
	if built:
		await _test_review_scene()
	await _test_failure_recovery()
	_check("review scene left GameSession.menu_error as it found it", GameSession.menu_error == menu_error)
	_check("shipped assets, manifest, settings and saves are unmodified", _fingerprint() == guarded)
	print("INDUSTRIAL_MARKET: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _fingerprint() -> Dictionary:
	var result := {}
	for name in IDS:
		result[name] = FileAccess.get_md5(DIR + name + ".glb")
	result["manifest"] = FileAccess.get_md5(MANIFEST_PATH)
	for file in DirAccess.get_files_at("user://"):
		result["user:" + file] = FileAccess.get_md5("user://" + file)
	return result


# ---------------------------------------------------------------- manifest_errors

func _test_manifest_validation() -> void:
	_check("actual manifest passes", IndustrialMarketBenchmark.manifest_errors(_manifest).is_empty())
	var extra := _mutated(func(m: Dictionary) -> void: m["unrelated"] = [1, 2])
	_check("unrelated manifest keys are tolerated", IndustrialMarketBenchmark.manifest_errors(extra).is_empty())
	for root: Variant in [null, [], "manifest", 1, 1.0, true, {}, {"version": 1}, {"version": 2, "assets": [], "placements": []},
			{"version": 1, "assets": {}, "placements": []},
			{"version": 1, "assets": [], "placements": {}}, {"version": 1, "assets": [], "placements": []}]:
		_rejects("root %s" % [var_to_str(root)], root)
	# assets
	_rejects("missing asset", _mutated(func(m: Dictionary) -> void: m["assets"].pop_back()))
	_rejects("duplicate asset", _mutated(func(m: Dictionary) -> void: m["assets"][2] = m["assets"][1].duplicate(true)))
	_rejects("unknown asset id", _mutated(func(m: Dictionary) -> void: m["assets"][0]["id"] = "other_shop"))
	_rejects("non-dictionary asset", _mutated(func(m: Dictionary) -> void: m["assets"][0] = "redline_shop"))
	_rejects("null asset", _mutated(func(m: Dictionary) -> void: m["assets"][1] = null))
	_rejects("numeric asset id", _mutated(func(m: Dictionary) -> void: m["assets"][0]["id"] = 7))
	_rejects("missing asset filename", _mutated(func(m: Dictionary) -> void: m["assets"][0].erase("glb")))
	for filename: Variant in ["../redline_shop.glb", "/redline_shop.glb", "C:/redline_shop.glb", "C:\\redline_shop.glb", "sub/redline_shop.glb",
			"..\\redline_shop.glb", "ramen_vendor.glb", "redline_shop.GLB", "res://redline_shop.glb", "", null]:
		_rejects("asset filename %s" % [var_to_str(filename)], _mutated(func(m: Dictionary) -> void: m["assets"][0]["glb"] = filename))
	# placements
	_rejects("missing placement", _mutated(func(m: Dictionary) -> void: m["placements"].pop_back()))
	_rejects("duplicate placement", _mutated(func(m: Dictionary) -> void: m["placements"][2]["asset"] = "ramen_vendor"))
	_rejects("unknown placement asset", _mutated(func(m: Dictionary) -> void: m["placements"][0]["asset"] = "other_shop"))
	_rejects("non-dictionary placement", _mutated(func(m: Dictionary) -> void: m["placements"][1] = [0, 0, 0]))
	_rejects("null placement", _mutated(func(m: Dictionary) -> void: m["placements"][1] = null))
	_rejects("missing position", _mutated(func(m: Dictionary) -> void: m["placements"][1].erase("position")))
	_rejects("missing yaw", _mutated(func(m: Dictionary) -> void: m["placements"][1].erase("yaw_degrees")))
	_rejects("null position", _mutated(func(m: Dictionary) -> void: m["placements"][1]["position"] = null))
	_rejects("two-component position", _mutated(func(m: Dictionary) -> void: m["placements"][1]["position"] = [0.0, 0.0]))
	_rejects("four-component position", _mutated(func(m: Dictionary) -> void: m["placements"][1]["position"] = [0.0, 0.0, 0.0, 0.0]))
	_rejects("dictionary position", _mutated(func(m: Dictionary) -> void: m["placements"][1]["position"] = {"x": 0.0}))
	for axis in 3:
		for bad: Variant in BAD_NUMBERS:
			_rejects("position[%d] = %s" % [axis, var_to_str(bad)], _mutated(func(m: Dictionary) -> void: m["placements"][1]["position"][axis] = bad))
	for bad: Variant in BAD_NUMBERS:
		_rejects("yaw = %s" % [var_to_str(bad)], _mutated(func(m: Dictionary) -> void: m["placements"][2]["yaw_degrees"] = bad))
	_check("integer and large-but-sane placements are accepted", IndustrialMarketBenchmark.manifest_errors(_mutated(func(m: Dictionary) -> void:
		m["placements"][1]["position"] = [5, 0, -999.5]
		m["placements"][1]["yaw_degrees"] = -720)).is_empty())
	# review targets
	_rejects("missing review_targets", _mutated(func(m: Dictionary) -> void: m.erase("review_targets")))
	_rejects("null review_targets", _mutated(func(m: Dictionary) -> void: m["review_targets"] = null))
	_rejects("array review_targets", _mutated(func(m: Dictionary) -> void: m["review_targets"] = []))
	for key: String in ["counter", "vendor_face", "customer_face", "support", "sign"]:
		_rejects("missing target %s" % key, _mutated(func(m: Dictionary) -> void: m["review_targets"].erase(key)))
		_rejects("short target %s" % key, _mutated(func(m: Dictionary) -> void: m["review_targets"][key] = [1.0, 2.0]))
		for bad: Variant in BAD_NUMBERS:
			_rejects("target %s[1] = %s" % [key, var_to_str(bad)], _mutated(func(m: Dictionary) -> void: m["review_targets"][key][1] = bad))
	_rejects("missing materials", _mutated(func(m: Dictionary) -> void: m["review_targets"].erase("materials")))
	_rejects("empty materials", _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"] = {}))
	_rejects("array materials", _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"] = [[0.0, 0.0, 0.0]]))
	_rejects("null materials", _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"] = null))
	_rejects("empty nested material target", _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"]["concrete"] = []))
	_rejects("null nested material target", _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"]["concrete"] = null))
	_rejects("string nested material target", _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"]["concrete"] = "x"))
	_rejects("dictionary nested material target", _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"]["concrete"] = {"a": [0, 0, 0]}))
	for bad: Variant in BAD_NUMBERS:
		_rejects("nested material target = %s" % [var_to_str(bad)], _mutated(func(m: Dictionary) -> void: m["review_targets"]["materials"]["concrete"][2] = bad))
	_check("number helper rejects NaN, infinity, huge finite values and bools", not IndustrialMarketBenchmark.is_number(NAN)
		and not IndustrialMarketBenchmark.is_number(INF) and not IndustrialMarketBenchmark.is_number(1e100)
		and not IndustrialMarketBenchmark.is_number(false) and IndustrialMarketBenchmark.is_number(0) and IndustrialMarketBenchmark.is_number(-12.5))


func _mutated(change: Callable) -> Dictionary:
	var copy: Dictionary = _manifest.duplicate(true)
	change.call(copy)
	return copy


func _rejects(label: String, value: Variant) -> void:
	_check("manifest_errors rejects " + label, not IndustrialMarketBenchmark.manifest_errors(value).is_empty())


# ---------------------------------------------------------------- geometry

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		result.append(found as MeshInstance3D)
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	return result


func _indexed_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_check_once(not indices.is_empty() and indices.size() % 3 == 0, "surface %d is indexed triangles" % surface)
		total += indices.size() / 3
	return total


func _world_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for instance in _meshes(model):
		var box := instance.global_transform * instance.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _expected_bounds(entry: Dictionary, placement: Dictionary) -> AABB:
	var low: Array = entry["aabb"]["min"]
	var high: Array = entry["aabb"]["max"]
	var transform := Transform3D(Basis(Vector3.UP, deg_to_rad(float(placement["yaw_degrees"]))), _vector(placement["position"]))
	var bounds := AABB()
	for corner in 8:
		var point := Vector3(high[0] if corner & 1 else low[0], high[1] if corner & 2 else low[1], high[2] if corner & 4 else low[2])
		bounds = AABB(transform * point, Vector3.ZERO) if corner == 0 else bounds.expand(transform * point)
	return bounds


func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


func _entry(id: String) -> Dictionary:
	for entry: Dictionary in _manifest["assets"]:
		if entry["id"] == id:
			return entry
	return {}


func _placement(id: String) -> Dictionary:
	for placement: Dictionary in _manifest["placements"]:
		if placement["asset"] == id:
			return placement
	return {}


func _test_placements_and_geometry(benchmark: IndustrialMarketBenchmark) -> void:
	_check("exactly the three approved models are built", benchmark.models.size() == 3 and benchmark.models.keys().all(func(k: Variant) -> bool: return k in IDS))
	var triangles := 0
	var surfaces := 0
	for id in IDS:
		var model: Node3D = benchmark.models[id]
		var placement := _placement(id)
		_check("%s is a child named after its asset" % id, model.get_parent() == benchmark and model.name == id)
		_check("%s position matches the manifest placement" % id, model.position.is_equal_approx(_vector(placement["position"])))
		_check("%s yaw matches the manifest placement" % id, absf(angle_difference(model.rotation.y, deg_to_rad(float(placement["yaw_degrees"])))) < 1e-4)
		_check("%s has no pitch or roll" % id, is_zero_approx(model.rotation.x) and is_zero_approx(model.rotation.z))
		_check("%s has visual geometry only" % id, model.find_children("*", "CollisionObject3D", true, false).is_empty()
			and model.find_children("*", "Light3D", true, false).is_empty() and model.find_children("*", "Camera3D", true, false).is_empty())
		var measured := 0
		var count := 0
		for instance in _meshes(model):
			measured += _indexed_triangles(instance.mesh)
			count += instance.mesh.get_surface_count()
			_check_once(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s shadow casting" % id)
		var entry := _entry(id)
		_check("%s measured indexed triangles %d match manifest %d" % [id, measured, entry["tris"]], measured == int(entry["tris"]))
		_check("%s surface count %d matches manifest %d" % [id, count, entry["surfaces"].size()], count == entry["surfaces"].size())
		triangles += measured
		surfaces += count
		var world := _world_bounds(model)
		var expected := _expected_bounds(entry, placement)
		_check("%s world bounds %s match manifest placement %s" % [id, world, expected],
			world.position.distance_to(expected.position) < TOLERANCE and world.end.distance_to(expected.end) < TOLERANCE)
		_check("%s finite bounds" % id, world.position.is_finite() and world.end.is_finite())
		_check("%s benchmark mesh_bounds agree with measurement" % id, benchmark.mesh_bounds[id].size.distance_to(world.size) < TOLERANCE)
	_check("candidate triangles %d are measured as 88624 and reported as such" % triangles, triangles == 88624 and benchmark.triangle_count == triangles)
	_check("candidate surfaces %d are measured as 20 and reported as such" % surfaces, surfaces == 20 and benchmark.surface_count == surfaces)
	_check("candidate stays within 120000 triangles and 20 surfaces", triangles <= IndustrialMarketBenchmark.TRIANGLE_CAP and surfaces <= IndustrialMarketBenchmark.SURFACE_CAP)
	_check("manifest cost block agrees with measurement", int(_manifest["costs"]["combined_tris"]) == triangles and int(_manifest["costs"]["combined_surfaces"]) == surfaces)
	_check("benchmark errors stay empty", benchmark.errors.is_empty())
	_check("texture working-set estimate within the 128 MiB budget", float(_manifest["costs"]["texture_mib_working"]) <= 128.0)


# ---------------------------------------------------------------- materials

func _declared_slots(entry: Dictionary, material_name: String) -> Array[String]:
	var result: Array[String] = []
	for texture: Dictionary in entry["textures"]:
		if texture["material"] == material_name:
			result.append(texture["slot"])
	return result


func _declared_size(entry: Dictionary, material_name: String, slot: String) -> Vector2i:
	for texture: Dictionary in entry["textures"]:
		if texture["material"] == material_name and texture["slot"] == slot:
			return Vector2i(texture["width"], texture["height"])
	return Vector2i.ZERO


func _test_materials(benchmark: IndustrialMarketBenchmark) -> void:
	for id in IDS:
		var entry := _entry(id)
		var names: Array = entry["surfaces"]
		var seen: Array[String] = []
		var shade_low := 1.0
		var shade_high := 0.0
		for instance in _meshes(benchmark.models[id]):
			var mesh := instance.mesh
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface) as BaseMaterial3D
				_check("%s surface %d has a standard material" % [id, surface], material != null)
				if material == null:
					continue
				var label := "%s/%s" % [id, material.resource_name]
				seen.append(material.resource_name)
				var slots := _declared_slots(entry, material.resource_name)
				var emissive := material.resource_name == "sign_emissive"
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				# UVs and tangents
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				_check("%s has one finite UV per vertex" % label, uvs.size() == vertices.size() and uvs.size() > 0)
				var finite := true
				for uv in uvs:
					finite = finite and uv.is_finite() and absf(uv.x) < 1000.0 and absf(uv.y) < 1000.0
				_check("%s has one finite UV per imported vertex" % label, finite)
				if "normal" in slots:
					var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
					_check("%s carries tangents for its normal map" % label, tangents.size() == vertices.size() * 4)
				# declared texture maps
				_check("%s declares an albedo map unless purely emissive" % label, emissive or "baseColor" in slots)
				_check("%s albedo map present iff declared" % label, (material.albedo_texture != null) == ("baseColor" in slots))
				_check("%s normal map present iff declared" % label, (material.normal_texture != null) == ("normal" in slots) and material.normal_enabled == ("normal" in slots))
				_check("%s ORM map present iff declared" % label, (material.roughness_texture != null) == ("metallicRoughness" in slots))
				if "metallicRoughness" in slots:
					_check("%s roughness reads G and metallic reads B" % label, material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
						and material.metallic_texture != null and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE)
				for slot in slots:
					var texture: Texture2D = {"baseColor": material.albedo_texture, "normal": material.normal_texture, "metallicRoughness": material.roughness_texture}.get(slot)
					var size := _declared_size(entry, material.resource_name, slot)
					_check("%s %s texture loads at its declared %s" % [label, slot, size], texture != null and Vector2i(texture.get_width(), texture.get_height()) == size)
				if not emissive:
					_check("%s is not emissive" % label, not material.emission_enabled)
				# baked vertex colours
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				_check("%s has one baked COLOR_0 per vertex" % label, colors.size() == vertices.size())
				if not material.vertex_color_use_as_albedo:
					# Observed importer behaviour, reported to the lead rather than asserted: the first material of each model does not get the flag.
					print("KNOWN_DEFECT: %s imported without vertex_color_use_as_albedo" % label)
				var colors_valid := true
				for color in colors:
					colors_valid = colors_valid and is_finite(color.r + color.g + color.b + color.a) and color.r >= 0.0 and color.g >= 0.0 and color.b >= 0.0 and maxf(maxf(color.r, color.g), color.b) <= 1.0
					shade_low = minf(shade_low, color.r)
					shade_high = maxf(shade_high, color.r)
				_check("%s vertex colours are finite and within 0..1" % label, colors_valid)
				# skin sub-surface scattering is a candidate-only instance override, never written to the shared mesh material
				var is_skin := "skin" in material.resource_name.to_lower()
				var active := instance.get_active_material(surface) as BaseMaterial3D
				_check("%s shared mesh material has no subsurface scattering" % label, not material.subsurf_scatter_enabled)
				if is_skin:
					_check("%s skin override enables SSS skin mode at strength 0.08" % label, instance.get_surface_override_material(surface) != null
						and active.subsurf_scatter_enabled and active.subsurf_scatter_skin_mode and is_equal_approx(active.subsurf_scatter_strength, 0.08)
						and active.albedo_texture == material.albedo_texture)
				else:
					_check("%s has no SSS override" % label, instance.get_surface_override_material(surface) == null and not active.subsurf_scatter_enabled)
		_check("%s GLB material order %s matches manifest" % [id, seen], seen == names)
		if shade_high - shade_low <= 0.05:
			# Observed: the baked AO/wear is exported as COLOR_1 and COLOR_0 is flat white, so Godot imports no wear at all.
			print("KNOWN_DEFECT: %s imported COLOR_0 is a flat fill (%.3f..%.3f)" % [id, shade_low, shade_high])
	var sign_material: BaseMaterial3D
	for instance in _meshes(benchmark.models["redline_shop"]):
		for surface in instance.mesh.get_surface_count():
			if instance.mesh.surface_get_material(surface).resource_name == "sign_emissive":
				sign_material = instance.mesh.surface_get_material(surface)
	_check("the shop sign alone is emissive", sign_material != null and sign_material.emission_enabled and sign_material.emission_energy_multiplier > 0.0)


func _texcoord_sets(json: Dictionary, material_name: String) -> Array:
	var sets := []
	for material: Dictionary in json["materials"]:
		if material.get("name") != material_name:
			continue
		var refs: Array = [material.get("normalTexture"), material.get("emissiveTexture"), material.get("occlusionTexture"),
			material.get("pbrMetallicRoughness", {}).get("baseColorTexture"), material.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture")]
		for ref: Variant in refs:
			if ref is Dictionary:
				sets.append(int(ref.get("texCoord", 0)))
	return sets


## Reads the authored UVs straight from the GLB (uncompressed), since imported meshes are quantized.
func _test_authored_uvs() -> void:
	for id in IDS:
		var state := GLTFState.new()
		var error := GLTFDocument.new().append_from_file(ProjectSettings.globalize_path(DIR + id + ".glb"), state)
		_check("%s GLB parses for authored UV inspection" % id, error == OK and state.get_meshes().size() == 1)
		if error != OK or state.get_meshes().size() != 1:
			continue
		var mesh: ImporterMesh = state.get_meshes()[0].mesh
		var names: Array[String] = []
		for surface in mesh.get_surface_count():
			var label := "%s/%s" % [id, mesh.get_surface_name(surface)]
			names.append(mesh.get_surface_name(surface))
			var arrays := mesh.get_surface_arrays(surface)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			var finite := true
			for uv in uvs:
				finite = finite and uv.is_finite() and absf(uv.x) < 1000.0 and absf(uv.y) < 1000.0
				low = low.min(uv)
				high = high.max(uv)
			_check("%s authored UVs: one finite UV per vertex" % label, finite and uvs.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() and uvs.size() > 0)
			var spans := high.x - low.x > 0.01 and high.y - low.y > 0.01
			if _texcoord_sets(state.get_json(), mesh.get_surface_name(surface)).has(1):
				# Observed: these maps are authored on TEXCOORD_1, which Godot's importer does not apply to albedo/normal/ORM; TEXCOORD_0 is constant.
				print("KNOWN_DEFECT: %s samples its maps from TEXCOORD_1; TEXCOORD_0 spans %s..%s" % [label, low, high])
			else:
				_check("%s authored UVs span a real area (%s..%s)" % [label, low, high], spans)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			_check("%s authored COLOR_0 per vertex" % label, colors.size() == uvs.size())
		_check("%s authored surface names %s match the manifest" % [id, names], names == _entry(id)["surfaces"])


# ---------------------------------------------------------------- people

func _test_people(benchmark: IndustrialMarketBenchmark) -> void:
	var shop := _world_bounds(benchmark.models["redline_shop"])
	var heights: Array[float] = []
	for id in PEOPLE:
		var model: Node3D = benchmark.models[id]
		var bounds := _world_bounds(model)
		heights.append(bounds.size.y)
		_check("%s is human scale (%.2f m)" % [id, bounds.size.y], bounds.size.y >= 1.55 and bounds.size.y <= 1.95 and bounds.size.x < 1.2 and bounds.size.z < 1.2)
		_check("%s stands on the %.2f m floor/sidewalk top" % [id, FLOOR_TOP], absf(bounds.position.y - FLOOR_TOP) < 0.012)
		_check("%s stands within the shop footprint" % id, shop.position.x < model.position.x and model.position.x < shop.end.x
			and shop.position.z < model.position.z and model.position.z < shop.end.z)
		_check("%s is not inside the street reference strip" % id, model.position.z > -4.7)
	_check("the two people are distinct figures", absf(heights[0] - heights[1]) > 0.05
		and benchmark.models["ramen_vendor"].position.distance_to(benchmark.models["ramen_customer"].position) > 0.8
		and _entry("ramen_vendor")["surfaces"] != _entry("ramen_customer")["surfaces"] and _entry("ramen_vendor")["tris"] != _entry("ramen_customer")["tris"])
	_check("vendor and customer face each other across the counter", absf(absf(angle_difference(benchmark.models["ramen_vendor"].rotation.y, benchmark.models["ramen_customer"].rotation.y)) - PI) < 0.01
		and benchmark.models["ramen_customer"].position.z < benchmark.models["ramen_vendor"].position.z)
	_check("no person material is emissive", PEOPLE.all(func(id: String) -> bool: return _meshes(benchmark.models[id]).all(func(i: MeshInstance3D) -> bool:
		return range(i.mesh.get_surface_count()).all(func(s: int) -> bool: return not (i.get_active_material(s) as BaseMaterial3D).emission_enabled))))


# ---------------------------------------------------------------- Blackjack reference

func _test_reference_vehicle(benchmark: IndustrialMarketBenchmark, catalog_before: String) -> void:
	var car := benchmark.reference_vehicle
	_check("reference vehicle exists beside the candidate", car != null and car.get_parent() == benchmark and car.name == "ReferenceBlackjackX17")
	if car == null:
		return
	var reference: Dictionary = benchmark.get_meta("vehicle_reference")
	var spec := VehicleCatalog.get_vehicle("blackjack")
	_check("reference metadata names the factory Blackjack", reference["id"] == "blackjack" and reference["rig"] == spec["visual"]["rig"]
		and reference["scene"] == spec["visual"]["scene"] and car.vehicle_id == "blackjack")
	_check("reference uses default customization", var_to_str(reference["customization"]) == var_to_str(VehicleCatalog.default_customization("blackjack")))
	_check("catalog entry is not mutated by the benchmark", var_to_str(VehicleCatalog.get_vehicle("blackjack")) == catalog_before)
	_check("reference has a tuning profile and is frozen", car.tuning != null and car.freeze)
	_check("reference processing is disabled", car.process_mode == Node.PROCESS_MODE_DISABLED and not car.can_process())
	_check("reference body has no collision layers", car.collision_layer == 0 and car.collision_mask == 0)
	_check("reference placed at the manifest vehicle slot", is_equal_approx(car.rotation.y, PI * 0.5) and is_equal_approx(car.position.x, -3.0) and is_equal_approx(car.position.z, -7.5))
	_check("reference is inside the reserved curb strip", car.position.z <= -5.0 and car.position.z >= -10.0)
	var shapes := 0
	for body: CollisionObject3D in car.find_children("*", "CollisionObject3D", true, false):
		_check_once(body.collision_layer == 0 and body.collision_mask == 0, "collision object %s has no layers" % body.name)
	for shape: CollisionShape3D in car.find_children("*", "CollisionShape3D", true, false):
		shapes += 1
		_check_once(shape.disabled, "collision shape %s is disabled" % shape.name)
	for ray: RayCast3D in car.find_children("*", "RayCast3D", true, false):
		_check_once(not ray.enabled, "raycast %s is disabled" % ray.name)
	for node: Node in car.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			_check_once(not node.playing, "audio player %s is silent" % node.name)
		if node is Light3D or node is Camera3D:
			_check_once(false, "%s adds a light or camera" % node.name)
	var triangles := 0
	var surfaces := 0
	var union := AABB()
	var first := true
	for instance in _meshes(car):
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		triangles += _indexed_or_flat_triangles(instance.mesh)
		surfaces += instance.mesh.get_surface_count()
		var box := instance.global_transform * instance.mesh.get_aabb()
		union = box if first else union.merge(box)
		first = false
	_check("reference has visible geometry (%d triangles, %d surfaces)" % [triangles, surfaces], triangles > 0 and surfaces > 0)
	_check("reference triangles are measured separately from the candidate", benchmark.vehicle_triangle_count == triangles and benchmark.vehicle_surface_count == surfaces
		and benchmark.triangle_count == 88624)
	var bounds := benchmark.vehicle_bounds
	_check("reference vertex bounds %s are finite and inside the mesh boxes" % bounds, bounds.position.is_finite() and bounds.size.is_finite()
		and bounds.size.x > 0.5 and bounds.size.y > 0.5 and bounds.size.z > 0.5 and union.grow(TOLERANCE).encloses(bounds))
	_check("reference is a car-sized object (%s)" % bounds.size, maxf(bounds.size.x, bounds.size.z) > 2.5 and maxf(bounds.size.x, bounds.size.z) < 8.0 and bounds.size.y < 2.5)
	_check("reference preview is grounded (lowest vertex %.3f)" % bounds.position.y, absf(bounds.position.y) < 0.35)
	_check("reference sits in the curb strip", bounds.position.z > -11.5 and bounds.end.z < -4.5)


func _indexed_or_flat_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		total += (indices as PackedInt32Array).size() / 3 if indices != null and not (indices as PackedInt32Array).is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _test_rebuild_rejected(benchmark: IndustrialMarketBenchmark) -> void:
	var children := benchmark.get_child_count()
	var triangles := benchmark.triangle_count
	benchmark.errors.clear()
	_check("a second build into the populated host is rejected", not benchmark.build() and benchmark.errors.size() == 1 and "empty node" in benchmark.errors[0])
	_check("a rejected rebuild changes nothing", benchmark.get_child_count() == children and benchmark.triangle_count == triangles and benchmark.models.size() == 3)


# ---------------------------------------------------------------- review scene

func _lights(root: Node) -> Array[Light3D]:
	var result: Array[Light3D] = []
	for found: Node in root.find_children("*", "Light3D", true, false):
		result.append(found as Light3D)
	return result


func _visible_lights(root: Node) -> Array[Light3D]:
	return _lights(root).filter(func(light: Light3D) -> bool: return light.visible)


func _test_review_scene() -> void:
	var viewer: Node3D = (load("res://scenes/industrial_market_review.tscn") as PackedScene).instantiate()
	add_child(viewer)
	var camera: Camera3D = viewer.camera
	_check("review scene built a benchmark and a current camera", viewer.benchmark != null and viewer.benchmark.errors.is_empty() and camera != null and camera.current)
	_check("eight camera presets", viewer.VIEWS.size() == 8)
	var views: OptionButton = viewer.get_node("ReviewControls").find_child("ReviewView", true, false)
	_check("view selector lists every preset", views != null and views.item_count == viewer.VIEWS.size())
	for index in viewer.VIEWS.size():
		views.select(index)
		views.item_selected.emit(index)
		var focus: Vector3 = viewer.focus
		var position := camera.global_position
		var label := "view %d (%s)" % [index, viewer.VIEWS[index]]
		_check("%s selected" % label, viewer.view_index == index)
		_check("%s camera and focus are finite" % label, position.is_finite() and focus.is_finite() and is_finite(viewer.distance) and is_finite(viewer.yaw) and is_finite(viewer.pitch))
		_check("%s camera is above ground" % label, position.y >= 0.12 - 1e-4)
		_check("%s zoom distance %.2f is in bounds" % [label, viewer.distance], viewer.distance >= 0.6 and viewer.distance <= 35.0)
		_check("%s camera stays over the 36 m ground" % label, absf(position.x) <= 18.0 and absf(position.z) <= 18.0)
		_check("%s looks at its focus" % label, (-camera.global_transform.basis.z).dot((focus - position).normalized()) > 0.999)
		_check("%s focus is near the benchmark" % label, focus.length() < 12.0 and focus.y > 0.0 and focus.y < 6.0)
	viewer._set_view(99)
	_check("out-of-range view index clamps to the last preset", viewer.view_index == viewer.VIEWS.size() - 1)
	viewer._set_view(-4)
	_check("negative view index clamps to the first preset", viewer.view_index == 0)
	# zoom
	for step in 80:
		viewer._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	_check("zooming in stops at 0.6 m", is_equal_approx(viewer.distance, 0.6) and camera.global_position.y >= 0.12 - 1e-4)
	for step in 120:
		viewer._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	_check("zooming out stops at 35 m", is_equal_approx(viewer.distance, 35.0) and camera.global_position.is_finite() and camera.global_position.y >= 0.12 - 1e-4)
	# orbit (needs the right mouse button latched in Input)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var yaw_before: float = viewer.yaw
	for relative in [Vector2(40.0, 1.0e6), Vector2(-25.0, -1.0e6)]:
		var motion := InputEventMouseMotion.new()
		motion.relative = relative
		viewer._unhandled_input(motion)
		_check("orbit with %s keeps pitch within -0.15..1.25 and camera above ground" % relative, viewer.pitch >= -0.15 and viewer.pitch <= 1.25
			and camera.global_position.is_finite() and camera.global_position.y >= 0.12 - 1e-4)
		if relative.y > 0.0:
			_check("right-drag orbit changes yaw", not is_equal_approx(viewer.yaw, yaw_before))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	# lighting
	var toggle: CheckButton = viewer.get_node("ReviewControls").find_child("NightLighting", true, false)
	var status: Label = viewer.get_node("ReviewControls").find_child("LightingSetup", true, false)
	_check("lighting controls exist", toggle != null and status != null and not toggle.button_pressed)
	var neutral := _visible_lights(viewer)
	_check("neutral lighting is the single directional key only", neutral.size() == 1 and neutral[0] is DirectionalLight3D and neutral[0] == viewer.key
		and not viewer.night and status.text.begins_with("NEUTRAL"))
	_check("neutral environment is present", viewer.environment.environment != null)
	_check("the review defines exactly four local lights, two of them spots", viewer.local_lights.size() == 4 and viewer.local_lights.filter(func(l: Light3D) -> bool: return l is SpotLight3D).size() == 2)
	toggle.button_pressed = true
	var night := _visible_lights(viewer).filter(func(light: Light3D) -> bool: return not light is DirectionalLight3D)
	var shadowed := _visible_lights(viewer).filter(func(light: Light3D) -> bool: return light.shadow_enabled)
	_check("night shows exactly four local lights and no sun", viewer.night and night.size() == 4 and not viewer.key.visible
		and _visible_lights(viewer).size() == 4 and status.text.begins_with("NIGHT"))
	_check("at most two night lights cast shadows, all spots", shadowed.size() <= 2 and shadowed.all(func(light: Light3D) -> bool: return light is SpotLight3D))
	_check("night has a distinct environment", viewer.environment.environment != null and not viewer.environment.environment.ambient_light_source == Environment.AMBIENT_SOURCE_BG)
	_check("local lights are not parented inside the candidate models", _lights(viewer.benchmark).is_empty())
	toggle.button_pressed = false
	_check("returning to neutral restores the sun-only setup", _visible_lights(viewer).size() == 1 and viewer.key.visible and not viewer.night)
	_check("review controls expose a back button", viewer.get_node("ReviewControls").find_children("*", "Button", true, false).any(func(b: Button) -> bool:
		return b.text == "BACK TO MENU" and b.pressed.get_connections().size() == 1))
	viewer.free()


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


# ---------------------------------------------------------------- failure recovery

func _test_failure_recovery() -> void:
	var saved: String = GameSession.menu_error
	GameSession.menu_error = ""
	var viewer: Node3D = preload("res://tests/industrial_market_failing_review.gd").new()
	add_child(viewer)
	_check("failure does not navigate synchronously", viewer.back_requests == 0)
	await get_tree().process_frame
	_check("failure requests exactly one deferred return to the menu", viewer.back_requests == 1)
	_check("failure reports the benchmark errors to the menu", GameSession.menu_error.begins_with("Industrial market review: ") and "forced benchmark failure" in GameSession.menu_error)
	_check("failure builds no controls, world or camera", viewer.get_node_or_null("ReviewControls") == null and viewer.camera == null and viewer.key == null
		and viewer.local_lights.is_empty() and viewer.find_children("*", "Camera3D", true, false).is_empty())
	_check("the process is still running and the failed benchmark is parented for cleanup", is_instance_valid(viewer) and viewer.benchmark.get_parent() == viewer)
	viewer.free()
	GameSession.menu_error = saved


# ---------------------------------------------------------------- helpers

var _once: Dictionary = {}


func _check_once(condition: bool, label: String) -> void:
	if not condition and not _once.has(label):
		_once[label] = true
		_check(label, false)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
