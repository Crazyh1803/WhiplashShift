// Code-native dark-steel facade for City mid-rise bodies. Unshaded so the body keeps a
// readable silhouette with no sun or ambient: panel seams, floor lines and shutter bays
// are all derived from the instance size and world height, no textures.
shader_type spatial;
render_mode unshaded;

const float BAY = 3.2;
const float FLOOR_H = 3.6;

varying vec3 lpos;
varying vec3 lnorm;
varying flat vec3 msize;
varying float wy;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	msize = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 n = abs(lnorm);
	vec3 p = lpos * msize;
	vec3 steel = vec3(0.80, 0.92, 1.08);
	float seed = hash(msize.xz);
	if (n.y > 0.5) {
		vec2 g = fract(p.xz / 4.0);
		float seam = step(g.x, 0.03) + step(g.y, 0.03);
		ALBEDO = steel * mix(0.02, 0.004, clamp(seam, 0.0, 1.0));
	} else {
		float u = n.x > 0.5 ? p.z : p.x;
		float side = n.x > 0.5 ? 1.0 : 0.78;
		float bay = floor(u / BAY);
		float level = floor(wy / FLOOR_H);
		vec2 cell = vec2(bay, level);
		float fu = fract(u / BAY);
		float fl = fract(wy / FLOOR_H);
		float tone = 0.025 + 0.02 * hash(cell + seed * 31.0);
		float seam = max(step(fu, 0.04), step(fl, 0.035));
		float inset = step(0.16, fu) * step(fu, 0.84) * step(0.2, fl) * step(fl, 0.78);
		float shutter = step(mix(0.62, 0.3, step(level, 1.0)), hash(cell + seed * 7.0 + 3.0));
		float slat = step(fract(wy * 5.0), 0.5);
		float shade = tone;
		shade = mix(shade, mix(0.01, 0.05, slat), inset * shutter);
		shade = mix(shade, 0.004, seam);
		// A thin lit lip under each floor line keeps the hard seam readable at distance.
		shade += 0.01 * step(0.035, fl) * step(fl, 0.07) * (1.0 - seam);
		ALBEDO = steel * shade * side;
	}
}
