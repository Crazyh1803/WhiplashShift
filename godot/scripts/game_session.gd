extends Node

const CUSTOMIZATION_PATH := "user://vehicle_customization.cfg"
const CUSTOMIZATION_SCHEMA_VERSION := 1
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SCHEMA_VERSION := 1

var callsign: String = "ROADGHOST"
var selected_vehicle_id: String = "blackjack"
var cpu_vehicle_ids: Array[String] = []
var cpu_difficulty: String = "medium"
var course_id: String = "split_shift"
var vehicle_customizations: Dictionary = {}
var speed_unit: String = DrivingHud.DEFAULT_UNIT
## Separate from the vehicle and profile files; tests point this at a scratch path.
var settings_path: String = SETTINGS_PATH


func _ready() -> void:
	_load_customizations()
	load_settings()


## Applies and saves immediately. Unknown values fall back to the default unit.
func set_speed_unit(value: String) -> Error:
	speed_unit = DrivingHud.sanitize_unit(value)
	return save_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	speed_unit = DrivingHud.sanitize_unit(config.get_value("display", "speed_unit", DrivingHud.DEFAULT_UNIT)) \
		if config.load(settings_path) == OK else DrivingHud.DEFAULT_UNIT


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "schema_version", SETTINGS_SCHEMA_VERSION)
	config.set_value("display", "speed_unit", speed_unit)
	return config.save(settings_path)


func configure(p_callsign: String, p_vehicle_id: String, p_cpu_ids: Array[String]) -> void:
	var clean_callsign := p_callsign.strip_edges().to_upper()
	callsign = clean_callsign if not clean_callsign.is_empty() else "ROADGHOST"
	selected_vehicle_id = p_vehicle_id if not p_vehicle_id.is_empty() else "blackjack"
	cpu_vehicle_ids = p_cpu_ids.duplicate()


func set_course(value: String) -> void:
	course_id = CourseCatalog.sanitize(value)


func set_cpu_difficulty(value: String) -> void:
	cpu_difficulty = value if CpuDriver.DIFFICULTIES.has(value) else "medium"


func selected_vehicle() -> Dictionary:
	var spec := VehicleCatalog.get_vehicle(selected_vehicle_id)
	spec["customization"] = customization_for(selected_vehicle_id)
	return spec


func customization_for(vehicle_id: String) -> Dictionary:
	var defaults := VehicleCatalog.default_customization(vehicle_id)
	var saved: Dictionary = vehicle_customizations.get(vehicle_id, {})
	var merged := defaults.duplicate(true)
	for key: String in ["primary_color", "secondary_color", "accent_color", "wheel_style"]:
		if saved.has(key):
			merged[key] = saved[key]
	var parts: Dictionary = merged["parts"]
	var saved_parts: Dictionary = saved.get("parts", {})
	for socket_name: String in parts:
		if saved_parts.has(socket_name):
			parts[socket_name] = saved_parts[socket_name]
	merged["parts"] = parts
	return _sanitize_customization(vehicle_id, merged)


func set_vehicle_customization(vehicle_id: String, customization: Dictionary) -> void:
	vehicle_customizations[vehicle_id] = _sanitize_customization(vehicle_id, customization)
	_save_customizations()


func _sanitize_customization(vehicle_id: String, customization: Dictionary) -> Dictionary:
	var clean := VehicleCatalog.default_customization(vehicle_id)
	for key: String in ["primary_color", "secondary_color", "accent_color"]:
		var fallback := String(clean[key])
		var raw := String(customization.get(key, fallback)).trim_prefix("#")
		clean[key] = Color.from_string("#" + raw, Color.from_string("#" + fallback, Color.WHITE)).to_html(false)
	var wheel_style := String(customization.get("wheel_style", clean["wheel_style"])).strip_edges()
	var visual: Dictionary = VehicleCatalog.get_vehicle(vehicle_id).get("visual", {})
	var wheel_styles: Dictionary = visual.get("wheel_styles", {})
	clean["wheel_style"] = wheel_style if wheel_styles.has(wheel_style) else clean["wheel_style"]
	var incoming_parts: Dictionary = customization.get("parts", {})
	var parts: Dictionary = clean["parts"]
	var part_scenes: Dictionary = visual.get("part_scenes", {})
	for socket_name: String in parts:
		var selection := String(incoming_parts.get(socket_name, parts[socket_name])).strip_edges()
		var socket_scenes: Dictionary = part_scenes.get(socket_name, {})
		if selection in ["stock", "none"] or socket_scenes.has(selection):
			parts[socket_name] = selection
	clean["parts"] = parts
	return clean


func _load_customizations() -> void:
	vehicle_customizations.clear()
	var config := ConfigFile.new()
	var loaded := config.load(CUSTOMIZATION_PATH) == OK
	for vehicle: Dictionary in VehicleCatalog.VEHICLES:
		var vehicle_id := String(vehicle["id"])
		var data := VehicleCatalog.default_customization(vehicle_id)
		if loaded:
			var section := "vehicle.%s" % vehicle_id
			for key: String in ["primary_color", "secondary_color", "accent_color", "wheel_style"]:
				data[key] = config.get_value(section, key, data[key])
			var parts: Dictionary = data["parts"]
			for socket_name: String in parts:
				parts[socket_name] = config.get_value(section, "part_%s" % socket_name, parts[socket_name])
			data["parts"] = parts
		vehicle_customizations[vehicle_id] = _sanitize_customization(vehicle_id, data)


func _save_customizations() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "schema_version", CUSTOMIZATION_SCHEMA_VERSION)
	for vehicle: Dictionary in VehicleCatalog.VEHICLES:
		var vehicle_id := String(vehicle["id"])
		var data := customization_for(vehicle_id)
		var section := "vehicle.%s" % vehicle_id
		for key: String in ["primary_color", "secondary_color", "accent_color", "wheel_style"]:
			config.set_value(section, key, data[key])
		var parts: Dictionary = data["parts"]
		for socket_name: String in parts:
			config.set_value(section, "part_%s" % socket_name, parts[socket_name])
	config.save(CUSTOMIZATION_PATH)
