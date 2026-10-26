## BOULDER relief must move the real rigid body, and the cosmetic rock pose must follow contacts.
extends Node3D

const DT := 1.0 / 60.0
const RUN_LENGTH := 420.0
const SETTLE_FRAMES := 90
const WINDOW_FRAMES := 300

var _pass := 0
var _fail := 0
var _stub: Vehicle
var _wheels_made: Array[Wheel] = []


func _ready() -> void:
	_test_rock_pose_units()
	await _test_driven_bodies()
	for wheel in _wheels_made:
		wheel.free()
	print("BOULDER_MOTION: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)


# ------------------------------------------------------------------ driven rigid body
func _test_driven_bodies() -> void:
	for speed: float in [20.0, 50.0]:
		for end: String in ["A", "B"]:
			var flat := await _drive(Surfaces.Id.TARMAC, speed, end)
			var rough := await _drive(Surfaces.Id.BOULDER, speed, end)
			var tag := "%s end %s @%dm/s" % ["BOULDER", end, int(speed)]
			print("BOULDER_MOTION: %s flat pitch %.3f roll %.3f yaw %.4f drift %.3f | boulder pitch %.3f roll %.3f yaw %.4f drift %.3f gap %.2fs speed %.1f" % [
				tag, flat["pitch"], flat["roll"], flat["yaw"], flat["drift"],
				rough["pitch"], rough["roll"], rough["yaw"], rough["drift"], rough["gap"], rough["speed"]])
			var flat_tilt: float = flat["pitch"] + flat["roll"]
			var rough_tilt: float = rough["pitch"] + rough["roll"]
			_check(tag + " drives for real on both surfaces", flat["speed"] > speed * 0.5 and rough["speed"] > speed * 0.5)
			_check(tag + " flat tarmac stays calm", flat_tilt < 1.0 and flat["gap"] < 0.1)
			_check(tag + " body pitch/roll visibly beats flat tarmac", rough_tilt > flat_tilt * 1.5 + 0.15)
			_check(tag + " pitch and roll both respond", rough["pitch"] > flat["pitch"] and rough["roll"] > flat["roll"])
			_check(tag + " motion is bounded, no runaway", rough["pitch"] < 12.0 and rough["roll"] < 12.0 and rough["max_tilt"] < 25.0)
			_check(tag + " yaw rate is bounded", rough["yaw"] < 0.3)
			_check(tag + " lateral drift is bounded", rough["drift"] < 2.0)
			_check(tag + " keeps support (no long airborne gaps)", rough["gap"] < 0.3)
			_check(tag + " flat tarmac has no cosmetic rock pose", flat["rock"] == 0.0)
			var boulder_rock: float = rough["rock"]
			_check(tag + " boulder cosmetic pose is active and clamped", boulder_rock > 0.001 and boulder_rock < 0.08)
			if speed == 20.0:
				await _test_soft_driven(end, speed, boulder_rock)


func _test_soft_driven(end: String, speed: float, boulder_rock: float) -> void:
	for entry: Array in [[Surfaces.Id.MUD, 0.5], [Surfaces.Id.GRAVEL, 0.35], [Surfaces.Id.WATER, 0.2]]:
		var soft := await _drive(entry[0], speed, end)
		var tag := "%s end %s @%dm/s" % [Surfaces.KEYS[entry[0]], end, int(speed)]
		print("BOULDER_MOTION: %s cosmetic rock %.4f vs boulder %.4f" % [tag, soft["rock"], boulder_rock])
		_check(tag + " cosmetic pose stays gentler than boulder", soft["rock"] < boulder_rock)
		_check(tag + " cosmetic pose is bounded", soft["rock"] < 0.08)


func _run_points(length: float) -> Array:
	var run: Array = []
	var spacing := 3.5
	for i in int(length / spacing) + 1:
		run.append({"pos": Vector3(0, 0, -i * spacing), "dir": Vector3(0, 0, -1), "w": 24.0, "dist": spacing, "s": Surfaces.Id.BOULDER})
	return run


## Drives straight at a held speed and returns body motion metrics in degrees, rad/s and metres.
func _drive(sid: int, speed: float, end: String) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	TrackBuilder._build_run(root, _run_points(RUN_LENGTH), sid, 0, 0.0, true)
	var car := preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle("blackjack"))
	car.active_end = end
	root.add_child(car)
	# End B's forward is body +Z, so turn the chassis to keep both ends heading down -Z.
	car.global_transform = Transform3D(Basis(Vector3.UP, PI if end == "B" else 0.0), Vector3(0, 1.0, -8.0))
	car.linear_velocity = Vector3(0, 0, -speed)
	var start := car.global_position
	var pitch_lo := INF
	var pitch_hi := -INF
	var roll_lo := INF
	var roll_hi := -INF
	var yaw_sq := 0.0
	var speed_sum := 0.0
	var max_tilt := 0.0
	var gap := 0
	var longest_gap := 0
	var rock := 0.0
	var fx: VisceraResponse = car.get_node("VisceraResponse")
	for frame in SETTLE_FRAMES + WINDOW_FRAMES:
		car.throttle = clampf((speed - car.fwd_speed) * 0.5, 0.0, 1.0)
		car.brake = 0.0
		await get_tree().physics_frame
		if frame < SETTLE_FRAMES:
			continue
		var chassis := car.global_basis
		var pitch := rad_to_deg(asin(clampf(chassis.z.y, -1.0, 1.0)))
		var roll := rad_to_deg(asin(clampf(chassis.x.y, -1.0, 1.0)))
		pitch_lo = minf(pitch_lo, pitch)
		pitch_hi = maxf(pitch_hi, pitch)
		roll_lo = minf(roll_lo, roll)
		roll_hi = maxf(roll_hi, roll)
		yaw_sq += car.angular_velocity.y * car.angular_velocity.y
		speed_sum += car.linear_velocity.length()
		max_tilt = maxf(max_tilt, rad_to_deg(chassis.y.angle_to(Vector3.UP)))
		rock = maxf(rock, fx._rock_pose.length())
		var touching := false
		for wheel: Wheel in car.wheels:
			touching = touching or wheel.contact
		gap = 0 if touching else gap + 1
		longest_gap = maxi(longest_gap, gap)
	var result := {"pitch": pitch_hi - pitch_lo, "roll": roll_hi - roll_lo,
		"yaw": sqrt(yaw_sq / WINDOW_FRAMES), "drift": absf(car.global_position.x - start.x),
		"gap": longest_gap * DT, "speed": speed_sum / WINDOW_FRAMES, "max_tilt": max_tilt, "rock": rock}
	root.queue_free()
	await get_tree().process_frame
	return result


# ------------------------------------------------------------------ cosmetic rock pose
func _wheels(sid: int = Surfaces.Id.BOULDER, front := 0.0, rear := 0.0, left := 0.0, right := 0.0) -> Array[Wheel]:
	var result: Array[Wheel] = []
	for index in 4:
		var wheel := Wheel.new()
		wheel.end = "A" if index < 2 else "B"
		wheel.side = -1 if index % 2 == 0 else 1
		wheel.contact = true
		wheel.contact_normal = Vector3.UP
		wheel.surface_id = sid
		wheel.compression = (front if wheel.end == "A" else rear) + (left if wheel.side < 0 else right)
		result.append(wheel)
		_wheels_made.append(wheel)
	return result


func _tilted_boulder(slope: Vector3) -> Array[Wheel]:
	var result := _wheels()
	for wheel in result:
		wheel.contact_normal = slope if wheel.end == "A" else Vector3(-slope.x, slope.y, slope.z)
	return result


func _fx() -> VisceraResponse:
	if _stub == null:
		_stub = Vehicle.new()
		_stub.freeze = true
		add_child(_stub)
	var fx := VisceraResponse.new()
	fx._car = _stub
	return fx


## Runs the filter for `steps` frames and returns the cosmetic pose in chassis-local axes.
func _pose(wheels: Array, end: String, speed := 20.0, steps := 6, chassis := Basis.IDENTITY, fx: VisceraResponse = null) -> Vector3:
	var response := fx if fx != null else _fx()
	for step in steps:
		response._rock_contact_pose(DT, wheels, end, speed, chassis)
	var pose := response._rock_pose
	if fx == null:
		response.free()
	return pose


func _test_rock_pose_units() -> void:
	for end: String in ["A", "B"]:
		# Chassis-local axes: x pitch (End A is the -Z end), y yaw, z roll; the axle sign must not follow the driving end.
		_check("front axle compression lifts +pitch from End %s" % end, _pose(_wheels(Surfaces.Id.BOULDER, 0.02), end).x > 0.0)
		_check("rear axle compression lifts -pitch from End %s" % end, _pose(_wheels(Surfaces.Id.BOULDER, 0.0, 0.02), end).x < 0.0)
		_check("right side compression rolls + from End %s" % end, _pose(_wheels(Surfaces.Id.BOULDER, 0.0, 0.0, 0.0, 0.02), end).z > 0.0)
		_check("left side compression rolls - from End %s" % end, _pose(_wheels(Surfaces.Id.BOULDER, 0.0, 0.0, 0.02, 0.0), end).z < 0.0)
		var tilted := _wheels()
		var slope := Vector3(0.2, 1.0, 0.0).normalized()
		for wheel in tilted:
			wheel.contact_normal = slope if wheel.end == "A" else Vector3(-slope.x, slope.y, slope.z)
		_check("opposed axle slopes yaw + from End %s" % end, _pose(tilted, end).y > 0.0)
		for wheel in tilted:
			wheel.contact_normal = Vector3(-wheel.contact_normal.x, wheel.contact_normal.y, wheel.contact_normal.z)
		_check("reversed axle slopes yaw - from End %s" % end, _pose(tilted, end).y < 0.0)
		# World normals must be read in the chassis frame: a car yawed 90 degrees sees the same local slope.
		var turned := Basis(Vector3.UP, PI * 0.5)
		var world_tilted := _wheels()
		for wheel in world_tilted:
			var local := slope if wheel.end == "A" else Vector3(-slope.x, slope.y, slope.z)
			wheel.contact_normal = turned * local
		_check("yaw uses chassis-local normals from End %s" % end, _pose(world_tilted, end, 20.0, 6, turned).y > 0.0)

	var a := _pose(_wheels(Surfaces.Id.BOULDER, 0.02), "A")
	var b := _pose(_wheels(Surfaces.Id.BOULDER, 0.02), "B")
	_check("same contacts give the same axle sign from both ends", a.x > 0.0 and b.x > 0.0)
	_check("End B attenuates cosmetic motion (0.55x)", b.x < a.x and is_equal_approx(b.x, a.x * 0.55))
	_check("slow speeds scale the pose down", is_equal_approx(_pose(_wheels(Surfaces.Id.BOULDER, 0.02), "A", 4.0).x, a.x * 0.5))

	var big := _pose(_wheels(Surfaces.Id.BOULDER, 1.0, 0.0, 0.0, 1.0), "A", 30.0, 12)
	_check("pose clamps hold under extreme compression", absf(big.x) <= 0.052 + 0.0001 and absf(big.y) <= 0.021 + 0.0001
		and absf(big.z) <= 0.044 + 0.0001 and big.x > 0.04 and big.z > 0.03)

	var held := _fx()
	_pose(_wheels(Surfaces.Id.BOULDER, 0.05), "A", 20.0, 12, Basis.IDENTITY, held)
	_check("pose is non-zero while rocking", held._rock_pose.length() > 0.001)
	var airborne := _wheels(Surfaces.Id.BOULDER, 0.05)
	for wheel in airborne:
		wheel.contact = false
	_pose(airborne, "A", 20.0, 60, Basis.IDENTITY, held)
	_check("airborne wheels relax the pose and clear the filter", held._rock_pose.length() < 0.0005 and held._rock_slow == Vector3.ZERO)
	_pose(_wheels(Surfaces.Id.BOULDER, 0.05), "A", 20.0, 12, Basis.IDENTITY, held)
	held.reset_effect()
	_check("reset clears the cosmetic rock state", held._rock_pose == Vector3.ZERO and held._rock_slow == Vector3.ZERO)
	held.free()

	_check("stationary car has no rock pose", _pose(_wheels(Surfaces.Id.BOULDER, 0.05), "A", 0.0, 12) == Vector3.ZERO)
	_check("crawling below the speed gate has no rock pose", _pose(_wheels(Surfaces.Id.BOULDER, 0.05), "A", 0.2, 12) == Vector3.ZERO)
	for sid: int in [Surfaces.Id.TARMAC, Surfaces.Id.RUMBLE, Surfaces.Id.ICE, Surfaces.Id.OIL, Surfaces.Id.OFF]:
		_check("%s contacts cause no rock pose" % Surfaces.KEYS[sid], _pose(_wheels(sid, 0.05, 0.03, 0.02, 0.04), "A", 30.0, 12) == Vector3.ZERO)

	# Soft surfaces reuse the boulder filter at a fraction of its gain, identical contacts at both ends.
	for end: String in ["A", "B"]:
		var base := _pose(_wheels(Surfaces.Id.BOULDER, 0.02, 0.0, 0.0, 0.02), end)
		for entry: Array in [[Surfaces.Id.MUD, 0.5], [Surfaces.Id.GRAVEL, 0.35], [Surfaces.Id.WATER, 0.2]]:
			var soft := _pose(_wheels(entry[0], 0.02, 0.0, 0.0, 0.02), end)
			var tag := "%s from End %s" % [Surfaces.KEYS[entry[0]], end]
			_check("%s keeps boulder signs" % tag, soft.x > 0.0 and soft.z > 0.0)
			_check("%s pose is %.2fx boulder" % [tag, entry[1]], is_equal_approx(soft.x, base.x * entry[1]) and is_equal_approx(soft.z, base.z * entry[1]))
		var slope := Vector3(0.2, 1.0, 0.0).normalized()
		var tilted := _wheels(Surfaces.Id.MUD)
		for wheel in tilted:
			wheel.contact_normal = slope if wheel.end == "A" else Vector3(-slope.x, slope.y, slope.z)
		_check("mud slopes yaw + gently from End %s" % end, _pose(tilted, end).y > 0.0
			and _pose(tilted, end).y < _pose(_tilted_boulder(slope), end).y)
		# Per-contact weighting: boulder front plus mud rear sums the two contributions.
		var mixed := _wheels(Surfaces.Id.BOULDER, 0.02, 0.02)
		for wheel in mixed:
			if wheel.end == "B":
				wheel.surface_id = Surfaces.Id.MUD
		var boulder_front := _pose(_wheels(Surfaces.Id.BOULDER, 0.02, 0.0, 0.0, 0.0), end).x
		var expected := boulder_front - 0.5 * boulder_front
		var mixed_pose := _pose(mixed, end)
		_check("mixed boulder/mud weights each contact from End %s" % end, absf(mixed_pose.x - expected) < absf(expected) * 0.01 + 1e-6)
		var quiet := _wheels(Surfaces.Id.BOULDER, 0.02, 0.02)
		for wheel in quiet:
			if wheel.end == "B":
				wheel.surface_id = Surfaces.Id.TARMAC
		var water_mix := _wheels(Surfaces.Id.WATER, 0.02, 0.02)
		for wheel in water_mix:
			if wheel.end == "B":
				wheel.surface_id = Surfaces.Id.OIL
		_check("quiet partners do not add or damp pose from End %s" % end,
			is_equal_approx(_pose(quiet, end).x, _pose(_wheels(Surfaces.Id.BOULDER, 0.02), end).x)
			and is_equal_approx(_pose(water_mix, end).x, _pose(_wheels(Surfaces.Id.WATER, 0.02), end).x))

	# Settling: identical compression stops moving the pose, then recovery returns it to rest.
	var settle := _fx()
	_pose(_wheels(Surfaces.Id.MUD, 0.02, 0.02, 0.02, 0.02), "A", 20.0, 600, Basis.IDENTITY, settle)
	_check("flat equal soft contacts settle to no pose", settle._rock_pose.length() < 0.0005)
	var rocked := _wheels(Surfaces.Id.MUD, 0.04)
	_pose(rocked, "A", 20.0, 12, Basis.IDENTITY, settle)
	_check("unequal soft contacts move the pose", settle._rock_pose.length() > 0.001)
	_pose(rocked, "A", 20.0, 900, Basis.IDENTITY, settle)
	_check("held soft contacts settle", settle._rock_pose.length() < 0.0005)
	settle.free()

	# Mixed terrain: only BOULDER wheels count, however hard the others are compressed.
	var mixed := _wheels(Surfaces.Id.BOULDER, 0.02)
	var reference := _pose(mixed, "A")
	var polluted := _wheels(Surfaces.Id.BOULDER, 0.02)
	for wheel in polluted:
		if wheel.end == "B":
			wheel.surface_id = Surfaces.Id.TARMAC
			wheel.compression = 0.08
	var partial := _pose(polluted, "A")
	_check("non-boulder wheels are ignored on mixed terrain", partial.x > 0.0 and absf(partial.x - reference.x) < reference.x * 0.01 + 1e-6)
