## Effluent sheets, spray and motion-driven plowing reuse the gameplay fixture.
extends "res://tests/viscera_response_tests.gd"


func _ready() -> void:
	_test_effluent()
	await _test_effluent_recovery()
	if "--capture" in OS.get_cmdline_user_args():
		await _captures(Surfaces.Id.WATER, "reactor-effluent-response")
	print("EFFLUENT_RESPONSE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _water_wheels() -> Array:
	var wheels := _wheels()
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.WATER
	return wheels


func _test_effluent() -> void:
	var wheels := _water_wheels()
	var right := VisceraResponse.response(wheels, "B", 10, 1)
	var wrong := VisceraResponse.response(wheels, "A", 10, 1)
	_check("wrong A has much stronger spray and drag pose", wrong.water_wrong and not right.water_wrong
		and wrong.water_rate > right.water_rate * 4 and wrong.wash > right.wash * 5
		and wrong.water_sink >= right.water_sink * 4.99 and wrong.water_pitch > right.water_pitch * 5)
	_check("effluent avoids dry rattle armor kicks and ice skid", wrong.rattle == 0 and wrong.impact == 0 and wrong.skid == 0)
	var still := VisceraResponse.response(wheels, "A", 0, 1)
	_check("standing liquid contact has no invented spray or plowing", still.water_rate == 0 and still.wash == 0 and still.water_sink == 0 and still.water_pitch == 0)
	wheels[0].spin = 1
	_check("water wheelspin can churn liquid when bogged", VisceraResponse.response(wheels, "A", 0, 1).water_rate > 0)
	wheels[0].surface_id = Surfaces.Id.ICE
	_check("neighboring ice wheelspin cannot churn stationary water", VisceraResponse.response(wheels, "A", 0, 1).water_rate == 0)
	wheels[0].surface_id = Surfaces.Id.WATER
	wheels[0].spin = 0
	for wheel: Wheel in wheels:
		wheel.contact = false
	_check("airborne water cannot produce a drag pose", VisceraResponse.response(wheels, "A", 10, 1).wash == 0)
	for wheel: Wheel in wheels:
		wheel.contact = true
	var car := Vehicle.new()
	car.freeze = true
	add_child(car)
	var fx: VisceraResponse = car.get_node("VisceraResponse")
	fx.set_process(false)
	var visual: Node3D = car.get_node("VisualRoot")
	var original := car.transform
	var mounts: Array[Transform3D] = []
	for wheel: Wheel in car.wheels:
		mounts.append(wheel.transform)
	var collider: Node3D = car.get_child(0)
	var collision_transform := collider.transform
	var seen := 0
	var bounded := true
	for frame in 240:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
		var total := 0
		for kind in VisceraResponse.FRAGMENT_NAMES.size():
			var count: int = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count
			total += count
			if count > 0:
				seen |= 1 << kind
		bounded = bounded and total == fx.active_count and total <= VisceraResponse.CAPACITY
	_check("water exclusively emits sheets and droplets within shared pool", seen == 3072 and bounded)
	_check("wrong A plows nose down with bounded immersion", fx.wash > 0.99 and fx.sink > 0.074 and fx.sink <= 0.07501
		and visual.position.y > -0.082 and visual.position.y < -0.068
		and visual.rotation.x < -0.04 and visual.rotation.x > -0.043)
	_check("liquid re-entry never bounces like solid fragments", fx.bounced_total == 0)
	var sheet_batch: MultiMesh = fx.get_node("ThrownEffluentSheets").multimesh
	var spreading := false
	for i in sheet_batch.visible_instance_count:
		var scale := sheet_batch.get_instance_transform(i).basis.get_scale()
		spreading = spreading or scale.x > scale.y * 1.2
	if DisplayServer.get_name() != "headless":
		_check("liquid sheets spread and flatten during flight", spreading)
	else:
		print("  SKIP: sheet spread requires GPU MultiMesh transform readback")
	var untouched := car.transform == original and collider.transform == collision_transform
	for i in car.wheels.size():
		untouched = untouched and car.wheels[i].transform == mounts[i]
	_check("plowing never writes physical body velocity collider or wheels", untouched and car.linear_velocity == Vector3.ZERO and car.angular_velocity == Vector3.ZERO)
	_check("effluent adds no collision geometry", fx.find_children("*", "CollisionObject3D", true, false).is_empty())
	for kind in [10, 11]:
		var batch: MultiMeshInstance3D = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind])
		var faces := batch.multimesh.mesh.get_faces()
		var valid := faces.size() > 0 and faces.size() <= 480
		for i in range(0, faces.size(), 3):
			valid = valid and faces[i].is_finite() and (faces[i+1] - faces[i]).cross(faces[i+2] - faces[i]).length_squared() > 0.000001
		_check("effluent mesh %d has bounded wet geometry without emission" % kind, valid
			and batch.material_override.roughness < 0.2 and batch.material_override.clearcoat_enabled
			and not batch.material_override.emission_enabled)
	var sheet_bounds := fx.get_node("ThrownEffluentSheets").multimesh.mesh.get_aabb().size as Vector3
	var drop_bounds := fx.get_node("ThrownEffluentDroplets").multimesh.mesh.get_aabb().size as Vector3
	_check("torn sheets and stretched droplets have distinct silhouettes", sheet_bounds.x > sheet_bounds.y * 2 and drop_bounds.y > drop_bounds.x * 3)
	for wheel: Wheel in wheels:
		wheel.contact = false
	var emitted := fx.emitted_total
	for frame in 180:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	_check("airborne transition stops spray and clears pose", fx.active_count == 0 and fx.emitted_total == emitted and fx.wash < 0.0001 and visual.position.length() < 0.0001)
	for wheel: Wheel in wheels:
		wheel.contact = true
	fx.reset_effect()
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	_check("correct B has shallow immersion and reverse-end nose pitch", fx.sink > 0.014 and fx.sink < 0.016 and visual.rotation.x > 0.006 and visual.rotation.x < 0.008)
	fx.reset_effect()
	wheels[0].surface_id = Surfaces.Id.MUD
	wheels[1].surface_id = Surfaces.Id.GRAVEL
	wheels[2].surface_id = Surfaces.Id.ICE
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "A", Vector3(3, 0, -10), 1, Basis.IDENTITY)
	_check("mixed seams blend liquid mud gravel and ice in one pose", fx.wash > 0.24 and fx.wash < 0.26
		and fx.sink > 0.04 and fx.sink < 0.06 and fx.rattle > 0 and fx.skid > 0)
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.TARMAC
	emitted = fx.emitted_total
	for frame in 180:
		fx.advance(1.0 / 60, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	_check("leaving effluent clears spray and restores the body", fx.active_count == 0 and fx.emitted_total == emitted
		and fx.wash < 0.0001 and visual.position.length() < 0.0001 and visual.rotation.length() < 0.0001)
	for wheel: Wheel in wheels:
		wheel.free()
	car.free()


func _test_effluent_recovery() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	var wheels := _water_wheels()
	var fx: VisceraResponse = scene.car.get_node("VisceraResponse")
	fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene._place_player(scene._spawn, "A")
	_check("player recovery clears liquid drag and spray", fx.wash == 0 and fx.sink == 0 and fx.active_count == 0)
	var cpu_fx: VisceraResponse = scene.cpu_cars[0].get_node("VisceraResponse")
	cpu_fx.advance(0.05, wheels, "A", Vector3(0, 0, -10), 1, Basis.IDENTITY)
	scene.cpu_drivers[0].reset(scene._grid_indices[1])
	_check("CPU recovery clears liquid drag and spray", cpu_fx.wash == 0 and cpu_fx.sink == 0 and cpu_fx.active_count == 0)
	for wheel: Wheel in wheels:
		wheel.free()
	scene.queue_free()
	for frame in 3:
		await get_tree().process_frame
