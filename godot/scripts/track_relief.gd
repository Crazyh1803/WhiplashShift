## Shared metre-space road/collision relief. Positive heights stay above the global floor.
class_name TrackRelief
extends RefCounted

const MAX_HEIGHTS := {Surfaces.Id.GRAVEL: 0.03, Surfaces.Id.MUD: 0.05,
	Surfaces.Id.BOULDER: 0.20, Surfaces.Id.WATER: 0.02}
const END_FADE := 3.5
const EDGE_FADE := 3.0
const ROCK_ROW := 5.0
const ROCK_LANE := 3.9


static func enabled(sid: int) -> bool:
	return MAX_HEIGHTS.has(sid)


static func height(sid: int, s: float, across: float, width: float, length: float, seed: int = 0) -> float:
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


## Mirrored left/right rocks keep aggregate lateral loading symmetric; rows, lanes, sizes and phases are seeded.
## Rock heights scale with footprint so gradients stay bounded, and taper near ends/edges so the fades stay safe.
static func _boulders(s: float, across: float, width: float, length: float, seed: int) -> float:
	var half := width * 0.5
	var lateral := absf(across)
	var end_taper := lerpf(0.5, 1.0, smoothstep(END_FADE, END_FADE + 5.0, minf(s, length - s)))
	var edge_taper := lerpf(0.5, 1.0, smoothstep(EDGE_FADE, EDGE_FADE + 5.0, half - lateral))
	var base_row := floori(s / ROCK_ROW)
	var peak := 0.0
	for row in range(base_row - 3, base_row + 4):
		for pair in range(0, 7):
			var state := posmod(row * 73856093 ^ pair * 19349663 ^ seed * 83492791, 2147483646) + 1
			state = _rand(state)
			var center_s := (float(row) + 0.5 + (float(state) / 2147483647.0 - 0.5) * 1.1) * ROCK_ROW
			if absf(s - center_s) > 10.0:
				continue
			# Pair 6 is a shoulder rock tucked just inside the edge fade so outer car lanes still meet bumps.
			var shoulder := pair == 6
			state = _rand(state)
			var center_u := (float(pair) + 0.5 + (float(state) / 2147483647.0 - 0.5) * 0.9) * ROCK_LANE
			if shoulder:
				center_u = half - 2.6 + (float(state) / 2147483647.0 - 0.5)
			if center_u > half - 0.5:
				continue
			state = _rand(state)
			var radius_s := 4.2 + 2.8 * float(state) / 2147483647.0
			state = _rand(state)
			var radius_u := 3.4 + 1.8 * float(state) / 2147483647.0
			state = _rand(state)
			var variation := float(state) / 2147483647.0
			state = _rand(state)
			var diamond := 0.70 + 0.04 * float(state) / 2147483647.0
			# Full-sized rocks use a wider footprint (not steeper slopes) to reach the accepted 0.16-0.20 m crowns.
			var slope := 0.026
			if shoulder or pair == posmod(row + seed, 3):
				radius_s = 8.0 + 1.5 * (radius_s - 4.2) / 2.8
				radius_u = 8.0 + 1.5 * (radius_u - 3.4) / 1.8
				variation = 0.9 + 0.1 * variation
				slope = 0.0245
			var crown := minf(0.2 * (0.6 + 0.4 * variation), slope * minf(radius_s, radius_u))
			var dx := absf(s - center_s) / radius_s
			if dx >= 1.0:
				continue
			for side in [-1.0, 1.0]:
				var dy := absf(lateral - side * center_u) / radius_u
				var footprint := maxf(maxf(dx, dy), (dx + dy) * diamond)
				if footprint < 1.0:
					var crown_radius := maxf(0.0, (footprint - 0.12) / 0.88)
					var dome := 0.5 + 0.5 * cos(PI * crown_radius)
					peak = maxf(peak, crown * dome * dome)
	return peak * end_taper * edge_taper


## Subdivide the original quad, retaining its exact boundary and winding.
static func append_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, widths: PackedVector2Array, a: Dictionary, b: Dictionary,
		sid: int, distance: float, run_start: float, run_length: float, seed: int) -> void:
	var an: Vector3 = Vector3(-a["dir"].z, 0, a["dir"].x) * (float(a["w"]) * 0.5)
	var bn: Vector3 = Vector3(-b["dir"].z, 0, b["dir"].x) * (float(b["w"]) * 0.5)
	var al: Vector3 = a["pos"] + an
	var ar: Vector3 = a["pos"] - an
	var bl: Vector3 = b["pos"] + bn
	var br: Vector3 = b["pos"] - bn
	var spacing := 0.6 if sid == Surfaces.Id.BOULDER else 0.9
	var steps := maxi(1, ceili(float(a["dist"]) / spacing))
	var lane_width := 0.8 if sid == Surfaces.Id.BOULDER else 2.5
	var lanes := clampi(ceili(maxf(a["w"], b["w"]) / lane_width), 8, 48 if sid == Surfaces.Id.BOULDER else 16)
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
				var h := height(sid, s - run_start, across, width, run_length, seed)
				p.y += h
				positions.append(p)
				heights.append(h / float(MAX_HEIGHTS.get(sid, 1.0)))
			for tri: Array in [[0, 1, 2], [2, 1, 3]]:
				# Godot's front-face winding is opposite the geometric cross product.
				var normal: Vector3 = (positions[tri[2]] - positions[tri[0]]).cross(positions[tri[1]] - positions[tri[0]]).normalized()
				for index: int in tri:
					verts.append(positions[index])
					normals.append(normal)
					var corner := corners[index]
					uvs.append(Vector2(corner.x, distance + float(a["dist"]) * corner.y))
					widths.append(Vector2(lerpf(a["w"], b["w"], corner.y), heights[index]))
