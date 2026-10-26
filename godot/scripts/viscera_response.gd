## Terrain contact feedback. Reads physics; writes cosmetic meshes only.
class_name VisceraResponse
extends Node3D

const CAPACITY := 96
const ROCK_GAINS := {Surfaces.Id.BOULDER: 1.0, Surfaces.Id.MUD: 0.5, Surfaces.Id.GRAVEL: 0.35, Surfaces.Id.WATER: 0.2}
const FRAGMENT_NAMES := ["ThrownViscera", "ThrownEntrails", "ThrownLimbFragments", "ThrownArmorChips", "ThrownCarbonGrit", "ThrownRubbleChunks", "ThrownSpinalPlates", "ThrownBrokenRibs", "ThrownCoolantFlakes", "ThrownCoolantSplinters", "ThrownEffluentSheets", "ThrownEffluentDroplets", "ThrownIchorStrands", "ThrownIchorDroplets"]
static var _fragment_meshes: Array[ArrayMesh] = []
var sink := 0.0
var active_count := 0
var emitted_total := 0
var last_rate := 0.0
var rattle := 0.0
var impact := 0.0
var skid := 0.0
var wash := 0.0
var oil_slide := 0.0
var _oil_yaw := 0.0
var _skid_yaw := 0.0
var bounced_total := 0
var _rattle_phase := 0.0
var _car: RigidBody3D
var _visual: Node3D
var _rest := Transform3D.IDENTITY
var _pitch := 0.0
var _rock_pose := Vector3.ZERO
var _rock_slow := Vector3.ZERO
var _previous := Vector3.ZERO
var _suppress := 0
var _cursor := 0
var _carry := PackedFloat32Array([0, 0, 0, 0])
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _life := PackedFloat32Array()
var _duration := PackedFloat32Array()
var _sizes := PackedFloat32Array()
var _floor_y := PackedFloat32Array()
var _bounces := PackedInt32Array()
var _colors := PackedColorArray()
var _batches: Array[MultiMeshInstance3D] = []
var _kind := PackedInt32Array()
var _rotations := PackedVector3Array()
var _tumbles := PackedVector3Array()
var _rng := RandomNumberGenerator.new()


func setup(car: RigidBody3D) -> void:
	_car = car
	_previous = car.global_position
	_rng.seed = 71193


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for data in [_positions, _velocities, _life, _duration, _sizes, _floor_y, _colors, _kind, _rotations, _tumbles, _bounces]:
		data.resize(CAPACITY)
	if _fragment_meshes.is_empty():
		_fragment_meshes = [_tissue_mesh(), _entrail_mesh(), _limb_mesh(), _chip_mesh(), _grit_mesh(), _rubble_mesh(), _plate_mesh(), _rib_mesh(), _ice_mesh(false), _ice_mesh(true), _sheet_mesh(), _droplet_mesh(), _ichor_strand_mesh(), _ichor_drop_mesh()]
	var wet := StandardMaterial3D.new()
	wet.vertex_color_use_as_albedo = true
	wet.roughness = 0.22
	wet.metallic_specular = 0.6
	wet.clearcoat_enabled = true
	wet.clearcoat = 0.25
	wet.clearcoat_roughness = 0.15
	wet.cull_mode = BaseMaterial3D.CULL_DISABLED
	wet.emission_enabled = true
	wet.emission = Color("9b2226")
	wet.emission_energy_multiplier = 0.12
	var dry := StandardMaterial3D.new()
	dry.vertex_color_use_as_albedo = true
	dry.roughness = 0.82
	dry.metallic = 0.1
	dry.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ice := StandardMaterial3D.new()
	ice.vertex_color_use_as_albedo = true
	ice.roughness = 0.28
	ice.metallic_specular = 0.8
	ice.clearcoat_enabled = true
	ice.clearcoat = 0.5
	ice.clearcoat_roughness = 0.2
	ice.cull_mode = BaseMaterial3D.CULL_DISABLED
	var liquid := StandardMaterial3D.new()
	liquid.vertex_color_use_as_albedo = true
	liquid.roughness = 0.14
	liquid.metallic_specular = 0.8
	liquid.clearcoat_enabled = true
	liquid.clearcoat = 0.65
	liquid.clearcoat_roughness = 0.1
	liquid.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ichor := StandardMaterial3D.new()
	ichor.vertex_color_use_as_albedo = true
	ichor.roughness = 0.08
	ichor.metallic = 0.1
	ichor.metallic_specular = 0.9
	ichor.clearcoat_enabled = true
	ichor.clearcoat = 1.0
	ichor.clearcoat_roughness = 0.08
	ichor.cull_mode = BaseMaterial3D.CULL_DISABLED
	for kind in FRAGMENT_NAMES.size():
		var batch := _batch(FRAGMENT_NAMES[kind], _fragment_meshes[kind], CAPACITY, true)
		if kind >= 12:
			batch.material_override = ichor
		elif kind >= 10:
			batch.material_override = liquid
		else:
			batch.material_override = ice if kind >= 8 else (wet if kind < 3 else dry)
		_batches.append(batch)



func _batch(label: String, mesh: Mesh, count: int, colors: bool) -> MultiMeshInstance3D:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = colors
	batch.mesh = mesh
	batch.instance_count = count
	batch.visible_instance_count = 0
	var visual := MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = batch
	add_child(visual)
	return visual


## Matched-input response also makes the end comparison directly testable.
static func response(wheels: Array, end: String, speed: float, throttle: float, lateral_speed: float = 0.0) -> Dictionary:
	var wet := 0
	var rubble := 0
	var armor := 0
	var ice := 0
	var water := 0
	var oil := 0
	var oil_spin := 0.0
	var oil_slip := 0.0
	var water_spin := 0.0
	var ice_spin := 0.0
	var ice_slip := 0.0
	var spin := 0.0
	for wheel: Wheel in wheels:
		if not wheel.contact:
			continue
		if wheel.surface_id == Surfaces.Id.OIL:
			oil += 1
			oil_spin = maxf(oil_spin, wheel.spin)
			oil_slip = maxf(oil_slip, wheel.slip)
			continue
		if wheel.surface_id == Surfaces.Id.WATER:
			water += 1
			water_spin = maxf(water_spin, wheel.spin)
			continue
		if wheel.surface_id == Surfaces.Id.ICE:
			ice += 1
			ice_spin = maxf(ice_spin, wheel.spin)
			ice_slip = maxf(ice_slip, wheel.slip)
			continue
		if wheel.surface_id == Surfaces.Id.MUD:
			wet += 1
		elif wheel.surface_id == Surfaces.Id.GRAVEL:
			rubble += 1
		elif wheel.surface_id == Surfaces.Id.BOULDER:
			armor += 1
		else:
			continue
		spin = maxf(spin, wheel.spin)
	var wrong := end != Surfaces.PREFERRED[Surfaces.Id.MUD]
	var motion := clampf(absf(speed) / 10.0 + absf(throttle) * spin * 0.8, 0.0, 1.5)
	if absf(speed) < 0.25 and spin < 0.08:
		motion = 0.0
	var coverage := float(wet) / 4.0
	var rubble_wrong := end != Surfaces.PREFERRED[Surfaces.Id.GRAVEL]
	var armor_wrong := end != Surfaces.PREFERRED[Surfaces.Id.BOULDER]
	var rough_motion := clampf(absf(speed) / 12.0 + absf(throttle) * spin * 0.5, 0.0, 1.0)
	var ice_wrong := end != Surfaces.PREFERRED[Surfaces.Id.ICE]
	var ice_motion := clampf(absf(speed) / 10.0 + absf(throttle) * ice_spin * 0.8, 0.0, 1.5)
	if absf(speed) < 0.25 and ice_spin < 0.08:
		ice_motion = 0.0
	var water_wrong := end != Surfaces.PREFERRED[Surfaces.Id.WATER]
	var water_motion := clampf(absf(speed) / 10.0 + absf(throttle) * water_spin * 0.8, 0.0, 1.5)
	if absf(speed) < 0.25 and water_spin < 0.08:
		water_motion = 0.0
	var water_coverage := float(water) / 4.0
	var water_strength := minf(water_motion, 1.0)
	var wash_strength := water_coverage * water_strength * (1.0 if water_wrong else 0.18)
	var oil_wrong := end != Surfaces.PREFERRED[Surfaces.Id.OIL]
	var oil_motion := clampf(absf(speed) / 10.0 + absf(throttle) * oil_spin * 0.8, 0.0, 1.5)
	if absf(speed) < 0.25 and oil_spin < 0.08:
		oil_motion = 0.0
	return {"oil": oil, "oil_wrong": oil_wrong,
		"oil_rate": (27.0 if oil_wrong else 10.0) * oil_motion * (0.35 + 0.65 * clampf(oil_slip, 0.0, 1.0)),
		"oil_slide": float(oil) / 4.0 * clampf(lateral_speed / 2.5, -1.0, 1.0) * minf(absf(speed) / 2.0, 1.0) * (1.0 if oil_wrong else 0.14),
		"water": water, "water_wrong": water_wrong,
		"water_rate": (28.0 if water_wrong else 12.0) * water_motion,
		"wash": wash_strength,
		"water_sink": water_coverage * water_strength * (0.075 if water_wrong else 0.015),
		"water_pitch": wash_strength * deg_to_rad(2.4),
		"ice": ice, "ice_wrong": ice_wrong,
		"ice_rate": (25.0 if ice_wrong else 10.0) * ice_motion * (0.4 + 0.6 * clampf(ice_slip, 0.0, 1.0)),
		"skid": float(ice) / 4.0 * clampf(lateral_speed / 3.0, -1.0, 1.0) * minf(absf(speed) / 2.0, 1.0) * (1.0 if ice_wrong else 0.2),
		"wrong": wrong, "wet": wet,
		"rate": (24.0 if wrong else 10.0) * motion,
		"sink": coverage * (0.12 if wrong else 0.025) * (0.5 + 0.5 * absf(throttle)),
		"pitch": coverage * deg_to_rad(1.5 if wrong else 0.2) * absf(throttle),
		"power": 3.2 if wrong else 1.56,
		"rubble": rubble, "rubble_wrong": rubble_wrong,
		"rubble_rate": (30.0 if rubble_wrong else 14.0) * motion,
		"rubble_power": 3.0 if rubble_wrong else 1.44,
		"armor": armor, "armor_wrong": armor_wrong,
		"armor_rate": (15.0 if armor_wrong else 6.0) * motion,
		"armor_power": 3.8 if armor_wrong else 1.68,
		"impact": float(armor) / 4.0 * rough_motion * (1.0 if armor_wrong else 0.14),
		"rattle": float(rubble) / 4.0 * rough_motion * (1.0 if rubble_wrong else 0.18)}


func _process(delta: float) -> void:
	if not is_instance_valid(_car):
		return
	if _car.freeze:
		reset_effect()
		return
	var position := _car.global_position
	if position.distance_to(_previous) > maxf(6.0, _car.linear_velocity.length() * delta * 3.0):
		reset_effect()
		_previous = position
		return
	_previous = position
	if _suppress > 0:
		_suppress -= 1
		return
	var offset := _car.get_global_transform_interpolated().origin - position
	advance(minf(delta, 0.05), _car.get("wheels"), _car.get("active_end"),
		_car.linear_velocity, float(_car.get("throttle")), _car.global_basis, offset)


func advance(dt: float, wheels: Array, end: String, velocity: Vector3, throttle: float,
		body_basis: Basis, interpolation_offset: Vector3 = Vector3.ZERO) -> void:
	var state := response(wheels, end, velocity.length(), throttle, velocity.dot(body_basis.x))
	last_rate = maxf(float(state["rate"]) if int(state["wet"]) > 0 else 0.0,
		float(state["rubble_rate"]) if int(state["rubble"]) > 0 else 0.0)
	last_rate = maxf(last_rate, float(state["armor_rate"]) if int(state["armor"]) > 0 else 0.0)
	last_rate = maxf(last_rate, float(state["ice_rate"]) if int(state["ice"]) > 0 else 0.0)
	last_rate = maxf(last_rate, float(state["water_rate"]) if int(state["water"]) > 0 else 0.0)
	last_rate = maxf(last_rate, float(state["oil_rate"]) if int(state["oil"]) > 0 else 0.0)
	var weight := 1.0 - exp(-8.0 * dt)
	sink = lerpf(sink, float(state["sink"]) + float(state["water_sink"]), weight)
	wash = lerpf(wash, state["wash"], weight)
	rattle = lerpf(rattle, state["rattle"], weight)
	impact = lerpf(impact, state["impact"], weight)
	# Keep the mixed-frequency oscillators continuous; recovery resets the phase.
	_rattle_phase += dt * (14.0 + minf(velocity.length(), 25.0) * 0.6)
	var sign_end := -1.0 if end == "A" else 1.0
	oil_slide = lerpf(oil_slide, state["oil_slide"], weight)
	_oil_yaw = lerpf(_oil_yaw, sign_end * float(state["oil_slide"]) * 0.07, weight)
	skid = lerpf(skid, state["skid"], weight)
	_skid_yaw = lerpf(_skid_yaw, sign_end * float(state["skid"]) * 0.055, weight)
	_pitch = lerpf(_pitch, sign_end * (float(state["pitch"]) + float(state["water_pitch"])), weight)
	_rock_contact_pose(dt, wheels, end, velocity.length(), body_basis)
	_update_pose()
	for index in mini(wheels.size(), 4):
		var wheel: Wheel = wheels[index]
		if not wheel.contact or wheel.surface_id not in [Surfaces.Id.MUD, Surfaces.Id.GRAVEL, Surfaces.Id.BOULDER, Surfaces.Id.ICE, Surfaces.Id.WATER, Surfaces.Id.OIL]:
			_carry[index] = 0.0
			continue
		var contact := wheel.contact_point + interpolation_offset
		var normal := wheel.contact_normal.normalized()
		if normal.length_squared() < 0.5:
			normal = Vector3.UP
		var driven := wheel.end == end
		var rubble := wheel.surface_id == Surfaces.Id.GRAVEL
		var armor := wheel.surface_id == Surfaces.Id.BOULDER
		var ice := wheel.surface_id == Surfaces.Id.ICE
		var water := wheel.surface_id == Surfaces.Id.WATER
		var oil := wheel.surface_id == Surfaces.Id.OIL
		var rate: float = state["rate"]
		if oil:
			rate = state["oil_rate"]
		elif water:
			rate = state["water_rate"]
		elif ice:
			rate = state["ice_rate"]
		elif armor:
			rate = state["armor_rate"]
		elif rubble:
			rate = state["rubble_rate"]
		_carry[index] += rate * (1.5 if driven else 0.6) * dt
		while _carry[index] >= 1.0:
			_carry[index] -= 1.0
			if oil:
				_emit_ichor(contact, normal, body_basis.x * wheel.side, velocity, state["oil_wrong"])
			elif water:
				_emit_effluent(contact, normal, body_basis.x * wheel.side, velocity, state["water_wrong"])
			elif ice:
				_emit_ice(contact, normal, body_basis.x * wheel.side, velocity, state["ice_wrong"])
			elif armor:
				_emit_armor(contact, normal, body_basis.x * wheel.side, velocity, state["armor_power"], state["armor_wrong"])
			elif rubble:
				_emit_rubble(contact, normal, body_basis.x * wheel.side, velocity, state["rubble_power"], state["rubble_wrong"])
			else:
				_emit(contact, normal, body_basis.x * wheel.side, velocity, state["power"], state["wrong"])
	active_count = 0
	var counts := PackedInt32Array()
	counts.resize(FRAGMENT_NAMES.size())
	for index in CAPACITY:
		if _life[index] <= 0.0:
			continue
		_life[index] -= dt
		_velocities[index] += Vector3.DOWN * 9.8 * dt
		_positions[index] += _velocities[index] * dt
		if _life[index] <= 0.0:
			continue
		if _positions[index].y < _floor_y[index]:
			if _kind[index] >= 3 and _kind[index] < 10 and _bounces[index] == 0:
				_positions[index].y = _floor_y[index]
				_velocities[index] *= Vector3(0.6, -0.3, 0.6)
				_life[index] = minf(_life[index], 0.2)
				_bounces[index] = 1
				bounced_total += 1
			else:
				_life[index] = 0.0
				continue
		var shrink := clampf(_life[index] / (_duration[index] * 0.25), 0.0, 1.0)
		var size := _sizes[index] * shrink
		_rotations[index] += _tumbles[index] * dt
		var kind := _kind[index]
		var batch := _batches[kind].multimesh
		var shape := Basis.from_euler(_rotations[index])
		var scale := Vector3.ONE * size
		if kind == 10:
			var age := clampf(1.0 - _life[index] / _duration[index], 0.0, 1.0)
			scale *= Vector3(1.0 + age * 0.8, 1.0 - age * 0.7, 1.0 + age * 0.4)
		elif kind == 12:
			var age := clampf(1.0 - _life[index] / _duration[index], 0.0, 1.0)
			scale *= Vector3(1.0 - age * 0.55, 1.0 - age * 0.35, 1.0 + age * 1.2)
			if _velocities[index].length_squared() > 0.001:
				shape = Basis(Quaternion(Vector3.FORWARD, _velocities[index].normalized()))
		elif kind in [11, 13] and _velocities[index].length_squared() > 0.001:
			shape = Basis(Quaternion(Vector3.UP, _velocities[index].normalized()))
		batch.set_instance_transform(counts[kind], Transform3D(shape.scaled_local(scale), _positions[index]))
		batch.set_instance_color(counts[kind], _colors[index])
		counts[kind] += 1
		active_count += 1
	for kind in _batches.size():
		_batches[kind].multimesh.visible_instance_count = counts[kind]


func _emit(point: Vector3, normal: Vector3, outward: Vector3, velocity: Vector3, power: float, wrong: bool) -> void:
	var index := _cursor
	_cursor = (_cursor + 1) % CAPACITY
	_positions[index] = point + normal * 0.08
	_bounces[index] = 0
	# Broken low ejecta at the contact patch, mixed with the taller thrown spray.
	# Nothing remains attached underneath or encircles the tyre.
	var low := _rng.randf() < 0.35
	var rise := _rng.randf_range(0.15, 0.35) if low else _rng.randf_range(0.65, 1.2)
	_velocities[index] = velocity * 0.35 + outward * _rng.randf_range(0.4, power) + normal * power * rise
	_duration[index] = _rng.randf_range(0.2, 0.35) if low else _rng.randf_range(0.45, 0.85)
	_life[index] = _duration[index]
	_sizes[index] = _rng.randf_range(0.055, 0.12) * (1.5 if wrong else 0.9) * (0.65 if low else 1.0)
	_floor_y[index] = point.y + 0.01
	var pick := _rng.randf()
	_kind[index] = 0 if pick < 0.55 else (1 if pick < 0.90 else 2)
	_sizes[index] *= [0.65, 0.9, 0.6][_kind[index]]
	_rotations[index] = Vector3(_rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI))
	_tumbles[index] = Vector3(_rng.randf_range(-7, 7), _rng.randf_range(-7, 7), _rng.randf_range(-7, 7))
	# Geometry carries tissue/cut/bone colors; a neutral instance tint preserves them.
	_colors[index] = Color("bfaea1").lerp(Color.WHITE, _rng.randf_range(0.2, 1.0))
	emitted_total += 1


func _emit_rubble(point: Vector3, normal: Vector3, outward: Vector3, velocity: Vector3, power: float, wrong: bool) -> void:
	var index := _cursor
	_cursor = (_cursor + 1) % CAPACITY
	var pick := _rng.randf()
	_kind[index] = 3 if pick < 0.55 else (4 if pick < 0.90 else 5)
	_positions[index] = point + normal * 0.05
	_velocities[index] = velocity * 0.22 + outward * _rng.randf_range(0.3, power) + normal * _rng.randf_range(power * 0.4, power)
	_duration[index] = _rng.randf_range(0.4, 0.8)
	_life[index] = _duration[index]
	_sizes[index] = _rng.randf_range(0.035, 0.085) * (1.4 if wrong else 0.96) * (0.4 if _kind[index] == 4 else 1.0)
	_floor_y[index] = point.y + 0.015
	_bounces[index] = 0
	_rotations[index] = Vector3(_rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI))
	_tumbles[index] = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
	_colors[index] = Color("b3b0a6").lerp(Color.WHITE, _rng.randf_range(0.2, 1.0))
	emitted_total += 1


func _emit_armor(point: Vector3, normal: Vector3, outward: Vector3, velocity: Vector3, power: float, wrong: bool) -> void:
	# Reuse the dry trajectory/bounce lifecycle with larger, slower rotating plates.
	_emit_rubble(point, normal, outward, velocity, power, wrong)
	var index := (_cursor + CAPACITY - 1) % CAPACITY
	_kind[index] = 6 if _rng.randf() < 0.65 else 7
	_sizes[index] = _rng.randf_range(0.09, 0.17) * (1.45 if wrong else 0.78)
	_tumbles[index] *= 0.45
	_duration[index] = _rng.randf_range(0.65, 1.0)
	_life[index] = _duration[index]


func _emit_ice(point: Vector3, normal: Vector3, outward: Vector3, velocity: Vector3, wrong: bool) -> void:
	var index := _cursor
	_cursor = (_cursor + 1) % CAPACITY
	_kind[index] = 8 if _rng.randf() < 0.7 else 9
	_positions[index] = point + normal * 0.035
	var power := 2.0 if wrong else 0.78
	_velocities[index] = velocity * 0.3 + outward * _rng.randf_range(0.3, power) + normal * _rng.randf_range(0.2, power * 0.6)
	_duration[index] = _rng.randf_range(0.35, 0.7)
	_life[index] = _duration[index]
	_sizes[index] = _rng.randf_range(0.035, 0.09) * (1.6 if wrong else 0.84)
	_floor_y[index] = point.y + 0.008
	_bounces[index] = 0
	_rotations[index] = Vector3(_rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI))
	_tumbles[index] = Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9), _rng.randf_range(-9, 9))
	_colors[index] = Color("b2e8ed").lerp(Color.WHITE, _rng.randf_range(0.2, 1.0))
	emitted_total += 1


func _emit_effluent(point: Vector3, normal: Vector3, outward: Vector3, velocity: Vector3, wrong: bool) -> void:
	var index := _cursor
	_cursor = (_cursor + 1) % CAPACITY
	var sheet := _rng.randf() < 0.6
	_kind[index] = 10 if sheet else 11
	_positions[index] = point + normal * 0.05
	var power := 3.2 if wrong else 1.32
	# Low sheets pull outward; separate droplets form the higher broken spray.
	var rise := _rng.randf_range(0.15, 0.4) if sheet else _rng.randf_range(0.45, 0.85)
	_velocities[index] = velocity * 0.25 + outward * _rng.randf_range(0.5, power) + normal * power * rise
	_duration[index] = _rng.randf_range(0.3, 0.65)
	_life[index] = _duration[index]
	_sizes[index] = _rng.randf_range(0.11, 0.20) * (1.55 if wrong else 0.78) * (1.0 if sheet else 0.45)
	_floor_y[index] = point.y + 0.008
	_bounces[index] = 0
	_rotations[index] = Vector3(_rng.randf_range(-0.3, 0.3), -atan2(outward.z, outward.x), _rng.randf_range(-0.2, 0.2))
	_tumbles[index] = Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1, 1), _rng.randf_range(-1.5, 1.5))
	_colors[index] = Color("8ab6a5").lerp(Color.WHITE, _rng.randf_range(0.3, 0.8))
	emitted_total += 1


func _emit_ichor(point: Vector3, normal: Vector3, outward: Vector3, velocity: Vector3, wrong: bool) -> void:
	var index := _cursor
	_cursor = (_cursor + 1) % CAPACITY
	var strand := _rng.randf() < 0.65
	_kind[index] = 12 if strand else 13
	_positions[index] = point + normal * 0.04
	var power := 2.5 if wrong else 0.9
	_velocities[index] = velocity * 0.28 + outward * _rng.randf_range(0.2, power) + normal * _rng.randf_range(0.25, 0.7 if strand else 1.2) * power
	_duration[index] = _rng.randf_range(0.4, 0.75)
	_life[index] = _duration[index]
	_sizes[index] = _rng.randf_range(0.11, 0.18) * (1.6 if wrong else 0.78) * (1.0 if strand else 0.45)
	_floor_y[index] = point.y + 0.006
	_bounces[index] = 0
	_rotations[index] = Vector3.ZERO
	_tumbles[index] = Vector3.ZERO
	_colors[index] = Color("b0b7bc").lerp(Color.WHITE, _rng.randf_range(0.4, 1.0))
	emitted_total += 1


func _update_pose() -> void:
	if not is_instance_valid(_car):
		return
	var visual := _car.get_node_or_null("VisualRoot") as Node3D
	if visual != _visual or not is_instance_valid(_visual):
		_restore_pose()
		_visual = visual
		if is_instance_valid(_visual):
			_rest = _visual.transform
	if is_instance_valid(_visual):
		var shake := Vector3(sin(_rattle_phase) * 0.015, 0, sin(_rattle_phase * 1.37) * 0.01) * rattle
		var lift := sin(_rattle_phase * 1.73) * rattle * 0.022
		lift += sin(_rattle_phase * 0.21) * wash * 0.006
		shake += Vector3(0, _skid_yaw + _oil_yaw, -skid * 0.012 - oil_slide * 0.018)
		shake += _rock_pose
		_visual.transform = _rest * Transform3D(Basis.from_euler(Vector3(_pitch, 0, 0) + shake), Vector3(0, -sink + lift, 0))


func _rock_contact_pose(dt: float, wheels: Array, end: String, speed: float, body_basis: Basis) -> void:
	var target := Vector3.ZERO
	var contacts := 0
	var contact_gain := 0.0
	var tuning: TuningProfile = _car.get("tuning") if is_instance_valid(_car) else null
	if tuning != null and speed > 0.25:
		for wheel: Wheel in wheels:
			var weight: float = ROCK_GAINS.get(wheel.surface_id, 0.0)
			if not wheel.contact or weight == 0.0:
				continue
			contacts += 1
			contact_gain = clampf(maxf(contact_gain, weight), 0.0, 1.0)
			var axle := 1.0 if wheel.end == "A" else -1.0
			var normal := body_basis.inverse() * wheel.contact_normal
			target.x += weight * axle * wheel.compression / maxf(tuning.half_base * 4.0, 0.1)
			target.z += weight * float(wheel.side) * wheel.compression / maxf(tuning.half_track * 4.0, 0.1)
			target.y += weight * axle * normal.x * 0.25
	if contacts == 0:
		_rock_slow = Vector3.ZERO
		_rock_pose = _rock_pose.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * dt))
		return
	_rock_slow = _rock_slow.lerp(target, 1.0 - exp(-1.5 * dt))
	var gain := (1.0 if end == "A" else 0.55) * minf(speed / 8.0, 1.0)
	var pose := (target - _rock_slow) * gain
	pose = pose.clamp(Vector3(-0.052, -0.021, -0.044) * contact_gain, Vector3(0.052, 0.021, 0.044) * contact_gain)
	_rock_pose = _rock_pose.lerp(pose, 1.0 - exp(-12.0 * dt))


func _restore_pose() -> void:
	if is_instance_valid(_visual):
		_visual.transform = _rest


func reset_effect() -> void:
	_restore_pose()
	sink = 0.0
	rattle = 0.0
	impact = 0.0
	skid = 0.0
	wash = 0.0
	oil_slide = 0.0
	_oil_yaw = 0.0
	_skid_yaw = 0.0
	_rattle_phase = 0.0
	_pitch = 0.0
	_rock_pose = Vector3.ZERO
	_rock_slow = Vector3.ZERO
	last_rate = 0.0
	active_count = 0
	_life.fill(0.0)
	_carry.fill(0.0)
	_suppress = 2
	for batch in _batches:
		batch.multimesh.visible_instance_count = 0
	if is_instance_valid(_car):
		_previous = _car.global_position


func _exit_tree() -> void:
	_restore_pose()


## Small closed folded shreds, curved hollow-cut guts, and jointed appendage pieces.
## Cached code-native meshes; no billboard discs or sphere particles.
static func _face(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for vertex in 3:
		tool.set_normal(normal)
		tool.set_color([ca, cb, cc][vertex])
		tool.add_vertex([a, b, c][vertex])


static func _tissue_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = [Vector3(-1, 0, -0.5), Vector3(-0.4, 0.25, -1),
		Vector3(0.4, -0.05, -0.7), Vector3(0.95, 0.1, -0.1), Vector3(0.5, -0.18, 0.9),
		Vector3(-0.2, 0.05, 1), Vector3(-0.9, 0.2, 0.4)]
	var muscle := Color("9b2226")
	var cut := Color("e26d5c")
	for index in rim.size():
		var a := rim[index]
		var b := rim[(index + 1) % rim.size()]
		var fat := Color("b9a18a") if index == 2 else cut
		_face(tool, Vector3(0.05, 0.24, 0), a + Vector3.UP * 0.09, b + Vector3.UP * 0.09, fat, cut, muscle)
		_face(tool, Vector3(-0.1, -0.22, 0.05), b - Vector3.UP * 0.09, a - Vector3.UP * 0.09, muscle, muscle, cut)
		_face(tool, a + Vector3.UP * 0.09, a - Vector3.UP * 0.09, b + Vector3.UP * 0.09, cut, muscle, cut)
		_face(tool, b + Vector3.UP * 0.09, a - Vector3.UP * 0.09, b - Vector3.UP * 0.09, cut, muscle, muscle)
	return tool.commit()


static func _tube(tool: SurfaceTool, points: Array[Vector3], radii: Array[float], color: Color, cut_color: Color = Color("d68d78"), core_color: Color = Color("370e18")) -> void:
	const SIDES := 7
	var rings: Array = []
	var normals: Array = []
	for index in points.size():
		var tangent := (points[mini(index + 1, points.size() - 1)] - points[maxi(0, index - 1)]).normalized()
		var reference := Vector3.RIGHT if absf(tangent.dot(Vector3.UP)) > 0.9 else Vector3.UP
		var u := tangent.cross(reference).normalized()
		var v := tangent.cross(u).normalized()
		var ring: Array[Vector3] = []
		var radial: Array[Vector3] = []
		for side in SIDES:
			var angle := TAU * float(side) / SIDES
			var normal := u * cos(angle) + v * sin(angle)
			ring.append(points[index] + normal * radii[index])
			radial.append(normal)
		rings.append(ring)
		normals.append(radial)
	for index in points.size() - 1:
		for side in SIDES:
			var next := (side + 1) % SIDES
			for corner: Vector2i in [Vector2i(index, side), Vector2i(index + 1, side), Vector2i(index, next),
					Vector2i(index, next), Vector2i(index + 1, side), Vector2i(index + 1, next)]:
				tool.set_normal(normals[corner.x][corner.y])
				tool.set_color(color.lightened(0.08 if side % 3 == 0 else 0.0))
				tool.add_vertex(rings[corner.x][corner.y])
	# Closed end rims; anatomy defaults retain the pale cut and dark lumen.
	for index in [0, points.size() - 1]:
		var outward: Vector3 = (points[0] - points[1]).normalized() if index == 0 else (points[-1] - points[-2]).normalized()
		var center: Vector3 = points[index] - outward * radii[index] * 0.35
		for side in SIDES:
			var a: Vector3 = rings[index][side]
			var b: Vector3 = rings[index][(side + 1) % SIDES]
			_face(tool, a if index == 0 else b, b if index == 0 else a, center,
				cut_color, cut_color, core_color)


static func _entrail_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(tool, [Vector3(-0.35, 0.1, -1.65), Vector3(-0.35, 0, -0.85),
		Vector3(0.05, 0.2, -0.1), Vector3(0.35, 0.05, 0.7), Vector3(0.3, -0.1, 1.5)],
		[0.11, 0.17, 0.16, 0.14, 0.09], Color("be6254"))
	return tool.commit()


static func _limb_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(tool, [Vector3(-0.7, 0, -1.0), Vector3(-0.1, 0.15, -0.15), Vector3(0.65, 0.25, 0.8)],
		[0.23, 0.32, 0.17], Color("8d3032"))
	_tube(tool, [Vector3(0.63, 0.25, 0.77), Vector3(0.85, 0.28, 1.15)],
		[0.085, 0.045], Color("d8d3c4"))
	return tool.commit()


static func _chip_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = [Vector3(-1, 0, -0.6), Vector3(-0.2, 0, -1), Vector3(1, 0, -0.25), Vector3(0.4, 0, 0.8), Vector3(-0.7, 0, 0.6)]
	var bone := Color("d8d3c4")
	var carbon := Color("33353a")
	for index in rim.size():
		var a := rim[index]
		var b := rim[(index + 1) % rim.size()]
		_face(tool, Vector3(0, 0.15, -0.1), a + Vector3.UP * 0.04, b + Vector3.UP * 0.04,
			carbon if index == 2 else bone, bone, bone)
		_face(tool, Vector3(0, -0.16, -0.1), b - Vector3.UP * 0.04, a - Vector3.UP * 0.04, carbon, carbon, bone)
		_face(tool, a + Vector3.UP * 0.04, a - Vector3.UP * 0.04, b + Vector3.UP * 0.04, bone, carbon, bone)
		_face(tool, b + Vector3.UP * 0.04, a - Vector3.UP * 0.04, b - Vector3.UP * 0.04, bone, carbon, carbon)
	return tool.commit()


static func _grit_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = [Vector3(-0.8, -0.5, -0.6), Vector3(0.9, -0.4, -0.3), Vector3(0, -0.3, 0.9), Vector3(0.1, 0.9, 0)]
	for tri: Vector3i in [Vector3i(0, 1, 2), Vector3i(0, 3, 1), Vector3i(1, 3, 2), Vector3i(2, 3, 0)]:
		_face(tool, points[tri.x], points[tri.y], points[tri.z], Color("272a31"), Color("55565b"), Color("181b22"))
	return tool.commit()


static func _rubble_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = [Vector3(-0.7, 0, 0), Vector3(0.9, 0.15, 0), Vector3(0, -0.7, 0.1),
		Vector3(0.1, 0.8, -0.1), Vector3(0, 0, -0.8), Vector3(-0.1, 0, 0.9)]
	for tri: Vector3i in [Vector3i(3, 0, 4), Vector3i(3, 4, 1), Vector3i(3, 1, 5), Vector3i(3, 5, 0),
			Vector3i(2, 4, 0), Vector3i(2, 1, 4), Vector3i(2, 5, 1), Vector3i(2, 0, 5)]:
		_face(tool, points[tri.x], points[tri.y], points[tri.z], Color("a8a08e"), Color("d8d3c4"), Color("595c63"))
	return tool.commit()


static func _plate_mesh() -> ArrayMesh:
	# A bent ceramic laminate with a contrasting exposed carbon core.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = [Vector3(-1.2, 0.2, -0.7), Vector3(-0.3, 0, -0.9), Vector3(1.1, 0.15, -0.5), Vector3(0.7, 0.35, 0.6), Vector3(-0.6, 0.25, 0.8)]
	for index in rim.size():
		var a := rim[index]
		var b := rim[(index + 1) % rim.size()]
		var down := Vector3.DOWN * 0.18
		_face(tool, Vector3(0, 0.4, 0), a, b, Color("a8a08e"), Color("d8d3c4"), Color("d8d3c4"))
		_face(tool, Vector3(0, 0.05, 0), b + down, a + down, Color("181b22"), Color("55565b"), Color("181b22"))
		_face(tool, a, a + down, b, Color("d8d3c4"), Color("181b22"), Color("a8a08e"))
		_face(tool, b, a + down, b + down, Color("a8a08e"), Color("181b22"), Color("181b22"))
	return tool.commit()


static func _rib_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(tool, [Vector3(-1.1, -0.35, 0), Vector3(-0.65, 0.2, 0.1), Vector3(0, 0.45, 0), Vector3(0.65, 0.2, -0.1)], [0.24, 0.3, 0.27, 0.18], Color("bfb6a1"))
	return tool.commit()


static func _ice_mesh(splinter: bool) -> ArrayMesh:
	# Thin closed triangular prisms: frost-white faces, cold blue fracture edges.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = [Vector3(-0.65, 0, -0.8), Vector3(0.8, 0, -0.35), Vector3(0.1, 0, 1.0)]
	var axis := Vector3(0.32, 1.0, 1.8) if splinter else Vector3.ONE
	var thickness := Vector3.UP * 0.045
	for i in points.size():
		points[i] *= axis
	var face := Color("e4f2ef")
	var edge := Color("6fabb9")
	_face(tool, points[0] + thickness, points[1] + thickness, points[2] + thickness, face, Color.WHITE, face)
	_face(tool, points[2] - thickness, points[1] - thickness, points[0] - thickness, edge, edge, face)
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		_face(tool, a + thickness, a - thickness, b + thickness, face, edge, face)
		_face(tool, b + thickness, a - thickness, b - thickness, face, edge, edge)
	return tool.commit()


static func _sheet_mesh() -> ArrayMesh:
	# Uneven open ribbons with gaps: no closed disc or solid boulder silhouette.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Color("245650")
	var foam := Color("b8c8a5")
	for strip in 2:
		for segment in 3:
			var x := -1.1 + float(segment) * 0.73
			var next := x + 0.67
			var z := -0.32 + float(strip) * 0.42
			var a := Vector3(x, 0.05 + 0.28 * sin(float(segment)), z)
			var b := Vector3(next, 0.05 + 0.28 * sin(float(segment + 1)), z + 0.08)
			var c := a + Vector3(0.12, 0.3 + float(segment % 2) * 0.16, 0.19)
			var d := b + Vector3(-0.08, 0.32, 0.23)
			_face(tool, a, b, c, dark, dark, foam)
			_face(tool, c, b, d, foam, dark, foam)
	return tool.commit()


static func _droplet_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = [Vector3(-0.25, 0, 0), Vector3(0, 0, -0.22), Vector3(0.25, 0, 0), Vector3(0, 0, 0.22)]
	for i in rim.size():
		var a := rim[i]
		var b := rim[(i + 1) % rim.size()]
		_face(tool, Vector3(0.08, 1.0, 0), a, b, Color("b8c8a5"), Color("32685e"), Color("487d70"))
		_face(tool, Vector3(0, -0.6, 0), b, a, Color("245650"), Color("487d70"), Color("32685e"))
	return tool.commit()


static func _ichor_strand_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(tool, [Vector3(-0.15, 0, -1.2), Vector3(0.12, 0.2, -0.6), Vector3(-0.08, 0.05, 0), Vector3(0.15, 0.22, 0.65), Vector3(0.1, -0.1, 1.2)],
		[0.045, 0.09, 0.06, 0.085, 0.025], Color("252137"), Color("52675f"), Color("100d18"))
	return tool.commit()


static func _ichor_drop_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = [Vector3(-0.28, 0, 0), Vector3(0, 0, -0.24), Vector3(0.28, 0, 0), Vector3(0, 0, 0.24)]
	for i in rim.size():
		var a := rim[i]
		var b := rim[(i + 1) % rim.size()]
		_face(tool, Vector3(0.06, 1.1, 0), a, b, Color("616078"), Color("18131f"), Color("344a43"))
		_face(tool, Vector3(0, -0.55, 0), b, a, Color("0d0a13"), Color("344a43"), Color("18131f"))
	return tool.commit()
