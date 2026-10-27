## Native driving readout: the dashboard band (red seven-segment speed, scanner sweep,
## instrument wells) and a static whole-course minimap with live racer markers (right). The projected course is
## cached and only rebuilt when the course or the map size changes; `update()` just
## reprojects the few racer markers. Pure state is exposed so tests can assert on it.
class_name DrivingHud
extends Control

const UNITS := {
	"kmh": {"label": "KM/H", "factor": 3.6},
	"mph": {"label": "MPH", "factor": 2.2369362920544},
}
const DEFAULT_UNIT := "kmh"
const MAP_PAD := 12.0
const KEY_HEIGHT := 26.0
const SCAN_PERIOD := 3.4 ## seconds per there-and-back sweep
const PLAYER_COLOR := Color("4fd2ff")
const OPPONENT_COLORS: Array[Color] = [Color("ff5a8a"), Color("ffd24d"), Color("b48cff"), Color("7dff9b")]

var unit := DEFAULT_UNIT
var speed_value := 0
var reversing := false
var markers: Array[Dictionary] = [] ## {index, pos, heading, player, color}; map-local
var dash: Dictionary = {} ## DashInstruments.layout() for the current size
var map_size := Vector2(300.0, 180.0)
var scanner_time := 0.0 ## seconds; tests and QA set it for a deterministic sweep
var fit: Dictionary = {} ## cached course projection, see fit_course()
var map_rebuilds := 0
var _map_course: CourseDefinition
var _map_area := Rect2()
var _map: Control
var _course_layer: Control
var _marker_layer: Control
var _scanner: Control
var _laid_size := Vector2.ZERO
var _racer_count := 0


## Unit id that is always valid; anything unknown falls back to km/h.
static func sanitize_unit(value: Variant) -> String:
	var id := String(value).strip_edges().to_lower() if value is String else ""
	return id if UNITS.has(id) else DEFAULT_UNIT


static func unit_label(p_unit: String) -> String:
	return String(UNITS[sanitize_unit(p_unit)]["label"])


## Metres per second in the chosen unit, unrounded.
static func convert_speed(mps: float, p_unit: String) -> float:
	return mps * float(UNITS[sanitize_unit(p_unit)]["factor"])


static func display_speed(mps: float, p_unit: String) -> int:
	return roundi(absf(convert_speed(mps, p_unit))) if is_finite(mps) else 0


## Corner advisory speed in the chosen unit, floored to the nearest 5.
static func advisory_speed(mps: float, p_unit: String) -> int:
	return floori(convert_speed(mps, p_unit) / 5.0) * 5


## Projects the course's XZ footprint into `area`, preserving aspect ratio.
## Returns {valid, scale, min (world XZ), offset (map px of the world min), polyline, start, start_dir, bounds}.
static func fit_course(points: Array, area: Rect2) -> Dictionary:
	var flat: Array[Vector2] = []
	var heads: Array[Vector2] = []
	for point: Variant in points:
		if not (point is Dictionary) or not (point as Dictionary).get("pos") is Vector3:
			continue
		var pos: Vector3 = (point as Dictionary)["pos"]
		if not (is_finite(pos.x) and is_finite(pos.z)):
			continue
		flat.append(Vector2(pos.x, pos.z))
		var dir: Variant = (point as Dictionary).get("dir")
		heads.append(Vector2(dir.x, dir.z) if dir is Vector3 else Vector2.ZERO)
	if flat.is_empty() or area.size.x <= 1.0 or area.size.y <= 1.0:
		return {"valid": false, "scale": 1.0, "min": Vector2.ZERO, "offset": area.position,
			"polyline": PackedVector2Array(), "start": area.get_center(), "start_dir": Vector2.UP, "bounds": Rect2(area.get_center(), Vector2.ZERO)}
	var lo := flat[0]
	var hi := flat[0]
	for p in flat:
		lo = lo.min(p)
		hi = hi.max(p)
	var extent := hi - lo
	var scale := INF
	if extent.x > 0.001:
		scale = minf(scale, area.size.x / extent.x)
	if extent.y > 0.001:
		scale = minf(scale, area.size.y / extent.y)
	if is_inf(scale):
		scale = 1.0 # every point coincides: a single centred dot
	var drawn := extent * scale
	var offset := area.position + (area.size - drawn) * 0.5
	var result := {"valid": true, "scale": scale, "min": lo, "offset": offset}
	var line := PackedVector2Array()
	for p in flat:
		line.append(offset + (p - lo) * scale)
	if line.size() > 1:
		line.append(line[0]) # closed circuit
	var start_dir := heads[0]
	if start_dir.length_squared() < 0.0001 and flat.size() > 1:
		start_dir = flat[1] - flat[0]
	start_dir = start_dir.normalized() if start_dir.length_squared() > 0.0001 else Vector2.UP
	result["polyline"] = line
	result["start"] = line[0]
	result["start_dir"] = start_dir
	result["bounds"] = Rect2(offset, drawn)
	return result


## World position to map-local pixels under a fit from fit_course(), clamped into `area`.
static func project(p_fit: Dictionary, world: Vector3, area: Rect2) -> Vector2:
	if not bool(p_fit.get("valid", false)) or not (is_finite(world.x) and is_finite(world.z)):
		return area.get_center()
	var mapped: Vector2 = Vector2(p_fit["offset"]) + (Vector2(world.x, world.z) - Vector2(p_fit["min"])) * float(p_fit["scale"])
	return mapped.clamp(area.position, area.end)


func _ready() -> void:
	name = "DrivingHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map = Control.new()
	_map.name = "Minimap"
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map_panel)
	add_child(_map)
	_course_layer = _layer("CourseLayer", _draw_course)
	_marker_layer = _layer("MarkerLayer", _draw_markers)
	_scanner = Control.new()
	_scanner.name = "ScannerLayer"
	_scanner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scanner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scanner.draw.connect(_draw_scanner)
	add_child(_scanner)
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	if visible:
		scanner_time += delta
		_scanner.queue_redraw() # the sweep only repaints its own layer; the cached course is untouched


func _layer(layer_name: String, painter: Callable) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(painter)
	_map.add_child(layer)
	return layer


func _layout() -> void:
	_laid_size = size
	dash = DashInstruments.layout(size)
	var s: float = dash["scale"]
	var area: Rect2 = dash["map"]
	if _map != null:
		_map.position = area.position + Vector2(6.0, 22.0) * s
		map_size = (area.size - Vector2(12.0, 28.0) * s).max(Vector2(20.0, 20.0))
		_map.size = map_size
		for layer: Control in [_course_layer, _marker_layer]:
			layer.size = map_size
	queue_redraw()


## Course area inside the map panel (excludes padding and the key strip).
func map_area() -> Rect2:
	return Rect2(Vector2(MAP_PAD, MAP_PAD), map_size - Vector2(MAP_PAD * 2.0, MAP_PAD * 2.0 + KEY_HEIGHT))


func clear() -> void:
	markers.clear()
	speed_value = 0
	reversing = false
	queue_redraw()
	if _marker_layer != null:
		_marker_layer.queue_redraw()


## `racers[0]` is the player; the rest are opponents in entrant order.
func update(p_unit: String, car: Vehicle, racers: Array, course: CourseDefinition) -> void:
	if size != _laid_size:
		_layout() # size changed since the last layout (resized may not have fired yet)
	var clean_unit := sanitize_unit(p_unit)
	var value := display_speed(car.speed, clean_unit) if car != null else 0
	var back := car != null and car.reversing
	if clean_unit != unit or value != speed_value or back != reversing:
		unit = clean_unit
		speed_value = value
		reversing = back
		queue_redraw()
	_ensure_map(course, racers.size())
	markers.clear()
	if not bool(fit.get("valid", false)):
		_marker_layer.queue_redraw()
		return
	var area := map_area()
	for i in racers.size():
		var racer: Vehicle = racers[i] if is_instance_valid(racers[i]) else null
		if racer == null:
			continue
		var forward := racer.forward_vector()
		var heading := Vector2(forward.x, forward.z)
		markers.append({"index": i, "pos": project(fit, racer.global_position, area),
			"heading": heading.normalized() if heading.length_squared() > 0.0001 else Vector2.UP,
			"player": i == 0, "color": PLAYER_COLOR if i == 0 else OPPONENT_COLORS[(i - 1) % OPPONENT_COLORS.size()]})
	_marker_layer.queue_redraw()


func _ensure_map(course: CourseDefinition, racer_count: int) -> void:
	var area := map_area()
	if course == _map_course and area == _map_area and racer_count == _racer_count:
		return
	_map_course = course
	_map_area = area
	_racer_count = racer_count
	map_rebuilds += 1
	fit = fit_course(course.points if course != null else [], area)
	_course_layer.queue_redraw()


func _draw() -> void:
	if dash.is_empty():
		return
	var font := ThemeDB.fallback_font
	var s: float = dash["scale"]
	var band: Rect2 = dash["band"]
	# Black recessed band: deep fill, a dark inner lip and one thin amber bezel line.
	draw_rect(band, DashInstruments.BAND_FILL)
	draw_rect(band.grow(2.0 * s), Color(0, 0, 0, 0.7), false, 4.0 * s)
	draw_rect(band, DashInstruments.AMBER_DIM, false, 1.0)
	var titles := {"velocity": "VELOCITY", "systems": "SYSTEMS", "route": "ROUTE", "combat": "WEAPONS", "map": "COURSE"}
	for key: String in titles:
		var rect: Rect2 = dash[key]
		draw_rect(rect, DashInstruments.WELL_FILL)
		draw_rect(rect, DashInstruments.AMBER_DIM, false, 1.0)
		draw_line(rect.position + Vector2(8.0, 19.0) * s, rect.position + Vector2(rect.size.x - 8.0 * s, 19.0 * s), DashInstruments.AMBER_DIM, 1.0)
		draw_string(font, rect.position + Vector2(10.0, 14.0) * s, titles[key], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0 * s,
			maxi(9, roundi(12.0 * s)), DashInstruments.AMBER)
	_draw_speed(font, s)


func _draw_speed(font: Font, s: float) -> void:
	var parts := DashInstruments.speed_layout(dash["velocity"], s)
	var masks := DashInstruments.speed_masks(speed_value)
	var cells: Array[Rect2] = parts["cells"]
	for i in cells.size():
		var polys := DashInstruments.segment_polygons(cells[i])
		for bit: int in polys:
			draw_colored_polygon(polys[bit], DashInstruments.RED if masks[i] & bit else DashInstruments.RED_DIM)
	var unit_rect: Rect2 = parts["unit"]
	var unit_text := unit_label(unit)
	draw_string(font, unit_rect.position + Vector2(0.0, unit_rect.size.y - 4.0 * s), unit_text, HORIZONTAL_ALIGNMENT_LEFT, unit_rect.size.x,
		DashInstruments.fit_font_size(font, unit_text, unit_rect.size, roundi(22.0 * s)), DashInstruments.AMBER)
	var reverse_rect: Rect2 = parts["reverse"]
	var lamp := DashInstruments.AMBER if reversing else DashInstruments.AMBER_DIM
	draw_string(font, reverse_rect.position + Vector2(0.0, reverse_rect.size.y - 6.0 * s), "REVERSE", HORIZONTAL_ALIGNMENT_LEFT, reverse_rect.size.x,
		DashInstruments.fit_font_size(font, "REVERSE", reverse_rect.size, roundi(15.0 * s)), lamp)


func _draw_scanner() -> void:
	if dash.is_empty():
		return
	var strip: Rect2 = dash["scanner"]
	_scanner.draw_rect(strip, Color(0.12, 0.01, 0.01, 0.55))
	for cell: Dictionary in DashInstruments.scanner_cells(strip, scanner_time / SCAN_PERIOD):
		_scanner.draw_rect(cell["rect"], Color(DashInstruments.RED, float(cell["alpha"])))


func _draw_map_panel() -> void:
	_map.draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.01, 0.015, 0.02, 0.8))
	_map.draw_rect(Rect2(Vector2.ZERO, map_size), DashInstruments.AMBER_DIM, false, 1.0)


func _draw_course() -> void:
	var font := ThemeDB.fallback_font
	if not bool(fit.get("valid", false)):
		_course_layer.draw_string(font, Vector2(0.0, map_size.y * 0.5), "NO COURSE DATA", HORIZONTAL_ALIGNMENT_CENTER, map_size.x, 13, Color(1, 1, 1, 0.5))
		return
	var line: PackedVector2Array = fit["polyline"]
	if line.size() > 1:
		_course_layer.draw_polyline(line, Color(0, 0, 0, 0.6), 7.0, true)
		_course_layer.draw_polyline(line, Color("9fb0bc"), 3.0, true)
	else:
		_course_layer.draw_circle(Vector2(fit["start"]), 3.0, Color("9fb0bc"))
	# Start/finish: a checkered bar across the track direction.
	var start: Vector2 = fit["start"]
	var across := Vector2(fit["start_dir"]).orthogonal() * 8.0
	_course_layer.draw_line(start - across, start + across, Color.WHITE, 5.0)
	_course_layer.draw_line(start - across * 0.5, start + across * 0.5, Color.BLACK, 2.0)


func _draw_markers() -> void:
	var font := ThemeDB.fallback_font
	for entry: Dictionary in markers: # opponents first, the player last so it stays on top
		if not bool(entry["player"]):
			_marker_layer.draw_circle(Vector2(entry["pos"]), 6.5, Color(0, 0, 0, 0.85))
			_marker_layer.draw_circle(Vector2(entry["pos"]), 4.5, Color(entry["color"]))
	for entry: Dictionary in markers:
		if bool(entry["player"]):
			var heading: Vector2 = entry["heading"]
			var side := heading.orthogonal()
			var pos: Vector2 = entry["pos"]
			var arrow := PackedVector2Array([pos + heading * 10.0, pos - heading * 6.0 + side * 6.5, pos - heading * 2.0, pos - heading * 6.0 - side * 6.5])
			_marker_layer.draw_colored_polygon(arrow, Color(entry["color"]))
			_marker_layer.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), Color.WHITE, 1.5)
	# Key: what each marker means.
	var key_y := map_size.y - 10.0
	var slot := (map_size.x - MAP_PAD) / float(_racer_count + 1)
	var x := MAP_PAD * 0.5 + 4.0
	for i in _racer_count:
		var swatch := Vector2(x + 5.0, key_y - 4.0)
		if i == 0:
			var up := PackedVector2Array([swatch + Vector2(0, -5), swatch + Vector2(4.5, 4), swatch + Vector2(0, 1.5), swatch + Vector2(-4.5, 4)])
			_marker_layer.draw_colored_polygon(up, PLAYER_COLOR)
		else:
			_marker_layer.draw_circle(swatch, 4.0, OPPONENT_COLORS[(i - 1) % OPPONENT_COLORS.size()])
		_marker_layer.draw_string(font, Vector2(x + 13.0, key_y), "YOU" if i == 0 else "CPU %d" % i, HORIZONTAL_ALIGNMENT_LEFT, slot - 13.0, 11, Color(1, 1, 1, 0.8))
		x += slot
	_marker_layer.draw_rect(Rect2(x + 1.0, key_y - 9.0, 8.0, 8.0), Color.WHITE)
	_marker_layer.draw_rect(Rect2(x + 3.0, key_y - 7.0, 4.0, 4.0), Color.BLACK)
	_marker_layer.draw_string(font, Vector2(x + 13.0, key_y), "S/F", HORIZONTAL_ALIGNMENT_LEFT, slot - 13.0, 11, Color(1, 1, 1, 0.8))
