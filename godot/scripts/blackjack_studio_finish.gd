extends RefCounted

# Neutral HDR softboxes supply reflections even with a flat-color background.
# No vehicle textures, save data or protected-material overrides are altered.
static var _studio_sky: Sky
const SOFTBOXES: Array[Vector4] = [Vector4(.24,.17,.18,.055),Vector4(.03,.40,.025,.16),Vector4(.56,.38,.035,.17),Vector4(.82,.36,.025,.15)]


static func environment(background: Color) -> Environment:
	var result:=Environment.new()
	result.background_mode=Environment.BG_COLOR
	result.background_color=background
	result.sky=reflection_sky()
	result.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	result.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	result.ambient_light_color=Color("e8edf0")
	result.ambient_light_energy=.30
	result.tonemap_mode=Environment.TONE_MAPPER_AGX
	result.ssao_enabled=true
	result.ssao_radius=.16
	result.ssao_intensity=1.15
	return result


static func reflection_sky() -> Sky:
	if _studio_sky!=null:
		return _studio_sky
	var panorama:=Image.create(256,128,false,Image.FORMAT_RGBAH)
	for y in range(128):
		var v: float=(y+.5)/128.0
		for x in range(256):
			var u: float=(x+.5)/256.0
			var energy: float=.035+.13*pow(1-v,2)
			for box: Vector4 in SOFTBOXES:
				var distance: float=absf(u-box.x)
				distance=minf(distance,1-distance)
				energy+=3.2*exp(-pow(distance/box.z,4)-pow((v-box.y)/box.w,4))
			panorama.set_pixel(x,y,Color(energy,energy,energy,1))
	var material:=PanoramaSkyMaterial.new()
	material.panorama=ImageTexture.create_from_image(panorama)
	_studio_sky=Sky.new()
	_studio_sky.sky_material=material
	_studio_sky.radiance_size=Sky.RADIANCE_SIZE_256
	_studio_sky.process_mode=Sky.PROCESS_MODE_QUALITY
	return _studio_sky
