## Coolant flakes and cosmetic skid follow actual contact and lateral motion.
extends "res://tests/viscera_response_tests.gd"


func _ready() -> void:
	_test_coolant()
	await _test_coolant_recovery()
	if "--capture" in OS.get_cmdline_user_args():
		await _captures(Surfaces.Id.ICE, "coolant-ice-response")
	print("COOLANT_RESPONSE: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _ice_wheels() -> Array:
	var wheels := _wheels()
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.ICE
		wheel.slip = 0.9
	return wheels


func _test_coolant() -> void:
	var wheels := _ice_wheels()
	var right := VisceraResponse.response(wheels, "A", 10, 1, 3)
	var wrong := VisceraResponse.response(wheels, "B", 10, 1, 3)
	_check("wrong B has stronger shard spray and skid response", wrong.ice_wrong and not right.ice_wrong
		and wrong.ice_rate > right.ice_rate * 2 and wrong.skid >= right.skid * 4.99)
	_check("coolant has no dry rattle armor kick or mud sinking", wrong.sink == 0 and wrong.rattle == 0 and wrong.impact == 0)
	_check("skid changes sign with actual lateral motion", VisceraResponse.response(wheels, "B", 10, 1, -3).skid == -wrong.skid)
	_check("straight rolling has no invented lateral wobble", VisceraResponse.response(wheels, "B", 10, 1, 0).skid == 0)
	var still := VisceraResponse.response(wheels, "B", 0, 1, 0)
	_check("stationary unspinning coolant has no spray or skid", still.ice_rate == 0 and still.skid == 0)
	wheels[0].spin = 1
	_check("stationary wheelspin scatters frost without fake slide", VisceraResponse.response(wheels, "B", 0, 1).ice_rate > 0
		and VisceraResponse.response(wheels, "B", 0, 1).skid == 0)
	wheels[0].spin = 0
	for wheel: Wheel in wheels:
		wheel.contact = false
	_check("airborne contact cannot produce skid", VisceraResponse.response(wheels, "B", 10, 1, 3).skid == 0)
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
	var budget_ok := true
	for frame in 240:
		fx.advance(1.0 / 60, wheels, "B", Vector3(3, 0, -10), 1, Basis.IDENTITY)
		var total := 0
		for kind in VisceraResponse.FRAGMENT_NAMES.size():
			var count: int = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind]).multimesh.visible_instance_count
			total += count
			if count > 0:
				seen |= 1 << kind
		budget_ok = budget_ok and total == fx.active_count and total <= VisceraResponse.CAPACITY
	_check("coolant exclusively emits flakes and splinters within shared pool", seen == 768 and budget_ok)
	_check("wrong B skid pose is visible and bounded without sinking", visual.rotation.y > 0.04 and visual.rotation.y < 0.056
		and absf(visual.rotation.z) < 0.013 and visual.position == Vector3.ZERO)
	var untouched := car.transform == original and collider.transform == collision_transform
	for i in car.wheels.size():
		untouched = untouched and car.wheels[i].transform == mounts[i]
	_check("skid leaves physical body velocity collider and wheel mounts intact", untouched and car.linear_velocity == Vector3.ZERO and car.angular_velocity == Vector3.ZERO)
	_check("coolant never creates collision objects", fx.find_children("*", "CollisionObject3D", true, false).is_empty())
	for kind in [8, 9]:
		var batch: MultiMeshInstance3D = fx.get_node(VisceraResponse.FRAGMENT_NAMES[kind])
		var vertices: PackedVector3Array = batch.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var valid := vertices.size() > 0 and vertices.size() <= 480
		for i in range(0, vertices.size(), 3):
			valid = valid and vertices[i].is_finite() and (vertices[i+1] - vertices[i]).cross(vertices[i+2] - vertices[i]).length_squared() > 0.000001
		var bounds := batch.multimesh.mesh.get_aabb().size
		_check("coolant mesh %d is thin faceted and opaque without glow" % kind, valid and bounds.y < bounds.z * 0.1
			and batch.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and not batch.material_override.emission_enabled and batch.material_override.roughness < 0.4)
	fx.reset_effect()
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", Vector3(-3, 0, -10), 1, Basis.IDENTITY)
	_check("body skid reverses smoothly with slide direction", visual.rotation.y < -0.04 and fx.skid < -0.9)
	fx.reset_effect()
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "A", Vector3(3, 0, -10), 1, Basis.IDENTITY)
	_check("correct A keeps a small signed response", absf(visual.rotation.y) > 0.005 and absf(visual.rotation.y) < 0.012)
	fx.reset_effect()
	# A rotated body moving along its own forward axis must not look sideways.
	var turned := Basis(Vector3.UP, PI / 2)
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", turned * Vector3(0, 0, -10), 1, turned)
	_check("skid uses body-local velocity after turning", absf(fx.skid) < 0.0001 and absf(visual.rotation.y) < 0.0001)
	fx.reset_effect()
	wheels[0].surface_id = Surfaces.Id.MUD
	wheels[1].surface_id = Surfaces.Id.GRAVEL
	wheels[2].surface_id = Surfaces.Id.BOULDER
	for frame in 120:
		fx.advance(1.0 / 60, wheels, "B", Vector3(3, 0, -10), 1, Basis.IDENTITY)
	_check("mixed seam combines four responses in one body pose", fx.skid > 0.2 and fx.skid < 0.3 and fx.sink > 0 and fx.rattle > 0 and fx.impact > 0)
	for wheel: Wheel in wheels:
		wheel.surface_id = Surfaces.Id.TARMAC
	var emitted := fx.emitted_total
	for frame in 180:
		fx.advance(1.0 / 60, wheels, "B", Vector3(3, 0, -10), 1, Basis.IDENTITY)
	_check("leaving coolant stops spray and restores original pose", fx.emitted_total == emitted and fx.active_count == 0
		and absf(fx.skid) < 0.0001 and visual.position.length() < 0.0001 and visual.rotation.length() < 0.0001)
	for wheel: Wheel in wheels:
		wheel.free()
	car.free()


func _test_coolant_recovery() -> void:
	var scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	var wheels := _ice_wheels()
	var fx: VisceraResponse = scene.car.get_node("VisceraResponse")
	fx.advance(0.05, wheels, "B", Vector3(3, 0, -10), 1, Basis.IDENTITY)
	scene._place_player(scene._spawn, "B")
	_check("player recovery clears skid and flakes", fx.skid == 0 and fx.active_count == 0)
	var cpu_fx: VisceraResponse = scene.cpu_cars[0].get_node("VisceraResponse")
	cpu_fx.advance(0.05, wheels, "B", Vector3(3, 0, -10), 1, Basis.IDENTITY)
	scene.cpu_drivers[0].reset(scene._grid_indices[1])
	_check("CPU recovery clears skid and flakes", cpu_fx.skid == 0 and cpu_fx.active_count == 0)
	for wheel: Wheel in wheels:
		wheel.free()
	scene.queue_free()
	for frame in 3:
		await get_tree().process_frame
