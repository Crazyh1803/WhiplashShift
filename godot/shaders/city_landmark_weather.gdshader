// Converted-city weathering for the original landmark meshes (exchange hall, pump citadel, relay tower): the kit panel look plus deterministic procedural
// grime, a ground splash band, vertical rain streaks, rust bleed near the base and panel seams. No texture and no clock input: the result is identical every frame.
shader_type spatial;
render_mode specular_toon, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.23, 0.27, 0.32, 1.0);
uniform float metalness : hint_range(0.0, 1.0) = 0.25;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.55;
uniform float readability : hint_range(0.0, 1.0) = 0.35;
uniform float weather : hint_range(0.0, 1.0) = 0.85;
uniform float rust : hint_range(0.0, 1.0) = 0.4;
varying vec3 world_normal;
varying vec3 local_pos;
varying vec3 world_pos;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.15;
}

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float key = dot(n, normalize(vec3(-0.35, 0.8, 0.5)));
	float band = key > 0.45 ? 1.0 : (key > -0.2 ? 0.68 : 0.38);
	float vertical_face = 1.0 - abs(n.y);
	float height = max(local_pos.y, 0.0);
	float broad = fbm(world_pos * 0.22);
	float streak = fbm(vec3(world_pos.x * 1.5 + world_pos.z * 1.1, world_pos.y * 0.1, world_pos.z * 1.5 - world_pos.x * 1.1));
	float grime = (1.0 - smoothstep(0.0, 3.6, height)) * 0.55 + vertical_face * smoothstep(0.38, 0.8, streak) * 0.38 + (broad - 0.5) * 0.4;
	vec2 g = abs(n.x) > abs(n.z) ? vec2(local_pos.z, local_pos.y) : vec2(local_pos.x, local_pos.y);
	vec2 f = abs(fract(g / vec2(2.8, 2.4)) - 0.5);
	float seam = clamp(step(0.488, f.x) + step(0.484, f.y), 0.0, 1.0) * step(0.8, vertical_face);
	vec3 col = base_color.rgb * (1.0 - weather * clamp(grime, 0.0, 0.75) * 0.62);
	float rust_mask = rust * (1.0 - smoothstep(0.0, 7.0, height)) * smoothstep(0.35, 0.75, fbm(world_pos * 0.7));
	col = mix(col, col * vec3(1.55, 0.78, 0.45), rust_mask * weather);
	col *= 1.0 - weather * 0.33 * seam;
	ALBEDO = col;
	METALLIC = metalness * (1.0 - 0.45 * weather * clamp(grime, 0.0, 1.0));
	ROUGHNESS = min(1.0, surface_roughness + 0.25 * weather * clamp(grime, 0.0, 1.0));
	EMISSION = col * readability * 0.78 * band;
}
