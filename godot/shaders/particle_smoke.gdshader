shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D cloud : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
// Owner-only sight corridor: 0 leaves rival smoke fully dense.
uniform float protect = 0.0;
uniform vec3 eye = vec3(0.0);
uniform vec3 focus = vec3(0.0);
uniform float corridor_near = 2.1;
uniform float corridor_far = 0.9;
uniform float near_clear = 4.5;
varying vec3 world_pos;
void vertex() {
	// Face the camera while retaining each puff's animated world scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
	world_pos = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec4 tex = texture(cloud, UV);
	// The source contains both grey RGB and an opacity mask. Use opacity once,
	// preserving the cloud detail instead of multiplying it into darkness twice.
	vec4 col = tint * COLOR;
	float heat = smoothstep(0.7, 1.0, col.r) * (1.0 - col.b);
	ALBEDO = mix(col.rgb * (0.6 + tex.r * 0.8), vec3(1.8, 1.3, 0.55), tex.r * heat * 0.6);
	float a = pow(tex.a, 0.65) * col.a;
	if (protect > 0.0) {
		// Per-pixel distance to the camera->car line, narrowing toward the car
		// so the plume still visibly leaves the bumper; plus a near-lens clear.
		vec3 axis = focus - eye;
		float len2 = max(dot(axis, axis), 0.0001);
		float t = clamp(dot(world_pos - eye, axis) / len2, 0.0, 1.0);
		float dist = length(world_pos - (eye + axis * t));
		float radius = mix(corridor_near, corridor_far, smoothstep(0.0, 1.0, t));
		float clear = smoothstep(radius * 0.55, radius * 1.3, dist);
		clear *= smoothstep(near_clear * 0.35, near_clear, length(world_pos - eye));
		a *= mix(1.0, clear, protect);
	}
	ALPHA = a;
}
