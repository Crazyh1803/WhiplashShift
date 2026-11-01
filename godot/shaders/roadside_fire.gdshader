// Contained barrel flame and the warm ground pool it throws. No texture, no light node: additive procedural noise on three crossed quads and one ground disc.
// Everything is bounded by geometry: the flame is a 0.9 m tall quad set and the pool a 2 m radius disc, so the effect volume never exceeds the barrel's reserved box.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform float mode = 0.0;            // 0 = flame, 1 = ground pool
uniform float intensity : hint_range(0.2, 3.0) = 1.5;
varying float v_phase;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
	if (mode < 0.5) {
		float t = TIME * 6.0 + v_phase * 40.0;
		float h = UV.y;
		VERTEX.x += sin(t + h * 5.0) * 0.05 * h;
		VERTEX.z += cos(t * 1.3 + h * 4.0) * 0.04 * h;
		VERTEX.y = VERTEX.y * (0.92 + 0.1 * sin(t * 1.7 + v_phase * 10.0)) + INSTANCE_CUSTOM.y;     // custom.y = coal-bed height above the barrel foot
	}
}

void fragment() {
	if (mode < 0.5) {
		vec2 uv = UV;
		float w = abs(uv.x - 0.5) * 2.0;
		float n = vnoise(vec2(uv.x * 4.0 + v_phase * 7.0, uv.y * 3.0 - TIME * 2.4));
		float limit = mix(0.95, 0.1, pow(uv.y, 0.8)) + (n - 0.5) * 0.3 * uv.y;
		float body = smoothstep(limit, limit * 0.35, w);
		float tip = 1.0 - smoothstep(0.5, 1.0, uv.y + (n - 0.5) * 0.35);
		vec3 hot = vec3(1.0, 0.92, 0.55);
		vec3 cool = vec3(1.0, 0.32, 0.05);
		ALBEDO = mix(hot, cool, clamp(uv.y * 1.25, 0.0, 1.0)) * intensity;
		ALPHA = clamp(body * tip, 0.0, 1.0);
	} else {
		float d = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
		float flicker = 0.78 + 0.22 * sin(TIME * 7.0 + v_phase * 20.0) + 0.1 * (vnoise(vec2(TIME * 3.0, v_phase * 9.0)) - 0.5);
		ALBEDO = vec3(1.0, 0.42, 0.1) * 0.45 * flicker * intensity;
		ALPHA = pow(1.0 - d, 2.2);
	}
}
