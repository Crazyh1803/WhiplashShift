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

signal swapped(record: Dictionary)
signal whiplash(record: Dictionary)

@export var tuning: TuningProfile
@export var active_end: String = "A"

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


func _ready() -> void:
	if tuning == null:
		tuning = TuningProfile.new()
	_build()


func _build() -> void:
	mass = tuning.mass
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

	var w: float = tuning.body_width
	var h: float = tuning.body_height
	var l: float = tuning.body_length
	# Explicit inertia rather than letting the shape decide, so handling is
	# predictable and the yaw figure matches the web model exactly (2935).
	_inertia = Vector3(
		mass * (h * h + l * l) / 12.0,
		mass * (w * w + l * l) / 12.0,
		mass * (w * w + h * h) / 12.0,
	)
	inertia = _inertia
	_static_load = mass * 9.81 / 4.0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h * 0.75, l)
	shape.shape = box
	# sits above the centre of mass: CoM at hub height is what keeps it upright
	shape.position = Vector3(0.0, 0.25, 0.0)
	add_child(shape)

	_build_visuals()
	_build_wheels()


func _build_visuals() -> void:
	var spine := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tuning.body_width * 0.78, 0.5, tuning.body_length * 0.5)
	spine.mesh = bm
	spine.position = Vector3(0.0, 0.25, 0.0)
	spine.material_override = _mat(Color(0.20, 0.22, 0.26))
	add_child(spine)

	# End A: low, slim, sharp. End B: tall, blunt, wide. The asymmetry has to be
	# readable at a glance or none of the comedy lands.
	var a := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(tuning.body_width * 0.72, 0.34, 1.5)
	a.mesh = am
	a.position = Vector3(0.0, 0.12, -tuning.half_base - 0.35)
	a.material_override = _mat(Color("4fd2ff"))
	a.name = "EndAVisual"
	add_child(a)

	var b := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(tuning.body_width * 0.95, 0.78, 1.5)
	b.mesh = bmesh
	b.position = Vector3(0.0, 0.42, tuning.half_base + 0.35)
	b.material_override = _mat(Color("ffa63d"))
	b.name = "EndBVisual"
	add_child(b)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.65
	return m


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
		wheel.position = Vector3(
			side * tuning.half_track,
			0.0,
			(-tuning.half_base if end == "A" else tuning.half_base),
		)
		add_child(wheel)
		wheel.setup(end, side, tuning.wheel_radius(end))
		wheels.append(wheel)


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

	var top: float = tuning.top_speed(active_end) * top_mod
	# Taper against speed IN THE DIRECTION WE ARE DRIVING, not raw speed. This is
	# what lets End B pull full torque against the momentum it inherited.
	var drive_dir: float = 1.0 if thr >= 0.0 else -1.0
	var dir_top: float = maxf(4.0, top * (1.0 if drive_dir > 0.0 else 0.45))
	var taper: float = clampf(1.0 - (fwd_speed * drive_dir) / dir_top, 0.0, 1.0)
	var gate_open: float = 0.0 if power_cut > 0.0 else engage
	var drive_per_wheel: float = thr * tuning.drive(active_end) * accel_mod * taper * gate_open / 2.0
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
		var mu: float = tuning.tire_grip(wheel.end) * Surfaces.GRIP[sid] * Surfaces.mod_grip(wheel.end, sid)
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
		fx -= brk * tuning.brake_force(active_end) * 0.25 * _soft(lon)
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
	cooldown = maxf(0.0, cooldown - dt)
	power_cut = maxf(0.0, power_cut - dt)
	engage = 1.0 if tuning.swap_engage <= 0.0 else minf(1.0, engage + dt / tuning.swap_engage)


func _tick_steering(dt: float) -> void:
	var top_ref: float = maxf(1.0, tuning.top_speed(active_end))
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
			whiplash.emit(last_whiplash)
			return
	if float(_pending["t"]) > tuning.whiplash_window:
		_pending = {}


## Smooth sign: keeps rolling resistance and braking from chattering around zero.
static func _soft(x: float, k: float = 2.5) -> float:
	return tanh(x * k)
