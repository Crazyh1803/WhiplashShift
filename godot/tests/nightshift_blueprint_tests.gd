## Authored art must preserve hubs, paint isolation and the factory contract.
extends Node3D

const FACTORY := preload("res://scripts/vehicle_factory.gd")
var _fail := 0
var _pass := 0


func _ready() -> void:
	var spec := VehicleCatalog.get_vehicle("nightshift")
	var car := FACTORY.create(spec)
	car.tuning = TuningProfile.new()
	car.freeze = true
	car.position = Vector3(8.0, 0.62, -13.0)
	car.rotation.y = 0.73
	add_child(car)
	_check("Nightshift loads its dedicated adapter", car.get_script() == load("res://scripts/nightshift_blueprint_vehicle.gd"))
	var model := car.get_node_or_null("VisualRoot/ProductionModel") as Node3D
	_check("Nightshift loads authored production model", model != null)
	if model == null:
		get_tree().quit(1)
		return
	var custom := VehicleCatalog.default_customization("nightshift")
	custom["primary_color"] = "cc2244"
	custom["secondary_color"] = "225588"
	custom["accent_color"] = "ddb344"
	car.apply_customization(custom)
	model = car.get_node("VisualRoot/ProductionModel")
	var expected := {"Nightshift_Paint": Color("cc2244"),
		"Nightshift_Secondary": Color("225588"), "Nightshift_Stripe": Color("ddb344")}
	var found := {}
	var protected_ok := true
	for mesh: MeshInstance3D in car._visual_root.find_children("*", "MeshInstance3D", true, false):
		for surface: int in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if expected.has(source.resource_name):
				found[source.resource_name] = true
				_check("Paint channel applies to %s" % mesh.name,
					mesh.get_active_material(surface).albedo_color.is_equal_approx(expected[source.resource_name]))
			else:
				protected_ok = protected_ok and mesh.get_surface_override_material(surface) == null
	_check("All three authored paint channels exist", found.size() == 3)
	_check("Glass, lamps and hardware retain authored materials", protected_ok)
	var originals := model.find_children("Wheel_*", "MeshInstance3D", true, false)
	_check("Authored wheel parts exist", originals.size() > 4)
	var hidden := true
	for mesh: MeshInstance3D in originals:
		hidden = hidden and not mesh.visible
	_check("Embedded static wheels stay hidden", hidden)
	for wheel: Wheel in car.wheels:
		var assembly := wheel.get_node_or_null("ModularWheelVisual") as Node3D
		_check("%s has an authored assembly" % wheel.name, assembly != null)
		if assembly == null:
			continue
		var expected_count := 0
		for mesh: MeshInstance3D in originals:
			if String(mesh.name).begins_with("Wheel_Coupe_") == (wheel.end == "A") and signf(car.to_local(mesh.global_position).x) == wheel.side:
				expected_count += 1
		_check("%s copies every part exactly once" % wheel.name,
			expected_count > 1 and assembly.get_child_count() == expected_count)
		var tires := assembly.find_children("Wheel_*_Tire_*", "MeshInstance3D", true, false)
		_check("%s has one tire" % wheel.name, tires.size() == 1)
		if tires.size() == 1:
			var tire := tires[0] as MeshInstance3D
			var center := tire.to_global(tire.mesh.get_aabb().get_center())
			_check("%s pivots at its hub after rotated spawn" % wheel.name,
				center.distance_to(assembly.global_position) < 0.005)
		_check("%s occupies its correct end" % wheel.name,
			(car.to_local(assembly.global_position).z < 0.0) == (wheel.end == "A"))
		wheel.steer_angle = 0.3
		wheel._place_visual(0.8)
		_check("%s follows steering and suspension" % wheel.name,
			is_equal_approx(assembly.rotation.y, 0.3)
			and is_equal_approx(assembly.position.y, -0.8 + (0.40 if wheel.end == "A" else 0.43)))
	car._update_axle_visuals()
	for end: String in ["A", "B"]:
		var pair := car._wheel_pair(end)
		var left: Node3D = pair[0].get_node("ModularWheelVisual")
		var right: Node3D = pair[1].get_node("ModularWheelVisual")
		var axle: Node3D = car._axle_visuals[end]
		_check("%s axle follows the authored hubs" % end,
			axle.global_position.distance_to((left.global_position + right.global_position) * 0.5) < 0.00001)
	var counts: Array[int] = []
	for wheel: Wheel in car.wheels:
		counts.append(wheel._visual.get_child_count())
	car.apply_customization(custom)
	for i in car.wheels.size():
		_check("Repeated customization does not duplicate wheel parts", car.wheels[i]._visual.get_child_count() == counts[i])
	car.free()
	GameSession.configure("NIGHTSHIFT", "nightshift", ["nightshift", "deadbolt"])
	var race: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(race)
	await get_tree().physics_frame
	_check("Nightshift constructs as player and CPU", race.car.vehicle_id == "nightshift"
		and race.cpu_drivers.size() == 2 and race.cpu_drivers[0].target.vehicle_id == "nightshift")
	_check("Nightshift player has production artwork", race.car.get_node_or_null("VisualRoot/ProductionModel") != null)
	race.queue_free()
	await get_tree().process_frame
	print("NIGHTSHIFT: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
