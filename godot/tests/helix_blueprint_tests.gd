## Tracked/hover artwork must never change the original four-wheel simulation.
extends Node3D

const FACTORY := preload("res://scripts/vehicle_factory.gd")
var _pass := 0
var _fail := 0


func _ready() -> void:
	var spec := VehicleCatalog.get_vehicle("helix")
	var car := FACTORY.create(spec)
	car.tuning = TuningProfile.new()
	car.freeze = true
	car.position = Vector3(8, 0.62, -13)
	car.rotation.y = 0.73
	add_child(car)
	_check("Helix uses its dedicated tracked/hover adapter", car.get_script() == load("res://scripts/helix_blueprint_vehicle.gd"))
	var model := car.get_node_or_null("VisualRoot/ProductionModel") as Node3D
	_check("Helix loads authored production model", model != null)
	if model == null:
		get_tree().quit(1)
		return
	_check("Four simulation wheels remain authoritative", car.wheels.size() == 4)
	_check("No customization style exposes physics wheels", spec["visual"].get("wheel_styles", {}).is_empty())
	_check("No invented road wheels enter the hover artwork", model.find_children("Wheel_*", "MeshInstance3D", true, false).is_empty())
	var tracks := model.find_children("Prop_Track_*", "MeshInstance3D", true, false)
	_check("Source track bogies are present", tracks.size() >= 2)
	var low := [INF, INF]
	for track: MeshInstance3D in tracks:
		_check("Tracks remain visible body artwork", track.is_visible_in_tree() and track.find_parent("ModularWheelVisual") == null)
		for surface in track.mesh.get_surface_count():
			var vertices: PackedVector3Array = track.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := track.to_global(vertex)
				var side := 0 if car.to_local(point).x < 0 else 1
				low[side] = minf(low[side], point.y)
	for side in 2:
		_check("Each track contacts the frozen preview ground", absf(low[side]) < 0.01)
	var custom := VehicleCatalog.default_customization("helix")
	custom["primary_color"] = "cc2244"
	custom["secondary_color"] = "225588"
	custom["accent_color"] = "ddb344"
	var expected := {"Helix_Paint": Color("cc2244"), "Helix_Secondary": Color("225588"), "Helix_Stripe": Color("ddb344")}
	for refresh in 2:
		car.apply_customization(custom)
		model = car.get_node("VisualRoot/ProductionModel")
		var found := {}
		var protected_ok := true
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface: int in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if source == null:
					continue
				if expected.has(source.resource_name):
					found[source.resource_name] = true
					_check("Helix paint channel applies", mesh.get_active_material(surface).albedo_color.is_equal_approx(expected[source.resource_name]))
				else:
					protected_ok = protected_ok and mesh.get_surface_override_material(surface) == null
		_check("All three authored paint channels exist", found.size() == 3)
		_check("Glass, track rubber, lenses and hardware retain authored materials", protected_ok)
		for wheel: Wheel in car.wheels:
			_check("Physics wheel stays hidden after customization", not wheel.is_visible_in_tree())
			_check("Physical radius and hardpoint remain unchanged", is_equal_approx(wheel.radius, car.tuning.wheel_radius(wheel.end))
				and wheel.position.is_equal_approx(car._wheel_mount(wheel.end, wheel.side)))
		car._update_axle_visuals()
		_check("Physics axle shafts stay hidden", not car.get_node("AxleVisuals").is_visible_in_tree())
		_check("No extra visual bogie is generated", not car.get_node("VisualMiddleBogie").is_visible_in_tree())
		var refreshed := model.find_children("Prop_Track_*", "MeshInstance3D", true, false)
		_check("Customization retains the complete track assemblies", refreshed.size() == tracks.size())
		for track: MeshInstance3D in refreshed:
			_check("Track artwork remains visible after customization", track.is_visible_in_tree())
	car.free()
	GameSession.configure("HELIX", "helix", ["helix", "deadbolt"])
	var race: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(race)
	await get_tree().physics_frame
	_check("Helix constructs as player and CPU", race.car.vehicle_id == "helix"
		and race.cpu_drivers.size() == 2 and race.cpu_drivers[0].target.vehicle_id == "helix")
	_check("Helix player retains production artwork", race.car.get_node_or_null("VisualRoot/ProductionModel") != null)
	for wheel: Wheel in race.car.wheels:
		_check("Player physics wheels remain hidden", not wheel.is_visible_in_tree())
	race.queue_free()
	await get_tree().process_frame
	print("HELIX: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
