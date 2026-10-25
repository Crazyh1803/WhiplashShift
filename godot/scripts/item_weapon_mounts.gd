## Authored weapon attachments in chassis coordinates, independent of physics dimensions.
class_name ItemWeaponMounts
extends RefCounted

# Mount feet sit 1-2 cm into the measured deck surfaces of each production GLB.
const PROFILES := {
	"blackjack": [Vector3(0, .09, -1.55), Vector3(0, .73, 1.50)],
	"deadbolt": [Vector3(0, .51, -1.55), Vector3(0, .66, 1.50)],
	"nightshift": [Vector3(0, .29, -1.55), Vector3(0, .49, 1.50)],
	"ramjet": [Vector3(0, .57, -1.55), Vector3(0, .72, 1.50)],
	"boilerfang": [Vector3(0, .02, -1.55), Vector3(0, .46, 1.45)],
	"knifeedge": [Vector3(0, .36, -1.50), Vector3(0, .68, 1.40)],
	"helix": [Vector3(0, .28, -1.35), Vector3(0, .57, 1.15)],
}


static func create(car: Vehicle) -> Dictionary:
	var mounts := {}
	var profile: Array = PROFILES.get(car.vehicle_id, PROFILES["blackjack"])
	for end in ["A", "B"]:
		var node := Node3D.new()
		node.name = "ItemGun" + end
		car.add_child(node)
		node.position = profile[0 if end == "A" else 1]
		node.rotation.y = 0.0 if end == "A" else PI
		for kind in ["Gun", "Launcher"]:
			var filename := "item_gun_helix" if kind == "Gun" and car.vehicle_id == "helix" else ("item_gun_standard" if kind == "Gun" else "item_launcher")
			var packed := load("res://assets/items/weapons/" + filename + ".glb") as PackedScene
			var model := packed.instantiate() as Node3D
			model.name = kind
			node.add_child(model)
			model.hide()
			if kind == "Launcher" and car.vehicle_id == "helix":
				_skin_helix(model)
		node.hide()
		mounts[end] = node
	return mounts


static func show_weapon(mounts: Dictionary, end: String, id: String) -> void:
	for side: String in mounts:
		var mount: Node3D = mounts[side]
		mount.visible = side == end and id in ["machine_guns", "rockets", "homing", "grenades"]
		mount.get_node("Gun").visible = id == "machine_guns"
		mount.get_node("Launcher").visible = id in ["rockets", "homing", "grenades"]


static func muzzle(mounts: Dictionary, end: String, id: String, barrel: int) -> Vector3:
	var model: Node3D = mounts[end].get_node("Gun" if id == "machine_guns" else "Launcher")
	var marker_name := ("MuzzleLeft" if barrel % 2 == 0 else "MuzzleRight") if id == "machine_guns" else "Muzzle"
	var marker := model.find_child(marker_name, true, false) as Node3D
	if marker == null:
		push_error("Weapon GLB is missing muzzle socket: " + marker_name)
		return mounts[end].global_position
	return marker.global_position


static func _skin_helix(model: Node3D) -> void:
	var palette := {"M_Olive": Color(0.34, 0.07, 0.13), "M_Steel": Color(0.78, 0.73, 0.60), "M_Warn": Color(0.15, 1.0, 0.72)}
	var recolored := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and palette.has(source.resource_name):
				var material := source.duplicate() as StandardMaterial3D
				material.albedo_color = palette[source.resource_name]
				mesh.set_surface_override_material(surface, material)
				recolored += 1
	if recolored == 0:
		push_error("Helix launcher GLB has no recognized palette materials")
