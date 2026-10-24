shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D cloud : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	// Face the camera while retaining each puff's animated world scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
}
void fragment() {
	vec4 tex = texture(cloud, UV);
	// The source contains both grey RGB and an opacity mask. Use opacity once,
	// preserving the cloud detail instead of multiplying it into darkness twice.
	float heat = smoothstep(0.7, 1.0, tint.r) * (1.0 - tint.b);
	ALBEDO = mix(tint.rgb * (0.6 + tex.r * 0.8), vec3(1.8, 1.3, 0.55), tex.r * heat * 0.6);
	ALPHA = pow(tex.a, 0.65) * tint.a;
}
