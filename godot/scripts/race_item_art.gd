## Presentation only: arcade item rules and collisions stay in RaceItems.
class_name RaceItemArt
extends Node3D

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
	return {"visual": root, "model": model, "label": label}


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
		var tracer := CombatVisuals.box(root, Vector3.ZERO, Vector3(0.07, 0.07, 2.2), CombatVisuals.glow(Color("ffe8aa"), 3))
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if direction.cross(Vector3.UP).length_squared() > 0.001:
		root.look_at(pos + direction, Vector3.UP)
	return root


func muzzle(pos: Vector3, rocket: bool) -> void:
	_sprite_effect(pos, Color("fff4cc"), 2.2 if rocket else 1.3, 0.075, Vector3.ZERO, 0.7, false)
	var light := OmniLight3D.new()
	light.light_color = Color("ffbd70")
	light.light_energy = 2.0
	light.omni_range = 7.0
	particles.back().node.add_child(light)
	_sprite_effect(pos, Color(0.4, 0.42, 0.45, 0.3), 0.7, 0.4, Vector3.UP, 2.0, true)


func trail(shot: Dictionary, delta: float) -> void:
	var visual: Node3D = shot.visual
	var velocity: Vector3 = shot.velocity
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
