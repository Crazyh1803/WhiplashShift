shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.1, 0.7, 1.0, 1.0);
varying vec3 local_vertex;
void vertex() { local_vertex = VERTEX; }
void fragment() {
	float scan = 0.45 + 0.55 * smoothstep(0.2, 0.6, sin(local_vertex.y * 90.0 - TIME * 5.0));
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	ALBEDO = tint.rgb * (1.1 + rim);
	ALPHA = tint.a * (0.3 + rim * 0.5) * scan;
}
