## Bodywork wear: scuffs/scratches/scorching track Vehicle.damage on all seven production
## cars without touching paint, shared resources or physics.
extends Node3D

const CAR_IDS: Array[String] = ["blackjack", "boilerfang", "helix", "ramjet", "knifeedge", "deadbolt", "nightshift"]

var _pass := 0
var _fail := 0


func _ready() -> void:
	for id: String in CAR_IDS:
		await _test_car(id)
	await _test_independent_and_unshared()
	print("BODYWORK_VISUAL: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)


func _car(id: String) -> Vehicle:
	var car := preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle(id))
	car.freeze = true
	add_child(car)
	return car


func _bodywork(car: Vehicle) -> VehicleBodywork:
	return car.get_node("VehicleBodywork") as VehicleBodywork


func _overrides(bodywork: VehicleBodywork) -> Array[Material]:
	var result: Array[Material] = []
	for entry: Dictionary in bodywork.surface_entries():
		result.append((entry.mesh as MeshInstance3D).get_surface_override_material(entry.surface))
	return result


func _all_worn(bodywork: VehicleBodywork) -> bool:
	for entry: Dictionary in bodywork.surface_entries():
		if not bodywork.is_worn_surface(entry.mesh, entry.surface):
			return false
	return bodywork.surface_count() > 0


func _none_worn(bodywork: VehicleBodywork) -> bool:
	for entry: Dictionary in bodywork.surface_entries():
		if bodywork.is_worn_surface(entry.mesh, entry.surface):
			return false
	return true


## Number of wear passes in each surface's chain; must be exactly one per surface.
func _wear_pass_count(bodywork: VehicleBodywork) -> int:
	var most := 0
	for entry: Dictionary in bodywork.surface_entries():
		var count := 0
		var material: Material = (entry.mesh as MeshInstance3D).get_surface_override_material(entry.surface)
		while material != null:
			if material == bodywork.wear_material:
				count += 1
			material = material.next_pass
		most = maxi(most, count)
	return most


func _paint_signature(bodywork: VehicleBodywork) -> Array:
	var colors: Array = []
	for material: Material in _overrides(bodywork):
		if material is BaseMaterial3D:
			colors.append((material as BaseMaterial3D).albedo_color)
		elif material is ShaderMaterial:
			colors.append((material as ShaderMaterial).get_shader_parameter("primary_color"))
		else:
			colors.append(null)
	return colors


func _physics_signature(car: Vehicle) -> Array:
	var boxes: Array = []
	for shape: CollisionShape3D in car.find_children("*", "CollisionShape3D", true, false):
		var size := (shape.shape as BoxShape3D).size if shape.shape is BoxShape3D else Vector3.ZERO
		boxes.append([shape.transform, size])
	return [car.mass, car.center_of_mass, car.linear_damp, car.angular_damp, car.top_speed_multiplier,
		car.drive_multiplier, car.grip_multiplier, car.mass_multiplier, car.brake_multiplier, boxes]


func _test_car(id: String) -> void:
	var car := _car(id)
	await get_tree().process_frame
	var body := _bodywork(car)
	var tag := id + ": "
	_check(tag + "has eligible paint surfaces", body.surface_count() > 0)
	_check(tag + "bounded surface count", body.surface_count() <= VehicleBodywork.MAX_SURFACES)

	# Clean: no extra pass, original override objects, imported meshes untouched.
	var originals := _overrides(body)
	var clean_paint := _paint_signature(body)
	var physics_before := _physics_signature(car)
	_check(tag + "clean has no wear pass", _none_worn(body) and not body.is_attached())
	for entry: Dictionary in body.surface_entries():
		var source := (entry.mesh as MeshInstance3D).mesh.surface_get_material(entry.surface)
		_check(tag + "imported material has no next_pass", source == null or source.next_pass == null)

	# Staged wear follows the scalar.
	car.apply_cosmetic_damage(0.35)
	_check(tag + "scuffed wears every surface", _all_worn(body) and body.is_attached())
	_check(tag + "scuffed stage scalar", is_equal_approx(body.current_wear(), 0.35))
	_check(tag + "one wear pass per surface", _wear_pass_count(body) == 1)
	_check(tag + "paint unchanged under wear", _paint_signature(body) == clean_paint)
	car.apply_cosmetic_damage(0.45)
	_check(tag + "heavy stage scalar", is_equal_approx(body.current_wear(), 0.8))
	_check(tag + "no stacking on more damage", _wear_pass_count(body) == 1)
	_check(tag + "physics untouched by wear", _physics_signature(car) == physics_before)

	# Decay is driven by the car's own damage value.
	car.damage = 0.3
	await get_tree().process_frame
	_check(tag + "wear follows decayed damage", is_equal_approx(body.current_wear(), 0.3))
	car.damage = 0.0
	await get_tree().process_frame
	_check(tag + "wear clears when damage decays", _none_worn(body) and not body.is_attached())

	# Immediate reset restores the very same original materials.
	car.apply_cosmetic_damage(0.8)
	car.reset_effects_state()
	_check(tag + "reset clears wear immediately", _none_worn(body) and car.damage == 0.0)
	_check(tag + "reset restores paint", _paint_signature(body) == clean_paint)
	var restored := _overrides(body)
	var same_or_clean := true
	for index in originals.size():
		var material := restored[index]
		same_or_clean = same_or_clean and (material == originals[index] or material.next_pass == originals[index].next_pass)
	_check(tag + "reset restores original materials", same_or_clean)

	# Repaint while worn: new paint shows, a single wear pass remains.
	var custom := Color("ff2bd6")
	car.apply_cosmetic_damage(0.6)
	car.set_paint_color(custom)
	_check(tag + "repaint keeps wear", _all_worn(body) and _wear_pass_count(body) == 1)
	var recognisable := false
	for entry: Dictionary in body.surface_entries():
		var material := (entry.mesh as MeshInstance3D).get_surface_override_material(entry.surface)
		if material is BaseMaterial3D and (material as BaseMaterial3D).albedo_color.is_equal_approx(custom):
			recognisable = true
		elif material is ShaderMaterial and Color(
				(material as ShaderMaterial).get_shader_parameter("primary_color")).is_equal_approx(custom):
			recognisable = true
	_check(tag + "custom paint recognisable under wear", recognisable)
	car.set_paint_color(custom)
	_check(tag + "repeat repaint does not stack", _wear_pass_count(body) == 1)

	# Customization and spec rebuilds start from fresh visuals and keep following damage.
	var customization: Dictionary = VehicleCatalog.default_customization(id)
	customization["primary_color"] = "22cc88"
	car.apply_customization(customization)
	_check(tag + "customization rebuild keeps wear", _all_worn(body) and _wear_pass_count(body) == 1)
	car.apply_vehicle_spec(VehicleCatalog.get_vehicle(id))
	_check(tag + "spec rebuild keeps wear", _all_worn(body) and _wear_pass_count(body) == 1)
	_check(tag + "rebuild wear scalar", is_equal_approx(body.current_wear(), car.damage))
	car.reset_effects_state()
	_check(tag + "reset after rebuild clears wear", _none_worn(body) and body.surface_count() > 0)
	_check(tag + "physics untouched after rebuilds", _physics_signature(car) == physics_before)
	car.queue_free()
	await get_tree().process_frame


func _test_independent_and_unshared() -> void:
	var first := _car("deadbolt")
	var second := _car("deadbolt")
	await get_tree().process_frame
	var a := _bodywork(first)
	var b := _bodywork(second)
	first.apply_cosmetic_damage(0.8)
	_check("damaging one car leaves the other clean", _all_worn(a) and _none_worn(b) and not b.is_attached())
	_check("cars own separate wear materials", a.wear_material != b.wear_material)
	second.apply_cosmetic_damage(0.35)
	_check("cars hold independent scalars", is_equal_approx(a.current_wear(), 0.8) and is_equal_approx(b.current_wear(), 0.35))
	var shared := false
	for material_a: Material in _overrides(a):
		for material_b: Material in _overrides(b):
			shared = shared or material_a == material_b
	_check("no override material is shared between cars", not shared)
	first.reset_effects_state()
	_check("resetting one car leaves the other worn", _none_worn(a) and _all_worn(b))
	var entry: Dictionary = a.surface_entries()[0]
	var livery := ShaderMaterial.new()
	livery.shader = VehicleBodywork.LIVERY_SHADER
	entry.mesh.set_surface_override_material(entry.surface, livery)
	for cycle in 5:
		first.apply_cosmetic_damage(0.35)
		var clone: Material = entry.mesh.get_surface_override_material(entry.surface)
		_check("livery cycle %d retains only the original material" % cycle, clone.get_meta(VehicleBodywork.META_ORIGINAL) == livery)
		first.reset_effects_state()
	first.queue_free()
	second.queue_free()
	await get_tree().process_frame
