shader_type spatial;
render_mode cull_back;

uniform int surface_style = 0;
uniform int lane_axis = 0;
uniform vec2 surface_scale = vec2(1.0);
uniform bool parking_bays = false;
varying vec3 world_position;
varying vec2 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_position = VERTEX.xz * surface_scale;
}

void fragment() {
	vec2 p = world_position.xz;
	float variation = noise(p * 0.17);
	float grain = noise(p * 17.0);
	vec2 slab_size = surface_style == 1 ? vec2(2.0) : vec2(6.0, 4.0);
	vec2 edge = min(fract(p / slab_size), 1.0 - fract(p / slab_size)) * slab_size;
	float seams = 1.0 - smoothstep(0.008, 0.025, min(edge.x, edge.y));
	vec3 asphalt = mix(vec3(0.035, 0.042, 0.046), vec3(0.064, 0.060, 0.050), variation);
	vec3 concrete = mix(vec3(0.15, 0.165, 0.16), vec3(0.20, 0.185, 0.15), variation);
	vec3 base = surface_style == 0 ? asphalt : concrete;
	if (surface_style == 3) { base = mix(vec3(0.04, 0.036, 0.025), vec3(0.065, 0.059, 0.04), variation); }
	float patches = smoothstep(0.57, 0.75, noise(p * 0.48));
	base *= mix(0.94, 1.04, grain) * mix(1.0, 0.82, patches);
	float across = lane_axis == 1 ? local_position.x : local_position.y;
	float along = lane_axis == 1 ? local_position.y : local_position.x;
	float stripe = (1.0 - smoothstep(0.065, 0.1, abs(across))) * step(0.5, fract(along / 5.0));
	if (lane_axis != 0) { base = mix(base, vec3(0.48, 0.38, 0.16), stripe * (0.6 + grain * 0.25)); }
	if (surface_style == 1 || surface_style == 2) { base *= 1.0 - seams * 0.25; }
	if (parking_bays && local_position.y > 11.0) {
		float bay = abs(fract(local_position.x / 5.0 + 0.5) - 0.5) * 5.0;
		float paint = 1.0 - smoothstep(0.035, 0.065, bay);
		paint = max(paint, 1.0 - smoothstep(0.035, 0.065, abs(local_position.y - 17.5)));
		base = mix(base, vec3(0.32, 0.28, 0.18), paint * smoothstep(0.3, 0.7, grain));
	}
	float stain = smoothstep(0.62, 0.85, noise(p * 1.2));
	ALBEDO = base * (1.0 - stain * 0.22);
	ROUGHNESS = clamp(0.86 - patches * 0.18 + grain * 0.08, 0.4, 1.0);
	METALLIC = 0.02;
	EMISSION = ALBEDO * 0.17;
}
