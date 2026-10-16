## One wheel: the suspension raycast, what it found, and the visual.
##
## Deliberately dumb. It answers "what is under me and how far am I compressed";
## every force decision lives in vehicle.gd, so the thesis stays in one file the
## way it did in the web prototype.
class_name Wheel
extends Node3D

const TIRE_SHADER: Shader = preload("res://assets/vehicles/blackjack_tire.gdshader")

var end: String = "A"          ## "A" or "B"
var side: int = -1             ## -1 left, +1 right
var radius: float = 0.34

# --- filled each physics step by cast() ---
var contact: bool = false
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
var surface_id: int = Surfaces.Id.OFF
## Suspension displacement in metres. 0 = fully extended.
var compression: float = 0.0
var prev_compression: float = 0.0
## Distance from hardpoint to the contact patch.
var ride_distance: float = 0.0

# --- filled by vehicle.gd, read by the debug overlay ---
var normal_load: float = 0.0
var slip: float = 0.0
var spin: float = 0.0
var steered: bool = false
var steer_angle: float = 0.0
var dbg_fx: float = 0.0
var dbg_fy: float = 0.0
var dbg_lon: float = 0.0

var _visual: Node3D
var _visual_base_rotation := Vector3.ZERO
var _visual_offset := Vector3.ZERO


func setup(
	p_end: String,
	p_side: int,
	p_radius: float,
	scene_path: String = "",
	visual_config: Dictionary = {},
) -> void:
	end = p_end
	side = p_side
	radius = p_radius
	set_visual_scene(scene_path, visual_config)
	# Keep the preview state consistent with the first suspension result.  A zero
	# distance places the wheel (and therefore its axle) one radius above the
	# hardpoint until the first physics cast runs.
	ride_distance = radius
	_place_visual(ride_distance)


func set_visual_scene(scene_path: String, visual_config: Dictionary = {}) -> void:
	if _visual != null:
		remove_child(_visual)
		_visual.free()
	_visual_offset = Vector3.ZERO
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed != null:
			var imported := packed.instantiate() as Node3D
			if imported != null:
				var assembly := Node3D.new()
				assembly.name = "ModularWheelVisual"
				_visual = assembly
				_visual_base_rotation = _value_vec3(
					visual_config.get("assembly_rotation_degrees"), Vector3.ZERO
				) * PI / 180.0
				_visual_offset = _value_vec3(visual_config.get("assembly_offset"), Vector3.ZERO)
				add_child(assembly)
				_build_tire(assembly, visual_config)
				imported.name = "SwappableRim"
				imported.scale = _value_vec3(
					visual_config.get("rim_scale"), Vector3.ONE * radius * 0.82
				)
				imported.position = _value_vec3(visual_config.get("rim_offset"), Vector3.ZERO)
				imported.rotation_degrees = _value_vec3(
					visual_config.get("rim_rotation_degrees"), Vector3(0.0, 90.0, 0.0)
				)
				_configure_rim_material(imported)
				assembly.add_child(imported)
				return
	_build_placeholder_visual()


func _build_tire(parent: Node3D, visual_config: Dictionary) -> void:
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	var torus := TorusMesh.new()
	torus.outer_radius = radius
	torus.inner_radius = radius * float(visual_config.get("tire_inner_ratio", 0.66))
	torus.rings = 48
	torus.ring_segments = 24
	tire.mesh = torus
	# TorusMesh is built around Y; the suspension wheels roll around local X.
	tire.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	var material := ShaderMaterial.new()
	material.shader = TIRE_SHADER
	material.set_shader_parameter("tire_color", Color.from_string(
		"#" + String(visual_config.get("tire_color", "111418")), Color("111418")
	))
	material.set_shader_parameter("tread_scale", float(visual_config.get("tread_scale", 1.0)))
	tire.material_override = material
	parent.add_child(tire)
	_build_brake_hardware(parent)


func _configure_rim_material(root: Node3D) -> void:
	var alloy := StandardMaterial3D.new()
	alloy.albedo_color = Color("596168")
	alloy.metallic = 0.94
	alloy.roughness = 0.20
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = alloy
	for mesh_node: Node in root.find_children("*", "MeshInstance3D", true, false):
		(mesh_node as MeshInstance3D).material_override = alloy


func _build_brake_hardware(parent: Node3D) -> void:
	var disc := MeshInstance3D.new()
	disc.name = "BrakeDisc"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius * 0.52
	disc_mesh.bottom_radius = radius * 0.52
	disc_mesh.height = 0.035
	disc_mesh.radial_segments = 32
	disc.mesh = disc_mesh
	disc.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("7f878b")
	steel.metallic = 0.92
	steel.roughness = 0.34
	disc.material_override = steel
	parent.add_child(disc)

	var caliper := MeshInstance3D.new()
	caliper.name = "BrakeCaliper"
	var caliper_mesh := BoxMesh.new()
	caliper_mesh.size = Vector3(radius * 0.08, radius * 0.22, radius * 0.16)
	caliper.mesh = caliper_mesh
	caliper.position = Vector3(0.0, radius * 0.48, radius * 0.18)
	var caliper_material := StandardMaterial3D.new()
	caliper_material.albedo_color = Color("a91912")
	caliper_material.metallic = 0.54
	caliper_material.roughness = 0.30
	caliper.material_override = caliper_material
	parent.add_child(caliper)


func _build_placeholder_visual() -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.34 if end == "A" else 0.56
	cyl.radial_segments = 16
	mesh.mesh = cyl
	# cylinder's axis is Y by default; lay it on its side so it rolls about X
	_visual_base_rotation = Vector3(0.0, 0.0, PI * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.11)
	mat.roughness = 0.9
	mesh.material_override = mat
	_visual = mesh
	add_child(_visual)


## Raycast down the suspension axis. `rest` is travel length, not including radius.
## `from` is passed in rather than read off global_position: inside
## _integrate_forces the node transform lags the physics state we are mid-solving.
func cast(space: PhysicsDirectSpaceState3D, exclude: Array[RID], from: Vector3, body_up: Vector3, rest: float) -> void:
	prev_compression = compression
	var reach: float = rest + radius
	var query := PhysicsRayQueryParameters3D.create(from, from - body_up * reach)
	query.exclude = exclude
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)

	if hit.is_empty():
		contact = false
		compression = 0.0
		ride_distance = reach
		surface_id = Surfaces.Id.OFF
		normal_load = 0.0
		slip = 0.0
		spin = 0.0
		_place_visual(reach)
		return

	contact = true
	contact_point = hit["position"]
	contact_normal = hit["normal"]
	ride_distance = from.distance_to(contact_point)
	compression = maxf(0.0, reach - ride_distance)

	var col: Object = hit.get("collider")
	if col != null and col.has_meta("surface_type"):
		surface_id = Surfaces.id_from_key(str(col.get_meta("surface_type")))
	else:
		surface_id = Surfaces.Id.OFF

	_place_visual(ride_distance)


## Rate of compression, for the suspension damper.
func compression_velocity(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	return (compression - prev_compression) / dt


func _place_visual(dist: float) -> void:
	if _visual == null:
		return
	_visual.position = Vector3(0.0, -(dist - radius), 0.0) + _visual_offset
	_visual.rotation = Vector3(0.0, steer_angle, 0.0) + _visual_base_rotation


static func _value_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
