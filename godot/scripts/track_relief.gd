## Shared metre-space road/collision relief. Positive heights stay above the global floor.
class_name TrackRelief
extends RefCounted

const MAX_HEIGHTS := {Surfaces.Id.GRAVEL: 0.03, Surfaces.Id.MUD: 0.05,
	Surfaces.Id.BOULDER: 0.20, Surfaces.Id.WATER: 0.02}
const END_FADE := 3.5
const EDGE_FADE := 3.0
const ROCK_ROW := 5.0
const ROCK_LANE := 3.9
const LARGE_ROCK_CHANCE := 0.4


## Opt-in authoring profiles. A point may carry `"relief": {...}`; absent or empty keeps the
## surface's built-in relief. Shapes: boulders (+preset, +seed), ramp (+height/rise/fall), none/flatten.
const PRESET_CAPS := {"low": 0.12, "medium": 0.20, "high": 0.30}
const BOULDER_BASE_CAP := 0.20
const RAMP_DEFAULTS := {"height": 1.2, "rise": 14.0, "fall": 16.0}
const RAMP_MIN_HEIGHT := 0.5
const RAMP_MAX_HEIGHT := 1.5
const RAMP_MIN_CREST := 8.0
const RAMP_MAX_GRADE := 0.25
const RAMP_LATERAL_GRADE := 0.28
const RAMP_MAX_TURN_DEG := 8.0
const _KEYS_BY_SHAPE := {"boulders": ["shape", "preset", "seed"], "ramp": ["shape", "height", "rise", "fall"],
	"none": ["shape"], "flatten": ["shape"]}


static func enabled(sid: int) -> bool:
	return MAX_HEIGHTS.has(sid)


## Errors for one point's `relief` value; empty when it is valid (an empty dictionary is valid).
static func config_errors(relief: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(relief) != TYPE_DICTIONARY:
		errors.append("relief must be a Dictionary")
		return errors
	var cfg: Dictionary = relief
	if cfg.is_empty():
		return errors
	if not cfg.has("shape") or typeof(cfg["shape"]) != TYPE_STRING:
		errors.append("relief.shape must be a String")
		return errors
	var shape: String = cfg["shape"]
	if not _KEYS_BY_SHAPE.has(shape):
		errors.append("unknown relief shape '%s'" % shape)
		return errors
	for option in cfg:
		if typeof(option) != TYPE_STRING or not (option in _KEYS_BY_SHAPE[shape]):
			errors.append("unknown relief option '%s' for shape '%s'" % [str(option), shape])
	if shape == "boulders":
		if cfg.has("preset") and (typeof(cfg["preset"]) != TYPE_STRING or not PRESET_CAPS.has(cfg["preset"])):
			errors.append("unknown boulder preset '%s'" % str(cfg["preset"]))
		if cfg.has("seed") and typeof(cfg["seed"]) != TYPE_INT:
			errors.append("relief.seed must be an int")
	elif shape == "ramp":
		for option: String in RAMP_DEFAULTS:
			if cfg.has(option) and not _finite_number(cfg[option]):
				errors.append("relief.%s must be a finite number" % option)
		if errors.is_empty():
			var ramp_height := float(cfg.get("height", RAMP_DEFAULTS["height"]))
			if ramp_height < RAMP_MIN_HEIGHT or ramp_height > RAMP_MAX_HEIGHT:
				errors.append("ramp height must be %.1f to %.1f m" % [RAMP_MIN_HEIGHT, RAMP_MAX_HEIGHT])
			if float(cfg.get("rise", RAMP_DEFAULTS["rise"])) <= 0.0 or float(cfg.get("fall", RAMP_DEFAULTS["fall"])) <= 0.0:
				errors.append("ramp rise and fall must be positive")
	return errors


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


## Canonical profile for a surface plus optional config. Equivalent configs yield equal dictionaries.
## Invalid config gives shape "invalid", which samples as flat; callers validate first.
static func profile(sid: int, relief: Variant = {}) -> Dictionary:
	if not config_errors(relief).is_empty():
		return {"sid": sid, "shape": "invalid", "max": 0.0}
	var cfg: Dictionary = relief
	if cfg.is_empty():
		return _default_profile(sid)
	match String(cfg["shape"]):
		"none", "flatten":
			return {"sid": sid, "shape": "none", "max": 0.0}
		"boulders":
			var preset := String(cfg.get("preset", "medium"))
			if sid == Surfaces.Id.BOULDER and preset == "medium" and not cfg.has("seed"):
				return _default_profile(sid)
			var cap: float = PRESET_CAPS[preset]
			var result := {"sid": sid, "shape": "boulders", "preset": preset,
				"scale": cap / BOULDER_BASE_CAP, "max": cap}
			if cfg.has("seed"):
				result["seed"] = int(cfg["seed"])
			return result
	var height: float = float(cfg.get("height", RAMP_DEFAULTS["height"]))
	return {"sid": sid, "shape": "ramp", "height": height, "max": height,
		"rise": float(cfg.get("rise", RAMP_DEFAULTS["rise"])), "fall": float(cfg.get("fall", RAMP_DEFAULTS["fall"]))}


static func _default_profile(sid: int) -> Dictionary:
	if enabled(sid):
		return {"sid": sid, "shape": "default", "max": float(MAX_HEIGHTS[sid])}
	return {"sid": sid, "shape": "none", "max": 0.0}


## Stable text identity of surface + normalized profile; runs split where it changes.
static func key(sid: int, relief: Variant = {}) -> String:
	var p := profile(sid, relief)
	match String(p["shape"]):
		"boulders":
			return "%d:boulders:%s:%s" % [sid, p["preset"], str(p["seed"]) if p.has("seed") else "run"]
		"ramp":
			return "%d:ramp:%.6f:%.6f:%.6f" % [sid, p["height"], p["rise"], p["fall"]]
	return "%d:%s" % [sid, p["shape"]]


## True when the profile produces raised geometry.
static func active(prof: Dictionary) -> bool:
	return String(prof.get("shape", "none")) in ["default", "boulders", "ramp"]


static func _dense(prof: Dictionary) -> bool:
	return prof["shape"] == "boulders" or (prof["shape"] == "default" and prof["sid"] == Surfaces.Id.BOULDER)


## Lateral distance over which a ramp falls from full height to the road edge.
static func ramp_edge(ramp_height: float) -> float:
	return ramp_height * PI / (2.0 * RAMP_LATERAL_GRADE)


## Surface runs exactly as the builder cuts them: split by surface and normalized profile.
## `index` counts surface runs only (the historic seed); `piece` counts profile pieces within one.
static func partition(pts: Array) -> Array:
	var out: Array = []
	var n := pts.size()
	var i := 0
	while i < n:
		var sid: int = pts[i].get("s", 0)
		var run_key := key(sid, pts[i].get("relief", {}))
		var j := i
		var length: float = float(pts[i].get("dist", 0.0))
		while j + 1 < n and int(pts[j + 1].get("s", 0)) == sid and key(sid, pts[j + 1].get("relief", {})) == run_key:
			j += 1
			length += float(pts[j].get("dist", 0.0))
		var index := 0
		var piece := 0
		if not out.is_empty():
			var last: Dictionary = out[-1]
			index = last["index"] if last["sid"] == sid else int(last["index"]) + 1
			piece = int(last["piece"]) + 1 if last["sid"] == sid else 0
		out.append({"first": i, "last": j, "sid": sid, "key": run_key, "index": index, "piece": piece,
			"length": length, "profile": profile(sid, pts[i].get("relief", {}))})
		i = j + 1
	return out


## All authoring problems in a point list (config shape plus per-run ramp constraints).
static func validation(points: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for i in points.size():
		if typeof(points[i]) != TYPE_DICTIONARY:
			return errors
		if points[i].has("relief"):
			for message in config_errors(points[i]["relief"]):
				errors.append("point %d: %s" % [i, message])
	if not errors.is_empty():
		return errors
	for run: Dictionary in partition(points):
		var prof: Dictionary = run["profile"]
		if prof["shape"] != "ramp":
			continue
		var label := "ramp at points %d-%d" % [run["first"], run["last"]]
		if run["sid"] == Surfaces.Id.ICE or run["sid"] == Surfaces.Id.OIL:
			errors.append("%s: ramps are not allowed on ice or oil" % label)
		var h: float = prof["height"]
		var min_span := h * PI / (2.0 * RAMP_MAX_GRADE)
		if prof["rise"] < min_span - 0.0001 or prof["fall"] < min_span - 0.0001:
			errors.append("%s: rise and fall must be at least %.2f m for %.2f m height (slope <= %.2f)" % [label, min_span, h, RAMP_MAX_GRADE])
		if run["length"] < prof["rise"] + prof["fall"] + RAMP_MIN_CREST:
			errors.append("%s: run is %.1f m, needs rise + fall + %.0f m flat crest" % [label, run["length"], RAMP_MIN_CREST])
		var min_width := INF
		var first_dir := Vector3.ZERO
		var worst_turn := 0.0
		for k in range(int(run["first"]), int(run["last"]) + 1):
			var point: Dictionary = points[k]
			min_width = minf(min_width, float(point.get("w", 0.0)))
			var dir: Vector3 = point.get("dir", Vector3.ZERO)
			if first_dir == Vector3.ZERO:
				first_dir = dir
			elif first_dir.length_squared() > 0.0 and dir.length_squared() > 0.0:
				worst_turn = maxf(worst_turn, rad_to_deg(first_dir.angle_to(dir)))
		if min_width < 2.0 * ramp_edge(h):
			errors.append("%s: road is %.1f m wide, needs %.1f m for lateral slope <= %.2f" % [label, min_width, 2.0 * ramp_edge(h), RAMP_LATERAL_GRADE])
		if worst_turn > RAMP_MAX_TURN_DEG:
			errors.append("%s: heading changes %.1f degrees, max %.0f (ramps must be straight)" % [label, worst_turn, RAMP_MAX_TURN_DEG])
	return errors


## Height under a normalized profile. `seed` is the surface-run seed unless the profile carries its own.
static func sample(prof: Dictionary, s: float, across: float, width: float, length: float, seed: int = 0) -> float:
	var shape := String(prof.get("shape", "none"))
	if shape == "default":
		return _default(int(prof["sid"]), s, across, width, length, seed)
	if shape != "boulders" and shape != "ramp":
		return 0.0
	var edge := width * 0.5 - absf(across)
	if s <= 0.0 or s >= length or edge <= 0.0:
		return 0.0
	if shape == "boulders":
		var fade := smoothstep(0.0, END_FADE, minf(s, length - s)) * smoothstep(0.0, EDGE_FADE, edge)
		return _boulders(s, across, width, length, int(prof.get("seed", seed)), float(prof["scale"])) * fade
	var rise: float = prof["rise"]
	var fall: float = prof["fall"]
	var along := 1.0
	if s < rise:
		along = 0.5 - 0.5 * cos(PI * s / rise)
	if length - s < fall:
		along = minf(along, 0.5 - 0.5 * cos(PI * (length - s) / fall))
	var lateral := 0.5 - 0.5 * cos(PI * clampf(edge / ramp_edge(prof["height"]), 0.0, 1.0))
	return float(prof["height"]) * along * lateral


static func height(sid: int, s: float, across: float, width: float, length: float, seed: int = 0, prof: Dictionary = {}) -> float:
	if prof.is_empty():
		return _default(sid, s, across, width, length, seed)
	return sample(prof, s, across, width, length, seed)


static func _default(sid: int, s: float, across: float, width: float, length: float, seed: int) -> float:
	if not enabled(sid):
		return 0.0
	var edge := width * 0.5 - absf(across)
	if s <= 0.0 or s >= length or edge <= 0.0:
		return 0.0
	var fade := smoothstep(0.0, END_FADE, minf(s, length - s)) * smoothstep(0.0, EDGE_FADE, edge)
	if sid == Surfaces.Id.BOULDER:
		return _boulders(s, across, width, length, seed) * fade
	var phase := float(posmod(seed * 17 + sid * 31, 97)) * 0.1
	var frequency := 0.3 if sid == Surfaces.Id.GRAVEL else 0.2
	if sid == Surfaces.Id.WATER:
		frequency = 0.15
	# Broad swells avoid exciting the suspension near its natural frequency.
	var profile := 0.5 + 0.25 * cos(s * frequency + phase) + 0.25 * cos(across * 0.7)
	return float(MAX_HEIGHTS[sid]) * profile * fade


static func _rand(state: int) -> int:
	return (state * 48271) % 2147483647


## Every rock has its own seeded signed lateral centre and longitudinal offset; slots only stratify the full width.
## Rock heights scale with footprint so gradients stay bounded, and taper near ends/edges so the fades stay safe.
static func _boulders(s: float, across: float, width: float, length: float, seed: int, scale: float = 1.0) -> float:
	var half := width * 0.5
	var slots := maxi(3, roundi(width / ROCK_LANE))
	var slot_width := width / float(slots)
	var end_taper := lerpf(0.5, 1.0, smoothstep(END_FADE, END_FADE + 5.0, minf(s, length - s)))
	var edge_taper := lerpf(0.68, 1.0, smoothstep(EDGE_FADE, EDGE_FADE + 4.5, half - absf(across)))
	var base_row := floori(s / ROCK_ROW)
	var peak := 0.0
	for row in range(base_row - 3, base_row + 4):
		for slot in range(0, slots):
			var state := posmod(row * 73856093 ^ slot * 19349663 ^ seed * 83492791, 2147483646) + 1
			state = _rand(_rand(state))
			var center_s := (float(row) + 0.5 + (float(state) / 2147483647.0 - 0.5) * 1.1) * ROCK_ROW
			if absf(s - center_s) > 10.0:
				continue
			state = _rand(state)
			var center_u := -half + (float(slot) + 0.5 + (float(state) / 2147483647.0 - 0.5) * 0.95) * slot_width
			center_u = clampf(center_u, -half + 3.4, half - 3.4)
			state = _rand(state)
			var radius_s := 4.2 + 2.8 * float(state) / 2147483647.0
			state = _rand(state)
			var radius_u := 4.6 + 2.4 * float(state) / 2147483647.0
			state = _rand(state)
			var variation := float(state) / 2147483647.0
			state = _rand(state)
			var diamond := 0.70 + 0.04 * float(state) / 2147483647.0
			# Full-sized rocks use a wider footprint (not steeper slopes) to reach the accepted 0.16-0.20 m crowns.
			var slope := 0.026
			state = _rand(state)
			if float(state) / 2147483647.0 < LARGE_ROCK_CHANCE:
				radius_s = 8.0 + 1.5 * (radius_s - 4.2) / 2.8
				radius_u = 10.5 + 1.5 * (radius_u - 4.6) / 2.4
				variation = 0.9 + 0.1 * variation
				slope = 0.0245
			var crown := minf(0.2 * (0.6 + 0.4 * variation), slope * minf(radius_s, radius_u))
			var dx := absf(s - center_s) / radius_s
			var dy := absf(across - center_u) / radius_u
			var footprint := maxf(maxf(dx, dy), (dx + dy) * diamond)
			if footprint < 1.0:
				var crown_radius := maxf(0.0, (footprint - 0.12) / 0.88)
				var dome := 0.5 + 0.5 * cos(PI * crown_radius)
				peak = maxf(peak, crown * dome * dome)
	# Presets scale heights (and so gradients) uniformly; medium is exactly 1.0.
	return peak * end_taper * edge_taper * scale


## Subdivide the original quad, retaining its exact boundary and winding.
static func append_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, widths: PackedVector2Array, a: Dictionary, b: Dictionary,
		sid: int, distance: float, run_start: float, run_length: float, seed: int, prof: Dictionary = {}) -> void:
	if prof.is_empty():
		prof = _default_profile(sid)
	var dense := _dense(prof)
	var maximum: float = prof["max"]
	var an: Vector3 = Vector3(-a["dir"].z, 0, a["dir"].x) * (float(a["w"]) * 0.5)
	var bn: Vector3 = Vector3(-b["dir"].z, 0, b["dir"].x) * (float(b["w"]) * 0.5)
	var al: Vector3 = a["pos"] + an
	var ar: Vector3 = a["pos"] - an
	var bl: Vector3 = b["pos"] + bn
	var br: Vector3 = b["pos"] - bn
	var spacing := 0.6 if dense else 0.9
	var steps := maxi(1, ceili(float(a["dist"]) / spacing))
	var lane_width := 0.8 if dense else 2.5
	var lanes := clampi(ceili(maxf(a["w"], b["w"]) / lane_width), 8, 48 if dense else 16)
	for row in steps:
		for lane in lanes:
			var corners: Array[Vector2] = [Vector2(float(lane) / lanes, float(row) / steps),
				Vector2(float(lane + 1) / lanes, float(row) / steps),
				Vector2(float(lane) / lanes, float(row + 1) / steps),
				Vector2(float(lane + 1) / lanes, float(row + 1) / steps)]
			var positions: Array[Vector3] = []
			var heights: Array[float] = []
			for corner in corners:
				var width := lerpf(a["w"], b["w"], corner.y)
				var s := distance + float(a["dist"]) * corner.y
				var across := (corner.x - 0.5) * width
				var p := al.lerp(ar, corner.x).lerp(bl.lerp(br, corner.x), corner.y)
				var h := sample(prof, s - run_start, across, width, run_length, seed)
				p.y += h
				positions.append(p)
				# Overridden profiles may exceed the surface's own cap; normalise by the profile maximum.
				heights.append(h / maximum if prof["shape"] == "default" else minf(h / maximum, 1.0))
			for tri: Array in [[0, 1, 2], [2, 1, 3]]:
				# Godot's front-face winding is opposite the geometric cross product.
				var normal: Vector3 = (positions[tri[2]] - positions[tri[0]]).cross(positions[tri[1]] - positions[tri[0]]).normalized()
				for index: int in tri:
					verts.append(positions[index])
					normals.append(normal)
					var corner := corners[index]
					uvs.append(Vector2(corner.x, distance + float(a["dist"]) * corner.y))
					widths.append(Vector2(lerpf(a["w"], b["w"], corner.y), heights[index]))
