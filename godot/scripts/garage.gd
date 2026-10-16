extends Control

const PROFILE_PATH := "user://profile.cfg"
const RACE_SCENE := "res://scenes/proving_ground.tscn"
const INK := Color("f1eee7")
const MUTED := Color("7f929a")
const PANEL := Color("0b1115e8")

var _index: int = 0
var _launching: bool = false
var _accent: Color = Color("ff4d2e")
var _image: TextureRect
var _model_number: Label
var _name_label: Label
var _class_label: Label
var _description: Label
var _callsign: LineEdit
var _validation: Label
var _start_button: Button
var _prev_button: Button
var _next_button: Button
var _image_panel: PanelContainer
var _dossier_panel: PanelContainer
var _stat_fills: Dictionary = {}
var _stat_values: Dictionary = {}
var _roster_buttons: Array[Button] = []
var _customization_popup: PopupPanel
const PAINT_PICKER := preload("res://scripts/vehicle_paint_picker.gd")
var _primary_picker: PAINT_PICKER
var _secondary_picker: PAINT_PICKER
var _accent_picker: PAINT_PICKER
var _wheel_style: OptionButton
var _part_options: Dictionary = {}
var _customization_loading: bool = false
var _preview_viewport: SubViewport
var _preview_environment: WorldEnvironment
var _standard_preview_environment: Environment
var _preview_vehicle: Vehicle
var _preview_vehicle_id: String = ""
var _preview_container: SubViewportContainer
var _preview_camera: Camera3D
var _preview_yaw: float = 0.0
var _preview_distance: float = 7.2
var _preview_dragging: bool = false


func _ready() -> void:
	set_process_unhandled_key_input(true)
	_build_interface()
	_build_customization_popup()
	_load_profile()
	_select(0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("050708"))
	var glow := _accent
	glow.a = 0.055
	draw_circle(Vector2(size.x * 0.24, size.y * 0.54), size.x * 0.34, glow)
	var grid_color := Color("60768216")
	for x: int in range(0, ceili(size.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)
	for y: int in range(0, ceili(size.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)
	var scan_color := Color("ffffff08")
	for y: int in range(0, ceili(size.y) + 1, 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), scan_color, 1.0)


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)

	var eyebrow := _label("REDLINE AUTHORITY // GRID ACCESS", 13, _accent)
	eyebrow.add_theme_constant_override("outline_size", 4)
	eyebrow.add_theme_color_override("font_outline_color", Color("050708"))
	page.add_child(eyebrow)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 26)
	page.add_child(header)
	var title := _label("WHIPLASH SHIFT", 76, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color("00000099"))
	header.add_child(title)
	var tagline := _label("DRIVE BOTH WAYS.  SURVIVE EITHER ONE.", 14, MUTED)
	tagline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(tagline)

	var rule := ColorRect.new()
	rule.color = Color("42535c66")
	rule.custom_minimum_size.y = 1
	page.add_child(rule)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 30)
	page.add_child(content)
	_build_stage(content)
	_build_dossier(content)


func _build_stage(parent: HBoxContainer) -> void:
	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = 1.7
	stage.add_theme_constant_override("separation", 14)
	parent.add_child(stage)

	_image_panel = PanelContainer.new()
	_image_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_image_panel.custom_minimum_size = Vector2(680, 440)
	stage.add_child(_image_panel)
	var frame_margin := MarginContainer.new()
	frame_margin.add_theme_constant_override("margin_left", 3)
	frame_margin.add_theme_constant_override("margin_right", 3)
	frame_margin.add_theme_constant_override("margin_top", 3)
	frame_margin.add_theme_constant_override("margin_bottom", 3)
	_image_panel.add_child(frame_margin)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	frame_margin.add_child(_image)

	var overlay := VBoxContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("separation", 0)
	_image_panel.add_child(overlay)
	var top_line := HBoxContainer.new()
	top_line.add_theme_constant_override("separation", 8)
	overlay.add_child(top_line)
	var cleared := _label("  CHASSIS // CLEARED", 12, _accent)
	cleared.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_line.add_child(cleared)
	_model_number = _label("01 / 07  ", 13, INK)
	top_line.add_child(_model_number)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(spacer)
	var dossier := _label("  BIDIRECTIONAL VEHICLE PROGRAM // TECHNICAL DOSSIER", 11, Color("8da3aeaa"))
	overlay.add_child(dossier)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 14)
	stage.add_child(nav)
	_prev_button = _button("<", 17)
	_prev_button.tooltip_text = "Previous chassis"
	_prev_button.pressed.connect(func() -> void: _select(_index - 1))
	nav.add_child(_prev_button)
	for i: int in VehicleCatalog.VEHICLES.size():
		var dot := Button.new()
		dot.text = "—"
		dot.flat = true
		dot.focus_mode = Control.FOCUS_ALL
		dot.tooltip_text = String(VehicleCatalog.VEHICLES[i]["name"])
		dot.pressed.connect(_select.bind(i))
		nav.add_child(dot)
		_roster_buttons.append(dot)
	_next_button = _button(">", 17)
	_next_button.tooltip_text = "Next chassis"
	_next_button.pressed.connect(func() -> void: _select(_index + 1))
	nav.add_child(_next_button)


func _build_dossier(parent: HBoxContainer) -> void:
	_dossier_panel = PanelContainer.new()
	_dossier_panel.custom_minimum_size.x = 430
	_dossier_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dossier_panel.size_flags_stretch_ratio = 0.82
	parent.add_child(_dossier_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	_dossier_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	box.add_child(_label("SELECT CHASSIS", 13, _accent))
	_name_label = _label("", 46, INK)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_name_label)
	_class_label = _label("", 12, MUTED)
	box.add_child(_class_label)
	_description = _label("", 17, Color("c6d0d4"))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.y = 54
	box.add_child(_description)

	var divider := ColorRect.new()
	divider.color = _accent
	divider.custom_minimum_size.y = 3
	box.add_child(divider)
	for stat_key: String in ["speed", "accel", "handling", "armor"]:
		_build_stat(box, stat_key)
	var customize := _button("CUSTOMIZE  //  PAINT & PARTS", 14)
	customize.pressed.connect(_open_customization)
	box.add_child(customize)

	var cpu := PanelContainer.new()
	cpu.add_theme_stylebox_override("panel", _panel_style(Color("0a0e10"), Color("41515a66"), 1))
	box.add_child(cpu)
	var cpu_label := _label("  ●  CPU ROSTER          RANDOMIZED ON IGNITION", 11, Color("a7ef4e"))
	cpu_label.custom_minimum_size.y = 38
	cpu_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cpu.add_child(cpu_label)

	var callsign_label := _label("PILOT CALLSIGN", 11, MUTED)
	box.add_child(callsign_label)
	_callsign = LineEdit.new()
	_callsign.max_length = 16
	_callsign.placeholder_text = "ROADGHOST"
	_callsign.add_theme_font_size_override("font_size", 21)
	_callsign.add_theme_color_override("font_color", INK)
	_callsign.add_theme_stylebox_override("normal", _panel_style(Color("050708"), Color("52646d"), 1))
	_callsign.add_theme_stylebox_override("focus", _panel_style(Color("050708"), _accent, 2))
	_callsign.text_changed.connect(func(text: String) -> void:
		var caret := _callsign.caret_column
		_callsign.text = text.to_upper()
		_callsign.caret_column = caret
		_validation.text = "")
	box.add_child(_callsign)
	_validation = _label("", 11, Color("ff755f"))
	_validation.custom_minimum_size.y = 16
	box.add_child(_validation)
	_start_button = _button("IGNITE    //    ENTER GRID    >", 22)
	_start_button.custom_minimum_size.y = 60
	_start_button.pressed.connect(_ignite)
	box.add_child(_start_button)
	var hints := _label("← →  SELECT       ENTER  CONFIRM       BUILD 0.9.7 // NO MERCY", 10, Color("657780"))
	hints.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hints.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	box.add_child(hints)


func _build_stat(parent: VBoxContainer, stat_key: String) -> void:
	var names := {"speed": "TOP SPEED", "accel": "LAUNCH", "handling": "CONTROL", "armor": "CHASSIS"}
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	parent.add_child(column)
	var line := HBoxContainer.new()
	column.add_child(line)
	var stat_label := _label(String(names[stat_key]), 11, MUTED)
	stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(stat_label)
	var value_label := _label("0", 11, INK)
	line.add_child(value_label)
	_stat_values[stat_key] = value_label
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.custom_minimum_size.y = 6
	bar.add_theme_stylebox_override("background", _panel_style(Color("1d282d"), Color.TRANSPARENT, 0))
	bar.add_theme_stylebox_override("fill", _panel_style(_accent, Color.TRANSPARENT, 0))
	column.add_child(bar)
	_stat_fills[stat_key] = bar


func _build_customization_popup() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.85)
	shade.hide()
	add_child(shade)
	_customization_popup = PopupPanel.new()
	_customization_popup.title = "VEHICLE CUSTOMIZATION"
	_customization_popup.add_theme_stylebox_override("panel", _panel_style(Color("0b1115"), Color("42535c"), 2))
	_customization_popup.visibility_changed.connect(func() -> void: shade.visible = _customization_popup.visible)
	add_child(_customization_popup)
	var margin := MarginContainer.new()
	margin.custom_minimum_size = Vector2(880, 800)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_customization_popup.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	box.add_child(_label("CUSTOM BUILD // PAINT & HARDWARE", 20, INK))
	box.add_child(_label("Changes save immediately for each chassis.", 11, MUTED))
	_build_customization_preview(box)

	var paint_row := HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 10)
	box.add_child(paint_row)
	for paint_spec: Array in [
		["PRIMARY", "primary", Color("ff4d2e")],
		["SECONDARY", "secondary", Color("101820")],
		["ACCENT", "accent", Color("ffb238")],
	]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(_label(String(paint_spec[0]), 10, MUTED))
		var picker := PAINT_PICKER.new()
		picker.custom_minimum_size = Vector2(130, 38)
		picker.color = paint_spec[2]
		picker.color_changed.connect(func(_color: Color) -> void: _commit_customization())
		column.add_child(picker)
		paint_row.add_child(column)
		match String(paint_spec[1]):
			"primary": _primary_picker = picker
			"secondary": _secondary_picker = picker
			"accent": _accent_picker = picker

	box.add_child(_label("WHEEL PACKAGE", 10, MUTED))
	_wheel_style = OptionButton.new()
	_wheel_style.add_item("FACTORY // MODULAR")
	_wheel_style.set_item_metadata(0, "stock")
	_wheel_style.add_item("INTERCEPTOR // MODULAR")
	_wheel_style.set_item_metadata(1, "interceptor")
	_wheel_style.item_selected.connect(func(_index: int) -> void: _commit_customization())
	box.add_child(_wheel_style)

	box.add_child(_label("PART SOCKETS", 10, MUTED))
	var part_grid := GridContainer.new()
	part_grid.columns = 2
	part_grid.add_theme_constant_override("h_separation", 12)
	part_grid.add_theme_constant_override("v_separation", 7)
	box.add_child(part_grid)
	for socket_name: String in ["front_a", "front_b", "roof", "left", "right", "hood_engine"]:
		part_grid.add_child(_label(socket_name.replace("_", " ").to_upper(), 11, MUTED))
		var options := OptionButton.new()
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.add_item("STOCK")
		options.set_item_metadata(0, "stock")
		options.add_item("NONE")
		options.set_item_metadata(1, "none")
		options.item_selected.connect(func(_index: int) -> void: _commit_customization())
		part_grid.add_child(options)
		_part_options[socket_name] = options

	var close := _button("SAVE BUILD // CLOSE", 14)
	close.pressed.connect(_customization_popup.hide)
	box.add_child(close)


func _open_customization() -> void:
	_load_customization_controls()
	_customization_popup.popup_centered(Vector2i(920, 850))


func _build_customization_preview(parent: VBoxContainer) -> void:
	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(828, 300)
	_preview_container.stretch = true
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_preview_container.gui_input.connect(_preview_gui_input)
	parent.add_child(_preview_container)
	_preview_viewport = SubViewport.new()
	_preview_viewport.own_world_3d = true
	_preview_viewport.size = Vector2i(1656, 600)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview_viewport.msaa_3d = Viewport.MSAA_2X
	_preview_container.add_child(_preview_viewport)

	_preview_environment = WorldEnvironment.new()
	_standard_preview_environment = Environment.new()
	_standard_preview_environment.background_mode = Environment.BG_COLOR
	_standard_preview_environment.background_color = Color("091117")
	_standard_preview_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_standard_preview_environment.ambient_light_color = Color("b8d1db")
	_standard_preview_environment.ambient_light_energy = 0.72
	_standard_preview_environment.ssao_enabled = true
	_standard_preview_environment.ssao_radius = 0.16
	_standard_preview_environment.ssao_intensity = 1.15
	_preview_environment.environment = _standard_preview_environment
	_preview_viewport.add_child(_preview_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-46.0, -32.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	key_light.shadow_bias = 0.01
	key_light.shadow_normal_bias = 0.005
	_preview_viewport.add_child(key_light)
	_preview_camera = Camera3D.new()
	_preview_camera.fov = 38.0
	_preview_viewport.add_child(_preview_camera)
	_update_preview_camera()

	_preview_vehicle = Vehicle.new()
	_preview_vehicle.name = "CustomizationPreviewVehicle"
	_preview_vehicle.tuning = TuningProfile.new()
	_preview_vehicle.freeze = true
	_preview_vehicle.collision_layer = 0
	_preview_vehicle.collision_mask = 0
	_preview_vehicle.process_mode = Node.PROCESS_MODE_DISABLED
	_preview_viewport.add_child(_preview_vehicle)

	var rotate_row := HBoxContainer.new()
	rotate_row.add_theme_constant_override("separation", 10)
	parent.add_child(rotate_row)
	var rotate_left := _button("↶  ROTATE LEFT", 12)
	rotate_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_left.pressed.connect(func() -> void: _rotate_preview(-PI / 4.0))
	rotate_row.add_child(rotate_left)
	var instruction := _label("DRAG TO ROTATE  •  SCROLL TO ZOOM", 10, MUTED)
	instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rotate_row.add_child(instruction)
	var rotate_right := _button("ROTATE RIGHT  ↷", 12)
	rotate_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_right.pressed.connect(func() -> void: _rotate_preview(PI / 4.0))
	rotate_row.add_child(rotate_right)


func _preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_preview_dragging = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_preview_distance = clampf(_preview_distance - 0.5, 5.0, 10.0)
					_update_preview_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_preview_distance = clampf(_preview_distance + 0.5, 5.0, 10.0)
					_update_preview_camera()
	elif event is InputEventMouseMotion and _preview_dragging:
		var motion := event as InputEventMouseMotion
		_preview_yaw += motion.relative.x * 0.008
		if _preview_vehicle != null:
			_preview_vehicle.rotation.y = _preview_yaw


func _rotate_preview(step: float) -> void:
	_preview_yaw += step
	if _preview_vehicle != null:
		_preview_vehicle.rotation.y = _preview_yaw


func _update_preview_camera() -> void:
	if _preview_camera == null:
		return
	var camera_position := Vector3(
		_preview_distance * 0.62, 2.7, _preview_distance * 0.78
	)
	_preview_camera.look_at_from_position(camera_position, Vector3(0.0, 0.45, 0.0))


func _load_customization_controls() -> void:
	_customization_loading = true
	var vehicle_id := String(VehicleCatalog.VEHICLES[_index]["id"])
	var data := GameSession.customization_for(vehicle_id)
	var visual: Dictionary = VehicleCatalog.get_vehicle(vehicle_id).get("visual", {})
	var wheel_styles: Dictionary = visual.get("wheel_styles", {})
	_wheel_style.clear()
	_wheel_style.add_item("FACTORY // MODULAR")
	_wheel_style.set_item_metadata(0, "stock")
	for style_name: String in wheel_styles:
		if style_name == "stock":
			continue
		_wheel_style.add_item(style_name.replace("_", " ").to_upper())
		_wheel_style.set_item_metadata(_wheel_style.item_count - 1, style_name)
	_primary_picker.color = Color.from_string("#" + String(data["primary_color"]), Color("ff4d2e"))
	_secondary_picker.color = Color.from_string("#" + String(data["secondary_color"]), Color("101820"))
	_accent_picker.color = Color.from_string("#" + String(data["accent_color"]), Color("ffb238"))
	for picker in [_primary_picker,_secondary_picker,_accent_picker]:
		picker.limit_to_palette(vehicle_id=="blackjack")
	_select_option(_wheel_style, String(data["wheel_style"]))
	var parts: Dictionary = data["parts"]
	for socket_name: String in _part_options:
		_select_option(_part_options[socket_name] as OptionButton, String(parts[socket_name]))
	_customization_loading = false
	_refresh_customization_preview(vehicle_id, data)


func _select_option(options: OptionButton, value: String) -> void:
	for item_index: int in options.item_count:
		if String(options.get_item_metadata(item_index)) == value:
			options.select(item_index)
			return
	options.select(0)


func _commit_customization() -> void:
	if _customization_loading:
		return
	var vehicle_id := String(VehicleCatalog.VEHICLES[_index]["id"])
	var parts: Dictionary = {}
	for socket_name: String in _part_options:
		var options := _part_options[socket_name] as OptionButton
		parts[socket_name] = String(options.get_item_metadata(options.selected))
	var data := {
		"primary_color": _primary_picker.color.to_html(false),
		"secondary_color": _secondary_picker.color.to_html(false),
		"accent_color": _accent_picker.color.to_html(false),
		"wheel_style": String(_wheel_style.get_item_metadata(_wheel_style.selected)),
		"parts": parts,
	}
	GameSession.set_vehicle_customization(vehicle_id, data)
	_refresh_customization_preview(vehicle_id, data)


func _refresh_customization_preview(vehicle_id: String, data: Dictionary) -> void:
	if _preview_vehicle == null:
		return
	if _preview_vehicle_id != vehicle_id:
		_preview_environment.environment = preload("res://scripts/blackjack_studio_finish.gd").environment(Color("091117")) if vehicle_id=="blackjack" else _standard_preview_environment
		var spec := VehicleCatalog.get_vehicle(vehicle_id)
		spec["customization"] = data
		_preview_vehicle.free()
		_preview_vehicle=preload("res://scripts/vehicle_factory.gd").create(spec)
		_preview_vehicle.name="CustomizationPreviewVehicle"
		_preview_vehicle.tuning=TuningProfile.new()
		_preview_vehicle.freeze=true
		_preview_vehicle.collision_layer=0
		_preview_vehicle.collision_mask=0
		_preview_vehicle.process_mode=Node.PROCESS_MODE_DISABLED
		_preview_vehicle.rotation.y=_preview_yaw
		if _preview_vehicle.has_method("configure_static_preview"):
			_preview_vehicle.configure_static_preview()
		_preview_viewport.add_child(_preview_vehicle)
		_preview_vehicle_id = vehicle_id
	else:
		_preview_vehicle.apply_customization(data)


func _select(next_index: int) -> void:
	if _launching:
		return
	_index = posmod(next_index, VehicleCatalog.VEHICLES.size())
	var spec: Dictionary = VehicleCatalog.VEHICLES[_index]
	_accent = Color.from_string("#" + String(spec["color"]), Color("ff4d2e"))
	_image.texture = load(String(spec["image"])) as Texture2D
	_model_number.text = "%02d / %02d  " % [_index + 1, VehicleCatalog.VEHICLES.size()]
	_name_label.text = String(spec["name"])
	_class_label.text = "%s // %s" % [spec["class_name"], spec["origin"]]
	_description.text = String(spec["description"])
	for stat_key: String in _stat_fills:
		var value := int(spec["stats"][stat_key])
		(_stat_fills[stat_key] as ProgressBar).value = value
		(_stat_fills[stat_key] as ProgressBar).add_theme_stylebox_override("fill", _panel_style(_accent, Color.TRANSPARENT, 0))
		(_stat_values[stat_key] as Label).text = str(value)
	for i: int in _roster_buttons.size():
		_roster_buttons[i].text = "━━━━" if i == _index else "—"
		_roster_buttons[i].add_theme_color_override("font_color", _accent if i == _index else MUTED)
	_image_panel.add_theme_stylebox_override("panel", _panel_style(Color("08213ae6"), _accent, 2))
	_dossier_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, Color("52646d44"), 1))
	_start_button.add_theme_stylebox_override("normal", _panel_style(_accent, _accent, 0))
	_start_button.add_theme_stylebox_override("hover", _panel_style(_accent.lightened(0.16), _accent, 0))
	_start_button.add_theme_color_override("font_color", Color("080a0b"))
	_start_button.add_theme_color_override("font_hover_color", Color("080a0b"))
	queue_redraw()


func _ignite() -> void:
	if _launching:
		return
	var pilot := _callsign.text.strip_edges().to_upper()
	if pilot.is_empty():
		_validation.text = "CALLSIGN REQUIRED // ACCESS DENIED"
		_callsign.grab_focus()
		return
	_launching = true
	var spec: Dictionary = VehicleCatalog.VEHICLES[_index]
	var vehicle_id := String(spec["id"])
	var cpu_ids := VehicleCatalog.random_cpu_roster(2, vehicle_id)
	GameSession.configure(pilot, vehicle_id, cpu_ids)
	_save_profile(pilot)
	_start_button.text = "IGNITION SEQUENCE // ARMED"
	_start_button.disabled = true
	_prev_button.disabled = true
	_next_button.disabled = true
	for button: Button in _roster_buttons:
		button.disabled = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.55)
	await tween.finished
	get_tree().change_scene_to_file(RACE_SCENE)


func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) == OK:
		_callsign.text = String(config.get_value("profile", "callsign", "ROADGHOST"))
	else:
		_callsign.text = "ROADGHOST"


func _save_profile(pilot: String) -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "callsign", pilot)
	config.save(PROFILE_PATH)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _launching:
		return
	match key.keycode:
		KEY_LEFT:
			_select(_index - 1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_select(_index + 1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_ignite()
			get_viewport().set_input_as_handled()


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
	button.add_theme_stylebox_override("normal", _panel_style(Color("0a0e10"), Color("52646d"), 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color("172126"), _accent, 1))
	button.add_theme_stylebox_override("focus", _panel_style(Color("172126"), _accent, 2))
	return button


func _panel_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
