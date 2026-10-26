shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float grain = fract(sin(dot(floor(world_pos.xz * 25.0), vec2(127.1, 311.7))) * 43758.5453);
	float edge = abs(UV.x - 0.5) * 2.0;
	float feather = 1.0 - smoothstep(0.78, 1.0, edge);
	float scuff = 0.7 + 0.3 * grain;
	ALBEDO = mix(vec3(0.012, 0.015, 0.018), vec3(0.06, 0.065, 0.07), smoothstep(0.6, 0.9, edge) * smoothstep(0.4, 0.8, grain));
	ALPHA = COLOR.a * feather * scuff;
}
