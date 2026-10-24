shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	float edge = pow(max(0.0, 1.0 - abs(UV.x - 0.5) * 2.0), 1.8);
	float tail = pow(UV.y, 1.5);
	ALBEDO = mix(vec3(1.0, 0.35, 0.05), vec3(1.7, 1.5, 1.0), UV.y);
	ALPHA = edge * tail * 0.8;
}
