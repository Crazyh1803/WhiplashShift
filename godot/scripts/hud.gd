## Minimal readout: everything you need to judge the swap, nothing you don't.
class_name Hud
extends CanvasLayer

signal main_menu_requested
signal retry_requested
signal continue_requested

var continue_caption: String = ""
var season_lines := PackedStringArray()
var _continue_button: Button

@export var target: Vehicle
var cpu_drivers: Array[CpuDriver] = []
var pilot_callsign: String = "ROADGHOST"
var cpu_callsigns: Array[String] = [] ## per-match CPU names, same order as cpu_drivers
var race: RaceDirector
var items: RaceItems:
	set(value):
		if items != null and items.attack_hit.is_connected(_on_attack_hit):
			items.attack_hit.disconnect(_on_attack_hit)
		items = value
		if items != null:
			items.attack_hit.connect(_on_attack_hit)
## Optional override; defaults to the viewport's current camera, which follows swaps.
var camera: Camera3D
var combat: CombatHud
var driving: DrivingHud
var _last_race_state := -1
var _laid_view := Vector2.ZERO
var _fitted: Dictionary = {} ## Label -> text the font size was last fitted for
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
	menu_button.position = Vector2(18.0, 118.0)
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
	driving = DrivingHud.new()
	add_child(driving)
	# Instrument text is created after the band so it draws on top of it.
	_upcoming = _label(18, Vector2.ZERO)
	_upcoming.name = "RouteAdvice"
	_upcoming.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_status = _label(15, Vector2.ZERO)
	_item_status.name = "HeldItem"
	_item_status.add_theme_color_override("font_color", Color("ffc34d"))
	_boost_status = _label(15, Vector2.ZERO)
	_boost_status.name = "BoostStatus"
	for label: Label in [_item_status, _boost_status]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for label: Label in [_upcoming, _item_status, _boost_status]:
		label.clip_text = true
		label.add_theme_constant_override("line_spacing", 0) # compact band: two lines must stay visible
	combat = CombatHud.new()
	add_child(combat)
	_build_results()
	_layout_dash()


## Positions the text instruments inside the dashboard band for the current viewport.
func _layout_dash() -> void:
	_laid_view = get_viewport().get_visible_rect().size
	var l := DashInstruments.layout(_laid_view)
	var s: float = l["scale"]
	var systems := DashInstruments.systems_layout(l["systems"], s)
	_hint.position = Vector2(18.0 * s, float(l["hint_top"]))
	_place(_upcoming, DashInstruments.body(l["route"], s))
	_place(_boost_status, systems["boost"])
	_place(_item_status, systems["status"])


func _place(label: Label, rect: Rect2) -> void:
	label.position = rect.position
	label.size = rect.size
	_fitted.erase(label)


## Sets text, shrinking the font until it fits the label's box (wrapping labels wrap at its width).
func _set_fitted(label: Label, text: String, max_size: int) -> void:
	if label.text == text and _fitted.get(label, "") == text:
		return
	label.text = text
	_fitted[label] = text
	label.add_theme_font_size_override("font_size", DashInstruments.fit_font_size(
		label.get_theme_font("font"), text, label.size, max_size, 9, label.autowrap_mode != TextServer.AUTOWRAP_OFF))


func _on_attack_hit(victim: int, source_pos: Vector3, blocked: bool, _weapon: String) -> void:
	if victim == 0 and combat != null and race != null and race.state == RaceDirector.State.RACING:
		combat.add_hit(source_pos, blocked)


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
	_results_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_results_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	column.add_child(buttons)
	for caption: String in ["RACE AGAIN  [ENTER]", "MAIN MENU"]:
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
	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.custom_minimum_size.y = 48
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	column.add_child(_continue_button)
	_continue_button.hide()
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


func _process(delta: float) -> void:
	if get_viewport().get_visible_rect().size != _laid_view:
		_layout_dash()
	if target == null:
		return
	if race != null and int(race.state) != _last_race_state:
		# Countdown, results and retry all start from a clean combat readout.
		_last_race_state = int(race.state)
		combat.clear()
		driving.clear()
	var unit := DrivingHud.sanitize_unit(GameSession.speed_unit)
	var racers: Array = [target]
	var names: Array[String] = ["YOU"]
	var cpu_lines := PackedStringArray()
	for driver: CpuDriver in cpu_drivers:
		if not is_instance_valid(driver.target):
			continue
		racers.append(driver.target)
		var slot := cpu_drivers.find(driver)
		var callsign := cpu_callsigns[slot] if slot < cpu_callsigns.size() else driver.target.name.replace("_", " ")
		names.append(callsign)
		cpu_lines.append("%s  %3d %s  END %s  LAP %d%s" % [
			callsign,
			DrivingHud.display_speed(driver.target.speed, unit), DrivingHud.unit_label(unit), driver.target.active_end,
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
		"END %s DRIVING   %s   SWAP %s" % [target.active_end, Surfaces.NAMES[target.surface_under], swap_state],
		"A pair on %s   B pair on %s" % [Surfaces.NAMES[a_surf], Surfaces.NAMES[b_surf]],
		"WRONG END" if target.wrong_end and target.speed > 11.0 else "",
	])
	_main.modulate = Color("4fd2ff") if target.active_end == "A" else Color("ffa63d")
	driving.visible = race == null or race.state != RaceDirector.State.RESULTS
	if driving.visible:
		driving.update(unit, target, racers, race.course if race != null else null, names)
	else:
		driving.clear()

	var boost_text := "BOOST UNCHARGED\nWHIPLASH TO CHARGE"
	if target.boost_time > 0.0:
		boost_text = "BOOST FIRING  %.1fs" % target.boost_time
	elif target.boost_cooldown > 0.0:
		boost_text = "BOOST COOLING  %.1fs" % target.boost_cooldown
	elif target.boost_charge > 0:
		boost_text = "BOOST READY\nACCELERATE + [Q]"
	_set_fitted(_boost_status, boost_text, 12)
	_boost_status.modulate = Color("4fd2ff") if target.boost_charge > 0 or target.boost_time > 0 else Color("a7adb7")
	var wl: Dictionary = target.last_whiplash
	if wl.is_empty() or float(wl.get("age", 99.0)) > 2.2:
		_banner.text = ""
	else:
		_banner.text = "%s   %d%% MOMENTUM RETAINED" % [wl["kind"], roundi(float(wl["retained"]) * 100.0)]
	if target.swap_feedback_time > 0.0 and _banner.text.is_empty():
		_banner.text = "END %s ENGAGED" % target.active_end
		_banner.modulate = Color("4fd2ff") if target.active_end == "A" else Color("ffa63d")
	else:
		_banner.modulate = Color.WHITE
	if items != null:
		_item_status.visible = race.state == RaceDirector.State.RACING
		var lamps := PackedStringArray()
		if items.oil_time[0] > 0.0:
			lamps.append("LOW GRIP")
		if items.obscured[0]:
			lamps.append("SMOKE")
		var status := "  ".join(lamps)
		if items.feedback_time > 0.0:
			status += ("\n" if not status.is_empty() else "") + items.feedback
		_set_fitted(_item_status, status, 13)
		combat.visible = race.state == RaceDirector.State.RACING
		var view_camera := camera if camera != null else get_viewport().get_camera_3d()
		combat.update(delta, items, target, view_camera)
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
	_continue_button.visible = not continue_caption.is_empty()
	_continue_button.text = continue_caption
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
	if not season_lines.is_empty():
		lines.append("")
		lines.append_array(season_lines)
	_results_text.text = "\n".join(lines)


func _update_upcoming(tracker: TrackProgress) -> void:
	_set_fitted(_upcoming, _route_text(tracker), 18)


func _route_text(tracker: TrackProgress) -> String:
	if course_cues == null or race.state != RaceDirector.State.RACING or tracker.wrong_way:
		return ""
	var width := float(race.course.points[tracker.index]["w"])
	if tracker.off_line >= width * 0.65:
		return ""
	var lines := PackedStringArray()
	var caution := false
	var corner := course_cues.corner_advice(tracker.distance, target)
	if not corner.is_empty():
		var where := "IN CORNER" if bool(corner["inside"]) else "IN %dm" % ceili(float(corner["metres"]))
		lines.append("%s · %s" % [corner["label"], where])
		var action := "EASE SPEED · " if bool(corner["inside"]) else "BRAKE BEFORE TURN · "
		if bool(corner["low_grip"]):
			lines.append("LOW GRIP — EASE SPEED")
		else:
			lines.append((action if bool(corner["slow"]) else "") + "ADVISORY %d %s" % [
					DrivingHud.advisory_speed(float(corner["speed"]), GameSession.speed_unit),
					DrivingHud.unit_label(GameSession.speed_unit)])
		caution = caution or bool(corner["slow"]) or bool(corner["low_grip"])
	_upcoming.modulate = Color("ffdc80") if caution else Color("e7f1ff")
	return "\n".join(lines)
