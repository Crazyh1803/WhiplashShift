## Presentation only: arcade item rules and collisions stay in RaceItems.
class_name RaceItemArt
extends Node3D

const TRACER = preload("res://shaders/item_tracer.gdshader")
const PLAYER_SMOKE_LAYER := 1 << 10
var streams: Array[Dictionary] = []

const SHIELD = preload("res://shaders/item_shield.gdshader")
const OIL = preload("res://shaders/item_oil.gdshader")

var particles: Array[Dictionary] = []
var clock := 0.0


func tick(delta: float) -> void:
	var dt := delta
	clock += dt
	for effect in particles.duplicate():
		if effect.get("delay", 0.0) > 0:
			effect.delay -= dt
			effect.node.visible = effect.delay <= 0
			continue
		effect.life -= dt
		if effect.life <= 0:
			effect.node.queue_free()
			particles.erase(effect)
			continue
		var fraction: float = effect.life / effect.duration
		effect.node.position += effect.velocity * dt
		effect.node.scale = Vector3.ONE * (1.0 + (1.0 - fraction) * effect.growth)
		if effect.has("material"):
			var color: Color = effect.start_color.lerp(effect.end_color, 1.0 - fraction)
			color.a *= minf(1.0, fraction * 3.0)
			if effect.material is ShaderMaterial:
				effect.material.set_shader_parameter("tint", color)
			else:
				effect.material.albedo_color = color
		else:
			effect.node.transparency = 1.0 - fraction
		if effect.get("gravity", false):
			effect.velocity.y -= dt * 12.0


func clear() -> void:
	for particle in particles:
		particle.node.queue_free()
	particles.clear()


func supply(pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var model := Node3D.new()
	root.add_child(model)
	var display := CombatVisuals.crate(model, Color("ffc34d"), "RANDOM ITEM")
	var icon := Label3D.new()
	icon.text = "?"
	icon.font_size = 110
	icon.pixel_size = 0.009
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.modulate = Color("ffe49b")
	display.add_child(icon)
	CombatVisuals.ring(root, Vector3(0, -1.35, 0), 1.55, 0.045, CombatVisuals.glow(Color("ffc34d")))
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.85
	label.font_size = 38
	label.pixel_size = 0.009
	label.modulate = Color("ffe49b")
	root.add_child(label)
	return {"visual": root, "model": model, "label": label, "icon": icon}


func projectile(pos: Vector3, direction: Vector3, id: String) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	if id in ["rockets", "homing"]:
		CombatVisuals.rocket(root, Color(ItemCatalog.DATA[id]["color"]))
	elif id == "grenades":
		CombatVisuals.cylinder(root, Vector3.ZERO, 0.24, 0.45, CombatVisuals.metal(Color("355b32")))
		CombatVisuals.box(root, Vector3(0, 0.3, 0), Vector3(0.12, 0.18, 0.2), CombatVisuals.metal(Color("8d999a")))
		CombatVisuals.box(root, Vector3(0, 0.3, 0.1), Vector3(0.1, 0.05, 0.45), CombatVisuals.metal(Color("bac0bd")))
	else:
		# A readable amber streak and solid bullet tip, without a camera-facing flare.
		var material := ShaderMaterial.new()
		material.shader = TRACER
		for angle in [0.0, PI / 2]:
			var streak := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.085, 1.5)
			streak.mesh = quad
			streak.material_override = material
			streak.basis = Basis(Vector3.FORWARD, angle) * Basis(Vector3.RIGHT, PI / 2)
			streak.scale.y = 0.001
			streak.position.z = 0.001
			streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(streak)
		var tip := CombatVisuals.cylinder(root, Vector3.ZERO, 0.028, 0.11, CombatVisuals.glow(Color("ffd786"), 0.3))
		tip.rotation.x = PI / 2
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if direction.cross(Vector3.UP).length_squared() > 0.001:
		root.look_at(pos + direction, Vector3.UP)
	root.reset_physics_interpolation()
	return root


func muzzle(pos: Vector3, rocket: bool, direction := Vector3.FORWARD) -> void:
	if rocket:
		_sprite_effect(pos, Color("fff4cc"), 2.2, 0.075, Vector3.ZERO, 0.7, false)
	else:
		# A brief forward flame cone replaces the star-shaped gun flash.
		while particles.size() >= 240:
			var oldest: Dictionary = particles.pop_front()
			oldest.node.queue_free()
		var material := CombatVisuals.glow(Color(1.0, 0.67, 0.2, 0.9), 0.4)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var flame := CombatVisuals.cylinder(self, pos + direction * 0.14, 0.075, 0.28, material, 0.015)
		flame.quaternion = Quaternion(Vector3.UP, direction.normalized())
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.append({"node": flame, "material": material, "start_color": material.albedo_color,
			"end_color": Color(1.0, 0.35, 0.06, 0.0), "life": 0.028, "duration": 0.028,
			"velocity": Vector3.ZERO, "growth": 0.2})
	var light := OmniLight3D.new()
	light.light_color = Color("ffbd70")
	light.light_energy = 2.0 if rocket else 0.7
	light.omni_range = 7.0 if rocket else 4.0
	particles.back().node.add_child(light)
	_sprite_effect(pos, Color(0.4, 0.42, 0.45, 0.3), 0.7, 0.4, Vector3.UP, 2.0, true)


func trail(shot: Dictionary, delta: float) -> void:
	var visual: Node3D = shot.visual
	var velocity: Vector3 = shot.velocity
	if shot.id == "machine_guns":
		var length := minf(1.5, float(shot.get("travel", 0.0)))
		for i in range(2):
			visual.get_child(i).scale.y = maxf(0.001, length / 1.5)
			visual.get_child(i).position.z = length * 0.5
		return
	if shot.id == "grenades":
		visual.rotate_x(delta * 5.0)
		return
	if velocity.length_squared() > 0.001:
		visual.look_at(visual.global_position + velocity, Vector3.UP)
	if not shot.id in ["rockets", "homing"]:
		return
	shot["trail_time"] = float(shot.get("trail_time", 0.0)) - delta
	if shot.trail_time > 0:
		return
	shot.trail_time = 0.04
	var tail: Vector3 = shot.pos - velocity.normalized() * 0.85
	_sprite_effect(tail, Color("ffb950"), 0.8, 0.12, -velocity.normalized(), 0.3, false)
	_sprite_effect(tail, Color(0.4, 0.42, 0.45, 0.45), 0.65, 0.9, Vector3.UP * 0.8, 3.0, true)


func _sprite_effect(pos: Vector3, color: Color, diameter: float, duration: float, velocity: Vector3,
	growth: float, smoke: bool, delay := 0.0) -> void:
	while particles.size() >= 240:
		var oldest: Dictionary = particles.pop_front()
		oldest.node.queue_free()
	var node := CombatVisuals.billboard(self, pos, color, diameter, smoke)
	var material: Material = node.material_override
	var end_color := color
	if smoke and color.r > 0.8:
		end_color = Color(0.2, 0.16, 0.12, 0.2)
	node.visible = delay <= 0
	particles.append({"node": node, "material": material, "start_color": color, "end_color": end_color,
		"life": duration, "duration": duration, "velocity": velocity, "growth": growth, "delay": delay})


func _effect(pos: Vector3, color: Color, size: float, duration: float, velocity: Vector3, growth: float) -> void:
	_sprite_effect(pos, color, size * 2.0, duration, velocity, growth, false)


func burst(pos: Vector3, color: Color, count: int, explosion: bool) -> void:
	if explosion:
		_sprite_effect(pos, Color("fff4d0"), 6.0, 0.1, Vector3.ZERO, 1.0, false)
		var light := OmniLight3D.new()
		light.light_color = Color("ffb359")
		light.light_energy = 5.0
		light.omni_range = 18.0
		particles.back().node.add_child(light)
		for i in range(9):
			var offset := Vector3(sin(i * 2.4), float(i % 3) * 0.5, cos(i * 2.4))
			_sprite_effect(pos + offset * 0.4, Color(1.0, 0.37 + i * 0.04, 0.06, 0.95),
				3.5, 0.7, offset * 2.5 + Vector3.UP, 1.8, true)
			_sprite_effect(pos + offset, Color(0.25, 0.27, 0.29, 0.65),
				2.0, 1.7, offset * 1.5 + Vector3.UP * 2.4, 2.8, true, 0.12)
		# Ground shockwave is a fading, expanding ring rather than a solid sphere.
		var material := CombatVisuals.glow(Color(1, 0.62, 0.2, 0.7))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		while particles.size() >= 240:
			var oldest: Dictionary = particles.pop_front()
			oldest.node.queue_free()
		var ring := CombatVisuals.ring(self, pos, 1.0, 0.05, material)
		particles.append({"node": ring, "material": material, "start_color": material.albedo_color,
			"end_color": Color(0.35, 0.3, 0.25, 0), "life": 0.5, "duration": 0.5,
			"velocity": Vector3.ZERO, "growth": 11.0})
	else:
		_sprite_effect(pos, color.lightened(0.4), 1.2, 0.1, Vector3.ZERO, 1.0, false)
	for i in range(count):
		var velocity := Vector3(sin(i * 2.4), 0.5 + float(i % 3) * 0.4, cos(i * 2.4)) * (13 if explosion else 5)
		_sprite_effect(pos, color, 0.2, 0.6, velocity, 0.0, false)
		particles.back()["gravity"] = true


func shield(pos: Vector3, radius: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 40
	sphere.rings = 20
	visual.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = SHIELD
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	visual.global_position = pos
	return visual


func update_shield(visual: MeshInstance3D, pos: Vector3, delta: float) -> void:
	visual.global_position = pos
	var strength := maxf(0, float(visual.get_meta("impact", 0.0)) - delta * 3)
	visual.set_meta("impact", strength)
	visual.set_instance_shader_parameter("impact_strength", strength)


func shield_hit(visual: MeshInstance3D) -> void:
	visual.set_meta("impact", 1.0)
	visual.set_instance_shader_parameter("impact_strength", 1.0)


func gun_mounts(car: Vehicle) -> Dictionary:
	return ItemWeaponMounts.create(car)


func casing(pos: Vector3, velocity: Vector3) -> void:
	while particles.size() >= 240:
		var oldest: Dictionary = particles.pop_front()
		oldest.node.queue_free()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d6ad5d")
	material.metallic = 0.8
	material.roughness = 0.3
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var node := CombatVisuals.cylinder(self, pos, 0.045, 0.18, material)
	node.rotation.z = 0.6
	particles.append({"node": node, "material": material, "start_color": material.albedo_color,
		"end_color": material.albedo_color, "life": 0.65, "duration": 0.65, "velocity": velocity,
		"growth": 0.0, "gravity": true})


func hazard(pos: Vector3, id: String, normal: Vector3, owner := -1) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	if id == "smoke":
		for i in range(7):
			var offset := Vector3(sin(i * 2.4) * 1.7, float(i % 3) * 0.7 - 0.5, cos(i * 2.4) * 1.7)
			var puff := CombatVisuals.billboard(root, offset, Color(0.48, 0.5, 0.53, 0.92), 6.0, true)
			puff.set_meta("origin", offset)
			if owner == 0:
				puff.layers = PLAYER_SMOKE_LAYER
	else:
		var slick := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(7, 7)
		slick.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = OIL
		slick.material_override = material
		slick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(slick)
		root.quaternion = Quaternion(Vector3.UP, normal.normalized())
	return root


func animate_hazard(entry: Dictionary) -> void:
	var root: Node3D = entry.visual
	var fade := minf(1, float(entry.life))
	if entry.id == "smoke":
		var age := 5.0 - float(entry.life)
		for i in root.get_child_count():
			var puff := root.get_child(i) as MeshInstance3D
			var origin: Vector3 = puff.get_meta("origin")
			puff.position = origin + Vector3(sin(age + i) * 0.2, sin(age * 0.7 + i) * 0.25, cos(age + i) * 0.2)
			puff.scale = Vector3.ONE * (0.85 + minf(age, 1.5) * 0.12)
			puff.material_override.set_shader_parameter("tint", Color(0.48, 0.5, 0.53, 0.92 * fade))
	else:
		root.get_child(0).material_override.set_shader_parameter("opacity", fade)


func conceal_supply(pickup: Dictionary) -> void:
	# All items share the same public presentation until collection.
	pickup["label"].text = "MYSTERY ITEM"
	pickup["label"].modulate = Color("ffe49b")
	pickup["icon"].text = "?"
	pickup["icon"].modulate = Color("ffe49b")


func prepare_streams(car: Vehicle, owner := -1) -> void:
	var pair := {}
	for id in ["smoke", "oil"]:
		var emitter := CPUParticles3D.new()
		emitter.name = "ItemStream" + id.capitalize()
		emitter.emitting = false
		emitter.local_coords = false
		emitter.amount = 32 if id == "smoke" else 24
		if id == "smoke" and owner == 0:
			emitter.layers = PLAYER_SMOKE_LAYER
		emitter.lifetime = 0.8 if id == "smoke" else 0.28
		emitter.direction = Vector3(0, 0.2 if id == "smoke" else -0.2, -1)
		emitter.spread = 16 if id == "smoke" else 6
		emitter.initial_velocity_min = 2.0
		emitter.initial_velocity_max = 4.0
		emitter.gravity = Vector3(0, 0.8 if id == "smoke" else -14.0, 0)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		if id == "smoke":
			var quad := QuadMesh.new()
			quad.size = Vector2(1.5, 1.5)
			emitter.mesh = quad
			material.albedo_texture = CombatVisuals.SMOKE
			material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			emitter.scale_amount_min = 0.5
			emitter.scale_amount_max = 1.5
		else:
			var drop := SphereMesh.new()
			drop.radius = 0.055
			drop.height = 0.11
			drop.radial_segments = 8
			drop.rings = 4
			emitter.mesh = drop
			material.albedo_color = Color("12131a")
			material.metallic = 0.7
			material.roughness = 0.16
		emitter.material_override = material
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.7, 0.72, 0.75, 0.9) if id == "smoke" else Color.WHITE)
		ramp.set_color(1, Color(0.4, 0.42, 0.45, 0.0))
		emitter.color_ramp = ramp
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(emitter)
		pair[id] = emitter
	streams.append(pair)


func sync_streams(cars: Array[Vehicle], active: Array[String]) -> void:
	for i in cars.size():
		var rear := -cars[i].forward_vector().normalized()
		for id: String in streams[i]:
			var emitter: CPUParticles3D = streams[i][id]
			emitter.global_position = cars[i].global_position + rear * (cars[i].tuning.body_length * 0.5 + 0.3) + Vector3.UP * 0.3
			emitter.look_at(emitter.global_position + rear, Vector3.UP)
			emitter.emitting = active[i] == id


func stop_stream(index: int) -> void:
	if index >= streams.size():
		return
	for emitter: CPUParticles3D in streams[index].values():
		emitter.emitting = false


func clear_streams() -> void:
	for pair in streams:
		for emitter: CPUParticles3D in pair.values():
			if is_instance_valid(emitter):
				emitter.queue_free()
	streams.clear()
