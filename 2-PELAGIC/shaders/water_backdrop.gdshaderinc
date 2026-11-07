// Far-water colour seen in a direction from a depth (no uniforms: shared by the sky and the surface).
// Palette tokens converted to linear: SURF_TURQ (a cerulean surface blue, #2aa7d0), BLUE_CLEAR, BLUE_DEEP, INDIGO, ABYSS.
// Keep in step with scripts/Palette.gd (water_at).
const vec3 WB_SURF = vec3(0.0232, 0.3864, 0.6308);
const vec3 WB_CLEAR = vec3(0.0030, 0.0931, 0.451);
const vec3 WB_DEEP = vec3(0.0030, 0.0232, 0.156);
const vec3 WB_INDIGO = vec3(0.0021, 0.0070, 0.0513);
const vec3 WB_ABYSS = vec3(0.0006, 0.0018, 0.0048);
const vec3 WB_SUNLIGHT = vec3(1.0, 0.913, 0.716);
const vec3 WB_LUMA = vec3(0.2126, 0.7152, 0.0722);

// Cerulean at the surface, clear blue from ~70 m (held to 100 m), then deep blue, indigo, abyss.
vec3 wb_water_col(float d) {
	d = max(d, 0.0);
	if (d < 100.0) return mix(WB_SURF, WB_CLEAR, smoothstep(0.0, 70.0, d));
	if (d < 250.0) return mix(WB_CLEAR, WB_DEEP, smoothstep(100.0, 250.0, d));
	if (d < 500.0) return mix(WB_DEEP, WB_INDIGO, smoothstep(250.0, 500.0, d));
	return mix(WB_INDIGO, WB_ABYSS, smoothstep(500.0, 950.0, d));
}

// Colour of sunlight that has travelled down to a depth (unit-ish max channel): near white at the top, red and
// yellow gone by a few tens of metres, cyan-blue at 30-150 m, deep blue below. Used for shafts, ray volumes and
// the sun glow, so the light never adds warm grey to the blue.
vec3 wb_light_tint(float depth) {
	vec3 c = mix(vec3(0.85, 0.97, 1.0), vec3(0.15, 0.70, 1.0), smoothstep(4.0, 60.0, depth));
	return mix(c, vec3(0.05, 0.42, 1.0), smoothstep(120.0, 320.0, depth));
}

// The light overhead (looking straight up, away from Snell's window) as seen from a depth: it sinks steadily, about
// one stop per ~70 m, and cools from cerulean through cobalt to a dim deep-blue glow; in the deep it stays a little
// brighter than the horizontal water (a smooth max of the two, no kink).
vec3 wb_zenith(float d) {
	vec3 hue = wb_water_col(d * 0.8 + 10.0);
	float a = 0.42 * exp2(-max(d, 0.0) / 72.0);
	float b = 1.3 * dot(wb_water_col(d + 18.0), WB_LUMA);
	float l = sqrt(sqrt(a * a * a * a + b * b * b * b));
	return hue * (l / max(dot(hue, WB_LUMA), 1e-5));
}

// Integer hash of a lattice point (0..1). Exact integer arithmetic: the corner a cell shares with its neighbour gets
// bit-identical values from both sides. (A fract(sin(dot) * 43758) hash amplifies a one-ulp difference in its
// argument into a different value, and the compiler is free to fold the corner offsets differently in the two
// cells: the noise then steps at cell borders, which drew hard-edged wedges into the ray fans.)
float wb_hash(ivec2 q) {
	uint h = uint(q.x) * 2376512323u + uint(q.y) * 3625334849u;
	h ^= h >> 16u;
	h *= 2146121005u;
	h ^= h >> 15u;
	h *= 2221713035u;
	h ^= h >> 16u;
	return float(h >> 8u) * (1.0 / 16777215.0);
}

// Smooth value noise (C1), 0..1.
float wb_noise(vec2 p) {
	vec2 fl = floor(p);
	vec2 f = p - fl;
	ivec2 i = ivec2(fl);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(wb_hash(i), wb_hash(i + ivec2(1, 0)), u.x),
		mix(wb_hash(i + ivec2(0, 1)), wb_hash(i + ivec2(1, 1)), u.x), u.y);
}

// 0..1 ramps away from the horizon with zero slope at 0 and no kink anywhere (no Mach band at the horizon).
float wb_ramp_up(float x) {
	return smoothstep(0.0, 1.0, x);
}

float wb_ramp_down(float x) {
	float g = smoothstep(0.0, 1.0, x);
	return 1.0 - (1.0 - g) * (1.0 - g);
}

vec3 wb_backdrop(vec3 dir, float d, float below_dark) {
	float up = dir.y;
	vec3 horiz = wb_water_col(d + 18.0);
	vec3 above = wb_zenith(d);
	vec3 below = wb_water_col(d + 260.0) * mix(1.0, 0.72, below_dark);
	return up < 0.0 ? mix(horiz, below, wb_ramp_down(-up)) : mix(horiz, above, wb_ramp_up(up));
}

// Soft, irregular light streaks fanning out from a convergence point; c = unit vector of the azimuth around it,
// r = angular distance from it (rad). Broad low-contrast bands with a finer, shimmering texture.
float wb_streaks(vec2 c, float r, float t) {
	float a = wb_noise(c * 3.1 + vec2(t * 0.045, 1.7));
	float b = wb_noise(c * 6.0 + vec2(4.1, t * 0.08));
	float along = wb_noise(c * 4.3 + vec2(r * 2.6 - t * 0.35, 9.2));
	float s = 0.7 * smoothstep(0.30, 0.92, a) + 0.3 * smoothstep(0.40, 0.97, b);
	return s * (0.35 + 0.65 * along);
}

// The last rays seen from mid-depth: 8-12 broad soft rays converging on the sun glow, each brightening and fading
// along its length (slow pulses running away from the light), the whole fan drifting slowly round the light.
float wb_last_rays(vec2 c, float r, float t) {
	// many narrow soft rays with gentle gates: a few broad high-contrast wedges read as a starburst filter / pinwheel
	float a = wb_noise(c * 5.0 + vec2(t * 0.012, 3.3));
	float b = wb_noise(c * 9.0 + vec2(7.7, -t * 0.02));
	float ray = 0.72 * smoothstep(0.20, 1.0, a) + 0.28 * smoothstep(0.35, 1.0, b);
	float along = wb_noise(c * 3.7 + vec2(r * 3.0 - t * 0.1, 5.1));
	return ray * (0.45 + 0.55 * along);
}

// Looking straight down from mid-depth the water column sinks into a well: a soft radial darkening towards the
// nadir, a gaussian of ~18 deg in the angle from it (1 + dir.y = 1 - cos: no rim and no flat core, so it reads as
// depth, not as a spot; ~3 % at 45 deg below the horizon, so the dark line framed at -45..-55 deg keeps its
// surroundings), part of it relaxed in the deep, where the water is already dark (the far body must still separate
// from it). Applied to the backdrop inside wb_sky only: the reef, fish and bubble fills (wb_backdrop) keep their light.
float wb_nadir_well(vec3 dir, float d) {
	// half of it relaxes before the dark line (255-285 s at ~175-195 m): at full strength it swallowed the line's
	// lower part, which runs near the nadir in the line's framing
	float k = exp(-10.0 * clamp(1.0 + dir.y, 0.0, 2.0)) * smoothstep(60.0, 140.0, d) * (1.0 - 0.5 * smoothstep(150.0, 200.0, d));
	return mix(1.0, 0.48, k);
}

// The complete far-water look in a direction with a weight per kind of term. w.x: images of the light seen through
// the water (the sun disc); w.y: the forward-scatter glow around the sun (halo, glow, last-light spot); w.z: the
// painted ray fans. The sky draws them all (wb_sky); the per-fragment fog (water_fog) weights them by how fogged
// the fragment is, so a near occluder in front of the sun stays a dark silhouette and only a fully fogged far one
// melts into exactly the sky behind it.
// There is no painted fan in the lower hemisphere: rays below the diver come from the 3D ray volume
// (light_volume.gdshader) and the shaft ribbons, which have parallax.
vec3 wb_sky_w(vec3 dir, float d, float shaft_amount, vec3 sun_w, float t, vec3 w) {
	float up = dir.y;
	vec3 col = wb_backdrop(dir, d, 1.0) * wb_nadir_well(dir, d);
	vec3 zen = wb_zenith(d);
	vec3 lt = wb_light_tint(d);
	// Snell's window: a bright disc in the shallows, a soft brighter zone deeper (the last light overhead)
	float soft = mix(0.03, 0.40, smoothstep(0.0, 130.0, d));
	float win = smoothstep(0.661 - soft, 0.661 + soft * 0.6, up);
	col += win * (vec3(0.36, 0.70, 0.86) * 0.55 * exp(-d / 32.0) + zen * 0.35 * smoothstep(10.0, 90.0, d));
	// refracted sun: a disc only in the shallows, a halo deeper, then a dim glow that narrows as the diver sinks
	float cs = clamp(dot(dir, sun_w), -1.0, 1.0);
	float cp = max(cs, 0.0);
	col += WB_SUNLIGHT * pow(cp, 900.0) * 10.0 * exp(-d / 10.0) * w.x;
	col += lt * pow(cp, 60.0) * 0.9 * exp(-d / 38.0) * w.y;
	float gn = mix(6.0, 14.0, smoothstep(40.0, 400.0, d));
	col += zen * pow(cp, gn) * mix(0.35, 0.7, smoothstep(30.0, 200.0, d)) * w.y;
	// from mid-depth the shrinking light: a tighter glow spot on the refracted sun (gone in the deep)
	col += zen * pow(cp, 28.0) * 0.3 * smoothstep(80.0, 140.0, d) * (1.0 - smoothstep(300.0, 420.0, d)) * w.y;
	// fans of rays around the sun when looking up (water-tinted, never warm)
	if (up > 0.0 && w.z > 0.0) {
		vec3 u = normalize(cross(sun_w, vec3(0.0, 0.0, 1.0)));
		vec3 v = cross(sun_w, u);
		vec2 p = vec2(dot(dir, u), dot(dir, v));
		vec2 c = p / max(length(p), 1e-5);
		float ang = acos(cs);
		float up_m = smoothstep(0.0, 0.35, up);
		// shallows: a faint fan outside Snell's window (the ray volume and the shafts carry the rays there)
		float up_w = smoothstep(0.06, 0.40, ang) * (1.0 - smoothstep(0.5, 1.2, ang)) * up_m * (1.0 - win * 0.6);
		float depth_w = 0.8 * exp(-d / 65.0) + 0.2 * exp(-d / 170.0);
		if (up_w > 0.001) {
			col += lt * 0.6 * wb_streaks(c, ang, t) * up_w * 0.03 * shaft_amount * depth_w * w.z;
		}
		// mid-depth (80-320 m): the last rays, soft streaks coming out of the glow, strongest close to it and
		// fading by ~1 rad; relative to the light overhead, in the colour of the sunlight at this depth
		float mid = smoothstep(80.0, 120.0, d) * (1.0 - smoothstep(230.0, 320.0, d));
		float mid_w = mid * smoothstep(0.12, 0.40, ang) * exp(-ang / 1.0) * (1.0 - smoothstep(0.7, 1.1, ang)) * up_m;
		if (mid_w > 0.001) {
			float zl = dot(zen, WB_LUMA);
			col += lt * (zl / max(dot(lt, WB_LUMA), 1e-4)) * 0.5 * wb_last_rays(c, ang, t) * mid_w * shaft_amount * w.z;
		}
	}
	return col;
}

// The far-water look as the sky shows it (detail: the sun disc and the fans; the radiance cubemap pass uses less).
vec3 wb_sky(vec3 dir, float d, float shaft_amount, vec3 sun_w, float t, float detail) {
	return wb_sky_w(dir, d, shaft_amount, sun_w, t, vec3(detail, 1.0, detail));
}
