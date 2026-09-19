## The circuit, authored exactly as web/src/track.js authored it.
##
## Straights and arcs, sampled every few metres. Porting this is why a drivable
## greybox circuit costs barely more than a flat plane — the shape already exists.
## Web's (x, y) maps to Godot's (x, z); the whole thing is recentred on the origin.
class_name TrackData
extends RefCounted

const STEP := 3.5
const CENTRE := Vector2(490.0, 425.0)   # web ORIGIN + WORLD/2

static func _straight(out: Array, x0: float, y0: float, x1: float, y1: float, w: float, s: int) -> void:
	var d := Vector2(x1 - x0, y1 - y0)
	var n := maxi(1, int(round(d.length() / STEP)))
	var start := 1 if out.size() > 0 else 0
	for i in range(start, n + 1):
		var t := float(i) / float(n)
		out.append({"p": Vector2(x0, y0) + d * t, "w": w, "s": s})


static func _arc(out: Array, cx: float, cy: float, r: float, a0: float, a1: float, w: float, s: int) -> void:
	var sweep := a1 - a0
	var n := maxi(2, int(round(absf(sweep) * r / STEP)))
	var start := 1 if out.size() > 0 else 0
	for i in range(start, n + 1):
		var a := a0 + sweep * (float(i) / float(n))
		out.append({"p": Vector2(cx + cos(a) * r, cy + sin(a) * r), "w": w, "s": s})


## Ordered, closed centreline. Each entry: pos (Vector3), w, s, dir (Vector3), dist.
static func author() -> Array:
	var D := PI / 180.0
	var p: Array = []
	_straight(p, 220, 180, 650, 180, 26, Surfaces.Id.TARMAC)     # start / finish
	_straight(p, 650, 180, 722, 180, 26, Surfaces.Id.RUMBLE)     # "tarmac ends ahead"
	_arc(p, 730, 280, 100, 270 * D, 360 * D, 24, Surfaces.Id.MUD)
	_straight(p, 830, 280, 830, 355, 24, Surfaces.Id.MUD)
	_straight(p, 830, 355, 830, 420, 24, Surfaces.Id.WATER)
	_straight(p, 830, 420, 830, 560, 24, Surfaces.Id.BOULDER)
	_arc(p, 730, 560, 100, 0, 90 * D, 24, Surfaces.Id.BOULDER)
	_straight(p, 730, 660, 560, 660, 24, Surfaces.Id.GRAVEL)
	_straight(p, 560, 660, 470, 660, 24, Surfaces.Id.ICE)
	_straight(p, 470, 660, 400, 660, 24, Surfaces.Id.GRAVEL)
	_arc(p, 400, 600, 60, 90 * D, 270 * D, 22, Surfaces.Id.MUD)  # the hairpin
	_straight(p, 400, 540, 520, 540, 22, Surfaces.Id.MUD)        # backwards branch
	_arc(p, 520, 460, 80, 90 * D, -90 * D, 24, Surfaces.Id.GRAVEL)
	_straight(p, 520, 380, 330, 380, 24, Surfaces.Id.GRAVEL)
	_straight(p, 330, 380, 260, 380, 26, Surfaces.Id.RUMBLE)     # "tarmac resumes"
	_straight(p, 260, 380, 220, 380, 26, Surfaces.Id.TARMAC)
	_arc(p, 220, 280, 100, 90 * D, 270 * D, 26, Surfaces.Id.TARMAC)
	p.pop_back()   # last point coincides with the first

	var out: Array = []
	var n := p.size()
	for i in n:
		var here: Vector2 = p[i]["p"] - CENTRE
		var nxt: Vector2 = p[(i + 1) % n]["p"] - CENTRE
		var prv: Vector2 = p[(i - 1 + n) % n]["p"] - CENTRE
		var tangent := (nxt - prv).normalized()
		out.append({
			"pos": Vector3(here.x, 0.0, here.y),
			"dir": Vector3(tangent.x, 0.0, tangent.y),
			"w": p[i]["w"],
			"s": p[i]["s"],
			"dist": here.distance_to(nxt),
		})
	return out
