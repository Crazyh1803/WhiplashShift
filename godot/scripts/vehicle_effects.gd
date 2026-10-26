## Cosmetic vehicle effects: tyre smoke, skid strips, boost plume, damage smoke, swap pulse.
## Reads vehicle and wheel state; writes only its own world-space meshes. Organic and
## terrain spray belongs to VisceraResponse and is deliberately not duplicated here.
class_name VehicleEffects
extends Node3D

const SMOKE_TEXTURE: Texture2D = preload("res://assets/vfx/smoke.png")
const SPARK_TEXTURE: Texture2D = preload("res://assets/vfx/spark.png")
const CLOUD_SHADER: Shader = preload("res://shaders/particle_smoke.gdshader")

const TYRE_SMOKE_CAPACITY := 160
const DAMAGE_SMOKE_CAPACITY := 64
const PLUME_CAPACITY := 96
const SKID_CAPACITY := 2048
const SKID_LIFETIME := 12.0
const SKID_MIN_SEGMENT := 0.6
const SKID_MAX_GAP := 3.0          ## a longer hop is a teleport or lost contact, never a streak
const TELEPORT_DISTANCE := 5.0
const SKID_LIFT := 0.025           ## offset along the ground normal against z-fighting
const MIN_SLIDE_LOAD := 200.0      ## newtons; lighter than this is airborne or skimming
const SMOKE_THRESHOLD := 0.16
const SKID_START := 0.22
const SKID_KEEP := 0.14
const PULSE_TIME := 0.5
const BOOST_RATE := 110.0
const TYRE_SMOKE_RATE := 44.0
const END_COLORS := {"A": Color("4fd2ff"), "B": Color("ff8a2a")}

static var _quad_mesh: QuadMesh
static var _plane_mesh: PlaneMesh
const PULSE_SHADER := preload("res://shaders/pulse_ring.gdshader")
static var _smoke_material: ShaderMaterial
static var _spark_material: StandardMaterial3D
static var _skid_material: ShaderMaterial
const SKID_SHADER := preload("res://shaders/tyre_skid.gdshader")

## Test and QA hook: values here replace what the vehicle reports (boost_time, damage, ...).
var state_override: Dictionary = {}
var tyre_smoke_emitted := 0
var damage_smoke_emitted := 0
var plume_emitted := 0
var skid_emitted := 0
var swap_pulses := 0
var damage_events := 0
var pulse_end := ""
var pulse_age := 999.0

var _car: Vehicle
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _prev_origin := Vector3.ZERO
var _have_origin := false
var _tyre: Pool
var _damage_pool: Pool
var _plume: Pool
var _skid_node: MultiMeshInstance3D
var _skid_a := PackedVector3Array()
var _skid_b := PackedVector3Array()
var _skid_n := PackedVector3Array()
var _skid_birth := PackedFloat32Array()
var _skid_width := PackedFloat32Array()
var _skid_wheel := PackedInt32Array()
var _skid_refresh := 0.0
var _skid_cursor := 0
var _skid_high := 0
var _chain_point: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _chain_live: Array[bool] = [false, false, false, false]
var _smoke_carry := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _damage_carry := 0.0
var _plume_carry := 0.0
var _pulse: MeshInstance3D


## Fixed-size particle pool drawn through one MultiMesh. Billboarding comes from the material.
class Pool extends RefCounted:
	var capacity := 0
	var count := 0
	var emitted := 0
	var gravity := Vector3.ZERO
	var node: MultiMeshInstance3D
	var _multimesh: MultiMesh
	var _cursor := 0
	var _pos := PackedVector3Array()
	var _vel := PackedVector3Array()
	var _age := PackedFloat32Array()
	var _dur := PackedFloat32Array()
	var _size0 := PackedFloat32Array()
	var _size1 := PackedFloat32Array()
	var _drag := PackedFloat32Array()
	var _c0 := PackedColorArray()
	var _c1 := PackedColorArray()

	func _init(label: String, mesh: Mesh, material: Material, size: int) -> void:
		capacity = size
		for data in [_pos, _vel, _age, _dur, _size0, _size1, _drag, _c0, _c1]:
			data.resize(size)
		_multimesh = MultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_colors = true
		_multimesh.mesh = mesh
		_multimesh.instance_count = size
		_multimesh.visible_instance_count = 0
		node = MultiMeshInstance3D.new()
		node.name = label
		node.multimesh = _multimesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))

	func emit(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, c0: Color, c1: Color, drag: float = 1.5) -> void:
		var slot := count
		if count >= capacity:
			slot = _cursor
			_cursor = (_cursor + 1) % capacity
		else:
			count += 1
		_pos[slot] = pos
		_vel[slot] = vel
		_age[slot] = 0.0
		_dur[slot] = maxf(0.05, life)
		_size0[slot] = size0
		_size1[slot] = size1
		_c0[slot] = c0
		_c1[slot] = c1
		_drag[slot] = drag
		emitted += 1

	func step(dt: float) -> void:
		var i := 0
		while i < count:
			_age[i] += dt
			if _age[i] >= _dur[i]:
				count -= 1
				if i != count:
					_pos[i] = _pos[count]
					_vel[i] = _vel[count]
					_age[i] = _age[count]
					_dur[i] = _dur[count]
					_size0[i] = _size0[count]
					_size1[i] = _size1[count]
					_c0[i] = _c0[count]
					_c1[i] = _c1[count]
					_drag[i] = _drag[count]
				if _cursor >= count:
					_cursor = 0
				continue
			_vel[i] = _vel[i] * maxf(0.0, 1.0 - _drag[i] * dt) + gravity * dt
			_pos[i] += _vel[i] * dt
			i += 1
		for index in count:
			var t := _age[index] / _dur[index]
			var color := _c0[index].lerp(_c1[index], t)
			color.a *= smoothstep(0.0, 0.12, t) * (1.0 - t)
			var size := lerpf(_size0[index], _size1[index], t)
			_multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * size), _pos[index]))
			_multimesh.set_instance_color(index, color)
		_multimesh.visible_instance_count = count

	func clear() -> void:
		count = 0
		_cursor = 0
		_multimesh.visible_instance_count = 0

	func positions() -> Array[Vector3]:
		var result: Array[Vector3] = []
		for index in count:
			result.append(_pos[index])
		return result

	func velocities() -> Array[Vector3]:
		var result: Array[Vector3] = []
		for index in count:
			result.append(_vel[index])
		return result


# ------------------------------------------------------------------ policy helpers
static func is_hard_surface(surface_id: int) -> bool:
	return surface_id == Surfaces.Id.TARMAC or surface_id == Surfaces.Id.RUMBLE


## How strongly a wheel is genuinely sliding, 0..1. wheel.slip is friction-circle
## utilisation, so a saturated value alone proves nothing: it needs lateral contact
## velocity, drive wheelspin, or a locked (handbrake/hard-braking) tyre to back it up.
static func slide_intensity(
	contact: bool, load: float, surface_id: int, lateral_speed: float, spin: float,
	slip: float, speed: float, locked: bool = false, braking: bool = false
) -> float:
	if not contact or load < MIN_SLIDE_LOAD or not is_hard_surface(surface_id):
		return 0.0
	var amount := smoothstep(0.8, 3.5, absf(lateral_speed)) * smoothstep(0.35, 0.85, slip)
	if slip >= 0.9 and spin > 0.3:
		amount = maxf(amount, clampf(spin, 0.0, 1.0) * 0.9)
	if locked and speed > 2.5:
		amount = maxf(amount, 0.85)
	if braking and slip >= 0.85 and speed > 6.0:
		amount = maxf(amount, 0.55)
	return clampf(amount, 0.0, 1.0)


static func end_color(end: String) -> Color:
	return END_COLORS.get(end, END_COLORS["A"])


## Local offset of an end's nose from the car origin. End A is -Z, End B is +Z.
static func end_offset(end: String, half_base: float, height: float = 0.5, reach: float = 0.8) -> Vector3:
	return Vector3(0.0, height, (half_base + reach) * (1.0 if end == "B" else -1.0))


static func other_end(end: String) -> String:
	return "B" if end == "A" else "A"


# ------------------------------------------------------------------ lifecycle
func setup(car: Vehicle) -> void:
	_car = car
	_prev_origin = car.global_position if car.is_inside_tree() else car.position
	_have_origin = true
	_rng.seed = 40113
	if car.has_signal("swapped") and not car.swapped.is_connected(_on_swapped):
		car.swapped.connect(_on_swapped)
	if car.has_signal("boosted") and not car.is_connected("boosted", _on_boosted):
		car.connect("boosted", _on_boosted)
	if car.has_signal("damaged") and not car.is_connected("damaged", _on_damaged):
		car.connect("damaged", _on_damaged)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_shared()
	_tyre = Pool.new("TyreSmoke", _quad_mesh, _smoke_material, TYRE_SMOKE_CAPACITY)
	_tyre.gravity = Vector3(0.0, 0.5, 0.0)
	_damage_pool = Pool.new("DamageSmoke", _quad_mesh, _smoke_material, DAMAGE_SMOKE_CAPACITY)
	_damage_pool.gravity = Vector3(0.0, 1.2, 0.0)
	_plume = Pool.new("BoostPlume", _quad_mesh, _spark_material, PLUME_CAPACITY)
	for pool: Pool in [_tyre, _damage_pool, _plume]:
		add_child(pool.node)
	_skid_a.resize(SKID_CAPACITY)
	_skid_b.resize(SKID_CAPACITY)
	_skid_n.resize(SKID_CAPACITY)
	_skid_birth.resize(SKID_CAPACITY)
	_skid_birth.fill(-1.0)
	_skid_width.resize(SKID_CAPACITY)
	_skid_wheel.resize(SKID_CAPACITY)
	var skid := MultiMesh.new()
	skid.transform_format = MultiMesh.TRANSFORM_3D
	skid.use_colors = true
	skid.mesh = _plane_mesh
	skid.instance_count = SKID_CAPACITY
	skid.visible_instance_count = 0
	_skid_node = MultiMeshInstance3D.new()
	_skid_node.name = "SkidStrips"
	_skid_node.multimesh = skid
	_skid_node.material_override = _skid_material
	_skid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skid_node.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))
	add_child(_skid_node)
	_pulse = MeshInstance3D.new()
	_pulse.name = "SwapPulse"
	_pulse.mesh = _quad_mesh
	_pulse.material_override = _pulse_material()
	_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulse.visible = false
	add_child(_pulse)


static func _build_shared() -> void:
	if _quad_mesh != null:
		return
	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = Vector2.ONE
	_plane_mesh = PlaneMesh.new()
	_plane_mesh.size = Vector2.ONE
	_smoke_material = ShaderMaterial.new()
	_smoke_material.shader = CLOUD_SHADER
	_smoke_material.set_shader_parameter("cloud", SMOKE_TEXTURE)
	_smoke_material.set_shader_parameter("luminance_mask", true)
	_spark_material = StandardMaterial3D.new()
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_spark_material.billboard_keep_scale = true
	_spark_material.vertex_color_use_as_albedo = true
	_spark_material.albedo_texture = SPARK_TEXTURE
	_spark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skid_material = ShaderMaterial.new()
	_skid_material.shader = SKID_SHADER


static func _pulse_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PULSE_SHADER
	material.set_shader_parameter("tint", Color.WHITE)
	return material


## Clear every particle, strip and pulse. Safe to call repeatedly (retry, recovery, respawn).
func reset() -> void:
	if _tyre == null:
		return
	for pool: Pool in [_tyre, _damage_pool, _plume]:
		pool.clear()
	_skid_birth.fill(-1.0)
	_skid_cursor = 0
	_skid_refresh = 0.0
	_skid_high = 0
	_skid_node.multimesh.visible_instance_count = 0
	_cut_chains()
	_smoke_carry.fill(0.0)
	_damage_carry = 0.0
	_plume_carry = 0.0
	pulse_age = 999.0
	pulse_end = ""
	_pulse.visible = false
	if _car != null and _car.is_inside_tree():
		_prev_origin = _car.global_position
	_have_origin = _car != null


func _physics_process(delta: float) -> void:
	if _car == null or not is_instance_valid(_car):
		return
	advance(delta, not _car.freeze)


# ------------------------------------------------------------------ state reads
func _read(key: String) -> float:
	if state_override.has(key):
		return float(state_override[key])
	if _car == null:
		return 0.0
	var value: Variant = _car.get(key)
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0.0


func _half_base() -> float:
	if _car != null and _car.tuning != null:
		return _car.tuning.half_base
	return 1.4


func _active_end() -> String:
	return _car.active_end if _car != null else "A"


# ------------------------------------------------------------------ simulation
## One effects step. `motion` may carry lin_vel/ang_vel overrides (tests, QA fixtures).
func advance(dt: float, emit: bool = true, motion: Dictionary = {}) -> void:
	if _tyre == null or _car == null or dt <= 0.0:
		return
	_time += dt
	var origin := _car.global_position
	if _have_origin and origin.distance_to(_prev_origin) > TELEPORT_DISTANCE:
		_cut_chains()
	_prev_origin = origin
	_have_origin = true
	var lin_vel: Vector3 = motion.get("lin_vel", _car.linear_velocity)
	var ang_vel: Vector3 = motion.get("ang_vel", _car.angular_velocity)
	if emit:
		_emit_tyre(dt, lin_vel, ang_vel)
		_emit_boost(dt, lin_vel)
		_emit_damage(dt, lin_vel)
	else:
		_cut_chains()
	_tyre.step(dt)
	_damage_pool.step(dt)
	_plume.step(dt)
	_skid_refresh += dt
	if _skid_refresh >= 0.05:
		_skid_refresh = fmod(_skid_refresh, 0.05)
		_refresh_skids()
	_update_pulse(dt)


func _cut_chains() -> void:
	for index in 4:
		_chain_live[index] = false


func _emit_tyre(dt: float, lin_vel: Vector3, ang_vel: Vector3) -> void:
	var xform := _car.global_transform
	var basis := xform.basis
	var speed := lin_vel.length()
	var lvel_body := basis.inverse() * lin_vel
	var trailing := "B" if -lvel_body.z >= 0.0 else "A"
	for index in _car.wheels.size():
		var wheel: Wheel = _car.wheels[index]
		var lateral := 0.0
		if wheel.contact:
			var n := wheel.contact_normal
			var lat_axis: Vector3 = basis * (Basis(Vector3.UP, wheel.steer_angle) * Vector3.RIGHT)
			lat_axis = (lat_axis - n * lat_axis.dot(n)).normalized()
			var v_point := lin_vel + ang_vel.cross(basis * wheel.position)
			lateral = v_point.dot(lat_axis)
		var locked := _car.handbrake and wheel.end == trailing
		var braking := _car.brake > 0.6 and absf(lvel_body.z) > 6.0
		var amount := slide_intensity(wheel.contact, wheel.normal_load, wheel.surface_id,
			lateral, wheel.spin, wheel.slip, speed, locked, braking)
		if amount >= SMOKE_THRESHOLD:
			_smoke_carry[index] += TYRE_SMOKE_RATE * amount * dt
			while _smoke_carry[index] >= 1.0:
				_smoke_carry[index] -= 1.0
				var p := wheel.contact_point + wheel.contact_normal * 0.18
				var drift := Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.6, 1.4), _rng.randf_range(-0.6, 0.6))
				var grey := _rng.randf_range(0.78, 0.94)
				_tyre.emit(p, lin_vel * 0.15 + drift, _rng.randf_range(1.2, 1.9),
					0.65, 2.0 + amount, Color(grey, grey, grey, 0.7 * amount),
					Color(grey * 0.8, grey * 0.8, grey * 0.84, 0.0), 1.8)
			tyre_smoke_emitted = _tyre.emitted
		else:
			_smoke_carry[index] = 0.0
		var threshold := SKID_KEEP if _chain_live[index] else SKID_START
		if amount >= threshold:
			_extend_skid(index, wheel)
		else:
			_chain_live[index] = false


func _extend_skid(index: int, wheel: Wheel) -> void:
	var point := wheel.contact_point
	if not _chain_live[index]:
		_chain_point[index] = point
		_chain_live[index] = true
		return
	var gap := point.distance_to(_chain_point[index])
	if gap > SKID_MAX_GAP:
		_chain_point[index] = point
		return
	if gap < SKID_MIN_SEGMENT:
		return
	var slot := _skid_cursor
	_skid_cursor = (_skid_cursor + 1) % SKID_CAPACITY
	_skid_high = maxi(_skid_high, slot + 1)
	_skid_a[slot] = _chain_point[index]
	_skid_b[slot] = point
	_skid_n[slot] = wheel.contact_normal
	_skid_birth[slot] = _time
	_skid_width[slot] = 0.32 if wheel.end == "A" else 0.48
	_skid_wheel[slot] = index
	_chain_point[index] = point
	skid_emitted += 1


## CPU-side strip transform: a unit plane laid on the ground normal between the two ends.
func skid_transform(slot: int) -> Transform3D:
	var normal := _skid_n[slot].normalized()
	var along := (_skid_b[slot] - _skid_a[slot]).slide(normal)
	var length := along.length()
	var fallback := normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var dir := (along / length) if length > 0.0001 else fallback
	var side := dir.cross(normal).normalized()
	var basis := Basis(side * _skid_width[slot], normal, dir * (length + 0.04))
	var center := (_skid_a[slot] + _skid_b[slot]) * 0.5 + normal * SKID_LIFT
	return Transform3D(basis, center)


func _refresh_skids() -> void:
	var multimesh := _skid_node.multimesh
	for slot in _skid_high:
		var birth := _skid_birth[slot]
		if birth < 0.0:
			continue
		var age := _time - birth
		if age >= SKID_LIFETIME:
			_skid_birth[slot] = -1.0
			multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -1000.0, 0.0)))
			continue
		multimesh.set_instance_transform(slot, skid_transform(slot))
		var fade := 1.0 - smoothstep(0.3, 1.0, age / SKID_LIFETIME)
		multimesh.set_instance_color(slot, Color(1.0, 1.0, 1.0, 0.9 * fade))
	multimesh.visible_instance_count = _skid_high


func _emit_boost(dt: float, lin_vel: Vector3) -> void:
	if _read("boost_time") <= 0.0:
		_plume_carry = 0.0
		return
	_plume_carry += BOOST_RATE * dt
	while _plume_carry >= 1.0:
		_plume_carry -= 1.0
		_spawn_plume(lin_vel, 1)


func _spawn_plume(lin_vel: Vector3, burst: int) -> void:
	var trailing := other_end(_active_end())
	var xform := _car.global_transform
	var back := xform.basis * Vector3(0.0, 0.0, 1.0 if trailing == "B" else -1.0)
	var base_color := end_color(trailing)
	for i in burst:
		var jitter := Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.1, 0.2), _rng.randf_range(-0.25, 0.25))
		var pos: Vector3 = xform * end_offset(trailing, _half_base(), 0.45, 0.6) + jitter * 0.4
		var vel := lin_vel * 0.3 + back * _rng.randf_range(14.0, 22.0) + jitter * 3.0
		_plume.emit(pos, vel, _rng.randf_range(0.3, 0.5), 0.9, 0.15,
			Color(base_color.r, base_color.g, base_color.b, 0.95).lightened(0.35),
			Color(base_color.r, base_color.g, base_color.b, 0.0), 0.6)
	plume_emitted = _plume.emitted


func _emit_damage(dt: float, lin_vel: Vector3) -> void:
	var damage := clampf(_read("damage"), 0.0, 1.0)
	if damage < 0.1:
		_damage_carry = 0.0
		return
	_damage_carry += lerpf(4.0, 22.0, damage) * dt
	while _damage_carry >= 1.0:
		_damage_carry -= 1.0
		_spawn_damage_puff(damage, lin_vel)


func _spawn_damage_puff(damage: float, lin_vel: Vector3) -> void:
	var xform := _car.global_transform
	var pos: Vector3 = xform * end_offset(_active_end(), _half_base(), 0.75, 0.2)
	var vel := lin_vel * 0.5 + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(1.5, 2.6), _rng.randf_range(-0.5, 0.5))
	var dark := _rng.randf_range(0.05, 0.14)
	_damage_pool.emit(pos, vel, _rng.randf_range(1.2, 2.0), 0.5, 1.8 + damage,
		Color(dark, dark, dark, 0.35 + 0.4 * damage), Color(dark, dark, dark, 0.0), 1.0)
	damage_smoke_emitted = _damage_pool.emitted


# ------------------------------------------------------------------ signal responses
func _on_swapped(record: Dictionary) -> void:
	if _car == null or _tyre == null:
		return
	pulse_end = String(record.get("end", _active_end()))
	pulse_age = 0.0
	swap_pulses += 1
	_pulse.visible = true
	(_pulse.material_override as ShaderMaterial).set_shader_parameter("tint", end_color(pulse_end))
	_update_pulse(0.0)


func _on_boosted(_record: Dictionary = {}) -> void:
	if _car == null or _tyre == null:
		return
	_spawn_plume(_car.linear_velocity, 14)


func _on_damaged(severity: float) -> void:
	if _car == null or _tyre == null or severity <= 0.0:
		return
	var level := clampf(severity, 0.0, 1.0)
	damage_events += 1
	for i in int(4.0 + 12.0 * level):
		_spawn_damage_puff(maxf(level, 0.3), _car.linear_velocity)


func _update_pulse(dt: float) -> void:
	if _pulse == null or not _pulse.visible:
		return
	pulse_age += dt
	if pulse_age >= PULSE_TIME:
		_pulse.visible = false
		return
	var t := pulse_age / PULSE_TIME
	var xform := _car.global_transform
	var ring := Basis.from_scale(Vector3.ONE * lerpf(0.8, 3.2, t))
	_pulse.global_transform = Transform3D(xform.basis * ring, xform * end_offset(pulse_end, _half_base(), 0.4, 0.5))
	var color := end_color(pulse_end)
	color.a = (1.0 - t) * 0.9
	(_pulse.material_override as ShaderMaterial).set_shader_parameter("tint", color)


# ------------------------------------------------------------------ inspection (tests, QA)
func skid_count() -> int:
	var alive := 0
	for slot in _skid_high:
		if _skid_birth[slot] >= 0.0:
			alive += 1
	return alive


## Live strips as {a, b, normal, wheel, birth, slot}, oldest first (the ring buffer is unwrapped).
func skid_segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := _skid_cursor if _skid_high >= SKID_CAPACITY else 0
	for offset in _skid_high:
		var slot := (start + offset) % SKID_CAPACITY
		if _skid_birth[slot] >= 0.0:
			result.append({"a": _skid_a[slot], "b": _skid_b[slot], "normal": _skid_n[slot],
				"wheel": _skid_wheel[slot], "birth": _skid_birth[slot], "slot": slot})
	return result


func particle_counts() -> Dictionary:
	return {"tyre": _tyre.count, "damage": _damage_pool.count, "plume": _plume.count, "skid": skid_count()}


func plume_positions() -> Array[Vector3]:
	return _plume.positions()


func plume_velocities() -> Array[Vector3]:
	return _plume.velocities()


func pulse_visible() -> bool:
	return _pulse != null and _pulse.visible


func pulse_node() -> MeshInstance3D:
	return _pulse
