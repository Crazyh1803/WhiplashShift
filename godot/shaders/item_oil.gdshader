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
	// Meniscus: a raised lip tilts the normal outward then back across the edge band,
	// so glancing light catches a thin bright curve around the puddle.
	float lip = smoothstep(boundary - 0.28, boundary - 0.1, r) * (1.0 - smoothstep(boundary - 0.1, boundary, r));
	vec2 radial = p / max(r, 0.001);
	vec2 tilt = grad * 0.02 * (1.0 - rim * 0.6) + radial * lip * 0.3;
	NORMAL_MAP = vec3(0.5 + tilt, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = vec3(0.004, 0.004, 0.005);
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = mix(0.04, 0.09, rim);
	// Glassy wet coat over the black body; reflection only, no tint or emission.
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
	ALPHA = edge * opacity * 0.97;
}
