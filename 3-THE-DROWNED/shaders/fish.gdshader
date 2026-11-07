shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// One school of fish (Fish.gd). The school moves as one body: its centre roams around `center`, every fish
// holds a place in a formation stretched along the school's heading and faces that heading (with a little
// wobble of its own), so when the school turns, all of it turns together, the turn rippling from the front to
// the back. Each fish also drifts slowly within its place, beats its tail and shies away from the diver.
// Far away a fish is never smaller than min_px on screen (1-px specks read as pepper noise), the far school
// thins out (fewer, slightly larger fish) and the far fish lighten toward a silvery fogged tone.
// Countershaded silver: dark back, bright belly, sun glints.
// INSTANCE_CUSTOM: x = seed, y = phase, z = length (m), w = variation.
#include "res://shaders/inc/uw.gdshaderinc"

uniform vec3 center = vec3(0.0);
uniform vec3 radius = vec3(5.0, 1.8, 4.0);    // formation half extents: across, up, along the heading
uniform vec3 roam = vec3(10.0, 2.0, 7.0);
uniform float school_seed = 0.0;
uniform vec3 tint : source_color = vec3(0.75, 0.8, 0.78);
uniform float min_px = 3.6;                    // shortest fish on screen, px at 1080p
uniform float max_grow = 2.6;                  // ... but a far fish grows at most this much
uniform vec2 thin_dist = vec2(30.0, 80.0);     // the school thins out over this distance ...
uniform float thin_keep = 0.55;                // ... to this fraction of its fish

varying vec3 wpos;
varying vec3 wnrm;
varying float belly;
varying float far_k;

vec3 school_c(float t) {
	return center + vec3(sin(t * 0.07 + school_seed) * roam.x, sin(t * 0.05 + school_seed * 2.0) * roam.y,
		cos(t * 0.06 + school_seed * 3.0) * roam.z);
}

vec3 school_dir(float t) {
	vec3 d = school_c(t + 1.0) - school_c(t - 1.0);
	d.y *= 0.4;
	return normalize(d + vec3(1e-4, 0.0, 0.0));
}

void vertex() {
	float sd = INSTANCE_CUSTOM.x;
	float ph = INSTANCE_CUSTOM.y;
	float len = INSTANCE_CUSTOM.z;
	float t = uw_time;
	// place in the formation (unit ball, denser toward the middle)
	vec3 o = vec3(fract(sd * 13.71) - 0.5, fract(sd * 7.37) - 0.5, fract(sd * 3.19) - 0.5) * 2.0;
	o = normalize(o + vec3(1e-3)) * pow(fract(sd * 21.3), 0.6);
	// the fish further back follow the turn a moment later: the school bends through a turn
	float lag = (1.0 - o.z) * 1.6;
	vec3 fwd = school_dir(t - lag);
	vec3 rgt = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 upv = cross(fwd, rgt);
	vec3 drift = vec3(sin(t * 0.31 + ph * 6.283), sin(t * 0.43 + ph * 4.1), sin(t * 0.27 + ph * 9.7)) * 0.18;
	vec3 lo = (o + drift) * radius;
	lo.y *= lo.y < 0.0 ? 0.5 : 1.0;                   // the lower half packed tighter: a school low over the sand
	                                                  // otherwise strewed fish on it like pebbles
	vec3 p0 = school_c(t - lag) + rgt * lo.x + upv * lo.y + fwd * lo.z;
	// shy away from the diver
	vec3 dv = p0 - uw_cam_pos;
	float dd = length(dv);
	p0 += dv / max(dd, 1e-3) * 6.0 * (1.0 - smoothstep(2.0, 9.0, dd));
	// heading: the school's, a little wobble of each fish's own
	float wob = sin(t * (0.6 + 0.4 * fract(sd * 5.1)) + ph * 6.283) * 0.22;
	vec3 hdg = normalize(fwd + rgt * wob + upv * wob * 0.3);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), hdg));
	vec3 up = cross(hdg, right);
	// screen size floor and distance thinning (this fish's rank decides when it drops out)
	float dist = length(p0 - uw_cam_pos);
	float px_per_m = abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / max(dist, 0.1);   // [1][1] < 0 when Y is flipped
	float want = min_px * VIEWPORT_SIZE.y / 1080.0;
	float grow = clamp(want / max(len * px_per_m, 1e-4), 1.0, max_grow);
	// the sun's shadow pass renders with an orthographic projection: no screen floor there (it grew every
	// fish's shadow into a dark blot on the sand)
	if (PROJECTION_MATRIX[3][3] > 0.5) grow = 1.0;
	float keep = mix(1.0, thin_keep, smoothstep(thin_dist.x, thin_dist.y, dist));
	float rank = fract(sd * 97.31 + ph * 0.37);
	float alive = smoothstep(rank - 0.06, rank + 0.06, keep);
	far_k = smoothstep(thin_dist.x * 0.6, thin_dist.y, dist);
	vec3 v = VERTEX;
	float beat = sin(t * (9.0 + 4.0 * INSTANCE_CUSTOM.w) + sd * 40.0);
	v.x += beat * 0.22 * pow(max(0.12 - v.z, 0.0), 1.6);
	v.x *= 1.0 + 0.35 * (grow - 1.0);                 // a grown far fish fattens a little: a dash, not a hair
	vec3 w = p0 + (right * v.x + up * v.y + hdg * v.z) * len * grow * alive;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	vec3 n = normalize(right * NORMAL.x + up * NORMAL.y + hdg * NORMAL.z);
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(n, 0.0)).xyz);
	wpos = w;
	wnrm = n;
	belly = smoothstep(0.02, -0.06, v.y);
}

void fragment() {
	vec3 back = pal_steel * 2.2;
	vec3 side = tint * 0.55;
	vec3 col = mix(back, side, smoothstep(-0.2, 0.6, -wnrm.y + 0.3));
	col = mix(col, tint * 0.9, belly);
	// far away the dark backs would print as black specks: silver them toward the side tone
	col = mix(col, tint * 0.7, far_k * 0.45);
	ALBEDO = col * uw_albedo_light(wpos.y);
	METALLIC = 0.55;
	ROUGHNESS = 0.28;
	SPECULAR = 0.6;
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	EMISSION = uw_ambient_glow(normalize(wnrm), vw, wpos.y) * (0.6 + 0.5 * far_k);
	FOG = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
}
