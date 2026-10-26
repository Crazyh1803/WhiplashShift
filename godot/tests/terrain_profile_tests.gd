## Terrain profiles (relief): defaults unchanged, authoring contract, shared mesh/collider, viscera, real traversal.
## `--capture` (rendered, not headless) also saves MUD boulders + ramp screenshots to .ai/captures/terrain-profiles.
extends Node3D

const SPACING := 3.5
const HIGH_MUD := {"shape": "boulders", "preset": "high", "seed": 7}
const RAMP_MAX := {"shape": "ramp", "height": 1.5, "rise": 14.0, "fall": 16.0}

var _pass := 0
var _fail := 0
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	if "--refusal-probe" in OS.get_cmdline_user_args():
		_refusal_probe()
		return
	_test_default_baseline()
	_test_canonical_configs()
	_test_track_build()
	_test_invalid_configs()
	_test_rejections()
	_test_propagation()
	_test_partition_stability()
	_test_samples()
	_test_seed_asymmetry()
	await _test_built_bodies()
	await _test_viscera()
	await _test_traversal()
	if "--capture" in OS.get_cmdline_user_args():
		await _captures()
	print("TERRAIN_PROFILES: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)


# ------------------------------------------------------------------ helpers
## Straight line down -Z. Each part: [point count, surface id, relief Dictionary, width].
func _line(parts: Array) -> Array:
	var pts: Array = []
	for part: Array in parts:
		for _i in int(part[0]):
			var point := {"pos": Vector3(0, 0, -SPACING * pts.size()), "dir": Vector3(0, 0, -1),
				"w": float(part[3]), "s": int(part[1]), "dist": SPACING}
			if not (part[2] as Dictionary).is_empty():
				point["relief"] = (part[2] as Dictionary).duplicate(true)
			pts.append(point)
	return pts


## One relief section between tarmac pads, built like TrackBuilder.build but without the closed-loop wrap.
func _build_line(root: Node3D, pts: Array) -> void:
	var distance := 0.0
	for part: Dictionary in TrackRelief.partition(pts):
		var run: Array = []
		for k in range(int(part["first"]), mini(int(part["last"]) + 2, pts.size())):
			run.append(pts[k])
		TrackBuilder._build_run(root, run, int(part["sid"]), int(part["index"]), distance, true, part["profile"], int(part["piece"]))
		for k in range(int(part["first"]), int(part["last"]) + 1):
			distance += float(pts[k]["dist"])


func _section(sid: int, relief: Dictionary, count: int, width: float = 26.0) -> StaticBody3D:
	var root := Node3D.new()
	add_child(root)
	_build_line(root, _line([[4, Surfaces.Id.TARMAC, {}, width], [count, sid, relief, width], [4, Surfaces.Id.TARMAC, {}, width]]))
	return root.get_child(1)


func _verts(body: StaticBody3D) -> PackedVector3Array:
	var mi: MeshInstance3D = body.get_node("RoadMesh")
	return (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _faces(body: StaticBody3D) -> PackedVector3Array:
	return ((body.get_child(1) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()


func _max_y(verts: PackedVector3Array) -> float:
	var top := -INF
	for v in verts:
		top = maxf(top, v.y)
	return top


func _min_y(verts: PackedVector3Array) -> float:
	var low := INF
	for v in verts:
		low = minf(low, v.y)
	return low


## Height of the triangle mesh under (x, z), or NAN outside it.
func _mesh_height(verts: PackedVector3Array, x: float, z: float) -> float:
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var det := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(det) < 0.000001:
			continue
		var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / det
		var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / det
		var l3 := 1.0 - l1 - l2
		if l1 >= -0.0001 and l2 >= -0.0001 and l3 >= -0.0001:
			return l1 * a.y + l2 * b.y + l3 * c.y
	return NAN


## Max |dh/ds| and |dh/dacross| of the height field on a 0.5 m grid.
func _slopes(prof: Dictionary, width: float, length: float) -> Vector2:
	var step := 0.5
	var worst := Vector2.ZERO
	var s := 0.0
	while s < length:
		var a := -width * 0.5
		while a < width * 0.5:
			var h := TrackRelief.sample(prof, s, a, width, length)
			worst.x = maxf(worst.x, absf(TrackRelief.sample(prof, s + step, a, width, length) - h) / step)
			worst.y = maxf(worst.y, absf(TrackRelief.sample(prof, s, a + step, width, length) - h) / step)
			a += step
		s += step
	return worst


func _max_height(prof: Dictionary, width: float, length: float) -> float:
	var top := 0.0
	var s := 0.0
	while s <= length:
		var a := -width * 0.5
		while a <= width * 0.5:
			top = maxf(top, TrackRelief.sample(prof, s, a, width, length))
			a += 0.5
		s += 0.5
	return top


# ------------------------------------------------------------------ defaults
func _test_default_baseline() -> void:
	# Single source of truth: the baseline script compares against the pre-implementation fixture.
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/terrain_baseline.gd", "--", "--check"], output, true)
	var text := "" if output.is_empty() else String(output[0])
	_check("default circuit hashes match the pre-profile fixture", code == 0 and "TERRAIN_BASELINE: match" in text)
	if code != 0:
		print(text.right(600))
	var plain := TrackRelief.profile(Surfaces.Id.MUD)
	_check("MUD default profile is the original max 0.05", plain["shape"] == "default" and is_equal_approx(plain["max"], 0.05))
	_check("BOULDER medium equals the default profile", TrackRelief.profile(Surfaces.Id.BOULDER, {"shape": "boulders", "preset": "medium"}) == TrackRelief.profile(Surfaces.Id.BOULDER))


# ------------------------------------------------------------------ canonical identity
func _test_canonical_configs() -> void:
	var mud := Surfaces.Id.MUD
	var ramp_default := TrackRelief.key(mud, {"shape": "ramp"})
	_check("ramp defaults equal explicit ints", ramp_default == TrackRelief.key(mud, {"shape": "ramp", "height": 1.2, "rise": 14, "fall": 16}))
	_check("int and float rise share a key", TrackRelief.key(mud, {"shape": "ramp", "rise": 14}) == TrackRelief.key(mud, {"shape": "ramp", "rise": 14.0}))
	_check("option order does not matter", TrackRelief.key(mud, {"fall": 16.0, "shape": "ramp", "rise": 14.0}) == ramp_default)
	_check("submicro rise change is a distinct key", TrackRelief.key(mud, {"shape": "ramp", "rise": 14.0 + 1.0e-9}) != ramp_default)
	_check("submicro height change is a distinct key", TrackRelief.key(mud, {"shape": "ramp", "height": 1.2 + 1.0e-12}) != ramp_default)
	_check("flatten and none are one key", TrackRelief.key(mud, {"shape": "flatten"}) == TrackRelief.key(mud, {"shape": "none"}))
	_check("explicit medium equals omitted preset", TrackRelief.key(mud, {"shape": "boulders"}) == TrackRelief.key(mud, {"shape": "boulders", "preset": "medium"}))
	_check("presets are distinct keys", TrackRelief.key(mud, {"shape": "boulders", "preset": "low"}) != TrackRelief.key(mud, {"shape": "boulders", "preset": "high"}))
	_check("seed changes key", TrackRelief.key(mud, {"shape": "boulders", "seed": 1}) != TrackRelief.key(mud, {"shape": "boulders", "seed": 2}))
	_check("seed 0 differs from no seed", TrackRelief.key(mud, {"shape": "boulders", "seed": 0}) != TrackRelief.key(mud, {"shape": "boulders"}))
	_check("surface is part of the key", TrackRelief.key(Surfaces.Id.GRAVEL, {"shape": "ramp"}) != ramp_default)
	_check("equivalent configs share one normalized profile", TrackRelief.profile(mud, {"shape": "ramp", "rise": 14}) == TrackRelief.profile(mud, {"shape": "ramp"}))


# ------------------------------------------------------------------ invalid shapes
func _test_invalid_configs() -> void:
	var bad: Array = [
		["string", "boulders"], ["null", null], ["array", []], ["unknown shape", {"shape": "cliff"}],
		["non-string shape", {"shape": 3}], ["missing shape", {"height": 1.0}],
		["unknown option", {"shape": "boulders", "bogus": 1}], ["ramp option on boulders", {"shape": "boulders", "height": 1.0}],
		["boulder option on ramp", {"shape": "ramp", "preset": "low"}], ["option on none", {"shape": "none", "seed": 1}],
		["unknown preset", {"shape": "boulders", "preset": "huge"}], ["non-string preset", {"shape": "boulders", "preset": 2}],
		["float seed", {"shape": "boulders", "seed": 1.5}], ["string seed", {"shape": "boulders", "seed": "7"}],
		["height too low", {"shape": "ramp", "height": 0.4}], ["height too high", {"shape": "ramp", "height": 1.51}],
		["nan height", {"shape": "ramp", "height": NAN}], ["inf rise", {"shape": "ramp", "rise": INF}],
		["-inf fall", {"shape": "ramp", "fall": -INF}], ["string rise", {"shape": "ramp", "rise": "14"}],
		["zero rise", {"shape": "ramp", "rise": 0.0}], ["negative fall", {"shape": "ramp", "fall": -4.0}],
		["fall below rise", {"shape": "ramp", "rise": 16.0, "fall": 14.0}],
	]
	for entry: Array in bad:
		_check("rejects " + String(entry[0]), not TrackRelief.config_errors(entry[1]).is_empty())
		_check("invalid profile is flat: " + String(entry[0]), TrackRelief.profile(Surfaces.Id.MUD, entry[1])["shape"] == "invalid")
	_check("empty config is valid", TrackRelief.config_errors({}).is_empty())
	_check("nan height message", "finite" in "; ".join(TrackRelief.config_errors({"shape": "ramp", "height": NAN})))
	_check("fall below rise message", "fall must be at least rise" in "; ".join(TrackRelief.config_errors({"shape": "ramp", "rise": 16.0, "fall": 14.0})))
	var course := CourseDefinition.new().configure("t", "T", "t", 1, _line([[40, Surfaces.Id.MUD, {"shape": "cliff"}, 26.0]]))
	_check("CourseDefinition.validate reports bad relief", "unknown relief shape" in "; ".join(course.validate()))
	_check("invalid profile samples flat", TrackRelief.sample(TrackRelief.profile(Surfaces.Id.MUD, {"shape": "cliff"}), 10.0, 0.0, 26.0, 40.0) == 0.0)


# ------------------------------------------------------------------ ramp footprint rules
func _ramp_errors(pts: Array) -> String:
	return "; ".join(TrackRelief.validation(pts))


func _test_rejections() -> void:
	var pad := [4, Surfaces.Id.TARMAC, {}, 26.0]
	_check("full 1.5 m ramp on 26 m road is accepted", TrackRelief.validation(_line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad])).is_empty())
	_check("medium default ramp is accepted", TrackRelief.validation(_line([pad, [12, Surfaces.Id.MUD, {"shape": "ramp"}, 26.0], pad])).is_empty())
	# docs/terrain-authoring.md promises a 24 m road supports 1.5 m.
	_check("24 m road with 1.5 m ramp is accepted", _ramp_errors(_line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, 24.0], pad])).is_empty())
	var needed := TrackRelief.RAMP_MIN_CREST_WIDTH + 2.0 * TrackRelief.ramp_edge(1.5)
	_check("1.5 m ramp width threshold is between 23 and 24 m (%.3f)" % needed, needed > 23.0 and needed < 24.0)
	_check("width just below the threshold is rejected", "wide" in _ramp_errors(_line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, needed - 0.01], pad])))
	_check("width just above the threshold is accepted", _ramp_errors(_line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, needed + 0.01], pad])).is_empty())
	_check("steep slope rejected", "slope" in _ramp_errors(_line([pad, [12, Surfaces.Id.MUD, {"shape": "ramp", "height": 1.5, "rise": 5.0, "fall": 5.0}, 26.0], pad])))
	_check("slope limit is exact at the boundary", TrackRelief.validation(_line([pad, [12, Surfaces.Id.MUD, {"shape": "ramp", "height": 1.5, "rise": 1.5 * PI / 0.5, "fall": 1.5 * PI / 0.5}, 26.0], pad])).is_empty())
	_check("narrow road rejected", "wide" in _ramp_errors(_line([pad, [12, Surfaces.Id.MUD, {"shape": "ramp"}, 12.0], pad])))
	_check("short tabletop rejected", "tabletop" in _ramp_errors(_line([pad, [9, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad])))
	_check("tabletop of at least 4 m accepted", TrackRelief.validation(_line([pad, [10, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad])).is_empty())
	_check("carried end point narrowing rejected", "wide" in _ramp_errors(_line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], [4, Surfaces.Id.TARMAC, {}, 10.0]])))
	for sid: int in [Surfaces.Id.ICE, Surfaces.Id.OIL]:
		_check("ramp rejected on " + Surfaces.KEYS[sid], "ice or oil" in _ramp_errors(_line([pad, [12, sid, RAMP_MAX, 26.0], pad])))
	var turning := _line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad])
	for i in range(4, 16):
		var angle := deg_to_rad(float(i - 4) * 1.5)
		turning[i]["dir"] = Vector3(sin(angle), 0, -cos(angle))
	_check("turning ramp rejected", "heading" in _ramp_errors(turning))
	var carried := _line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad])
	carried[16]["dir"] = Vector3(sin(deg_to_rad(15.0)), 0, -cos(deg_to_rad(15.0)))
	_check("carried end heading counts", "heading" in _ramp_errors(carried))
	var nonfinite := _line([pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad])
	nonfinite[6]["w"] = NAN
	_check("non-finite point width rejected", not TrackRelief.validation(nonfinite).is_empty())
	_check("boulders on ice are allowed", TrackRelief.validation(_line([pad, [12, Surfaces.Id.ICE, {"shape": "boulders"}, 26.0], pad])).is_empty())


func _test_propagation() -> void:
	var cfg := {"shape": "boulders", "preset": "high"}
	var out: Array = []
	TrackData._straight(out, 0, 0, 35, 0, 26, Surfaces.Id.MUD, cfg)
	_check("_straight carries relief on every node", out.size() > 1 and out.all(func(n: Dictionary) -> bool: return n.get("relief") == cfg))
	_check("_straight copies the config per node", not is_same(out[0]["relief"], cfg) and not is_same(out[0]["relief"], out[1]["relief"]))
	var arc: Array = []
	TrackData._arc(arc, 0, 0, 50, 0.0, 1.0, 26, Surfaces.Id.MUD, cfg)
	_check("_arc carries relief on every node", arc.size() > 1 and arc.all(func(n: Dictionary) -> bool: return n.get("relief") == cfg))
	var plain: Array = []
	TrackData._straight(plain, 0, 0, 35, 0, 26, Surfaces.Id.MUD)
	_check("omitting relief adds no key", plain.all(func(n: Dictionary) -> bool: return not n.has("relief")))


# ------------------------------------------------------------------ TrackBuilder.build entry point
func _invalid_authoring_cases() -> Dictionary:
	var pad := [4, Surfaces.Id.TARMAC, {}, 26.0]
	return {
		# A valid boulder run precedes the bad one, so a partial build would leave children behind.
		"unknown shape late in the track": _line([pad, [12, Surfaces.Id.MUD, HIGH_MUD, 26.0], pad, [12, Surfaces.Id.MUD, {"shape": "cliff"}, 26.0], pad]),
		"ramp on a narrow road late in the track": _line([pad, [12, Surfaces.Id.MUD, HIGH_MUD, 26.0], pad, [12, Surfaces.Id.MUD, RAMP_MAX, 12.0], pad]),
	}


## Child process entry: prints one line per case. The expected push_error stays in the child's output.
func _refusal_probe() -> void:
	var cases := _invalid_authoring_cases()
	for label: String in cases:
		var parent := Node3D.new()
		add_child(parent)
		var built := TrackBuilder.build(parent, cases[label])
		print("REFUSAL_PROBE: %s | built=%s children=%d" % [label, built, parent.get_child_count()])
	get_tree().quit(0)


func _test_track_build() -> void:
	var pad := [4, Surfaces.Id.TARMAC, {}, 26.0]
	var pts := _line([pad, [18, Surfaces.Id.MUD, HIGH_MUD, 26.0], pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad])
	_check("authoring is valid", TrackRelief.validation(pts).is_empty())
	var parent := Node3D.new()
	add_child(parent)
	var parts := TrackRelief.partition(pts)
	_check("TrackBuilder.build accepts valid profiles", TrackBuilder.build(parent, pts))
	_check("build makes one body per partition run (%d)" % parent.get_child_count(), parent.get_child_count() == parts.size())
	var ramp_body: StaticBody3D = parent.get_child(3)
	var boulder_body: StaticBody3D = parent.get_child(1)
	_check("build keeps the ramp surface", ramp_body.get_meta("surface_type") == "mud" and boulder_body.get_meta("surface_type") == "mud")
	_check("build raises the ramp to 1.5 m", absf(_max_y(_verts(ramp_body)) - 1.5) < 0.0001 and _verts(ramp_body) == _faces(ramp_body))
	var high := _max_y(_verts(boulder_body))
	_check("build raises boulders to 0.24..0.30 m (%.3f)" % high, high > 0.24 and high <= 0.3001)
	var flat := Node3D.new()
	add_child(flat)
	_check("relief=false build still succeeds", TrackBuilder.build(flat, pts, false))
	_check("relief=false build is flat", _max_y(_verts(flat.get_child(3))) < 0.0001)
	parent.free()
	flat.free()
	# Invalid authoring must refuse before building anything. The refusal push_error runs in a child
	# process so it cannot be mistaken for a failure of this run.
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/terrain_profile_tests.tscn", "--", "--refusal-probe"], output, true)
	var text := "" if output.is_empty() else String(output[0])
	_check("refusal probe exits cleanly", code == 0)
	_check("refusal reports the expected error", "TrackBuilder refused invalid terrain authoring" in text)
	for label: String in _invalid_authoring_cases():
		_check("refuses %s without building" % label, ("REFUSAL_PROBE: %s | built=false children=0" % label) in text)
	if code != 0:
		print(text.right(600))


# ------------------------------------------------------------------ run splitting
func _test_partition_stability() -> void:
	var mud := Surfaces.Id.MUD
	var with_relief := _line([[6, mud, {}, 26.0], [10, mud, {"shape": "boulders", "preset": "low"}, 26.0], [6, mud, {}, 26.0],
		[5, Surfaces.Id.GRAVEL, {}, 26.0], [6, mud, {}, 26.0], [6, Surfaces.Id.BOULDER, {}, 26.0]])
	var legacy := _line([[6, mud, {}, 26.0], [10, mud, {}, 26.0], [6, mud, {}, 26.0],
		[5, Surfaces.Id.GRAVEL, {}, 26.0], [6, mud, {}, 26.0], [6, Surfaces.Id.BOULDER, {}, 26.0]])
	var split := TrackRelief.partition(with_relief)
	var old := TrackRelief.partition(legacy)
	_check("profile change splits a surface run", split.size() == old.size() + 2)
	_check("profile pieces keep the surface-run index", split[0]["index"] == 0 and split[1]["index"] == 0 and split[2]["index"] == 0)
	_check("pieces count within one surface run", split[0]["piece"] == 0 and split[1]["piece"] == 1 and split[2]["piece"] == 2)
	_check("later runs keep legacy seeds", split[3]["index"] == old[1]["index"] and split[4]["index"] == old[2]["index"] and split[5]["index"] == old[3]["index"])
	_check("legacy list is a single run per surface", old.size() == 4 and old[0]["last"] == 21)
	var lengths := 0.0
	for part: Dictionary in split:
		lengths += float(part["length"])
	_check("partition covers every point once", is_equal_approx(lengths, SPACING * with_relief.size()))


# ------------------------------------------------------------------ height field
func _test_samples() -> void:
	var width := 26.0
	var length := 63.0
	var mud := Surfaces.Id.MUD
	var maxima := {}
	for preset: String in ["low", "medium", "high"]:
		var cap: float = TrackRelief.PRESET_CAPS[preset]
		var prof := TrackRelief.profile(mud, {"shape": "boulders", "preset": preset, "seed": 11})
		var top := _max_height(prof, width, length)
		maxima[preset] = top
		_check("%s boulders stay under %.2f m" % [preset, cap], top <= cap + 0.0001)
		_check("%s boulders really reach most of %.2f m (got %.3f)" % [preset, cap, top], top >= cap * 0.75)
		_check("%s boulders are never negative" % preset, _min_over(prof, width, length) >= 0.0)
		_check_zero_boundary(prof, "%s boulders" % preset, width, length)
	_check("presets are ordered", maxima["low"] < maxima["medium"] and maxima["medium"] < maxima["high"])
	var medium := _slopes(TrackRelief.profile(mud, {"shape": "boulders", "preset": "medium", "seed": 11}), width, length)
	var high := _slopes(TrackRelief.profile(mud, {"shape": "boulders", "preset": "high", "seed": 11}), width, length)
	_check("high slopes are the medium slopes scaled by 1.5", high.x <= medium.x * 1.5 + 0.001 and high.y <= medium.y * 1.5 + 0.001)
	_check("high boulder slopes stay gentle (%.3f/%.3f)" % [high.x, high.y], high.x < 0.35 and high.y < 0.35)
	for dims: Array in [[1.5, 14.0, 16.0], [1.5, 9.5, 9.5], [0.5, 4.0, 4.0], [1.2, 14.0, 16.0]]:
		var ramp := TrackRelief.profile(mud, {"shape": "ramp", "height": dims[0], "rise": dims[1], "fall": dims[2]})
		var ramp_length: float = dims[1] + dims[2] + 4.0
		var tag := "ramp %.1f/%.1f/%.1f" % [dims[0], dims[1], dims[2]]
		_check(tag + " hits its height", is_equal_approx(_max_height(ramp, width, ramp_length + 8.0), dims[0]) or absf(_max_height(ramp, width, ramp_length + 8.0) - dims[0]) < 0.0001)
		var slopes := _slopes(ramp, width, ramp_length + 8.0)
		_check(tag + " along slope <= 0.25 (%.3f)" % slopes.x, slopes.x <= TrackRelief.RAMP_MAX_GRADE + 0.001)
		_check(tag + " lateral slope <= 0.30 (%.3f)" % slopes.y, slopes.y <= 0.30)
		_check_zero_boundary(ramp, tag, width, ramp_length + 8.0)
		_check(tag + " tabletop is flat across the crest", is_equal_approx(TrackRelief.sample(ramp, dims[1] + 2.0, 0.0, width, ramp_length), dims[0]))


func _min_over(prof: Dictionary, width: float, length: float) -> float:
	var low := INF
	var s := 0.0
	while s <= length:
		for a in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			low = minf(low, TrackRelief.sample(prof, s, a, width, length))
		s += 1.0
	return low


func _check_zero_boundary(prof: Dictionary, tag: String, width: float, length: float) -> void:
	var edge_ok := true
	var seam_ok := true
	var s := 0.0
	while s <= length:
		edge_ok = edge_ok and TrackRelief.sample(prof, s, width * 0.5, width, length) == 0.0 and TrackRelief.sample(prof, s, -width * 0.5, width, length) == 0.0
		s += 1.0
	var a := -width * 0.5
	while a <= width * 0.5:
		seam_ok = seam_ok and TrackRelief.sample(prof, 0.0, a, width, length) == 0.0 and TrackRelief.sample(prof, length, a, width, length) == 0.0
		a += 1.0
	_check(tag + " is zero at both road edges", edge_ok)
	_check(tag + " is zero at both run seams", seam_ok)


func _test_seed_asymmetry() -> void:
	var width := 26.0
	var length := 63.0
	var a := TrackRelief.profile(Surfaces.Id.MUD, {"shape": "boulders", "preset": "high", "seed": 42})
	var b := TrackRelief.profile(Surfaces.Id.MUD, {"shape": "boulders", "preset": "high", "seed": 43})
	var same := true
	var differs := false
	var asymmetry := 0.0
	var left := 0.0
	var right := 0.0
	var s := 2.0
	while s < length:
		var u := -12.0
		while u <= 12.0:
			var h := TrackRelief.sample(a, s, u, width, length)
			same = same and h == TrackRelief.sample(a, s, u, width, length, 999)
			differs = differs or absf(h - TrackRelief.sample(b, s, u, width, length)) > 0.001
			asymmetry = maxf(asymmetry, absf(h - TrackRelief.sample(a, s, -u, width, length)))
			if u < 0.0:
				left = maxf(left, h)
			else:
				right = maxf(right, h)
			u += 1.0
		s += 1.5
	_check("explicit seed ignores the run seed and is deterministic", same)
	_check("different seeds give different fields", differs)
	_check("field is not mirror-symmetric (%.3f)" % asymmetry, asymmetry > 0.02)
	_check("rocks sit on both sides of the centreline", left > 0.1 and right > 0.1)
	var plain := TrackRelief.profile(Surfaces.Id.MUD, {"shape": "boulders", "preset": "high"})
	_check("unseeded boulders follow the run seed", _field_sum(plain, width, length, 1) != _field_sum(plain, width, length, 2))


func _field_sum(prof: Dictionary, width: float, length: float, seed: int) -> float:
	var total := 0.0
	var s := 2.0
	while s < length:
		for u in [-9.0, -4.0, 0.0, 4.0, 9.0]:
			total += TrackRelief.sample(prof, s, u, width, length, seed)
		s += 2.0
	return total


# ------------------------------------------------------------------ built bodies
func _test_built_bodies() -> void:
	var root := Node3D.new()
	add_child(root)
	var pad := [4, Surfaces.Id.TARMAC, {}, 26.0]
	_build_line(root, _line([pad, [18, Surfaces.Id.MUD, HIGH_MUD, 26.0], pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad]))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_viewport().world_3d.direct_space_state
	# Grip and material follow `s`, never the relief.
	for sid: int in [Surfaces.Id.MUD, Surfaces.Id.TARMAC]:
		for cfg: Dictionary in [{"shape": "boulders", "preset": "low"}, {"shape": "boulders", "preset": "medium"}, {"shape": "boulders", "preset": "high"}, RAMP_MAX]:
			var body := _section(sid, cfg, 12)
			var tag := "%s %s" % [Surfaces.KEYS[sid], cfg.get("preset", cfg["shape"])]
			_check(tag + " keeps surface id", Surfaces.id_from_key(body.get_meta("surface_type")) == sid)
			_check(tag + " keeps grip", Surfaces.GRIP[Surfaces.id_from_key(body.get_meta("surface_type"))] == Surfaces.GRIP[sid])
			_check(tag + " keeps its material", (body.get_node("RoadMesh") as MeshInstance3D).material_override == TrackMaterials.surface(sid, true))
			_check(tag + " mesh equals collider", _verts(body) == _faces(body) and _verts(body).size() > 0)
			# Fixtures all overlap z 14..56 and the ray test below must only see `root`: free now, flush below.
			body.get_parent().free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ramp_body: StaticBody3D = root.get_child(3)
	var boulder_body: StaticBody3D = root.get_child(1)
	_check("built ramp reaches 1.5 m", absf(_max_y(_verts(ramp_body)) - 1.5) < 0.0001 and absf(_max_y(_faces(ramp_body)) - 1.5) < 0.0001)
	_check("built ramp never dips below the road", _min_y(_verts(ramp_body)) >= 0.0)
	var high := _max_y(_verts(boulder_body))
	_check("built high boulders in 0.24..0.30 m (%.3f)" % high, high > 0.24 and high <= 0.3001)
	for body: StaticBody3D in [boulder_body, ramp_body]:
		var verts := _verts(body)
		_check(String(body.name) + " mesh equals collider", verts == _faces(body))
		_check(String(body.name) + " keeps surface metadata", body.get_meta("surface_type") == "mud")
		var z_lo := INF
		var z_hi := -INF
		for v in verts:
			z_lo = minf(z_lo, v.z)
			z_hi = maxf(z_hi, v.z)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var worst := 0.0
		var hits := 0
		# The builder carries one extra node into the next run, so stay off that overlap.
		var z_end := z_lo + SPACING + 0.5
		for _i in 40:
			var x := rng.randf_range(-12.0, 12.0)
			var z := rng.randf_range(z_end, z_hi - 0.5)
			var expected := _mesh_height(verts, x, z)
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 10.0, z), Vector3(x, -5.0, z))
			var hit := _space.intersect_ray(query)
			_check("%s expected height exists at (%.1f, %.1f)" % [body.name, x, z], not is_nan(expected))
			_check("%s ray hits its own collider at (%.1f, %.1f)" % [body.name, x, z], not hit.is_empty() and hit["collider"] == body)
			if hit.is_empty() or is_nan(expected) or hit["collider"] != body:
				continue
			hits += 1
			# The collider and road mesh are both lifted 0.02 m.
			worst = maxf(worst, absf(float(hit["position"].y) - (expected + 0.02)))
		_check(String(body.name) + " every ray hits (%d/40)" % hits, hits == 40)
		_check(String(body.name) + " ray heights match triangle interpolation (%.5f)" % worst, worst < 0.002)
	root.queue_free()


# ------------------------------------------------------------------ viscera
func _test_viscera() -> void:
	var pad := [4, Surfaces.Id.TARMAC, {}, 26.0]
	var root := Node3D.new()
	add_child(root)
	_build_line(root, _line([pad, [18, Surfaces.Id.MUD, HIGH_MUD, 26.0], pad, [12, Surfaces.Id.MUD, RAMP_MAX, 26.0], pad]))
	var offsets := {"Coils": -0.01, "Organs": -0.015, "Pools": 0.014}
	for entry: Array in [[root.get_child(1), HIGH_MUD], [root.get_child(3), RAMP_MAX]]:
		var body: StaticBody3D = entry[0]
		var cfg: Dictionary = entry[1]
		var start_z := _run_origin_z(body)
		var length: float = SPACING * (18 if cfg == HIGH_MUD else 12)
		var prof := TrackRelief.profile(Surfaces.Id.MUD, cfg)
		var pit := body.get_node_or_null("RoadMesh/VisceraPit")
		_check(String(body.name) + " keeps viscera dressing", pit != null)
		if pit == null:
			continue
		var top := -INF
		var tilted := 0
		var worst_height := 0.0
		var worst_angle := 0.0
		var count := 0
		for batch: MultiMeshInstance3D in pit.get_children():
			var offset: float = offsets[String(batch.name)]
			for xf: Transform3D in batch.get_meta("cpu_transforms"):
				var s := start_z - xf.origin.z
				var u := -xf.origin.x
				var h := TrackRelief.sample(prof, s, u, 26.0, length)
				worst_height = maxf(worst_height, absf(xf.origin.y - (h + offset)))
				top = maxf(top, xf.origin.y)
				var expected := Vector3((TrackRelief.sample(prof, s, u + 1.0, 26.0, length) - TrackRelief.sample(prof, s, u - 1.0, 26.0, length)) * 0.5,
					1.0, (TrackRelief.sample(prof, s + 1.0, u, 26.0, length) - TrackRelief.sample(prof, s - 1.0, u, 26.0, length)) * 0.5).normalized()
				var angle := xf.basis.y.normalized().angle_to(expected)
				worst_angle = maxf(worst_angle, angle)
				if xf.basis.y.normalized().angle_to(Vector3.UP) > 0.05:
					tilted += 1
				count += 1
		_check(String(body.name) + " has many ornaments (%d)" % count, count > 40)
		_check(String(body.name) + " ornaments ride the height field (%.4f)" % worst_height, worst_height < 0.004)
		_check(String(body.name) + " ornaments tilt onto the surface (%.3f rad)" % worst_angle, worst_angle < 0.02)
		_check(String(body.name) + " some ornaments are visibly tilted (%d)" % tilted, tilted > 0)
		if cfg == RAMP_MAX:
			_check("ramp ornaments reach the tabletop (%.2f)" % top, top > 1.3)
	root.queue_free()
	await get_tree().process_frame


## z at which the body's run begins (its first vertex row).
func _run_origin_z(body: StaticBody3D) -> float:
	var z_hi := -INF
	for v in _verts(body):
		z_hi = maxf(z_hi, v.z)
	return z_hi


# ------------------------------------------------------------------ real vehicle traversal
## Screenshot-only combined track (the traversal tests drive each feature on its own track).
func _capture_track(root: Node3D) -> float:
	var pad := [12, Surfaces.Id.TARMAC, {}, 26.0]
	var pts := _line([pad, [18, Surfaces.Id.MUD, HIGH_MUD, 26.0], [4, Surfaces.Id.TARMAC, {}, 26.0],
		[12, Surfaces.Id.MUD, RAMP_MAX, 26.0], [20, Surfaces.Id.TARMAC, {}, 26.0]])
	_build_line(root, pts)
	return SPACING * (12 + 18 + 4 + 12)


const RUN_UP := 24
const EXIT_TARMAC := 48
const SUPPORT_WINDOW := 2.0
const SUPPORT_WHEELS := 3
const SUPPORT_TICKS := 15


## One feature between a run-up and a tarmac exit, so neither feature drains speed before the other.
## Returns {start, end, length} as positive distances down -Z.
func _feature_track(root: Node3D, cfg: Dictionary, count: int) -> Dictionary:
	var pts := _line([[RUN_UP, Surfaces.Id.TARMAC, {}, 26.0], [count, Surfaces.Id.MUD, cfg, 26.0], [EXIT_TARMAC, Surfaces.Id.TARMAC, {}, 26.0]])
	_build_line(root, pts)
	return {"start": SPACING * RUN_UP, "end": SPACING * (RUN_UP + count), "length": SPACING * pts.size()}


func _test_traversal() -> void:
	var features := {"high boulders": [HIGH_MUD, 18], "1.5 m ramp": [RAMP_MAX, 12]}
	for feature: String in features:
		var root := Node3D.new()
		add_child(root)
		var track := _feature_track(root, features[feature][0], features[feature][1])
		await get_tree().physics_frame
		await get_tree().physics_frame
		_space = get_viewport().world_3d.direct_space_state
		for speed: float in [15.0, 30.0, 50.0]:
			for end: String in ["A", "B"]:
				var r := await _drive(root, speed, end, track)
				var tag := "%s End %s @%dm/s" % [feature, end, int(speed)]
				print("TERRAIN_PROFILES: %s -> entry %.1f m/s, min in feature %.1f, finite %s clearance %.2f tilt %.1f lane %.1f nohit %d reached %s support %s (at %.2fs) frames %d last z %.1f speed %.1f" % [
					tag, r["entry"], r["min_speed"], r["finite"], r["clearance"], r["tilt"], r["lane"], r["nohit"], r["reached"],
					r["support"], r["support_time"], r["frames"], r["z"], r["speed"]])
				_check(tag + " enters at speed (%.1f of %.0f)" % [r["entry"], speed], r["entry"] >= speed * 0.85)
				_check(tag + " pose stays finite", r["finite"])
				_check(tag + " ground ray always hits inside the footprint (%d misses)" % r["nohit"], r["nohit"] == 0)
				_check(tag + " never sinks or tunnels (clearance %.2f)" % r["clearance"], r["clearance"] > 0.05)
				_check(tag + " tilt stays bounded (%.1f)" % r["tilt"], r["tilt"] < 50.0)
				_check(tag + " stays on the road (%.1f)" % r["lane"], r["lane"] < 11.5)
				_check(tag + " clears the feature and the support window", r["reached"])
				_check(tag + " regains %d wheels of support within %.0f s of the exit" % [SUPPORT_WHEELS, SUPPORT_WINDOW], r["support"])
		root.free()
		await get_tree().process_frame


## Drives one blackjack end through `track` ({start, end, length}) holding `speed` and the lane centre.
## Steering is the car's own input (positive = right, i.e. world +x while heading -Z); nothing
## writes position or velocity after the spawn. Support = SUPPORT_WHEELS wheels in contact for SUPPORT_TICKS
## consecutive ticks within SUPPORT_WINDOW seconds of leaving the feature.
func _drive(root: Node3D, speed: float, end: String, track: Dictionary) -> Dictionary:
	var car := preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle("blackjack"))
	car.active_end = end
	root.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, PI if end == "B" else 0.0), Vector3(0, 1.0, -8.0))
	car.linear_velocity = Vector3(0, 0, -speed)
	var result := {"finite": true, "clearance": INF, "tilt": 0.0, "lane": 0.0, "reached": false, "support": false,
		"support_time": -1.0, "frames": 0, "entry": 0.0, "min_speed": INF, "nohit": 0, "z": 0.0, "speed": 0.0}
	var ticks := float(Engine.physics_ticks_per_second)
	var window := int(SUPPORT_WINDOW * ticks)
	var entered := false
	var after := -1
	var streak := 0
	for frame in int(40.0 * ticks):
		var forward := car.forward_vector()
		var steer := -(0.04 * car.global_position.x + 1.2 * forward.x) / (1.0 + car.fwd_speed / 25.0)
		car.steer = clampf(steer, -0.6, 0.6)
		car.throttle = clampf((speed - car.fwd_speed) * 0.5, 0.0, 1.0)
		car.brake = 0.0
		await get_tree().physics_frame
		result["frames"] = frame
		var chassis := car.global_basis
		if not (car.global_position.is_finite() and chassis.determinant() == chassis.determinant() and car.linear_velocity.is_finite()):
			result["finite"] = false
			break
		result["z"] = car.global_position.z
		result["speed"] = car.fwd_speed
		# Range is far larger than the car can sink, so a miss means it left the ground, not that the ray is short.
		var query := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * 4.0, car.global_position + Vector3.DOWN * 40.0, 0xFFFFFFFF, [car.get_rid()])
		var hit := _space.intersect_ray(query)
		var inside: bool = car.global_position.z > -float(track["length"]) and car.global_position.z < 0.0
		if hit.is_empty():
			if inside:
				result["nohit"] += 1
		else:
			result["clearance"] = minf(result["clearance"], car.global_position.y - float(hit["position"].y))
		result["tilt"] = maxf(result["tilt"], rad_to_deg(chassis.y.angle_to(Vector3.UP)))
		result["lane"] = maxf(result["lane"], absf(car.global_position.x))
		var z: float = -car.global_position.z
		if not entered and z >= float(track["start"]):
			entered = true
			result["entry"] = car.fwd_speed
		if entered and after < 0:
			result["min_speed"] = minf(result["min_speed"], car.fwd_speed)
			if z >= float(track["end"]):
				after = frame
		if after >= 0:
			var touching := 0
			for wheel: Wheel in car.wheels:
				touching += 1 if wheel.contact else 0
			streak = streak + 1 if touching >= SUPPORT_WHEELS else 0
			if streak >= SUPPORT_TICKS and not result["support"]:
				result["support"] = true
				result["support_time"] = float(frame - after) / ticks
			if frame >= after + window:
				result["reached"] = true
				break
	root.remove_child(car)
	car.free()
	await get_tree().process_frame
	return result


# ------------------------------------------------------------------ optional screenshots
func _captures() -> void:
	var root := Node3D.new()
	add_child(root)
	var ramp_end := _traversal_track(root)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	root.add_child(env)
	var camera := Camera3D.new()
	camera.far = 600
	root.add_child(camera)
	camera.current = true
	var path := ProjectSettings.globalize_path("res://../.ai/captures/terrain-profiles")
	DirAccess.make_dir_recursive_absolute(path)
	var views := {
		"mud-boulders": [Vector3(9, 3.2, -40), Vector3(0, 0, -78)],
		"mud-ramp": [Vector3(10, 3.5, -102), Vector3(0, 0.8, -128)],
		"overview": [Vector3(28, 34, -50), Vector3(0, 0, -100)],
	}
	for label: String in views:
		camera.global_position = views[label][0]
		camera.look_at(views[label][1], Vector3.UP)
		for _f in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var saved := get_viewport().get_texture().get_image().save_png(path.path_join(label + ".png"))
		_check(label + " screenshot saved", saved == OK)
	root.queue_free()
	_check("capture track spans the ramp", ramp_end > 100.0)
