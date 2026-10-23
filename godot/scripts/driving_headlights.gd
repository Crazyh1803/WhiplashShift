## Paired beams mounted at the authored lenses, with a fallback for greybox cars.
## Kept outside VisualRoot so paint/part rebuilds cannot remove the lights.
extends Node3D

var _car: Vehicle
var _lamps: Dictionary = {}
var _lens_materials: Array[ShaderMaterial] = []
var _visual: Node3D


func _ready() -> void:
	_car = get_parent() as Vehicle
	var mounts := _lens_mounts()
	for end: String in ["A", "B"]:
		var pair := Node3D.new()
		pair.name = "End" + end
		add_child(pair)
		_lamps[end] = pair
		var sign_z := -1.0 if end == "A" else 1.0
		for side: int in [-1, 1]:
			var lamp := SpotLight3D.new()
			lamp.name = "Left" if side < 0 else "Right"
			var key := "%s_%d" % [end, side]
			lamp.position = mounts.get(key, Vector3(side * _car.tuning.body_width * 0.3,
				0.3 if end == "A" else 0.65, sign_z * (_car.tuning.half_base + 1.1)))
			# Start just beyond the lens to avoid lighting the body from within.
			lamp.position.z += sign_z * 0.1
			lamp.rotation_degrees = Vector3(-5.0, 0.0 if end == "A" else 180.0, 0.0)
			lamp.light_color = Color("fff1d6")
			lamp.light_energy = 8.0
			lamp.spot_range = 65.0
			lamp.spot_angle = 32.0
			lamp.spot_angle_attenuation = 1.5
			lamp.spot_attenuation = 1.0
			lamp.shadow_enabled = true
			pair.add_child(lamp)
	update_active_end(_car.active_end)


func update_active_end(end: String) -> void:
	for key: String in _lamps:
		_lamps[key].visible = key == end
	for material in _lens_materials:
		material.set_shader_parameter("active_sign", -1.0 if end == "A" else 1.0)


func _process(_delta: float) -> void:
	# Follow terrain-induced visual motion as well as the chassis transform.
	var visual := _car.get_node_or_null("VisualRoot") as Node3D
	if visual != null:
		if visual != _visual:
			_lens_materials.clear()
			_lens_mounts()
			update_active_end(_car.active_end)
		transform = visual.transform


func _lens_mounts() -> Dictionary:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	var visual := _car.get_node("VisualRoot") as Node3D
	_visual = visual
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var local := _car.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null:
				continue
			var label := material.resource_name.to_lower()
			if label != "lights" and not label.ends_with("_headlight") and not label.ends_with("_lamp") and not label.ends_with("_light"):
				continue
			# Imported meshes may combine both ends in one surface. Mask emission
			# in chassis space so the inactive lenses still receive world lighting.
			var lens := ShaderMaterial.new()
			lens.shader = preload("res://shaders/driving_headlight.gdshader")
			lens.set_shader_parameter("lens_color", material.albedo_color)
			lens.set_shader_parameter("lens_emission", material.emission * material.emission_energy_multiplier if material.emission_enabled else Color.BLACK)
			lens.set_shader_parameter("lens_texture", material.albedo_texture)
			lens.set_shader_parameter("has_lens_texture", material.albedo_texture != null)
			lens.set_shader_parameter("lens_metallic", material.metallic)
			lens.set_shader_parameter("lens_roughness", material.roughness)
			lens.set_shader_parameter("mesh_to_chassis", local)
			mesh.set_surface_override_material(surface, lens)
			_lens_materials.append(lens)
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = local * vertex
				if absf(point.z) < 0.5:
					continue
				var key := "%s_%d" % ["A" if point.z < 0 else "B", -1 if point.x < 0 else 1]
				sums[key] = sums.get(key, Vector3.ZERO) + point
				counts[key] = int(counts.get(key, 0)) + 1
	for key: String in sums:
		sums[key] /= float(counts[key])
	return sums
