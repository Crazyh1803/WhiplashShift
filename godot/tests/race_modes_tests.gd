extends Node3D

const TEST_MENU := preload("res://tests/race_modes_test_menu.gd")
const ERROR_COLOR := Color("ff7a5c")
const BUILT_LAPS: Array[int] = [1, 7, 99]

var _pass := 0
var _fail := 0
var _scratch := ""
var _saved := {}
var _continue_events := 0


func _ready() -> void:
	_scratch = "user://race_modes_tests_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_scratch)
	_snapshot_session()
	GameSession.settings_path = _scratch.path_join("settings.cfg")
	_test_courses()
	_test_reverse_synthetic_relief()
	_test_season_run()
	_test_session()
	await _test_menu_boot()
	await _test_menu_navigation()
	await _test_menu_single_and_garage()
	await _test_menu_pending_season()
	await _test_menu_custom_editor()
	await _test_menu_import_failures()
	await _test_menu_settings_and_about()
	for id: String in CourseCatalog.IDS:
		for reverse: bool in [false, true]:
			await _test_lap_run(id, 1, reverse)
	await _test_lap_run("block_circuit", 7, false)
	await _test_lap_run("block_circuit", 7, true)
	await _test_season_flow()
	_restore_session()
	_remove_recursive(_scratch)
	print("RACE_MODES: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _snapshot_session() -> void:
	for key: String in ["course_id", "race_laps", "race_reverse", "race_setup_active", "season", "callsign",
			"selected_vehicle_id", "cpu_vehicle_ids", "cpu_difficulty", "speed_unit", "settings_path"]:
		_saved[key] = GameSession.get(key)


func _restore_session() -> void:
	for key: String in _saved:
		GameSession.set(key, _saved[key])


func _reset_session() -> void:
	GameSession.season = null
	GameSession.race_setup_active = false
	GameSession.course_id = "split_shift"
	GameSession.race_laps = 3
	GameSession.race_reverse = false
	GameSession.set_cpu_difficulty("medium")


func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for entry in dir.get_files():
		dir.remove(entry)
	for entry in dir.get_directories():
		_remove_recursive(path.path_join(entry))
	DirAccess.remove_absolute(path)


func _season_data(season_name: String, races: Array) -> Dictionary:
	return {"format": SeasonDefinition.FORMAT, "version": SeasonDefinition.VERSION, "name": season_name, "races": races}


func _three_races() -> Array:
	return [{"course_id": "block_circuit", "laps": 1, "reverse": false},
		{"course_id": "split_shift", "laps": 2, "reverse": true},
		{"course_id": "block_circuit", "laps": 7, "reverse": true}]


func _test_courses() -> void:
	var old := TrackData.build_course()
	var golden := CourseCatalog.build_course("split_shift")
	_check("Split Shift defaults keep the rotated golden course", golden.points == old.points.slice(16) + old.points.slice(0, 16)
		and golden.total_length == old.total_length and golden.default_laps == old.default_laps
		and not golden.is_reverse and golden.geometry() == golden)
	for id: String in CourseCatalog.IDS:
		for laps: int in BUILT_LAPS:
			var forward := CourseCatalog.build_course(id, false, laps)
			var reverse := CourseCatalog.build_course(id, true, laps)
			var label := "%s laps %d" % [id, laps]
			_check(label + " forward validates and honours laps", forward.validate().is_empty() and forward.default_laps == laps and not forward.is_reverse)
			_check(label + " reverse validates and honours laps", reverse != null and reverse.validate().is_empty()
				and reverse.default_laps == laps and reverse.is_reverse and reverse.course_id == id)
			if reverse == null:
				continue
			_check(label + " reverse edge metadata follows the preceding forward edge", _reverse_error(forward.points, reverse.points) == "",
				_reverse_error(forward.points, reverse.points))
			_check(label + " reverse keeps forward geometry points", reverse.geometry().points == forward.points
				and reverse.geometry().validate().is_empty() and reverse.geometry() != reverse)
			_check(label + " reverse keeps total length", absf(reverse.total_length - forward.total_length) < 0.01)
			_check(label + " reverse tangents are not worse than forward", _backward_edges(reverse.points) <= _backward_edges(forward.points))
			for course: CourseDefinition in [forward, reverse]:
				for gap: int in [14, 4, 9]:
					var point: Dictionary = course.points[course.points.size() - gap]
					_check("%s %s grid slot %d is dry and aligned" % [label, "reverse" if course.is_reverse else "forward", gap],
						point["s"] == Surfaces.Id.TARMAC and not point.has("relief")
						and (point["dir"] as Vector3).dot(course.points[0]["dir"]) > 0.999)
			_check(label + " reverse double reversal returns the original",
				CourseCatalog.reverse_points(CourseCatalog.reverse_points(forward.points)) == forward.points)


func _reverse_error(forward: Array, reverse: Array) -> String:
	var count := forward.size()
	if reverse.size() != count:
		return "point count differs"
	var first := -1
	for i in count:
		if (forward[i] as Dictionary)["pos"] == (reverse[0] as Dictionary)["pos"]:
			first = i
			break
	if first < 0:
		return "reverse start is not a forward vertex"
	for k in count:
		var vertex := posmod(first - k, count)
		var edge := posmod(vertex - 1, count)
		var source: Dictionary = forward[vertex]
		var preceding: Dictionary = forward[edge]
		var out: Dictionary = reverse[k]
		if out["pos"] != source["pos"] or out["w"] != source["w"]:
			return "pos/w changed at reverse index %d" % k
		if not (out["dir"] as Vector3).is_equal_approx(-(source["dir"] as Vector3)):
			return "dir not negated at reverse index %d" % k
		if out["s"] != preceding["s"] or not is_equal_approx(float(out["dist"]), float(preceding["dist"])):
			return "s/dist not from preceding edge at reverse index %d" % k
		if out.has("relief") != preceding.has("relief") or (out.has("relief") and out["relief"] != preceding["relief"]):
			return "relief not from preceding edge at reverse index %d" % k
	return ""


func _backward_edges(points: Array) -> int:
	var backward := 0
	for i in points.size():
		var chord: Vector3 = (points[(i + 1) % points.size()]["pos"] as Vector3) - (points[i]["pos"] as Vector3)
		if chord.normalized().dot(points[i]["dir"]) < 0.0:
			backward += 1
	return backward


func _test_reverse_synthetic_relief() -> void:
	var ramp := {"shape": "ramp", "height": 1.0, "rise": 10.0, "fall": 12.0}
	var forward: Array = []
	for i in 6:
		var point := {"pos": Vector3(i * 10.0, 0.0, 0.0), "dir": Vector3(1, 0, 0), "w": 24.0 + i, "s": Surfaces.Id.TARMAC, "dist": 10.0 + i}
		if i == 2:
			point["relief"] = ramp.duplicate(true)
		forward.append(point)
	var before := forward.duplicate(true)
	var reversed := CourseCatalog.reverse_points(forward)
	_check("synthetic reverse leaves its input untouched", forward == before)
	var carriers := 0
	for point: Dictionary in reversed:
		if point.has("relief"):
			carriers += 1
			_check("synthetic relief dictionary is preserved unchanged", point["relief"] == ramp)
			_check("synthetic relief sits at the vertex after the forward edge", point["pos"] == forward[3]["pos"])
			(point["relief"] as Dictionary)["height"] = 1.4
	_check("exactly one reversed point carries the relief", carriers == 1)
	_check("reversed relief is a copy, not shared", forward[2]["relief"] == ramp)
	_check("synthetic round trip restores the original", CourseCatalog.reverse_points(CourseCatalog.reverse_points(before)) == before)


func _test_season_run() -> void:
	var run := SeasonRun.new().configure(_season_data("Run", _three_races()))
	_check("fresh run is empty and incomplete", run.round_index == 0 and run.points == [0, 0, 0] and run.wins == [0, 0, 0]
		and run.pending.is_empty() and not run.is_complete() and run.entrants.is_empty())
	_check("fresh run exposes first race options", run.race_options() == _three_races()[0])
	var options := run.race_options()
	options["laps"] = 55
	_check("race options are copies", run.race_options()["laps"] == 1)
	_check("commit without a pending result is ignored", not run.commit() and run.round_index == 0)
	_check("malformed pending orders are rejected", not run.set_pending([0, 0, 1]) and not run.set_pending([0, 1, 3]) and not run.set_pending([0, 1])
		and run.pending.is_empty())
	var roster: Array[Dictionary] = [{"callsign": "A", "vehicle_id": "blackjack"}, {"callsign": "B", "vehicle_id": "ramjet"}, {"callsign": "C", "vehicle_id": "helix"}]
	run.set_roster(roster.slice(0, 2))
	_check("short roster is rejected", run.entrants.is_empty())
	run.set_roster(roster)
	var other: Array[Dictionary] = [{"callsign": "X", "vehicle_id": "x"}, {"callsign": "Y", "vehicle_id": "y"}, {"callsign": "Z", "vehicle_id": "z"}]
	run.set_roster(other)
	_check("roster identities are stable once set", run.entrants == roster)
	_check("pending result accepted", run.set_pending([0, 1, 2]))
	_check("no score before Continue", run.points == [0, 0, 0] and run.wins == [0, 0, 0] and run.round_index == 0)
	_check("provisional table shows 10/6/3 without committing", run.table_lines(true)[0].contains("PROVISIONAL")
		and run.table_lines(true)[1] == "1. A   10 PTS   1 WINS" and run.table_lines(true)[2] == "2. B   6 PTS   0 WINS"
		and run.table_lines(true)[3] == "3. C   3 PTS   0 WINS" and run.points == [0, 0, 0])
	_check("committed table has no provisional heading", not run.table_lines(false)[0].contains("PROVISIONAL"))
	run.pending.clear()
	_check("retry clears pending without scoring", run.points == [0, 0, 0] and run.round_index == 0 and not run.commit())
	_check("retry result replaces the earlier one", run.set_pending([2, 0, 1]) and run.set_pending([0, 1, 2]))
	_check("first commit awards 10/6/3", run.commit() and run.points == [10, 6, 3] and run.wins == [1, 0, 0] and run.round_index == 1)
	_check("a commit never double scores", not run.commit() and run.points == [10, 6, 3] and run.results == [[0, 1, 2]])
	_check("second race options advance", run.race_options() == _three_races()[1])
	run.set_pending([1, 0, 2])
	run.commit()
	_check("second commit accumulates", run.points == [16, 16, 6] and run.wins == [1, 1, 0])
	_check("equal points and wins order by entrant slot", run.table_lines(false)[1].begins_with("1. A") and run.table_lines(false)[2].begins_with("2. B"))
	run.set_pending([2, 1, 0])
	run.commit()
	_check("three-race totals are complete", run.points == [19, 22, 16] and run.wins == [1, 1, 1] and run.is_complete())
	_check("standings are ordered by points", run.table_lines(false)[1].begins_with("1. B") and run.table_lines(false)[3].begins_with("3. C"))
	_check("completed run exposes no options and rejects more", run.race_options().is_empty() and not run.set_pending([0, 1, 2]) and not run.commit()
		and run.points == [19, 22, 16] and run.results.size() == 3)
	var tied := SeasonRun.new().configure(_season_data("Tie", _three_races()))
	for order: Array[int] in [[0, 1, 2], [1, 2, 0], [2, 0, 1]]:
		tied.set_pending(order)
		tied.commit()
	_check("three way tie keeps entrant order", tied.points == [19, 19, 19] and tied.table_lines(false)[1].begins_with("1. YOU")
		and tied.table_lines(false)[3].begins_with("3. RIVAL 2"))
	var again := tied.configure(_season_data("Again", _three_races()))
	_check("configure resets every counter", again == tied and tied.points == [0, 0, 0] and tied.results.is_empty() and tied.round_index == 0 and tied.entrants.is_empty())


func _test_session() -> void:
	_reset_session()
	_check("default race options keep the old three lap forward race", GameSession.race_options() == {"course_id": "split_shift", "laps": 3, "reverse": false})
	GameSession.begin_single("block_circuit", 7, true)
	_check("single race reaches the session", GameSession.course_id == "block_circuit" and GameSession.race_laps == 7 and GameSession.race_reverse
		and GameSession.race_setup_active and GameSession.season == null)
	_check("single race options are reported", GameSession.race_options() == {"course_id": "block_circuit", "laps": 7, "reverse": true})
	GameSession.begin_single("nowhere", 0, false)
	_check("single race sanitises track and low laps", GameSession.course_id == "split_shift" and GameSession.race_laps == 1)
	GameSession.begin_single("block_circuit", 500, false)
	_check("single race clamps high laps", GameSession.race_laps == 99)
	var broken := _season_data("Broken", [{"course_id": "nowhere", "laps": 3, "reverse": false}])
	_check("invalid season is refused without disturbing the session", not GameSession.begin_season(broken) and GameSession.season == null and GameSession.race_laps == 99)
	_check("valid season starts", GameSession.begin_season(_season_data("Three", _three_races()), true))
	var run: SeasonRun = GameSession.season
	_check("season marks builtin and prepares first race", run.builtin and GameSession.course_id == "block_circuit" and GameSession.race_laps == 1
		and not GameSession.race_reverse and GameSession.race_setup_active)
	_check("season race options come from the run", GameSession.race_options() == _three_races()[0])
	GameSession.begin_single("split_shift", 2, true)
	_check("a single race detaches the season", GameSession.season == null and GameSession.race_options()["reverse"])
	GameSession.begin_season(_season_data("Three", _three_races()))
	_check("custom season is not builtin", not GameSession.season.builtin)
	_check("advance without a pending result is refused", not GameSession.advance_season() and GameSession.season.round_index == 0)
	GameSession.season.set_pending([0, 1, 2])
	_check("advance scores and prepares round two", GameSession.advance_season() and GameSession.season.points == [10, 6, 3]
		and GameSession.course_id == "split_shift" and GameSession.race_laps == 2 and GameSession.race_reverse)
	_check("round two options match", GameSession.race_options() == _three_races()[1])
	GameSession.season.set_pending([1, 0, 2])
	GameSession.advance_season()
	GameSession.season.set_pending([2, 0, 1])
	_check("final advance completes the season", GameSession.advance_season() and GameSession.season.is_complete())
	_check("extra advance is ignored once complete", not GameSession.advance_season() and GameSession.season.results.size() == 3)
	GameSession.configure("Pilot", "blackjack", ["ramjet", "helix"])
	var roster: Array[Dictionary] = [{"callsign": "KEEP", "vehicle_id": "blackjack"}, {"callsign": "R1", "vehicle_id": "knifeedge"}, {"callsign": "R2", "vehicle_id": "ramjet"}]
	GameSession.season = SeasonRun.new().configure(_season_data("Roster", _three_races()))
	GameSession.season.set_roster(roster)
	GameSession.configure("Other", "helix", ["blackjack", "blackjack"])
	_check("season roster overrides later configure calls", GameSession.callsign == "KEEP" and GameSession.cpu_vehicle_ids == ["knifeedge", "ramjet"]
		and GameSession.selected_vehicle_id == "helix")
	_reset_session()


func _test_menu_boot() -> void:
	_reset_session()
	_check("main scene boots the main menu", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu.tscn")
	var scene: Variant = load("res://scenes/main_menu.tscn").instantiate()
	scene.library.directory = _scratch.path_join("boot_library")
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("boot scene is the MainMenu on the home page", scene is MainMenu and scene._page_name == "home" and scene._pages["home"].visible)
	_check("boot menu lists every page", scene._pages.keys() == MainMenu.PAGES)
	_check("home focus lands on a visible button", get_viewport().gui_get_focus_owner() == scene._first_focus["home"])
	_check("resume is hidden without a season", not scene._resume_button.visible)
	scene.queue_free()
	await get_tree().process_frame


func _menu() -> Variant:
	var menu: Variant = TEST_MENU.new()
	menu.library.directory = _scratch.path_join("library")
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	await get_tree().process_frame
	return menu


func _drop(menu: Node) -> void:
	menu.queue_free()
	await get_tree().process_frame


func _descendants(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		out.append(child)
		_descendants(child, out)
	return out


func _button(root: Node, text: String) -> Button:
	for node in _descendants(root):
		if node is Button and not node is OptionButton and (node as Button).text == text:
			return node
	return null


func _named(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func _press(button: BaseButton) -> void:
	button.pressed.emit()


func _test_menu_navigation() -> void:
	_reset_session()
	var menu: Variant = await _menu()
	var routes := {"SeasonButton": "season", "SingleButton": "single", "CustomButton": "custom", "SettingsButton": "settings", "AboutButton": "about"}
	for button_name: String in routes:
		var page: String = routes[button_name]
		var button := _named(menu, button_name) as Button
		_check(button_name + " exists on home", button != null and button.is_visible_in_tree())
		_press(button)
		var only_page := true
		for key: String in menu._pages:
			only_page = only_page and menu._pages[key].visible == (key == page)
		_check(button_name + " opens exactly the " + page + " page", menu._page_name == page and only_page)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(page + " focus lands inside the page", menu.get_viewport().gui_get_focus_owner() != null
			and (menu._pages[page] as Control).is_ancestor_of(menu.get_viewport().gui_get_focus_owner()))
		_press(_named(menu._pages[page], "BackButton"))
		_check(page + " back button returns home", menu._page_name == "home")
		_press(button)
		var cancel := InputEventAction.new()
		cancel.action = "ui_cancel"
		cancel.pressed = true
		menu._unhandled_input(cancel)
		_check(page + " escape returns home", menu._page_name == "home")
	var labels := 0
	var coming := 0
	var preview := 0
	for node in _descendants(menu._pages["season"]):
		if node is Label:
			labels += 1
			coming += int((node as Label).text.ends_with("COMING SOON"))
			preview += int((node as Label).text.ends_with("PLAYABLE PREVIEW"))
	_check("season page labels one preview and eight coming soon", labels > 9 and preview == 1 and coming == 8)
	_press(_named(menu, "StartSeasonOne"))
	_check("Season 1 preview starts a builtin one race season", menu.garage_requests == 1 and GameSession.season != null and GameSession.season.builtin
		and GameSession.season.definition["races"].size() == 1 and GameSession.course_id == "block_circuit")
	await _drop(menu)
	_reset_session()


func _test_menu_single_and_garage() -> void:
	_reset_session()
	var menu: Variant = await _menu()
	var course: OptionButton = menu._single_course
	var ids: Array[String] = []
	for i in course.item_count:
		ids.append(String(course.get_item_metadata(i)))
	_check("single race offers exactly the built courses", ids == CourseCatalog.IDS)
	var laps: SpinBox = menu._single_laps
	_check("laps spinner spans 1 to 99 with the old default", laps.min_value == 1 and laps.max_value == 99 and laps.value == 3)
	laps.value = 150
	_check("laps spinner clamps high", laps.value == 99)
	laps.value = 0
	_check("laps spinner clamps low", laps.value == 1)
	course.select(ids.find("split_shift"))
	laps.value = 7
	menu._single_direction.select(1)
	_press(_named(menu, "ChooseVehicle"))
	_check("single selection arrives in the session", menu.garage_requests == 1 and GameSession.course_id == "split_shift" and GameSession.race_laps == 7
		and GameSession.race_reverse and GameSession.season == null and GameSession.race_setup_active)
	course.select(ids.find("block_circuit"))
	laps.value = 5
	menu._single_direction.select(0)
	_press(_named(menu, "ChooseVehicle"))
	_check("second selection replaces the first", menu.garage_requests == 2 and GameSession.course_id == "block_circuit" and GameSession.race_laps == 5
		and not GameSession.race_reverse)
	await _drop(menu)
	GameSession.begin_single("block_circuit", 5, true)
	GameSession.set_cpu_difficulty("easy")
	var profile := _scratch.path_join("garage_profile.cfg")
	var config := ConfigFile.new()
	config.set_value("profile", "callsign", "PROFILE")
	config.set_value("profile", "course", "split_shift")
	config.set_value("profile", "cpu_difficulty", "hard")
	config.save(profile)
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	garage.profile_path = profile
	add_child(garage)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("garage profile does not override menu race options", GameSession.course_id == "block_circuit" and GameSession.race_laps == 5
		and GameSession.race_reverse and GameSession.cpu_difficulty == "easy" and GameSession.race_setup_active)
	_check("garage locks the course selector while race setup is active", garage._course.disabled and garage._course.get_item_metadata(garage._course.selected) == "block_circuit")
	garage.queue_free()
	await get_tree().process_frame
	_reset_session()


func _valid_draft(menu: Variant) -> void:
	menu._season_name.text = "Grand Tour"
	menu._draft_races.clear()
	for race: Dictionary in _three_races():
		menu._draft_races.append(race.duplicate())
	menu._refresh_races()


func _test_menu_pending_season() -> void:
	_reset_session()
	GameSession.begin_season(_season_data("Live Season", _three_races()))
	var live: SeasonRun = GameSession.season
	var menu: Variant = await _menu()
	menu._show_page("home")
	_check("resume appears for a season in progress", menu._resume_button.visible and menu._resume_button.text.contains("LIVE SEASON"))
	_press(menu._resume_button)
	_check("resume reopens the garage without touching the run", menu.garage_requests == 1 and GameSession.season == live and live.round_index == 0)
	_press(_named(menu, "SingleButton"))
	_press(_named(menu, "ChooseVehicle"))
	_check("single race asks before replacing a season", menu._confirm.visible and menu.garage_requests == 1 and GameSession.season == live)
	menu._confirm.get_cancel_button().pressed.emit()
	_check("cancel keeps the season and does nothing", not menu._confirm.visible and menu.garage_requests == 1 and GameSession.season == live
		and GameSession.course_id == "block_circuit")
	_press(_named(menu, "ChooseVehicle"))
	menu._confirm.get_ok_button().pressed.emit()
	_check("confirm replaces the season with the single race", menu.garage_requests == 2 and GameSession.season == null and GameSession.race_setup_active)
	GameSession.begin_season(_season_data("Live Season", _three_races()))
	live = GameSession.season
	_valid_draft(menu)
	menu._show_page("custom")
	_press(_named(menu, "StartCustom"))
	_check("custom start asks before replacing a season", menu._confirm.visible and GameSession.season == live and menu.garage_requests == 2)
	menu._confirm.get_cancel_button().pressed.emit()
	_check("cancelled custom start keeps the old season", GameSession.season == live and menu.garage_requests == 2)
	_press(_named(menu, "StartCustom"))
	menu._confirm.get_ok_button().pressed.emit()
	_check("confirmed custom start swaps in the new season", GameSession.season != live and GameSession.season.definition["name"] == "Grand Tour"
		and menu.garage_requests == 3)
	_press(_named(menu, "StartSeasonOne"))
	_check("Season 1 also asks first", menu._confirm.visible and GameSession.season.definition["name"] == "Grand Tour")
	menu._confirm.get_cancel_button().pressed.emit()
	await _drop(menu)
	var done := SeasonRun.new().configure(_season_data("Done", _three_races()))
	var roster: Array[Dictionary] = [{"callsign": "ONE", "vehicle_id": "blackjack"}, {"callsign": "TWO", "vehicle_id": "ramjet"}, {"callsign": "THREE", "vehicle_id": "helix"}]
	done.set_roster(roster)
	for i in 3:
		done.set_pending([0, 1, 2])
		done.commit()
	GameSession.season = done
	menu = await _menu()
	_check("a finished season opens on final standings", menu._page_name == "standings" and menu._standings_label.text.contains("1. ONE   30 PTS   3 WINS"))
	_press(_named(menu, "StandingsHome"))
	_check("standings return home without a resume button", menu._page_name == "home" and not menu._resume_button.visible)
	_press(_named(menu, "SingleButton"))
	_press(_named(menu, "ChooseVehicle"))
	_check("a finished season needs no replacement prompt", not menu._confirm.visible and menu.garage_requests == 1 and GameSession.season == null)
	await _drop(menu)
	_reset_session()


func _test_menu_custom_editor() -> void:
	_reset_session()
	var menu: Variant = await _menu()
	menu._show_page("custom")
	menu._season_name.text = "Editor Cup"
	var courses: OptionButton = menu._entry_course
	courses.select(CourseCatalog.IDS.find("split_shift"))
	menu._entry_laps.value = 7
	menu._entry_direction.select(1)
	_press(_named(menu, "AddRace"))
	courses.select(CourseCatalog.IDS.find("block_circuit"))
	menu._entry_laps.value = 2
	menu._entry_direction.select(0)
	_press(_named(menu, "AddRace"))
	menu._entry_laps.value = 99
	_press(_named(menu, "AddRace"))
	_check("add appends races in order", menu._draft_races == [{"course_id": "split_shift", "laps": 7, "reverse": true},
		{"course_id": "block_circuit", "laps": 2, "reverse": false}, {"course_id": "block_circuit", "laps": 99, "reverse": false}]
		and menu._race_list.item_count == 3)
	_check("list text names laps and direction", menu._race_list.get_item_text(0).contains("7 laps") and menu._race_list.get_item_text(0).contains("Reverse")
		and menu._race_list.get_item_text(1).contains("Forward"))
	menu._race_list.select(1)
	menu._race_list.item_selected.emit(1)
	_check("selecting a row loads it into the entry controls", menu._entry_laps.value == 2 and menu._entry_direction.selected == 0
		and menu._selected_course(courses) == "block_circuit")
	menu._entry_laps.value = 4
	menu._entry_direction.select(1)
	_press(_named(menu, "UpdateRace"))
	_check("update rewrites only the selected race", menu._draft_races[1] == {"course_id": "block_circuit", "laps": 4, "reverse": true}
		and menu._draft_races[0]["laps"] == 7 and menu._draft_races[2]["laps"] == 99)
	_press(_button(menu, "MOVE UP"))
	_check("move up swaps with the previous race", menu._draft_races[0]["laps"] == 4 and menu._draft_races[1]["laps"] == 7 and menu._selected_index() == 0)
	_press(_button(menu, "MOVE UP"))
	_check("move up at the top is a no-op", menu._draft_races[0]["laps"] == 4 and menu._selected_index() == 0)
	_press(_button(menu, "MOVE DOWN"))
	_press(_button(menu, "MOVE DOWN"))
	_check("move down walks the race to the bottom", menu._draft_races[2]["laps"] == 4 and menu._selected_index() == 2)
	_press(_button(menu, "MOVE DOWN"))
	_check("move down at the bottom is a no-op", menu._draft_races[2]["laps"] == 4)
	_press(_named(menu, "RemoveRace"))
	_check("remove drops the selected race", menu._draft_races.size() == 2 and menu._draft_races[0]["laps"] == 7 and menu._draft_races[1]["laps"] == 99)
	menu._race_list.deselect_all()
	_press(_named(menu, "UpdateRace"))
	_check("update without a selection reports an error", menu._status.get_theme_color("font_color") == ERROR_COLOR and menu._draft_races.size() == 2)
	_press(_named(menu, "RemoveRace"))
	_check("remove without a selection reports an error", menu._status.get_theme_color("font_color") == ERROR_COLOR and menu._draft_races.size() == 2)
	var snapshot: Array = menu._draft_races.duplicate(true)
	_press(_named(menu, "SaveSeason"))
	var saved := menu.library.list_seasons()
	_check("save writes one library entry and selects it", saved.size() == 1 and saved[0]["name"] == "Editor Cup" and saved[0]["race_count"] == 2
		and menu._saved_seasons.item_count == 1 and menu._status.get_theme_color("font_color") != ERROR_COLOR)
	_check("library lives in the scratch folder", FileAccess.file_exists(_scratch.path_join("library").path_join(saved[0]["id"] + ".json")))
	menu._draft_races.clear()
	menu._refresh_races()
	menu._season_name.text = "Scratch"
	_press(_named(menu, "LoadSeason"))
	_check("load restores the saved draft", menu._draft_races == snapshot and menu._season_name.text == "Editor Cup" and menu._race_list.item_count == 2)
	var export_path := _scratch.path_join("export.json")
	menu._export_file(export_path)
	_check("export writes a portable file", FileAccess.file_exists(export_path) and menu._status.text == "Season exported.")
	menu._draft_races.clear()
	menu._season_name.text = "Other"
	menu._import_file(export_path)
	_check("import of the exported file restores the draft", menu._draft_races == snapshot and menu._season_name.text == "Editor Cup")
	_press(_button(menu, "MAKE CODE"))
	var code: String = menu._share_text.text
	_check("make code produces a WS1 code", code.begins_with(SeasonDefinition.SHARE_PREFIX))
	menu._draft_races.clear()
	menu._season_name.text = ""
	menu._refresh_races()
	_press(_button(menu, "IMPORT CODE"))
	_check("share code round trip restores the draft", menu._draft_races == snapshot and menu._season_name.text == "Editor Cup")
	menu._share_text.text = ""
	_press(_button(menu, "COPY"))
	_check("copy with nothing to share reports an error", menu._status.get_theme_color("font_color") == ERROR_COLOR)
	menu._season_name.text = "   "
	_press(_named(menu, "SaveSeason"))
	_check("blank names are not saved", menu.library.list_seasons().size() == 1 and menu._status.get_theme_color("font_color") == ERROR_COLOR)
	menu._season_name.text = "Editor Cup"
	menu._draft_races.clear()
	_press(_named(menu, "StartCustom"))
	_check("empty draft cannot start", menu.garage_requests == 0 and GameSession.season == null and menu._status.get_theme_color("font_color") == ERROR_COLOR)
	for i in SeasonDefinition.MAX_RACES + 2:
		_press(_named(menu, "AddRace"))
	_check("draft is bounded at thirty races", menu._draft_races.size() == SeasonDefinition.MAX_RACES and menu._status.get_theme_color("font_color") == ERROR_COLOR)
	_valid_draft(menu)
	menu._season_name.text = "Grand Tour"
	_press(_named(menu, "StartCustom"))
	_check("valid draft starts a season with the first race ready", menu.garage_requests == 1 and GameSession.season != null
		and GameSession.season.definition["races"] == _three_races() and GameSession.season.definition["name"] == "Grand Tour"
		and not GameSession.season.builtin and GameSession.race_options() == _three_races()[0])
	await _drop(menu)
	_reset_session()


func _test_menu_import_failures() -> void:
	_reset_session()
	var menu: Variant = await _menu()
	menu._show_page("custom")
	_valid_draft(menu)
	var name_before: String = menu._season_name.text
	var draft_before: Array = menu._draft_races.duplicate(true)
	var good_code := SeasonDefinition.encode_share(_season_data("Other", _three_races()))
	var unknown_track := JSON.stringify(_season_data("Bad", [{"course_id": "mars", "laps": 3, "reverse": false}]))
	var bad_inputs := {
		"garbage text": "hello", "malformed code": "WS1.@@@.zzzz",
		"tampered checksum": good_code.substr(0, good_code.length() - 1) + ("0" if not good_code.ends_with("0") else "1"),
		"truncated code": good_code.substr(0, good_code.length() - 12),
		"unknown track": unknown_track, "empty JSON": "{}", "huge text": "{" + "x".repeat(20000)}
	for label: String in bad_inputs:
		menu._share_text.text = bad_inputs[label]
		_press(_button(menu, "IMPORT CODE"))
		_check("failed import (%s) keeps the draft intact" % label, menu._draft_races == draft_before and menu._season_name.text == name_before
			and menu._race_list.item_count == draft_before.size() and menu._status.get_theme_color("font_color") == ERROR_COLOR)
	var oversized := _scratch.path_join("big.json")
	var file := FileAccess.open(oversized, FileAccess.WRITE)
	file.store_string("x".repeat(SeasonDefinition.MAX_BYTES + 10))
	file.close()
	var binary := _scratch.path_join("binary.json")
	file = FileAccess.open(binary, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0x7b, 0xff, 0xfe, 0x7d]))
	file.close()
	for path: String in [oversized, binary, _scratch.path_join("missing.json")]:
		menu._import_file(path)
		_check("failed file import (%s) keeps the draft intact" % path.get_file(), menu._draft_races == draft_before and menu._season_name.text == name_before
			and menu._status.get_theme_color("font_color") == ERROR_COLOR)
	menu._share_text.text = good_code
	_press(_button(menu, "IMPORT CODE"))
	_check("a later valid import still succeeds", menu._season_name.text == "Other" and menu._draft_races == _three_races())
	await _drop(menu)
	_reset_session()


func _test_menu_settings_and_about() -> void:
	_reset_session()
	var settings_file := _scratch.path_join("settings.cfg")
	if FileAccess.file_exists(settings_file):
		DirAccess.remove_absolute(settings_file)
	var menu: Variant = await _menu()
	_press(_named(menu, "SettingsButton"))
	for unit_id: String in DrivingHud.UNITS:
		var choice := _named(menu, "Unit_" + unit_id) as Button
		_press(choice)
		var config := ConfigFile.new()
		_check("speed unit %s applies and saves to the scratch file" % unit_id, GameSession.speed_unit == unit_id
			and config.load(settings_file) == OK and config.get_value("display", "speed_unit") == unit_id)
	var cpu: OptionButton = menu._cpu_options
	var ids: Array[String] = []
	for i in cpu.item_count:
		ids.append(String(cpu.get_item_metadata(i)))
	_check("CPU options are the known difficulties", ids.size() == CpuDriver.DIFFICULTIES.size() and ids.all(func(id: String) -> bool: return CpuDriver.DIFFICULTIES.has(id)))
	for id: String in ids:
		cpu.select(ids.find(id))
		cpu.item_selected.emit(ids.find(id))
		var config := ConfigFile.new()
		_check("CPU %s applies and saves" % id, GameSession.cpu_difficulty == id and config.load(settings_file) == OK and config.get_value("race", "cpu_difficulty") == id)
	cpu.select(ids.find("hard"))
	cpu.item_selected.emit(ids.find("hard"))
	var last_unit := String(DrivingHud.UNITS.keys()[-1])
	_press(_named(menu, "Unit_" + last_unit))
	GameSession.speed_unit = DrivingHud.DEFAULT_UNIT
	GameSession.set_cpu_difficulty("easy")
	GameSession.load_settings()
	_check("settings reload from the file", GameSession.speed_unit == last_unit and GameSession.cpu_difficulty == "hard")
	menu._show_page("home")
	GameSession.set_cpu_difficulty("medium")
	GameSession.speed_unit = DrivingHud.DEFAULT_UNIT
	menu._show_page("settings")
	_check("settings page reflects the session", (menu._speed_buttons[DrivingHud.DEFAULT_UNIT] as Button).button_pressed
		and cpu.get_item_metadata(cpu.selected) == "medium")
	_check("unknown unit falls back and is saved", GameSession.set_speed_unit("furlongs") == OK and GameSession.speed_unit == DrivingHud.DEFAULT_UNIT)
	_check("about constants are the supplied HTTPS links", MainMenu.HOMEPAGE_URL == "https://appsbydan.com" and MainMenu.SUPPORT_URL == "https://buymeacoffee.com/AppsbyDan")
	menu._show_page("about")
	_check("opening the about page opens nothing", menu.opened_links.is_empty())
	_press(_named(menu, "HomepageLink"))
	_check("homepage button requests only the homepage", menu.opened_links == ["https://appsbydan.com"])
	_press(_named(menu, "SupportLink"))
	_check("support button requests only the support link", menu.opened_links == ["https://appsbydan.com", "https://buymeacoffee.com/AppsbyDan"])
	await _drop(menu)
	_reset_session()


func _begin(id: String, laps: int, reverse: bool) -> void:
	GameSession.season = null
	GameSession.begin_single(id, laps, reverse)
	GameSession.configure("MODE TEST", "blackjack", ["boilerfang", "ramjet"])


func _spawn_race() -> Variant:
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	scene.set_physics_process(false)
	for racer: Vehicle in [scene.car, scene.cpu_cars[0], scene.cpu_cars[1]]:
		racer.freeze = true
	for driver: CpuDriver in scene.cpu_drivers:
		driver.enabled = false
	scene.race.tick(3.0)
	return scene


func _drive_laps(scene: Variant, laps: int, label: String) -> void:
	var tracker: TrackProgress = scene.player_progress
	for i in range(tracker.index, scene.course.points.size()):
		tracker.update(scene.course.points[i]["pos"])
	tracker.update(scene.course.points[0]["pos"])
	_check(label + " grid crossing does not award a lap", tracker.lap == 0)
	for lap in laps:
		for i in range(1, scene.course.points.size()):
			tracker.update(scene.course.points[i]["pos"])
		tracker.update(scene.course.points[0]["pos"])
		scene.race.tick(60.0)
		var last := lap == laps - 1
		_check("%s lap %d counted in order" % [label, lap + 1], tracker.lap == lap + 1
			and (scene.race.state == RaceDirector.State.RESULTS) == last)


func _test_lap_run(id: String, laps: int, reverse: bool) -> void:
	var label := "%s %s %d lap(s)" % [id, "reverse" if reverse else "forward", laps]
	_begin(id, laps, reverse)
	var scene: Variant = await _spawn_race()
	_check(label + " scene receives course, laps and direction", scene.course.course_id == id and scene.course.is_reverse == reverse
		and scene.course.default_laps == laps and scene.race.course == scene.course)
	_check(label + " scenery follows the forward world", scene.has_node("CityScenery") == (id == "block_circuit"))
	await _drive_laps(scene, laps, label)
	_check(label + " finishes with results", scene.race.state == RaceDirector.State.RESULTS and scene.race.player_position() >= 1)
	scene.restart_race()
	_check(label + " retry keeps course, laps and direction", scene.course.course_id == id and scene.course.is_reverse == reverse
		and scene.course.default_laps == laps and scene.race.state == RaceDirector.State.COUNTDOWN and scene.player_progress.lap == 0
		and GameSession.race_laps == laps and GameSession.race_reverse == reverse and GameSession.course_id == id
		and scene.car.position.is_equal_approx(scene._spawn.origin))
	scene.queue_free()
	await get_tree().process_frame


func _press_continue(scene: Variant) -> int:
	_continue_events = 0
	var handler := func() -> void: _continue_events += 1
	scene.hud.continue_requested.disconnect(scene._continue_season)
	scene.hud.continue_requested.connect(handler)
	await get_tree().process_frame
	await get_tree().process_frame
	var button := _named(scene.hud, "ContinueButton") as Button
	var visible: bool = button != null and button.visible
	if visible:
		_press(button)
	scene.hud.continue_requested.disconnect(handler)
	scene.hud.continue_requested.connect(scene._continue_season)
	return _continue_events if visible else -1


func _test_season_flow() -> void:
	var races := [{"course_id": "block_circuit", "laps": 1, "reverse": true}, {"course_id": "split_shift", "laps": 1, "reverse": false}]
	GameSession.season = null
	_check("flow season starts", GameSession.begin_season(_season_data("Flow", races)))
	GameSession.configure("FLOW PILOT", "blackjack", ["boilerfang", "ramjet"])
	var run: SeasonRun = GameSession.season
	var scene: Variant = await _spawn_race()
	_check("round one loads the reverse city", scene.course.course_id == "block_circuit" and scene.course.is_reverse and scene.course.default_laps == 1)
	var entrants: Array[Dictionary] = run.entrants.duplicate(true)
	_check("scene registers a three entrant roster", entrants.size() == 3 and entrants[0]["callsign"] == "FLOW PILOT")
	await _drive_laps(scene, 1, "season round one")
	scene._physics_process(0.0)
	var order: Array[int] = scene.race.standings()
	_check("results hold the finishing order as pending only", run.pending == order and run.points == [0, 0, 0] and run.round_index == 0)
	_check("results carry the Continue caption and provisional table", scene.hud.continue_caption == "NEXT RACE  [N]"
		and scene.hud.season_lines == run.table_lines(true) and scene.hud.season_lines[0].contains("PROVISIONAL"))
	var pressed: int = await _press_continue(scene)
	_check("continue button shows its caption and emits the signal once", pressed == 1
		and (_named(scene.hud, "ContinueButton") as Button).text == "NEXT RACE  [N]")
	scene.restart_race()
	_check("retry clears pending and the season table", run.pending.is_empty() and scene.hud.season_lines.is_empty() and run.points == [0, 0, 0]
		and scene.course.is_reverse and scene.race.state == RaceDirector.State.COUNTDOWN)
	_check("retry keeps the roster", run.entrants == entrants and scene.cpu_callsigns == [entrants[1]["callsign"], entrants[2]["callsign"]]
		and scene.race.entrants[1]["name"] == entrants[1]["callsign"])
	scene.race.tick(3.0)
	await _drive_laps(scene, 1, "season retry")
	scene._physics_process(0.0)
	_check("a repeated result is still not scored", run.points == [0, 0, 0] and run.pending.size() == 3)
	var expected: Array[int] = [0, 0, 0]
	for rank in 3:
		expected[run.pending[rank]] += SeasonRun.POINTS[rank]
	_check("Continue scores the round once", GameSession.advance_season() and run.points == expected and run.round_index == 1
		and not GameSession.advance_season() and run.points == expected)
	_check("session prepared round two", GameSession.course_id == "split_shift" and GameSession.race_laps == 1 and not GameSession.race_reverse)
	scene.queue_free()
	await get_tree().process_frame
	GameSession.configure("SOMEONE ELSE", "ramjet", ["helix", "helix"])
	_check("configure keeps the season pilot", GameSession.callsign == "FLOW PILOT")
	var second: Variant = await _spawn_race()
	_check("round two loads the forward proving ground", second.course.course_id == "split_shift" and not second.course.is_reverse)
	_check("rivals keep their identity into round two", run.entrants == entrants and second.cpu_callsigns == [entrants[1]["callsign"], entrants[2]["callsign"]]
		and second.cpu_cars[0].vehicle_id == entrants[1]["vehicle_id"] and second.cpu_cars[1].vehicle_id == entrants[2]["vehicle_id"])
	await _drive_laps(second, 1, "season round two")
	second._physics_process(0.0)
	var final_pressed: int = await _press_continue(second)
	_check("last round offers final standings", second.hud.continue_caption == "FINAL STANDINGS  [N]" and final_pressed == 1)
	var before: Array[int] = run.points.duplicate()
	var final_order: Array[int] = second.race.standings()
	for rank in 3:
		before[final_order[rank]] += SeasonRun.POINTS[rank]
	_check("final Continue completes the season with summed totals", GameSession.advance_season() and run.is_complete() and run.points == before
		and run.results.size() == 2)
	_check("extra Continue after the final round is ignored", not GameSession.advance_season() and run.points == before and run.results.size() == 2)
	second.queue_free()
	await get_tree().process_frame
	_reset_session()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_pass += int(ok)
	_fail += int(not ok)
	print("  [%s] %s%s" % ["pass" if ok else "FAIL", label, "" if ok or detail.is_empty() else " :: " + detail])
