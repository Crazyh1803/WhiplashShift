shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
void fragment() {
	float edge = pow(max(0.0, 1.0 - abs(UV.x - 0.5) * 2.0), 1.2);
	float tail = smoothstep(0.0, 0.25, UV.y);
	ALBEDO = mix(vec3(0.9, 0.4, 0.08), vec3(1.0, 0.85, 0.5), UV.y);
	ALPHA = edge * tail * 0.9;
}
