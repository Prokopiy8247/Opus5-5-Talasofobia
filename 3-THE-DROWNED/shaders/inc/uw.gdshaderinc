// Shared underwater look: depth light, depth-tinted fog with analytic horizontal fog bands,
// palette globals and small noise helpers. Every material in the game writes FOG = uw_fog_eval(...),
// and the sky uses the same function, so the far backdrop always equals the fog colour.

global uniform vec3 uw_cam_pos;
global uniform vec4 uw_glow;        // rgb: warm light the lit wall scatters into the water near it; w: WALL_Z
global uniform float uw_time;
global uniform vec4 uw_fog;        // x density shallow, y density deep, z band gain, w master light
global uniform vec4 uw_bands_c0;   // band centres (depth, negative y)
global uniform vec4 uw_bands_c1;
global uniform vec4 uw_bands_w0;   // band sigma (m)
global uniform vec4 uw_bands_w1;
global uniform vec4 uw_bands_s0;   // band extra density
global uniform vec4 uw_bands_s1;
global uniform vec4 uw_reveal;     // x wall lights, y statue head, z door lamp, w ending
global uniform vec3 uw_lamp_pos;   // the diver's lamp (world)
global uniform vec4 uw_lamp_dir;   // xyz beam direction, w power (0 = off)
global uniform vec3 uw_bcol0;      // fog band colours (constant, from WorldEnv: uw_band_col of each centre)
global uniform vec3 uw_bcol1;
global uniform vec3 uw_bcol2;
global uniform vec3 uw_bcol3;
global uniform vec3 uw_bcol4;
global uniform vec3 uw_bcol5;
global uniform vec3 uw_bcol6;
global uniform vec3 uw_bcol7;
global uniform vec3 pal_teal_near;
global uniform vec3 pal_teal_far;
global uniform vec3 pal_deep;
global uniform vec3 pal_moss;
global uniform vec3 pal_steel;
global uniform vec3 pal_rust;
global uniform vec3 pal_verdigris;
global uniform vec3 pal_bone;
global uniform vec3 pal_shaft;
global uniform vec3 pal_amber;

// ---------------------------------------------------------------- light and water colour
float uw_light(float y) {           // fraction of the lost sun reaching depth y
	return exp(min(y, 0.0) / 230.0);
}

vec3 uw_water_col(float y) {        // colour scattered by the water at depth y
	float l = uw_light(y);
	vec3 c = mix(pal_deep, pal_teal_far, smoothstep(0.0, 0.45, l));
	c = mix(c, pal_teal_near, smoothstep(0.35, 1.0, l));
	c *= 0.82 + 0.5 * l * l * l * l;             // brighter right under the surface
	return c * uw_fog.w;
}

vec3 uw_band_col(float c) {         // fog bands catch a little more light: lighter layers
	return (uw_water_col(c) * 1.55 + pal_teal_far * 0.22 * (1.0 - uw_light(c))) * uw_fog.w;
}

float uw_density(float y) {
	return mix(uw_fog.y, uw_fog.x, exp(min(y, 0.0) / 120.0));
}

// ---------------------------------------------------------------- analytic gaussian bands
vec4 uw_erf4(vec4 x) {
	vec4 x2 = x * x;
	vec4 a = 0.147 * x2;
	return sign(x) * sqrt(max(vec4(1.0) - exp(-x2 * (1.2732395 + a) / (1.0 + a)), vec4(0.0)));
}

vec4 uw_band_od4(float y0, float y1, float dt, vec4 c, vec4 w) {
	float dy = abs(y1 - y0);
	vec4 tm = (vec4(0.5 * (y0 + y1)) - c) / w;
	vec4 mid = dt * exp(-0.5 * tm * tm);
	vec4 e = uw_erf4((vec4(y1) - c) / (w * 1.4142136)) - uw_erf4((vec4(y0) - c) / (w * 1.4142136));
	vec4 ana = (dt / max(dy, 1e-3)) * w * 1.2533141 * abs(e);
	return mix(mid, ana, step(0.3 * w, vec4(dy)));
}

// Returns vec4(fog colour, fog amount) for a ray from cam to p. Use: FOG = uw_fog_eval(cam, p);
vec4 uw_fog_eval(vec3 cam, vec3 p) {
	vec3 d = p - cam;
	float L = length(d);
	vec3 dir = d / max(L, 1e-4);
	// brighter toward the surface, but less so the deeper the eye is (no bright "30 m" water at 240 m)
	float ph = 0.85 + 2.2 * pow(max(dir.y, 0.0), 2.0) * mix(0.3, 1.0, uw_light(cam.y));
	// looking down into the deep sees less scattered light than looking across: the drop reads as a drop
	float down = 1.0 - 0.62 * pow(max(-dir.y, 0.0), 1.1);
	// the lit wall warms the water in front of it (rays heading toward it, fading with distance from it)
	float gdir = pow(max(-dir.z, 0.0), 1.5) * step(0.0001, dot(uw_glow.rgb, vec3(1.0)));
	float mw = uw_fog.w * uw_fog.w;
	vec3 bc0 = uw_bcol0 * mw, bc1 = uw_bcol1 * mw, bc2 = uw_bcol2 * mw, bc3 = uw_bcol3 * mw;
	vec3 bc4 = uw_bcol4 * mw, bc5 = uw_bcol5 * mw, bc6 = uw_bcol6 * mw, bc7 = uw_bcol7 * mw;
	vec4 s0 = uw_bands_s0 * uw_fog.z, s1 = uw_bands_s1 * uw_fog.z;
	vec3 acc = vec3(0.0);
	float T = 1.0;
	float t0 = 0.0;
	float k = clamp(log2(L * 0.05 + 1.0) + 2.0, 3.0, 8.0);   // finer near the camera on long rays
	float kn = 1.0 / (exp2(k) - 1.0);
	for (int i = 1; i <= 8; i++) {
		float f = float(i) * 0.125;
		float t1 = L * (exp2(f * k) - 1.0) * kn;
		float y0 = cam.y + dir.y * t0;
		float y1 = cam.y + dir.y * t1;
		float dt = t1 - t0;
		float ym = 0.5 * (y0 + y1);
		float rb = uw_density(ym) * dt;
		vec4 o0 = uw_band_od4(y0, y1, dt, uw_bands_c0, uw_bands_w0) * s0;
		vec4 o1 = uw_band_od4(y0, y1, dt, uw_bands_c1, uw_bands_w1) * s1;
		float tau = rb + dot(o0, vec4(1.0)) + dot(o1, vec4(1.0));
		vec3 cs = (rb * uw_water_col(ym) * ph
			+ o0.x * bc0 + o0.y * bc1 + o0.z * bc2 + o0.w * bc3
			+ o1.x * bc4 + o1.y * bc5 + o1.z * bc6 + o1.w * bc7) * down;
		if (gdir > 0.0) {
			vec3 pm = cam + dir * (0.5 * (t0 + t1));
			float wd = max(pm.z - (uw_glow.w + pm.x * pm.x / 5000.0), 0.0);
			cs += tau * uw_glow.rgb * gdir * exp(-wd / 220.0);
		}
		float a = 1.0 - exp(-tau);
		acc += T * a * cs / max(tau, 1e-6);
		T *= 1.0 - a;
		t0 = t1;
	}
	float alpha = 1.0 - T;
	return vec4(acc / max(alpha, 1e-5), alpha);
}

// soft rim of water colour + faint top light, keeps silhouettes readable in the deep
vec3 uw_ambient_glow(vec3 n, vec3 v, float y) {
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	float top = clamp(n.y, 0.0, 1.0);
	float deepf = 1.0 - uw_light(y);
	return uw_water_col(y) * rim * 0.85 + pal_teal_far * top * 0.06 * deepf * uw_fog.w;
}

float uw_albedo_light(float y) {          // objects keep a soft stylised top light, fading to silhouettes in the deep
	return mix(0.1, 0.16, smoothstep(-700.0, -300.0, y)) + 0.84 * exp(min(y, 0.0) / 420.0);
}

// the diver's lamp: 0..1 intensity of the beam at p (cone falloff and distance), for unshaded effects
float uw_lamp_at(vec3 p) {
	vec3 lv = p - uw_lamp_pos;
	float d = length(lv);
	float c = dot(lv / max(d, 1e-3), uw_lamp_dir.xyz);
	return uw_lamp_dir.w * smoothstep(0.86, 0.97, c) * exp(-d / 11.0);
}

// ---------------------------------------------------------------- noise
float uw_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float uw_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float uw_vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(uw_hash12(i), uw_hash12(i + vec2(1, 0)), u.x),
		mix(uw_hash12(i + vec2(0, 1)), uw_hash12(i + vec2(1, 1)), u.x), u.y);
}

float uw_vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(uw_hash13(i), uw_hash13(i + vec3(1, 0, 0)), u.x),
		mix(uw_hash13(i + vec3(0, 1, 0)), uw_hash13(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(uw_hash13(i + vec3(0, 0, 1)), uw_hash13(i + vec3(1, 0, 1)), u.x),
		mix(uw_hash13(i + vec3(0, 1, 1)), uw_hash13(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

float uw_fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * uw_vnoise3(p);
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		a *= 0.5;
	}
	return s;
}

float uw_fbm2(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * uw_vnoise2(p);
		p = p * 2.07 + vec2(11.3, 5.1);
		a *= 0.5;
	}
	return s;
}

// cheap animated caustic network (0..1), p in metres
float uw_caustics(vec2 p, float t) {
	// three warped octaves, each rotated (no lattice of "paving slabs"), sharpened into thin filaments
	vec2 q = p * 0.35;
	float c = 0.0;
	float a = 1.0;
	const mat2 R = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 3; i++) {
		vec2 w = q + vec2(sin(q.y * 1.7 + t * 0.6), cos(q.x * 1.5 - t * 0.5)) * 0.75;
		float v = abs(sin(w.x * 2.1 + t * 0.3) * sin(w.y * 2.3 - t * 0.25));
		c += pow(1.0 - v, 9.0) * a;
		q = R * q * 1.7 + vec2(3.1, 1.7);
		a *= 0.7;
	}
	return clamp(c * 0.75, 0.0, 1.0);
}

// anti-aliased line mask: 1 on the line of half-width hw (same units as x)
float uw_aa_line(float x, float hw) {
	float fw = max(fwidth(x), 1e-5);
	return 1.0 - smoothstep(hw - fw, hw + fw, abs(x));
}
