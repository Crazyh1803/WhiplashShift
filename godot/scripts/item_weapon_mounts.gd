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
		_build_hatch(node)
		_reset_state(node)
		_pose(node)
		mounts[end] = node
	return mounts


## Fold rig. Per-mount state lives in node metadata: "want" / "shown" are "", "Gun" or "Launcher";
## "t" is deploy progress 0 (folded in the hatch) .. 1 (deployed).
const DEPLOY_TIME := 0.45
const RETRACT_TIME := 0.35
const SINK := 0.55
const PULL_BACK := 0.35
const FOLD_PITCH := 0.55
const DOOR_OPEN := 1.9
const RECESS := Vector3(1.12, 0.03, 0.9)


static func _kind(id: String) -> String:
	if id == "machine_guns":
		return "Gun"
	return "Launcher" if id in ["rockets", "homing", "grenades"] else ""


## Requests the desired state only; tick() animates toward it.
static func show_weapon(mounts: Dictionary, end: String, id: String) -> void:
	for side: String in mounts:
		var mount: Node3D = mounts[side]
		mount.set_meta("want", _kind(id) if side == end else "")


## True when `id`'s rig is fully deployed on `end` and nothing is pending.
static func ready(mounts: Dictionary, end: String, id: String) -> bool:
	if not mounts.has(end):
		return false
	var mount: Node3D = mounts[end]
	var kind := _kind(id)
	return kind != "" and mount.get_meta("want", "") == kind and mount.get_meta("shown", "") == kind \
		and float(mount.get_meta("t", 0.0)) >= 1.0


## Requests every rig to fold away; `immediate` snaps all to the hidden folded state (hard reset).
static func hide(mounts: Dictionary, immediate := false) -> void:
	for side: String in mounts:
		var mount: Node3D = mounts[side]
		mount.set_meta("want", "")
		if immediate:
			mount.set_meta("shown", "")
			mount.set_meta("t", 0.0)
			_pose(mount)


## Deterministic: old end(s) fully retract before a new end or weapon deploys; a large delta runs both.
static func tick(mounts: Dictionary, delta: float) -> void:
	var budget := maxf(delta, 0.0)
	for _step in 6:
		var retracting: Array[Node3D] = []
		for side: String in mounts:
			var mount: Node3D = mounts[side]
			var shown: String = mount.get_meta("shown", "")
			if shown != "" and shown != mount.get_meta("want", ""):
				retracting.append(mount)
		var used := 0.0
		if not retracting.is_empty():
			for mount in retracting:
				var t := float(mount.get_meta("t", 0.0))
				var step := minf(budget, t * RETRACT_TIME)
				used = maxf(used, step)
				t = maxf(0.0, t - step / RETRACT_TIME)
				mount.set_meta("t", t)
				if t <= 0.0:
					mount.set_meta("shown", "")
				_pose(mount)
		else:
			for side: String in mounts:
				var mount: Node3D = mounts[side]
				var want: String = mount.get_meta("want", "")
				if want == "":
					continue
				if mount.get_meta("shown", "") == "":
					mount.set_meta("shown", want)
					mount.set_meta("t", 0.0)
				var t := float(mount.get_meta("t", 0.0))
				var step := minf(budget, (1.0 - t) * DEPLOY_TIME)
				used = step
				mount.set_meta("t", minf(1.0, t + step / DEPLOY_TIME))
				_pose(mount)
				break
		budget -= used
		if budget <= 0.00001 or used <= 0.0 and retracting.is_empty():
			break


static func _pose(mount: Node3D) -> void:
	var shown: String = mount.get_meta("shown", "")
	var t: float = mount.get_meta("t", 0.0) if shown != "" else 0.0
	var door := smoothstep(0.0, 0.3, t)
	var lift := smoothstep(0.2, 0.9, t)
	mount.visible = shown != "" and t > 0.0
	for kind in ["Gun", "Launcher"]:
		var model: Node3D = mount.get_node(kind)
		model.visible = kind == shown and t > 0.12
		if model.visible:
			model.transform = Transform3D(Basis(Vector3.RIGHT, -FOLD_PITCH * (1.0 - lift)),
				Vector3(0, -SINK * (1.0 - lift), PULL_BACK * (1.0 - lift)))
	var hatch: Node3D = mount.get_node_or_null("Hatch")
	if hatch == null:
		return
	for side in [-1.0, 1.0]:
		var pivot: Node3D = hatch.get_node("Door" + ("L" if side < 0 else "R"))
		pivot.rotation.z = -side * DOOR_OPEN * door
		var arm: Node3D = hatch.get_node("Arm" + ("L" if side < 0 else "R"))
		arm.rotation.x = 1.0 * lift


static func _build_hatch(mount: Node3D) -> void:
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	mount.add_child(hatch)
	var dark := CombatVisuals.metal(Color("05080b"))
	var steel := CombatVisuals.metal(Color("59636c"))
	var armor := CombatVisuals.metal(Color("2a323b"))
	# Dark recess pad with a raised steel frame, set just above the deck so it reads as a cut-out.
	CombatVisuals.box(hatch, Vector3(0, 0.025, 0), Vector3(RECESS.x, RECESS.y, RECESS.z), dark)
	for z in [-1.0, 1.0]:
		CombatVisuals.box(hatch, Vector3(0, 0.04, z * (RECESS.z * 0.5 + 0.03)), Vector3(RECESS.x + 0.12, 0.06, 0.06), steel)
	for x in [-1.0, 1.0]:
		CombatVisuals.box(hatch, Vector3(x * (RECESS.x * 0.5 + 0.03), 0.04, 0), Vector3(0.06, 0.06, RECESS.z + 0.12), steel)
	for side in [-1.0, 1.0]:
		var tag := "L" if side < 0 else "R"
		# Hinged door leaf: pivot on the outer edge, plate extends inward when closed.
		var pivot := Node3D.new()
		pivot.name = "Door" + tag
		pivot.position = Vector3(side * RECESS.x * 0.5, 0.06, 0)
		hatch.add_child(pivot)
		CombatVisuals.box(pivot, Vector3(-side * RECESS.x * 0.25, 0, 0), Vector3(RECESS.x * 0.5, 0.035, RECESS.z), armor)
		CombatVisuals.box(pivot, Vector3(-side * RECESS.x * 0.25, 0.022, 0), Vector3(RECESS.x * 0.36, 0.01, 0.12), CombatVisuals.glow(Color("ffa53d"), 1.0))
		# Small lift arm: rod hinged at the frame that swings up as the weapon rises.
		var arm := Node3D.new()
		arm.name = "Arm" + tag
		arm.position = Vector3(side * (RECESS.x * 0.5 + 0.12), 0.06, RECESS.z * 0.35)
		hatch.add_child(arm)
		CombatVisuals.box(arm, Vector3(0, 0, -0.22), Vector3(0.05, 0.05, 0.44), steel)
		CombatVisuals.cylinder(arm, Vector3.ZERO, 0.045, 0.1, armor).rotation.z = PI / 2


static func _reset_state(mount: Node3D) -> void:
	mount.set_meta("want", "")
	mount.set_meta("shown", "")
	mount.set_meta("t", 0.0)


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
