## One wheel: the suspension raycast, what it found, and the visual.
##
## Deliberately dumb. It answers "what is under me and how far am I compressed";
## every force decision lives in vehicle.gd, so the thesis stays in one file the
## way it did in the web prototype.
class_name Wheel
extends Node3D

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

var _mesh: MeshInstance3D


func setup(p_end: String, p_side: int, p_radius: float) -> void:
	end = p_end
	side = p_side
	radius = p_radius
	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.34 if end == "A" else 0.56
	cyl.radial_segments = 16
	_mesh.mesh = cyl
	# cylinder's axis is Y by default; lay it on its side so it rolls about X
	_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.11)
	mat.roughness = 0.9
	_mesh.material_override = mat
	add_child(_mesh)


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
	if _mesh == null:
		return
	_mesh.position = Vector3(0.0, -(dist - radius), 0.0)
	_mesh.rotation = Vector3(0.0, steer_angle, PI * 0.5)
