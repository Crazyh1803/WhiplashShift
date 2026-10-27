extends Node3D

const VIEWS: Array[Vector2] = [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080), Vector2(1152, 648)]

var _pass := 0
var _fail := 0
var _retry_requests := 0


func _ready() -> void:
	_test_digits()
	_test_segments()
	_test_scanner()
	_test_layout()
	_test_ring()
	_test_fit()
	await _test_integration()
	print("DASHBOARD HUD: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _lit(mask: int) -> int:
	var count := 0
	for bit in 7:
		count += (mask >> bit) & 1
	return count


func _test_digits() -> void:
	var zero := DashInstruments.speed_masks(0)
	_check("0 shows one lit zero with blank leading digits", zero[0] == 0 and zero[1] == 0 and _lit(zero[2]) == 6)
	var thirteen := DashInstruments.speed_masks(13)
	_check("13 is blank, 1, 3", thirteen[0] == 0 and thirteen[1] == DashInstruments.DIGIT_MASKS[1] and thirteen[2] == DashInstruments.DIGIT_MASKS[3])
	var v112 := DashInstruments.speed_masks(112)
	_check("112 is 1, 1, 2", v112[0] == DashInstruments.DIGIT_MASKS[1] and v112[1] == DashInstruments.DIGIT_MASKS[1] and v112[2] == DashInstruments.DIGIT_MASKS[2])
	var v200 := DashInstruments.speed_masks(200)
	_check("200 keeps its zeros", v200[1] == DashInstruments.DIGIT_MASKS[0] and v200[2] == DashInstruments.DIGIT_MASKS[0])
	var nines := DashInstruments.speed_masks(999)
	_check("999 lights every digit as nine", nines[0] == nines[1] and nines[1] == nines[2] and _lit(nines[0]) == 6)
	_check("speeds above 999 clamp and negatives read 0", DashInstruments.speed_masks(5400) == nines and DashInstruments.speed_masks(-4) == zero)
	_check("eight lights all seven segments", _lit(DashInstruments.DIGIT_MASKS[8]) == 7)


func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


func _test_segments() -> void:
	var cell := Rect2(100.0, 200.0, 52.0, 100.0)
	var polys := DashInstruments.segment_polygons(cell)
	var inside := true
	var solid := true
	for bit: int in polys:
		var poly: PackedVector2Array = polys[bit]
		solid = solid and poly.size() == 6 and _area(poly) > 20.0 and not Geometry2D.triangulate_polygon(poly).is_empty()
		for p in poly:
			inside = inside and cell.grow(0.01).has_point(p)
	_check("seven true hexagon polygons", polys.size() == 7 and solid)
	_check("segments stay inside the digit cell", inside)
	var clean := true
	var keys: Array = polys.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			clean = clean and Geometry2D.intersect_polygons(polys[keys[i]], polys[keys[j]]).is_empty()
	_check("segments never overlap", clean)
	var lit_area := 0.0
	var dim_area := 0.0
	for bit: int in polys:
		lit_area += _area(polys[bit]) * float((DashInstruments.DIGIT_MASKS[7] & bit) != 0)
		dim_area += _area(polys[bit]) * float((DashInstruments.DIGIT_MASKS[7] & bit) == 0)
	_check("inactive segments exist to draw dim", dim_area > 0.0 and lit_area > 0.0)
	var parts := DashInstruments.speed_layout(DashInstruments.layout(Vector2(1600, 900))["velocity"], 1.0)
	var cells: Array[Rect2] = parts["cells"]
	_check("digit cells are tall and non-overlapping", cells.size() == 3 and cells[0].size.y > cells[0].size.x * 1.5
		and not cells[0].intersects(cells[1]) and not cells[1].intersects(cells[2]))


func _test_scanner() -> void:
	var strip := Rect2(18.0, 636.0, 1564.0, 6.0)
	var inside := true
	var heads := 0
	for step in 41:
		var cells := DashInstruments.scanner_cells(strip, step / 40.0)
		for cell: Dictionary in cells:
			inside = inside and strip.grow(0.01).encloses(cell["rect"])
			heads += 1 if cell["head"] else 0
	_check("scanner cells stay inside the strip all sweep long", inside and heads == 41)
	var start := DashInstruments.scanner_cells(strip, 0.0)
	var mid := DashInstruments.scanner_cells(strip, 0.5)
	_check("sweep starts left and reaches the right edge", absf((start[0]["rect"] as Rect2).position.x - strip.position.x) < 0.01
		and absf((mid[0]["rect"] as Rect2).end.x - strip.end.x) < 1.5)
	var quarter := DashInstruments.scanner_cells(strip, 0.25)
	var fading := quarter.size() > 3 and float(quarter[0]["alpha"]) == 1.0
	for i in range(1, quarter.size()):
		fading = fading and float(quarter[i]["alpha"]) < float(quarter[i - 1]["alpha"]) and (quarter[i]["rect"] as Rect2).position.x < (quarter[i - 1]["rect"] as Rect2).position.x
	_check("trail fades behind the head", fading)
	var back := DashInstruments.scanner_cells(strip, 0.75)
	_check("return sweep trails to the right", back.size() > 3 and (back[1]["rect"] as Rect2).position.x > (back[0]["rect"] as Rect2).position.x)
	_check("phase wraps", (DashInstruments.scanner_cells(strip, 1.25)[0]["rect"] as Rect2).is_equal_approx(quarter[0]["rect"]))


func _test_layout() -> void:
	var l := DashInstruments.layout(Vector2(1600, 900))
	var band: Rect2 = l["band"]
	_check("compact band spans y 700 to 860 at 1600x900", absf(band.position.y - 700.0) < 0.5 and absf(band.end.y - 860.0) < 0.5)
	_check("band is at least 25% shorter than the 210px original", band.size.y <= 210.0 * 0.78)
	for view in VIEWS:
		var lay := DashInstruments.layout(view)
		var b: Rect2 = lay["band"]
		var rects: Array[Rect2] = []
		for key: String in ["velocity", "systems", "route", "combat", "map"]:
			rects.append(lay[key])
		var ordered := true
		var inside := Rect2(Vector2.ZERO, view).encloses(b)
		for i in rects.size():
			inside = inside and b.encloses(rects[i])
			ordered = ordered and (i == 0 or (rects[i].position.x > rects[i - 1].end.x and absf(rects[i].position.y - rects[0].position.y) < 0.01))
		_check("five ordered instruments inside the band at %s" % view, inside and ordered)
		_check("map keeps useful width at %s" % view, (lay["map"] as Rect2).size.x > 200.0 * float(lay["scale"]))
		_check("scanner sits above the band and the hint below it at %s" % view, (lay["scanner"] as Rect2).end.y < b.position.y
			and float(lay["hint_top"]) > b.end.y and float(lay["hint_top"]) + 16.0 <= view.y)


func _test_ring() -> void:
	for view in VIEWS:
		var lay := DashInstruments.layout(view)
		var limit: float = (lay["scanner"] as Rect2).position.y
		var worst := -INF
		var top := INF
		for step in 72:
			for p in CombatHud.ring_triangle(view, TAU * step / 72.0):
				worst = maxf(worst, p.y)
				top = minf(top, p.y)
		_check("attack ring stays above the dashboard at %s" % view, worst < limit and top > 0.0)


func _test_fit() -> void:
	var font := ThemeDB.fallback_font
	var advice := "HAIRPIN RIGHT · IN 120m\nBRAKE BEFORE TURN · ADVISORY 100 KM/H"
	var box := DashInstruments.body(DashInstruments.layout(Vector2(1600, 900))["route"], 1.0)
	var size := DashInstruments.fit_font_size(font, advice, box.size, 18)
	var measured := font.get_multiline_string_size(advice, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	_check("two-line corner advice fits the route instrument", measured.x <= box.size.x and measured.y <= box.size.y and size >= 13)
	var tight := DashInstruments.fit_font_size(font, "A VERY LONG LINE OF ADVICE THAT CANNOT POSSIBLY FIT", Vector2(120.0, 30.0), 18)
	_check("impossible text shrinks to the floor", tight == 9)
	var wrapped := DashInstruments.fit_font_size(font, "BOOST READY  ACCELERATE + [Q]", Vector2(204.0, 36.0), 12, 9, true)
	var size_wrapped := font.get_multiline_string_size("BOOST READY  ACCELERATE + [Q]", HORIZONTAL_ALIGNMENT_LEFT, 204.0, wrapped)
	_check("boost text wraps inside the compact systems instrument", size_wrapped.y <= 36.0 and size_wrapped.x <= 204.0)
	var parts := DashInstruments.speed_layout(DashInstruments.layout(Vector2(1600, 900))["velocity"], 1.0)
	var unit_rect: Rect2 = parts["unit"]
	for text in ["KM/H", "MPH", "REVERSE"]:
		var rect: Rect2 = parts["reverse"] if text == "REVERSE" else unit_rect
		var fitted := DashInstruments.fit_font_size(font, text, rect.size, 22)
		_check("%s label fits its lamp" % text, fitted >= 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x <= rect.size.x)


func _test_integration() -> void:
	GameSession.configure("DASHBOARD HUD TEST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
		driver.target.freeze = true
	var car: Vehicle = scene.car
	car.freeze = true
	var hud: Hud = scene.hud
	var driving: DrivingHud = hud.driving
	var race: RaceDirector = scene.race
	hud.retry_requested.connect(func() -> void: _retry_requests += 1)
	hud._process(0.016)
	await get_tree().process_frame
	var view := get_viewport().get_visible_rect().size
	var l := DashInstruments.layout(view)
	var s: float = l["scale"]
	_check("driving readout lays out from the same function", driving.dash["band"] == l["band"])
	_check("scanner layer exists and ignores the mouse", driving.get_node("ScannerLayer").mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# Scanner animation must not rebuild the cached course.
	var rebuilds := driving.map_rebuilds
	for i in 30:
		driving._process(0.1)
		hud._process(0.016)
	await get_tree().process_frame
	_check("scanner time advances", driving.scanner_time > 2.9)
	_check("scanner sweep does not rebuild the course", driving.map_rebuilds == rebuilds)

	# Map instrument holds the real projection and markers.
	var map_rect := Rect2(driving.get_node("Minimap").position, driving.map_size)
	_check("minimap sits inside the map instrument", (l["map"] as Rect2).encloses(map_rect))
	var start_point: Vector3 = race.course.points[0]["pos"]
	car.global_position = start_point
	hud._process(0.016)
	_check("player marker projects from the real world position", (driving.markers[0]["pos"] as Vector2).distance_to(
		DrivingHud.project(driving.fit, start_point, driving.map_area())) < 0.01)
	_check("map area is inside the map layer", Rect2(Vector2.ZERO, driving.map_size).encloses(driving.map_area()))

	# Text instruments stay inside their wells and the hint clears the band.
	race.tick(3.0)
	var systems := DashInstruments.systems_layout(l["systems"], s)
	var route := DashInstruments.body(l["route"], s)
	_check("hint clears the band and the viewport", hud._hint.get_global_rect().position.y >= (l["band"] as Rect2).end.y
		and Rect2(Vector2.ZERO, view).encloses(hud._hint.get_global_rect()))
	var route_text := "HAIRPIN RIGHT · IN 120m\nBRAKE BEFORE TURN · ADVISORY 100 KM/H"
	hud._set_fitted(hud._upcoming, route_text, 18)
	var font := hud._upcoming.get_theme_font("font")
	var route_size := font.get_multiline_string_size(route_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, hud._upcoming.get_theme_font_size("font_size"))
	_check("route label sits in the route instrument", route.encloses(hud._upcoming.get_rect()) and route_size.x <= route.size.x and route_size.y <= route.size.y)
	hud._set_fitted(hud._item_status, "LOW GRIP  SMOKE\nNO MISSILE LOCK — ITEM SAVED", 13)
	var status_font := hud._item_status.get_theme_font("font")
	var status_size := status_font.get_multiline_string_size(hud._item_status.text, HORIZONTAL_ALIGNMENT_LEFT, hud._item_status.size.x, hud._item_status.get_theme_font_size("font_size"))
	_check("long item feedback wraps inside the systems instrument", (systems["status"] as Rect2) == hud._item_status.get_rect()
		and status_size.y <= hud._item_status.size.y and (l["systems"] as Rect2).encloses(hud._item_status.get_rect()))
	_check("boost label sits above bodywork inside systems", (l["systems"] as Rect2).encloses(hud._boost_status.get_rect())
		and hud._boost_status.get_rect().end.y <= hud._item_status.get_rect().position.y
		and hud._item_status.get_rect().end.y <= (systems["damage_label"] as Rect2).position.y)
	_check("boost charging instruction shows both lines", hud._boost_status.get_line_count() == 2 and hud._boost_status.get_visible_line_count() >= 2)
	_check("main diagnostics keep driver, end and surface", "END " in hud._main.text and hud._main.text.contains(hud.pilot_callsign)
		and not ("transmission" in hud._main.text))
	_check("diagnostics clear the dashboard", hud._main.get_rect().end.y < (l["scanner"] as Rect2).position.y
		and hud._cpu.get_rect().end.y < (l["scanner"] as Rect2).position.y)
	var combat_panel := DashInstruments.body(l["combat"], s)
	_check("weapon panel fits the combat instrument", (l["combat"] as Rect2).encloses(combat_panel) and combat_panel.size.y >= 100.0 * s)

	# Speed values: digits follow display_speed for each saved unit.
	GameSession.speed_unit = "kmh"
	for kmh in [0, 13, 112, 200, 999]:
		car.speed = float(kmh) / 3.6
		hud._process(0.016)
		_check("%d km/h reaches the digits" % kmh, driving.speed_value == kmh and DashInstruments.speed_masks(driving.speed_value).size() == 3)
	GameSession.speed_unit = "kmh"

	# Countdown banner and top header stay clear of the band; results buttons still work.
	_check("banner and race header are above the band", hud._banner.get_rect().end.y < (l["band"] as Rect2).position.y
		and hud._race_status.get_rect().end.y < (l["band"] as Rect2).position.y)
	race.state = RaceDirector.State.RESULTS
	hud._process(0.016)
	var retry: Button = hud._results.find_child("RetryButton", true, false)
	var garage: Button = hud._results.find_child("GarageButton", true, false)
	_check("results buttons are interactive and on screen", hud._results.visible and not retry.disabled and not garage.disabled
		and retry.mouse_filter == Control.MOUSE_FILTER_STOP and Rect2(Vector2.ZERO, view).encloses(retry.get_global_rect()))
	retry.pressed.emit()
	_check("retry button still requests a retry", _retry_requests == 1)
	scene.restart_race()
	hud._process(0.016)
	_check("retry returns to a countdown with the band visible", race.state == RaceDirector.State.COUNTDOWN and driving.visible)
	scene.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
