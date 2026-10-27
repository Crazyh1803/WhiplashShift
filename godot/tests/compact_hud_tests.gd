extends Node3D

const VIEWS: Array[Vector2] = [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080), Vector2(1152, 648)]
const PLAYER := "ghostwire" ## deliberately lower case and a pool name

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_compact_geometry()
	_test_label_fit()
	_test_roster()
	_test_map_labels()
	await _test_real_hud()
	await _test_restart()
	print("COMPACT HUD: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_compact_geometry() -> void:
	var band_h: float = (DashInstruments.layout(Vector2(1600, 900))["band"] as Rect2).size.y
	_check("band is about 160px, at least 25% shorter than the old 210px", absf(band_h - 160.0) < 0.5 and band_h <= 210.0 * 0.77)
	var outer := DashInstruments.BAND_FILL.a
	var well := DashInstruments.WELL_FILL.a
	_check("outer band is about half transparent", outer >= 0.4 and outer <= 0.6)
	_check("instrument wells are light", well >= 0.1 and well <= 0.25)
	var old_effective := 1.0 - (1.0 - 0.94) * (1.0 - 0.55)
	_check("effective layered opacity is far below the old near-opaque stack", DashInstruments.effective_alpha() <= 0.65
		and DashInstruments.effective_alpha() < old_effective - 0.3)
	_check("scenery still shows through the map panel", DashInstruments.effective_alpha(true) <= 0.75)
	_check("digit plate keeps speed readable without making the band opaque", DashInstruments.PLATE_FILL.a >= 0.4 and DashInstruments.PLATE_FILL.a <= 0.7)
	for view in VIEWS:
		var l := DashInstruments.layout(view)
		var b: Rect2 = l["band"]
		_check("compact band fits the viewport at %s" % view, Rect2(Vector2.ZERO, view).encloses(b) and absf(b.size.y - 160.0 * float(l["scale"])) < 0.5)
		_check("map gained route width at %s" % view, (l["map"] as Rect2).size.x > 420.0 * float(l["scale"]))


func _test_label_fit() -> void:
	var font := ThemeDB.fallback_font
	var boost_texts := ["BOOST UNCHARGED\nWHIPLASH TO CHARGE", "BOOST READY\nACCELERATE + [Q]", "BOOST FIRING  1.2s", "BOOST COOLING  8.0s"]
	for view in VIEWS:
		var l := DashInstruments.layout(view)
		var s: float = l["scale"]
		var parts := DashInstruments.systems_layout(l["systems"], s)
		var systems: Rect2 = l["systems"]
		var stacked: bool = (parts["boost"] as Rect2).end.y <= (parts["status"] as Rect2).position.y \
			and (parts["status"] as Rect2).end.y <= (parts["damage_label"] as Rect2).position.y \
			and (parts["damage_label"] as Rect2).end.y <= (parts["damage_bar"] as Rect2).position.y \
			and systems.encloses(parts["damage_bar"])
		_check("systems rows stack inside the compact well at %s" % view, stacked)
		var all_fit := true
		for text: String in boost_texts:
			var box: Vector2 = (parts["boost"] as Rect2).size
			var size := DashInstruments.fit_font_size(font, text, box, 12, 9, true)
			var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box.x, size)
			all_fit = all_fit and measured.y <= box.y and measured.x <= box.x
		_check("every boost state fits its row at %s" % view, all_fit)
		var route := DashInstruments.body(l["route"], s)
		var advice := "HAIRPIN RIGHT · IN 120m\nBRAKE BEFORE TURN · ADVISORY 100 KM/H"
		var advice_size := DashInstruments.fit_font_size(font, advice, route.size, 18, 9)
		var advice_box := font.get_multiline_string_size(advice, HORIZONTAL_ALIGNMENT_LEFT, -1.0, advice_size)
		_check("corner advice fits the route instrument at %s" % view, advice_box.x <= route.size.x and advice_box.y <= route.size.y)


func _test_roster() -> void:
	var pool := RacerCallsigns.POOL
	var unique := {}
	var short := true
	for name in pool:
		unique[name] = true
		short = short and name.length() <= 12 and name == name.to_upper()
	_check("pool has 24 unique callsigns of 12 characters or fewer", pool.size() == 24 and unique.size() == 24 and short)

	var rng := RandomNumberGenerator.new()
	var clean := true
	var players_ok := true
	for seed_value in 200:
		rng.seed = seed_value
		var picked := RacerCallsigns.draw(2, PLAYER, [], rng)
		clean = clean and picked.size() == 2 and picked[0] != picked[1] and picked.all(func(n: String) -> bool: return n in pool)
		players_ok = players_ok and not picked.any(func(n: String) -> bool: return n.to_upper() == PLAYER.to_upper())
	_check("every draw is two unique pool names", clean)
	_check("the player's name is excluded case-insensitively", players_ok)
	var hit_every_name := {}
	for seed_value in 400:
		rng.seed = seed_value
		for n in RacerCallsigns.draw(2, "", [], rng):
			hit_every_name[n] = true
	_check("random draws reach the whole pool, not a fixed pair", hit_every_name.size() == 24)

	rng.seed = 99
	var first := RacerCallsigns.draw(2, "ROADGHOST", [], rng)
	rng.seed = 99
	_check("a seeded rng is deterministic", RacerCallsigns.draw(2, "ROADGHOST", [], rng) == first)

	var fresh := true
	for seed_value in 100:
		rng.seed = seed_value
		var again := RacerCallsigns.draw(2, "ROADGHOST", first, rng)
		fresh = fresh and not again.has(first[0]) and not again.has(first[1])
	_check("a new draw avoids the previous roster while the pool allows", fresh)

	var almost_all: Array[String] = []
	for n in pool.slice(0, 23):
		almost_all.append(n)
	rng.seed = 5
	var squeezed := RacerCallsigns.draw(2, "ROADGHOST", almost_all, rng)
	_check("a nearly exhausted fresh pool still yields two unique names", squeezed.size() == 2 and squeezed[0] != squeezed[1] and squeezed.has(pool[23]))
	var many := RacerCallsigns.draw(30, "ROADGHOST", [], rng)
	var many_unique := {}
	for n in many:
		many_unique[n] = true
	_check("oversized requests stay unique with placeholders", many.size() == 30 and many_unique.size() == 30)


func _test_map_labels() -> void:
	var font := ThemeDB.fallback_font
	var bounds := Rect2(2.0, 2.0, 456.0, 92.0)
	var long_name := "AN EXTREMELY LONG CALLSIGN THAT KEEPS GOING"
	var cases := {
		"start grid, identical positions": [Vector2(60, 40), Vector2(60, 40), Vector2(60, 40)],
		"start grid, stacked a few pixels apart": [Vector2(60, 40), Vector2(63, 43), Vector2(58, 38)],
		"top-left corner": [Vector2(2, 2), Vector2(4, 3), Vector2(2, 4)],
		"bottom-right corner": [Vector2(458, 94), Vector2(456, 92), Vector2(458, 90)],
		"right edge cluster": [Vector2(455, 40), Vector2(452, 44), Vector2(456, 36)],
		"spread out": [Vector2(40, 30), Vector2(220, 50), Vector2(400, 70)],
	}
	var names := ["YOU", "DREADNOUGHT", long_name]
	for label: String in cases:
		var entries: Array = []
		var positions: Array = cases[label]
		for i in positions.size():
			entries.append({"pos": positions[i], "text": names[i]})
		var placed := DashInstruments.place_map_labels(entries, bounds, font, DrivingHud.LABEL_SIZE)
		var inside := placed.size() == 3
		var distinct := true
		var clear_of_markers := true
		var short_enough := true
		for i in placed.size():
			var rect: Rect2 = placed[i]["rect"]
			inside = inside and bounds.grow(0.01).encloses(rect)
			short_enough = short_enough and rect.size.x <= 121.0
			for j in placed.size():
				if j != i:
					distinct = distinct and not rect.intersects(placed[j]["rect"])
					var disc := Rect2(Vector2(positions[j]) - Vector2.ONE * 8.0, Vector2.ONE * 16.0)
					clear_of_markers = clear_of_markers and not rect.intersects(disc)
		_check("labels stay inside the map bounds: %s" % label, inside)
		_check("label boxes are distinct and clear of other markers: %s" % label, distinct and clear_of_markers)
		_check("long callsigns are shortened: %s" % label, short_enough and String(placed[2]["text"]).ends_with("…"))
	var lone := DashInstruments.place_map_labels([{"pos": Vector2(200, 40), "text": "GLITCH"}], bounds, font, DrivingHud.LABEL_SIZE)
	_check("an undisturbed label sits beside its marker without a leader", lone.size() == 1 and not bool(lone[0]["leader"])
		and (lone[0]["rect"] as Rect2).position.distance_to(Vector2(200, 40)) < 30.0)
	var crowd: Array = []
	for i in 6:
		crowd.append({"pos": Vector2(60, 40), "text": "ROAD HEX"})
	var displaced := DashInstruments.place_map_labels(crowd, bounds, font, DrivingHud.LABEL_SIZE)
	_check("crowded labels get a leader line to their marker", displaced.any(func(d: Dictionary) -> bool: return bool(d["leader"])))


func _spawn_scene(seed_value: int) -> Variant:
	GameSession.configure(PLAYER, "blackjack", ["boilerfang", "ramjet"])
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	scene.callsign_rng.seed = seed_value
	add_child(scene)
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
		driver.target.freeze = true
	scene.car.freeze = true
	return scene


func _test_real_hud() -> void:
	var scene: Variant = _spawn_scene(321)
	await get_tree().physics_frame
	var hud: Hud = scene.hud
	var race: RaceDirector = scene.race
	var driving: DrivingHud = hud.driving
	var items: RaceItems = scene.items
	var roster: Array[String] = scene.cpu_callsigns
	_check("the match has two unique CPU callsigns that are not the player", roster.size() == 2 and roster[0] != roster[1]
		and not roster.any(func(n: String) -> bool: return n.to_upper() == GameSession.callsign.to_upper()))
	_check("scene nodes and chassis ids keep their original names", scene.cpu_cars[0].name.begins_with("CPU_1_") and not scene.cpu_cars[0].name.contains(roster[0].replace(" ", "_")))

	# Names agree across the race record, the CPU readout, the map markers and the key.
	race.state = RaceDirector.State.RACING
	hud._process(0.016)
	await get_tree().process_frame
	var entrant_names: Array = race.entrants.map(func(e: Dictionary) -> String: return e["name"])
	_check("race entrants are the player and the callsigns", entrant_names == [GameSession.callsign, roster[0], roster[1]])
	_check("CPU readout shows each callsign", hud._cpu.text.contains(roster[0]) and hud._cpu.text.contains(roster[1]))
	_check("map markers carry the same names", driving.markers.map(func(m: Dictionary) -> String: return m["name"]) == ["YOU", roster[0], roster[1]])
	_check("key strip lists the same names", driving.legend.map(func(e: Dictionary) -> String: return e["name"]) == ["YOU", roster[0], roster[1]])
	_check("map shows a name box per marker", driving.labels.size() == 3 and driving.labels.map(func(d: Dictionary) -> String: return d["text"].trim_suffix("…")).all(
		func(t: String) -> bool: return t == "YOU" or roster[0].begins_with(t) or roster[1].begins_with(t)))
	for i in 5:
		hud._process(0.016)
	_check("callsigns are stable frame to frame", scene.cpu_callsigns == roster and hud.cpu_callsigns == roster)

	# Start grid: cars sit together, labels still land inside the map and apart.
	var bounds := driving.label_bounds()
	var boxes: Array[Rect2] = []
	for entry: Dictionary in driving.labels:
		boxes.append(entry["rect"])
	var apart := true
	for i in boxes.size():
		apart = apart and bounds.grow(0.01).encloses(boxes[i]) and Rect2(Vector2.ZERO, driving.map_size).encloses(boxes[i])
		for j in range(i + 1, boxes.size()):
			apart = apart and not boxes[i].intersects(boxes[j])
	_check("real clustered start-grid labels are bounded and distinct", apart)
	var colors: Array = driving.markers.map(func(m: Dictionary) -> Color: return m["color"])
	_check("marker colours stay stable and the player differs", colors == [DrivingHud.racer_color(0), DrivingHud.racer_color(1), DrivingHud.racer_color(2)]
		and colors[0] != colors[1] and colors[1] != colors[2] and colors[0] != colors[2])

	# Boost labels really show both lines.
	var boost_states: Array[Dictionary] = [
		{"charge": 0, "time": 0.0, "cool": 0.0, "lines": 2},
		{"charge": 1, "time": 0.0, "cool": 0.0, "lines": 2},
		{"charge": 1, "time": 1.4, "cool": 0.0, "lines": 1},
		{"charge": 0, "time": 0.0, "cool": 6.0, "lines": 1},
	]
	var all_visible := true
	for state: Dictionary in boost_states:
		scene.car.boost_charge = int(state["charge"])
		scene.car.boost_time = float(state["time"])
		scene.car.boost_cooldown = float(state["cool"])
		hud._process(0.016)
		await get_tree().process_frame
		var label: Label = hud._boost_status
		var lines := label.get_line_count()
		all_visible = all_visible and lines == int(state["lines"]) and label.get_visible_line_count() == lines and not label.text.is_empty() \
			and label.get_rect().size.y >= float(lines) * float(label.get_theme_font_size("font_size"))
	_check("every boost state shows all of its text lines in the real label", all_visible)
	scene.car.boost_charge = 0
	scene.car.boost_time = 0.0
	scene.car.boost_cooldown = 0.0

	# Current low-grip and smoke lamps stay; they report the present state, not a forecast.
	items.oil_time[0] = 2.0
	items.obscured[0] = true
	hud._process(0.016)
	await get_tree().process_frame
	_check("current low-grip and smoke lamps remain", hud._item_status.text.contains("LOW GRIP") and hud._item_status.text.contains("SMOKE")
		and hud._item_status.get_visible_line_count() >= 1)
	items.oil_time[0] = 0.0
	items.obscured[0] = false

	# Corners and braking advice survive; terrain transitions are gone.
	var event: Dictionary = scene.course_cues.events[0]
	var approach: Dictionary = scene.course_cues.sample_at(float(event["distance"]) - 40.0)
	scene.player_progress.reset(int(approach["index"]))
	scene.player_progress.update(approach["position"])
	scene.car.speed = 20.0
	hud._process(0.0)
	var terrain_words: Array[String] = ["PREPARE END", "HOLD END", " READY", "LIFT OFF"]
	for sid in Surfaces.NAMES.size():
		terrain_words.append("%s IN " % Surfaces.NAMES[sid])
	var forecast_free := true
	for word in terrain_words:
		forecast_free = forecast_free and not hud._upcoming.text.contains(word)
	_check("approaching a surface change shows no terrain prediction", forecast_free)
	var corner: Dictionary = scene.course_cues.corners[0]
	var turn: Dictionary = scene.course_cues.sample_at(float(corner["distance"]) - 50.0)
	scene.player_progress.reset(int(turn["index"]))
	scene.player_progress.update(turn["position"])
	scene.car.speed = 50.0
	hud._process(0.0)
	await get_tree().process_frame
	_check("real corners and braking advice are preserved", hud._upcoming.text.contains("ADVISORY") and hud._upcoming.text.contains("BRAKE BEFORE TURN"))
	var route: Rect2 = DashInstruments.body(DashInstruments.layout(get_viewport().get_visible_rect().size)["route"], DashInstruments.view_scale(get_viewport().get_visible_rect().size))
	_check("corner advice stays inside the route instrument", route.encloses(hud._upcoming.get_rect()) and hud._upcoming.get_visible_line_count() >= 2)
	_check("the route label is no longer named for terrain", hud.get_node_or_null("UpcomingTerrain") == null)

	# Results show the same callsigns.
	race.state = RaceDirector.State.RESULTS
	hud._process(0.016)
	_check("results list the same callsigns", hud._results_text.text.contains(roster[0]) and hud._results_text.text.contains(roster[1]))
	scene.queue_free()
	await get_tree().process_frame


func _test_restart() -> void:
	var scene: Variant = _spawn_scene(77)
	await get_tree().physics_frame
	var hud: Hud = scene.hud
	var race: RaceDirector = scene.race
	var first: Array[String] = scene.cpu_callsigns.duplicate()
	var colors_before: Array = []
	hud._process(0.016)
	for marker: Dictionary in hud.driving.markers:
		colors_before.append(marker["color"])
	scene.restart_race()
	_check("restart before the results leaves the roster untouched", scene.cpu_callsigns == first)
	race.state = RaceDirector.State.RESULTS
	var seen := {}
	for n in first:
		seen[n] = true
	var players_ok := true
	var fresh_each_time := true
	for round_index in 6:
		var before: Array[String] = scene.cpu_callsigns.duplicate()
		race.state = RaceDirector.State.RESULTS
		scene.restart_race()
		var after: Array[String] = scene.cpu_callsigns
		fresh_each_time = fresh_each_time and after.size() == 2 and after[0] != after[1] and not after.has(before[0]) and not after.has(before[1])
		players_ok = players_ok and not after.any(func(n: String) -> bool: return n.to_upper() == GameSession.callsign.to_upper())
		_check("round %d: race record, HUD and scene share the new roster" % round_index,
			race.entrants.map(func(e: Dictionary) -> String: return e["name"]) == [GameSession.callsign, after[0], after[1]] and hud.cpu_callsigns == after)
		for n in after:
			seen[n] = true
	_check("Race Again draws fresh unique non-player identities each time", fresh_each_time and players_ok)
	_check("several restarts produce more than the first pair", seen.size() > 2)
	hud._process(0.016)
	await get_tree().process_frame
	var after_names: Array = hud.driving.markers.map(func(m: Dictionary) -> String: return m["name"])
	_check("the map follows the restarted roster", after_names == ["YOU", scene.cpu_callsigns[0], scene.cpu_callsigns[1]])
	var colors_after: Array = hud.driving.markers.map(func(m: Dictionary) -> Color: return m["color"])
	_check("marker colours do not change with new names", colors_after == colors_before)
	_check("the CPU readout shows the restarted roster", hud._cpu.text.contains(scene.cpu_callsigns[0]) and hud._cpu.text.contains(scene.cpu_callsigns[1]))
	scene.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
