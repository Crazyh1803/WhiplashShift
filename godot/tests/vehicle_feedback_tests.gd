extends Node3D
## Field-feedback checks for tyre marks and the smoke screen, independent of the lead's own tests:
## slide policy, trail history/fade/expiry, per-puff smoke variation, and a real handbrake manoeuvre
## on the proving ground (actual Wheel.cast contacts, no mocked wheel state).
## The static helpers at the bottom are shared with vehicle_feedback_visual_qa.gd.

const EFFECTS_SCRIPT := preload("res://scripts/vehicle_effects.gd")
const DT := 1.0 / 60.0
const FAR_PARK := Vector3(3000.0, 40.0, 3000.0)

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_policy()
	_test_synthetic_marks()
	_test_history_and_links()
	_test_fade_and_expiry()
	_test_smoke_puffs()
	await _test_real_handbrake()
	_test_full_grid_cost()
	print("VEHICLE_FEEDBACK: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)


# ------------------------------------------------------------------ fixtures
func _car(at := Vector3(0, 1, 0)) -> Vehicle:
	var car := Vehicle.new()
	car.freeze = true
	add_child(car)
	car.global_position = at
	return car


func _effects(car: Vehicle) -> VehicleEffects:
	var fx := EFFECTS_SCRIPT.new() as VehicleEffects
	fx.name = "VehicleEffects"
	car.add_child(fx)
	fx.setup(car)
	fx.set_physics_process(false)
	return fx


func _ground(car: Vehicle, load := 3400.0, slip := 1.0, spin := 0.0, sid := Surfaces.Id.TARMAC) -> void:
	for wheel: Wheel in car.wheels:
		wheel.contact = true
		wheel.contact_point = car.global_transform * (wheel.position - Vector3(0, 0.6, 0))
		wheel.contact_normal = Vector3.UP
		wheel.surface_id = sid
		wheel.normal_load = load
		wheel.slip = slip
		wheel.spin = spin


func _airborne(car: Vehicle) -> void:
	for wheel: Wheel in car.wheels:
		wheel.contact = false
		wheel.normal_load = 0.0


## Moves the frozen car along -Z at `speed` with `side` m/s sideways, feeding matching velocity.
func _drive(car: Vehicle, fx: VehicleEffects, steps: int, speed: float, side := 0.0, load := 3400.0, slip := 1.0, spin := 0.0) -> void:
	for step in steps:
		car.global_position += Vector3(side, 0, -speed) * DT
		_ground(car, load, slip, spin)
		fx.advance(DT, true, {"lin_vel": Vector3(side, 0, -speed)})


# ------------------------------------------------------------------ slide policy
func _test_policy() -> void:
	var hard := Surfaces.Id.TARMAC
	_check("trail constants: pool 2048, spacing 0.6, lifetime 12",
		VehicleEffects.SKID_CAPACITY == 2048 and is_equal_approx(VehicleEffects.SKID_MIN_SEGMENT, 0.6)
		and is_equal_approx(VehicleEffects.SKID_LIFETIME, 12.0))
	_check("moderate loaded lateral slide now clears the mark threshold",
		VehicleEffects.slide_intensity(true, 3400, hard, 2.0, 0.0, 0.7, 15.0) >= VehicleEffects.SKID_START)
	_check("low-slip straight stays clean", VehicleEffects.slide_intensity(true, 3400, hard, 0.2, 0.0, 0.3, 25.0) == 0.0)
	_check("airborne and unloaded stay clean",
		VehicleEffects.slide_intensity(false, 3400, hard, 6.0, 0.0, 1.0, 20.0) == 0.0
		and VehicleEffects.slide_intensity(true, 150, hard, 6.0, 0.0, 1.0, 20.0) == 0.0)
	_check("handbrake lock produces feedback just above 2.5 m/s only",
		VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 1.0, 2.6, true) >= VehicleEffects.SMOKE_THRESHOLD
		and VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 1.0, 2.4, true) == 0.0)
	_check("saturated hard braking produces feedback just above 6 m/s only",
		VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 0.9, 6.2, false, true) >= VehicleEffects.SMOKE_THRESHOLD
		and VehicleEffects.slide_intensity(true, 3400, hard, 0.0, 0.0, 0.9, 5.8, false, true) == 0.0)


# ------------------------------------------------------------------ emission through advance()
func _test_synthetic_marks() -> void:
	var car := _car()
	var fx := _effects(car)
	_drive(car, fx, 90, 25.0, 0.0, 3400.0, 0.3)
	_check("low-slip straight emits nothing", fx.tyre_smoke_emitted == 0 and fx.skid_emitted == 0)
	_drive(car, fx, 90, 25.0, 6.0, 100.0, 1.0)
	_check("low load never emits, whatever the slip", fx.tyre_smoke_emitted == 0 and fx.skid_emitted == 0)
	_airborne(car)
	for step in 60:
		car.global_position += Vector3(6, 0, -25) * DT
		fx.advance(DT, true, {"lin_vel": Vector3(6, 0, -25)})
	_check("airborne emits nothing", fx.tyre_smoke_emitted == 0 and fx.skid_emitted == 0)
	_drive(car, fx, 60, 15.0, 2.0, 3400.0, 0.7)
	_check("moderate loaded lateral slide emits smoke and marks", fx.tyre_smoke_emitted > 4 and fx.skid_emitted > 4)
	car.free()

	car = _car()
	fx = _effects(car)
	car.handbrake = true
	_drive(car, fx, 60, 2.0, 0.0)
	_check("handbrake below 2.5 m/s stays clean", fx.tyre_smoke_emitted == 0 and fx.skid_emitted == 0)
	_drive(car, fx, 60, 3.2, 0.0)
	_check("handbrake above 2.5 m/s smokes and marks", fx.tyre_smoke_emitted > 0 and fx.skid_emitted > 0)
	car.free()

	car = _car()
	fx = _effects(car)
	car.brake = 0.9
	_drive(car, fx, 60, 5.0, 0.0, 3400.0, 0.95)
	_check("saturated braking below 6 m/s stays clean", fx.tyre_smoke_emitted == 0 and fx.skid_emitted == 0)
	_drive(car, fx, 60, 8.0, 0.0, 3400.0, 0.95)
	_check("saturated braking above 6 m/s gives feedback", fx.tyre_smoke_emitted > 0 and fx.skid_emitted > 0)
	car.free()


# ------------------------------------------------------------------ trail history and links
func _test_history_and_links() -> void:
	var car := _car()
	var fx := _effects(car)
	_drive(car, fx, 300, 40.0, 6.0)
	var segments := fx.skid_segments()
	_check("five seconds of 40 m/s four-wheel sliding never wraps the pool",
		fx.skid_emitted > 600 and fx.skid_emitted < VehicleEffects.SKID_CAPACITY and fx.skid_count() == fx.skid_emitted)
	_check("the first mark of the manoeuvre is still on the road", not segments.is_empty() and float(segments[0]["birth"]) < 0.2)
	var spaced := true
	var linked := true
	var last_b := {}
	for seg: Dictionary in segments:
		var length: float = seg.a.distance_to(seg.b)
		spaced = spaced and length >= VehicleEffects.SKID_MIN_SEGMENT - 0.001 and length <= VehicleEffects.SKID_MAX_GAP
		if last_b.has(seg.wheel):
			linked = linked and last_b[seg.wheel].is_equal_approx(seg.a)
		last_b[seg.wheel] = seg.b
	_check("every strip respects the 0.6 m minimum spacing and the hop limit", spaced)
	_check("per-wheel strips chain end to end", linked)
	var before := fx.skid_emitted
	for jump: Vector3 in [Vector3(4.0, 0, 0), Vector3(60.0, 0, 30.0)]:
		car.global_position += jump
		_drive(car, fx, 20, 40.0, 6.0)
	var bridge := false
	for seg: Dictionary in fx.skid_segments():
		bridge = bridge or seg.a.distance_to(seg.b) > VehicleEffects.SKID_MAX_GAP
	_check("neither a short hop nor a teleport is linked by a streak", not bridge and fx.skid_emitted > before)
	car.free()


func _slot_alpha(fx: VehicleEffects, slot: int) -> float:
	return (fx.get_node("SkidStrips") as MultiMeshInstance3D).multimesh.get_instance_color(slot).a


func _test_fade_and_expiry() -> void:
	var car := _car()
	var fx := _effects(car)
	_drive(car, fx, 30, 18.0, 6.0)
	_airborne(car)
	var oldest: Dictionary = fx.skid_segments()[0]
	var slot: int = oldest["slot"]
	var rendered := DisplayServer.get_name() != "headless"
	var alphas: Array[float] = []
	for target_age: float in [2.0, 7.8, 11.6]:
		while fx._time - float(oldest["birth"]) < target_age:
			fx.advance(DT, true, {"lin_vel": Vector3.ZERO})
		alphas.append(_slot_alpha(fx, slot) if rendered else -1.0)
	if rendered:
		var mid_expected := 0.9 * (1.0 - smoothstep(0.3, 1.0, 7.8 / VehicleEffects.SKID_LIFETIME))
		_check("marks are fully opaque before 30% of their life", absf(alphas[0] - 0.9) < 0.02)
		_check("marks fade through the middle of their life", absf(alphas[1] - mid_expected) < 0.03 and alphas[1] < alphas[0])
		_check("marks are nearly gone just before expiry", alphas[2] > 0.0 and alphas[2] < alphas[1] * 0.5)
	_check("marks are still on the road until their lifetime", fx.skid_count() > 0)
	while fx._time - float(oldest["birth"]) < VehicleEffects.SKID_LIFETIME + 0.6:
		fx.advance(DT, true, {"lin_vel": Vector3.ZERO})
	_check("every mark has expired after 12 s", fx.skid_count() == 0)
	# Freeze semantics: emission stops, existing strips keep ageing and are not reset.
	_drive(car, fx, 40, 18.0, 6.0)
	var emitted := fx.skid_emitted
	var live := fx.skid_count()
	for step in int(6.0 / DT):
		fx.advance(DT, false)
	_check("frozen state emits nothing", fx.skid_emitted == emitted)
	_check("frozen state keeps existing marks alive and ageing", fx.skid_count() == live and live > 0)
	_drive(car, fx, 1, 18.0, 6.0)
	_check("emission resuming after a freeze starts a new chain", fx.skid_emitted == emitted)
	for step in int(6.8 / DT):
		fx.advance(DT, false)
	_check("frozen marks still expire on schedule", fx.skid_count() == 0)
	_drive(car, fx, 40, 18.0, 6.0)
	fx.reset()
	_check("reset clears marks and smoke at once", fx.skid_count() == 0 and fx.particle_counts().tyre == 0)
	car.free()


# ------------------------------------------------------------------ smoke screen puffs
func _puffs(cloud: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in cloud.get_children():
		result.append(child as MeshInstance3D)
	return result


func _spread(values: Array) -> float:
	return (values.max() - values.min()) if not values.is_empty() else 0.0


func _distinct(values: Array) -> int:
	var seen := {}
	for value in values:
		seen[snappedf(value, 0.001)] = true
	return seen.size()


func _tint(puff: MeshInstance3D) -> Color:
	return (puff.material_override as ShaderMaterial).get_shader_parameter("tint")


func _finite(puff: MeshInstance3D) -> bool:
	var t := puff.transform
	return t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite() and t.basis.get_scale().x > 0.0


func _test_smoke_puffs() -> void:
	var art := RaceItemArt.new()
	add_child(art)
	art.tick(1.7)   # a non-zero clock proves ages are measured from each cloud's own birth
	art._rng.seed = 90210
	var cloud_a := art.hazard(Vector3(0, 3, 0), "smoke", Vector3.UP, -1)
	var cloud_b := art.hazard(Vector3(0, 3, 0), "smoke", Vector3.UP, -1)
	var puffs := _puffs(cloud_a)
	var other := _puffs(cloud_b)
	_check("a smoke deposit is built from several puffs", puffs.size() >= 5 and other.size() == puffs.size())
	var keys := {"origin": [], "drift": [], "phase": [], "growth": [], "fade_end": [], "fade_span": [], "rotation": []}
	for puff in puffs:
		var o: Vector3 = puff.get_meta("origin")
		var d: Vector3 = puff.get_meta("drift")
		keys["origin"].append(o.x + o.y * 7.0 + o.z * 13.0)
		keys["drift"].append(d.x + d.y * 7.0 + d.z * 13.0)
		keys["phase"].append(float(puff.get_meta("phase")))
		keys["growth"].append(float(puff.get_meta("growth")))
		keys["fade_end"].append(float(puff.get_meta("fade_end")))
		keys["fade_span"].append(float(puff.get_meta("fade_span")))
		keys["rotation"].append(float((puff.material_override as ShaderMaterial).get_shader_parameter("cloud_rotation")))
	for key: String in keys:
		_check("puffs randomise %s individually" % key, _distinct(keys[key]) >= puffs.size() - 1)
	var bounded := true
	for puff in puffs + other:
		var window := float(puff.get_meta("fade_end")) + float(puff.get_meta("fade_span"))
		bounded = bounded and float(puff.get_meta("fade_end")) >= 0.0 and window <= 5.0 and float(puff.get_meta("growth")) > 0.0
	_check("every puff fades inside the five-second life", bounded)
	_check("separate deposits are not clones of each other",
		_puffs(cloud_a)[0].get_meta("origin") != _puffs(cloud_b)[0].get_meta("origin")
		and puffs[1].get_meta("drift") != other[1].get_meta("drift"))
	art._rng.seed = 90210
	var replay := _puffs(art.hazard(Vector3(0, 3, 0), "smoke", Vector3.UP, -1))
	var replayed := true
	for i in puffs.size():
		replayed = replayed and replay[i].get_meta("origin") == puffs[i].get_meta("origin") and replay[i].get_meta("drift") == puffs[i].get_meta("drift")
	_check("seeding art._rng reproduces the same cloud", replayed)

	# A hazard whose life is refreshed every step (stationary owner): visual age must still advance.
	var held := {"visual": cloud_a, "id": "smoke", "life": 4.0}
	var last_scale: Array[float] = []
	last_scale.resize(puffs.size())
	last_scale.fill(0.0)
	var monotonic := true
	var finite := true
	var bounds := true
	var origin_dist_early := 0.0
	var origin_dist_late := 0.0
	for step in 120:
		art.tick(0.1)
		held["life"] = 4.0
		art.animate_hazard(held)
		for i in puffs.size():
			var s := puffs[i].scale.x
			monotonic = monotonic and s >= last_scale[i] - 0.000001
			last_scale[i] = s
			finite = finite and _finite(puffs[i])
			var a := _tint(puffs[i]).a
			bounds = bounds and is_finite(a) and a >= 0.0 and a <= 0.9001
		if step == 5:
			origin_dist_early = _mean_travel(puffs)
	origin_dist_late = _mean_travel(puffs)
	_check("with life pinned, puff scale never shrinks as art.clock advances", monotonic)
	_check("puffs keep spreading with the clock while life is refreshed", origin_dist_late > origin_dist_early + 0.5)
	_check("transforms are finite and alpha stays within 0..0.9", finite and bounds)
	var pos_a: Array[Vector3] = []
	for puff in puffs:
		pos_a.append(puff.position)
	held["life"] = 1.0
	art.animate_hazard(held)
	var age_free := true
	for i in puffs.size():
		age_free = age_free and puffs[i].position.is_equal_approx(pos_a[i])
	_check("puff motion depends on art.clock, not on remaining life", age_free)

	# heterogeneous spread at a late age, and varying late alpha across puffs and deposits
	var dx: Array[float] = []
	var dy: Array[float] = []
	var dz: Array[float] = []
	for puff in puffs:
		var offset: Vector3 = puff.position - puff.get_meta("origin")
		dx.append(offset.x)
		dy.append(offset.y)
		dz.append(offset.z)
	_check("lateral spread differs between puffs", _spread(dx) > 0.5 and _spread(dz) > 0.4 and _distinct(dx) == puffs.size())
	_check("vertical rise differs between puffs", _spread(dy) > 0.3 and _distinct(dy) == puffs.size())
	for late_life: float in [1.6, 1.2, 0.6]:
		held["life"] = late_life
		art.animate_hazard(held)
		var held_b := {"visual": cloud_b, "id": "smoke", "life": late_life}
		art.animate_hazard(held_b)
		var alpha_a: Array[float] = []
		var alpha_b: Array[float] = []
		for puff in puffs:
			alpha_a.append(_tint(puff).a)
		for puff in other:
			alpha_b.append(_tint(puff).a)
		_check("late alpha varies across puffs at %.1f s left" % late_life, _spread(alpha_a) > 0.05)
		_check("late alpha pattern differs between deposits at %.1f s left" % late_life, alpha_a != alpha_b)
	var alpha_end := true
	held["life"] = 0.0
	art.animate_hazard(held)
	for puff in puffs:
		alpha_end = alpha_end and _tint(puff).a == 0.0
	_check("every puff is fully transparent when life reaches zero", alpha_end)
	art.free()


func _mean_travel(puffs: Array[MeshInstance3D]) -> float:
	var total := 0.0
	for puff in puffs:
		total += (puff.position - Vector3(puff.get_meta("origin"))).length()
	return total / puffs.size()


# ------------------------------------------------------------------ real physics manoeuvre
func _test_real_handbrake() -> void:
	GameSession.configure("VEHICLE FEEDBACK", "blackjack", ["ramjet", "boilerfang"])
	var scene: Node3D = ResourceLoader.load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	prepare_track(scene)
	var car: Vehicle = scene.car
	var fx := car.get_node("VehicleEffects") as VehicleEffects
	car.brake = 0.0
	car.throttle = 0.0
	for frame in 90:
		await get_tree().physics_frame
	var loaded := 0
	for wheel: Wheel in car.wheels:
		loaded += int(wheel.contact and wheel.normal_load >= VehicleEffects.MIN_SLIDE_LOAD and VehicleEffects.is_hard_surface(wheel.surface_id))
	_check("player settles on the opening tarmac with every wheel loaded", loaded == car.wheels.size())
	var heading_start := car.forward_vector()
	fx.reset()
	var smoke_start := fx.tyre_smoke_emitted
	var skid_start := fx.skid_emitted
	car.linear_velocity = heading_start.normalized() * 20.0
	car.throttle = 1.0
	car.handbrake = true
	car.steer = 0.6
	var contacts: Array = [[], [], [], []]
	var loaded_frames := 0
	for frame in 60:
		await get_tree().physics_frame
		for index in car.wheels.size():
			var wheel: Wheel = car.wheels[index]
			if wheel.contact and wheel.normal_load >= VehicleEffects.MIN_SLIDE_LOAD and VehicleEffects.is_hard_surface(wheel.surface_id):
				contacts[index].append(wheel.contact_point)
				loaded_frames += 1
	_check("the manoeuvre really turned the car", heading_start.angle_to(car.forward_vector()) > deg_to_rad(2.0))
	_check("wheels stayed loaded on hard ground through the manoeuvre", loaded_frames > 60)
	_check("handbrake manoeuvre emits tyre smoke", fx.tyre_smoke_emitted > smoke_start)
	_check("handbrake manoeuvre lays tyre marks", fx.skid_emitted > skid_start and fx.skid_count() > 0)
	var anchored := true
	var level := true
	for seg: Dictionary in fx.skid_segments():
		var near := false
		for point: Vector3 in contacts[seg.wheel]:
			near = near or point.distance_to(seg.b) < 0.6
		anchored = anchored and near
		level = level and (seg.normal as Vector3).dot(Vector3.UP) > 0.9
	_check("every mark ends on a recorded loaded contact of its own wheel", anchored)
	_check("marks sit on level ground", level)

	# Smoke-screen invariants on the real RaceItems: radius 5, five-second life, owner exemption.
	var items: RaceItems = scene.items
	scene.race.state = RaceDirector.State.RACING
	car.handbrake = false
	car.throttle = 0.0
	car.steer = 0.0
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	items.reset()
	scene.race.state = RaceDirector.State.RACING
	items.grant_item(0, "smoke")
	_check("smoke fires", items.fire(0))
	var smokes := items.hazards.filter(func(h: Dictionary) -> bool: return h["id"] == "smoke")
	_check("smoke deploys a hazard", not smokes.is_empty())
	if not smokes.is_empty():
		var hazard: Dictionary = smokes[0]
		_check("smoke radius is unchanged at 5 and life is five seconds", is_equal_approx(float(hazard["radius"]), 5.0) and is_equal_approx(float(hazard["life"]), 5.0))
		var pos: Vector3 = hazard["pos"]
		var start := pos + Vector3(-20, 0, 0)
		var finish := pos + Vector3(20, 0, 0)
		_check("owner's shots pass through their own smoke", not items._smoke_blocks(start, finish, 0))
		_check("a rival's shots are blocked by the smoke", items._smoke_blocks(start, finish, 1) and items._smoke_blocks(start, finish, -1))
		_check("a ray 6 m clear of the centre is not blocked", not items._smoke_blocks(start + Vector3(0, 0, 6), finish + Vector3(0, 0, 6), 1))
		hazard["life"] = 2.0
		items._tick_active(0, 0.1)
		_check("a stationary owner refreshes the hazard life to 5", is_equal_approx(float(hazard["life"]), 5.0))
	scene.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ cost of a full grid
func _test_full_grid_cost() -> void:
	var cars: Array[Vehicle] = []
	var effects: Array[VehicleEffects] = []
	for index in 3:
		var car := _car(Vector3(index * 40.0, 1, 0))
		cars.append(car)
		effects.append(_effects(car))
	# 45 m/s moves 0.75 m per step, so every wheel lays a strip every step and 10 s overfills the pool inside its lifetime.
	for step in 600:
		for index in 3:
			_drive(cars[index], effects[index], 1, 45.0, 6.0)
	var full := true
	for fx in effects:
		full = full and fx.skid_count() == VehicleEffects.SKID_CAPACITY and fx.skid_emitted > VehicleEffects.SKID_CAPACITY
	_check("synthetic worst case fills all three 2048-strip pools with live marks", full)
	var steps := 240
	var started := Time.get_ticks_usec()
	for step in steps:
		for index in 3:
			_drive(cars[index], effects[index], 1, 45.0, 6.0)
	var drive_ms := float(Time.get_ticks_usec() - started) / 1000.0 / steps
	started = Time.get_ticks_usec()
	var refreshes := 120
	for step in refreshes:
		for fx in effects:
			fx._refresh_skids()
	var refresh_ms := float(Time.get_ticks_usec() - started) / 1000.0 / refreshes
	_check("cost measurements are finite", is_finite(drive_ms) and is_finite(refresh_ms))
	print("VEHICLE_FEEDBACK_PERF: 3 full grids, %.3f ms per 3-car effects step (emitting, refresh every 3rd step), %.3f ms per 3-car skid refresh [%s renderer; headless multimesh writes are not representative]"
		% [drive_ms, refresh_ms, DisplayServer.get_name()])
	for car in cars:
		car.free()


# ------------------------------------------------------------------ shared with the visual QA
## Pauses the scene's controls and CPU drivers and parks the CPU cars out of the way,
## leaving the player alone on the real opening tarmac.
static func prepare_track(scene: Node3D) -> void:
	scene.set_physics_process(false)
	if scene.hud != null:
		scene.hud.hide()
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
		driver.enabled = false
	var slot := 0
	for cpu: Vehicle in scene.cpu_cars:
		cpu.throttle = 0.0
		cpu.brake = 0.0
		cpu.handbrake = false
		cpu.freeze = true
		cpu.collision_layer = 0
		cpu.collision_mask = 0
		cpu.global_position = FAR_PARK + Vector3(slot * 40.0, 0.0, 0.0)
		cpu.visible = false
		slot += 1
	var car: Vehicle = scene.car
	car.throttle = 0.0
	car.brake = 0.0
	car.steer = 0.0
	car.handbrake = false
