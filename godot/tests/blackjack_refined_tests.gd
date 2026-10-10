extends Node3D

const CANDIDATE := "res://assets/vehicles/models/blackjack/blackjack_refined.glb"
const LOD := "res://assets/vehicles/models/blackjack/blackjack_refined_lod1.glb"
const SEMANTICS := ["Paint_Primary", "Paint_Secondary", "Paint_Accent", "Glass", "Mirror", "Rubber", "Grille", "Lights", "Gunmetal", "BrushedMetal", "ArmorProtected"]
var passed := 0
var failed := 0


func _ready() -> void:
	# Replace this guard with full assembly/decal acceptance gates before promotion.
	_check("unapproved over-budget candidate stays inactive", VehicleCatalog.get_vehicle("blackjack")["visual"]["scene"] != CANDIDATE)
	for material_name: String in ["armor_wear", "brushed_metal", "grille", "rubber"]:
		var material := load("res://assets/vehicles/models/blackjack/refined_materials/blackjack_%s.tres" % material_name) as ORMMaterial3D
		_check("procedural Godot ORM resource loads", material != null and material.orm_texture != null)
	var baseline := _vehicle(false)
	var candidate := _vehicle(true)
	await get_tree().process_frame
	var model := candidate.get_node("VisualRoot/ProductionModel")
	var triangles := _triangles(model)
	_check("gameplay triangle budget", triangles >= 20000 and triangles <= 40000)
	var low := (load(LOD) as PackedScene).instantiate()
	var low_triangles := _triangles(low)
	_check("LOD reduces triangles", low_triangles >= 7000 and low_triangles < triangles * 0.65)
	low.free()
	var materials := {}
	var protected_before := {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_check("UV channel: " + mesh.name, uv.size() == vertices.size() and not uv.is_empty())
			if source == null:
				_check("standard semantic material", false)
				continue
			materials[source.resource_name] = true
			_check("no default or unknown semantic material", SEMANTICS.has(source.resource_name))
			if not source.resource_name.begins_with("Paint_"):
				protected_before[str(mesh.get_path()) + ":" + str(surface)] = source.albedo_color
				_check("protected surface has no paint override", mesh.get_surface_override_material(surface) == null)
	for semantic: String in SEMANTICS:
		_check("semantic slot: " + semantic, materials.has(semantic))
	var customization := VehicleCatalog.default_customization("blackjack")
	customization["primary_color"] = "e32636"
	customization["secondary_color"] = "25cf5c"
	customization["accent_color"] = "375bea"
	customization["parts"]["hood_engine"] = "supercharger"
	candidate.apply_customization(customization)
	model = candidate.get_node("VisualRoot/ProductionModel")
	var expected := {"Paint_Primary": Color("e32636"), "Paint_Secondary": Color("25cf5c"), "Paint_Accent": Color("375bea")}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				_check("customized semantic material remains assigned", false)
				continue
			if source.resource_name.begins_with("Paint_"):
				var override := mesh.get_surface_override_material(surface) as StandardMaterial3D
				_check("paint reaches only its channel", override != null and override.albedo_color.is_equal_approx(expected[source.resource_name]))
			else:
				var key := str(mesh.get_path()) + ":" + str(surface)
				_check("protected color unchanged", source.albedo_color == protected_before[key] and mesh.get_surface_override_material(surface) == null)
	_check("physical wheels remain four", candidate.wheels.size() == 4)
	_check("middle bogie remains visual only", candidate.get_node("VisualMiddleBogie").get_child_count() == 3)
	_check("collision shapes unchanged", _collision_signature(candidate) == _collision_signature(baseline))
	_check("mass unchanged", candidate.mass == baseline.mass)
	_check("inertia unchanged", candidate.inertia == baseline.inertia)
	for i in range(4):
		_check("wheel hardpoint and radius unchanged", candidate.wheels[i].position == baseline.wheels[i].position and candidate.wheels[i].radius == baseline.wheels[i].radius)
	var engine := candidate.get_part_socket("hood_engine")
	_check("modular engine socket retained", engine != null and engine.get_child_count() == 1)
	_check("socket transform unchanged", engine.transform == baseline.get_part_socket("hood_engine").transform)
	_check("axle assemblies present", candidate.get_node("AxleVisuals").get_child_count() == 2)
	await get_tree().process_frame
	_check("six visible suspension links", candidate.supports.size() == 6)
	for support: MeshInstance3D in candidate.supports:
		_check("suspension link has no physical collider", support.get_child_count() == 0)
		_check("suspension link has finite, nonzero transform", support.transform.is_finite() and absf(support.basis.determinant()) > 0.001)
	var visual_wheels: Array[Wheel] = candidate.wheels.duplicate()
	for child: Node in candidate.get_node("VisualMiddleBogie").get_children():
		if child is Wheel:
			visual_wheels.append(child)
	for wheel: Wheel in visual_wheels:
		candidate._install_tire(wheel)
		candidate._install_tire(wheel)
		var assembly := wheel.get_node("ModularWheelVisual")
		_check("tire installation is idempotent", assembly.find_children("Tire_Refined*", "", false, false).size() == 1)
		_check("old torus tire removed", assembly.get_node_or_null("Tire") == null)
		for mesh: MeshInstance3D in assembly.get_node("Tire_Refined").find_children("*", "MeshInstance3D", true, false):
			_check("tire is authored geometry, not a torus primitive", not mesh.mesh is TorusMesh)
			for surface in range(mesh.mesh.get_surface_count()):
				var tire_material := mesh.mesh.surface_get_material(surface)
				_check("tire material protected", tire_material != null and tire_material.resource_name == "Rubber" and mesh.get_surface_override_material(surface) == null)
	await _check_settled_contact(baseline, candidate)
	print("BLACKJACK_REFINED_TESTS %d passed, %d failed; gameplay %d; LOD %d" % [passed, failed, triangles, low_triangles])
	get_tree().quit(1 if failed else 0)


func _vehicle(refined: bool) -> Vehicle:
	var vehicle: Vehicle = preload("res://tests/blackjack_refined_preview_vehicle.gd").new() if refined else Vehicle.new()
	vehicle.tuning = TuningProfile.new()
	vehicle.freeze = true
	var spec := VehicleCatalog.get_vehicle("blackjack")
	if refined:
		spec = preload("res://tests/blackjack_refined_fixture.gd").spec()
	vehicle.apply_vehicle_spec(spec)
	add_child(vehicle)
	return vehicle


func _check_settled_contact(baseline: Vehicle, candidate: Vehicle) -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, .1, 40)
	collision.shape = box
	collision.position.y = -.05
	ground.add_child(collision)
	add_child(ground)
	baseline.position = Vector3(-10, .85, 0)
	candidate.position = Vector3(0, .85, 0)
	baseline.freeze = false
	candidate.freeze = false
	for i in range(180):
		await get_tree().physics_frame
	baseline.freeze = true
	candidate.freeze = true
	_check("art rig preserves settled body pose", (baseline.position + Vector3(10, 0, 0)).distance_to(candidate.position) < .001 and baseline.basis.is_equal_approx(candidate.basis))
	_check("art rig preserves settled velocity", baseline.linear_velocity.distance_to(candidate.linear_velocity) < .001)
	for child: Node in candidate.get_node("VisualMiddleBogie").get_children():
		if child is Wheel:
			var center := (child.get_node("ModularWheelVisual") as Node3D).global_position
			_check("visual bogie seated on ground", absf(center.y - child.radius) < .025)


func _triangles(root: Node) -> int:
	var total := 0
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			total += int(mesh.mesh.surface_get_array_index_len(surface) / 3.0)
	return total


func _collision_signature(vehicle: Vehicle) -> Array:
	var result := []
	for node: Node in vehicle.get_children():
		if node is CollisionShape3D:
			result.append([node.transform, (node.shape as BoxShape3D).size])
	return result


func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("BLACKJACK_REFINED: " + label)
