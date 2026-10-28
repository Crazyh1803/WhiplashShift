shader_type spatial;
render_mode specular_toon;

uniform vec4 base_color : source_color = vec4(0.23, 0.27, 0.32, 1.0);
uniform float metalness : hint_range(0.0, 1.0) = 0.25;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.55;
uniform float readability : hint_range(0.0, 1.0) = 0.35;
varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float key = dot(n, normalize(vec3(-0.35, 0.8, 0.5)));
	float band = key > 0.45 ? 1.0 : (key > -0.2 ? 0.68 : 0.38);
	ALBEDO = base_color.rgb;
	METALLIC = metalness;
	ROUGHNESS = surface_roughness;
	EMISSION = base_color.rgb * readability * band;
}
