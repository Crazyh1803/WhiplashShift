## Candidate-only art rig. All force integration is inherited unchanged from Vehicle.
extends Vehicle

var supports: Array[MeshInstance3D] = []
var visual_wheels: Array[Wheel] = []
const TIRE_SCENES := {
	"aero": preload("res://assets/vehicles/models/blackjack/blackjack_refined_tire_aero.glb"),
	"rugged": preload("res://assets/vehicles/models/blackjack/blackjack_refined_tire_rugged.glb"),
}


func _build_wheels() -> void:
	super._build_wheels()
	for wheel: Wheel in wheels:
		_install_tire(wheel)


func _refresh_wheel_visuals_and_mounts() -> void:
	super._refresh_wheel_visuals_and_mounts()
	for wheel: Wheel in wheels:
		_install_tire(wheel)


func _build_visual_bogie() -> void:
	super._build_visual_bogie()
	visual_wheels = wheels.duplicate()
	if _bogie_root != null:
		for child: Node in _bogie_root.get_children():
			if child is Wheel:
				_install_tire(child)
				visual_wheels.append(child)


func _install_tire(wheel: Wheel) -> void:
	var assembly := wheel.get_node_or_null("ModularWheelVisual") as Node3D
	if assembly == null:
		return
	for tire_name: String in ["Tire", "Tire_Refined"]:
		var old := assembly.get_node_or_null(tire_name)
		if old != null:
			assembly.remove_child(old)
			old.queue_free()
	var style := "aero" if wheel.end == "A" else "rugged"
	var packed := TIRE_SCENES[style] as PackedScene
	var tire := packed.instantiate() as Node3D
	tire.name = "Tire_Refined"
	tire.scale = Vector3.ONE * wheel.radius
	assembly.add_child(tire)
	var rim := assembly.get_node_or_null("SwappableRim")
	if rim != null:
		for mesh: MeshInstance3D in rim.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = null


func _update_visual_bogie() -> void:
	super._update_visual_bogie()
	if _bogie_root == null or not _bogie_root.visible or wheels.size() != 4:
		return
	# Correct only the visual contact plane at the intermediate axle. No raycast,
	# suspension, wheel state or force calculation is added or modified.
	var front := _wheel_pair("A")
	var rear := _wheel_pair("B")
	if front.size() != 2 or rear.size() != 2:
		return
	var z_a := (front[0].position.z + front[1].position.z) * .5
	var z_b := (rear[0].position.z + rear[1].position.z) * .5
	if absf(z_b - z_a) < .0001:
		return
	var contact_a := 0.0
	var contact_b := 0.0
	for i in range(2):
		contact_a += (front[i].position.y - front[i].ride_distance) * .5
		contact_b += (rear[i].position.y - rear[i].ride_distance) * .5
	var t := clampf((_bogie_root.position.z + float(_visual_config.get("middle_bogie_z", .66)) - z_a) / (z_b - z_a), 0, 1)
	# The visual middle pair uses the rugged B radius; A tires remain smaller.
	_bogie_root.position.y = lerpf(contact_a, contact_b, t) + tuning.wheel_radius("B")


func _process(_delta: float) -> void:
	# Vehicle has no _process callback; physics and wheel updates are inherited.
	if supports.size() != visual_wheels.size():
		for mesh in supports:
			mesh.queue_free()
		supports.clear()
		for wheel: Wheel in visual_wheels:
			var mesh := MeshInstance3D.new()
			mesh.name = "VisualSuspensionLink_" + wheel.name
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .038
			cylinder.bottom_radius = .038
			cylinder.height = 1
			cylinder.radial_segments = 12
			mesh.mesh = cylinder
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("2a3032")
			material.metallic = .82
			material.roughness = .45
			mesh.material_override = material
			add_child(mesh)
			supports.append(mesh)
	for i in range(visual_wheels.size()):
		var wheel := visual_wheels[i]
		var assembly := wheel.get_node_or_null("ModularWheelVisual") as Node3D
		if assembly == null:
			continue
		var center := to_local(assembly.global_position)
		var upper := Vector3(wheel.side*.57, -.04, center.z+.11)
		var lower := Vector3(wheel.side*.68, center.y, center.z)
		var y := (lower-upper).normalized()
		var x := y.cross(Vector3.FORWARD).normalized()
		supports[i].position = (upper+lower)*.5
		supports[i].basis = Basis(x, y*(lower-upper).length(), x.cross(y))
