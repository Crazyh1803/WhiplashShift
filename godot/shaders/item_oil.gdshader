shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform float opacity = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float boundary = 0.88 + sin(angle * 5.0) * 0.06 + sin(angle * 9.0 + 1.0) * 0.035;
	float edge = 1.0 - smoothstep(boundary - 0.06, boundary, length(p));
	vec3 film = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + length(p) * 21.0 + sin(angle * 3.0) * 3.0 + TIME * 0.5);
	ALBEDO = vec3(0.012) + film * 0.065;
	EMISSION = film * 0.055;
	METALLIC = 0.8;
	ROUGHNESS = 0.15;
	ALPHA = edge * opacity * 0.96;
}
