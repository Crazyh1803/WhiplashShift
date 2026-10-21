## Shared seamless materials. Noise and mipmaps are generated once, no imported art.
class_name TrackMaterials
extends RefCounted

const SURFACE_SHADER := preload("res://shaders/track_surface.gdshader")
static var _noise: NoiseTexture2D
static var _materials: Dictionary = {}


static func surface(sid: int, markings: bool = false) -> ShaderMaterial:
	var key := "%d_%s" % [sid, markings]
	if _materials.has(key):
		return _materials[key]
	if _noise == null:
		var noise := FastNoiseLite.new()
		noise.seed = 41729
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.065
		noise.fractal_octaves = 3
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = noise
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("surface_noise", _noise)
	material.set_shader_parameter("surface_id", sid)
	material.set_shader_parameter("base_color", Surfaces.COLORS[sid])
	material.set_shader_parameter("road_markings", markings)
	if sid == Surfaces.Id.MUD:
		var organic := flesh()
		material.set_shader_parameter("sinew_normal", organic.normal_texture)
		material.set_shader_parameter("sinew_roughness", organic.roughness_texture)
	_materials[key] = material
	return material


## All colors are sRGB authoring values; Godot converts source colors for lighting.
static func environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("050508")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("050508")
	env.fog_light_energy = 0.0
	env.fog_sun_scatter = 0.0
	env.fog_depth_begin = 110.0
	env.fog_depth_end = 280.0
	env.fog_depth_curve = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 2.5
	return env


static func flesh() -> StandardMaterial3D:
	if _materials.has("flesh"):
		return _materials["flesh"]
	var normal := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var rough := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var u := TAU * float(x) / 128.0
			var v := TAU * float(y) / 128.0
			var phase := u * 8.0 + sin(v * 2.0) * 0.7
			var n := Vector3(cos(phase) * 0.65, cos(v * 2.0) * cos(phase) * 0.16, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
			var wet := 0.1 + (sin(phase) * 0.5 + 0.5) * 0.15
			rough.set_pixel(x, y, Color(wet, wet, wet))
	normal.generate_mipmaps()
	rough.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c44b45")
	material.metallic = 0.0
	material.roughness = 1.0 # Dedicated map supplies the calibrated 0.1–0.25 values.
	material.roughness_texture = ImageTexture.create_from_image(rough)
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.normal_enabled = true
	material.normal_texture = ImageTexture.create_from_image(normal)
	material.normal_scale = 0.8
	material.clearcoat_enabled = true
	material.clearcoat = 0.4
	material.clearcoat_roughness = 0.15
	material.subsurf_scatter_enabled = true
	material.subsurf_scatter_strength = 0.65
	material.subsurf_scatter_skin_mode = true
	_materials["flesh"] = material
	return material


## A continuous local pool keeps both reversible driving directions readable.
## No opposed cone masks, global ambient or directional sun.
static func attach_driving_light(car: Node3D) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "DrivingLightPool"
	lamp.position = Vector3(0, 2.8, 0)
	lamp.light_color = Color("d8d3c4")
	lamp.light_energy = 5.0
	lamp.omni_range = 65.0
	lamp.omni_attenuation = 1.5
	# This represents scattered local illumination, without a vehicle self-shadow wedge.
	lamp.shadow_enabled = false
	car.add_child(lamp)
