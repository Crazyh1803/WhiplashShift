shader_type spatial;
// Procedural cosmetic bodywork wear, drawn as a next_pass over a car's paint surfaces.
// One scalar (`wear`, the car's 0..1 damage) drives three layers: dulled scuffs from
// the first hit, bare-metal scratches soon after, and soot scorching when heavy.
// The pass is only attached while the car is damaged, so a clean car renders as before.
render_mode blend_mix, depth_draw_never, cull_back;

uniform float wear : hint_range(0.0, 1.0) = 0.0;
uniform float body_scale = 1.0;       // mesh-local units to metres, so patterns match across cars
uniform float variation = 0.0;        // per-car pattern offset
uniform bool hide_embedded_wheels = false;  // mirrors the Blackjack livery shader
uniform vec4 scuff_color : source_color = vec4(0.36, 0.31, 0.25, 1.0);
uniform vec4 metal_color : source_color = vec4(0.78, 0.76, 0.72, 1.0);
uniform vec4 soot_color : source_color = vec4(0.012, 0.010, 0.009, 1.0);
uniform vec4 ember_color : source_color = vec4(0.42, 0.15, 0.03, 1.0);

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419) + variation);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x),
		mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
		mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

// One thin, broken scratch family along a warped direction.
float scratches(vec3 q, vec3 dir, float density, float seed) {
	float coord = dot(q, dir) * density + fbm(q * 2.2 + seed) * 3.0;
	float cell = floor(coord);
	float across = abs(fract(coord) - 0.5);
	float line = 1.0 - smoothstep(0.012, 0.05, across);
	float exists = step(0.58, hash31(vec3(cell, seed, 3.7)));
	float breaks = smoothstep(0.50, 0.62, vnoise(q * 5.0 + vec3(seed * 7.0)));
	return line * exists * breaks;
}

float disc_mask(vec2 point, vec2 center, float radius, float feather) {
	return 1.0 - smoothstep(radius - feather, radius + feather, distance(point, center));
}

float range_mask(float value, float low, float high, float feather) {
	return smoothstep(low - feather, low + feather, value)
		* (1.0 - smoothstep(high - feather, high + feather, value));
}

vec4 layer_over(vec4 under, vec3 color, float alpha) {
	float out_alpha = alpha + under.a * (1.0 - alpha);
	vec3 out_color = (color * alpha + under.rgb * under.a * (1.0 - alpha)) / max(out_alpha, 0.0001);
	return vec4(out_color, out_alpha);
}

void fragment() {
	if (hide_embedded_wheels) {
		vec2 profile = model_position.xy;
		float wheel_mask = max(max(disc_mask(profile, vec2(-0.63, -0.21), 0.145, 0.018),
			disc_mask(profile, vec2(-0.28, -0.21), 0.145, 0.018)),
			disc_mask(profile, vec2(0.63, -0.22), 0.145, 0.018));
		if (wheel_mask > 0.48) {
			discard;
		}
	}

	vec3 q = model_position * body_scale;
	float scuff_amount = smoothstep(0.0, 0.45, wear);
	float scratch_amount = smoothstep(0.12, 0.6, wear);
	float scorch_amount = smoothstep(0.3, 0.85, wear);

	// Broad dulled patches, the first thing a fender-bender leaves.
	float patch_noise = fbm(q * 2.4 + 11.0);
	float scuff = smoothstep(0.64 - 0.32 * scuff_amount, 0.72 - 0.32 * scuff_amount, patch_noise);
	float grain = 0.75 + 0.25 * vnoise(q * 30.0);
	float scuff_alpha = scuff * grain * 0.62 * smoothstep(0.0, 0.06, wear);

	// Bare-metal scratches, two crossing families.
	float scratch = max(scratches(q, normalize(vec3(1.0, 0.35, 0.2)), 24.0, 1.0),
		scratches(q, normalize(vec3(0.25, -0.4, 1.0)), 19.0, 5.0));
	float scratch_alpha = scratch * scratch_amount * 0.95;

	// Soot and scorching, ringed by a heat-tinted edge.
	float soot_noise = fbm(q * 1.7 + 29.0);
	float soot_edge0 = 0.66 - 0.34 * scorch_amount;
	float soot = smoothstep(soot_edge0, soot_edge0 + 0.07, soot_noise);
	float ring = smoothstep(soot_edge0 - 0.09, soot_edge0, soot_noise) * (1.0 - soot);
	float scorch_alpha = soot * scorch_amount * 0.9;
	float ember_alpha = ring * scorch_amount * 0.55;

	vec4 layers = vec4(0.0);
	layers = layer_over(layers, scuff_color.rgb, scuff_alpha);
	layers = layer_over(layers, soot_color.rgb, scorch_alpha);
	layers = layer_over(layers, ember_color.rgb, ember_alpha);
	layers = layer_over(layers, metal_color.rgb, scratch_alpha);

	ALBEDO = layers.rgb;
	ALPHA = clamp(layers.a, 0.0, 1.0);
	METALLIC = scratch_alpha;
	ROUGHNESS = mix(0.95, 0.35, scratch_alpha);
	SPECULAR = 0.2;
}
