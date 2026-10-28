class_name MainMenu
extends Control

const GARAGE_SCENE := "res://scenes/garage.tscn"
const HOMEPAGE_URL := "https://appsbydan.com"
const SUPPORT_URL := "https://buymeacoffee.com/AppsbyDan"
const INK := Color("f1eee7")
const MUTED := Color("7f929a")
const ACCENT := Color("ff4d2e")
const GOOD := Color("a7ef4e")
const PAGES: Array[String] = ["home", "season", "single", "custom", "settings", "about", "standings"]

var library := SeasonLibrary.new()
var _page_name := "home"
var _pages: Dictionary = {}
var _first_focus: Dictionary = {}
var _status: Label
var _confirm: ConfirmationDialog
var _pending_start := Callable()
var _resume_button: Button
var _standings_label: Label
var _single_course: OptionButton
var _single_laps: SpinBox
var _single_direction: OptionButton
var _season_name: LineEdit
var _race_list: ItemList
var _entry_course: OptionButton
var _entry_laps: SpinBox
var _entry_direction: OptionButton
var _saved_seasons: OptionButton
var _share_text: LineEdit
var _import_dialog: FileDialog
var _export_dialog: FileDialog
var _draft_races: Array[Dictionary] = []
var _speed_buttons: Dictionary = {}
var _cpu_options: OptionButton


func _ready() -> void:
	set_process_unhandled_input(true)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	column.add_child(_label("REDLINE AUTHORITY // MAIN MENU", 13, ACCENT))
	var title := _label("WHIPLASH SHIFT", 56, INK)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color("00000099"))
	column.add_child(title)
	var rule := ColorRect.new()
	rule.color = Color("42535c66")
	rule.custom_minimum_size.y = 1
	column.add_child(rule)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stack)
	for page_name: String in PAGES:
		var scroll := ScrollContainer.new()
		scroll.name = page_name.capitalize() + "Page"
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.visible = false
		stack.add_child(scroll)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 12)
		scroll.add_child(body)
		_pages[page_name] = scroll
	_status = _label("", 14, MUTED)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_build_home()
	_build_season()
	_build_single()
	_build_custom()
	_build_settings()
	_build_about()
	_build_standings()
	_build_dialogs()
	_refresh_saved()
	var run: Variant = _season_run()
	_show_page("standings" if run != null and bool(run.call("is_complete")) else "home")
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("050708"))
	var glow := ACCENT
	glow.a = 0.05
	draw_circle(Vector2(size.x * 0.24, size.y * 0.54), size.x * 0.34, glow)
	for x: int in range(0, ceili(size.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("60768216"), 1.0)
	for y: int in range(0, ceili(size.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("60768216"), 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _page_name != "home":
		get_viewport().set_input_as_handled()
		_show_page("home")


func _show_page(page_name: String) -> void:
	_page_name = page_name
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page_name
	if page_name == "home":
		_refresh_home()
	elif page_name == "standings":
		_refresh_standings()
	elif page_name == "settings":
		_sync_settings()
	_set_status("")
	var target: Control = _first_focus.get(page_name)
	if target != null and target.is_visible_in_tree():
		target.grab_focus.call_deferred()


func _set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color("ff7a5c") if is_error else GOOD)


func _body(page_name: String) -> VBoxContainer:
	return (_pages[page_name] as ScrollContainer).get_child(0)


func _build_home() -> void:
	var body := _body("home")
	_resume_button = _button("RESUME SEASON", 20)
	_resume_button.name = "ResumeButton"
	_resume_button.pressed.connect(_resume_season)
	body.add_child(_resume_button)
	var entries := [["SEASON RACE", "SeasonButton", "season"], ["SINGLE RACE", "SingleButton", "single"],
		["CUSTOM SEASON", "CustomButton", "custom"], ["SETTINGS", "SettingsButton", "settings"], ["ABOUT", "AboutButton", "about"]]
	for entry: Array in entries:
		var button := _button(entry[0], 20)
		button.name = entry[1]
		button.pressed.connect(_show_page.bind(entry[2]))
		body.add_child(button)
		if not _first_focus.has("home"):
			_first_focus["home"] = button


func _refresh_home() -> void:
	var run: Variant = _season_run()
	_resume_button.visible = run != null and not bool(run.call("is_complete"))
	if _resume_button.visible:
		_resume_button.text = "RESUME SEASON  //  %s" % _run_name(run)
		_first_focus["home"] = _resume_button
	else:
		_first_focus["home"] = (_body("home").get_child(1) as Control)


func _build_season() -> void:
	var body := _body("season")
	body.add_child(_label("SEASON 1 // THREE CUPS, NINE RACES", 22, INK))
	var built := SeasonLibrary.season_one()
	var plan: Array = built["plan"]
	var cups := HFlowContainer.new()
	cups.add_theme_constant_override("h_separation", 14)
	cups.add_theme_constant_override("v_separation", 14)
	body.add_child(cups)
	for cup: int in range(1, 4):
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style(Color("0b1115e8"), Color("42535c"), 1))
		panel.custom_minimum_size.x = 340
		cups.add_child(panel)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		panel.add_child(rows)
		rows.add_child(_label("CUP %d" % cup, 15, ACCENT))
		var number := 0
		for item: Dictionary in plan:
			if item["cup"] != cup:
				continue
			number += 1
			var available: bool = item["available"]
			var row := _label("%d.%d  %s  //  %s" % [cup, number, item["title"], "PLAYABLE PREVIEW" if available else "COMING SOON"], 14, INK if available else MUTED)
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rows.add_child(row)
	var note := _label("Only Block Circuit is built so far. The preview runs that one race; the other eight are planned and cannot be played yet.", 14, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	var start := _button("START SEASON 1 PREVIEW  (BLOCK CIRCUIT)", 18)
	start.name = "StartSeasonOne"
	start.pressed.connect(_start_season_one)
	body.add_child(start)
	_first_focus["season"] = start
	body.add_child(_back_button())


func _build_single() -> void:
	var body := _body("single")
	body.add_child(_label("SINGLE RACE", 22, INK))
	_single_course = _course_options()
	_single_course.name = "SingleCourse"
	body.add_child(_row("TRACK", _single_course))
	_single_laps = _laps_spin()
	_single_laps.name = "SingleLaps"
	body.add_child(_row("LAPS", _single_laps))
	_single_direction = _direction_options()
	_single_direction.name = "SingleDirection"
	body.add_child(_row("DIRECTION", _single_direction))
	var choose := _button("CHOOSE VEHICLE", 18)
	choose.name = "ChooseVehicle"
	choose.pressed.connect(_start_single)
	body.add_child(choose)
	body.add_child(_back_button())
	_first_focus["single"] = _single_course


func _build_custom() -> void:
	var body := _body("custom")
	body.add_child(_label("CUSTOM SEASON", 22, INK))
	_season_name = LineEdit.new()
	_season_name.name = "SeasonName"
	_season_name.placeholder_text = "Season name"
	_season_name.max_length = SeasonDefinition.MAX_NAME
	_season_name.custom_minimum_size.x = 320
	body.add_child(_row("NAME", _season_name))
	var split := HFlowContainer.new()
	split.add_theme_constant_override("h_separation", 24)
	split.add_theme_constant_override("v_separation", 12)
	body.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)
	left.add_child(_label("RACES (1-%d, ORDERED)" % SeasonDefinition.MAX_RACES, 13, ACCENT))
	_race_list = ItemList.new()
	_race_list.name = "RaceList"
	_race_list.custom_minimum_size = Vector2(420, 200)
	_race_list.item_selected.connect(_on_race_selected)
	left.add_child(_race_list)
	var order := HFlowContainer.new()
	left.add_child(order)
	for spec: Array in [["MOVE UP", -1], ["MOVE DOWN", 1]]:
		var move := _button(spec[0], 13)
		move.pressed.connect(_move_selected.bind(spec[1]))
		order.add_child(move)
	var remove := _button("REMOVE", 13)
	remove.name = "RemoveRace"
	remove.pressed.connect(_remove_selected)
	order.add_child(remove)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 340
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)
	right.add_child(_label("RACE ENTRY", 13, ACCENT))
	_entry_course = _course_options()
	_entry_course.name = "EntryCourse"
	right.add_child(_row("TRACK", _entry_course))
	_entry_laps = _laps_spin()
	_entry_laps.name = "EntryLaps"
	right.add_child(_row("LAPS", _entry_laps))
	_entry_direction = _direction_options()
	_entry_direction.name = "EntryDirection"
	right.add_child(_row("DIRECTION", _entry_direction))
	var entry_buttons := HFlowContainer.new()
	right.add_child(entry_buttons)
	var add := _button("ADD RACE", 14)
	add.name = "AddRace"
	add.pressed.connect(_add_race)
	entry_buttons.add_child(add)
	var update := _button("UPDATE SELECTED", 14)
	update.name = "UpdateRace"
	update.pressed.connect(_update_race)
	entry_buttons.add_child(update)
	body.add_child(_label("LOCAL LIBRARY", 13, ACCENT))
	var library_row := HFlowContainer.new()
	body.add_child(library_row)
	_saved_seasons = OptionButton.new()
	_saved_seasons.name = "SavedSeasons"
	_saved_seasons.custom_minimum_size.x = 260
	library_row.add_child(_saved_seasons)
	var load_button := _button("LOAD", 14)
	load_button.name = "LoadSeason"
	load_button.pressed.connect(_load_saved)
	library_row.add_child(load_button)
	var save_button := _button("SAVE", 14)
	save_button.name = "SaveSeason"
	save_button.pressed.connect(_save_current)
	library_row.add_child(save_button)
	var import_button := _button("IMPORT FILE", 14)
	import_button.name = "ImportFile"
	import_button.pressed.connect(func() -> void: _import_dialog.popup_centered_ratio(0.7))
	library_row.add_child(import_button)
	var export_button := _button("EXPORT FILE", 14)
	export_button.name = "ExportFile"
	export_button.pressed.connect(_open_export)
	library_row.add_child(export_button)
	body.add_child(_label("SHARE CODE", 13, ACCENT))
	var share_row := HFlowContainer.new()
	body.add_child(share_row)
	_share_text = LineEdit.new()
	_share_text.name = "ShareText"
	_share_text.placeholder_text = "Paste a WS1 share code or season JSON"
	_share_text.max_length = SeasonDefinition.MAX_BYTES * 2
	_share_text.custom_minimum_size.x = 420
	share_row.add_child(_share_text)
	for spec: Array in [["MAKE CODE", _make_share], ["COPY", _copy_share], ["IMPORT CODE", _import_share]]:
		var share_button := _button(spec[0], 14)
		share_button.pressed.connect(spec[1])
		share_row.add_child(share_button)
	var start := _button("START SEASON", 18)
	start.name = "StartCustom"
	start.pressed.connect(_start_custom)
	body.add_child(start)
	body.add_child(_back_button())
	_first_focus["custom"] = _season_name
	_refresh_races()


func _build_settings() -> void:
	var body := _body("settings")
	body.add_child(_label("SETTINGS", 22, INK))
	body.add_child(_label("SPEED UNITS", 13, ACCENT))
	var units := HFlowContainer.new()
	body.add_child(units)
	var group := ButtonGroup.new()
	for unit_id: String in DrivingHud.UNITS:
		var choice := _button(DrivingHud.unit_label(unit_id), 15)
		choice.name = "Unit_" + unit_id
		choice.toggle_mode = true
		choice.button_group = group
		choice.pressed.connect(_select_speed_unit.bind(unit_id))
		units.add_child(choice)
		_speed_buttons[unit_id] = choice
		if not _first_focus.has("settings"):
			_first_focus["settings"] = choice
	body.add_child(_label("CPU DIFFICULTY", 13, ACCENT))
	_cpu_options = OptionButton.new()
	_cpu_options.name = "CpuDifficulty"
	_cpu_options.custom_minimum_size = Vector2(240, 38)
	for id: String in CpuDriver.DIFFICULTIES:
		_cpu_options.add_item(String(CpuDriver.DIFFICULTIES[id]["label"]))
		_cpu_options.set_item_metadata(_cpu_options.item_count - 1, id)
	_cpu_options.item_selected.connect(_select_cpu)
	body.add_child(_cpu_options)
	body.add_child(_back_button())


func _build_about() -> void:
	var body := _body("about")
	body.add_child(_label("ABOUT", 22, INK))
	body.add_child(_label("WHIPLASH SHIFT  //  APPS BY DAN", 16, INK))
	var home := _button("HOMEPAGE  //  appsbydan.com", 16)
	home.name = "HomepageLink"
	home.pressed.connect(_open_url.bind(HOMEPAGE_URL))
	body.add_child(home)
	var support := _button("SUPPORT  //  buymeacoffee.com/AppsbyDan", 16)
	support.name = "SupportLink"
	support.pressed.connect(_open_url.bind(SUPPORT_URL))
	body.add_child(support)
	body.add_child(_back_button())
	_first_focus["about"] = home


func _build_standings() -> void:
	var body := _body("standings")
	body.add_child(_label("SEASON COMPLETE // FINAL STANDINGS", 22, INK))
	_standings_label = _label("", 16, INK)
	body.add_child(_standings_label)
	var home := _button("MAIN MENU", 18)
	home.name = "StandingsHome"
	home.pressed.connect(_show_page.bind("home"))
	body.add_child(home)
	_first_focus["standings"] = home


func _build_dialogs() -> void:
	_confirm = ConfirmationDialog.new()
	_confirm.name = "ReplaceSeasonDialog"
	_confirm.title = "SEASON IN PROGRESS"
	_confirm.dialog_text = "A season is in progress. Starting a new race or season will discard it. Replace it?"
	_confirm.ok_button_text = "REPLACE"
	_confirm.cancel_button_text = "KEEP"
	_confirm.confirmed.connect(_on_replace_confirmed)
	add_child(_confirm)
	_import_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	_import_dialog.file_selected.connect(_import_file)
	_export_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	_export_dialog.file_selected.connect(_export_file)


func _file_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.json ; Whiplash season"])
	add_child(dialog)
	return dialog


func _refresh_standings() -> void:
	var run: Variant = _season_run()
	if run == null:
		_standings_label.text = "No season results."
		return
	_standings_label.text = "\n".join(run.call("table_lines", false))


func _season_run() -> Variant:
	return GameSession.get("season")


func _run_name(run: Variant) -> String:
	var definition: Dictionary = run.get("definition")
	return str(definition.get("name", "")).to_upper()


func _course_options() -> OptionButton:
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(300, 38)
	for id: String in CourseCatalog.IDS:
		options.add_item(String(CourseCatalog.LABELS.get(id, id)))
		options.set_item_metadata(options.item_count - 1, id)
	return options


func _direction_options() -> OptionButton:
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(300, 38)
	options.add_item("FORWARD")
	options.add_item("REVERSE")
	return options


func _laps_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = SeasonDefinition.MAX_LAPS
	spin.step = 1
	spin.value = 3
	spin.rounded = true
	spin.custom_minimum_size = Vector2(300, 38)
	return spin


func _row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _label(caption, 13, MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	row.add_child(control)
	return row


func _back_button() -> Button:
	var back := _button("BACK  (ESC)", 14)
	back.name = "BackButton"
	back.pressed.connect(_show_page.bind("home"))
	return back


func _selected_course(options: OptionButton) -> String:
	return String(options.get_item_metadata(options.selected))


func _entry_from_controls() -> Dictionary:
	return {"course_id": _selected_course(_entry_course), "laps": int(_entry_laps.value), "reverse": _entry_direction.selected == 1}


func _race_text(index: int, race: Dictionary) -> String:
	return "%02d  %s  //  %d %s  //  %s" % [index + 1, CourseCatalog.LABELS.get(race["course_id"], race["course_id"]),
		race["laps"], "lap" if race["laps"] == 1 else "laps", "Reverse" if race["reverse"] else "Forward"]


func _refresh_races(select := -1) -> void:
	_race_list.clear()
	for i: int in _draft_races.size():
		_race_list.add_item(_race_text(i, _draft_races[i]))
	if select >= 0 and select < _draft_races.size():
		_race_list.select(select)


func _selected_index() -> int:
	var picked := _race_list.get_selected_items()
	return picked[0] if not picked.is_empty() else -1


func _on_race_selected(index: int) -> void:
	var race := _draft_races[index]
	_entry_course.select(maxi(CourseCatalog.IDS.find(race["course_id"]), 0))
	_entry_laps.value = race["laps"]
	_entry_direction.select(1 if race["reverse"] else 0)


func _add_race() -> void:
	if _draft_races.size() >= SeasonDefinition.MAX_RACES:
		_set_status("A season can hold at most %d races." % SeasonDefinition.MAX_RACES, true)
		return
	_draft_races.append(_entry_from_controls())
	_refresh_races(_draft_races.size() - 1)
	_set_status("Race added.")


func _update_race() -> void:
	var index := _selected_index()
	if index < 0:
		_set_status("Select a race in the list to update.", true)
		return
	_draft_races[index] = _entry_from_controls()
	_refresh_races(index)
	_set_status("Race updated.")


func _remove_selected() -> void:
	var index := _selected_index()
	if index < 0:
		_set_status("Select a race in the list to remove.", true)
		return
	_draft_races.remove_at(index)
	_refresh_races(mini(index, _draft_races.size() - 1))
	_set_status("Race removed.")


func _move_selected(step: int) -> void:
	var index := _selected_index()
	var target := index + step
	if index < 0 or target < 0 or target >= _draft_races.size():
		return
	var moved := _draft_races[index]
	_draft_races[index] = _draft_races[target]
	_draft_races[target] = moved
	_refresh_races(target)


func _current_season() -> Dictionary:
	return {"format": SeasonDefinition.FORMAT, "version": SeasonDefinition.VERSION,
		"name": _season_name.text, "races": _draft_races.duplicate(true)}


func _apply_season(season: Dictionary) -> void:
	_season_name.text = season["name"]
	_draft_races.clear()
	for race: Dictionary in season["races"]:
		_draft_races.append(race.duplicate())
	_refresh_races()


func _apply_result(result: Dictionary, success_text: String) -> bool:
	if not result["ok"]:
		_set_status(result["error"], true)
		return false
	_apply_season(result["season"])
	_set_status(success_text)
	return true


func _refresh_saved(select_id := "") -> void:
	_saved_seasons.clear()
	for summary: Dictionary in library.list_seasons():
		_saved_seasons.add_item("%s  (%d)" % [summary["name"], summary["race_count"]])
		_saved_seasons.set_item_metadata(_saved_seasons.item_count - 1, summary["id"])
		if summary["id"] == select_id:
			_saved_seasons.select(_saved_seasons.item_count - 1)


func _save_current() -> void:
	var saved := library.save(_current_season())
	if not saved["ok"]:
		_set_status(saved["error"], true)
		return
	_refresh_saved(saved["id"])
	_set_status("Season saved.")


func _load_saved() -> void:
	if _saved_seasons.item_count == 0:
		_set_status("No saved seasons yet.", true)
		return
	_apply_result(library.load_season(String(_saved_seasons.get_item_metadata(_saved_seasons.selected))), "Season loaded.")


func _import_file(path: String) -> void:
	_apply_result(library.import_file(path), "Season imported into the editor. Save it to keep a copy.")


func _open_export() -> void:
	var checked := SeasonDefinition.validate(_current_season())
	if not checked["ok"]:
		_set_status(checked["error"], true)
		return
	_export_dialog.current_file = SeasonLibrary.make_id(checked["season"]["name"]) + ".json"
	_export_dialog.popup_centered_ratio(0.7)


func _export_file(path: String) -> void:
	var result := library.export_file(path, _current_season())
	_set_status("Season exported." if result["ok"] else result["error"], not result["ok"])


func _make_share() -> void:
	var code := SeasonDefinition.encode_share(_current_season())
	if code.is_empty():
		_set_status(SeasonDefinition.validate(_current_season())["error"], true)
		return
	_share_text.text = code
	_set_status("Share code ready. Copy it to send to a friend.")


func _copy_share() -> void:
	if _share_text.text.strip_edges().is_empty():
		_set_status("Nothing to copy. Make a code first.", true)
		return
	DisplayServer.clipboard_set(_share_text.text)
	_set_status("Copied to the clipboard.")


func _import_share() -> void:
	_apply_result(SeasonDefinition.decode_text(_share_text.text), "Share code imported into the editor. Save it to keep a copy.")


func _select_speed_unit(unit_id: String) -> void:
	var saved: Error = GameSession.set_speed_unit(unit_id)
	_set_status("Speed units: %s." % DrivingHud.unit_label(unit_id) if saved == OK else "Could not save settings.", saved != OK)


func _select_cpu(index: int) -> void:
	GameSession.set_cpu_difficulty(String(_cpu_options.get_item_metadata(index)))
	var saved: Error = GameSession.save_settings()
	_set_status("CPU difficulty: %s." % _cpu_options.get_item_text(index) if saved == OK else "Could not save settings.", saved != OK)


func _sync_settings() -> void:
	var unit := DrivingHud.sanitize_unit(GameSession.speed_unit)
	for unit_id: String in _speed_buttons:
		(_speed_buttons[unit_id] as Button).set_pressed_no_signal(unit_id == unit)
	for i: int in _cpu_options.item_count:
		if _cpu_options.get_item_metadata(i) == GameSession.cpu_difficulty:
			_cpu_options.select(i)


func _open_url(url: String) -> void:
	if OS.shell_open(url) != OK:
		_set_status("Could not open the link. Visit %s" % url, true)


func _start_season_one() -> void:
	_request_start(func() -> void: _begin_season(SeasonLibrary.season_one()["season"], true))


func _start_custom() -> void:
	var checked := SeasonDefinition.validate(_current_season())
	if not checked["ok"]:
		_set_status(checked["error"], true)
		return
	_request_start(func() -> void: _begin_season(checked["season"], false))


func _start_single() -> void:
	var course_id := _selected_course(_single_course)
	var laps := int(_single_laps.value)
	var reverse := _single_direction.selected == 1
	_request_start(func() -> void:
		GameSession.call("begin_single", course_id, laps, reverse)
		get_tree().change_scene_to_file(GARAGE_SCENE))


func _begin_season(data: Dictionary, builtin: bool) -> void:
	if not bool(GameSession.call("begin_season", data, builtin)):
		_set_status("Could not start that season.", true)
		return
	get_tree().change_scene_to_file(GARAGE_SCENE)


func _request_start(action: Callable) -> void:
	var run: Variant = _season_run()
	if run != null and not bool(run.call("is_complete")):
		_pending_start = action
		_confirm.popup_centered()
		return
	action.call()


func _on_replace_confirmed() -> void:
	var action := _pending_start
	_pending_start = Callable()
	if action.is_valid():
		action.call()


func _resume_season() -> void:
	get_tree().change_scene_to_file(GARAGE_SCENE)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text_value: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", INK)
	button.custom_minimum_size.y = 40
	button.add_theme_stylebox_override("normal", _panel_style(Color("0a0e10"), Color("52646d"), 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color("172126"), ACCENT, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("2a1a14"), ACCENT, 2))
	button.add_theme_stylebox_override("focus", _panel_style(Color("172126"), ACCENT, 2))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("0a0e10"), Color("2a343a"), 1))
	return button


func _panel_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
