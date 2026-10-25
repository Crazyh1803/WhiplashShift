shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
instance uniform float impact_strength = 0.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	vec2 p = UV * vec2(48.0, 24.0);
	vec2 s = vec2(1.732, 1.0);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 cell = abs(dot(a, a) < dot(b, b) ? a : b);
	float edge = max(cell.x * 0.866 + cell.y * 0.5, cell.y);
	float hex = smoothstep(0.43, 0.48, edge);
	float pulse = 0.8 + sin(TIME * 5.0) * 0.2;
	ALBEDO = mix(vec3(0.08, 0.65, 1.2), vec3(1.6), impact_strength);
	ALPHA = (0.035 + rim * 0.65 + hex * 0.16) * pulse + impact_strength * 0.5;
}
