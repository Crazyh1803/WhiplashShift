shader_type spatial;
uniform vec4 paint : source_color = vec4(0.12, 0.15, 0.18, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float grain = hash(floor(UV * vec2(700.0, 420.0)));
	float brushing = sin(UV.y * 950.0) * 0.012;
	float scratches = step(0.998, hash(floor(UV * vec2(35.0, 220.0))));
	ALBEDO = paint.rgb * (0.97 + grain * 0.06 + brushing) + scratches * 0.025;
	METALLIC = 0.72;
	ROUGHNESS = 0.38 + grain * 0.2;
}
