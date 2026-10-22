## Rubble-specific contracts reuse the exact gameplay capture/lifecycle fixture.
extends "res://tests/viscera_response_tests.gd"


func _ready() -> void:
	_test_rubble_policy()
	_test_rubble_pool_and_pose()
	await _test_rubble_recovery()
	if "--capture" in OS.get_cmdline_user_args():
		await _captures(Surfaces.Id.GRAVEL, "chitin-rubble-response")
	print("RUBBLE_RESPONSE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _rubble_wheels() -> Array:
	var wheels := _wheels()
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.GRAVEL
	return wheels


func _test_rubble_policy() -> void:
	var wheels := _rubble_wheels()
	var right := VisceraResponse.response(wheels, "B", 10, 1)
	var wrong := VisceraResponse.response(wheels, "A", 10, 1)
	_check("wrong end has stronger rubble spray and chassis response", wrong.rubble_rate > right.rubble_rate * 2
		and wrong.rattle > right.rattle * 5 and wrong.rubble_power > right.rubble_power * 2)
	_check("rubble rattles without viscera sinking", wrong.rattle > 0 and wrong.sink == 0 and wrong.wet == 0)
	var stationary := VisceraResponse.response(wheels, "A", 0, 1)
	_check("stationary unspinning rubble has no spray or rattle", stationary.rubble_rate == 0 and stationary.rattle == 0)
	wheels[0].spin = 1.0
	_check("wheelspin can scatter rubble when bogged", VisceraResponse.response(wheels, "A", 0, 1).rubble_rate > 0)
	for wheel: Wheel in wheels:
		wheel.contact = false
	_check("airborne contact cannot trigger chassis rattle", VisceraResponse.response(wheels, "A", 10, 1).rattle == 0)
	for wheel: Wheel in wheels:
		wheel.free()


func _test_rubble_pool_and_pose() -> void:
	var car := Vehicle.new()
	car.freeze = true
	add_child(car)
	var fx: VisceraResponse = car.get_node("VisceraResponse")
	fx.set_process(false)
	var wheels := _rubble_wheels()
	var body_transform := car.transform
	var physical: Array[Transform3D] = []
	for wheel: Wheel in car.wheels:
		physical.append(wheel.transform)
	var collider: Node3D = car.get_child(0)
	var collider_transform := collider.transform
	var visual: Node3D = car.get_node("VisualRoot")
	var kinds_seen := 0
	var max_heave := 0.0
	var max_angle := 0.0
	var previous_heave := 0.0
	var max_heave_step := 0.0
	for frame in 360:
		fx.advance(1.0 / 60.0, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
		max_heave_step = maxf(max_heave_step, absf(visual.position.y - previous_heave))
		previous_heave = visual.position.y
		max_heave = maxf(max_heave, absf(visual.position.y))
		max_angle = maxf(max_angle, visual.rotation.length())
		for kind in 6:
			if fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count > 0:
				kinds_seen |= 1 << kind
	_check("all dry debris kinds emit without organic fragments", kinds_seen == 56)
	var total := 0
	var dry_material := true
	for kind in 6:
		var batch: MultiMeshInstance3D = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind])
		total += batch.multimesh.visible_instance_count
		if kind >= 3:
			dry_material = dry_material and not batch.material_override.emission_enabled and batch.material_override.roughness > 0.65
	_check("six batches share one bounded live pool", total == fx.active_count and total > 0 and total <= VisceraResponse.CAPACITY)
	_check("rubble is dry rather than wet or glowing", dry_material)
	_check("rubble pieces have a bounded ground bounce", fx.bounced_total > 0)
	_check("wrong-end chassis shudder is visible but bounded", max_heave > 0.01 and max_heave < 0.023 and max_angle > 0.005 and max_angle < deg_to_rad(1.2))
	_check("chassis rattle stays continuous across oscillation cycles", max_heave_step < 0.012)
	var untouched := car.transform == body_transform and collider.transform == collider_transform
	for index in car.wheels.size():
		untouched = untouched and car.wheels[index].transform == physical[index]
	_check("shudder never moves physical body, collider or wheel mounts", untouched
		and car.linear_velocity == Vector3.ZERO and car.angular_velocity == Vector3.ZERO)
	_check("rubble never adds collision objects", fx.find_children("*", "CollisionObject3D", true, false).is_empty())
	fx.reset_effect()
	wheels[0].surface_id = Surfaces.Id.MUD
	wheels[1].surface_id = Surfaces.Id.MUD
	for frame in 120:
		fx.advance(1.0 / 60.0, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	var wet_live := 0
	var dry_live := 0
	for kind in 6:
		var count: int = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count
		if kind < 3:
			wet_live += count
		else:
			dry_live += count
	_check("mixed seams emit the debris belonging to each tyre contact", wet_live > 0 and dry_live > 0
		and wet_live + dry_live == fx.active_count and fx.active_count <= VisceraResponse.CAPACITY)
	_check("mixed seams blend one body pose without competing controllers", fx.sink > 0.04 and fx.sink < 0.07 and fx.rattle > 0.3 and fx.rattle < 0.5)
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.TARMAC
	var emitted := fx.emitted_total
	for frame in 180:
		fx.advance(1.0 / 60.0, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	_check("leaving rubble stops emission and restores the body", fx.emitted_total == emitted and fx.active_count == 0
		and fx.rattle < 0.0001 and visual.position.length() < 0.0001 and visual.rotation.length() < 0.0001)
	for wheel: Wheel in wheels:
		wheel.free()
	car.free()


func _test_rubble_recovery() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	var wheels := _rubble_wheels()
	var fx: VisceraResponse = scene.car.get_node("VisceraResponse")
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene._place_player(scene._spawn, "A")
	_check("player recovery clears rubble and rattle immediately", fx.active_count == 0 and fx.rattle == 0)
	var cpu_fx: VisceraResponse = scene.cpu_cars[0].get_node("VisceraResponse")
	cpu_fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene.cpu_drivers[0].reset(scene._grid_indices[1])
	_check("CPU recovery clears rubble and rattle immediately", cpu_fx.active_count == 0 and cpu_fx.rattle == 0)
	scene.restart_race()
	_check("retry keeps one combined response controller per car", scene.car.find_children("VisceraResponse", "Node3D", false, false).size() == 1)
	for wheel: Wheel in wheels:
		wheel.free()
	scene.queue_free()
	for frame in 3:
		await get_tree().process_frame
