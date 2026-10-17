## Shared authored-art checks; scene metadata selects the vehicle.
extends Node3D

const FACTORY := preload("res://scripts/vehicle_factory.gd")
var _fail := 0
var _pass := 0


func _ready() -> void:
	var vehicle_id := String(get_meta("vehicle_id", "nightshift"))
	var label := vehicle_id.capitalize()
	var spec := VehicleCatalog.get_vehicle(vehicle_id)
	var display_radii: Dictionary = spec["visual"].get("display_radius", {"A": 0.40, "B": 0.43})
	var car := FACTORY.create(spec)
	car.tuning = TuningProfile.new()
	car.freeze = true
	car.position = Vector3(8.0, 0.62, -13.0)
	car.rotation.y = 0.73
	add_child(car)
	_check("%s loads its dedicated adapter" % label, car.get_script() == load("res://scripts/%s_blueprint_vehicle.gd" % vehicle_id))
	var model := car.get_node_or_null("VisualRoot/ProductionModel") as Node3D
	_check("%s loads authored production model" % label, model != null)
	if model == null:
		get_tree().quit(1)
		return
	var custom := VehicleCatalog.default_customization(vehicle_id)
	custom["primary_color"] = "cc2244"
	custom["secondary_color"] = "225588"
	custom["accent_color"] = "ddb344"
	car.apply_customization(custom)
	model = car.get_node("VisualRoot/ProductionModel")
	var expected := {"%s_Paint" % label: Color("cc2244"),
		"%s_Secondary" % label: Color("225588"), "%s_Stripe" % label: Color("ddb344")}
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
			var center := assembly.to_local(tire.to_global(tire.mesh.get_aabb().get_center()))
			# Outboard sidewall studs shift the axial bounds, not the spin axis.
			center.x = 0.0
			_check("%s pivots at its hub after rotated spawn" % wheel.name,
				tire.global_position.distance_to(assembly.global_position) < 0.005
				and center.length() < 0.005)
		_check("%s occupies its correct end" % wheel.name,
			(car.to_local(assembly.global_position).z < 0.0) == (wheel.end == "A"))
		if vehicle_id == "boilerfang":
			var low := INF
			var high := -INF
			for mesh: MeshInstance3D in assembly.find_children("*", "MeshInstance3D", true, false):
				for surface in mesh.mesh.get_surface_count():
					var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex: Vector3 in vertices:
						var y := (mesh.transform * vertex).y
						low = minf(low, y)
						high = maxf(high, y)
			_check("%s display radius matches the entire visible wheel" % wheel.name,
				absf((high - low) * 0.5 - float(display_radii[wheel.end])) < 0.005)
			_check("%s frozen wheel meets the ground" % wheel.name,
				absf(assembly.global_position.y + low) < 0.005)
			_check("%s keeps its physical radius and hardpoint" % wheel.name,
				is_equal_approx(wheel.radius, car.tuning.wheel_radius(wheel.end))
				and wheel.position.is_equal_approx(car._wheel_mount(wheel.end, wheel.side)))
		wheel.steer_angle = 0.3
		wheel._place_visual(0.8)
		_check("%s follows steering and suspension" % wheel.name,
			is_equal_approx(assembly.rotation.y, 0.3)
			and is_equal_approx(assembly.position.y, -0.8 + float(display_radii[wheel.end])))
	car._update_axle_visuals()
	for end: String in ["A", "B"]:
		var pair := car._wheel_pair(end)
		var left: Node3D = pair[0].get_node("ModularWheelVisual")
		var right: Node3D = pair[1].get_node("ModularWheelVisual")
		var axle: Node3D = car._axle_visuals[end]
		_check("%s axle follows the authored hubs" % end,
			axle.global_position.distance_to((left.global_position + right.global_position) * 0.5) < 0.00001)
	if vehicle_id == "boilerfang":
		var props := model.find_children("Prop_MidDrive*", "MeshInstance3D", true, false)
		_check("Central drive mechanism remains visible body artwork", props.size() >= 1)
		for prop: MeshInstance3D in props:
			_check("Central drive meshes are visible and stay out of wheel assemblies", prop.visible
				and prop.find_parent("ModularWheelVisual") == null)
	var counts: Array[int] = []
	for wheel: Wheel in car.wheels:
		counts.append(wheel._visual.get_child_count())
	car.apply_customization(custom)
	for i in car.wheels.size():
		_check("Repeated customization does not duplicate wheel parts", car.wheels[i]._visual.get_child_count() == counts[i])
	car.free()
	GameSession.configure(label.to_upper(), vehicle_id, [vehicle_id, "deadbolt"])
	var race: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(race)
	await get_tree().physics_frame
	_check("%s constructs as player and CPU" % label, race.car.vehicle_id == vehicle_id
		and race.cpu_drivers.size() == 2 and race.cpu_drivers[0].target.vehicle_id == vehicle_id)
	_check("%s player has production artwork" % label, race.car.get_node_or_null("VisualRoot/ProductionModel") != null)
	race.queue_free()
	await get_tree().process_frame
	print("%s: %d passed, %d failed" % [label.to_upper(), _pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
