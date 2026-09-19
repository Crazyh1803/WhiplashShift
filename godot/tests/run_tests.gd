## Headless checks for the M0 physics port.
##
##   godot --headless --fixed-fps 120 --path godot res://tests/test_main.tscn
##
## No addon: a SceneTree scene plus `await get_tree().physics_frame` lets the
## tests read as straight-line code while the physics actually steps. Exits
## non-zero on failure so this can gate a commit.
extends Node3D

const TICK := 120.0

var car: Vehicle
var ground: StaticBody3D
var _pass := 0
var _fail := 0


func _ready() -> void:
	ground = _make_ground()
	add_child(ground)
	car = Vehicle.new()
	car.tuning = TuningProfile.new()
	add_child(car)
	await get_tree().physics_frame
	await _run_all()
	print("\n%d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run_all() -> void:
	print("\nthe thesis: a swap must not touch the body state")
	await _test_swap_preserves_momentum()

	print("\nsign checks (where an axis change bites)")
	await _test_steering_sign()
	await _test_forward_direction()

	print("\nsuspension (the one system with no web equivalent)")
	await _test_suspension_settles()

	print("\nfaithfulness to the web prototype (km/h, +/-15%)")
	await _test_top_speeds()

	print("\nasymmetry invariants")
	await _test_asymmetry()

	print("\nstability")
	await _test_no_nan_and_upright()

	print("\nthe real scene (authoring -> mesh -> collision -> metadata -> raycast)")
	await _test_scene_builds()


# ---------------------------------------------------------------- harness
func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [pass] %s%s" % [name, "  " + detail if detail else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, "  " + detail if detail else ""])


func _make_ground() -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000.0, 2.0, 6000.0)
	cs.shape = box
	cs.position = Vector3(0.0, -1.0, 0.0)   # top face sits at y = 0
	sb.add_child(cs)
	sb.set_meta("surface_type", "tarmac")
	return sb


func _reset(end: String, surface: String, speed: float = 0.0) -> void:
	ground.set_meta("surface_type", surface)
	car.active_end = end
	car.engage = 1.0
	car.cooldown = 0.0
	car.power_cut = 0.0
	car.steer_angle = 0.0
	car.throttle = 0.0
	car.brake = 0.0
	car.steer = 0.0
	car.handbrake = false
	car.last_whiplash = {}
	var t := Transform3D.IDENTITY
	# End B's forward is body +Z, so spin the body 180 deg and both ends start
	# pointing the same way in world space: toward -Z.
	if end == "B":
		t.basis = Basis(Vector3.UP, PI)
	t.origin = Vector3(0.0, 1.4, 0.0)
	car.global_transform = t
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	var v: Vector3 = t.basis * Vector3(0.0, 0.0, -1.0) * car.forward_sign() * speed
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	await _sim(0.35)   # let the suspension settle onto the ground


func _sim(seconds: float) -> void:
	var steps := int(seconds * TICK)
	for i in steps:
		await get_tree().physics_frame


func _drive(seconds: float, throttle: float = 1.0, steer: float = 0.0, brake: float = 0.0, hb: bool = false) -> void:
	car.throttle = throttle
	car.steer = steer
	car.brake = brake
	car.handbrake = hb
	await _sim(seconds)


# ---------------------------------------------------------------- tests
func _test_swap_preserves_momentum() -> void:
	await _reset("A", "tarmac")
	await _drive(2.5, 1.0, 0.25)          # some yaw on the clock as well as speed
	var pre_lin: Vector3 = car.linear_velocity
	var pre_ang: Vector3 = car.angular_velocity
	var pre_basis: Basis = car.global_transform.basis
	var rec: Dictionary = car.swap_ends("test")

	_check("linear velocity preserved exactly",
		car.linear_velocity == pre_lin,
		"%.6f -> %.6f m/s" % [pre_lin.length(), car.linear_velocity.length()])
	_check("angular velocity preserved exactly",
		car.angular_velocity == pre_ang,
		"y %.6f rad/s" % pre_ang.y)
	_check("basis untouched (the body does not rotate on a swap)",
		rec["basis_unchanged"])
	_check("active end actually changed", car.active_end == "B", "A -> %s" % car.active_end)
	_check("transmission drops out and has to spool back up", car.engage < 0.05)


func _test_steering_sign() -> void:
	# Facing -Z with +Y up, right is +X. Steering right must move us to +X.
	await _reset("A", "tarmac")
	await _drive(3.0, 1.0, 1.0)
	var x_right: float = car.global_position.x
	await _reset("A", "tarmac")
	await _drive(3.0, 1.0, -1.0)
	var x_left: float = car.global_position.x
	_check("steer right goes right, steer left goes left",
		x_right > 2.0 and x_left < -2.0,
		"right x=%.1f  left x=%.1f" % [x_right, x_left])

	# and the same input must still turn the same way on the other end
	await _reset("B", "mud")
	await _drive(3.0, 1.0, 1.0)
	var x_b: float = car.global_position.x
	_check("steering stays correct with End B driving", x_b > 1.0, "x=%.1f" % x_b)


func _test_forward_direction() -> void:
	await _reset("A", "tarmac")
	await _drive(2.0, 1.0)
	var z_a: float = car.global_position.z
	_check("End A drives along its own forward axis", z_a < -3.0, "z=%.1f" % z_a)
	_check("fwd_speed reads positive when driving forward", car.fwd_speed > 0.0,
		"%.1f m/s" % car.fwd_speed)

	await _reset("B", "mud")
	await _drive(2.0, 1.0)
	var z_b: float = car.global_position.z
	_check("End B drives along ITS forward axis, not End A's", z_b < -1.0, "z=%.1f" % z_b)


func _test_suspension_settles() -> void:
	await _reset("A", "tarmac")
	await _sim(1.5)
	var y_settled: float = car.global_position.y
	var a_ride: float = (car.wheels[0].ride_distance + car.wheels[1].ride_distance) * 0.5
	var b_ride: float = (car.wheels[2].ride_distance + car.wheels[3].ride_distance) * 0.5
	var all_planted := true
	var load_sum := 0.0
	for w: Wheel in car.wheels:
		all_planted = all_planted and w.contact
		load_sum += w.normal_load

	_check("all four wheels find the ground", all_planted)
	_check("car settles instead of sinking or launching",
		y_settled > 0.3 and y_settled < 1.6, "y=%.2f m" % y_settled)
	_check("suspension carries roughly the car's weight",
		absf(load_sum - car.mass * 9.81) < car.mass * 9.81 * 0.15,
		"%.0f N vs %.0f N static" % [load_sum, car.mass * 9.81])
	_check("End B rides visibly higher than End A",
		b_ride > a_ride + 0.15, "A %.2f m, B %.2f m" % [a_ride, b_ride])

	await _sim(1.0)
	_check("ride height is steady, not oscillating",
		absf(car.global_position.y - y_settled) < 0.03,
		"drift %.3f m over 1 s" % absf(car.global_position.y - y_settled))


func _test_top_speeds() -> void:
	# Measured from the web model itself at the SAME 26 s duration used here, on a
	# flat surface with no track logic. Ice converges very slowly — near-zero
	# rolling resistance means it is still creeping up at 18 s — so comparing
	# against a differently-timed reference reads as a 28% error that isn't real.
	var targets := {
		"A_tarmac": 192.0, "B_tarmac": 71.0,
		"A_mud": 4.0, "B_mud": 91.0,
		"A_gravel": 84.0, "B_gravel": 104.0,
		"A_ice": 96.0, "B_ice": 86.0,
	}
	for key: String in targets:
		var parts := key.split("_")
		await _reset(parts[0], parts[1])
		await _drive(26.0, 1.0)
		var kmh: float = car.speed * 3.6
		var want: float = targets[key]
		# the mud/A case is a near-stall; an absolute floor is fairer than a ratio
		var ok: bool = absf(kmh - want) <= maxf(want * 0.15, 6.0)
		_check("%-9s %6.0f (web %.0f)" % [key, kmh, want], ok)


func _test_asymmetry() -> void:
	await _reset("A", "tarmac")
	await _drive(20.0, 1.0)
	var a_tarmac: float = car.speed
	await _reset("B", "tarmac")
	await _drive(20.0, 1.0)
	var b_tarmac: float = car.speed
	_check("End A out-tops End B on tarmac by >35%%",
		a_tarmac > b_tarmac * 1.35,
		"%.0f vs %.0f km/h" % [a_tarmac * 3.6, b_tarmac * 3.6])

	await _reset("A", "tarmac")
	await _drive(2.0, 1.0)
	var a_tarmac_accel: float = car.speed
	await _reset("A", "mud")
	await _drive(2.0, 1.0)
	var a_mud_accel: float = car.speed
	await _reset("B", "mud")
	await _drive(2.0, 1.0)
	var b_mud_accel: float = car.speed

	_check("End A loses >=60%% of its acceleration in mud",
		a_mud_accel < a_tarmac_accel * 0.4,
		"%.1f -> %.1f m/s after 2 s" % [a_tarmac_accel, a_mud_accel])
	_check("End B out-accelerates End A in mud by >2x",
		b_mud_accel > a_mud_accel * 2.0,
		"%.1f vs %.1f m/s" % [b_mud_accel, a_mud_accel])


func _test_no_nan_and_upright() -> void:
	await _reset("A", "tarmac")
	var flipped := false
	var t := 0.0
	while t < 20.0:
		# full throttle into full lock: the classic way to put a car on its roof
		var s: float = 1.0 if fmod(t, 8.0) < 4.0 else -1.0
		await _drive(0.5, 1.0, s)
		t += 0.5
		if car.global_transform.basis.y.dot(Vector3.UP) < 0.2:
			flipped = true
	var p: Vector3 = car.global_position
	var v: Vector3 = car.linear_velocity
	_check("no NaN in position or velocity after 20 s",
		is_finite(p.x) and is_finite(p.y) and is_finite(p.z)
		and is_finite(v.x) and is_finite(v.y) and is_finite(v.z))
	_check("car stays on its wheels through full lock at speed", not flipped,
		"up.y = %.2f" % car.global_transform.basis.y.dot(Vector3.UP))


func _test_scene_builds() -> void:
	# tear down the bench world so the scene under test owns the space
	car.queue_free()
	ground.queue_free()
	await get_tree().process_frame

	var packed: PackedScene = load("res://scenes/proving_ground.tscn")
	_check("proving ground scene loads", packed != null)
	if packed == null:
		return
	var scene: Node3D = packed.instantiate()
	add_child(scene)
	await get_tree().physics_frame

	var runs := 0
	var proving := 0
	for c: Node in scene.get_children():
		if c.name.begins_with("Run_"):
			runs += 1
		elif c.name.begins_with("Proving_"):
			proving += 1
	_check("circuit built as surface runs", runs >= 12, "%d runs" % runs)
	_check("proving ground built beside it", proving >= 6, "%d strips" % proving)

	var scar: Vehicle = scene.get_node("Car")
	for i in 180:
		await get_tree().physics_frame
	var planted := true
	for w: Wheel in scar.wheels:
		planted = planted and w.contact
	_check("car settles on the grid with all four wheels down", planted)
	_check("and the surface under it reads TARMAC",
		scar.surface_under == Surfaces.Id.TARMAC,
		Surfaces.KEYS[scar.surface_under])

	# drive up the start straight; it must still be on tarmac, not off in a field.
	# the scene reads the keyboard every physics step, so stand that down first
	scene.set_physics_process(false)
	scar.throttle = 1.0
	for i in 480:
		await get_tree().physics_frame
	_check("driving the start straight stays on tarmac",
		scar.surface_under == Surfaces.Id.TARMAC and scar.speed > 15.0,
		"%s at %.0f km/h" % [Surfaces.KEYS[scar.surface_under], scar.speed * 3.6])

	# far enough to reach the rumble strip warning before the first gate
	for i in 360:
		await get_tree().physics_frame
	_check("keeps driving without falling through the ribbon",
		scar.global_position.y > -1.0 and is_finite(scar.global_position.y),
		"y=%.2f surface=%s" % [scar.global_position.y, Surfaces.KEYS[scar.surface_under]])
