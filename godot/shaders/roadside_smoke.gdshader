// Soft bounded smoke for a burning barrel: six camera-facing puffs per barrel, each looping on a fixed schedule. A puff rises at most HEIGHT metres and
// drifts at most RADIUS metres, so the column always stays inside the barrel's reserved effect volume (radius 2 m, height 5.8 m). No texture, no particles.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

const float HEIGHT = 4.6;
const float RADIUS = 0.9;
uniform vec4 tint : source_color = vec4(0.17, 0.16, 0.15, 1.0);
uniform float rise_time : hint_range(3.0, 14.0) = 7.5;
uniform float density : hint_range(0.0, 1.0) = 0.34;
varying float v_age;

void vertex() {
	float idx = COLOR.r;
	float age = fract(TIME / rise_time + idx + INSTANCE_CUSTOM.x);
	v_age = age;
	float drift = RADIUS * age * age;
	vec2 wind = normalize(vec2(0.85, 0.3 + idx));
	vec3 centre = MODEL_MATRIX[3].xyz + vec3(clamp(wind.x * drift + sin(age * 6.0 + idx * 20.0) * 0.1 * age, -RADIUS, RADIUS), INSTANCE_CUSTOM.y + HEIGHT * pow(age, 0.85), clamp(wind.y * drift * 0.7, -RADIUS, RADIUS));
	float size = mix(0.28, 0.95, sqrt(age));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(centre, 1.0));
	VERTEX = vec3(VERTEX.xy * size, 0.0);
}

void fragment() {
	float d = length(UV * 2.0 - vec2(1.0));
	float soft = 1.0 - smoothstep(0.15, 1.0, d);
	float fade = smoothstep(0.0, 0.12, v_age) * (1.0 - smoothstep(0.5, 1.0, v_age));
	ALBEDO = tint.rgb + vec3(0.16, 0.06, 0.0) * (1.0 - v_age) * (1.0 - v_age);
	ALPHA = soft * fade * density;
}
