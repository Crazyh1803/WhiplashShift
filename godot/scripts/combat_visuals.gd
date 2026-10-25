## Reusable combat art. Materials and textures are shared; transient nodes are bounded by Combat.
class_name CombatVisuals
extends RefCounted

const SMOKE = preload("res://assets/vfx/smoke.png")
const SPARK = preload("res://assets/vfx/spark.png")
const METAL = preload("res://shaders/crate_metal.gdshader")
const CLOUD = preload("res://shaders/particle_smoke.gdshader")
const HOLOGRAM = preload("res://shaders/hologram.gdshader")
const CRATE_GLB := "res://assets/items/crate/item_supply_crate.glb"


static func metal(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = METAL
	material.set_shader_parameter("paint", color)
	return material


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


static func hologram(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HOLOGRAM
	material.set_shader_parameter("tint", color)
	return material


static func box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = pos
	return node


static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, top := -1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = pos
	return node


static func ring(parent: Node3D, pos: Vector3, radius: float, thickness: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius
	mesh.rings = 32
	mesh.ring_segments = 8
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = pos
	return node


static func crate(parent: Node3D) -> Node3D:
	## Text-free industrial supply crate (Blender-authored); plain armored box if the GLB is missing.
	var packed := load(CRATE_GLB) as PackedScene
	var model: Node3D
	if packed != null:
		model = packed.instantiate() as Node3D
	else:
		push_error("Supply crate GLB missing: " + CRATE_GLB)
		model = Node3D.new()
		box(model, Vector3.ZERO, Vector3(1.8, 1.3, 1.6), metal(Color("343d48")))
	model.name = "SupplyCrate"
	parent.add_child(model)
	return model


## Non-text respawn hardware: a dark pad with a ring of segments the caller fills as cooldown drains.
static func charge_pad(parent: Node3D, y: float, segments := 12, radius := 1.45) -> Array[MeshInstance3D]:
	var pad := Node3D.new()
	pad.name = "ChargePad"
	pad.position.y = y
	parent.add_child(pad)
	cylinder(pad, Vector3.ZERO, radius + 0.18, 0.08, metal(Color("1a222b")))
	ring(pad, Vector3(0, 0.05, 0), radius + 0.15, 0.04, metal(Color("89939c")))
	var cells: Array[MeshInstance3D] = []
	for i in segments:
		var angle := TAU * i / segments
		var cell := box(pad, Vector3(sin(angle), 0.07, cos(angle)) * radius, Vector3(0.3, 0.05, 0.62), glow(Color("ffa53d")))
		cell.rotation.y = angle
		cell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cells.append(cell)
	return cells


static func rocket(parent: Node3D, accent: Color) -> void:
	var casing := metal(Color("adb5be"))
	var dark := metal(Color("252c35"))
	var painted := metal(accent.darkened(0.25))
	var body := cylinder(parent, Vector3(0, 0, 0.05), 0.19, 1.1, casing)
	body.rotation.x = PI / 2
	var nose := cylinder(parent, Vector3(0, 0, -0.7), 0.19, 0.4, dark, 0.015)
	nose.rotation.x = -PI / 2
	for z in [-0.32, 0.38]:
		var band := cylinder(parent, Vector3(0, 0, z), 0.198, 0.1, painted)
		band.rotation.x = PI / 2
	for i in range(4):
		var fin := box(parent, Vector3.ZERO, Vector3(0.06, 0.5, 0.48), dark)
		fin.rotation.z = i * PI / 2
		fin.position = Vector3(sin(i * PI / 2) * 0.23, cos(i * PI / 2) * 0.23, 0.45)
	var nozzle := cylinder(parent, Vector3(0, 0, 0.68), 0.12, 0.22, dark, 0.17)
	nozzle.rotation.x = PI / 2
	var core := cylinder(parent, Vector3(0, 0, 0.8), 0.1, 0.04, glow(Color("fff1ae"), 3))
	core.rotation.x = PI / 2


static func gun(parent: Node3D, z: float) -> void:
	var mount := box(parent, Vector3(0, 0.62, z), Vector3(0.6, 0.38, 0.65), metal(Color("333e49")))
	for x in [-0.17, 0.17]:
		var barrel := cylinder(mount, Vector3(x, 0.12, signf(z) * 0.45), 0.09, 0.9, metal(Color("68727a")))
		barrel.rotation.x = PI / 2


static func billboard(parent: Node3D, pos: Vector3, color: Color, diameter: float, smoke: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter
	node.mesh = quad
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if smoke else BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = SMOKE if smoke else SPARK
	material.albedo_color = color
	material.no_depth_test = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if smoke:
		var cloud_material := ShaderMaterial.new()
		cloud_material.shader = CLOUD
		cloud_material.set_shader_parameter("cloud", SMOKE)
		cloud_material.set_shader_parameter("tint", color)
		node.material_override = cloud_material
	else:
		node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.position = pos
	return node
