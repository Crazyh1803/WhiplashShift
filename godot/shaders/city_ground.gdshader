shader_type spatial;
render_mode cull_back;

uniform int surface_style = 0;
uniform int lane_axis = 0;
uniform vec2 surface_scale = vec2(1.0);
varying vec3 world_position;
varying vec2 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_position = VERTEX.xz * surface_scale;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 tile = floor(p / 2.0);
	float variation = hash(tile);
	float grain = hash(floor(p * 30.0));
	vec2 edge = min(fract(p / 2.0), 1.0 - fract(p / 2.0));
	float seams = 1.0 - smoothstep(0.006, 0.018, min(edge.x, edge.y));
	vec3 asphalt = mix(vec3(0.09, 0.105, 0.115), vec3(0.16, 0.15, 0.13), variation * 0.7);
	vec3 concrete = mix(vec3(0.25, 0.27, 0.265), vec3(0.36, 0.33, 0.27), variation);
	vec3 base = surface_style == 0 ? asphalt : concrete;
	float patches = step(0.84, hash(floor(p / vec2(5.0, 3.0))));
	base *= mix(0.82, 1.12, grain) * mix(1.0, 0.77, patches);
	float across = lane_axis == 1 ? local_position.x : local_position.y;
	float along = lane_axis == 1 ? local_position.y : local_position.x;
	float stripe = (1.0 - smoothstep(0.065, 0.1, abs(across))) * step(0.5, fract(along / 5.0));
	if (lane_axis != 0) { base = mix(base, vec3(0.48, 0.38, 0.16), stripe * (0.6 + grain * 0.25)); }
	if (surface_style != 0) { base *= 1.0 - seams * 0.38; }
	float stain = pow(hash(floor(p / 0.6)), 10.0);
	ALBEDO = base * (1.0 - stain * 0.22);
	ROUGHNESS = clamp(0.86 - patches * 0.18 + grain * 0.08, 0.4, 1.0);
	METALLIC = 0.02;
	EMISSION = ALBEDO * 0.17;
}
