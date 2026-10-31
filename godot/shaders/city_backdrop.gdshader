// Weathered midground facade for the converted city's backdrop towers. Unshaded and
// code-native: muted per-building tone, grime, rain streaks, repair patches and a sparse,
// stable scatter of warm and cool lit windows, all from instance size, height and the
// per-instance custom data (x: tone index 0-4, y: building seed). Nothing animates.
shader_type spatial;
render_mode unshaded;

const float BAY = 3.4;
const float FLOOR_H = 3.8;
// Darkens the whole facade to sit behind the detailed night fronts (old body facade ~0.025-0.045).
const float BACKDROP_EXPOSURE = 0.22;

varying vec3 lpos;
varying vec3 lnorm;
varying flat vec3 msize;
varying flat vec2 info;
varying float wy;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 tone(float index) {
	if (index < 0.5) return vec3(0.17, 0.19, 0.22); // slate
	if (index < 1.5) return vec3(0.22, 0.19, 0.16); // weathered brick
	if (index < 2.5) return vec3(0.18, 0.20, 0.17); // olive concrete
	if (index < 3.5) return vec3(0.21, 0.21, 0.20); // pale ash
	return vec3(0.16, 0.18, 0.23); // blue steel
}

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	msize = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	info = INSTANCE_CUSTOM.xy;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 n = abs(lnorm);
	vec3 p = lpos * msize;
	vec3 base = tone(info.x) * BACKDROP_EXPOSURE;
	float seed = info.y * 97.0;
	if (n.y > 0.5) {
		vec2 g = fract(p.xz / 4.0);
		float seam = step(g.x, 0.03) + step(g.y, 0.03);
		float patch = step(0.8, hash(floor(p.xz / 5.0) + seed));
		ALBEDO = base * mix(0.55, 0.35, clamp(seam, 0.0, 1.0)) * mix(1.0, 1.35, patch);
	} else {
		float u = n.x > 0.5 ? p.z : p.x;
		float side = n.x > 0.5 ? 1.0 : 0.8;
		float bay = floor(u / BAY);
		float level = floor(wy / FLOOR_H);
		vec2 cell = vec2(bay, level);
		float fu = fract(u / BAY);
		float fl = fract(wy / FLOOR_H);
		float panel = 0.82 + 0.3 * hash(cell + seed);
		float seam = max(step(fu, 0.05), step(fl, 0.045));
		float inset = step(0.2, fu) * step(fu, 0.8) * step(0.25, fl) * step(fl, 0.72);
		vec3 wall = base * panel * side;
		// Repair patches: a few two-bay by two-floor panels of a different, cleaner tone.
		vec2 pc = floor(vec2(u / (BAY * 2.0), wy / (FLOOR_H * 2.0)));
		float repair = step(0.86, hash(pc + seed * 3.0));
		vec3 patch_tone = mix(vec3(0.27, 0.25, 0.21), vec3(0.19, 0.23, 0.26), step(0.5, hash(pc + seed))) * BACKDROP_EXPOSURE;
		wall = mix(wall, patch_tone * panel * side, repair * 0.85);
		// Rain streaks run down a few columns and fade with height; grime pools low.
		float column = hash(vec2(floor(u * 3.0), seed * 5.0));
		float streak = step(0.7, column) * (1.0 - fract(wy * 0.03 + column * 9.0)) * 0.45;
		wall *= 1.0 - streak;
		wall *= mix(0.5, 1.0, smoothstep(0.0, 14.0, wy));
		// Window insets: dark glass, with a sparse stable scatter lit warm or cool.
		float lit_roll = hash(cell + seed * 7.0 + 3.0);
		float lit = step(0.93, lit_roll) * step(1.0, level) * inset;
		vec3 glass = base * 0.35 * side;
		vec3 lamp = mix(vec3(1.0, 0.72, 0.38), vec3(0.5, 0.82, 1.0), step(0.5, hash(cell + seed * 11.0)));
		vec3 colour = mix(wall, glass, inset * (1.0 - repair * 0.8));
		colour = mix(colour, lamp * 0.3, lit);
		colour = mix(colour, base * 0.15, seam);
		ALBEDO = colour;
		EMISSION = lamp * 0.2 * lit;
	}
}
