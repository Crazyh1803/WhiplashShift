## Layout bounds for every main menu page at both target sizes; --capture also renders them to .ai/captures/main-menu.
extends Node

const TEST_MENU := preload("res://tests/race_modes_test_menu.gd")
const SIZES: Array[Vector2i] = [Vector2i(1600, 900), Vector2i(1280, 720)]
const PAGE_STATES: Array[String] = ["home", "home-resume", "season", "single", "custom", "custom-filled", "settings", "about", "standings"]
const SLACK := 0.75

var _pass := 0
var _fail := 0
var _capture := false
var _scratch := ""
var _out := ""
var _saved := {}


func _ready() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_scratch = "user://main_menu_qa_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_scratch)
	_out = ProjectSettings.globalize_path("res://../.ai/captures/main-menu")
	if _capture:
		DirAccess.make_dir_recursive_absolute(_out)
	for key: String in ["course_id", "race_laps", "race_reverse", "race_setup_active", "season", "callsign",
			"selected_vehicle_id", "cpu_vehicle_ids", "cpu_difficulty", "speed_unit", "settings_path"]:
		_saved[key] = GameSession.get(key)
	GameSession.settings_path = _scratch.path_join("settings.cfg")
	for size: Vector2i in SIZES:
		await _menu_pages(size)
		if _capture:
			await _confirm_capture(size)
			await _results_hud_capture(size)
			await _garage_capture(size)
	for key: String in _saved:
		GameSession.set(key, _saved[key])
	_remove_recursive(_scratch)
	print("MAIN_MENU_QA: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for entry in dir.get_files():
		dir.remove(entry)
	for entry in dir.get_directories():
		_remove_recursive(path.path_join(entry))
	DirAccess.remove_absolute(path)


func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	return viewport


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _size_text(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


func _season_data(season_name: String, races: Array) -> Dictionary:
	return {"format": SeasonDefinition.FORMAT, "version": SeasonDefinition.VERSION, "name": season_name, "races": races}


func _long_races(count: int) -> Array:
	var races: Array = []
	for i in count:
		races.append({"course_id": CourseCatalog.IDS[i % 2], "laps": [3, 99, 7, 1][i % 4], "reverse": i % 3 == 1})
	return races


func _menu_pages(size: Vector2i) -> void:
	GameSession.season = null
	GameSession.race_setup_active = false
	var viewport := _viewport(size)
	var menu: Variant = TEST_MENU.new()
	menu.library.directory = _scratch.path_join("library_" + _size_text(size))
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(menu)
	await _settle()
	for state: String in PAGE_STATES:
		var page := state.get_slice("-", 0)
		match state:
			"home-resume":
				GameSession.begin_season(_season_data("Midnight Grand Tour Championship", _long_races(6)))
			"standings":
				var done := SeasonRun.new().configure(_season_data("Done", _long_races(3)))
				var roster: Array[Dictionary] = [{"callsign": "ROADGHOST", "vehicle_id": "blackjack"}, {"callsign": "CINDERBACK", "vehicle_id": "ramjet"},
					{"callsign": "VANTA", "vehicle_id": "helix"}]
				done.set_roster(roster)
				for raw_order: Array in [[0, 1, 2], [1, 0, 2], [1, 2, 0]]:
					var order: Array[int] = []
					order.assign(raw_order)
					done.set_pending(order)
					done.commit()
				GameSession.season = done
			"custom-filled":
				GameSession.season = null
				menu._season_name.text = "Midnight Grand Tour Championship"
				menu._draft_races.clear()
				for race: Dictionary in _long_races(14):
					menu._draft_races.append(race)
				menu._refresh_races(2)
				menu._on_race_selected(2)
				menu._save_current()
				menu._season_name.text = "Quick Sprint"
				menu._save_current()
				menu._season_name.text = "Midnight Grand Tour Championship"
				menu._make_share()
			"settings":
				GameSession.set_speed_unit(String(DrivingHud.UNITS.keys()[0]))
			_:
				GameSession.season = null
		menu._show_page(page)
		await _settle()
		var label := "%s %s" % [_size_text(size), state]
		await _check_page(menu, page, label, size)
		if _capture:
			await _save(viewport, "%s-%s" % [_size_text(size), state])
			if state == "custom-filled" or state == "season":
				var scroll: ScrollContainer = menu._pages[page]
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				await _settle()
				await _save(viewport, "%s-%s-bottom" % [_size_text(size), state])
				scroll.scroll_vertical = 0
	GameSession.season = null
	viewport.queue_free()
	await get_tree().process_frame


func _check_page(menu: Control, page: String, label: String, size: Vector2i) -> void:
	var scroll: ScrollContainer = menu._pages[page]
	var body := scroll.get_child(0) as Control
	var clip := scroll.get_global_rect()
	_check(label + " page fits the viewport", Rect2(Vector2.ZERO, Vector2(size)).grow(SLACK).encloses(clip) and clip.size.x > 400.0 and clip.size.y > 120.0)
	_check(label + " has no horizontal overflow", body.get_combined_minimum_size().x <= scroll.size.x + SLACK and body.size.x <= scroll.size.x + SLACK)
	var bar := scroll.get_v_scroll_bar()
	var reach_ok: bool = bar.max_value - bar.page >= body.size.y - scroll.size.y - 1.0
	_check(label + " vertical scroll reaches the whole page", reach_ok)
	var actionable := 0
	for node in _descendants(scroll):
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			continue
		var control := node as Control
		if not (control is BaseButton or control is LineEdit or control is SpinBox or control is ItemList or control is Label):
			continue
		var rect := control.get_global_rect()
		var name_text := "%s %s" % [label, _describe(control)]
		_check(name_text + " is horizontally inside the page", rect.position.x >= clip.position.x - SLACK and rect.end.x <= clip.end.x + SLACK)
		var content_end := rect.end.y - body.global_position.y
		var inside := rect.position.y >= clip.position.y - SLACK and rect.end.y <= clip.end.y + SLACK
		_check(name_text + " is visible or reachable by scrolling", inside or (content_end <= body.size.y + SLACK and reach_ok))
		var minimum := control.get_combined_minimum_size()
		_check(name_text + " is not cut", control.size.x + SLACK >= minimum.x and control.size.y + SLACK >= minimum.y and _text_fits(control))
		actionable += int(control is BaseButton or control is LineEdit or control is SpinBox or control is ItemList)
	_check(label + " has actionable controls", actionable > 0 or page == "standings" or page == "season")
	if body.size.y > scroll.size.y:
		scroll.scroll_vertical = int(bar.max_value)
		await get_tree().process_frame
		var lowest := 0.0
		for node in _descendants(scroll):
			if node is Control and (node as Control).is_visible_in_tree():
				lowest = maxf(lowest, (node as Control).get_global_rect().end.y)
		_check(label + " scrolled to the end shows the last control", lowest <= clip.end.y + 1.5)
		scroll.scroll_vertical = 0
		await get_tree().process_frame


func _text_fits(control: Control) -> bool:
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	if font == null:
		return true
	if control is Button and not control is OptionButton:
		var button := control as Button
		return font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= button.size.x - 20.0 + SLACK
	if control is Label:
		var label := control as Label
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x + SLACK
		return label.get_line_count() <= maxi(label.get_visible_line_count(), 1)
	if control is LineEdit:
		var edit := control as LineEdit
		var shown := edit.text if not edit.text.is_empty() else edit.placeholder_text
		if edit.text.length() > 60:
			return true
		return font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= edit.size.x - 16.0 + SLACK
	if control is ItemList:
		var list := control as ItemList
		for i in list.item_count:
			if font.get_string_size(list.get_item_text(i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > list.size.x - 28.0:
				return false
	return true


func _describe(control: Control) -> String:
	var text := ""
	if control is Button:
		text = (control as Button).text
	elif control is Label:
		text = (control as Label).text
	return "%s '%s'" % [control.name, text.left(32)]


func _descendants(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		out.append(child)
		_descendants(child, out)
	return out


func _save(viewport: SubViewport, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_check(label + " capture saved", image != null and image.get_width() == viewport.size.x and image.get_height() == viewport.size.y
		and image.save_png(_out.path_join(label + ".png")) == OK)


func _confirm_capture(size: Vector2i) -> void:
	GameSession.begin_season(_season_data("Midnight Grand Tour Championship", _long_races(6)))
	var viewport := _viewport(size)
	var menu: Variant = TEST_MENU.new()
	menu.library.directory = _scratch.path_join("library_confirm")
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(menu)
	await _settle()
	menu._show_page("single")
	menu._request_start(func() -> void: menu._open_garage())
	await _settle()
	var dialog: ConfirmationDialog = menu._confirm
	var rect := Rect2(dialog.position, dialog.size)
	_check(_size_text(size) + " replace-season dialog is visible and inside the viewport", dialog.visible and Rect2(Vector2.ZERO, Vector2(size)).encloses(rect))
	await _save(viewport, "%s-replace-dialog" % _size_text(size))
	GameSession.season = null
	viewport.queue_free()
	await get_tree().process_frame


func _results_hud_capture(size: Vector2i) -> void:
	var run_races := [{"course_id": "split_shift", "laps": 1, "reverse": true}, {"course_id": "split_shift", "laps": 1, "reverse": false},
		{"course_id": "block_circuit", "laps": 3, "reverse": true}]
	GameSession.season = null
	GameSession.begin_season(_season_data("Midnight Grand Tour Championship", run_races))
	var roster: Array[Dictionary] = [{"callsign": "ROADGHOST", "vehicle_id": "blackjack"}, {"callsign": "CINDERBACK", "vehicle_id": "boilerfang"},
		{"callsign": "VANTA", "vehicle_id": "ramjet"}]
	GameSession.season.set_roster(roster)
	GameSession.season.set_pending([1, 0, 2])
	GameSession.advance_season()
	GameSession.configure("ROADGHOST", "blackjack", ["boilerfang", "ramjet"])
	var viewport := _viewport(size)
	var scene: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	viewport.add_child(scene)
	await get_tree().physics_frame
	scene.set_physics_process(false)
	for racer: Vehicle in [scene.car, scene.cpu_cars[0], scene.cpu_cars[1]]:
		racer.freeze = true
	for driver: CpuDriver in scene.cpu_drivers:
		driver.enabled = false
	scene.race.tick(3.0)
	var tracker: TrackProgress = scene.player_progress
	for i in range(tracker.index, scene.course.points.size()):
		tracker.update(scene.course.points[i]["pos"])
	tracker.update(scene.course.points[0]["pos"])
	for i in range(1, scene.course.points.size()):
		tracker.update(scene.course.points[i]["pos"])
	tracker.update(scene.course.points[0]["pos"])
	scene.race.tick(75.0)
	scene._physics_process(0.0)
	await _settle()
	var label := _size_text(size)
	_check(label + " results HUD shows the provisional season table", scene.race.state == RaceDirector.State.RESULTS and scene.hud.season_lines.size() == 4
		and scene.hud.continue_caption == "NEXT RACE  [N]")
	var button := scene.hud.find_child("ContinueButton", true, false) as Button
	_check(label + " continue button is visible inside the viewport", button != null and button.visible
		and Rect2(Vector2.ZERO, Vector2(size)).grow(SLACK).encloses(button.get_global_rect()))
	await _save(viewport, "%s-season-results-hud" % label)
	GameSession.season = null
	GameSession.race_setup_active = false
	viewport.queue_free()
	await get_tree().process_frame


func _garage_capture(size: Vector2i) -> void:
	GameSession.season = null
	GameSession.begin_single("block_circuit", 5, true)
	var viewport := _viewport(size)
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	garage.profile_path = _scratch.path_join("garage_profile.cfg")
	viewport.add_child(garage)
	await _settle()
	await _settle()
	_check(_size_text(size) + " garage keeps the menu's race options", GameSession.course_id == "block_circuit" and GameSession.race_laps == 5 and GameSession.race_reverse)
	await _save(viewport, "%s-garage-single-reverse" % _size_text(size))
	viewport.queue_free()
	GameSession.race_setup_active = false
	await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	_pass += int(ok)
	_fail += int(not ok)
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
