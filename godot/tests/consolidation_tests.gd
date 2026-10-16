extends Node3D

const FACTORY := preload("res://scripts/vehicle_factory.gd")
var _pass := 0
var _fail := 0


func _ready() -> void:
	# All seven saved designs must still construct through the actual game factory.
	for entry: Dictionary in VehicleCatalog.VEHICLES:
		var spec := VehicleCatalog.get_vehicle(entry["id"])
		_check("%s reference survives consolidation" % entry["id"], ResourceLoader.exists(entry["image"]))
		var car := FACTORY.create(spec)
		car.tuning = TuningProfile.new()
		car.freeze = true
		add_child(car)
		_check("%s constructs four physical wheels" % entry["id"], car.wheels.size() == 4)
		if entry["id"] == "deadbolt":
			_test_deadbolt_art(car)
			var custom := VehicleCatalog.default_customization("deadbolt")
			custom["primary_color"] = "cc2244"
			custom["secondary_color"] = "225588"
			custom["accent_color"] = "ddb344"
			car.apply_customization(custom)
			_test_deadbolt_art(car)
			var expected_paint := {
				"Deadbolt_Paint": Color("cc2244"),
				"Deadbolt_Secondary": Color("225588"),
				"Deadbolt_Stripe": Color("ddb344"),
			}
			var paint_ok := {"Deadbolt_Paint": false, "Deadbolt_Secondary": false, "Deadbolt_Stripe": false}
			var protected_ok := true
			for mesh: MeshInstance3D in car._visual_root.find_children("*", "MeshInstance3D", true, false):
				for surface: int in mesh.mesh.get_surface_count():
					var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
					if expected_paint.has(source.resource_name):
						paint_ok[source.resource_name] = mesh.get_active_material(surface).albedo_color.is_equal_approx(expected_paint[source.resource_name])
					else:
						protected_ok = protected_ok and mesh.get_surface_override_material(surface) == null
			for channel: String in paint_ok:
				_check("%s paint changes" % channel, paint_ok[channel])
			_check("Deadbolt glass and hardware retain authored materials", protected_ok)
		car.free()
	await _test_deadbolt_physics()
	await _test_garage_and_race()
	print("CONSOLIDATION: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_deadbolt_art(car: Vehicle) -> void:
	var model := car.get_node_or_null("VisualRoot/ProductionModel")
	_check("Deadbolt loads the saved production mesh", model != null)
	var coupe_is_forward := true
	var original_wheels_hidden := true
	for mesh: MeshInstance3D in model.find_children("Wheel_*", "MeshInstance3D", true, false):
		original_wheels_hidden = original_wheels_hidden and not mesh.visible
		if String(mesh.name).begins_with("Wheel_Coupe_"):
			coupe_is_forward = coupe_is_forward and car.to_local(mesh.global_position).z < 0.0
	_check("Deadbolt coupe faces End A", coupe_is_forward)
	_check("Deadbolt embedded wheel copies are hidden", original_wheels_hidden)
	for wheel: Wheel in car.wheels:
		var assembly := wheel.get_node("ModularWheelVisual")
		var expected := 13 if wheel.end == "A" else 9
		_check("%s has exactly one complete authored wheel" % wheel.name, assembly.get_child_count() == expected)
		wheel.steer_angle = 0.25
		wheel._place_visual(0.8)
		_check("%s art follows suspension and steering" % wheel.name,
			is_equal_approx(assembly.rotation.y, 0.25)
			and is_equal_approx(assembly.position.y, -0.8 + (0.40 if wheel.end == "A" else 0.43)))
	car._update_axle_visuals()
	for end: String in ["A", "B"]:
		var pair := car._wheel_pair(end)
		var left: Node3D = pair[0].get_node("ModularWheelVisual")
		var right: Node3D = pair[1].get_node("ModularWheelVisual")
		var axle: Node3D = car._axle_visuals[end]
		_check("%s axle follows the authored wheel hubs" % end,
			axle.global_position.distance_to((left.global_position + right.global_position) * 0.5) < 0.00001)


func _test_deadbolt_physics() -> void:
	# Independent identical worlds at identical coordinates avoid collision/precision differences.
	var worlds: Array[SubViewport] = []
	var cars: Array[Vehicle] = []
	for imported: bool in [true, false]:
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		add_child(viewport)
		worlds.append(viewport)
		var ground := StaticBody3D.new()
		ground.set_meta("surface_type", "tarmac")
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(100, 1, 2000)
		collision.shape = box
		collision.position.y = -0.5
		ground.add_child(collision)
		viewport.add_child(ground)
		var spec := VehicleCatalog.get_vehicle("deadbolt")
		if not imported:
			spec["visual"]["scene"] = ""
			spec["visual"]["rig"] = ""
		var car := FACTORY.create(spec)
		car.tuning = TuningProfile.new()
		car.position = Vector3(5, 1.4, 10)
		viewport.add_child(car)
		cars.append(car)
	var parity := true
	for tick in 840:
		for car: Vehicle in cars:
			car.throttle = 0.7 if tick >= 240 else 0.0
			car.brake = 0.5 if tick >= 720 else 0.0
			if tick == 600:
				var velocity := car.linear_velocity
				var angular := car.angular_velocity
				var basis_before := car.basis
				car.swap_ends()
				_check("Deadbolt swap preserves momentum and orientation",
					car.linear_velocity == velocity and car.angular_velocity == angular and car.basis == basis_before)
		await get_tree().physics_frame
		parity = parity and cars[0].position.distance_to(cars[1].position) < 0.00001
		parity = parity and cars[0].linear_velocity.distance_to(cars[1].linear_velocity) < 0.00001
	_check("Deadbolt artwork preserves driving/braking/swap physics", parity)
	_check("Deadbolt accelerates with the saved handling", cars[0].speed > 1.0)
	for viewport: SubViewport in worlds:
		viewport.queue_free()
	await get_tree().process_frame


func _test_garage_and_race() -> void:
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	for frame in 2:
		await get_tree().process_frame
	var controls_fit := true
	var visible := get_viewport().get_visible_rect()
	for button: Button in garage._roster_buttons:
		controls_fit = controls_fit and visible.encloses(button.get_global_rect())
	controls_fit = controls_fit and visible.encloses(garage._next_button.get_global_rect())
	controls_fit = controls_fit and visible.encloses(garage._prev_button.get_global_rect())
	controls_fit = controls_fit and visible.encloses(garage._start_button.get_global_rect())
	controls_fit = controls_fit and visible.encloses(garage._dossier_panel.get_global_rect())
	_check("All named vehicle and ignition buttons fit the garage", controls_fit)
	if not controls_fit:
		print("LAYOUT_DEBUG viewport=", visible, " image=", garage._image_panel.get_global_rect(),
			" image_min=", garage._image_panel.custom_minimum_size,
			" dossier=", garage._dossier_panel.get_global_rect(),
			" last=", garage._roster_buttons[-1].get_global_rect(),
			" next=", garage._next_button.get_global_rect(), " ignite=", garage._start_button.get_global_rect())
	_check("Garage exposes seven named vehicle buttons", garage._roster_buttons.size() == 7
		and garage._roster_buttons[5].text == "DEADBOLT")
	garage._roster_buttons[5].pressed.emit()
	_check("Deadbolt button selects the chassis directly", garage._index == 5
		and garage._name_label.text == "DEADBOLT RS" and garage._roster_buttons[5].button_pressed)
	garage._open_customization()
	_check("Customize opens the selected Deadbolt model", garage._preview_vehicle.vehicle_id == "deadbolt")
	garage._customization_popup.hide()
	for id: String in ["blackjack", "deadbolt", "nightshift", "deadbolt"]:
		garage._refresh_customization_preview(id, VehicleCatalog.default_customization(id))
		_check("Garage preview switches to %s" % id, garage._preview_vehicle.vehicle_id == id)
	garage.free()
	GameSession.configure("CONSOLIDATION", "deadbolt", ["blackjack", "nightshift"])
	garage = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	_check("Returning from a Deadbolt race keeps Deadbolt selected", garage._index == 5)
	garage.free()
	var race: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(race)
	await get_tree().physics_frame
	_check("Race builds Deadbolt player and two CPU drivers",
		race.car.vehicle_id == "deadbolt" and race.cpu_drivers.size() == 2)
	_check("Race player uses Deadbolt production art", race.car.get_node_or_null("VisualRoot/ProductionModel") != null)
	race.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
