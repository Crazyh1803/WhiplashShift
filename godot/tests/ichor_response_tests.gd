## Oil strands and measured lateral slip use the production contact fixture.
extends "res://tests/viscera_response_tests.gd"


func _ready() -> void:
	_test_ichor()
	await _test_ichor_recovery()
	if "--capture" in OS.get_cmdline_user_args():
		await _captures(Surfaces.Id.OIL, "black-ichor-response")
	print("ICHOR_RESPONSE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _oil_wheels() -> Array:
	var wheels := _wheels()
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.OIL
		wheel.slip = 0.9
	return wheels


func _test_ichor() -> void:
	var wheels := _oil_wheels()
	var right := VisceraResponse.response(wheels, "A", 10, 1, 2.5)
	var wrong := VisceraResponse.response(wheels, "B", 10, 1, 2.5)
	_check("wrong B has stronger oil spray and lateral slip pose", wrong.oil_wrong and not right.oil_wrong
		and wrong.oil_rate > right.oil_rate * 2 and wrong.oil_slide > right.oil_slide * 7)
	_check("oil does not sink rattle kick or wash like other surfaces", wrong.sink == 0 and wrong.water_sink == 0
		and wrong.rattle == 0 and wrong.impact == 0 and wrong.wash == 0 and wrong.skid == 0)
	_check("oil slip follows measured slide direction", VisceraResponse.response(wheels, "B", 10, 1, -2.5).oil_slide == -wrong.oil_slide)
	_check("straight rolling cannot invent sideways motion", VisceraResponse.response(wheels, "B", 10, 1).oil_slide == 0)
	var still := VisceraResponse.response(wheels, "B", 0, 1)
	_check("stationary unspinning oil has no spray or slide", still.oil_rate == 0 and still.oil_slide == 0)
	wheels[0].spin = 1
	_check("oil wheelspin throws spray without fake lateral slide", VisceraResponse.response(wheels, "B", 0, 1).oil_rate > 0
		and VisceraResponse.response(wheels, "B", 0, 1).oil_slide == 0)
	wheels[0].surface_id = Surfaces.Id.WATER
	_check("neighboring water wheelspin cannot trigger stationary oil", VisceraResponse.response(wheels, "B", 0, 1).oil_rate == 0)
	wheels[0].surface_id = Surfaces.Id.OIL
	wheels[0].spin = 0
	for wheel: Wheel in wheels:
		wheel.contact = false
	_check("airborne oil cannot produce slip pose", VisceraResponse.response(wheels, "B", 10, 1, 2.5).oil_slide == 0)
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
		fx.advance(1.0 / 60, wheels, "B", Vector3(2.5, 0, -10), 1, Basis.IDENTITY)
		var total := 0
		for kind in VisceraResponse.FRAGMENT_NAMES.size():
			var count: int = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count
			total += count
			if count > 0:
				seen |= 1 << kind
		bounded = bounded and total == fx.active_count and total <= VisceraResponse.CAPACITY
	_check("oil exclusively emits strands and drops within shared pool", seen == 12288 and bounded)
	_check("wrong B has visible bounded yaw and roll without sinking", visual.rotation.y > 0.06 and visual.rotation.y < 0.071
		and absf(visual.rotation.z) < 0.019 and visual.position == Vector3.ZERO)
	_check("oil re-entry never bounces like solid fragments", fx.bounced_total == 0)
	var strands: MultiMesh = fx.get_node("ThrownIchorStrands").multimesh
	var stretched := false
	for i in strands.visible_instance_count:
		var shape := strands.get_instance_transform(i).basis
		var scale := shape.get_scale()
		stretched = stretched or scale.z > scale.x * 1.2
	if DisplayServer.get_name() != "headless":
		_check("oil strands stretch thin during flight", stretched)
	else:
		print("  SKIP: strand stretch requires GPU MultiMesh transform readback")
	var untouched := car.transform == original and collider.transform == collision_transform
	for i in car.wheels.size():
		untouched = untouched and car.wheels[i].transform == mounts[i]
	_check("oil pose never writes physical body velocity collider or wheels", untouched and car.linear_velocity == Vector3.ZERO and car.angular_velocity == Vector3.ZERO)
	_check("oil adds no collision geometry", fx.find_children("*", "CollisionObject3D", true, false).is_empty())
	for kind in [12, 13]:
		var batch: MultiMeshInstance3D = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind])
		var faces := batch.multimesh.mesh.get_faces()
		var valid := faces.size() > 0 and faces.size() <= 480
		for i in range(0, faces.size(), 3):
			valid = valid and faces[i].is_finite() and (faces[i+1] - faces[i]).cross(faces[i+2] - faces[i]).length_squared() > 0.0000000001
		_check("oil mesh %d is finite glossy opaque and non-emissive" % kind, valid and batch.material_override.roughness < 0.1
			and batch.material_override.clearcoat_enabled and not batch.material_override.emission_enabled
			and batch.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	var bounds := strands.mesh.get_aabb().size
	_check("oil strands have a thin elongated silhouette", bounds.z > bounds.x * 4)
	fx.reset_effect()
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", Vector3(-2.5, 0, -10), 1, Basis.IDENTITY)
	_check("oil pose reverses with actual slide", fx.oil_slide < -0.99 and visual.rotation.y < -0.06)
	fx.reset_effect()
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "A", Vector3(2.5, 0, -10), 1, Basis.IDENTITY)
	_check("correct A has a small signed slip pose", visual.rotation.y < -0.008 and visual.rotation.y > -0.011)
	fx.reset_effect()
	var turned := Basis(Vector3.UP, PI / 2)
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", turned * Vector3(0, 0, -10), 1, turned)
	_check("oil slide uses body-local velocity after turning", absf(fx.oil_slide) < 0.0001 and absf(visual.rotation.y) < 0.0001)
	fx.reset_effect()
	wheels[0].surface_id = Surfaces.Id.MUD
	wheels[1].surface_id = Surfaces.Id.ICE
	wheels[2].surface_id = Surfaces.Id.WATER
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", Vector3(2.5, 0, -10), 1, Basis.IDENTITY)
	_check("mixed seam blends oil ice mud and water in one pose", fx.oil_slide > 0.24 and fx.oil_slide < 0.26
		and fx.skid > 0 and fx.sink > 0 and fx.wash > 0)
	for wheel: Wheel in wheels:
		wheel.contact = false
	var emitted := fx.emitted_total
	for frame in 180:
		fx.advance(1.0 / 60, wheels, "B", Vector3(2.5, 0, -10), 1, Basis.IDENTITY)
	_check("airborne transition stops spray and restores pose", fx.active_count == 0 and fx.emitted_total == emitted
		and absf(fx.oil_slide) < 0.0001 and visual.position.length() < 0.0001 and visual.rotation.length() < 0.0001)
	for wheel: Wheel in wheels:
		wheel.contact = true
		wheel.surface_id = Surfaces.Id.TARMAC
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", Vector3(2.5, 0, -10), 1, Basis.IDENTITY)
	_check("dry road cannot emit ichor or invent lateral pose", fx.emitted_total == emitted and fx.active_count == 0 and absf(fx.oil_slide) < 0.0001)
	for wheel: Wheel in wheels:
		wheel.free()
	car.free()


func _test_ichor_recovery() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	var wheels := _oil_wheels()
	var fx: VisceraResponse = scene.car.get_node("VisceraResponse")
	fx.advance(0.05, wheels, "B", Vector3(2.5, 0, -10), 1, Basis.IDENTITY)
	scene._place_player(scene._spawn, "B")
	_check("player recovery clears oil slip and spray", fx.oil_slide == 0 and fx.active_count == 0)
	var cpu_fx: VisceraResponse = scene.cpu_cars[0].get_node("VisceraResponse")
	cpu_fx.advance(0.05, wheels, "B", Vector3(2.5, 0, -10), 1, Basis.IDENTITY)
	scene.cpu_drivers[0].reset(scene._grid_indices[1])
	_check("CPU recovery clears oil slip and spray", cpu_fx.oil_slide == 0 and cpu_fx.active_count == 0)
	for wheel: Wheel in wheels:
		wheel.free()
	scene.queue_free()
	for frame in 3:
		await get_tree().process_frame
