extends Node3D

const EFFECTS_SCRIPT := preload("res://scripts/vehicle_effects.gd")
const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_policy()
	_test_smoke()
	_test_skids()
	_test_boost_plume()
	_test_damage_and_pulse()
	_test_multiple_and_cleanup()
	await _test_state_api()
	await _test_boost_force()
	await _test_integration()
	print("VEHICLE_EFFECTS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)


func _car(at := Vector3(0, 1, 0)) -> Vehicle:
	var car := Vehicle.new()
	car.freeze = true
	add_child(car)
	car.global_position = at
	return car


func _effects(car: Vehicle) -> VehicleEffects:
	var fx := car.get_node_or_null("VehicleEffects") as VehicleEffects
	if fx == null:
		fx = EFFECTS_SCRIPT.new()
		fx.name = "VehicleEffects"
		car.add_child(fx)
		fx.setup(car)
	fx.set_physics_process(false)
	return fx


func _ground(car: Vehicle, normal := Vector3.UP, sid := Surfaces.Id.TARMAC, slip := 1.0, spin := 0.0) -> void:
	for wheel: Wheel in car.wheels:
		wheel.contact = true
		wheel.contact_point = car.global_transform * (wheel.position - Vector3(0, 0.6, 0))
		wheel.contact_normal = normal
		wheel.surface_id = sid
		wheel.normal_load = 3400.0
		wheel.slip = slip
		wheel.spin = spin


## Steps the frozen car along -Z at `speed` with optional sideways velocity.
func _drive(car: Vehicle, fx: VehicleEffects, steps: int, speed: float, side := 0.0, normal := Vector3.UP, sid := Surfaces.Id.TARMAC, slip := 1.0, spin := 0.0) -> void:
	for step in steps:
		car.global_position += Vector3(side, 0, -speed) * DT
		_ground(car, normal, sid, slip, spin)
		fx.advance(DT, true, {"lin_vel": Vector3(side, 0, -speed)})


func _test_policy() -> void:
	var hard := Surfaces.Id.TARMAC
	_check("lateral slide counts", VehicleEffects.slide_intensity(true, 3400, hard, 6.0, 0.0, 1.0, 20.0) > 0.9)
	_check("saturated friction alone is not sliding", VehicleEffects.slide_intensity(true, 3400, hard, 0.2, 0.0, 1.0, 20.0) == 0.0)
	_check("low utilisation and low lateral is clean", VehicleEffects.slide_intensity(true, 3400, hard, 0.3, 0.0, 0.2, 20.0) == 0.0)
	_check("stationary burnout counts", VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.8, 1.0, 0.0) > 0.5)
	_check("spin without saturation is not sliding", VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.8, 0.5, 5.0) == 0.0)
	_check("handbrake lock counts when moving, not stationary",
		VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 1.0, 12.0, true) > 0.5
		and VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 1.0, 0.5, true) == 0.0)
	_check("hard braking counts only when saturated and fast",
		VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 1.0, 20.0, false, true) > 0.3
		and VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 0.5, 20.0, false, true) == 0.0)
	_check("airborne and unloaded wheels never slide",
		VehicleEffects.slide_intensity(false, 3400, hard, 9.0, 1.0, 1.0, 20.0) == 0.0
		and VehicleEffects.slide_intensity(true, 50, hard, 9.0, 1.0, 1.0, 20.0) == 0.0)
	_check("soft terrain is left to the viscera response",
		VehicleEffects.slide_intensity(true, 3400, Surfaces.Id.MUD, 9.0, 1.0, 1.0, 20.0) == 0.0
		and VehicleEffects.slide_intensity(true, 3400, Surfaces.Id.ICE, 9.0, 1.0, 1.0, 20.0) == 0.0)
	_check("ends have distinct colours", VehicleEffects.end_color("A") != VehicleEffects.end_color("B"))
	_check("end offsets sit at opposite noses", VehicleEffects.end_offset("A", 1.4).z < -1.4 and VehicleEffects.end_offset("B", 1.4).z > 1.4)


func _test_smoke() -> void:
	var car := _car()
	var fx := _effects(car)
	_check("effects root is top-level world space and direct child", fx.top_level and fx.get_parent() == car and fx.global_transform == Transform3D.IDENTITY)
	_ground(car, Vector3.UP, Surfaces.Id.TARMAC, 1.0, 0.0)
	for step in 60:
		fx.advance(DT, true, {"lin_vel": Vector3.ZERO})
	_check("stationary saturated tyres do not smoke or mark", fx.tyre_smoke_emitted == 0 and fx.skid_emitted == 0)
	_drive(car, fx, 60, 20.0, 0.0, Vector3.UP, Surfaces.Id.TARMAC, 0.3, 0.0)
	_check("low-slip straight driving is clean", fx.tyre_smoke_emitted == 0 and fx.skid_emitted == 0)
	_drive(car, fx, 60, 20.0, 0.0, Vector3.UP, Surfaces.Id.TARMAC, 1.0, 0.0)
	_check("saturated friction without lateral velocity is clean", fx.tyre_smoke_emitted == 0)
	_airborne(car)
	for step in 60:
		fx.advance(DT, true, {"lin_vel": Vector3(6, 0, -20)})
	_check("airborne car does not smoke", fx.tyre_smoke_emitted == 0)
	_drive(car, fx, 30, 18.0, 6.0)
	_check("sliding on tarmac emits smoke", fx.tyre_smoke_emitted > 10)
	var before := fx.tyre_smoke_emitted
	_drive(car, fx, 30, 18.0, 6.0, Vector3.UP, Surfaces.Id.MUD)
	_check("same slide in mud leaves smoke to the terrain response", fx.tyre_smoke_emitted == before)
	car.handbrake = true
	_drive(car, fx, 30, 14.0, 0.0)
	_check("locked trailing pair smokes under handbrake", fx.tyre_smoke_emitted > before)
	car.handbrake = false
	before = fx.tyre_smoke_emitted
	_drive(car, fx, 30, 0.0, 0.0, Vector3.UP, Surfaces.Id.TARMAC, 1.0, 0.9)
	_check("burnout wheelspin emits smoke at standstill", fx.tyre_smoke_emitted > before)
	_drive(car, fx, 600, 18.0, 6.0)
	_check("smoke pool stays bounded", fx.particle_counts().tyre <= VehicleEffects.TYRE_SMOKE_CAPACITY)
	car.free()


func _test_skids() -> void:
	var car := _car()
	var fx := _effects(car)
	var tilt := Vector3(0, 0.96, 0.28).normalized()
	_drive(car, fx, 60, 15.0, 5.0, tilt)
	var segments := fx.skid_segments()
	_check("sliding lays strips", segments.size() > 4)
	var normals_ok := true
	var continuous := true
	var last_b := {}
	var short := true
	for seg: Dictionary in segments:
		normals_ok = normals_ok and seg.normal.is_equal_approx(tilt)
		short = short and seg.a.distance_to(seg.b) < VehicleEffects.SKID_MAX_GAP
		if last_b.has(seg.wheel):
			continuous = continuous and last_b[seg.wheel].is_equal_approx(seg.a)
		last_b[seg.wheel] = seg.b
	_check("strips carry the ground normal", normals_ok)
	_check("strips are continuous per wheel with no long hops", continuous and short)
	var strips: MultiMeshInstance3D = fx.get_node("SkidStrips")
	# The headless renderer does not store MultiMesh data, so read the CPU geometry the multimesh is fed from.
	var planar := not segments.is_empty()
	for seg: Dictionary in segments:
		var strip: Transform3D = fx.skid_transform(seg.slot)
		planar = planar and absf(strip.basis.y.normalized().dot(tilt)) > 0.999 \
			and absf(strip.basis.x.normalized().dot(tilt)) < 0.001 \
			and absf(strip.basis.z.normalized().dot(tilt)) < 0.001 \
			and strip.origin.is_equal_approx((seg.a + seg.b) * 0.5 + tilt * VehicleEffects.SKID_LIFT)
	_check("strip transforms lie in the ground plane", planar)
	_check("strips are ordered oldest to newest", _births_ascend(segments))
	_check("strips are world-space, not parented to the moving car", fx.top_level and strips.global_transform == Transform3D.IDENTITY)
	# a teleport must not bridge a streak
	var count_before := fx.skid_count()
	car.global_position += Vector3(80, 0, 40)
	_drive(car, fx, 12, 15.0, 5.0)
	var bridge := false
	for seg: Dictionary in fx.skid_segments():
		bridge = bridge or seg.a.distance_to(seg.b) > VehicleEffects.SKID_MAX_GAP
	_check("teleport leaves no streak between positions", not bridge and fx.skid_count() >= count_before)
	# lost contact cuts the chain; resuming elsewhere does not connect
	_airborne(car)
	fx.advance(DT, true, {"lin_vel": Vector3(5, 0, -15)})
	var emitted := fx.skid_emitted
	car.global_position += Vector3(2, 0, 0)
	_drive(car, fx, 1, 15.0, 5.0)
	_check("resuming after airtime starts a new chain", fx.skid_emitted == emitted)
	# cap and lifetime
	_drive(car, fx, 1500, 30.0, 8.0)
	_check("skid strips are capped", fx.skid_count() <= VehicleEffects.SKID_CAPACITY and fx.skid_emitted > VehicleEffects.SKID_CAPACITY)
	_airborne(car)
	for step in int((VehicleEffects.SKID_LIFETIME + 1.0) / DT):
		fx.advance(DT, true, {"lin_vel": Vector3.ZERO})
	_check("strips expire after their lifetime", fx.skid_count() == 0)
	_drive(car, fx, 40, 15.0, 5.0)
	_check("skids return after expiry", fx.skid_count() > 0)
	fx.reset()
	_check("reset clears strips and smoke", fx.skid_count() == 0 and fx.particle_counts().tyre == 0)
	_drive(car, fx, 1, 15.0, 5.0)
	_check("reset leaves no chain bridging to the old position", fx.skid_count() == 0)
	car.free()


func _test_boost_plume() -> void:
	var car := _car()
	var fx := _effects(car)
	fx.state_override = {"boost_time": 0.0}
	for step in 30:
		fx.advance(DT, true, {"lin_vel": Vector3(0, 0, -20)})
	_check("no plume without boost", fx.plume_emitted == 0)
	fx.state_override = {"boost_time": 0.6}
	for step in 20:
		fx.advance(DT, true, {"lin_vel": Vector3(0, 0, -20)})
	var behind := fx.plume_positions()
	var behind_ok := behind.size() > 5
	for p in behind:
		behind_ok = behind_ok and p.z > car.global_position.z + 1.0
	var directional := not fx.plume_velocities().is_empty()
	for v in fx.plume_velocities():
		directional = directional and v.z > 0.0
	_check("End A drive plumes from the inactive End B", behind_ok)
	_check("plume streams backwards relative to travel", directional)
	car.active_end = "B"
	fx.reset()
	for step in 20:
		fx.advance(DT, true, {"lin_vel": Vector3(0, 0, 20)})
	var front := fx.plume_positions()
	var front_ok := front.size() > 5
	for p in front:
		front_ok = front_ok and p.z < car.global_position.z - 1.0
	_check("End B drive plumes from End A", front_ok)
	fx.state_override = {"boost_time": 0.0}
	var emitted := fx.plume_emitted
	for step in 90:
		fx.advance(DT, true, {})
	_check("plume stops and drains when boost ends", fx.plume_emitted == emitted and fx.particle_counts().plume == 0)
	fx.state_override = {"boost_time": 0.9}
	for step in 600:
		fx.advance(DT, true, {})
	_check("plume pool is bounded", fx.particle_counts().plume <= VehicleEffects.PLUME_CAPACITY)
	fx.reset()
	fx._on_boosted({})
	_check("boosted handler bursts a plume", fx.particle_counts().plume > 0)
	fx.reset()
	_check("reset clears plume", fx.particle_counts().plume == 0)
	car.free()


func _test_damage_and_pulse() -> void:
	var car := _car()
	var fx := _effects(car)
	fx.state_override = {"damage": 0.0}
	for step in 60:
		fx.advance(DT, true, {})
	_check("undamaged car does not smoke", fx.damage_smoke_emitted == 0)
	fx.state_override = {"damage": 0.3}
	for step in 120:
		fx.advance(DT, true, {})
	var light := fx.damage_smoke_emitted
	fx.reset()
	var baseline := fx.damage_smoke_emitted
	fx.state_override = {"damage": 1.0}
	for step in 120:
		fx.advance(DT, true, {})
	_check("damage smoke scales with severity", light > 0 and fx.damage_smoke_emitted - baseline > light)
	for step in 1200:
		fx.advance(DT, true, {})
	_check("damage smoke is bounded", fx.particle_counts().damage <= VehicleEffects.DAMAGE_SMOKE_CAPACITY)
	fx.state_override = {"damage": 0.0}
	for step in 240:
		fx.advance(DT, true, {})
	_check("damage smoke drains once repaired", fx.particle_counts().damage == 0)
	var events := fx.damage_events
	fx._on_damaged(0.0)
	_check("zero-severity hit is ignored", fx.damage_events == events and fx.particle_counts().damage == 0)
	fx._on_damaged(0.2)
	var weak: int = fx.particle_counts().damage
	fx.reset()
	fx._on_damaged(1.0)
	_check("harder hits burst more smoke", weak > 0 and fx.particle_counts().damage > weak)
	fx.reset()
	# swap pulse marks the newly active end
	_check("no pulse before a swap", not fx.pulse_visible())
	car.active_end = "B"
	car.swapped.emit({"end": "B", "reason": "test"})
	_check("swap shows a pulse for the new end", fx.pulse_visible() and fx.pulse_end == "B" and fx.swap_pulses == 1)
	var ring := fx.pulse_node()
	_check("pulse sits at the newly active end", ring.global_position.z > car.global_position.z + 1.0)
	fx.advance(DT * 10.0, true, {})
	_check("pulse grows while it plays", ring.global_transform.basis.x.length() > 1.0)
	fx.advance(VehicleEffects.PULSE_TIME, true, {})
	_check("pulse expires", not fx.pulse_visible())
	car.active_end = "A"
	car.swapped.emit({"end": "A", "reason": "test"})
	_check("swap back moves the pulse to End A", fx.pulse_node().global_position.z < car.global_position.z - 1.0)
	fx.reset()
	_check("reset hides the pulse", not fx.pulse_visible())
	car.free()


func _test_multiple_and_cleanup() -> void:
	var cars: Array[Vehicle] = []
	var effects: Array[VehicleEffects] = []
	for index in 3:
		var car := _car(Vector3(index * 20, 1, 0))
		cars.append(car)
		effects.append(_effects(car))
	_drive(cars[0], effects[0], 40, 15.0, 5.0)
	effects[1].state_override = {"boost_time": 0.5}
	for step in 20:
		effects[1].advance(DT, true, {})
	_check("effects are independent per vehicle",
		effects[0].skid_count() > 0 and effects[1].skid_count() == 0 and effects[2].tyre_smoke_emitted == 0
		and effects[1].plume_emitted > 0 and effects[0].plume_emitted == 0)
	var single := true
	for car in cars:
		single = single and car.find_children("VehicleEffects", "Node3D", false, false).size() == 1
	_check("each car owns exactly one effects node", single)
	var untouched := true
	for car in cars:
		untouched = untouched and car.linear_velocity == Vector3.ZERO and car.angular_velocity == Vector3.ZERO
	_check("effects never move the body", untouched)
	_check("effects create no collision objects", effects[0].find_children("*", "CollisionObject3D", true, false).is_empty())
	var weak: Array = []
	for fx in effects:
		weak.append(weakref(fx))
	for car in cars:
		car.free()
	var gone := true
	for ref: WeakRef in weak:
		gone = gone and ref.get_ref() == null
	_check("freeing a car frees its effects", gone)


## Needs the Vehicle boost/damage API; every check is synchronous until the awaits.
func _test_state_api() -> void:
	var car := _car()
	if not car.has_method("try_boost") or not car.has_method("apply_cosmetic_damage") or not car.has_method("reset_effects_state"):
		_check("Vehicle exposes the boost and damage API", false)
		car.free()
		return
	_check("API constants match the design", is_equal_approx(Vehicle.BOOST_TIME, 0.9) and is_equal_approx(Vehicle.BOOST_COOLDOWN, 3.0)
		and is_equal_approx(Vehicle.BOOST_DRIVE, 0.65) and is_equal_approx(Vehicle.DAMAGE_DECAY, 0.05))
	var arm := func() -> void:
		car.freeze = false
		car.boost_charge = 1
		car.boost_time = 0.0
		car.boost_cooldown = 0.0
		car.power_cut = 0.0
		car.engage = 1.0
		car.throttle = 1.0
		car.fwd_speed = 12.0
		car.brake = 0.0
		car.handbrake = false
		_ground(car)
	arm.call()
	var earned := [0]
	car.boosted.connect(func(_record: Dictionary) -> void: earned[0] += 1)
	_check("boost succeeds with every gate open", car.try_boost() and car.boost_charge == 0 and car.boost_time > 0.0 and earned[0] == 1)
	_check("a second boost needs a new charge", not car.try_boost())
	var gates := {
		"no charge": func() -> void: car.boost_charge = 0,
		"cooldown": func() -> void: car.boost_cooldown = 1.0,
		"power cut": func() -> void: car.power_cut = 0.5,
		"disengaged": func() -> void: car.engage = 0.3,
		"frozen": func() -> void: car.freeze = true,
		"no throttle": func() -> void: car.throttle = 0.0,
		"braking": func() -> void: car.brake = 0.5,
		"handbrake": func() -> void: car.handbrake = true,
		"rolling backwards": func() -> void: car.fwd_speed = -2.0,
		"airborne": func() -> void: _airborne(car),
		"unloaded": func() -> void: _unload(car),
	}
	for label: String in gates:
		arm.call()
		gates[label].call()
		_check("boost refused: " + label, not car.try_boost())
	arm.call()
	car.reset_effects_state()
	_check("reset clears boost and damage state", car.boost_charge == 0 and car.boost_time == 0.0 and car.boost_cooldown == 0.0 and car.damage == 0.0)
	# whiplash earns a charge only when most speed is retained
	var resolve := func(now_speed: float) -> void:
		car.speed = now_speed
		car._pending = {"t": 0.2, "entry_speed": 20.0, "entry_basis": Basis.IDENTITY}
		car._resolve_whiplash(DT, Basis.IDENTITY, Vector3(0, 0, -now_speed))
	resolve.call(10.0)
	var poor: int = car.boost_charge
	_check("poorly retained whiplash resolves without a charge", poor == 0 and float(car.last_whiplash["retained"]) < 0.7)
	resolve.call(13.9)
	var marginal: int = car.boost_charge
	resolve.call(15.0)
	_check("clean whiplash earns exactly one charge", marginal == 0 and car.boost_charge == 1 and float(car.last_whiplash["retained"]) >= 0.7)
	arm.call()
	car.boost_charge = 1
	_check("charged boost fires", car.try_boost() and car.boost_time > 0.0)
	car.brake = 0.5
	car._tick_timers(DT)
	_check("braking cancels the active boost", car.boost_time == 0.0)
	arm.call()
	car.boost_charge = 1
	car.try_boost()
	car.swap_ends("test")
	_check("swap cancels the active boost", car.boost_time == 0.0)
	var severity := [-1.0]
	car.damaged.connect(func(value: float) -> void: severity[0] = value)
	car.apply_cosmetic_damage(0.4)
	_check("cosmetic damage raises damage and signals", car.damage > 0.0 and car.damage <= 1.0 and severity[0] > 0.0)
	car.apply_cosmetic_damage(5.0)
	_check("damage is clamped to 1", car.damage <= 1.0 and car.damage > 0.9)
	var before: float = car.damage
	car.freeze = false
	for frame in 30:
		await get_tree().physics_frame
	_check("damage decays over time", car.damage < before)
	car.reset_effects_state()
	_check("damage reset", car.damage == 0.0)
	car.free()


func _births_ascend(segments: Array[Dictionary]) -> bool:
	for index in range(1, segments.size()):
		if segments[index].birth < segments[index - 1].birth:
			return false
	return not segments.is_empty()


## Two identical grounded cars at the same speed; only one is boosted.
func _test_boost_force() -> void:
	var road := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	shape.shape = box
	road.add_child(shape)
	add_child(road)
	road.position = Vector3(3000, -1, 0)
	var cars: Array[Vehicle] = []
	for index in 2:
		var car := Vehicle.new()
		add_child(car)
		car.global_position = Vector3(3000 + index * 30, 0.7, 0)
		car.throttle = 1.0
		cars.append(car)
	cars[1].boost_charge = 1
	for frame in 30:
		await get_tree().physics_frame
	for car in cars:
		car.linear_velocity = Vector3(0, 0, -10)
	for frame in 3:
		await get_tree().physics_frame
	var grounded := true
	for car in cars:
		for wheel: Wheel in car.wheels:
			grounded = grounded and wheel.contact
	_check("boost comparison cars are grounded and moving", grounded and cars[0].speed > 5.0 and cars[1].speed > 5.0)
	cars[1].boost_time = 0.0
	cars[1].try_boost()
	for frame in 2:
		await get_tree().physics_frame
	var base_drive: float = cars[0].dbg["drive_per_wheel"]
	var boost_drive: float = cars[1].dbg["drive_per_wheel"]
	_check("boost scales drive force by exactly 1 + BOOST_DRIVE",
		absf(base_drive) > 100.0 and absf(boost_drive / base_drive - (1.0 + Vehicle.BOOST_DRIVE)) < 0.03)
	var start_speed: float = cars[1].speed
	var base_start: float = cars[0].speed
	for frame in 20:
		await get_tree().physics_frame
	_check("boosted car out-accelerates the baseline", cars[1].speed - start_speed > cars[0].speed - base_start)
	for car in cars:
		car.free()
	road.free()


## Real proving-ground paths that must reset effects and route hits through the cosmetic API.
func _test_integration() -> void:
	var scene: Node3D = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	var items: RaceItems = scene.items
	items.reset()
	scene.race.state = RaceDirector.State.RACING
	var victim: Vehicle = items.cars[1]
	var fx_victim := victim.get_node("VehicleEffects") as VehicleEffects
	fx_victim.set_physics_process(false)
	victim.linear_velocity = Vector3(0, 0, -20)
	items.grant_item(1, "shield")
	items.fire(1)
	items._apply_hit(1, 0, "rockets")
	_check("shielded hit causes no damage, effect or protection",
		victim.damage == 0.0 and fx_victim.damage_events == 0 and items.protection[1] == 0.0)
	items._tick_active(1, 10.0)
	items._apply_hit(1, 0, "rockets")
	var first_damage := victim.damage
	_check("accepted hit applies cosmetic damage and triggers damage smoke",
		first_damage >= 0.15 and fx_victim.damage_events == 1 and fx_victim.particle_counts().damage > 0 and items.protection[1] > 0.0)
	items._apply_hit(1, 0, "rockets")
	_check("hit protection is immune to further damage", victim.damage == first_damage and fx_victim.damage_events == 1)
	# player respawn / recovery
	var car: Vehicle = scene.car
	var fx := car.get_node("VehicleEffects") as VehicleEffects
	fx.set_physics_process(false)
	_prime(car, fx)
	car.throttle = 1.0
	car.brake = 0.4
	car.handbrake = true
	var destination := Transform3D(Basis(Vector3.UP, 0.4), Vector3(-620.0, 1.4, 80.0))
	scene._place_player(destination, "A")
	_check("_place_player clears boost, damage and effects", _is_clean(car, fx))
	_check("_place_player clears held controls", car.throttle == 0.0 and car.brake == 0.0 and not car.handbrake)
	# CPU recovery
	var driver: CpuDriver = scene.cpu_drivers[0]
	var cpu: Vehicle = driver.target
	var fx_cpu := cpu.get_node("VehicleEffects") as VehicleEffects
	fx_cpu.set_physics_process(false)
	_prime(cpu, fx_cpu)
	var before := driver.recoveries
	driver._recover()
	_check("CPU _recover counts and clears boost, damage and effects", driver.recoveries == before + 1 and _is_clean(cpu, fx_cpu))
	scene.queue_free()
	await get_tree().process_frame


func _prime(car: Vehicle, fx: VehicleEffects) -> void:
	car.boost_charge = 1
	car.boost_time = 0.5
	car.boost_cooldown = 1.0
	car.apply_cosmetic_damage(0.6)
	fx._on_boosted({})
	fx._on_swapped({"end": "B"})
	_check("%s effects primed before reset" % car.name,
		fx.particle_counts().plume > 0 and fx.particle_counts().damage > 0 and fx.pulse_visible())


func _is_clean(car: Vehicle, fx: VehicleEffects) -> bool:
	var counts := fx.particle_counts()
	return car.boost_charge == 0 and car.boost_time == 0.0 and car.boost_cooldown == 0.0 and car.damage == 0.0 \
		and counts.plume == 0 and counts.damage == 0 and counts.tyre == 0 and counts.skid == 0 and not fx.pulse_visible()


func _airborne(car: Vehicle) -> void:
	for wheel: Wheel in car.wheels:
		wheel.contact = false
		wheel.normal_load = 0.0


func _unload(car: Vehicle) -> void:
	for wheel: Wheel in car.wheels:
		wheel.normal_load = 0.0
