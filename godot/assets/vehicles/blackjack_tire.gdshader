shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 tire_color : source_color = vec4(0.018, 0.022, 0.026, 1.0);
uniform float tread_scale : hint_range(0.5, 2.0) = 1.0;

void fragment() {
	float phase_a = (UV.x * 42.0 * tread_scale + UV.y * 8.0) * PI;
	float phase_b = (UV.x * 42.0 * tread_scale - UV.y * 8.0) * PI;
	float diagonal_a = 1.0 - smoothstep(0.06, 0.20, abs(sin(phase_a)));
	float diagonal_b = 1.0 - smoothstep(0.06, 0.20, abs(sin(phase_b)));
	float center_groove = 1.0 - smoothstep(0.016, 0.038, abs(UV.y - 0.5));
	float shoulder = smoothstep(0.10, 0.22, UV.y)
		* (1.0 - smoothstep(0.78, 0.90, UV.y));
	float tread = max(max(diagonal_a, diagonal_b) * shoulder, center_groove);
	float sidewall_band = smoothstep(0.012, 0.035, abs(sin(UV.y * 6.0 * PI)));
	float rubber_variation = 0.94 + 0.035 * sin(UV.x * 96.0 * PI);

	vec3 rubber = tire_color.rgb * rubber_variation;
	rubber = mix(rubber * (0.91 + 0.04 * sidewall_band), rubber * 0.52, tread);
	ALBEDO = rubber;
	ROUGHNESS = mix(0.88, 0.97, tread);
	METALLIC = 0.0;

	vec2 slope = vec2(
		(cos(phase_a) + cos(phase_b)) * shoulder,
		(cos(phase_a) - cos(phase_b)) * shoulder
	) * 0.075;
	vec3 tread_normal = normalize(vec3(slope, 1.0));
	NORMAL_MAP = tread_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.62;
}
