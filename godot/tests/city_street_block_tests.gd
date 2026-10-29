## CityStreetBlock integration regression suite; headless, no rendering.
## Everything is measured from the built scene (batches, stored transforms, real mesh vertices),
## not from the builder's constants, so a layout regression shows up as a failure here.
extends Node3D

const HEROES: Array[String] = ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot"]
const INFILL_IDS: Array[String] = ["shutter_workshop", "ribbed_stack"]
const HERO_SIDES := {"habitation_workshop": -1.0, "market_habitat": 1.0, "service_tenement": -1.0, "freight_depot": 1.0}
const HERO_ROUTES := {"habitation_workshop": 45.0, "market_habitat": 105.0, "service_tenement": 165.0, "freight_depot": 225.0}
const SOLID_KINDS: Array[String] = ["building", "furniture"]
const TRIANGLE_LIMIT := 220000
const BLOCK_BATCH_LIMIT := 24
const BLOCK_SURFACE_LIMIT := 120
const LIGHT_LIMIT := 8
const TOTAL_LIGHT_LIMIT := 12
const ALLEY_HALF_WIDTH := 4.0
const QUARTER_MARGIN := 40.0
const BLOCK_START := 6.0
const BLOCK_END := 282.0
const TOLERANCE := 0.02

var _pass := 0
var _fail := 0
var _course: CourseDefinition
var _vertex_bounds: Dictionary = {}


func _ready() -> void:
	_course = BlockCircuitData.build_course()
	var before := var_to_str(_course.points)
	_test_detectors()
	var host := Node3D.new()
	add_child(host)
	var scenery := CityScenery.build(host, _course)
	var block := scenery.get_node_or_null("CityStreetBlock") as Node3D
	_check("street block is built beside the legacy scenery", block != null and block.get_parent() == scenery and scenery.get_meta("authored_quarter") == true)
	if block != null:
		var placements: Array = block.get_meta("placements", [])
		_test_transforms(block, placements)
		_test_clearance(placements)
		_test_solids(placements)
		_test_coverage(block, placements)
		_test_alleys_and_ramps(placements)
		_test_surfaces(placements)
		_test_budget(block, placements)
		_test_lights_and_culling(scenery, block, placements)
		_test_materials(block)
		_test_no_colliders(block)
		_test_reservations(scenery, block, placements)
		_test_district(scenery, block, placements)
		_test_repeatability(block)
	_test_fallbacks(host)
	_check("course points are unmodified by the street block build", var_to_str(_course.points) == before)
	host.free()
	print("CITY_STREET_BLOCK: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


# --- transforms and metadata -------------------------------------------------------------

func _batches(block: Node3D) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for child in block.get_children():
		if child is MultiMeshInstance3D:
			out.append(child)
	return out


func _test_transforms(block: Node3D, placements: Array) -> void:
	var batches := _batches(block)
	_check("block places a substantive set (%d placements, %d batches)" % [placements.size(), batches.size()], placements.size() >= 150 and batches.size() >= 20)
	var per_asset := {}
	for placement: Dictionary in placements:
		per_asset[placement["asset"]] = int(per_asset.get(placement["asset"], 0)) + 1
	var total := 0
	var upright := true
	var rigid := true
	for batch in batches:
		var id := String(batch.name)
		var stored: Array = batch.get_meta("city_transforms", [])
		total += stored.size()
		_check("%s stores one transform per instance" % id, stored.size() == batch.multimesh.instance_count and stored.size() == int(per_asset.get(id, -1)))
		_check("%s is flagged as a street block piece" % id, batch.has_meta("street_block_piece"))
		var local: AABB = batch.get_meta("city_local_aabb", AABB())
		_check("%s local bounds equal its mesh bounds" % id, _aabb_close(local, batch.multimesh.mesh.get_aabb(), TOLERANCE))
		var real := _mesh_vertex_bounds(batch.multimesh.mesh)
		_check("%s stored local bounds enclose the real vertices" % id, local.grow(TOLERANCE).encloses(real))
		var matched := 0
		for index in stored.size():
			var xf: Transform3D = stored[index]
			# The headless dummy renderer does not retain instance transforms, so the stored
			# city_transforms metadata is the source of truth here; ground boxes are scaled slabs.
			if not id.begins_with("ground_"):
				rigid = rigid and xf.basis.is_conformal()
				upright = upright and xf.basis.y.is_equal_approx(Vector3.UP)
			for placement: Dictionary in placements:
				if placement["asset"] == id and placement["transform"] == xf:
					matched += 1
					# The reported bounds must be what the real vertices occupy after the transform.
					var world := _world_box(xf, real)
					_check_once(_aabb_close(world, placement["bounds"], 0.05) if not id.begins_with("ground_") else placement["bounds"].grow(TOLERANCE).encloses(world),
						"%s reported bounds equal its real transformed vertices" % id, index)
					break
		_check("%s stored transforms equal its placements" % id, matched == stored.size())
	_check("batches hold every placement", total == placements.size())
	_check("every building, furniture and paving piece stands upright and rigid", upright and rigid)
	var moved := placements.filter(func(p: Dictionary) -> bool: return (p["transform"] as Transform3D).origin.length() > 1.0)
	_check("placements are real world positions, not identity", moved.size() == placements.size())


func _test_clearance(placements: Array) -> void:
	var worst := INF
	var disagreements := 0
	var outside := 0
	var nearest_other := INF
	for placement: Dictionary in placements:
		var world := _world_box(placement["transform"], _local_bounds(placement))
		var gap := CityScenery.road_clearance(world, _course)
		worst = minf(worst, gap)
		if placement["kind"] != "ground":
			nearest_other = minf(nearest_other, gap)
		if gap < CityScenery.ROAD_CLEARANCE:
			outside += 1
		if not _gap_agrees(world, gap):
			disagreements += 1
	_check("every block placement clears the full course rail by %.1f m (worst %.2f, %d closer)" % [CityScenery.ROAD_CLEARANCE, worst, outside], outside == 0)
	_check("clearance is measured, not slack: nearest surface sits within 1 m of the limit (%.2f)" % worst, worst < CityScenery.ROAD_CLEARANCE + 1.0)
	_check("independent point sampling agrees with road_clearance (%d disagreements)" % disagreements, disagreements == 0)
	_check("nothing leaves the world limit", placements.all(func(p: Dictionary) -> bool: return not _outside(p["bounds"])))
	_check("raised furniture and buildings start beyond the sidewalk curb (%.1f m)" % nearest_other, nearest_other >= CityScenery.ROAD_CLEARANCE)


func _test_solids(placements: Array) -> void:
	var solids: Array[Dictionary] = []
	for placement: Dictionary in placements:
		if placement["kind"] in SOLID_KINDS:
			solids.append(placement)
	_check("solid set contains buildings and furniture (%d)" % solids.size(), solids.size() > 30)
	var overlaps := 0
	var tightest := INF
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			var gap := _rect_gap(_flat(solids[i]["bounds"]), _flat(solids[j]["bounds"]))
			tightest = minf(tightest, gap)
			if _flat(solids[i]["bounds"]).intersects(_flat(solids[j]["bounds"])):
				overlaps += 1
	_check("no solid building or furniture footprints overlap (%d pairs, tightest %.2f m)" % [overlaps, tightest], overlaps == 0 and tightest >= 0.15)
	# Overhead conduit is an open passage and ground is deliberately layered; they are not solids.
	for placement: Dictionary in placements:
		if placement["kind"] == "overhead":
			_check_once(placement["bounds"].position.y >= -0.01, "conduit stands on the ground", 0)
	var blocked := 0
	for placement: Dictionary in placements:
		if placement["kind"] == "overhead":
			for solid in solids:
				blocked += int(_flat(placement["bounds"]).intersects(_flat(solid["bounds"])))
	_check("overhead conduit leaves the alley floor free of solids (%d)" % blocked, blocked == 0)


func _test_coverage(block: Node3D, placements: Array) -> void:
	var counts := {}
	var kinds := {}
	for placement: Dictionary in placements:
		counts[placement["asset"]] = int(counts.get(placement["asset"], 0)) + 1
		kinds[placement["asset"]] = placement["kind"]
	for id in CityStreetBlock.STREET_IDS:
		_check("street category %s is placed (%d)" % [id, int(counts.get(id, 0))], int(counts.get(id, 0)) >= 1)
	_check("curbs and paving repeat along the block", int(counts.get("curb_segment", 0)) >= 40 and int(counts.get("sidewalk_panel", 0)) >= 8 and int(counts.get("drain_cover", 0)) >= 8)
	_check("lamps, benches and bollards populate both sides", int(counts.get("street_lamp", 0)) >= 4 and int(counts.get("bench_planter", 0)) >= 4 and int(counts.get("bollard", 0)) >= 4)
	_check("each service alley has overhead conduit on both sides (%d)" % int(counts.get("alley_conduit", 0)), int(counts.get("alley_conduit", 0)) == CityStreetBlock.ALLEYS.size() * 2)
	for id in HEROES:
		_check("hero %s appears exactly once (%d)" % [id, int(counts.get(id, 0))], int(counts.get(id, 0)) == 1 and kinds.get(id) == "building")
	var infill := 0
	for id in INFILL_IDS:
		infill += int(counts.get(id, 0))
	_check("budgeted infill uses the existing workshop and ribbed buildings (%d)" % infill, infill >= 1 and infill <= CityStreetBlock.INFILL.size())
	var rejected: Array = block.get_meta("rejected_slots", [])
	for slot: Dictionary in rejected:
		_check_once(slot["asset"] in INFILL_IDS or slot["asset"] in ["refuse_station", "street_lamp", "bench_planter", "bollard"], "rejected slot %s is optional" % slot["asset"], rejected.find(slot))
	for placement: Dictionary in placements:
		if placement["asset"] in HEROES:
			var id: String = placement["asset"]
			var centre: Vector3 = placement["bounds"].get_center()
			var route := _route(centre)
			_check("%s sits near its authored route slot (%.1f vs %.1f)" % [id, route, HERO_ROUTES[id]], absf(route - float(HERO_ROUTES[id])) < 8.0)
			_check("%s faces the road from the %s side" % [id, "left" if float(HERO_SIDES[id]) < 0.0 else "right"], _lateral(centre) * float(HERO_SIDES[id]) > 0.0)
			var frame := _frame(float(HERO_ROUTES[id]))
			var forward: Vector3 = -(placement["transform"] as Transform3D).basis.z
			_check("%s front faces the track" % id, forward.dot(frame["normal"]) * float(HERO_SIDES[id]) < -0.9)
	# the lateral spacing from rail to facade is the same for every hero (consistent street wall)
	var gaps: Array[float] = []
	for placement: Dictionary in placements:
		if placement["asset"] in HEROES:
			gaps.append(CityScenery.road_clearance(placement["bounds"], _course))
	_check("hero facades keep a consistent setback from the rail %s" % [gaps], gaps.size() == 4 and gaps.all(func(g: float) -> bool: return absf(g - gaps[0]) < 1.0 and g >= 11.0 and g <= 14.0))
	for placement: Dictionary in placements:
		var route := _route(placement["bounds"].get_center())
		_check_once(route >= BLOCK_START - 14.0 and route <= BLOCK_END + 14.0, "%s lies inside the 6-282 m block" % placement["asset"], int(route))


func _test_alleys_and_ramps(placements: Array) -> void:
	var alleys: Array[float] = []
	alleys.assign(CityStreetBlock.ALLEYS)
	var violations := 0
	for placement: Dictionary in placements:
		if placement["kind"] in SOLID_KINDS:
			for alley in alleys:
				if _in_alley_opening(placement["bounds"], alley):
					violations += 1
	_check("no solid building or furniture blocks an alley opening (%d)" % violations, violations == 0)
	var curbs := placements.filter(func(p: Dictionary) -> bool: return p["asset"] == "curb_segment")
	var curbs_in_gap := 0
	var before_gap := 0
	var after_gap := 0
	for curb: Dictionary in curbs:
		for alley in alleys:
			var span := _route_span(curb["bounds"])
			if span.y > alley - ALLEY_HALF_WIDTH and span.x < alley + ALLEY_HALF_WIDTH:
				curbs_in_gap += 1
			before_gap += int(span.y <= alley - ALLEY_HALF_WIDTH and span.y > alley - 30.0)
			after_gap += int(span.x >= alley + ALLEY_HALF_WIDTH and span.x < alley + 30.0)
	_check("curb has a break at every service alley on both sides (%d curbs inside)" % curbs_in_gap, curbs_in_gap == 0)
	_check("curb resumes either side of each break (%d before, %d after)" % [before_gap, after_gap], before_gap >= 4 and after_gap >= 4)
	var ramps := placements.filter(func(p: Dictionary) -> bool: return p["asset"] == "ground_alley_entry")
	_check("every alley mouth has a sloped entry on each side (%d)" % ramps.size(), ramps.size() == alleys.size() * 2)
	for ramp: Dictionary in ramps:
		var xf: Transform3D = ramp["transform"]
		var tilt := rad_to_deg(xf.basis.y.angle_to(Vector3.UP))
		_check_once(tilt > 0.5 and tilt < 8.0, "alley entry slopes gently (%.2f deg)" % tilt, int(_route(ramp["bounds"].get_center())))
		var heights := [(xf * Vector3(0.0, 0.5, -0.5)).y, (xf * Vector3(0.0, 0.5, 0.5)).y]
		var low := minf(heights[0], heights[1])
		var high := maxf(heights[0], heights[1])
		_check_once(low < 0.06 and high > 0.15 and high < 0.25, "alley entry rises from gutter (%.3f) to raised paving (%.3f)" % [low, high], int(_route(ramp["bounds"].get_center())))
		var near_route := absf(_route(ramp["bounds"].get_center()) - _nearest(alleys, _route(ramp["bounds"].get_center())))
		_check_once(near_route < 1.0, "alley entry is centred on its alley", int(near_route * 10.0))
	var lanes := placements.filter(func(p: Dictionary) -> bool: return p["asset"] == "ground_alley")
	_check("alley floors run from the sidewalk to the rear lane (%d)" % lanes.size(), lanes.size() == alleys.size() * 2)
	for lane: Dictionary in lanes:
		var span := _lateral_span(lane["bounds"])
		_check_once(span.y - span.x > 40.0, "alley floor is long (%.1f m)" % (span.y - span.x), int(span.x))
	var walks := placements.filter(func(p: Dictionary) -> bool: return p["asset"] == "ground_walk_base")
	var walk_in_alley := 0
	for walk: Dictionary in walks:
		var span := _route_span(walk["bounds"])
		for alley in alleys:
			walk_in_alley += int(span.y > alley - ALLEY_HALF_WIDTH + TOLERANCE and span.x < alley + ALLEY_HALF_WIDTH - TOLERANCE)
	_check("raised sidewalk stops for every alley (%d walks overlap the opening)" % walk_in_alley, walk_in_alley == 0 and walks.size() >= 6)
	# apron continuity: each hero has an entry apron that reaches its base
	var aprons := placements.filter(func(p: Dictionary) -> bool: return p["asset"] == "ground_entry_apron")
	_check("each hero building has an entry apron (%d)" % aprons.size(), aprons.size() == HEROES.size())
	for placement: Dictionary in placements:
		if placement["asset"] in HEROES:
			var base := _lateral_span(placement["bounds"])
			var id: String = placement["asset"]
			var hero_along := _route_span(placement["bounds"])
			var found := false
			for apron: Dictionary in aprons:
				var lateral := _lateral_span(apron["bounds"])
				var along := _route_span(apron["bounds"])
				var shared := minf(along.y, hero_along.y) - maxf(along.x, hero_along.x)
				if shared > 5.0 and _lateral(apron["bounds"].get_center()) * _lateral(placement["bounds"].get_center()) > 0.0:
					found = lateral.y >= base.x - 0.6 and lateral.x <= base.x + 0.05
			_check("%s apron is continuous to the building base (base starts %.2f m from the rail)" % [id, base.x], found)


func _test_surfaces(placements: Array) -> void:
	var grounds := placements.filter(func(p: Dictionary) -> bool: return p["kind"] == "ground")
	for band in ["gutter", "walk_base", "front_path", "yard", "rear_lane", "rear_verge", "alley", "alley_entry", "entry_apron"]:
		var sides := {}
		for ground: Dictionary in grounds:
			if ground["asset"] == "ground_" + band:
				sides[signf(_lateral(ground["bounds"].get_center()))] = true
		_check("ground band %s covers both street sides" % band, sides.size() == 2)
	var coplanar := 0
	for i in grounds.size():
		for j in range(i + 1, grounds.size()):
			var a: Dictionary = grounds[i]
			var b: Dictionary = grounds[j]
			if a["asset"] == "ground_alley_entry" or b["asset"] == "ground_alley_entry":
				continue
			var fa := _flat(a["bounds"]).grow(-0.05)
			var fb := _flat(b["bounds"]).grow(-0.05)
			if fa.size.x > 0.0 and fa.size.z > 0.0 and fb.size.x > 0.0 and fb.size.z > 0.0 and fa.intersects(fb) \
					and absf(a["bounds"].end.y - b["bounds"].end.y) < 0.004:
				coplanar += 1
	_check("overlapping ground layers sit at different heights, no coplanar fighting (%d)" % coplanar, coplanar == 0)
	var tops: Array[float] = []
	for ground: Dictionary in grounds:
		tops.append(ground["bounds"].end.y)
	_check("ground never rises above curb height", tops.all(func(t: float) -> bool: return t < 0.25 and t > -0.05))
	var paving := placements.filter(func(p: Dictionary) -> bool: return p["asset"] == "sidewalk_panel")
	var on_walk := paving.all(func(p: Dictionary) -> bool: return absf(float(p["bounds"].end.y) - 0.18) < 0.03)
	_check("detailed paving panels top out at the raised sidewalk height (%d)" % paving.size(), on_walk and paving.size() >= 8)


func _test_budget(block: Node3D, placements: Array) -> void:
	var sum := 0
	for placement: Dictionary in placements:
		sum += int(placement["tris"])
	var measured := 0
	var draws := 0
	for batch in _batches(block):
		var mesh := batch.multimesh.mesh
		measured += (mesh.get_faces().size() / 3) * batch.multimesh.instance_count
		draws += mesh.get_surface_count()
	_check("placed triangles (%d) stay within %d including infill" % [sum, TRIANGLE_LIMIT], sum <= TRIANGLE_LIMIT and TRIANGLE_LIMIT == CityStreetBlock.TRIANGLE_BUDGET)
	_check("triangle meta equals the placement total", int(block.get_meta("triangle_count", -1)) == sum and int(block.get_meta("triangle_budget", 0)) == TRIANGLE_LIMIT)
	_check("measured mesh triangles (%d) do not exceed the declared total (%d)" % [measured, sum], measured <= sum and measured >= sum * 0.95)
	_check("block batches stay within %d (%d), separate from the legacy and kit budgets" % [BLOCK_BATCH_LIMIT, _batches(block).size()], _batches(block).size() <= BLOCK_BATCH_LIMIT)
	_check("block surface draws stay within %d (%d)" % [BLOCK_SURFACE_LIMIT, draws], draws <= BLOCK_SURFACE_LIMIT)
	var heroes := 0
	for placement: Dictionary in placements:
		if placement["asset"] in HEROES:
			heroes += int(placement["tris"])
	_check("detailed buildings leave headroom for streets and infill (%d of %d)" % [heroes, TRIANGLE_LIMIT], heroes > 0 and heroes < TRIANGLE_LIMIT and sum > heroes)


func _test_lights_and_culling(scenery: Node3D, block: Node3D, placements: Array) -> void:
	var lamps := placements.filter(func(p: Dictionary) -> bool: return p["asset"] == "street_lamp")
	var lights := block.find_children("*", "OmniLight3D", true, false)
	_check("block lights (%d) are bounded by %d and match the lamp count (%d)" % [lights.size(), LIGHT_LIMIT, lamps.size()], lights.size() <= LIGHT_LIMIT and lights.size() == lamps.size() and lights.size() == int(block.get_meta("light_count", -1)))
	var all_lights := scenery.find_children("*", "OmniLight3D", true, false)
	_check("total city lights stay within the %d cap (%d)" % [TOTAL_LIGHT_LIMIT, all_lights.size()], all_lights.size() <= TOTAL_LIGHT_LIMIT and all_lights.size() >= 6)
	_check("every city light is shadowless and no directional or spot lights exist", all_lights.all(func(l: OmniLight3D) -> bool: return not l.shadow_enabled)
		and scenery.find_children("*", "DirectionalLight3D", true, false).is_empty() and scenery.find_children("*", "SpotLight3D", true, false).is_empty())
	for light: OmniLight3D in lights:
		var nearest := INF
		for lamp: Dictionary in lamps:
			var d: Vector3 = light.position - (lamp["transform"] as Transform3D).origin
			nearest = minf(nearest, Vector2(d.x, d.z).length())
		_check_once(nearest < 3.0 and light.position.y > 6.0 and light.position.y < 9.0, "light hangs from its lamp head (%.2f m away)" % nearest, lights.find(light))
		_check_once(light.distance_fade_enabled and light.omni_range <= 40.0, "light fades with distance and stays local", lights.find(light))
	var culled := true
	var shadowless := true
	for batch in _batches(block):
		culled = culled and batch.visibility_range_end > 0.0 and batch.visibility_range_end <= 420.0
		shadowless = shadowless and batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check("every batch has an explicit finite cull distance", culled)
	_check("block batches cast no shadows", shadowless)
	var detail := _batches(block).filter(func(b: MultiMeshInstance3D) -> bool: return b.name in CityStreetBlock.STREET_IDS)
	_check("small street detail culls sooner than buildings", detail.all(func(b: MultiMeshInstance3D) -> bool: return b.visibility_range_end < 300.0))


func _test_materials(block: Node3D) -> void:
	for batch in _batches(block):
		var id := String(batch.name)
		var mesh := batch.multimesh.mesh
		if id.begins_with("ground_"):
			var material := (mesh as PrimitiveMesh).material as ShaderMaterial
			_check("%s uses the procedural ground shader" % id, material != null and material.shader == CityStreetBlock.GROUND_SHADER)
			continue
		var coloured := true
		var materials := true
		var tinted_fill := true
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			coloured = coloured and arrays[Mesh.ARRAY_COLOR] is PackedColorArray and not (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty()
			materials = materials and mesh.surface_get_material(surface) != null
			if id in HEROES or id in CityStreetBlock.STREET_IDS:
				var material := mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null and material.resource_name not in ["glow_cyan", "glow_amber"]:
					tinted_fill = tinted_fill and material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY and material.emission == Color.WHITE
		if id in HEROES or id in CityStreetBlock.STREET_IDS:
			_check("%s keeps its source vertex colours" % id, coloured)
			var base: BaseMaterial3D = mesh.surface_get_material(0) as BaseMaterial3D
			_check("%s renders those colours without mutating shared materials" % id, base != null and base.vertex_color_use_as_albedo)
			_check("%s fill light preserves painted colour and dark sign backings" % id, tinted_fill)
		_check("%s surfaces all carry materials" % id, materials)
	# The legacy kit meshes reused for infill must keep their original shared materials.
	for id in INFILL_IDS:
		var entry: Dictionary = CityKit.entries()[id]
		var mesh := CityKit.mesh(id)
		var intact := true
		for surface in mesh.get_surface_count():
			intact = intact and mesh.surface_get_material(surface) == CityKit.material(String(entry["surfaces"][surface]))
		_check("shared kit mesh %s keeps its semantic materials" % id, intact)


func _test_no_colliders(block: Node3D) -> void:
	var extras := block.find_children("*", "CollisionObject3D", true, false)
	extras.append_array(block.find_children("*", "CollisionShape3D", true, false))
	extras.append_array(block.find_children("*", "Camera3D", true, false))
	extras.append_array(block.find_children("*", "AnimationPlayer", true, false))
	_check("street block has no collision, camera or animation nodes (%d)" % extras.size(), extras.is_empty())


# --- interaction with the older scenery --------------------------------------------------

func _test_reservations(scenery: Node3D, block: Node3D, placements: Array) -> void:
	var reserved: Array = block.get_meta("reserved_bounds", [])
	_check("one reservation per street side", reserved.size() == 2)
	var outside := 0
	for placement: Dictionary in placements:
		if placement["kind"] in ["building", "furniture"]:
			var inside := false
			for box: AABB in reserved:
				inside = inside or _flat(box).encloses(_flat(placement["bounds"]).grow(-0.01))
			outside += int(not inside)
	_check("every block building and prop lies inside a reservation (%d outside)" % outside, outside == 0)
	var road := 0
	for box: AABB in reserved:
		road += int(CityScenery.road_clearance(box, _course) < CityScenery.ROAD_CLEARANCE)
	_check("reservations never claim road clearance", road == 0)
	var old_host := Node3D.new()
	add_child(old_host)
	var old_root := CityScenery.build(old_host, _course, false)
	var quarter := _course.total_length * CityDistrict.FRACTION
	var crossing_before := 0
	var crossing_after := 0
	for piece_name in ["Wall", "Post", "Body", "Rib"]:
		var old_transforms := _legacy_transforms(old_root, piece_name)
		var new_transforms := _legacy_transforms(scenery, piece_name)
		var old_local: AABB = (old_root.get_node(piece_name) as Node3D).get_meta("city_local_aabb", CityScenery.UNIT_BOX)
		var new_local: AABB = (scenery.get_node(piece_name) as Node3D).get_meta("city_local_aabb", CityScenery.UNIT_BOX)
		var old_keys := {}
		for xf: Transform3D in old_transforms:
			old_keys[var_to_str(xf)] = true
			crossing_before += int(_hits_reservation(xf, old_local, reserved))
		var subset := true
		for xf: Transform3D in new_transforms:
			subset = subset and old_keys.has(var_to_str(xf))
			crossing_after += int(_hits_reservation(xf, new_local, reserved))
		_check("%s survivors are a subset of the old build (RNG preserved)" % piece_name, subset)
		# anything outside the replaced quarter and the reservation must survive unchanged
		var new_keys := {}
		for xf: Transform3D in new_transforms:
			new_keys[var_to_str(xf)] = true
		var lost := 0
		for xf: Transform3D in old_transforms:
			if not new_keys.has(var_to_str(xf)) and _route(xf.origin) >= quarter + QUARTER_MARGIN:
				lost += 1
		_check("%s loses nothing beyond the authored quarter (%d lost)" % [piece_name, lost], lost == 0)
	_check("the old build really had scenery on the reserved street (%d) - control" % crossing_before, crossing_before > 0)
	_check("no old-style tower, wall or post remains inside a reservation (%d)" % crossing_after, crossing_after == 0)
	var wall_old := _legacy_transforms(old_root, "Wall").size()
	var wall_new := _legacy_transforms(scenery, "Wall").size()
	_check("near walls were removed by the reservation (%d -> %d)" % [wall_old, wall_new], wall_new < wall_old)
	for piece_name in ["Skyline", "Windows", "CrownRib"]:
		if old_root.has_node(piece_name):
			_check("%s is identical to the old build outside the reservation" % piece_name, scenery.has_node(piece_name) and var_to_str(_legacy_transforms(old_root, piece_name)) == var_to_str(_legacy_transforms(scenery, piece_name)))
	var old_crown := old_root.get_node_or_null("Crown") as Node3D
	var new_crown := scenery.get_node_or_null("Crown") as Node3D
	_check("Crown and its children are unchanged", old_crown != null and new_crown != null and old_crown.position == new_crown.position and old_crown.get_child_count() == new_crown.get_child_count())
	var old_lights := _light_set(old_root, null)
	var new_lights := _light_set(scenery, block)
	var subset_lights := true
	for key: String in new_lights:
		subset_lights = subset_lights and old_lights.has(key)
	_check("remaining legacy lights are a subset of the old lights (%d of %d)" % [new_lights.size(), old_lights.size()], subset_lights)
	_check("legacy plus block lights stay within the shared cap (%d + %d)" % [new_lights.size(), block.find_children("*", "OmniLight3D", true, false).size()],
		new_lights.size() + block.find_children("*", "OmniLight3D", true, false).size() <= TOTAL_LIGHT_LIMIT)
	old_host.free()


func _test_district(scenery: Node3D, block: Node3D, placements: Array) -> void:
	var district := scenery.get_node_or_null("CityKit") as Node3D
	_check("older district still exists beside the block", district != null)
	if district == null:
		return
	var district_pieces: Array = district.get_meta("placements", [])
	var roles := {}
	for piece: Dictionary in district_pieces:
		roles[piece["asset"]] = true
	_check("district keeps all %d older roles in the remaining quarter (%d roles, %d pieces)" % [CityKit.EXPECTED_IDS.size(), roles.size(), district_pieces.size()], roles.size() == CityKit.EXPECTED_IDS.size())
	_check("district keeps its own triangle budget (%d)" % int(district.get_meta("triangle_count")), int(district.get_meta("triangle_count")) <= CityDistrict.TRIANGLE_BUDGET and int(district.get_meta("triangle_budget")) == CityDistrict.TRIANGLE_BUDGET)
	var reserved: Array = block.get_meta("reserved_bounds", [])
	var hits := 0
	var solid_hits := 0
	for piece: Dictionary in district_pieces:
		for box: AABB in reserved:
			hits += int(_flat(box).intersects(_flat(piece["bounds"])))
		for placement: Dictionary in placements:
			if placement["kind"] in SOLID_KINDS:
				solid_hits += int(_flat(placement["bounds"]).intersects(_flat(piece["bounds"])))
	_check("no district piece enters the reservation (%d) or touches a block solid (%d)" % [hits, solid_hits], hits == 0 and solid_hits == 0)
	var block_batches := 0
	for batch in district.find_children("*", "MultiMeshInstance3D", true, false):
		block_batches += int(batch.has_meta("street_block_piece"))
	_check("block pieces are not mixed into the district batches", block_batches == 0)
	var relay: Array = district_pieces.filter(func(p: Dictionary) -> bool: return p["asset"] == "relay_tower")
	_check("relay landmark moved past the block", relay.size() == 1 and float(relay[0]["s"]) > BLOCK_END)


func _test_repeatability(block: Node3D) -> void:
	var first := _signature(block)
	var host := Node3D.new()
	add_child(host)
	var repeat := CityScenery.build(host, _course).get_node("CityStreetBlock") as Node3D
	_check("repeated build produces an identical block", first == _signature(repeat))
	host.free()
	var reversed := CourseCatalog.build_course("block_circuit", true)
	var reverse_host := Node3D.new()
	add_child(reverse_host)
	var reverse_block := CityScenery.build(reverse_host, reversed).get_node_or_null("CityStreetBlock") as Node3D
	_check("reverse direction builds the same canonical block", reverse_block != null and first == _signature(reverse_block))
	reverse_host.free()


# --- fallbacks ---------------------------------------------------------------------------

func _test_fallbacks(host: Node3D) -> void:
	var flagged := CityScenery.build(host, _course, false)
	_check("kit flag off builds no street block, district or reservation", not flagged.has_node("CityStreetBlock") and not flagged.has_node("CityKit") and flagged.get_meta("authored_quarter") == false and flagged.has_node("Wall"))
	var flagged_lights := flagged.find_children("*", "OmniLight3D", true, false).size()
	_check("flag-off scenery keeps its full light budget (%d)" % flagged_lights, flagged_lights >= 6 and flagged_lights <= TOTAL_LIGHT_LIMIT)
	var other := CourseCatalog.build_course("split_shift")
	var other_root := Node3D.new()
	host.add_child(other_root)
	_check("street block refuses non-Block-Circuit courses", CityStreetBlock.build(other_root, other) == null and other_root.get_child_count() == 0)
	var other_scenery := CityScenery.build(host, other)
	_check("other courses get neither street block nor authored district", not other_scenery.has_node("CityStreetBlock") and not other_scenery.has_node("CityKit") and other_scenery.get_meta("authored_quarter") == false)
	var saved: Dictionary = CityKit._entries
	CityKit._entries = {}
	var unavailable := CityScenery.build(host, _course)
	_check("unavailable kit gives the complete old scenery with no block", not unavailable.has_node("CityStreetBlock") and not unavailable.has_node("CityKit") and unavailable.has_node("Body"))
	CityKit._entries = saved
	var old_walls := _legacy_transforms(flagged, "Wall")
	_check("unreserved fallback keeps every old wall", var_to_str(old_walls) == var_to_str(_legacy_transforms(unavailable, "Wall")))
	flagged.free()
	other_scenery.free()
	unavailable.free()
	other_root.free()


# --- detector self-tests (so the checks above can actually fail) --------------------------

func _test_detectors() -> void:
	var mid := CityDistrict.sample(_course, 75.0)
	var pos: Vector3 = mid["pos"]
	var normal := Vector3(-(mid["dir"] as Vector3).z, 0.0, (mid["dir"] as Vector3).x)
	var edge := float(mid["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET
	var in_alley := AABB(pos + normal * (edge + 20.0) - Vector3(1, 0, 1), Vector3(2, 3, 2))
	var beside := AABB(pos + (mid["dir"] as Vector3) * 10.0 + normal * (edge + 20.0) - Vector3(1, 0, 1), Vector3(2, 3, 2))
	_check("detector: a prop on the alley axis blocks the opening", _in_alley_opening(in_alley, 75.0))
	_check("detector: a prop 10 m along the street does not", not _in_alley_opening(beside, 75.0))
	_check("detector: a prop 1 m from the rail fails clearance", CityScenery.road_clearance(AABB(pos + normal * (edge + 1.0) - Vector3(0.5, 0, 0.5), Vector3(1, 3, 1)), _course) < CityScenery.ROAD_CLEARANCE)
	_check("detector: overlapping rects intersect, separated ones do not", _flat(AABB(Vector3.ZERO, Vector3(4, 1, 4))).intersects(_flat(AABB(Vector3(2, 0, 2), Vector3(4, 1, 4)))) and not _flat(AABB(Vector3.ZERO, Vector3(4, 1, 4))).intersects(_flat(AABB(Vector3(5, 0, 0), Vector3(4, 1, 4)))))
	var shifted := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI * 0.5), Vector3(10, 0, 0))
	var rotated := _world_box(shifted, AABB(Vector3(0, 0, 0), Vector3(2, 1, 6)))
	_check("detector: world box follows rotation and offset", _aabb_close(rotated, AABB(Vector3(10, 0, -2), Vector3(6, 1, 2)), 0.001))


# --- helpers -----------------------------------------------------------------------------

func _frame(route: float) -> Dictionary:
	var at := CityDistrict.sample(_course, route)
	var direction: Vector3 = at["dir"]
	return {"pos": at["pos"], "dir": direction, "normal": Vector3(-direction.z, 0.0, direction.x), "edge": float(at["w"]) * 0.5 + TrackBuilder.RAIL_OFFSET}


## Signed distance from the rail edge along the street normal, measured at the box's own route position.
func _lateral(point: Vector3) -> float:
	var frame := _frame(_route(point))
	return (point - (frame["pos"] as Vector3)).dot(frame["normal"])


func _route(point: Vector3) -> float:
	return CityDistrict.route_distance(_course, point)


func _route_span(box: AABB) -> Vector2:
	var low := INF
	var high := -INF
	for corner in 8:
		var s := _route(_corner(box, corner))
		low = minf(low, s)
		high = maxf(high, s)
	return Vector2(low, high)


## Unsigned lateral span measured from the rail edge on whichever side the box stands.
func _lateral_span(box: AABB) -> Vector2:
	var side := signf(_lateral(box.get_center()))
	var low := INF
	var high := -INF
	for corner in 8:
		var point := _corner(box, corner)
		var frame := _frame(_route(point))
		var d := side * (point - (frame["pos"] as Vector3)).dot(frame["normal"]) - float(frame["edge"])
		low = minf(low, d)
		high = maxf(high, d)
	return Vector2(low, high)


func _in_alley_opening(box: AABB, alley: float) -> bool:
	var frame := _frame(alley)
	var along_low := INF
	var along_high := -INF
	var lateral_low := INF
	var lateral_high := -INF
	var side := signf((box.get_center() - (frame["pos"] as Vector3)).dot(frame["normal"]))
	for corner in 8:
		var offset := _corner(box, corner) - (frame["pos"] as Vector3)
		var along := offset.dot(frame["dir"])
		var across := side * offset.dot(frame["normal"]) - float(frame["edge"])
		along_low = minf(along_low, along)
		along_high = maxf(along_high, along)
		lateral_low = minf(lateral_low, across)
		lateral_high = maxf(lateral_high, across)
	return along_high > -ALLEY_HALF_WIDTH + TOLERANCE and along_low < ALLEY_HALF_WIDTH - TOLERANCE \
		and lateral_high > 8.62 and lateral_low < 59.0 and box.position.y < 3.0


func _nearest(values: Array[float], target: float) -> float:
	var best := values[0]
	for value in values:
		if absf(value - target) < absf(best - target):
			best = value
	return best


func _local_bounds(placement: Dictionary) -> AABB:
	return _mesh_vertex_bounds(_mesh_for(placement["asset"]))


func _mesh_for(id: String) -> Mesh:
	var scenery_block := CityStreetBlock._meshes.get(id) as Mesh
	if scenery_block != null:
		return scenery_block
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box


func _mesh_vertex_bounds(mesh: Mesh) -> AABB:
	if _vertex_bounds.has(mesh):
		return _vertex_bounds[mesh]
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for vertex in mesh.get_faces():
		low = Vector3(minf(low.x, vertex.x), minf(low.y, vertex.y), minf(low.z, vertex.z))
		high = Vector3(maxf(high.x, vertex.x), maxf(high.y, vertex.y), maxf(high.z, vertex.z))
	var box := AABB(low, high - low)
	_vertex_bounds[mesh] = box
	return box


func _legacy_transforms(root: Node, node_name: String) -> Array:
	var node := root.get_node_or_null(node_name)
	return node.get_meta("city_transforms", []) if node != null else []


func _hits_reservation(xf: Transform3D, local: AABB, reserved: Array) -> bool:
	var world := _flat(_world_box(xf, local))
	for box: AABB in reserved:
		if _flat(box).intersects(world):
			return true
	return false


func _light_set(root: Node, exclude: Node) -> Dictionary:
	var out := {}
	for light: OmniLight3D in root.find_children("*", "OmniLight3D", true, false):
		if exclude != null and exclude.is_ancestor_of(light):
			continue
		out[var_to_str([light.position, light.light_color, light.omni_range])] = true
	return out


func _signature(block: Node3D) -> Array:
	var out: Array = []
	for placement: Dictionary in block.get_meta("placements", []):
		out.append(var_to_str([placement["asset"], placement["kind"], placement["transform"], placement["bounds"], placement["tris"]]))
	for child in block.get_children():
		if child is MultiMeshInstance3D:
			out.append(var_to_str([child.name, child.multimesh.instance_count, child.get_meta("city_transforms"), child.visibility_range_end]))
		elif child is OmniLight3D:
			out.append(var_to_str([child.position, child.light_color, child.omni_range]))
	out.append(var_to_str(block.get_meta("reserved_bounds", [])))
	out.append(var_to_str(block.get_meta("rejected_slots", [])))
	return out


func _corner(box: AABB, corner: int) -> Vector3:
	return box.position + Vector3(box.size.x * float(corner & 1), box.size.y * float((corner >> 1) & 1), box.size.z * float((corner >> 2) & 1))


func _world_box(xf: Transform3D, local: AABB) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for corner in 8:
		var w := xf.basis * _corner(local, corner) + xf.origin
		low = Vector3(minf(low.x, w.x), minf(low.y, w.y), minf(low.z, w.z))
		high = Vector3(maxf(high.x, w.x), maxf(high.y, w.y), maxf(high.z, w.z))
	return AABB(low, high - low)


func _flat(box: AABB) -> AABB:
	return AABB(Vector3(box.position.x, 0.0, box.position.z), Vector3(box.size.x, 1.0, box.size.z))


func _rect_gap(a: AABB, b: AABB) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.z - b.end.z, b.position.z - a.end.z), 0.0)
	return Vector2(dx, dz).length()


func _aabb_close(a: AABB, b: AABB, tolerance: float) -> bool:
	return a.position.distance_to(b.position) <= tolerance and a.end.distance_to(b.end) <= tolerance


func _outside(world: AABB) -> bool:
	return absf(world.position.x) > CityScenery.WORLD_LIMIT or absf(world.end.x) > CityScenery.WORLD_LIMIT or absf(world.position.z) > CityScenery.WORLD_LIMIT or absf(world.end.z) > CityScenery.WORLD_LIMIT


func _gap_agrees(world: AABB, gap: float) -> bool:
	var low := Vector2(world.position.x, world.position.z)
	var high := Vector2(world.end.x, world.end.z)
	var sampled := INF
	for point: Dictionary in _course.points:
		var p: Vector3 = point["pos"]
		var out := Vector2(maxf(maxf(low.x - p.x, 0.0), p.x - high.x), maxf(maxf(low.y - p.z, 0.0), p.z - high.y))
		sampled = minf(sampled, out.length() - float(point["w"]) * 0.5 - TrackBuilder.RAIL_OFFSET)
	return gap <= sampled + 0.001 and gap >= sampled - 2.3


func _check_once(condition: bool, label: String, index: int) -> void:
	if not condition:
		_check("%s at %d" % [label, index], false)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
