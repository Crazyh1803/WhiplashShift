shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D source_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D source_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D source_orm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 primary_color : source_color = vec4(0.31, 0.82, 1.0, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.035, 0.055, 0.075, 1.0);
uniform vec4 glass_color : source_color = vec4(0.018, 0.07, 0.10, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform vec4 trim_color : source_color = vec4(0.025, 0.032, 0.038, 1.0);
uniform vec4 detail_metal_color : source_color = vec4(0.31, 0.35, 0.38, 1.0);
uniform vec4 mirror_color : source_color = vec4(0.62, 0.70, 0.74, 1.0);
uniform vec4 grille_color : source_color = vec4(0.018, 0.022, 0.024, 1.0);
uniform vec4 exhaust_color : source_color = vec4(0.075, 0.082, 0.088, 1.0);
uniform vec4 headlight_color : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform vec4 taillight_color : source_color = vec4(0.72, 0.025, 0.012, 1.0);
uniform bool hide_embedded_wheels = false;

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

float disc_mask(vec2 point, vec2 center, float radius, float feather) {
	return 1.0 - smoothstep(radius - feather, radius + feather, distance(point, center));
}

float range_mask(float value, float low, float high, float feather) {
	return smoothstep(low - feather, low + feather, value)
		* (1.0 - smoothstep(high - feather, high + feather, value));
}

void fragment() {
	vec3 baked_albedo = texture(source_albedo, UV).rgb;
	vec3 baked_normal = texture(source_normal, UV).rgb;
	vec3 orm = texture(source_orm, UV).rgb;
	vec2 profile = model_position.xy;
	vec3 surface_normal = normalize(model_normal);
	float side_face = smoothstep(0.72, 0.94, abs(surface_normal.z));
	float top_face = smoothstep(0.48, 0.84, surface_normal.y);
	float end_face = smoothstep(0.62, 0.90, abs(surface_normal.x));

	float wheel_a = disc_mask(profile, vec2(-0.63, -0.21), 0.145, 0.018);
	float wheel_b = disc_mask(profile, vec2(-0.28, -0.21), 0.145, 0.018);
	float wheel_c = disc_mask(profile, vec2(0.63, -0.22), 0.145, 0.018);
	float wheel_mask = max(max(wheel_a, wheel_b), wheel_c);
	float hub_a = disc_mask(profile, vec2(-0.63, -0.21), 0.078, 0.012);
	float hub_b = disc_mask(profile, vec2(-0.28, -0.21), 0.078, 0.012);
	float hub_c = disc_mask(profile, vec2(0.63, -0.22), 0.078, 0.012);
	float hub_mask = max(max(hub_a, hub_b), hub_c) * side_face;
	if (hide_embedded_wheels && wheel_mask > 0.48) {
		discard;
	}

	// The windshields are sloped, not side-facing. Exclude only truly horizontal
	// roof polygons so the complete glass aperture stays out of the paint mask.
	float window_surface = 1.0 - smoothstep(0.82, 0.97, surface_normal.y);
	float truck_window = range_mask(profile.x, -0.82, -0.25, 0.025)
		* range_mask(profile.y, 0.035, 0.235, 0.018) * window_surface;
	float sport_window = range_mask(profile.x, 0.02, 0.52, 0.025)
		* range_mask(profile.y, 0.015, 0.18, 0.018) * window_surface;
	float glass_mask = clamp(max(truck_window, sport_window), 0.0, 1.0);

	// Paint is deliberately limited to broad sheet-metal zones. Everything else
	// keeps a fixed production material so a custom color still reads as a car.
	float truck_door = range_mask(profile.x, -0.80, -0.27, 0.025)
		* range_mask(profile.y, -0.145, 0.038, 0.018) * side_face;
	float sport_door = range_mask(profile.x, 0.015, 0.50, 0.025)
		* range_mask(profile.y, -0.145, 0.018, 0.018) * side_face;
	float sport_hood_side = range_mask(profile.x, 0.50, 0.84, 0.025)
		* range_mask(profile.y, -0.115, 0.105, 0.016) * side_face;
	float sport_nose = range_mask(profile.x, 0.72, 1.01, 0.018)
		* range_mask(profile.y, -0.105, 0.145, 0.016)
		* max(max(side_face, top_face), end_face);
	float truck_nose = range_mask(profile.x, -1.01, -0.71, 0.018)
		* range_mask(profile.y, -0.105, 0.205, 0.016)
		* max(max(side_face, top_face), end_face);
	float roof_panel = range_mask(profile.x, -0.73, 0.43, 0.035)
		* range_mask(profile.y, 0.075, 0.31, 0.025) * top_face;
	float hood_panel = range_mask(profile.x, 0.38, 0.99, 0.018)
		* range_mask(profile.y, -0.115, 0.205, 0.018) * top_face;
	float truck_hood_panel = range_mask(profile.x, -1.0, -0.67, 0.018)
		* range_mask(profile.y, -0.10, 0.235, 0.018) * top_face;
	float paint_candidate = clamp(
		max(
			max(max(truck_door, sport_door), max(sport_hood_side, roof_panel)),
			max(max(hood_panel, truck_hood_panel), max(sport_nose, truck_nose))
		),
		0.0, 1.0
	);

	float lower_trim = (1.0 - smoothstep(-0.15, -0.085, profile.y)) * (1.0 - wheel_mask);
	float front_end = range_mask(profile.x, 0.82, 1.02, 0.025);
	float rear_end = range_mask(profile.x, -1.02, -0.84, 0.025);
	float end_hardware = clamp(max(front_end, rear_end) * max(side_face, end_face), 0.0, 1.0);
	float grille_mask = max(front_end, rear_end)
		* range_mask(profile.y, -0.145, -0.015, 0.018) * max(side_face, end_face);
	float bumper_mask = end_hardware
		* range_mask(profile.y, -0.16, -0.075, 0.014) * (1.0 - grille_mask);
	float center_stack = range_mask(profile.x, -0.22, -0.08, 0.018)
		* range_mask(profile.y, 0.02, 0.34, 0.022);
	float side_exhaust = range_mask(profile.x, -0.20, 0.34, 0.022)
		* range_mask(profile.y, -0.175, -0.105, 0.014) * side_face;
	float exhaust_mask = clamp(max(center_stack, side_exhaust), 0.0, 1.0);
	float truck_mirror = disc_mask(profile, vec2(-0.79, 0.225), 0.052, 0.015) * side_face;
	float sport_mirror = disc_mask(profile, vec2(0.48, 0.145), 0.046, 0.014) * side_face;
	float mirror_mask = clamp(max(truck_mirror, sport_mirror), 0.0, 1.0);
	float headlight_mask = range_mask(profile.x, 0.78, 0.98, 0.018)
		* range_mask(profile.y, -0.045, 0.055, 0.016) * side_face;
	float taillight_mask = range_mask(profile.x, -0.98, -0.82, 0.018)
		* range_mask(profile.y, -0.035, 0.105, 0.016) * side_face;
	// Normal-map relief protects handles, seams, fasteners, vents and badges
	// embedded inside otherwise paintable panel bounds.
	float relief = smoothstep(0.34, 0.58, length(baked_normal.xy * 2.0 - 1.0));
	float protected_detail = clamp(max(
		max(max(glass_mask, wheel_mask), max(lower_trim, max(grille_mask, bumper_mask))),
		max(max(exhaust_mask, mirror_mask), max(headlight_mask, taillight_mask))
	), 0.0, 1.0);
	// Relief remains visible through the normal/roughness channels; excluding it
	// from color used to expose the source's white primer as speckled paint bleed.
	float paint_mask = smoothstep(0.32, 0.68, paint_candidate) * (1.0 - protected_detail);

	float secondary_panel = sport_door
		* range_mask(profile.y, -0.145, -0.075, 0.014) * paint_mask;
	float accent_stripe = range_mask(profile.y, -0.068, -0.036, 0.009)
		* side_face * paint_mask;
	vec3 panel_paint = primary_color.rgb * baked_albedo;
	panel_paint = mix(panel_paint, secondary_color.rgb, secondary_panel);
	panel_paint = mix(panel_paint, accent_color.rgb, accent_stripe);

	// Per-material micro variation keeps protected hardware from reading as
	// flat color even though the generated source arrived as one white material.
	float grille_weave = 0.68 + 0.20 * abs(
		sin(model_position.y * 150.0) * sin(model_position.z * 115.0)
	);
	float brushed_metal = 0.88 + 0.12 * sin(model_position.y * 420.0);
	float lens_rib = 0.90 + 0.10 * abs(sin(UV.x * 360.0));
	float view_fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 5.0);
	vec3 opaque_glass = mix(glass_color.rgb, vec3(0.15, 0.24, 0.28), view_fresnel * 0.72);
	vec3 reflective_mirror = mix(mirror_color.rgb, vec3(0.92, 0.97, 1.0), view_fresnel);
	vec3 textured_grille = grille_color.rgb * grille_weave;
	vec3 heated_exhaust = exhaust_color.rgb * brushed_metal;
	heated_exhaust = mix(heated_exhaust, vec3(0.13, 0.075, 0.045), center_stack * 0.28);

	// The source albedo is neutral white. Non-painted body structure therefore
	// starts from fixed graphite metal instead of leaking unselected white.
	vec3 result = detail_metal_color.rgb * mix(vec3(0.88), baked_albedo, 0.18);
	result = mix(result, panel_paint, paint_mask);
	result *= 1.0 - relief * 0.065;
	result = mix(result, trim_color.rgb, lower_trim);
	result = mix(result, detail_metal_color.rgb * brushed_metal, bumper_mask);
	result = mix(result, textured_grille, grille_mask);
	result = mix(result, heated_exhaust, exhaust_mask);
	result = mix(result, reflective_mirror, mirror_mask);
	result = mix(result, opaque_glass, glass_mask);
	result = mix(result, headlight_color.rgb * lens_rib, headlight_mask);
	result = mix(result, taillight_color.rgb * lens_rib, taillight_mask);
	result = mix(result, vec3(0.018, 0.022, 0.026), wheel_mask);
	result = mix(result, detail_metal_color.rgb, hub_mask);

	ALBEDO = result;
	NORMAL_MAP = baked_normal;
	NORMAL_MAP_DEPTH = 0.82;
	AO = mix(orm.r, 0.34, grille_mask);
	AO_LIGHT_AFFECT = 0.38;
	ROUGHNESS = mix(0.58, 0.30, paint_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.48, relief * (1.0 - glass_mask));
	ROUGHNESS = mix(ROUGHNESS, 0.88, wheel_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.76 + 0.12 * grille_weave, grille_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.62 + 0.10 * brushed_metal, exhaust_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.28, bumper_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.07, glass_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.025, mirror_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.10, max(headlight_mask, taillight_mask));
	METALLIC = mix(0.48, 0.34, paint_mask);
	METALLIC = mix(METALLIC, 0.02, max(max(wheel_mask, glass_mask), max(headlight_mask, taillight_mask)));
	METALLIC = mix(METALLIC, 0.38, grille_mask);
	METALLIC = mix(METALLIC, 0.84, exhaust_mask);
	METALLIC = mix(METALLIC, 0.80, max(hub_mask, bumper_mask));
	METALLIC = mix(METALLIC, 0.98, mirror_mask);
	SPECULAR = 0.52;
	CLEARCOAT = clamp(paint_mask * 0.72 + glass_mask * 0.34, 0.0, 1.0);
	CLEARCOAT_ROUGHNESS = mix(0.28, 0.04, glass_mask);
	EMISSION = headlight_color.rgb * headlight_mask * lens_rib * 1.45
		+ taillight_color.rgb * taillight_mask * lens_rib * 0.72;
}
