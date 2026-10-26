shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float edge = abs(UV.x - 0.5) * 2.0;
	float feather = 1.0 - smoothstep(0.78, 1.0, edge);
	float scuff = 0.85 + 0.15 * sin(UV.y * 91.0 + sin(UV.x * 53.0));
	ALBEDO = mix(vec3(0.025, 0.029, 0.035), vec3(0.13, 0.14, 0.15), smoothstep(0.55, 0.9, edge));
	ALPHA = COLOR.a * feather * scuff;
}
