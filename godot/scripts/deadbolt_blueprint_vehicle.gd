## Adapts authored coupe/truck hub artwork to the existing four-wheel simulation.
extends Vehicle

const DISPLAY_RADIUS := {"A": 0.40, "B": 0.43}


func _configure_imported_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.visible = not String(node.name).begins_with("Wheel_")
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var colors := _authored_paint_colors()
			if not colors.has(source.resource_name):
				continue
			var material := source.duplicate() as StandardMaterial3D
			material.albedo_color = colors[source.resource_name]
			mesh_instance.set_surface_override_material(surface, material)
	for child: Node in node.get_children():
		_configure_imported_meshes(child)


func _authored_paint_colors() -> Dictionary:
	return {
		"Deadbolt_Paint": vehicle_color,
		"Deadbolt_Secondary": vehicle_secondary_color,
		"Deadbolt_Stripe": vehicle_accent_color,
	}


func _build_wheels() -> void:
	super._build_wheels()
	_install_authored_wheels()


func _refresh_wheel_visuals_and_mounts() -> void:
	super._refresh_wheel_visuals_and_mounts()
	_install_authored_wheels()
	_update_axle_visuals()


func _install_authored_wheels() -> void:
	var model := _visual_root.get_node_or_null("ProductionModel") as Node3D
	if model == null:
		return
	var meshes := model.find_children("Wheel_*", "MeshInstance3D", true, false)
	for wheel: Wheel in wheels:
		var parts: Array[MeshInstance3D] = []
		var tire: MeshInstance3D
		for source: MeshInstance3D in meshes:
			var is_coupe := String(source.name).begins_with("Wheel_Coupe_")
			if is_coupe != (wheel.end == "A") or signf(to_local(source.global_position).x) != wheel.side:
				continue
			parts.append(source)
			if "_Tire_" in String(source.name):
				tire = source
		if tire == null:
			push_error("%s artwork is missing the tire hub for %s" % [vehicle_id, wheel.name])
			continue
		# Art hubs define the steering pivot, independently of physical hardpoints.
		# This also handles source transforms and cars spawned away from the origin.
		var center := to_local(tire.global_position)
		wheel.remove_child(wheel._visual)
		wheel._visual.free()
		var assembly := Node3D.new()
		assembly.name = "ModularWheelVisual"
		wheel.add_child(assembly)
		wheel._visual = assembly
		wheel._visual_base_rotation = Vector3.ZERO
		wheel._visual_offset = Vector3(
			center.x - wheel.position.x,
			float(DISPLAY_RADIUS[wheel.end]) - wheel.radius,
			center.z - wheel.position.z
		)
		for source: MeshInstance3D in parts:
			var local_transform := global_transform.affine_inverse() * source.global_transform
			var copy := source.duplicate() as MeshInstance3D
			copy.visible = true
			local_transform.origin -= center
			assembly.add_child(copy)
			copy.transform = local_transform
		wheel._place_visual(wheel.ride_distance)
		if freeze:
			assembly.position = center - wheel.position


func configure_static_preview() -> void:
	if freeze:
		position.y = 0.62


func _update_axle_visuals() -> void:
	super._update_axle_visuals()
	for end: String in _axle_visuals:
		var pair := _wheel_pair(end)
		if pair.size() != 2:
			continue
		var left := pair[0].get_node_or_null("ModularWheelVisual") as Node3D
		var right := pair[1].get_node_or_null("ModularWheelVisual") as Node3D
		if left == null or right == null:
			continue
		var axle := _axle_visuals[end] as Node3D
		axle.position = to_local((left.global_position + right.global_position) * 0.5)
		(axle.get_node("Shaft").mesh as CylinderMesh).height = left.global_position.distance_to(right.global_position) - 0.08
