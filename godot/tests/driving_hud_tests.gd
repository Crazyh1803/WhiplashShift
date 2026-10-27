extends Node3D

const TEST_SETTINGS := "user://driving_hud_test_settings.cfg"

var _pass := 0
var _fail := 0
var _saved_unit := ""
var _saved_path := ""


func _ready() -> void:
	# Never touch the player's real preferences: point the session at a scratch file.
	_saved_unit = GameSession.speed_unit
	_saved_path = GameSession.settings_path
	GameSession.settings_path = TEST_SETTINGS
	_remove_settings()
	_test_conversion()
	_test_projection()
	_test_degenerate()
	_test_preferences()
	await _test_garage_settings()
	await _test_integration()
	_remove_settings()
	GameSession.settings_path = _saved_path
	GameSession.speed_unit = _saved_unit
	print("DRIVING HUD: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_conversion() -> void:
	_check("three-digit speed fits the number area", ThemeDB.fallback_font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1, 74).x <= DrivingHud.SPEED_NUMBER_WIDTH)
	_check("zero speed reads 0 in both units", DrivingHud.display_speed(0.0, "mph") == 0 and DrivingHud.display_speed(0.0, "kmh") == 0)
	_check("20 m/s is 72 km/h", DrivingHud.display_speed(20.0, "kmh") == 72)
	_check("20 m/s is 45 mph", DrivingHud.display_speed(20.0, "mph") == 45)
	_check("100 km/h is about 62 mph", DrivingHud.display_speed(100.0 / 3.6, "mph") == 62)
	_check("reverse speed shows a magnitude", DrivingHud.display_speed(-10.0, "kmh") == 36)
	_check("non-finite speed reads 0", DrivingHud.display_speed(INF, "mph") == 0 and DrivingHud.display_speed(NAN, "kmh") == 0)
	_check("unit labels", DrivingHud.unit_label("mph") == "MPH" and DrivingHud.unit_label("kmh") == "KM/H")
	_check("unknown units fall back to km/h", DrivingHud.sanitize_unit("furlongs") == "kmh" and DrivingHud.sanitize_unit(7) == "kmh"
		and DrivingHud.sanitize_unit(null) == "kmh" and DrivingHud.sanitize_unit(" MPH ") == "mph")
	_check("km/h advisory keeps the old 5 km/h flooring", DrivingHud.advisory_speed(17.0, "kmh") == floori(17.0 * 3.6 / 5.0) * 5
		and DrivingHud.advisory_speed(17.0, "kmh") == 60)
	_check("mph advisory converts then floors to 5", DrivingHud.advisory_speed(17.0, "mph") == 35
		and DrivingHud.advisory_speed(20.0, "mph") == 40)


func _course(points: Array) -> Array:
	var result: Array = []
	for p: Vector3 in points:
		result.append({"pos": p, "dir": Vector3.FORWARD, "w": 10.0, "s": 0, "dist": 10.0})
	return result


func _test_projection() -> void:
	var area := Rect2(12.0, 12.0, 196.0, 162.0)
	# A wide 400 x 100 oval-ish loop must keep its 4:1 aspect inside the area.
	var wide := DrivingHud.fit_course(_course([Vector3(-200, 0, -50), Vector3(200, 0, -50), Vector3(200, 0, 50), Vector3(-200, 0, 50)]), area)
	var bounds: Rect2 = wide["bounds"]
	_check("fit is valid", wide["valid"])
	_check("fit preserves the 4:1 aspect ratio", absf(bounds.size.x / bounds.size.y - 4.0) < 0.01)
	_check("fit fills the limiting axis", absf(bounds.size.x - area.size.x) < 0.01 and bounds.size.y < area.size.y)
	_check("fit stays centred in the area", bounds.get_center().distance_to(area.get_center()) < 0.01)
	var inside := true
	for p: Vector2 in wide["polyline"]:
		inside = inside and area.grow(0.01).has_point(p)
	_check("every polyline point is inside the area", inside)
	_check("loop is closed", (wide["polyline"] as PackedVector2Array).size() == 5 and wide["polyline"][0] == wide["polyline"][4])
	_check("world corner projects to bounds corner", DrivingHud.project(wide, Vector3(-200, 0, -50), area).distance_to(bounds.position) < 0.01
		and DrivingHud.project(wide, Vector3(200, 0, 50), area).distance_to(bounds.end) < 0.01)
	_check("world centre projects to area centre", DrivingHud.project(wide, Vector3(0, 99, 0), area).distance_to(area.get_center()) < 0.01)
	_check("+X is right and +Z is down", DrivingHud.project(wide, Vector3(100, 0, 0), area).x > area.get_center().x
		and DrivingHud.project(wide, Vector3(0, 0, 25), area).y > area.get_center().y)
	_check("offscreen positions clamp to the area", area.grow(0.01).has_point(DrivingHud.project(wide, Vector3(9000, 0, -9000), area)))
	var tall := DrivingHud.fit_course(_course([Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(50, 0, 300), Vector3(0, 0, 300)]), area)
	var tb: Rect2 = tall["bounds"]
	_check("tall course is limited by height with 1:6 aspect", absf(tb.size.y - area.size.y) < 0.01 and absf(tb.size.y / tb.size.x - 6.0) < 0.01)
	_check("start marker sits on the first point with its direction", wide["start"] == wide["polyline"][0]
		and (wide["start_dir"] as Vector2).is_equal_approx(Vector2(0, -1)))


func _test_degenerate() -> void:
	var area := Rect2(12.0, 12.0, 196.0, 162.0)
	var none := DrivingHud.fit_course([], area)
	_check("empty course is invalid, not a crash", not none["valid"] and DrivingHud.project(none, Vector3(5, 0, 5), area) == area.get_center())
	var one := DrivingHud.fit_course(_course([Vector3(3, 0, 4)]), area)
	_check("single point centres as a dot", one["valid"] and (one["polyline"] as PackedVector2Array).size() == 1
		and (one["start"] as Vector2).distance_to(area.get_center()) < 0.01)
	var same := DrivingHud.fit_course(_course([Vector3(3, 0, 4), Vector3(3, 0, 4), Vector3(3, 0, 4)]), area)
	_check("coincident points fit without dividing by zero", same["valid"] and is_finite(same["scale"]))
	var line := DrivingHud.fit_course(_course([Vector3(0, 0, 0), Vector3(100, 0, 0)]), area)
	_check("collinear course scales by its one live axis", line["valid"] and absf(float(line["scale"]) - area.size.x / 100.0) < 0.001)
	var junk := DrivingHud.fit_course([{"w": 5}, "x", {"pos": Vector3(NAN, 0, 1)}, {"pos": Vector3(0, 0, 0)}, {"pos": Vector3(10, 0, 10)}], area)
	_check("malformed points are skipped", junk["valid"] and (junk["polyline"] as PackedVector2Array).size() == 3)
	_check("zero-size area is invalid", not DrivingHud.fit_course(_course([Vector3.ZERO, Vector3(1, 0, 1)]), Rect2()).get("valid"))


func _test_preferences() -> void:
	GameSession.set_speed_unit("mph")
	_check("choice saves immediately to the separate settings file", FileAccess.file_exists(TEST_SETTINGS) and GameSession.speed_unit == "mph")
	GameSession.speed_unit = "kmh"
	GameSession.load_settings()
	_check("saved unit is restored on startup", GameSession.speed_unit == "mph")
	GameSession.set_speed_unit("bogus")
	_check("invalid choice falls back safely", GameSession.speed_unit == "kmh")
	for bad: Variant in ["furlongs", 42, "", "MPH "]:
		var config := ConfigFile.new()
		config.set_value("display", "speed_unit", bad)
		config.save(TEST_SETTINGS)
		GameSession.speed_unit = "mph"
		GameSession.load_settings()
		var expected := "mph" if bad is String and String(bad) == "MPH " else "kmh"
		_check("stored %s loads as %s" % [var_to_str(bad), expected], GameSession.speed_unit == expected)
	_remove_settings()
	GameSession.speed_unit = "mph"
	GameSession.load_settings()
	_check("missing file loads the default", GameSession.speed_unit == "kmh")
	_check("customization file is not the settings file", GameSession.CUSTOMIZATION_PATH != GameSession.settings_path)


func _test_garage_settings() -> void:
	GameSession.speed_unit = "kmh"
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	await get_tree().process_frame
	_check("garage has a settings button and dialog", garage._settings_button != null and garage._settings_popup != null
		and garage._settings_button.visible)
	garage._settings_button.pressed.emit()
	await get_tree().process_frame
	_check("settings button opens the dialog", garage._settings_popup.visible)
	var kmh: Button = garage._speed_unit_buttons["kmh"]
	var mph: Button = garage._speed_unit_buttons["mph"]
	_check("current unit is highlighted", kmh.button_pressed and not mph.button_pressed)
	mph.pressed.emit()
	_check("mph choice applies through the real callback", GameSession.speed_unit == "mph" and mph.button_pressed and not kmh.button_pressed)
	var config := ConfigFile.new()
	_check("mph choice is persisted to the isolated file", config.load(TEST_SETTINGS) == OK
		and config.get_value("display", "speed_unit") == "mph")
	kmh.pressed.emit()
	config.load(TEST_SETTINGS)
	_check("switching back persists km/h", GameSession.speed_unit == "kmh" and config.get_value("display", "speed_unit") == "kmh")
	GameSession.settings_path = TEST_SETTINGS + "/settings.cfg"
	var error_output := Engine.print_error_messages
	Engine.print_error_messages = false
	mph.pressed.emit()
	Engine.print_error_messages = error_output
	_check("save failures are shown while the session choice applies", "Could not save" in garage._settings_status.text and GameSession.speed_unit == "mph")
	GameSession.settings_path = TEST_SETTINGS
	_check("dialog is smaller than a 1280x720 view", garage._settings_popup.size.x <= 1280 and garage._settings_popup.size.y <= 720)
	garage.queue_free()
	await get_tree().process_frame


func _test_integration() -> void:
	GameSession.speed_unit = "kmh"
	GameSession.configure("DRIVING HUD TEST", "blackjack", ["boilerfang", "ramjet"])
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
	_check("driving readout is part of the HUD", driving != null and driving.get_parent() == hud)

	hud._process(0.016)
	_check("countdown shows speedometer and all three racers", driving.visible and driving.markers.size() == 3)
	var rebuilds := driving.map_rebuilds
	_check("course is cached on first update", rebuilds == 1 and driving.fit["valid"])
	var start_point: Vector3 = race.course.points[0]["pos"]
	_check("fit uses the real course start", (driving.fit["start"] as Vector2).distance_to(
		DrivingHud.project(driving.fit, start_point, driving.map_area())) < 0.01)

	# Player speed: large readout, no tiny duplicate in the main text.
	race.tick(3.0)
	car.speed = 20.0
	car.reversing = false
	hud._process(0.016)
	_check("speedometer shows km/h", driving.speed_value == 72 and driving.unit == "kmh" and not driving.reversing)
	_check("main text has no duplicate speed readout", not ("KM/H" in hud._main.text) and not ("MPH" in hud._main.text) and not ("REVERSE" in hud._main.text))
	car.reversing = true
	hud._process(0.016)
	_check("reverse is flagged on the speedometer", driving.reversing)
	car.reversing = false
	GameSession.speed_unit = "mph"
	hud._process(0.016)
	_check("unit change applies live", driving.speed_value == 45 and driving.unit == "mph")
	var foe: Vehicle = scene.cpu_drivers[0].target
	foe.speed = 20.0
	hud._process(0.016)
	_check("CPU readout uses the chosen unit", " 45 MPH" in hud._cpu.text and not ("KM/H" in hud._cpu.text))
	GameSession.speed_unit = "kmh"
	hud._process(0.016)
	_check("CPU readout follows back to km/h", " 72 KM/H" in hud._cpu.text)

	# Markers follow every entrant, player above and distinct from opponents.
	var area := driving.map_area()
	car.global_position = start_point
	foe.global_position = start_point + Vector3(30, 0, 20)
	hud._process(0.016)
	var player_marker: Dictionary = driving.markers[0]
	var cpu_marker: Dictionary = driving.markers[1]
	_check("player marker is flagged and first entrant", player_marker["player"] and player_marker["index"] == 0 and not cpu_marker["player"])
	_check("player marker at its world position", (player_marker["pos"] as Vector2).distance_to(DrivingHud.project(driving.fit, start_point, area)) < 0.01)
	_check("opponent marker at its world position", (cpu_marker["pos"] as Vector2).distance_to(
		DrivingHud.project(driving.fit, start_point + Vector3(30, 0, 20), area)) < 0.01)
	_check("opponents are visibly differentiated", driving.markers[1]["color"] != driving.markers[2]["color"]
		and driving.markers[1]["color"] != driving.markers[0]["color"])
	var before := (cpu_marker["pos"] as Vector2)
	foe.global_position += Vector3(40, 0, 0)
	hud._process(0.016)
	_check("opponent marker moves live", (driving.markers[1]["pos"] as Vector2).x > before.x)
	car.global_position = start_point
	scene.cpu_drivers[1].target.global_position = start_point
	hud._process(0.016)
	_check("overlapping racers keep separate markers", driving.markers.size() == 3 and (driving.markers[0]["pos"] as Vector2).is_equal_approx(driving.markers[2]["pos"]))
	_check("cached course not rebuilt per frame", driving.map_rebuilds == rebuilds)

	# Layout: speedometer and map clear the existing panels at the test viewport.
	await get_tree().process_frame
	var map_rect := Rect2(driving.get_node("Minimap").global_position, DrivingHud.MAP_SIZE)
	var view := get_viewport().get_visible_rect()
	_check("minimap is inside the viewport", view.encloses(map_rect))
	# CombatHud's panel starts 360 px above the bottom edge (see CombatHud._draw_panel).
	_check("minimap clears CPU readout and the combat panel at 1280x720", DrivingHud.MAP_TOP >= hud._cpu.get_global_rect().position.y + 60.0
		and DrivingHud.MAP_TOP + DrivingHud.MAP_SIZE.y <= 720.0 - 360.0)
	var speedo := Rect2(DrivingHud.SPEEDO_MARGIN.x, view.size.y - DrivingHud.SPEEDO_MARGIN.y - DrivingHud.SPEEDO_SIZE.y,
		DrivingHud.SPEEDO_SIZE.x, DrivingHud.SPEEDO_SIZE.y)
	_check("speedometer clears the controls hint and boost readout", not speedo.intersects(hud._hint.get_global_rect())
		and speedo.position.y > hud._boost_status.get_global_rect().end.y + 40.0)

	# Corner advisory uses the same unit, with km/h behaviour unchanged.
	var corner: Dictionary = scene.course_cues.corners[0]
	var sample: Dictionary = scene.course_cues.sample_at(float(corner["distance"]) - 50.0)
	scene.player_progress.reset(int(sample["index"]))
	scene.player_progress.update(sample["position"])
	car.speed = 50.0
	var advice: Dictionary = scene.course_cues.corner_advice(scene.player_progress.distance, car)
	var advisory := float(advice["speed"])
	GameSession.speed_unit = "kmh"
	hud._process(0.0)
	_check("km/h advisory unchanged", "ADVISORY %d KM/H" % (floori(advisory * 3.6 / 5.0) * 5) in hud._upcoming.text)
	GameSession.speed_unit = "mph"
	hud._process(0.0)
	_check("mph advisory converted", "ADVISORY %d MPH" % (floori(advisory * 2.2369362920544 / 5.0) * 5) in hud._upcoming.text
		and not ("KM/H" in hud._upcoming.text))
	GameSession.speed_unit = "kmh"

	# Results, retry and new countdown.
	race.state = RaceDirector.State.RESULTS
	hud._process(0.016)
	_check("results hide the driving readout", not driving.visible and driving.markers.is_empty())
	scene.restart_race()
	hud._process(0.016)
	_check("retry shows a fresh countdown readout", driving.visible and race.state == RaceDirector.State.COUNTDOWN
		and driving.markers.size() == 3 and driving.speed_value == DrivingHud.display_speed(car.speed, "kmh"))
	driving.clear()
	_check("clear resets speed and markers", driving.markers.is_empty() and driving.speed_value == 0)
	scene.queue_free()
	await get_tree().process_frame


func _remove_settings() -> void:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
