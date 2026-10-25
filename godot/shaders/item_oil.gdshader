shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform float opacity = 1.0;

float pool_height(vec2 p) {
	// Slow, low-amplitude concentric swells around two off-centre points.
	float h = sin(length(p - vec2(0.18, -0.1)) * 17.0 - TIME * 0.9);
	h += sin(length(p + vec2(0.3, 0.22)) * 23.0 - TIME * 0.7) * 0.6;
	return h * (1.0 - length(p) * 0.5);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float boundary = 0.88 + sin(angle * 5.0) * 0.06 + sin(angle * 9.0 + 1.0) * 0.035;
	float r = length(p);
	float edge = 1.0 - smoothstep(boundary - 0.06, boundary, r);
	float rim = smoothstep(boundary - 0.2, boundary - 0.03, r);
	float e = 0.01;
	vec2 grad = vec2(pool_height(p + vec2(e, 0.0)) - pool_height(p - vec2(e, 0.0)),
		pool_height(p + vec2(0.0, e)) - pool_height(p - vec2(0.0, e))) / (2.0 * e);
	// Thicker, flatter rim: ripples calm toward the edge where oil bunches up.
	NORMAL_MAP = vec3(0.5 + grad * 0.012 * (1.0 - rim * 0.7), 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = vec3(0.004, 0.004, 0.005);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ROUGHNESS = mix(0.05, 0.12, rim);
	ALPHA = edge * opacity * 0.97;
}
