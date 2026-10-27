## Cosmetic bodywork wear: scuffs, scratches and scorching that track Vehicle.damage.
##
## The wear is a next_pass shader appended to the car's own paint override materials, so
## glass, lights, wheels and anything without a paint override are never touched. It only
## ever reads `damage`; physics, HUD and recovery rules stay with the Vehicle.
## Imported/shared resources are never mutated: each wrapped surface gets a private clone
## of its override material, and the original is put back when the car is clean again.
class_name VehicleBodywork
extends Node

const WEAR_SHADER: Shader = preload("res://assets/vehicles/bodywork_wear.gdshader")
const LIVERY_SHADER: Shader = preload("res://assets/vehicles/blackjack_livery.gdshader")

const META_ORIGINAL := &"bodywork_original"
const MAX_SURFACES := 64
const WEAR_STEP := 0.004
const SKIP_MARKERS: Array[String] = [
	"wheel", "rim", "tire", "tyre", "glass", "window", "windshield", "windscreen", "light",
	"lamp", "lens", "weapon", "gun", "turret", "cannon", "rubber", "emissive",
]

## The single wear material this car shares across its wrapped surfaces.
var wear_material: ShaderMaterial

var _car: Node3D
var _entries: Array[Dictionary] = []  # {mesh: MeshInstance3D, surface: int}
var _attached := false
var _applied_wear := -1.0


func setup(car: Node3D) -> void:
	_car = car
	name = "VehicleBodywork"
	wear_material = ShaderMaterial.new()
	wear_material.shader = WEAR_SHADER
	wear_material.set_shader_parameter("wear", 0.0)
	wear_material.set_shader_parameter("variation", float(car.get_instance_id() % 997) / 997.0)


func _process(_delta: float) -> void:
	sync()


## Rescan the eligible paint surfaces after the visuals or paint were rebuilt. Safe to call
## repeatedly: surfaces that already carry the wear pass are not wrapped again.
func rebind(visual_root: Node) -> void:
	_entries.clear()
	_attached = false
	_applied_wear = -1.0
	if visual_root == null:
		return
	var model := visual_root.get_node_or_null("ProductionModel")
	if model == null:
		return
	var scales: Array[float] = []
	_collect(model, scales)
	if not scales.is_empty():
		var total := 0.0
		for value: float in scales:
			total += value
		wear_material.set_shader_parameter("body_scale", total / scales.size())
	sync()


func sync() -> void:
	var target := clampf(float(_car.get("damage")), 0.0, 1.0) if _car != null else 0.0
	if target <= 0.0:
		if _attached or _applied_wear != 0.0:
			_detach()
		_applied_wear = 0.0
		return
	if not _attached:
		_attach()
		_applied_wear = -1.0
	if absf(target - _applied_wear) >= WEAR_STEP or _applied_wear < 0.0:
		_applied_wear = target
		wear_material.set_shader_parameter("wear", target)


func is_attached() -> bool:
	return _attached


func current_wear() -> float:
	return float(wear_material.get_shader_parameter("wear")) if _attached else 0.0


func surface_count() -> int:
	return _entries.size()


## Eligible {mesh, surface} pairs, for tests and QA.
func surface_entries() -> Array[Dictionary]:
	return _entries


## True when the surface currently draws the wear pass.
func is_worn_surface(mesh: MeshInstance3D, surface: int) -> bool:
	return _chain_has_wear(mesh.get_surface_override_material(surface))


func _collect(node: Node, scales: Array[float]) -> void:
	if node is MeshInstance3D and _entries.size() < MAX_SURFACES:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.visible and mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				if _entries.size() < MAX_SURFACES and _eligible(mesh_instance, surface):
					_entries.append({"mesh": mesh_instance, "surface": surface})
					scales.append(_local_scale(mesh_instance))
	for child: Node in node.get_children():
		_collect(child, scales)


func _local_scale(mesh_instance: Node3D) -> float:
	var to_car := Transform3D.IDENTITY
	var node: Node = mesh_instance
	while node != null and node != _car:
		if node is Node3D:
			to_car = (node as Node3D).transform * to_car
		node = node.get_parent()
	return maxf(to_car.basis.get_scale().x, 0.0001)


func _eligible(mesh_instance: MeshInstance3D, surface: int) -> bool:
	var paint := mesh_instance.get_surface_override_material(surface)
	if paint == null:
		return false
	if paint is ShaderMaterial:
		if (paint as ShaderMaterial).shader != LIVERY_SHADER:
			return false
	elif paint is BaseMaterial3D:
		var base := paint as BaseMaterial3D
		if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.emission_enabled:
			return false
	else:
		return false
	var source := mesh_instance.mesh.surface_get_material(surface)
	var source_name := source.resource_name.to_lower() if source != null else ""
	# Authored paint is explicitly named; everything else is judged by name so glass,
	# lights, tyres and weapon pods on a flat-painted body are left alone.
	if source_name.begins_with("paint_"):
		return true
	var haystack := String(mesh_instance.name).to_lower() + " " + source_name
	for marker: String in SKIP_MARKERS:
		if marker in haystack:
			return false
	return true


func _attach() -> void:
	for entry: Dictionary in _entries:
		var mesh_instance: MeshInstance3D = entry.mesh
		if not is_instance_valid(mesh_instance):
			continue
		var current := mesh_instance.get_surface_override_material(entry.surface)
		if current == null or _chain_has_wear(current):
			continue
		var clone := _chain_with_wear(current)
		clone.set_meta(META_ORIGINAL, current)
		mesh_instance.set_surface_override_material(entry.surface, clone)
		if clone is ShaderMaterial:
			wear_material.set_shader_parameter("hide_embedded_wheels",
				(clone as ShaderMaterial).get_shader_parameter("hide_embedded_wheels"))
	_attached = true


func _detach() -> void:
	for entry: Dictionary in _entries:
		var mesh_instance: MeshInstance3D = entry.mesh
		if not is_instance_valid(mesh_instance):
			continue
		var current := mesh_instance.get_surface_override_material(entry.surface)
		if current == null or not current.has_meta(META_ORIGINAL):
			continue
		var original: Material = current.get_meta(META_ORIGINAL)
		if current is ShaderMaterial:
			# Livery params are refreshed in place by Vehicle, so strip the pass instead of
			# restoring a possibly stale original.
			_strip_wear(current)
		else:
			mesh_instance.set_surface_override_material(entry.surface, original)
	_attached = false
	wear_material.set_shader_parameter("wear", 0.0)


## Private copy of `base` (and of every pass already chained after it) ending in the wear pass.
func _chain_with_wear(base: Material) -> Material:
	var clone := base.duplicate() as Material
	clone.next_pass = _chain_with_wear(base.next_pass) if base.next_pass != null else wear_material
	return clone


func _chain_has_wear(material: Material) -> bool:
	while material != null:
		if material == wear_material:
			return true
		material = material.next_pass
	return false


func _strip_wear(material: Material) -> void:
	while material != null:
		if material.next_pass == wear_material:
			material.next_pass = null
			return
		material = material.next_pass
