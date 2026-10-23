shader_type spatial;

uniform vec4 lens_color : source_color = vec4(1.0);
uniform vec4 lens_emission : source_color = vec4(1.0);
uniform sampler2D lens_texture : source_color;
uniform bool has_lens_texture = false;
uniform float lens_metallic = 0.0;
uniform float lens_roughness = 0.5;
uniform mat4 mesh_to_chassis;
uniform float active_sign = -1.0;
varying float chassis_z;

void vertex() {
	chassis_z = (mesh_to_chassis * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	ALBEDO = lens_color.rgb;
	if (has_lens_texture) {
		ALBEDO *= texture(lens_texture, UV).rgb;
	}
	METALLIC = lens_metallic;
	ROUGHNESS = lens_roughness;
	EMISSION = chassis_z * active_sign > 0.0 ? lens_emission.rgb : vec3(0.0);
}
