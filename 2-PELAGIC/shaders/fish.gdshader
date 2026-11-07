shader_type spatial;
// Shader-animated fauna for MultiMeshInstance3D (fish schools, and single turtles / sharks on slow loops).
// Instance transforms are identity; INSTANCE_CUSTOM = (orbit phase 0..1, radial 0..1, height -1..1, seed 0..1).
// Each animal follows a smooth orbit around the node's local Y axis, bent by coherent noise; its heading is the
// derivative of that flow, so nothing ever pops. Mesh space: forward +X, up +Y, side +Z, unit length.
// Vertex COLOR: r fin/skin, g dorsoventral (0 belly .. 1 back), b turtle shell, a fin tip / limb fraction.
// UV2: x animated part (0 body, 1 front flipper, 2 rear flipper, 3 head), y side (-1 / +1).
//
// Look of a school (real footage): seen from the side the silvered flanks are vertical mirrors of the uniform
// sideways water (camouflage), so a school is a soft darker mass; from above the dark backs and the mirrors
// (which then reflect the deep) make it dark; backlit, the fish facing the camera are in their own shade with lit
// backs; only fish that bank catch Snell's window and flash. The school shades itself: its core and the side away
// from the sun get little light (dark core, lit rim).
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/water_common.gdshaderinc"

// school flow (local space of the node)
uniform vec3 radii = vec3(8.0, 4.0, 8.0);
uniform float speed = 1.2;
uniform float tightness : hint_range(0.0, 1.0) = 0.5;
uniform float turbulence = 0.3;
uniform float spin = 1.0;
uniform float contract : hint_range(0.0, 1.0) = 0.0;
uniform vec3 school_vel = vec3(0.0);
uniform float school_seed = 0.0;
uniform float presence = 1.0;        // 0..1: the school melts into the water colour (and collapses only at ~0)
uniform float hollow = 0.0;          // 0 filled ball, ~0.5 thick milling ring (jack tornado)
uniform float flash_amp = 0.5;       // roll (rad) of the coordinated turn waves that sweep the school
uniform float flash_rate = 0.09;     // waves per second
uniform float orbit_tilt = 0.0;      // rad: per-fish tilt of the orbit plane (a 3D mill, not stacked flat rings)
uniform float head_jitter = 0.0;     // rad: slow individual heading noise around the flow direction
uniform float roll_jitter = 0.0;     // rad: slow individual roll, so only some flanks mirror the bright window
uniform float deform = 0.0;          // 0..~0.35: slowly deforming irregular outline
uniform float sub_frac = 0.0;        // fraction of the fish in three satellite sub-groups
uniform float stray_frac = 0.0;      // fraction of loose stragglers around the school
uniform vec4 stretch = vec4(1.0, 0.0, 0.0, 0.0);   // xyz local axis, w elongation (a fleeing school streams)
uniform float shade_k = 0.0;         // optical density of the school for its own light (1/m), 0 = off
uniform float startle = 0.0;         // 0..1: panic (a bolting school): every fish rolls hard and flashes
// body
uniform float fish_len = 0.25;
uniform float size_var = 0.25;
uniform float body_mode = 0.0;
uniform float wave_amp = 0.1;
uniform float wave_cycles = 0.9;
uniform float beat_hz = 2.5;
uniform float effort = 1.0;
uniform float roll_amp = 0.25;
uniform vec3 hinge_front = vec3(0.17, -0.01, 0.15);
uniform vec3 hinge_rear = vec3(-0.30, -0.02, 0.10);
uniform vec3 hinge_head = vec3(0.24, 0.0, 0.0);
// level of detail and readability
uniform float lod_band = 0.0;
uniform float lod_split = 25.0;
uniform float min_px = 1.2;
// render height in pixels of the 3D view, kept current by FishSchool
uniform float view_h = 1080.0;
uniform float max_infl = 2.5;
uniform float avoid_radius = 1.5;
// look
uniform vec4 col_back : source_color = vec4(0.13, 0.25, 0.34, 1.0);
uniform vec4 col_flank : source_color = vec4(0.66, 0.74, 0.78, 1.0);
uniform vec4 col_belly : source_color = vec4(0.93, 0.95, 0.96, 1.0);
uniform vec4 col_fin : source_color = vec4(0.58, 0.65, 0.69, 1.0);
uniform vec4 col_mark : source_color = vec4(0.25, 0.43, 0.55, 1.0);
uniform float mark_mode = 0.0;
uniform float stripe_pos = 0.6;
uniform float variety = 0.0;
uniform float tip_dark = 0.0;
uniform float metal = 0.7;
uniform float rough = 0.25;
uniform float glint = 1.0;
uniform vec3 eye_data = vec3(0.40, 0.018, 0.022);
uniform float fill_gain = 0.6;       // diffuse light scattered by the water around (same idea as the reef fill)
uniform float caustic_gain = 1.3;    // sun flicker of the shallow caustics on the fish (top ~25 m)
// look checks (FishSchool --fish-dbg): 0 normal, 1 emission only, 2 no emission, 3 no fog, 4 ambient only,
// 5 (coverage, fog alpha, fog luminance / 4), 6 (visibility, presence, pixel height / 8)
uniform int dbg_mode = 0;

varying vec3 v_local;
varying vec3 v_ln;
varying float v_seed;
varying float v_wy;
varying vec3 v_wp;
varying vec3 v_side;     // world side axis of the fish (the plane of its silvered flank)
varying vec3 v_upw;      // world dorsal axis of the fish
varying float v_px;      // true on-screen body height in pixels (before the readability inflation)
varying float v_cov;     // drawn height / wanted readable height (< 1: sub-pixel fish fade instead of growing)
varying vec3 v_q;        // position in the school (node space, m) for the self-shading of the school
varying float v_sun;     // sunlight reaching this fish through the school (0..1)
varying float v_ao;      // water light reaching it through the school (0..1)
varying float v_caus;    // shallow caustic flicker of the sunlight on this fish (-1..)
varying float v_flash;   // 0..1: this fish is banking in a turn wave (its flank swings into the light)

float fh(float n) {
	return fract(sin(n * 91.3458 + 0.731) * 47453.5453);
}

// normalize() that never returns NaN: a zero-length input (a degenerate interpolated normal, a fragment at the
// camera) gives the fallback instead (a NaN pixel shows black and the glow pass blooms it into a disc)
vec3 safe_norm(vec3 v, vec3 fb) {
	float l2 = dot(v, v);
	return l2 > 1e-12 ? v * inversesqrt(l2) : fb;
}

vec3 rot_axis(vec3 v, vec3 k, float a) {
	float ca = cos(a);
	float sa = sin(a);
	return v * ca + cross(k, v) * sa + k * dot(k, v) * (1.0 - ca);
}

vec3 school_flow(vec4 c, float t) {
	float s = school_seed;
	float sv = 0.85 + 0.3 * fh(c.w * 13.1 + 1.0);
	float g = fh(c.w * 17.31 + 0.5);
	float rr = mix(0.06 + 0.6 * hollow, 1.0, c.y);   // c.y is sqrt-distributed: a filled ball unless hollow > 0
	float tb = turbulence;
	float gs = 1.0;
	vec3 ctr = vec3(0.0);
	if (g < sub_frac) {
		// satellite sub-group: a small mill around a centre that wanders slowly around the main body
		float k = floor(fh(c.w * 29.7) * 3.0);
		float ak = k * 2.0944 + s * 1.7 + t * (0.017 + 0.006 * k);
		ctr = vec3(cos(ak) * (1.0 + 0.18 * sin(t * 0.043 + k * 2.3)), 0.5 * sin(t * 0.029 + k * 1.7 + s),
			sin(ak) * (1.05 + 0.15 * cos(t * 0.037 + k)));
		gs = 0.3 + 0.08 * k;
	} else if (g < sub_frac + stray_frac) {
		// stragglers: loose, wide orbits outside the body
		rr *= 1.25 + 0.55 * fh(c.w * 41.3);
		tb *= 2.2;
	}
	float rm = max(0.5 * (radii.x + radii.z) * rr * gs, 1.2);
	float a = 6.2831853 * c.x + spin * speed * sv * t / rm;
	float yv = c.z * sqrt(max(1.0 - 0.6 * rr * rr, 0.16));
	vec3 p = vec3(cos(a) * rr, yv, sin(a) * rr);
	vec3 d;
	d.x = sin(2.0 * a + 1.7 * yv + 0.21 * t + s) + 0.5 * sin(3.0 * a - 0.33 * t + 2.9 * yv + 1.3 * s);
	d.y = 0.7 * sin(2.0 * a + 0.17 * t + 2.1 * s) + 0.3 * sin(5.0 * a - 0.29 * t + 1.3 * yv);
	d.z = cos(2.0 * a - 1.9 * yv + 0.25 * t + 0.7 * s) + 0.5 * cos(3.0 * a + 0.37 * t + s);
	p += d * (tb * 0.35 * rr);
	if (orbit_tilt > 0.0) {
		// each fish mills in its own tilted plane: the rings cross instead of stacking into a yarn ball
		float ax = 6.2831853 * fh(c.w * 5.93);
		p = rot_axis(p, vec3(cos(ax), 0.0, sin(ax)), orbit_tilt * (2.0 * fh(c.w * 8.37) - 1.0));
	}
	p = ctr + p * gs;
	if (deform > 0.0) {
		// irregular outline: low-frequency lobes that drift over tens of seconds
		float l = 0.55 * sin(1.9 * p.x + 1.3 * p.y + 0.047 * t + s) * cos(1.4 * p.z - 0.8 * p.y + 0.039 * t + 2.0 * s)
			+ 0.45 * sin(2.7 * p.z + 1.1 * p.x - 0.061 * t + 4.0 * s);
		p *= 1.0 + deform * l;
		p.y += deform * 0.35 * sin(1.6 * p.x - 0.9 * p.z + 0.053 * t + 3.0 * s);
	}
	float w = 0.015 + 0.06 * (1.0 - tightness);
	p += vec3(sin(t * 0.63 + c.w * 40.0), sin(t * 0.51 + c.w * 23.0), cos(t * 0.57 + c.w * 31.0)) * w;
	p *= radii * (1.0 - 0.6 * contract);
	p += stretch.xyz * dot(p, stretch.xyz) * stretch.w;
	return p;
}

// Envelope of the school (node space, m) for its self-shading.
vec3 school_env() {
	return max(radii * (1.0 - 0.6 * contract) * (1.05 + 0.25 * turbulence + 0.6 * deform), vec3(0.3));
}

// Length (m) of the ray q + dir * x (x > 0) inside the ellipsoid of half axes R.
float ell_path(vec3 q, vec3 dir, vec3 R) {
	vec3 qs = q / R;
	vec3 ds = dir / R;
	float a = max(dot(ds, ds), 1e-6);
	float b = dot(qs, ds);
	float cc = dot(qs, qs) - 1.0;
	float disc = b * b - a * cc;
	if (disc <= 0.0) {
		return 0.0;
	}
	float sq = sqrt(disc);
	return max((-b + sq) / a - max((-b - sq) / a, 0.0), 0.0);
}

vec3 rot_x(vec3 q, float a) {
	float ca = cos(a);
	float sa = sin(a);
	return vec3(q.x, q.y * ca + q.z * sa, q.z * ca - q.y * sa);
}

vec3 rot_y(vec3 q, float a) {
	float ca = cos(a);
	float sa = sin(a);
	return vec3(q.x * ca + q.z * sa, q.y, q.z * ca - q.x * sa);
}

vec3 rot_z(vec3 q, float a) {
	float ca = cos(a);
	float sa = sin(a);
	return vec3(q.x * ca - q.y * sa, q.x * sa + q.y * ca, q.z);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float t = TIME + school_seed * 37.0;
	const float HS = 0.25;
	vec3 p0 = school_flow(cd, t);
	vec3 pa = school_flow(cd, t - HS);
	vec3 pb = school_flow(cd, t + HS);
	vec3 vel = (pb - pa) / (2.0 * HS) + school_vel;
	vec3 acc = (pb - 2.0 * p0 + pa) / (HS * HS);

	// heading frame: yaw from the flow (plus a slow individual wander), limited pitch, roll into turns plus a slow
	// individual rock (flank flashes)
	vec2 hz = vel.xz + vec2(1e-4, 0.0);
	float hl = max(length(hz), 1e-6);
	vec2 hd = hz / hl;
	if (head_jitter > 0.0) {
		float hj = head_jitter * (0.6 * sin(t * (0.09 + 0.08 * fh(cd.w * 2.9)) + cd.w * 37.0) + 0.4 * (2.0 * fh(cd.w * 6.1) - 1.0));
		hd = vec2(hd.x * cos(hj) - hd.y * sin(hj), hd.x * sin(hj) + hd.y * cos(hj));
	}
	float pitch = clamp(vel.y / max(hl, 1e-3), -0.7, 0.7);
	vec3 fwd = normalize(vec3(hd.x, pitch, hd.y));
	vec3 side = vec3(-hd.y, 0.0, hd.x);
	vec3 up = cross(side, fwd);
	float roll = clamp(dot(acc, side) * 0.5, -0.5, 0.5)
		+ roll_amp * sin(t * (0.6 + 0.6 * fh(cd.w * 5.3)) + cd.w * 61.0)
		+ roll_jitter * (0.7 * sin(t * (0.07 + 0.11 * fh(cd.w * 4.3)) + cd.w * 23.0) + 0.3 * (2.0 * fh(cd.w * 7.9) - 1.0));
	// coordinated turn waves: every few seconds a front sweeps through the school and each fish banks briefly,
	// so the silvered flanks catch the surface light in a travelling ripple of flashes
	v_flash = 0.0;
	if (body_mode < 0.5 && flash_amp > 0.0) {
		float wt = t * flash_rate + school_seed * 0.37;
		float cyc = floor(wt);
		float ang = 6.2831853 * fh(cyc + school_seed);
		vec3 wdir = normalize(vec3(cos(ang), 0.35 * (fh(cyc * 1.7) - 0.5), sin(ang)));
		float x = dot(p0 / max(radii, vec3(0.1)), wdir) * 0.5;
		float front = mix(-1.4, 1.4, fract(wt) / 0.3);
		float dxf = (x - front) * 3.0;
		float pulse = exp(-dxf * dxf) * step(0.2, fh(cyc * 3.1 + school_seed));
		roll += flash_amp * pulse * (fh(cyc * 5.7) > 0.5 ? 1.0 : -1.0) * (0.7 + 0.3 * fh(cd.w * 9.1));
		v_flash = pulse * clamp(flash_amp / 0.9, 0.0, 1.0);
	}
	// panic: a bolting school rocks hard, every fish on its own beat, a burst of flashes (amplitude only: no pops)
	if (body_mode < 0.5 && startle > 0.0) {
		float sk = sin(t * (2.2 + 1.6 * fh(cd.w * 3.7)) + cd.w * 47.0);
		roll += startle * 1.1 * sk;
		v_flash = max(v_flash, 0.7 * startle * sk * sk);
	}
	float cr = cos(roll);
	float sr = sin(roll);
	vec3 up2 = up * cr + side * sr;
	vec3 side2 = side * cr - up * sr;

	// the school's own shade: light reaching this fish through the other fish (sun and water light)
	mat3 mb = mat3(MODEL_MATRIX);
	v_q = p0;
	v_sun = 1.0;
	v_ao = 1.0;
	if (shade_k > 0.0) {
		vec3 R = school_env();
		vec3 sl = normalize(transpose(mb) * water_sun_dir);
		vec3 ul = normalize(transpose(mb) * vec3(0.0, 1.0, 0.0));
		v_sun = exp(-shade_k * ell_path(p0, sl, R));
		float out_path = 0.5 * ell_path(p0, ul, R) + 0.5 * ell_path(p0, safe_norm(p0, vec3(1.0, 0.0, 0.0)), R);
		v_ao = exp(-shade_k * 0.7 * out_path);
	}

	// fish part around the diver
	vec3 cam_l = transpose(mb) * (water_cam_pos - MODEL_MATRIX[3].xyz);
	vec3 dc = p0 - cam_l;
	float dl = max(length(dc), 1e-3);
	p0 += dc / dl * avoid_radius * exp(-dl / max(avoid_radius, 0.01));
	float dist = length(p0 - cam_l);

	// shallow caustics: the fish swims through the moving light net (one value per fish, top ~25 m only)
	vec3 wc = (MODEL_MATRIX * vec4(p0, 1.0)).xyz;
	v_caus = 0.0;
	if (caustic_gain > 0.0 && wc.y > -30.0) {
		vec3 sd = normalize(water_sun_dir);
		vec2 cp = wc.xz - wc.y * sd.xz / max(sd.y, 0.2);
		float cv = water_caustic(cp * 1.7, TIME * 1.6);
		v_caus = caustic_gain * (cv - 0.3) * (1.0 - smoothstep(10.0, 26.0, -wc.y));
	}

	// LOD band (hi mesh near, lo mesh far) and a capped minimum on-screen size: far fish stay true to size (fading
	// with their coverage) instead of growing into strokes that weave into a net
	float is_near = step(dist, lod_split);
	float keep = 1.0;
	if (lod_band > 1.5) {
		keep = 1.0 - is_near;
	} else if (lod_band > 0.5) {
		keep = is_near;
	}
	float sz = fish_len * (1.0 + size_var * (2.0 * fh(cd.w * 7.7) - 1.0));
	// (abs: the y scale of PROJECTION_MATRIX can be negative (a y-flipped projection); with the sign the size test
	// read every fish as sub-pixel: always fully inflated and 45 % washed into the fog colour)
	float px = 2.0 * dist / max(abs(PROJECTION_MATRIX[1][1]) * view_h, 1.0);
	float infl = clamp(px * min_px / (sz * 0.18), 1.0, max_infl);
	float scl = sz * infl * smoothstep(0.0, 0.08, presence) * keep;

	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_local = v;
	v_ln = n;
	float ph = cd.w * 6.2831853;
	float beat = beat_hz * (0.85 + 0.3 * fh(cd.w * 3.3));
	if (body_mode < 0.5) {
		// travelling body wave, amplitude growing towards the tail
		float s = clamp(0.5 - v.x, 0.0, 1.0);
		float amp = wave_amp * effort * (0.12 + 0.88 * s * s);
		float k = 6.2831853 * wave_cycles;
		float phase = k * s - 6.2831853 * beat * t + ph;
		float damp = wave_amp * effort * 1.76 * s;
		float slope = -(damp * sin(phase) + amp * k * cos(phase));
		v.z += amp * sin(phase);
		n = safe_norm(vec3(n.x - slope * n.z, n.y, n.z), vec3(0.0, 1.0, 0.0));
	} else {
		// turtle: slow flipper strokes (flap + sweep), rudder rear flippers, gentle head bob
		float part = UV2.x;
		float sd = UV2.y;
		float w = 6.2831853 * beat * t + ph;
		if (part > 0.5 && part < 1.5) {
			float fa = sd * (0.55 * sin(w) + 0.12) * (0.75 + 0.25 * COLOR.a) * effort;
			float fb = sd * 0.25 * cos(w);
			vec3 hp = vec3(hinge_front.x, hinge_front.y, hinge_front.z * sd);
			v = hp + rot_y(rot_x(v - hp, fa), fb);
			n = rot_y(rot_x(n, fa), fb);
		} else if (part > 1.5 && part < 2.5) {
			float ra = sd * 0.2 * sin(w + 1.3);
			vec3 hr = vec3(hinge_rear.x, hinge_rear.y, hinge_rear.z * sd);
			v = hr + rot_x(v - hr, ra);
			n = rot_x(n, ra);
		} else if (part > 2.5) {
			float hb = 0.06 * sin(w * 0.5 + 1.0);
			v = hinge_head + rot_z(v - hinge_head, hb);
			n = rot_z(n, hb);
		}
	}

	mat3 bm = mat3(fwd, up2, side2);
	VERTEX = p0 + bm * (v * scl);
	NORMAL = safe_norm(bm * n, up2);
	v_side = normalize(mb * side2);
	v_upw = normalize(mb * up2);
	v_px = sz * 0.18 / max(px, 1e-5);
	v_cov = clamp(v_px * infl / max(min_px, 0.5), 0.0, 1.0);
	v_seed = cd.w;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wy = v_wp.y;
}

vec3 vor(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(water_hash(ip + g), water_hash(ip + g + vec2(17.3, 5.1)));
			float d = length(g + o - fp);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = water_hash(ip + g + vec2(3.7, 9.2));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2, id);
}

// Water light field seen in a direction from a depth (for the mirror flanks): the backdrop gradient, a soft
// Snell's window and the refracted sun glow; no rays (they belong to the far view, not to a reflection).
vec3 fish_env(vec3 dir, float d) {
	vec3 col = wb_backdrop(dir, d, 1.0);
	col += mix(WB_SURF, vec3(1.0), 0.55) * smoothstep(0.5, 0.78, dir.y) * exp(-d / 85.0) * 0.9;
	float cs = max(dot(dir, normalize(water_sun_dir)), 0.0);
	col += vec3(1.0, 0.913, 0.716) * (pow(cs, 60.0) * 1.1 + pow(cs, 6.0) * 0.22) * exp(-d / 120.0);
	return col;
}

void fragment() {
	float dv = COLOR.g;
	float fin = COLOR.r;
	float h1 = fract(v_seed * 7.13);
	float h2 = fract(v_seed * 3.71);
	vec3 c;
	float met = 0.0;
	float eye_mask = 0.0;
	if (body_mode < 0.5) {
		// counter-shading: dark back, silver flank, white belly
		c = mix(col_belly.rgb, col_flank.rgb, smoothstep(0.12, 0.5, dv));
		c = mix(c, col_back.rgb, smoothstep(0.58, 0.9, dv));
		if (mark_mode > 0.5 && mark_mode < 1.5) {
			float band = 1.0 - smoothstep(0.035, 0.07, abs(dv - stripe_pos));
			band *= smoothstep(0.36, 0.22, v_local.x);
			c = mix(c, col_mark.rgb, band);
		} else if (mark_mode > 1.5) {
			float f = fract((v_local.x + 0.31) * 8.5);
			float bar = 1.0 - smoothstep(0.14, 0.2, abs(f - 0.5));
			bar *= smoothstep(0.2, 0.4, dv) * step(v_local.x, 0.3) * step(-0.29, v_local.x);
			c = mix(c, col_mark.rgb, bar);
		}
		c = mix(c, col_mark.rgb, variety * step(0.55, h1) * smoothstep(0.2, 0.6, dv));
		c *= 0.88 + 0.24 * h2;
		c = mix(c, col_fin.rgb, fin);
		c = mix(c, col_mark.rgb, tip_dark * smoothstep(0.5, 0.95, COLOR.a));
		// a fish only a few pixels tall shows its mean colour: fins, stripes and marks would break a far school into
		// 1-px blue/yellow glitter
		c = mix(mix(col_flank.rgb, col_back.rgb, 0.5), c, smoothstep(1.5, 5.0, v_px));
		met = metal * (1.0 - smoothstep(0.6, 0.86, dv)) * (1.0 - fin);
		eye_mask = 1.0 - fin;
	} else {
		// turtle: scuted shell, pale plastron, dark scaly skin with pale seams
		vec3 sv1 = vor(v_local.xz * 6.5);
		vec3 shc = col_back.rgb * (0.7 + 0.6 * sv1.z);
		float streak = water_noise(v_local.xz * vec2(38.0, 11.0) + sv1.z * 13.0);
		shc = mix(shc, col_mark.rgb, streak * 0.6 * sv1.z);
		shc *= mix(0.35, 1.0, smoothstep(0.015, 0.07, sv1.y - sv1.x));
		vec2 q = abs(v_ln.y) > 0.6 ? v_local.xz : (abs(v_ln.z) > abs(v_ln.x) ? v_local.xy : v_local.zy);
		vec3 sv2 = vor(q * 38.0);
		vec3 skc = col_fin.rgb * (0.75 + 0.5 * sv2.z);
		skc = mix(skc, col_belly.rgb * 0.8, (1.0 - smoothstep(0.03, 0.12, sv2.y - sv2.x)) * 0.8);
		skc = mix(skc, col_belly.rgb * 0.9, (1.0 - smoothstep(0.2, 0.45, dv)) * 0.55);
		c = mix(col_belly.rgb * 0.95, shc, COLOR.b);
		c = mix(c, skc, fin);
		eye_mask = step(2.5, UV2.x);
	}
	vec2 e = v_local.xy - eye_data.xy;
	float eye_v = (1.0 - smoothstep(eye_data.z * 0.75, eye_data.z, length(e))) * step(0.003, abs(v_local.z)) * eye_mask;
	c = mix(c, vec3(0.015, 0.017, 0.02), eye_v);
	met *= 1.0 - eye_v;
	// silvered skin is a mirror, not a diffuse white: its diffuse part is small
	c *= 1.0 - 0.6 * met;
	// 0 = reef fish (diffuse skin: underwater, skin and water have almost the same refractive index, so the skin
	// hardly reflects at all), 1 = silvered fish (guanine platelets: real mirrors)
	float silv = smoothstep(0.3, 0.7, metal);
	vec3 rel = water_rel_light(v_wy);
	float det = smoothstep(0.5, 2.5, v_px);   // 0 = sub-pixel fish: no sparkle, no contrast
	ALBEDO = c * rel * mix(0.8, 1.0, det);
	METALLIC = 0.0;
	ROUGHNESS = mix(max(rough, 0.45), 0.12, eye_v);
	SPECULAR = 0.2;
	vec3 vw = safe_norm(v_wp - water_cam_pos, vec3(0.0, 0.0, -1.0));
	vec3 nw = safe_norm((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, -vw);
	// water fill: the light the water around sends in the normal's direction (bright from above, dim sideways,
	// dark from the deep below), so backs are lighter than bellies and nothing is a flat black cut-out
	vec3 fill = wb_backdrop(nw, max(-water_cam_pos.y, 0.0), 1.0);
	// Ambient. Godot's sky ambient is the roughest radiance mip, a very wide blur that spreads the bright window over
	// every direction, so a belly is lit like a back and a reef fish reads as a flat pale sticker. Underwater almost
	// all light comes from above (the upwelling light is a few percent of it): for normals that do not face up, reef
	// fish take the water seen in the normal's direction instead (the dark deep below, the horizontal water to the
	// sides). Silvered fish keep the sky ambient (their mirrors make their look).
	// (a downward normal still sees the ring of horizontal water at the edge of its hemisphere: no black keel line)
	vec3 horiz = wb_backdrop(safe_norm(vec3(nw.x, 0.0, nw.z), vec3(1.0, 0.0, 0.0)), max(-water_cam_pos.y, 0.0), 1.0);
	vec3 irr = mix(fill, horiz, 0.4 * max(-nw.y, 0.0));
	IRRADIANCE = vec4(irr, (1.0 - silv) * (1.0 - smoothstep(-0.2, 0.7, nw.y)));
	// the body hides its own lower half from the light above: a rounded fish, lit back, shaded belly
	float body_ao = mix(mix(0.55, 0.5, silv), 1.0, smoothstep(mix(-0.6, -0.7, silv), mix(0.6, 0.5, silv), nw.y));
	AO = v_ao * body_ao;
	float fd = max(-v_wy, 0.0);
	float below = exp(-0.003 * max(water_cam_pos.y - v_wy - 40.0, 0.0));
	// reef fish: the fill lights the upper surfaces only (the ambient above already carries the rest)
	float fgain = fill_gain * mix((1.0 + 0.6 * smoothstep(0.0, 0.9, nw.y)) * smoothstep(-0.2, 0.6, nw.y), 1.0, silv);
	vec3 emit = c * rel * fill * (fgain * v_ao * body_ao) * mix(0.8, 1.0, det);
	// The silvered flank behaves like a vertical mirror (the guanine platelets stay parallel to the body plane
	// whatever the curvature of the skin): it reflects the water light field, which is uniform sideways
	// (camouflage), bright only overhead in Snell's window and dark below. A fish flashes only when it banks so the
	// mirror catches the surface light; seen from above its mirrors reflect the deep and it reads dark.
	vec3 sw = safe_norm(v_side, vec3(0.0, 0.0, 1.0));
	vec3 uw = safe_norm(v_upw, vec3(0.0, 1.0, 0.0));
	float sn = dot(nw, sw);
	vec3 tng = nw - sw * sn;
	tng -= uw * dot(tng, uw);
	vec3 mn = safe_norm(sw * clamp(sn * 4.0, -1.0, 1.0) + tng * 0.35 + nw * 0.06, nw);
	// only truly silver species have the vertical platelet mirror; the sheen of reef fish follows the curved skin
	// (light above, dark below, a rounded body instead of a flat cut-out)
	mn = safe_norm(mix(nw, mn, smoothstep(0.35, 0.75, metal)), nw);
	vec3 rw = reflect(vw, mn);
	// the mirror sees the other fish of the school where its reflection goes through it
	float occ = 1.0;
	if (shade_k > 0.0) {
		vec3 rl = safe_norm(transpose(mat3(MODEL_MATRIX)) * rw, vec3(0.0, 1.0, 0.0));
		occ = exp(-shade_k * ell_path(v_q, rl, school_env()));
	}
	vec3 tint = col_flank.rgb / max(max(col_flank.r, col_flank.g), max(col_flank.b, 1e-3));
	tint = mix(vec3(1.0), tint, 0.45);
	// the flank mirror is seen face-on only from the side; from above or below it is edge-on (dark backs, dark
	// bellies) and the guanine reflects about 60 %, so a fish that does not bank is a little darker than the water
	// seen from well below, a school is a silhouette against the light (the belly keel and the edge-on flanks)
	float side_w = smoothstep(0.1, 0.8, abs(dot(sw, vw))) * (1.0 - 0.75 * smoothstep(0.35, 0.85, vw.y));
	vec3 sun_w = normalize(water_sun_dir);
	float cs = max(dot(rw, sun_w), 0.0);
	float glow = pow(cs, 400.0) * glint * 2.5 * exp(-fd / 120.0) * v_sun;
	// a turn wave: the banking fish swing their flanks into the light together, a travelling silver ripple that reads
	// even where single fish are below a pixel (it is coherent over the school, so it does not crawl); inside the
	// school the light bounces between the mirrors, so a wave is not fully lost behind the other fish
	occ = max(occ, 0.4 * v_flash);
	float mref = met * mix(0.1, 1.0, silv);
	emit += (fish_env(rw, fd) * tint * 0.6 * occ * side_w + glow) * mref * below * mix(0.3, 1.0, max(det, v_flash));
	// the turning fish catch Snell's window together: orientations vary, so from any side some of the banking fish
	// mirror the window at the viewer, and the wave reads as a travelling silver band across the school
	float fw = v_flash * (0.35 + 0.65 * fract(v_seed * 13.7));
	emit += fish_env(normalize(vec3(rw.x, abs(rw.y) + 0.7, rw.z)), fd) * tint * (0.28 * fw) * mref * below;
	// contre-jour: against the light the outline of a fish that the sun reaches glows (thin fins and edges pass
	// light): dark silhouettes with lit rims
	float back = pow(max(dot(vw, sun_w), 0.0), 3.0);
	// (clamped: abs(dot) of two unit vectors can round above 1, and pow() of a negative base is undefined: NaN)
	float edge = clamp(1.0 - abs(dot(nw, vw)), 0.0, 1.0);
	edge *= edge;
	edge *= edge;
	emit += WB_SUNLIGHT * (0.2 * back * edge * v_sun * exp(-fd / 110.0) * mix(0.4, 1.0, det)) * mix(c, vec3(1.0), 0.5)
		* below;
	EMISSION = emit;
	// Water fog; sub-pixel fish fade with their coverage, and a school that is not (yet) present melts into the
	// water colour instead of shrinking.
	vec4 fg = water_fog(v_wp);
	float vis = (1.0 - fg.a) * mix(0.55, 1.0, v_cov) * clamp(presence, 0.0, 1.0);
	FOG = vec4(fg.rgb, 1.0 - vis);
	if (dbg_mode == 1) {
		ALBEDO = vec3(0.0);
	} else if (dbg_mode == 2 || dbg_mode == 4) {
		EMISSION = vec3(0.0);
	} else if (dbg_mode == 3) {
		FOG = vec4(0.0);
	} else if (dbg_mode == 5) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(v_cov, fg.a * 4.0, min(dot(fg.rgb, WB_LUMA), 4.0) / 4.0);
		FOG = vec4(0.0);
	} else if (dbg_mode == 6) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(vis, presence, v_px / 8.0);
		FOG = vec4(0.0);
	}
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// the sun reaches a fish through the school (dark core, lit rim) and dances with the shallow caustics
	float k = LIGHT_IS_DIRECTIONAL ? v_sun * max(1.0 + v_caus, 0.0) : 1.0;
	k *= dbg_mode == 4 ? 0.0 : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (ndl * k / PI);
	// a small normalized Blinn-Phong sheen (F0 ~ 0.03: wet skin, not a mirror; the mirror is in EMISSION)
	// (VIEW + LIGHT is zero for an exactly backlit fragment: guarded)
	vec3 hv = VIEW + LIGHT;
	vec3 h = hv * inversesqrt(max(dot(hv, hv), 1e-12));
	float sp = exp2(11.0 * (1.0 - ROUGHNESS));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (k * ndl * SPECULAR_AMOUNT * 0.03
		* pow(clamp(dot(NORMAL, h), 0.0, 1.0), sp) * (sp + 8.0) / (8.0 * PI));
}
