## Shared metre-space road/collision relief. Positive heights stay above the global floor.
class_name TrackRelief
extends RefCounted

const MAX_HEIGHTS := {Surfaces.Id.GRAVEL: 0.03, Surfaces.Id.MUD: 0.05,
	Surfaces.Id.BOULDER: 0.08, Surfaces.Id.WATER: 0.02}
const END_FADE := 3.5
const EDGE_FADE := 3.0


static func enabled(sid: int) -> bool:
	return MAX_HEIGHTS.has(sid)


static func height(sid: int, s: float, across: float, width: float, length: float, seed: int = 0) -> float:
	if not enabled(sid):
		return 0.0
	var edge := width * 0.5 - absf(across)
	if s <= 0.0 or s >= length or edge <= 0.0:
		return 0.0
	var fade := smoothstep(0.0, END_FADE, minf(s, length - s)) * smoothstep(0.0, EDGE_FADE, edge)
	var phase := float(posmod(seed * 17 + sid * 31, 97)) * 0.1
	var frequency := 0.3 if sid == Surfaces.Id.GRAVEL else 0.2
	if sid == Surfaces.Id.WATER:
		frequency = 0.15
	# Broad swells avoid exciting the suspension near its natural frequency.
	var profile := 0.5 + 0.25 * cos(s * frequency + phase) + 0.25 * cos(across * 0.7)
	return float(MAX_HEIGHTS[sid]) * profile * fade


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
	var steps := maxi(1, ceili(float(a["dist"]) / 0.9))
	var lanes := clampi(ceili(maxf(a["w"], b["w"]) / 2.5), 8, 16)
	for row in steps:
		for lane in lanes:
			var corners: Array[Vector2] = [Vector2(float(lane) / lanes, float(row) / steps),
				Vector2(float(lane + 1) / lanes, float(row) / steps),
				Vector2(float(lane) / lanes, float(row + 1) / steps),
				Vector2(float(lane + 1) / lanes, float(row + 1) / steps)]
			var positions: Array[Vector3] = []
			for corner in corners:
				var width := lerpf(a["w"], b["w"], corner.y)
				var s := distance + float(a["dist"]) * corner.y
				var across := (corner.x - 0.5) * width
				var p := al.lerp(ar, corner.x).lerp(bl.lerp(br, corner.x), corner.y)
				p.y += height(sid, s - run_start, across, width, run_length, seed)
				positions.append(p)
			for tri: Array in [[0, 1, 2], [2, 1, 3]]:
				# Godot's front-face winding is opposite the geometric cross product.
				var normal: Vector3 = (positions[tri[2]] - positions[tri[0]]).cross(positions[tri[1]] - positions[tri[0]]).normalized()
				for index: int in tri:
					verts.append(positions[index])
					normals.append(normal)
					var corner := corners[index]
					uvs.append(Vector2(corner.x, distance + float(a["dist"]) * corner.y))
					widths.append(Vector2(lerpf(a["w"], b["w"], corner.y), 0))
