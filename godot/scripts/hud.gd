## Minimal readout: everything you need to judge the swap, nothing you don't.
class_name Hud
extends CanvasLayer

signal main_menu_requested
signal retry_requested

@export var target: Vehicle
var cpu_drivers: Array[CpuDriver] = []
var pilot_callsign: String = "ROADGHOST"
var race: RaceDirector
var items: RaceItems
var _item_status: Label
var course_cues: CourseCues
var _upcoming: Label
var _main: Label
var _banner: Label
var _hint: Label
var _cpu: Label
var _race_status: Label
var _boost_status: Label
var _results: Control
var _results_text: Label


func _ready() -> void:
	_main = _label(16, Vector2(18, 14))
	_main.add_theme_font_size_override("font_size", 17)
	_banner = _label(28, Vector2(0, 0))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 90.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 28)
	_hint = _label(12, Vector2(18, 0))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_top = -34.0
	_hint.offset_left = 18.0
	_hint.text = "W/S throttle-brake  A/D steer  SPACE swap  SHIFT handbrake  E item  Q boost  R recover  C camera  F1 debug  F2 CPUs"
	_hint.modulate = Color(1, 1, 1, 0.45)
	_cpu = _label(15, Vector2.ZERO)
	_cpu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cpu.offset_left = -560.0
	_cpu.offset_top = 18.0
	_cpu.offset_right = -18.0
	_cpu.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cpu.clip_text = true
	var menu_button := Button.new()
	menu_button.name = "MainMenuButton"
	menu_button.text = "←  MAIN MENU"
	menu_button.position = Vector2(18.0, 176.0)
	menu_button.custom_minimum_size = Vector2(154.0, 38.0)
	menu_button.add_theme_font_size_override("font_size", 14)
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.pressed.connect(func() -> void: main_menu_requested.emit())
	add_child(menu_button)
	_race_status = _label(22, Vector2.ZERO)
	_race_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_race_status.offset_left = -210.0
	_race_status.offset_right = 210.0
	_race_status.offset_top = 18.0
	_race_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upcoming = _label(20, Vector2.ZERO)
	_upcoming.name = "UpcomingTerrain"
	_upcoming.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_upcoming.offset_left = -430.0
	_upcoming.offset_right = 430.0
	_upcoming.offset_top = -160.0
	_upcoming.offset_bottom = -48.0
	_upcoming.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upcoming.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_status = _label(19, Vector2(18, 228))
	_item_status.name = "HeldItem"
	_item_status.add_theme_color_override("font_color", Color("ffc34d"))
	_boost_status = _label(17, Vector2(18, 286))
	_boost_status.name = "BoostStatus"
	_build_results()


func _build_results() -> void:
	_results = Control.new()
	_results.name = "RaceResults"
	add_child(_results)
	_results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.04, 0.92)
	_results.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_results.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 360)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	_results_text = Label.new()
	_results_text.add_theme_font_size_override("font_size", 23)
	_results_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_results_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	column.add_child(buttons)
	for caption: String in ["RACE AGAIN  [ENTER]", "BACK TO GARAGE"]:
		var button := Button.new()
		button.name = "RetryButton" if buttons.get_child_count() == 0 else "GarageButton"
		button.text = caption
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(280, 48)
		if buttons.get_child_count() == 0:
			button.pressed.connect(func() -> void: retry_requested.emit())
		else:
			button.pressed.connect(func() -> void: main_menu_requested.emit())
		buttons.add_child(button)
	_results.hide()


func _label(size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if target == null:
		return
	var cpu_lines := PackedStringArray()
	for driver: CpuDriver in cpu_drivers:
		if not is_instance_valid(driver.target):
			continue
		cpu_lines.append("%s  %3d KM/H  END %s  LAP %d%s" % [
			driver.target.name.replace("_", " "),
			roundi(driver.target.speed * 3.6), driver.target.active_end,
			mini(driver.progress.lap + 1, race.course.default_laps) if race else driver.progress.lap + 1,
			"  FINISHED" if race and float(race.entrants[cpu_drivers.find(driver) + 1]["finish_time"]) >= 0.0
			else ("  PAUSED" if not driver.enabled else "")])
	_cpu.text = "\n".join(cpu_lines)
	var a_surf: int = target.wheels[0].surface_id
	var b_surf: int = target.wheels[2].surface_id
	var swap_state: String = "READY" if target.can_swap() else "LOCK %.2fs" % target.cooldown
	if target.power_cut > 0.0:
		swap_state = "POWER CUT"
	_main.text = "\n".join([
		"%s  //  %s" % [pilot_callsign, target.vehicle_label],
		"%3d KM/H   %s" % [roundi(target.speed * 3.6), "REVERSE" if target.reversing else ""],
		"END %s DRIVING   %s" % [target.active_end, Surfaces.NAMES[target.surface_under]],
		"  A pair on %-9s  B pair on %s" % [Surfaces.NAMES[a_surf], Surfaces.NAMES[b_surf]],
		"transmission %3d%%   swap %s" % [roundi(target.engage * 100.0), swap_state],
		"WRONG END" if target.wrong_end and target.speed > 11.0 else "",
	])
	_main.modulate = Color("4fd2ff") if target.active_end == "A" else Color("ffa63d")

	var boost_text := "BOOST: EARN WITH A CLEAN WHIPLASH"
	if target.boost_time > 0.0:
		boost_text = "BOOST FIRING  %.1fs" % target.boost_time
	elif target.boost_cooldown > 0.0:
		boost_text = "BOOST COOLING  %.1fs" % target.boost_cooldown
	elif target.boost_charge > 0:
		boost_text = "BOOST READY  [Q]"
	_boost_status.text = boost_text
	_boost_status.modulate = Color("4fd2ff") if target.boost_charge > 0 or target.boost_time > 0 else Color("a7adb7")
	var wl: Dictionary = target.last_whiplash
	if wl.is_empty() or float(wl.get("age", 99.0)) > 2.2:
		_banner.text = ""
	else:
		_banner.text = "%s   %d%% MOMENTUM RETAINED" % [wl["kind"], roundi(float(wl["retained"]) * 100.0)]
	if target.swap_feedback_time > 0.0:
		_banner.text = "END %s ENGAGED" % target.active_end
		_banner.modulate = Color("4fd2ff") if target.active_end == "A" else Color("ffa63d")
	else:
		_banner.modulate = Color.WHITE
	if items != null:
		_item_status.visible = race.state == RaceDirector.State.RACING
		_item_status.text = "ITEM: EMPTY — COLLECT A GOLD BOX"
		if not items.active[0].is_empty():
			_item_status.text = "%s ACTIVE  %.1fs" % [ItemCatalog.label(items.active[0]), items.remaining[0]]
		elif not items.held[0].is_empty():
			var id := items.held[0]
			if ItemCatalog.is_ammo(id):
				_item_status.text = "%s · %d LEFT  [E] %s" % [ItemCatalog.label(id), items.ammo[0], "3-ROUND BURST" if id == "machine_guns" else "FIRE ONE"]
			else:
				_item_status.text = "%s  [E] ACTIVATE" % ItemCatalog.label(id)
		if items.oil_time[0] > 0.0:
			_item_status.text += "  // LOW GRIP"
		if items.obscured[0]:
			_item_status.text += "  // SMOKE"
		if items.feedback_time > 0.0:
			_item_status.text += "\n" + items.feedback
	_update_race()


func _update_race() -> void:
	if race == null:
		return
	var tracker: TrackProgress = race.entrants[0]["progress"]
	_update_upcoming(tracker)
	_race_status.text = "%s\nLAP %d / %d    POS %d / %d\n%s%s" % [
		race.course.display_name.to_upper(), mini(tracker.lap + 1, race.course.default_laps),
		race.course.default_laps, race.player_position(), race.entrants.size(),
		RaceDirector.clock_text(race.elapsed), "   WRONG WAY" if tracker.wrong_way else ""]
	if race.state == RaceDirector.State.COUNTDOWN:
		_banner.text = str(ceili(race.countdown))
	elif race.state == RaceDirector.State.RACING and race.elapsed < 0.8:
		_banner.text = "GO!"
	_results.visible = race.state == RaceDirector.State.RESULTS
	if not _results.visible:
		return
	var lines := PackedStringArray(["RACE COMPLETE  //  POSITION %d / %d" % [race.player_position(), race.entrants.size()], ""])
	var order := race.standings()
	for rank in order.size():
		var entry: Dictionary = race.entrants[order[rank]]
		var time := float(entry["finish_time"])
		lines.append("%d. %s  —  %s" % [rank + 1, entry["name"],
			RaceDirector.clock_text(time) if time >= 0.0 else "UNFINISHED"])
	lines.append("\nRace ends when you finish.")
	_results_text.text = "\n".join(lines)


func _update_upcoming(tracker: TrackProgress) -> void:
	_upcoming.text = ""
	if course_cues == null or race.state != RaceDirector.State.RACING or tracker.wrong_way:
		return
	var width := float(race.course.points[tracker.index]["w"])
	if tracker.off_line >= width * 0.65:
		return
	var cue := course_cues.upcoming(tracker.distance, target.speed)
	var lines := PackedStringArray()
	var caution := false
	if not cue.is_empty():
		var sid := int(cue["surface"])
		lines.append("%s IN %dm" % [Surfaces.NAMES[sid], ceili(float(cue["metres"]))])
		lines.append(CourseCues.advice(sid, target.active_end))
		caution = sid in [Surfaces.Id.ICE, Surfaces.Id.OIL]
	var corner := course_cues.corner_advice(tracker.distance, target)
	if not corner.is_empty():
		var where := "IN CORNER" if bool(corner["inside"]) else "IN %dm" % ceili(float(corner["metres"]))
		lines.append("%s · %s" % [corner["label"], where])
		var action := "EASE SPEED · " if bool(corner["inside"]) else "BRAKE BEFORE TURN · "
		if bool(corner["low_grip"]):
			lines.append("LOW GRIP — EASE SPEED")
		else:
			lines.append((action if bool(corner["slow"]) else "") + "ADVISORY %d KM/H" % (floori(float(corner["speed"]) * 3.6 / 5.0) * 5))
		caution = caution or bool(corner["slow"]) or bool(corner["low_grip"])
	_upcoming.text = "\n".join(lines)
	_upcoming.modulate = Color("ffdc80") if caution else Color("e7f1ff")
