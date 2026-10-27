## The two-ended chassis. This file is the thesis.
##
## Port of web/src/vehicle.js. Axis mapping from the 2D original (see the plan):
##   web body +x (End A / forward) -> body -Z      web body +y (right) -> body +X
##   web v.ang (scalar yaw)        -> basis        web v.av -> angular_velocity.y
##   web w.ox / w.oy               -> -offset.z / offset.x
##   web baseLoad (fixed)          -> suspension spring force  <- the one real addition
##
## Everything else carries over unchanged: the friction circle, tanh lateral
## saturation, the direction-aware drive taper, the trailing-pair handbrake rule
## and reverse gated to near-standstill. Those were the four fixes the web
## prototype cost us and none of them were 2D-specific.
class_name Vehicle
extends RigidBody3D

const VISCERA_RESPONSE_SCRIPT := preload("res://scripts/viscera_response.gd")

const BLACKJACK_LIVERY_SHADER: Shader = preload("res://assets/vehicles/blackjack_livery.gdshader")

signal swapped(record: Dictionary)
signal whiplash(record: Dictionary)
signal boosted(record: Dictionary)
signal damaged(severity: float)

const BOOST_TIME := 0.9
const BOOST_COOLDOWN := 3.0
const BOOST_DRIVE := 0.65
const DAMAGE_DECAY := 0.05

@export var tuning: TuningProfile
@export var active_end: String = "A":
	set(value):
		active_end = value
		var headlights := get_node_or_null("DrivingHeadlights")
		if headlights != null:
			headlights.update_active_end(active_end)

var vehicle_id: String = "blackjack"
var vehicle_label: String = "BLACKJACK X-17"
var vehicle_color: Color = Color("4fd2ff")
var vehicle_secondary_color: Color = Color("101820")
var vehicle_accent_color: Color = Color("ffb238")
var top_speed_multiplier: float = 1.0
var drive_multiplier: float = 1.0
var grip_multiplier: float = 1.0
# Race-owned oil effect; independent of persistent vehicle tuning.
var item_grip_multiplier: float = 1.0
var mass_multiplier: float = 1.0
var brake_multiplier: float = 1.0

# --- control inputs, written from outside each frame ---
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var handbrake: bool = false

# --- readable state ---
var wheels: Array[Wheel] = []
var steer_angle: float = 0.0
var engage: float = 1.0          ## transmission ramp after a swap, 0..1
var cooldown: float = 0.0
var power_cut: float = 0.0
var boost_charge: int = 0
var boost_time: float = 0.0
var boost_cooldown: float = 0.0
var damage: float = 0.0
var swap_feedback_time: float = 0.0
var speed: float = 0.0
var fwd_speed: float = 0.0       ## speed along the ACTIVE end's forward axis
var surface_under: int = Surfaces.Id.OFF
var wrong_end: bool = false
var reversing: bool = false
var last_swap: Dictionary = {}
var last_whiplash: Dictionary = {}

## Per-step force budget, for the debug overlay and for working out why the car
## is doing something surprising. Written every physics step.
var dbg: Dictionary = {}

var _prev_lv: Vector3 = Vector3.ZERO
var _pending: Dictionary = {}
var _inertia: Vector3 = Vector3.ONE
var _static_load: float = 3434.0
var _visual_config: Dictionary = {}
var _customization: Dictionary = {}
var _visual_root: Node3D
var _collision_shapes: Array[CollisionShape3D] = []
var _part_sockets: Dictionary = {}
var _axle_root: Node3D
var _axle_visuals: Dictionary = {}
var _bogie_root: Node3D
var _bodywork: VehicleBodywork


func _ready() -> void:
	if tuning == null:
		tuning = TuningProfile.new()
	_build()


func _build() -> void:
	can_sleep = false
	# REPLACE, not the default COMBINE: otherwise the project-wide default damp of
	# 0.1 is added to ours and quietly eats ~4.6 kN at 120 km/h. Our model owns all
	# the drag it is going to have.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	continuous_cd = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO

	_refresh_mass_properties()

	_rebuild_collision()
	_bodywork = VehicleBodywork.new()
	add_child(_bodywork)
	_bodywork.setup(self)
	_rebuild_visuals()
	_build_wheels()
	_build_axles()
	_build_visual_bogie()
	var response := VISCERA_RESPONSE_SCRIPT.new()
	response.name = "VisceraResponse"
	add_child(response)
	response.setup(self)
	var effects := preload("res://scripts/vehicle_effects.gd").new()
	effects.name = "VehicleEffects"
	add_child(effects)
	effects.setup(self)


func reset_terrain_response() -> void:
	var response := get_node_or_null("VisceraResponse")
	if response != null:
		response.reset_effect()


func try_boost() -> bool:
	if freeze or boost_charge <= 0 or boost_time > 0.0 or boost_cooldown > 0.0:
		return false
	if power_cut > 0.0 or engage < 1.0 or throttle <= 0.05 or fwd_speed < 0.0 or brake > 0.05 or handbrake:
		return false
	var grounded := false
	for wheel: Wheel in wheels:
		if wheel.end == active_end and wheel.contact and wheel.normal_load > 1.0:
			grounded = true
	if not grounded:
		return false
	boost_charge = 0
	boost_time = BOOST_TIME
	boost_cooldown = BOOST_COOLDOWN
	boosted.emit({"end": active_end, "duration": BOOST_TIME})
	return true


func apply_cosmetic_damage(severity: float) -> void:
	if not is_finite(severity) or severity <= 0.0:
		return
	damage = clampf(damage + severity, 0.0, 1.0)
	_sync_bodywork()
	damaged.emit(severity)


func reset_effects_state() -> void:
	boost_charge = 0
	boost_time = 0.0
	boost_cooldown = 0.0
	damage = 0.0
	_sync_bodywork()
	swap_feedback_time = 0.0
	reset_terrain_response()
	var effects := get_node_or_null("VehicleEffects")
	if effects != null:
		effects.reset()


func _sync_bodywork() -> void:
	if _bodywork != null:
		_bodywork.sync()


func _rebind_bodywork() -> void:
	if _bodywork != null:
		_bodywork.rebind(_visual_root)


func _rebuild_visuals() -> void:
	if _visual_root != null:
		if _bodywork != null:
			_bodywork.rebind(null)
		remove_child(_visual_root)
		_visual_root.queue_free()
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	var scene_path := String(_visual_config.get("scene", ""))
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			if model != null:
				model.name = "ProductionModel"
				model.scale = _config_vec3("scale", Vector3.ONE)
				model.position = _config_vec3("offset", Vector3.ZERO)
				model.rotation_degrees = _config_vec3("rotation_degrees", Vector3.ZERO)
				_visual_root.add_child(model)
				_configure_imported_meshes(model)
				_rebind_bodywork()
				_build_part_sockets()
				_rebuild_parts()
				return

	_build_placeholder_visuals(_visual_root)
	_rebind_bodywork()
	_build_part_sockets()
	_rebuild_parts()


func _build_placeholder_visuals(parent: Node3D) -> void:
	var spine := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tuning.body_width * 0.78, 0.5, tuning.body_length * 0.5)
	spine.mesh = bm
	spine.position = Vector3(0.0, 0.25, 0.0)
	spine.material_override = _mat(Color(0.20, 0.22, 0.26))
	parent.add_child(spine)

	# End A: low, slim, sharp. End B: tall, blunt, wide. The asymmetry has to be
	# readable at a glance or none of the comedy lands.
	var a := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(tuning.body_width * 0.72, 0.34, 1.5)
	a.mesh = am
	a.position = Vector3(0.0, 0.12, -tuning.half_base - 0.35)
	a.material_override = _mat(vehicle_color)
	a.name = "EndAVisual"
	parent.add_child(a)

	var b := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(tuning.body_width * 0.95, 0.78, 1.5)
	b.mesh = bmesh
	b.position = Vector3(0.0, 0.42, tuning.half_base + 0.35)
	b.material_override = _mat(vehicle_color.darkened(0.32))
	b.name = "EndBVisual"
	parent.add_child(b)


func _configure_imported_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var lower_name := String(mesh_instance.name).to_lower()
		var is_wheel_geometry := false
		for marker: String in ["wheel", "rim", "tire", "tyre"]:
			is_wheel_geometry = is_wheel_geometry or marker in lower_name
		mesh_instance.visible = not is_wheel_geometry
		if not is_wheel_geometry:
			for surface_index: int in mesh_instance.mesh.get_surface_count():
				if vehicle_id == "blackjack":
					if bool(_visual_config.get("semantic_materials", false)):
						_configure_blackjack_semantic_surface(
							mesh_instance, surface_index, lower_name
						)
						continue
					var current := mesh_instance.get_surface_override_material(surface_index)
					if current is ShaderMaterial and current.shader == BLACKJACK_LIVERY_SHADER:
						current.set_shader_parameter("primary_color", vehicle_color)
						current.set_shader_parameter("secondary_color", vehicle_secondary_color)
						current.set_shader_parameter("accent_color", vehicle_accent_color)
						current.set_shader_parameter("hide_embedded_wheels", not _wheel_style_embedded())
						continue
					var source := mesh_instance.mesh.surface_get_material(surface_index) as StandardMaterial3D
					if source != null:
						mesh_instance.set_surface_override_material(
							surface_index, _blackjack_production_material(source)
						)
				else:
					mesh_instance.set_surface_override_material(surface_index, _mat(vehicle_color))
	for child: Node in node.get_children():
		_configure_imported_meshes(child)


func _configure_blackjack_semantic_surface(
	mesh_instance: MeshInstance3D, surface_index: int, _lower_name: String
) -> void:
	# The v2 production GLB carries explicit semantic materials. Mesh names are
	# deliberately ignored here so protected shell, glass and hardware cannot be
	# recolored merely because they are part of a body assembly.
	var source := mesh_instance.mesh.surface_get_material(surface_index) as StandardMaterial3D
	if source == null:
		return
	var semantic_name := source.resource_name.to_lower()
	if not semantic_name.begins_with("paint_"):
		return
	var paint_color := vehicle_color
	if semantic_name == "paint_secondary":
		paint_color = vehicle_secondary_color
	elif semantic_name == "paint_accent":
		paint_color = vehicle_accent_color
	var paint := source.duplicate() as StandardMaterial3D
	paint.albedo_color = paint_color
	paint.metallic = maxf(paint.metallic, 0.42)
	paint.roughness = 0.32
	mesh_instance.set_surface_override_material(surface_index, paint)


func _blackjack_production_material(source: StandardMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BLACKJACK_LIVERY_SHADER
	material.set_shader_parameter("source_albedo", source.albedo_texture)
	material.set_shader_parameter("source_normal", source.normal_texture)
	var orm_texture: Texture2D = source.ao_texture
	if orm_texture == null:
		orm_texture = source.metallic_texture
	material.set_shader_parameter("source_orm", orm_texture)
	material.set_shader_parameter("primary_color", vehicle_color)
	material.set_shader_parameter("secondary_color", vehicle_secondary_color)
	material.set_shader_parameter("accent_color", vehicle_accent_color)
	material.set_shader_parameter("hide_embedded_wheels", not _wheel_style_embedded())
	return material


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.65
	return m


func set_paint_color(color: Color) -> void:
	vehicle_color = color
	_customization["primary_color"] = color.to_html(false)
	if _visual_root != null:
		_configure_imported_meshes(_visual_root)
		_rebind_bodywork()


func apply_customization(customization: Dictionary) -> void:
	_customization = customization.duplicate(true)
	vehicle_color = Color.from_string("#" + String(_customization.get("primary_color", vehicle_color.to_html(false))), vehicle_color)
	vehicle_secondary_color = Color.from_string("#" + String(_customization.get("secondary_color", "101820")), Color("101820"))
	vehicle_accent_color = Color.from_string("#" + String(_customization.get("accent_color", "ffb238")), Color("ffb238"))
	if is_inside_tree():
		_rebuild_visuals()
		_refresh_wheel_visuals_and_mounts()


func apply_vehicle_spec(spec: Dictionary) -> void:
	vehicle_id = String(spec.get("id", "blackjack"))
	vehicle_label = String(spec.get("name", "BLACKJACK X-17"))
	vehicle_color = Color.from_string("#" + String(spec.get("color", "4fd2ff")), Color("4fd2ff"))
	_customization = spec.get("customization", VehicleCatalog.default_customization(vehicle_id)).duplicate(true)
	vehicle_color = Color.from_string("#" + String(_customization.get("primary_color", vehicle_color.to_html(false))), vehicle_color)
	vehicle_secondary_color = Color.from_string("#" + String(_customization.get("secondary_color", "101820")), Color("101820"))
	vehicle_accent_color = Color.from_string("#" + String(_customization.get("accent_color", "ffb238")), Color("ffb238"))
	var physics: Dictionary = spec.get("physics", {})
	top_speed_multiplier = float(physics.get("top_speed", 1.0))
	drive_multiplier = float(physics.get("drive", 1.0))
	grip_multiplier = float(physics.get("grip", 1.0))
	mass_multiplier = float(physics.get("mass", 1.0))
	brake_multiplier = float(physics.get("brake", 1.0))
	_visual_config = spec.get("visual", {}).duplicate(true)
	if tuning != null and is_inside_tree():
		_refresh_mass_properties()
		_rebuild_collision()
		_rebuild_visuals()
		_refresh_wheel_visuals_and_mounts()


func _refresh_mass_properties() -> void:
	mass = tuning.mass * mass_multiplier
	var w: float = tuning.body_width
	var h: float = tuning.body_height
	var l: float = tuning.body_length
	# Explicit inertia keeps the chassis response deterministic across visual specs.
	_inertia = Vector3(
		mass * (h * h + l * l) / 12.0,
		mass * (w * w + l * l) / 12.0,
		mass * (w * w + h * h) / 12.0,
	)
	inertia = _inertia
	_static_load = mass * 9.81 / 4.0


func _rebuild_collision() -> void:
	for old_shape: CollisionShape3D in _collision_shapes:
		remove_child(old_shape)
		old_shape.queue_free()
	_collision_shapes.clear()

	var boxes: Array = []
	var scene_path := String(_visual_config.get("scene", ""))
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		boxes = _visual_config.get("collision_boxes", [])
	if boxes.is_empty():
		boxes = [{
			"size": Vector3(tuning.body_width, tuning.body_height * 0.75, tuning.body_length),
			"position": Vector3(0.0, 0.25, 0.0),
		}]
	for box_spec: Dictionary in boxes:
		var collision := CollisionShape3D.new()
		collision.name = "ChassisCollision_%d" % _collision_shapes.size()
		var box := BoxShape3D.new()
		box.size = _value_vec3(box_spec.get("size"), Vector3.ONE)
		collision.shape = box
		collision.position = _value_vec3(box_spec.get("position"), Vector3.ZERO)
		collision.rotation_degrees = _value_vec3(box_spec.get("rotation_degrees"), Vector3.ZERO)
		add_child(collision)
		_collision_shapes.append(collision)


func _build_wheels() -> void:
	wheels.clear()
	# order matters: 0,1 are the End A pair and 2,3 the End B pair, so the
	# anti-roll bar can pair them by index.
	var spec := [
		["A", -1], ["A", 1], ["B", -1], ["B", 1],
	]
	for s: Array in spec:
		var end: String = s[0]
		var side: int = s[1]
		var wheel := Wheel.new()
		wheel.name = "Wheel_%s_%s" % [end, "L" if side < 0 else "R"]
		wheel.position = _wheel_mount(end, side)
		add_child(wheel)
		wheel.setup(
			end, side, tuning.wheel_radius(end),
			_wheel_scene_path(end), _wheel_visual_config(end, side),
		)
		wheel.visible = not _wheel_style_embedded()
		wheels.append(wheel)


func _refresh_wheel_visuals_and_mounts() -> void:
	for wheel: Wheel in wheels:
		wheel.position = _wheel_mount(wheel.end, wheel.side)
		wheel.set_visual_scene(
			_wheel_scene_path(wheel.end), _wheel_visual_config(wheel.end, wheel.side)
		)
		wheel.visible = not _wheel_style_embedded()
	_build_axles()
	_build_visual_bogie()


func _build_visual_bogie() -> void:
	if _bogie_root != null:
		remove_child(_bogie_root)
		_bogie_root.free()
	_bogie_root = Node3D.new()
	_bogie_root.name = "VisualMiddleBogie"
	_bogie_root.visible = bool(_visual_config.get("visual_middle_bogie", false)) \
		and not _wheel_style_embedded()
	add_child(_bogie_root)
	if not _bogie_root.visible:
		return
	var bogie_z := float(_visual_config.get("middle_bogie_z", 0.66))
	for side: int in [-1, 1]:
		var visual_wheel := Wheel.new()
		visual_wheel.name = "Bogie_%s" % ("L" if side < 0 else "R")
		visual_wheel.position = Vector3(
			side * tuning.half_track, 0.0, bogie_z
		)
		_bogie_root.add_child(visual_wheel)
		visual_wheel.setup(
			"B", side, tuning.wheel_radius("B"),
			_wheel_scene_path("B"), _wheel_visual_config("B", side),
		)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("161c20")
	metal.metallic = 0.86
	metal.roughness = 0.34
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.082
	shaft_mesh.bottom_radius = 0.082
	shaft_mesh.height = tuning.half_track * 2.0 - 0.24
	shaft_mesh.radial_segments = 14
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	shaft.position.z = bogie_z
	shaft.material_override = metal
	_bogie_root.add_child(shaft)
	_update_visual_bogie()


func _update_visual_bogie() -> void:
	if _bogie_root == null or not _bogie_root.visible:
		return
	var pair := _wheel_pair("B")
	if pair.size() != 2:
		return
	var ride_y := 0.0
	for wheel: Wheel in pair:
		var assembly := wheel.get_node_or_null("ModularWheelVisual") as Node3D
		if assembly != null:
			ride_y += assembly.position.y * 0.5
	_bogie_root.position.y = ride_y


func _build_axles() -> void:
	if _axle_root != null:
		remove_child(_axle_root)
		_axle_root.free()
	_axle_visuals.clear()
	_axle_root = Node3D.new()
	_axle_root.name = "AxleVisuals"
	_axle_root.visible = not _wheel_style_embedded()
	add_child(_axle_root)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("161c20")
	metal.metallic = 0.86
	metal.roughness = 0.34
	for end: String in ["A", "B"]:
		var pair := _wheel_pair(end)
		if pair.size() != 2:
			continue
		var left := pair[0] as Wheel
		var right := pair[1] as Wheel
		var assembly := Node3D.new()
		assembly.name = "Axle_%s" % end
		_axle_root.add_child(assembly)
		var shaft := MeshInstance3D.new()
		shaft.name = "Shaft"
		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.065 if end == "A" else 0.082
		shaft_mesh.bottom_radius = shaft_mesh.top_radius
		shaft_mesh.height = maxf(0.35, absf(right.position.x - left.position.x) - 0.24)
		shaft_mesh.radial_segments = 14
		shaft.mesh = shaft_mesh
		shaft.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		shaft.material_override = metal
		assembly.add_child(shaft)
		var differential := MeshInstance3D.new()
		differential.name = "Differential"
		var differential_mesh := SphereMesh.new()
		differential_mesh.radius = 0.13 if end == "A" else 0.17
		differential_mesh.height = differential_mesh.radius * 1.55
		differential_mesh.radial_segments = 16
		differential_mesh.rings = 8
		differential.mesh = differential_mesh
		differential.scale = Vector3(1.35, 0.78, 0.92)
		differential.material_override = metal
		assembly.add_child(differential)
		_axle_visuals[end] = assembly
	_update_axle_visuals()


func _wheel_pair(end: String) -> Array[Wheel]:
	var pair: Array[Wheel] = []
	for wheel: Wheel in wheels:
		if wheel.end == end:
			pair.append(wheel)
	pair.sort_custom(func(a: Wheel, b: Wheel) -> bool: return a.side < b.side)
	return pair


func _update_axle_visuals() -> void:
	if _axle_root == null:
		return
	_axle_root.visible = not _wheel_style_embedded()
	for end: String in _axle_visuals:
		var pair := _wheel_pair(end)
		if pair.size() != 2:
			continue
		var left := pair[0] as Wheel
		var right := pair[1] as Wheel
		var left_y := left.position.y - (left.ride_distance - left.radius)
		var right_y := right.position.y - (right.ride_distance - right.radius)
		var assembly := _axle_visuals[end] as Node3D
		assembly.position = Vector3(
			(left.position.x + right.position.x) * 0.5,
			(left_y + right_y) * 0.5,
			(left.position.z + right.position.z) * 0.5,
		)
	_update_visual_bogie()


func _build_part_sockets() -> void:
	_part_sockets.clear()
	var socket_specs: Dictionary = _visual_config.get("part_sockets", {})
	for socket_name: String in socket_specs:
		var socket := Node3D.new()
		socket.name = "Socket_%s" % socket_name.to_pascal_case()
		var transform_spec: Dictionary = socket_specs[socket_name]
		socket.position = _value_vec3(transform_spec.get("position"), Vector3.ZERO)
		socket.rotation_degrees = _value_vec3(transform_spec.get("rotation_degrees"), Vector3.ZERO)
		socket.scale = _value_vec3(transform_spec.get("scale"), Vector3.ONE)
		_visual_root.add_child(socket)
		_part_sockets[socket_name] = socket


func _rebuild_parts() -> void:
	var selections: Dictionary = _customization.get("parts", {})
	var scene_map: Dictionary = _visual_config.get("part_scenes", {})
	for socket_name: String in _part_sockets:
		var socket := _part_sockets[socket_name] as Node3D
		for child: Node in socket.get_children():
			child.queue_free()
		var selection := String(selections.get(socket_name, "stock"))
		if selection in ["", "none", "stock"]:
			continue
		var socket_scenes: Dictionary = scene_map.get(socket_name, {})
		var scene_path := String(socket_scenes.get(selection, ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var packed := load(scene_path) as PackedScene
		if packed != null:
			var part_instance := packed.instantiate() as Node3D
			if part_instance == null:
				continue
			if socket_name == "hood_engine":
				var engine_material := StandardMaterial3D.new()
				engine_material.albedo_color = Color("343a3d")
				engine_material.metallic = 0.82
				engine_material.roughness = 0.28
				if part_instance is MeshInstance3D:
					(part_instance as MeshInstance3D).material_override = engine_material
				for mesh_node: Node in part_instance.find_children(
					"*", "MeshInstance3D", true, false
				):
					(mesh_node as MeshInstance3D).material_override = engine_material
			socket.add_child(part_instance)


func get_part_socket(socket_name: String) -> Node3D:
	return _part_sockets.get(socket_name) as Node3D


func _wheel_mount(end: String, side: int) -> Vector3:
	var fallback := Vector3(
		side * tuning.half_track,
		0.0,
		-tuning.half_base if end == "A" else tuning.half_base,
	)
	var mounts: Dictionary = _visual_config.get("wheel_mounts", {})
	var key := "%s_%s" % [end, "L" if side < 0 else "R"]
	return _value_vec3(mounts.get(key), fallback)


func _wheel_scene_path(end: String) -> String:
	var style := _selected_wheel_style()
	var key := "wheel_scene_a" if end == "A" else "wheel_scene_b"
	return String(style.get(key, _visual_config.get(key, "")))


func _selected_wheel_style() -> Dictionary:
	var style_name := String(_customization.get("wheel_style", "stock"))
	var wheel_styles: Dictionary = _visual_config.get("wheel_styles", {})
	return wheel_styles.get(style_name, {}) as Dictionary


func _wheel_style_embedded() -> bool:
	return bool(_selected_wheel_style().get(
		"embedded", _visual_config.get("embedded_wheels", false)
	))


func _wheel_visual_config(end: String, side: int) -> Dictionary:
	var style := _selected_wheel_style().duplicate(true)
	var suffix := "a" if end == "A" else "b"
	for key: String in [
		"rim_scale", "rim_offset", "rim_rotation_degrees", "assembly_offset", "tread_scale"
	]:
		var end_key := "%s_%s" % [key, suffix]
		if style.has(end_key):
			style[key] = style[end_key]
	# Move the rim face toward the exterior side of the tire.
	var offset := _value_vec3(style.get("rim_offset"), Vector3.ZERO)
	offset.x *= side
	style["rim_offset"] = offset
	return style


func _config_vec3(key: String, fallback: Vector3) -> Vector3:
	return _value_vec3(_visual_config.get(key), fallback)


static func _value_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


# ---------------------------------------------------------------- the swap
func forward_sign() -> float:
	return 1.0 if active_end == "A" else -1.0


func forward_vector() -> Vector3:
	return global_transform.basis * Vector3(0.0, 0.0, -1.0) * forward_sign()


## Hand the drive to the other end. The whole prototype exists to test the one
## thing this function does NOT do: touch the body's momentum.
func swap_ends(reason: String = "manual") -> Dictionary:
	var pre_lin: Vector3 = linear_velocity
	var pre_ang: Vector3 = angular_velocity
	var pre_basis: Basis = global_transform.basis

	# ---- the thesis ----
	active_end = "B" if active_end == "A" else "A"
	# linear_velocity, angular_velocity and basis are deliberately left alone.
	# Inertia carries through; the driver deals with it.
	# --------------------

	engage = 0.0
	boost_time = 0.0
	swap_feedback_time = 0.75
	cooldown = tuning.swap_cooldown
	steer_angle *= 0.35

	last_swap = {
		"reason": reason,
		"pre_speed": pre_lin.length(), "post_speed": linear_velocity.length(),
		"pre_lin": pre_lin, "post_lin": linear_velocity,
		"pre_ang": pre_ang, "post_ang": angular_velocity,
		"basis_unchanged": pre_basis.is_equal_approx(global_transform.basis),
		"end": active_end,
	}

	if pre_lin.length() >= tuning.whiplash_min_speed:
		_pending = {"t": 0.0, "entry_speed": pre_lin.length(), "entry_basis": pre_basis}
	else:
		_pending = {}

	swapped.emit(last_swap)
	return last_swap


func can_swap() -> bool:
	return cooldown <= 0.0


# ---------------------------------------------------------------- the force loop
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	if dt <= 0.0:
		return
	var xform: Transform3D = state.transform
	var basis: Basis = xform.basis
	var inv: Basis = basis.inverse()
	var lv: Vector3 = state.linear_velocity
	var av: Vector3 = state.angular_velocity

	# actual acceleration last step, to check against the force budget
	dbg["actual_a"] = (lv - _prev_lv) / dt
	_prev_lv = lv

	var fs: float = forward_sign()
	speed = lv.length()
	var lvel: Vector3 = inv * lv          # velocity in body space
	fwd_speed = -lvel.z * fs

	_tick_timers(dt)
	_tick_steering(dt)

	# ---- pass 1: where is the ground, and what is it made of ----
	var space := state.get_space_state()
	var exclude: Array[RID] = [get_rid()]
	var hardpoints: Array[Vector3] = []
	var r_worlds: Array[Vector3] = []
	for wheel: Wheel in wheels:
		var r_world: Vector3 = basis * wheel.position
		var hp: Vector3 = xform.origin + r_world
		wheel.cast(space, exclude, hp, basis.y, tuning.susp_rest(wheel.end))
		hardpoints.append(hp)
		r_worlds.append(r_world)
	_update_axle_visuals()

	# ---- drive command, from what the ACTIVE pair is standing on ----
	reversing = brake > 0.05 and throttle < 0.05 and fwd_speed < 0.6 and speed < 2.5
	var thr: float = throttle
	var brk: float = brake
	if reversing:
		thr = -brake * 0.62
		brk = 0.0

	var accel_mod: float = 0.0
	var top_mod: float = 0.0
	var n: int = 0
	surface_under = Surfaces.Id.OFF
	for wheel: Wheel in wheels:
		if wheel.end != active_end:
			continue
		accel_mod += Surfaces.mod_accel(wheel.end, wheel.surface_id)
		top_mod += Surfaces.mod_top(wheel.end, wheel.surface_id)
		surface_under = wheel.surface_id
		n += 1
	if n > 0:
		accel_mod /= float(n)
		top_mod /= float(n)
	else:
		accel_mod = 1.0
		top_mod = 1.0

	var top: float = tuning.top_speed(active_end) * top_speed_multiplier * top_mod
	# Taper against speed IN THE DIRECTION WE ARE DRIVING, not raw speed. This is
	# what lets End B pull full torque against the momentum it inherited.
	var drive_dir: float = 1.0 if thr >= 0.0 else -1.0
	var dir_top: float = maxf(4.0, top * (1.0 if drive_dir > 0.0 else 0.45))
	var taper: float = clampf(1.0 - (fwd_speed * drive_dir) / dir_top, 0.0, 1.0)
	var gate_open: float = 0.0 if power_cut > 0.0 else engage
	var drive_per_wheel: float = thr * tuning.drive(active_end) * drive_multiplier * accel_mod * taper * gate_open / 2.0
	if boost_time > 0.0 and thr > 0.0 and not handbrake and brk <= 0.05:
		drive_per_wheel *= 1.0 + BOOST_DRIVE
	dbg["taper"] = taper
	dbg["top"] = top
	dbg["accel_mod"] = accel_mod
	dbg["drive_per_wheel"] = drive_per_wheel

	# The handbrake locks the pair TRAILING the velocity vector, not the inactive
	# pair. Normally identical. Straight after a high-speed swap they are not: the
	# newly active end is the one at the back, and locking it snaps the chassis
	# round. That is the Vector Slide.
	var hb_end: String = "B" if -lvel.z >= 0.0 else "A"

	# ---- anti-roll bar: extra roll stiffness across each pair ----
	# The MORE compressed wheel gets the extra upward force. Signing this the
	# other way subtracts roll stiffness instead of adding it, which drove End B's
	# effective roll rate negative and rolled the car over on a straight road.
	var arb: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for pair: int in [0, 2]:
		var d: float = wheels[pair].compression - wheels[pair + 1].compression
		arb[pair] = d * tuning.anti_roll
		arb[pair + 1] = -d * tuning.anti_roll

	# ---- pass 2: suspension + tyre forces ----
	var max_slip: float = 0.0
	var f_tyre_total := Vector3.ZERO
	var f_susp_total := Vector3.ZERO
	for i: int in wheels.size():
		var wheel: Wheel = wheels[i]
		if not wheel.contact:
			continue

		var spring: float = wheel.compression * tuning.susp_stiffness(wheel.end)
		var damper: float = wheel.compression_velocity(dt) * tuning.susp_damp(wheel.end)
		var load: float = clampf(spring + damper + arb[i], 0.0, _static_load * 8.0)
		wheel.normal_load = load

		var steered: bool = wheel.end == active_end
		wheel.steered = steered
		var delta_w: float = steer_angle if steered else 0.0
		wheel.steer_angle = delta_w
		var wb := Basis(Vector3.UP, delta_w)
		var w_dir: Vector3 = wb * Vector3(0.0, 0.0, -1.0)   # rolling axis, body space
		var w_lat: Vector3 = wb * Vector3(1.0, 0.0, 0.0)    # lateral axis, body space

		var v_point: Vector3 = lv + av.cross(r_worlds[i])
		var v_local: Vector3 = inv * v_point
		var lon: float = v_local.dot(w_dir)
		var lat: float = v_local.dot(w_lat)

		var sid: int = wheel.surface_id
		var hb: bool = handbrake and wheel.end == hb_end
		var mu: float = tuning.tire_grip(wheel.end) * grip_multiplier * clampf(item_grip_multiplier, 0.3, 1.0) * Surfaces.GRIP[sid] * Surfaces.mod_grip(wheel.end, sid)
		if hb:
			mu *= tuning.handbrake_grip
		var max_f: float = mu * load

		var fx: float = 0.0
		# fs points the drive at the ACTIVE end's forward axis: -Z for End A, +Z
		# for End B. A locked wheel puts no power down.
		if steered and not hb:
			fx += drive_per_wheel * fs
		var requested: float = absf(fx)
		# Rolling/bogging resistance eases off at a crawl, so a car caught in the
		# bog on the wrong end is crippled rather than welded to the spot.
		var bog: float = 0.4 + 0.6 * minf(1.0, absf(lon) / 8.0)
		fx -= Surfaces.ROLL[sid] * load * _soft(lon) * bog
		fx -= brk * tuning.brake_force(active_end) * brake_multiplier * 0.25 * _soft(lon)
		if hb:
			fx -= max_f * tuning.handbrake_lock * _soft(lon, 6.0)
		var fy: float = -max_f * tanh(lat * tuning.slip_k)

		var mag: float = sqrt(fx * fx + fy * fy)
		if mag > max_f and mag > 1e-6:
			var k: float = max_f / mag
			fx *= k
			fy *= k
			wheel.slip = 1.0
		else:
			wheel.slip = (mag / max_f) if max_f > 1e-6 else 0.0
		wheel.spin = maxf(0.0, (requested - absf(fx)) / requested) if requested > 1.0 else 0.0
		max_slip = maxf(max_slip, wheel.slip)

		# Tyre force acts at the contact patch. That is what produces real load
		# transfer and body roll, which the 2D model could not have.
		wheel.dbg_fx = fx
		wheel.dbg_fy = fy
		wheel.dbg_lon = lon
		var f_world: Vector3 = basis * (w_dir * fx + w_lat * fy)
		state.apply_force(f_world, basis * (wheel.position + Vector3(0.0, -wheel.ride_distance, 0.0)))
		# The ground reaction acts along the CONTACT NORMAL, not the strut axis.
		# Pushing along basis.y instead injects a phantom horizontal force whenever
		# the chassis is pitched or rolled — at a 5 deg rake that is sin(5) x 13.6 kN,
		# about 1.3 kN, which shoved End A along and held End B back.
		var f_susp: Vector3 = wheel.contact_normal * load
		state.apply_force(f_susp, r_worlds[i])
		f_tyre_total += f_world
		f_susp_total += f_susp

	# ---- body forces ----
	state.apply_central_force(-lv * speed * tuning.aero_drag)
	if active_end == "A" and tuning.downforce("A") > 0.0:
		state.apply_central_force(-basis.y * (tuning.downforce("A") * mass * 9.81 * pow(minf(speed, 80.0) / 60.0, 2.0)))

	var f_aero: Vector3 = -lv * speed * tuning.aero_drag
	var f_down := Vector3.ZERO
	if active_end == "A" and tuning.downforce("A") > 0.0:
		f_down = -basis.y * (tuning.downforce("A") * mass * 9.81 * pow(minf(speed, 80.0) / 60.0, 2.0))
	dbg["downforce"] = f_down
	dbg["tyre"] = f_tyre_total
	dbg["susp"] = f_susp_total
	dbg["aero"] = f_aero
	dbg["gravity"] = state.get_total_gravity() * mass
	dbg["net"] = f_tyre_total + f_susp_total + f_aero + f_down + state.get_total_gravity() * mass

	var av_local: Vector3 = inv * av
	state.apply_torque(basis * Vector3(
		-av_local.x * tuning.roll_damp * _inertia.x,
		-av_local.y * tuning.yaw_damp * _inertia.y,
		-av_local.z * tuning.roll_damp * _inertia.z,
	))

	wrong_end = Surfaces.PREFERRED[surface_under] != active_end
	_resolve_whiplash(dt, basis, lv)


func _tick_timers(dt: float) -> void:
	boost_time = maxf(0.0, boost_time - dt)
	if throttle <= 0.05 or brake > 0.05 or handbrake or power_cut > 0.0:
		boost_time = 0.0
	boost_cooldown = maxf(0.0, boost_cooldown - dt)
	damage = maxf(0.0, damage - DAMAGE_DECAY * dt)
	swap_feedback_time = maxf(0.0, swap_feedback_time - dt)
	cooldown = maxf(0.0, cooldown - dt)
	power_cut = maxf(0.0, power_cut - dt)
	engage = 1.0 if tuning.swap_engage <= 0.0 else minf(1.0, engage + dt / tuning.swap_engage)


func _tick_steering(dt: float) -> void:
	var top_ref: float = maxf(1.0, tuning.top_speed(active_end) * top_speed_multiplier)
	var lock: float = tuning.max_steer(active_end) * (
		1.0 - tuning.steer_falloff(active_end) * minf(1.0, speed / top_ref))
	# Negated: a positive rotation about +Y turns the forward vector toward -X,
	# which is LEFT in Godot. Steering right therefore wants a negative angle.
	var target: float = -steer * lock
	var rate: float = tuning.steer_rate(active_end) * dt
	steer_angle += clampf(target - steer_angle, -rate, rate)


func _resolve_whiplash(dt: float, basis: Basis, lv: Vector3) -> void:
	if _pending.is_empty():
		if not last_whiplash.is_empty():
			last_whiplash["age"] = float(last_whiplash.get("age", 0.0)) + dt
		return
	_pending["t"] = float(_pending["t"]) + dt
	var f: Vector3 = basis * Vector3(0.0, 0.0, -1.0) * forward_sign()
	var entry_speed: float = _pending["entry_speed"]
	if speed > 3.0:
		var aligned: float = f.dot(lv / speed)
		if aligned > 0.55 and speed > entry_speed * 0.45:
			var entry_basis: Basis = _pending["entry_basis"]
			var spun: float = absf((entry_basis.inverse() * basis).get_euler().y)
			last_whiplash = {
				"kind": "VECTOR SLIDE" if spun > 2.1 else "PURE REVERSAL",
				"retained": speed / entry_speed,
				"time": _pending["t"],
				"spun": spun,
				"age": 0.0,
			}
			_pending = {}
			# CPU charges are intentionally inert while its speed planner assumes normal drive.
			if float(last_whiplash["retained"]) >= 0.7:
				boost_charge = 1
			whiplash.emit(last_whiplash)
			return
	if float(_pending["t"]) > tuning.whiplash_window:
		_pending = {}


## Smooth sign: keeps rolling resistance and braking from chattering around zero.
static func _soft(x: float, k: float = 2.5) -> float:
	return tanh(x * k)
