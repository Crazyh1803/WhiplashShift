shader_type spatial;
render_mode cull_disabled;

uniform sampler2D surface_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sinew_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sinew_roughness : repeat_enable, filter_linear_mipmap_anisotropic;
uniform int surface_id = 0;
uniform bool road_markings = false;
uniform vec4 base_color : source_color = vec4(0.2, 0.22, 0.25, 1.0);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Nearest irregular shard and distance to its border, in world-space metres.
vec3 shards(vec2 position) {
	vec2 cell = floor(position);
	vec2 local = fract(position);
	float nearest = 10.0;
	float second = 10.0;
	float identity = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 seed = cell + offset;
			vec2 random = fract(sin(vec2(dot(seed, vec2(127.1, 311.7)), dot(seed, vec2(269.5, 183.3)))) * 43758.5453);
			vec2 delta = offset + 0.18 + random * 0.64 - local;
			float distance_sq = dot(delta, delta);
			if (distance_sq < nearest) {
				second = nearest;
				nearest = distance_sq;
				identity = random.x;
			} else {
				second = min(second, distance_sq);
			}
		}
	}
	return vec3(sqrt(nearest), sqrt(second) - sqrt(nearest), identity);
}

void fragment() {
	// Flat ribbons can be back-facing; road lighting must use the authored upper side.
	vec3 road_up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL *= dot(NORMAL, road_up) < 0.0 ? -1.0 : 1.0;
	vec2 p = world_position.xz;
	float broad = texture(surface_noise, p * 0.006).r;
	float mid = texture(surface_noise, p * 0.065).r;
	float grain = texture(surface_noise, p * 0.9).r;
	float width = max(UV2.x, 1.0);
	float across = (UV.x - 0.5) * width;
	float edge = min(UV.x, 1.0 - UV.x) * width;
	vec3 color = base_color.rgb * (0.74 + broad * 0.36 + grain * 0.22);
	float rough = 0.92;
	float spec = 0.35;

	vec3 emission = vec3(0.0);
	float metal = 0.0;
	float relief = 0.0;
	float flesh = 0.0;
	// Height-shading inputs: macro height is stable at range, micro detail fades with footprint.
	float macro_h = 0.5;
	float gran = 0.3;
	float pit_amt = 0.3;
	float wet = 0.0;
	float shade_k = 0.8;
	float relief_gain = 0.0;
	float fine = texture(surface_noise, p * 3.1).r;
	if (surface_id == 0) {
		// Longitudinal metre UVs keep interlocking ceramic seams continuous.
		float row = floor(UV.y / 4.0);
		float joint_x = abs(fract(across / 3.0 + mod(row, 2.0) * 0.5) - 0.5) * 3.0;
		float joint_y = min(mod(UV.y, 4.0), 4.0 - mod(UV.y, 4.0));
		float joint = min(joint_x, joint_y);
		float seam = 1.0 - smoothstep(0.035, 0.075, joint);
		float wear = (1.0 - smoothstep(0.08, 0.17, joint)) * step(0.46, grain);
		color = mix(vec3(0.659, 0.627, 0.557), vec3(0.847, 0.827, 0.769), mid);
		color = mix(color, vec3(0.847, 0.827, 0.769), wear);
		color = mix(color, vec3(0.020, 0.020, 0.031), seam);
		// Bevelled joints sink into a groove, with a bright chamfer lip and worn crowns.
		float lip_band = smoothstep(0.05, 0.11, joint) * (1.0 - smoothstep(0.11, 0.3, joint));
		macro_h = mix(0.05, 0.55, smoothstep(0.03, 0.24, joint)) + lip_band * 0.22 + (mid - 0.5) * 0.2 - wear * 0.08;
		gran = 0.5;
		pit_amt = 0.45;
		wet = 0.0;
		// Relief in metres: ~0.03m bevel into the joint, small chamfer lip, faint crown wear.
		relief = (smoothstep(0.03, 0.24, joint) - 1.0) * 0.03 + lip_band * 0.006 - wear * 0.002;
		relief_gain = 0.003;
		if (road_markings) {
			float curb = 1.0 - smoothstep(0.65, 0.78, edge);
			float stripe = step(0.5, fract((UV.y + across) / 2.0));
			vec3 paint = mix(vec3(0.12, 0.13, 0.15), vec3(0.70, 0.68, 0.62), stripe);
			color = mix(color, paint * (0.84 + grain * 0.16), curb);
			float slot = (1.0 - smoothstep(0.08, 0.12, abs(across))) * (1.0 - step(1.4, mod(UV.y, 10.0)));
			color = mix(color, vec3(0.02, 0.04, 0.05), slot);
			emission = vec3(0.0, 0.941, 1.0) * slot * 0.65;
			macro_h = mix(macro_h, 0.5, curb * 0.7);
			// Worn paint: ~8mm raised curb with grain-scale chipping, small but nonzero.
			relief = mix(relief, 0.008 + (grain - 0.5) * 0.004 + (mid - 0.5) * 0.004, curb);
			relief_gain = mix(relief_gain, 0.004, curb);
			gran *= 1.0 - curb * 0.5;
		}
		rough = 0.4 + grain * 0.1;
		metal = 0.1;
	} else if (surface_id == 1) {
		float stripe = step(0.5, fract((UV.y + across) / 2.0));
		color = mix(vec3(0.12, 0.13, 0.15), vec3(0.70, 0.68, 0.62), stripe);
		color *= 0.84 + grain * 0.16;
		rough = 0.48;
		relief = 0.006 + (grain - 0.5) * 0.004;
		gran = 0.2;
		shade_k = 0.5;
	} else if (surface_id == 2) {
		// Chitin ballast: small angular pale chips in pulverized carbon.
		vec3 chip = shards(p * 1.8);
		float aa = max(fwidth(chip.y), 0.012);
		float seam = 1.0 - smoothstep(0.045, 0.045 + aa, chip.y);
		float bone = step(0.36, chip.z);
		color = mix(vec3(0.075, 0.080, 0.095), vec3(0.62, 0.58, 0.48), bone);
		color *= 0.65 + chip.z * 0.35 + grain * 0.18;
		color = mix(color, vec3(0.025, 0.022, 0.028), seam * 0.9);
		relief = (1.0 - seam) * (0.02 + bone * 0.04);
		rough = 0.85 + grain * 0.12;
		macro_h = 0.15 + 0.5 * smoothstep(0.03, 0.2, chip.y) + bone * 0.2;
		gran = 0.6;
		pit_amt = 0.45;
		shade_k = 1.0;
		relief_gain = 0.012;
	} else if (surface_id == 3) {
		// Blood bed: irregular crimson/maroon pools, pale fatty patches, wet lobes and veins.
		vec2 warp = vec2(texture(surface_noise, p * 0.05 + vec2(0.31, 0.77)).r,
			texture(surface_noise, p * 0.05 + vec2(0.63, 0.18)).r) - 0.5;
		vec2 wp = p + warp * 5.0;
		float pool_field = texture(surface_noise, wp * 0.085).r * 0.65 + texture(surface_noise, wp * 0.21).r * 0.35;
		float pool = smoothstep(0.44, 0.58, pool_field);
		float deep = smoothstep(0.58, 0.72, pool_field);
		float fat_field = texture(surface_noise, wp * 0.13 + vec2(0.5, 0.2)).r;
		float fat = smoothstep(0.6, 0.72, fat_field) * (1.0 - deep);
		vec3 lobe = shards(wp * 1.25);
		vec3 vein = shards(wp * 3.4 + 7.0);
		float lobe_edge = 1.0 - smoothstep(0.03, 0.2, lobe.y);
		float vein_line = (1.0 - smoothstep(0.012, 0.05, vein.y)) * step(0.35, vein.z) * (1.0 - deep * 0.6);
		vec3 mapped = texture(sinew_normal, wp * 0.21).rgb * 2.0 - 1.0;
		color = mix(vec3(0.34, 0.045, 0.06), vec3(0.19, 0.02, 0.04), lobe.z);
		color = mix(color, vec3(0.43, 0.09, 0.08), (1.0 - lobe_edge) * 0.35 * mid);
		color = mix(color, vec3(0.07, 0.008, 0.016), pool * 0.75);
		color = mix(color, vec3(0.035, 0.004, 0.01), deep);
		color = mix(color, vec3(0.64, 0.5, 0.34), fat * 0.55);
		color = mix(color, vec3(0.1, 0.012, 0.035), lobe_edge * 0.6);
		color = mix(color, vec3(0.28, 0.04, 0.12), vein_line * 0.7);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(mapped.x * 0.12, 0.0, mapped.y * 0.12, 0.0)).xyz);
		rough = mix(0.26, 0.07, pool);
		rough = mix(rough, 0.34, fat * 0.7);
		spec = 0.8;
		flesh = 0.3 * (1.0 - pool);
		macro_h = 0.55 + smoothstep(0.02, 0.35, lobe.y) * 0.3 - pool * 0.3 - deep * 0.1 + vein_line * 0.1 + fat * 0.1;
		// Lobes swell about 1.5cm, veins sit proud ~5mm, pools settle ~1cm.
		relief = smoothstep(0.02, 0.35, lobe.y) * 0.015 + vein_line * 0.005 - pool * 0.01 - deep * 0.004;
		relief_gain = 0.003;
		gran = 0.2;
		pit_amt = 0.1;
		wet = 0.95;
		shade_k = 0.7;
	} else if (surface_id == 4) {
		// Vertex height is shared with the collider: crowns and flanks mark real rocks.
		float rock_height = clamp(UV2.y, 0.0, 1.0);
		float rock_aa = max(fwidth(rock_height), 0.008);
		float flank = smoothstep(0.015, 0.08 + rock_aa, rock_height);
		float crown = smoothstep(0.65, 0.92, rock_height);
		float rim = smoothstep(0.12, 0.25, rock_height) * (1.0 - smoothstep(0.25, 0.42, rock_height));
		vec3 cracks = shards(p * 2.6);
		float scratch = (1.0 - smoothstep(0.012, 0.012 + max(fwidth(cracks.y), 0.012), cracks.y)) * crown;
		vec3 stone = mix(vec3(0.38, 0.37, 0.34), vec3(0.63, 0.60, 0.51), crown);
		stone *= 0.82 + mid * 0.24 + grain * 0.12;
		stone = mix(stone, vec3(0.82, 0.79, 0.69), rim * 0.35);
		stone *= 1.0 - scratch * 0.24;
		color = mix(vec3(0.085, 0.075, 0.08) * (0.7 + grain * 0.6), stone, flank);
		relief = rock_height * 0.3;
		rough = 0.76 + grain * 0.18;
		metal = 0.05;
		macro_h = rock_height;
		gran = 0.35 * flank;
		pit_amt = 0.25;
		shade_k = 0.6;
		relief_gain = 0.002 * flank;
	} else if (surface_id == 5) {
		// Vitrified coolant: dark glass, trapped pale fractures and cyan capillaries.
		vec3 frost = shards(p * 0.65);
		float aa = max(fwidth(frost.y), 0.008);
		float fracture = 1.0 - smoothstep(0.018, 0.018 + aa, frost.y);
		float frost_edge = 1.0 - smoothstep(0.05, 0.18, frost.y);
		color = mix(vec3(0.035, 0.105, 0.14), vec3(0.22, 0.35, 0.38), broad);
		color = mix(color, vec3(0.65, 0.76, 0.75), frost_edge * 0.65);
		color = mix(color, vec3(0.05, 0.65, 0.70), fracture);
		emission = vec3(0.0, 0.941, 1.0) * fracture * 0.22;
		relief = frost_edge * 0.008;
		rough = 0.10 + grain * 0.1 + frost_edge * 0.14;
		spec = 0.75;
		macro_h = 0.5 + frost_edge * 0.15 - fracture * 0.3;
		gran = 0.1;
		pit_amt = 0.0;
		wet = 1.0;
		shade_k = 0.6;
	} else if (surface_id == 6) {
		// Reactor effluent: slow circulating coolant, cellular scum and pale foam.
		vec2 flow = p * 0.12 + vec2(TIME * 0.018, -TIME * 0.011);
		float eddy = texture(surface_noise, flow + vec2(mid * 0.14, 0.0)).r;
		float ripple = sin(p.x * 1.4 + p.y * 1.9 + TIME * 1.2 + eddy * 9.0);
		float foam = smoothstep(0.65, 0.74, eddy + ripple * 0.08);
		color = mix(vec3(0.018, 0.065, 0.075), vec3(0.045, 0.27, 0.25), eddy);
		color = mix(color, vec3(0.53, 0.59, 0.43), foam * 0.75);
		relief = ripple * 0.018 + eddy * 0.04;
		rough = mix(0.14, 0.4, foam);
		spec = 0.75;
		macro_h = 0.5 + ripple * 0.18 + (eddy - 0.5) * 0.4 + foam * 0.15;
		gran = 0.0;
		pit_amt = 0.0;
		wet = 1.0;
		shade_k = 0.8;
	} else if (surface_id == 7) {
		// Black ichor: slick membrane with restrained interference-color swirls.
		float swirl = sin(p.x * 0.9 + sin(p.y * 0.7 + broad * 6.0) * 3.0 + mid * 8.0);
		vec3 film = 0.5 + 0.5 * cos(swirl * 3.0 + vec3(0.0, 2.1, 4.2));
		color = vec3(0.018, 0.012, 0.025) + film * 0.055;
		relief = swirl * 0.008;
		rough = 0.07 + grain * 0.05;
		spec = 0.8;
		macro_h = 0.5 + swirl * 0.15;
		gran = 0.0;
		pit_amt = 0.0;
		wet = 1.0;
		shade_k = 0.5;
	} else {
		// Crushed carbon understructure with sparse discarded chitin fragments.
		vec3 debris = shards(p * 0.85);
		float chip = step(0.86, debris.z) * smoothstep(0.04, 0.14, debris.y);
		color = mix(vec3(0.020, 0.020, 0.031), vec3(0.075, 0.080, 0.095), mid);
		color = mix(color, vec3(0.34, 0.32, 0.27), chip * 0.7);
		relief = chip * 0.035;
		rough = 0.98;
		spec = 0.12;
		macro_h = 0.2 + 0.4 * smoothstep(0.02, 0.25, debris.y) + chip * 0.4 + (mid - 0.5) * 0.3;
		gran = 0.8;
		pit_amt = 0.5;
		wet = 0.0;
		shade_k = 1.0;
		relief_gain = 0.01;
	}
	// Footprint fade removes sub-pixel grain at range so detail never shimmers.
	float footprint = length(fwidth(p));
	float fade = 1.0 - smoothstep(0.06, 0.3, footprint);
	float micro = ((grain - 0.5) + (fine - 0.5)) * gran;
	float pits = smoothstep(0.68, 0.85, fine) * pit_amt;
	float height = clamp(macro_h + (micro - pits) * fade, 0.0, 1.0);
	// Multiplicative cavity/crown shading keeps mean brightness and dark guidance intact.
	color *= 1.0 + (height - 0.5) * shade_k;
	float pooled = (1.0 - smoothstep(0.25, 0.55, height)) * wet;
	rough = clamp(rough + micro * 0.3 * fade, 0.05, 1.0);
	rough = max(mix(rough, rough * 0.4, pooled), 0.05);
	relief += micro * relief_gain * fade;
	// Very low signal on physical hazards preserves recognition between pools.
	// These values remain far below the selective bloom threshold.
	if (surface_id >= 2 && surface_id <= 7) {
		emission += color * 0.045;
	}
	// Screen derivatives give relief lighting without moving collision or mesh vertices.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 rx = cross(dpdy, NORMAL);
	vec3 ry = cross(NORMAL, dpdx);
	float determinant = dot(dpdx, rx);
	vec3 gradient = (rx * dFdx(relief) + ry * dFdy(relief)) * sign(determinant) / max(abs(determinant), 0.00001);
	NORMAL = normalize(NORMAL - gradient);
	SSS_STRENGTH = flesh;
	CLEARCOAT = flesh * 0.6;
	CLEARCOAT_ROUGHNESS = 0.15;
	ALBEDO = color;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = emission;
}

// Mostly smooth diffuse so relief normals read under moving lights, plus restrained soft broad bands.
void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float q = ndl * 3.0;
	float stepped = (floor(q) + smoothstep(0.3, 0.7, fract(q))) / 3.0;
	float band = mix(ndl, stepped, 0.2);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band / PI;
	vec3 halfway = normalize(LIGHT + VIEW);
	float shine = pow(max(dot(NORMAL, halfway), 0.0), mix(96.0, 8.0, ROUGHNESS));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * shine * (1.0 - ROUGHNESS) * 0.25;
}
