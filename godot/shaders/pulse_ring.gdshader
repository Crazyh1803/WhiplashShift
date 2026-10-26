shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float ring = smoothstep(0.90, 0.93, r) * (1.0 - smoothstep(0.99, 1.0, r));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * ring;
}
