## Reusable combat art. Materials and textures are shared; transient nodes are bounded by Combat.
class_name CombatVisuals
extends RefCounted

const SMOKE = preload("res://assets/vfx/smoke.png")
const SPARK = preload("res://assets/vfx/spark.png")
const METAL = preload("res://shaders/crate_metal.gdshader")
const CLOUD = preload("res://shaders/particle_smoke.gdshader")
const HOLOGRAM = preload("res://shaders/hologram.gdshader")


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


static func crate(parent: Node3D, color: Color, title: String) -> Node3D:
	var armor := metal(Color("343d48"))
	var steel := metal(Color("89939c"))
	var dark := metal(Color("111a22"))
	var luminous := glow(color)
	box(parent, Vector3.ZERO, Vector3(1.75, 1.25, 1.55), armor)
	box(parent, Vector3(0, 0.65, 0), Vector3(1.85, 0.12, 1.65), steel)
	box(parent, Vector3(0, -0.65, 0), Vector3(1.85, 0.12, 1.65), dark)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			# Armored corners and bright inlaid status strips.
			box(parent, Vector3(x * 0.82, 0, z * 0.72), Vector3(0.28, 1.4, 0.28), steel)
			box(parent, Vector3(x * 0.83, 0.0, z * 0.875), Vector3(0.11, 0.85, 0.035), luminous)
	for z in [-1.0, 1.0]:
		box(parent, Vector3(0, 0, z * 0.79), Vector3(1.22, 0.93, 0.06), dark)
		for i in range(5):
			box(parent, Vector3(-0.46 + i * 0.23, -0.34, z * 0.83), Vector3(0.13, 0.07, 0.02), luminous)
		var label := Label3D.new()
		label.text = title + "\nWS / SUPPLY"
		label.font_size = 40
		label.pixel_size = 0.005
		label.modulate = color.lightened(0.35)
		label.position = Vector3(0, 0.1, z * 0.85)
		if z < 0:
			label.rotation.y = PI
		parent.add_child(label)
	for x in [-1.0, 1.0]:
		box(parent, Vector3(x * 0.9, 0, 0), Vector3(0.05, 0.85, 1.05), dark)
		for i in range(4):
			box(parent, Vector3(x * 0.94, -0.22 + i * 0.15, 0), Vector3(0.035, 0.045, 0.7), steel)
	cylinder(parent, Vector3(0, 0.76, 0), 0.55, 0.13, dark)
	ring(parent, Vector3(0, 0.84, 0), 0.57, 0.07, luminous)
	# The projector has a translucent cone and a counter-rotating halo.
	var holo := hologram(Color(color.r, color.g, color.b, 0.3))
	cylinder(parent, Vector3(0, 1.35, 0), 0.35, 1.0, holo, 0.72)
	var display := Node3D.new()
	parent.add_child(display)
	display.position.y = 1.8
	display.name = "HolographicDisplay"
	ring(parent, Vector3(0, -0.92, 0), 1.2, 0.025, luminous)
	for x in [-0.5, 0.5]:
		cylinder(parent, Vector3(x, -0.78, 0), 0.17, 0.15, luminous)
	return display


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
