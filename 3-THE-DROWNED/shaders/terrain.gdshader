shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Seabed: pale sand with ripples and caustics in the shallows, silt and dark rock in the deep, layered rock
// on the cliff. Sloping ground (from ~20 deg) uses 3D noise (no stretched streaks) and turns from rippled sand
// into darker slumped silt before the rock takes over; ripple crests follow the contours. Relief detail is
// band-limited by the pixel footprint per octave (no checker / moire), and a 1-4 m macro relief breaks up the
// flat facets of the mesh. The caustics are sunlight: they are added in light() for the directional light
// only, so the sun's shadow map masks them. The dive boat's shadow is drawn here, soft (boat / boat_size,
// set by Beat01_Shallows): the shadow map drew it as a crisp decal-like ellipse.
// Vertex COLOR: r = ambient occlusion (concavity, wreck contact), g = wreck bed (disturbed sediment),
// b = rock rib factor. light() reproduces diffuse_lambert_wrap + a GGX lobe.
// rock_ao_a / rock_ao_b (Rocks.gd): contact darkening round the boulders' bases (L8 maps over the slope and the
// floor before the door; rect = x0, z0, 1 / width, 1 / depth in metres; z = 0: none).
#include "res://shaders/inc/uw.gdshaderinc"

uniform float wall_z = -940.0;          // the wall: z = wall_z + x*x / 5000 (faces +Z)
uniform float caustic_gain = 0.62;
uniform vec3 sun_dir = vec3(0.18, -1.0, -0.22);
uniform vec4 boat = vec4(0.0, 0.0, 0.0, -1.0);  // xz of the boat's centre, xz unit bow direction
uniform vec2 boat_size = vec2(0.0);             // half length, half beam (m); 0 = no boat
uniform sampler2D rock_ao_a : filter_linear, repeat_disable;
uniform vec4 rock_ao_a_rect = vec4(0.0);
uniform sampler2D rock_ao_b : filter_linear, repeat_disable;
uniform vec4 rock_ao_b_rect = vec4(0.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying float caus_v;                   // fragment -> light: caustic intensity on this pixel
varying float sun_v;                    // fragment -> light: sunlight left under the boat's soft shadow

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

// value-noise fbm with a variable octave count (fewer far away: no sparkle)
float fbm2n(vec2 p, int oct) {
	float s = 0.0;
	float a = 0.5;
	float t = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= oct) break;
		s += a * uw_vnoise2(p);
		t += a;
		p = p * 2.07 + vec2(11.3, 5.1);
		a *= 0.5;
	}
	return s / max(t, 1e-4) * 0.9375;
}

float fbm3n(vec3 p, int oct) {
	float s = 0.0;
	float a = 0.5;
	float t = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= oct) break;
		s += a * uw_vnoise3(p);
		t += a;
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		a *= 0.5;
	}
	return s / max(t, 1e-4) * 0.9375;
}

// gradient noise for the bump: value noise has zero slope across every lattice line, which a grazing lamp
// shows as a regular dashed grid on the silt; gradient noise, quintic fade, rotated octaves has none
vec2 grad2(vec2 i) {
	float a = uw_hash12(i) * 6.2831853;
	return vec2(cos(a), sin(a));
}

float gnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad2(i), f);
	float b = dot(grad2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);    // about -0.7 .. 0.7
}

const mat2 ROT_A = mat2(vec2(0.8253, 0.5646), vec2(-0.5646, 0.8253));
const mat2 ROT_B = mat2(vec2(0.3624, -0.9320), vec2(0.9320, 0.3624));

// flat ground samples xz, steep ground 3D (sw = 0..1 steepness weight)
float ground_noise(vec3 p, float f, float sw, int oct) {
	float a = 0.0;
	float b = 0.0;
	if (sw < 0.999) a = fbm2n(p.xz * f, oct);
	if (sw > 0.001) b = fbm3n(p * f, oct);
	return mix(a, b, sw);
}

void fragment() {
	vec3 n0 = normalize(wnrm);
	float l = uw_light(wpos.y);
	float depth = -wpos.y;
	float slope = 1.0 - clamp(n0.y, 0.0, 1.0);
	float sw = smoothstep(0.08, 0.3, slope);              // planar noise on flat ground, 3D from ~25 deg
	vec3 cam = CAMERA_POSITION_WORLD;
	float dist = length(wpos - cam);
	float mpp = max(length(fwidth(wpos)), 1e-4);         // metres per pixel
	int oct = mpp < 0.05 ? 4 : (mpp < 0.25 ? 3 : 2);
	float n = ground_noise(wpos, 0.08, sw, oct);
	float n2 = ground_noise(wpos + 7.0, 0.6, sw, mpp < 0.12 ? 2 : 1);
	n2 = mix(0.5, n2, 1.0 - smoothstep(0.2, 0.4, 0.6 * mpp));   // sub-pixel mottling would shimmer
	float patch = smoothstep(0.35, 0.75, fbm2n(wpos.xz * 0.025 + 3.0, 3)) * (1.0 - sw);
	float bed = vcol.g;
	float rib = vcol.b;
	// ---- silt (deep) and sand (lit shallows), mottled; disturbed sediment around the wrecks is paler
	vec3 silt = mix(pal_moss * 0.55, pal_teal_far * 0.7, n);
	float mott = 0.5;
	if (l < 0.65) mott = fbm2n(wpos.xz * 0.06 + 11.0, oct);   // silt shows only where the sand fades out
	silt *= 0.82 + 0.36 * mott;
	silt = mix(silt, mix(pal_bone * 0.2, pal_moss * 0.62, n), bed * 0.55);
	vec3 sand = mix(pal_bone * 0.26, pal_bone * 0.42, n) * vec3(0.9, 1.0, 0.92);
	sand = mix(sand, pal_moss * 0.7, patch * 0.55 * (1.0 - bed));
	// sloping ground: sand does not hold its ripples or its pale crust above ~20 deg, it slumps into a darker,
	// siltier, blotchy sediment (isotropic 3D noise: nothing to stretch down the fall line)
	float steep = smoothstep(0.05, 0.16, slope) * (1.0 - bed * 0.6);
	if (steep > 0.001) {
		float sm = fbm3n(wpos * 0.15 + 5.0, oct > 3 ? 3 : oct);
		vec3 slump = mix(sand, mix(pal_moss * 0.62, pal_teal_far * 0.6, n), 0.55) * (0.78 + 0.34 * sm);
		sand = mix(sand, slump, steep * 0.85);
	}
	// rust leached into the sediment around a wreck: blotchy orange-brown stains, darker at the hull
	float stain = 0.0;
	if (bed > 0.002) stain = smoothstep(0.45, 0.8, fbm2n(wpos.xz * 0.11 + 31.0, oct)) * bed;
	silt = mix(silt, pal_rust * 0.3, stain * 0.45);
	sand = mix(sand, pal_rust * 0.34, stain * 0.3);
	vec3 col = mix(silt, sand, smoothstep(0.15, 0.6, l));
	// ---- rock: ribs and steep ground, layered strata on the cliff (evaluated only where rock shows)
	float rk = smoothstep(0.24, 0.5, slope + (n2 - 0.5) * 0.25 + rib * 0.45);
	rk = max(rk, smoothstep(0.4, 0.95, rib) * 0.65) * (1.0 - bed * 0.8);
	if (rk > 0.002) {
		float n3 = ground_noise(wpos * vec3(1.0, 2.2, 1.0) + 3.0, 0.04, 1.0, oct);
		float cliff = smoothstep(0.55, 0.8, slope);
		vec3 rock = mix(pal_steel * 1.3, pal_teal_far * 0.6, n3) * (0.7 + 0.5 * n3);
		vec3 crock = mix(pal_steel * 2.1, mix(pal_teal_far, pal_bone * 0.3, 0.35), n3) * (0.75 + 0.5 * n3);
		rock = mix(rock, crock, cliff);
		// strata on the cliff: warped horizontal beds at three scales, thin dark bedding planes
		if (cliff > 0.001) {
			float sy = wpos.y + n3 * 4.0 + fbm2n(wpos.xz * 0.012, 2) * 10.0;
			float strata = 0.5 + 0.5 * sin(sy * 0.2);
			float strata2 = 0.5 + 0.5 * sin(sy * 0.85 + 1.7);
			float bedding = smoothstep(0.86, 0.98, sin(sy * 2.4 + 0.4)) * (1.0 - smoothstep(0.3, 1.0, mpp));
			rock *= mix(1.0, (0.68 + 0.42 * strata) * (0.82 + 0.3 * strata2) * (1.0 - 0.38 * bedding), cliff);
		}
		col = mix(col, rock, rk);
		// silt settles on ledges of the cliff and on the tops of the ribs
		col = mix(col, silt * 1.1, smoothstep(0.75, 0.95, n0.y) * rk * 0.5);
	}
	// pale silt banked against the foot of the wall
	float wd = wpos.z - (wall_z + wpos.x * wpos.x / 5000.0);
	col = mix(col, pal_bone * 0.18, (1.0 - smoothstep(0.0, 14.0, wd)) * smoothstep(400.0, 700.0, depth) * 0.35);
	// ---- normal: sand ripples (shallow, band-limited) whose crests follow the contours: the seabed falls toward
	// -z, so the wave runs along z, bent by a slow warp; none on sloping ground or the wrecks' disturbed beds
	vec3 nw = n0;
	float rph = wpos.z * 2.7 + wpos.x * 0.4 + uw_vnoise2(wpos.xz * 0.05) * 18.0;
	float rip_amt = smoothstep(0.3, 0.8, l) * (1.0 - smoothstep(0.035, 0.11, slope)) * (1.0 - bed * 0.7);
	rip_amt *= (1.0 - smoothstep(40.0, 110.0, depth)) * (1.0 - smoothstep(0.7, 1.8, fwidth(rph)));
	float rd = cos(rph);
	nw = normalize(nw + vec3(rd * 0.05, 0.0, rd * 0.36) * rip_amt);
	// relief: a 1-4 m macro undulation out to ~170 m (the mesh's flat 2-5 m facets read as folded paper) and the
	// near fine relief (albedo); each octave fades when its cells shrink under ~3 px (no checker, no moire)
	float fm = 1.0 - smoothstep(70.0, 170.0, dist);
	float hm = 0.0;
	float pk = 0.0;
	float fine = 0.0;                     // fine relief, as albedo shading (-0.5 .. 0.5)
	if (fm > 0.0) {
		float wa = 1.0 - smoothstep(0.15, 0.4, 0.3 * mpp);
		float wb = 1.0 - smoothstep(0.15, 0.4, 0.75 * mpp);
		float w1 = 1.0 - smoothstep(0.15, 0.4, 1.3 * mpp);
		float w2 = 1.0 - smoothstep(0.15, 0.4, 3.7 * mpp);
		float micro = mix(0.35, 0.6, 1.0 - l);
		float flat_h = 0.0;
		float steep_h = 0.0;
		// the fine octaves (0.3-0.8 m) shade the albedo only: as screen-derivative bump under a grazing lamp
		// they drew a 1-px dashed perspective grid on the silt (t0540-t0548; gone with the bump off, a split
		// render showed); the bump keeps the 1-4 m relief
		float flat_m = 0.0;
		float steep_m = 0.0;
		if (sw < 0.999) {
			flat_h = gnoise2(ROT_B * wpos.xz * 0.3 + vec2(3.1, 0.7)) * 0.32 * wa
				+ gnoise2(ROT_A * wpos.xz * 0.75 + vec2(9.7, 4.2)) * 0.1 * wb;
			if (w1 > 0.0) flat_m = gnoise2(ROT_A * wpos.xz * 1.3) * 0.6 * w1
				+ gnoise2(ROT_B * wpos.xz * 3.7 + vec2(7.3, 2.9)) * 0.22 * w2;
		}
		if (sw > 0.001) {
			vec3 rp = vec3(ROT_A * wpos.xz, wpos.y).xzy;
			steep_h = (uw_vnoise3(rp * 0.3 + 3.1) - 0.5) * 0.55 * wa + (uw_vnoise3(rp * 0.75 + 9.7) - 0.5) * 0.17 * wb;
			if (w1 > 0.0) steep_m = (uw_vnoise3(rp * 1.3) - 0.5) * 0.9 * w1
				+ (uw_vnoise3(vec3(ROT_B * wpos.xz, wpos.y).xzy * 3.7 + 5.1) - 0.5) * 0.36 * w2;
		}
		hm = mix(flat_h, steep_h, sw);
		fine = mix(flat_m, steep_m, sw) * micro * fm;
		// sparse pockmarks (burrows) in the dim silt only (on sunlit sand they read as holes), jittered in their
		// cells, of varied size, shallow and soft
		float silt_w = 1.0 - smoothstep(0.5, 0.64, l);
		if (silt_w > 0.0 && w1 > 0.0) {
			vec2 pc = floor(ROT_B * wpos.xz / 1.7);
			vec2 jit = vec2(uw_hash12(pc + 3.1), uw_hash12(pc + 8.7)) - 0.5;
			vec2 pf = fract(ROT_B * wpos.xz / 1.7) - 0.5 - jit * 0.5;
			float pr = mix(0.12, 0.24, uw_hash12(pc + 41.0));
			pk = step(0.82, uw_hash12(pc + 19.0)) * (1.0 - smoothstep(pr * 0.3, pr, length(pf))) * (1.0 - sw)
				* silt_w * w1;
			hm -= pk * 0.12;
		}
		hm *= fm;
	}
	// bump from screen derivatives (kept in uniform control flow)
	vec3 dpdx = dFdx(wpos);
	vec3 dpdy = dFdy(wpos);
	float hx = dFdx(hm);
	float hy = dFdy(hm);
	vec3 r1 = cross(dpdy, nw);
	vec3 r2 = cross(nw, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (hx * r1 + hy * r2);
	nw = normalize(mix(nw, normalize(abs(det) * nw - grad), step(1e-9, abs(det)) * step(1e-6, fm)));
	col *= (1.0 - pk * 0.15) * (1.0 + fine * 0.35);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	col *= 0.9 + 0.1 * n2;
	// ---- occlusion: concavity + wreck contact (vertex), and the foot of the wall
	float ao = mix(1.0, vcol.r, 0.85);
	ao *= mix(0.5, 1.0, smoothstep(0.0, 18.0, wd));
	// the rocks sit in the ground: a soft dark ring hugs each base
	float rao = 0.0;
	if (rock_ao_a_rect.z > 0.0) {
		vec2 ruv = (wpos.xz - rock_ao_a_rect.xy) * rock_ao_a_rect.zw;
		if (all(greaterThan(ruv, vec2(0.0))) && all(lessThan(ruv, vec2(1.0)))) rao = textureLod(rock_ao_a, ruv, 0.0).r;
	}
	if (rock_ao_b_rect.z > 0.0) {
		vec2 ruv = (wpos.xz - rock_ao_b_rect.xy) * rock_ao_b_rect.zw;
		if (all(greaterThan(ruv, vec2(0.0))) && all(lessThan(ruv, vec2(1.0)))) rao = max(rao, textureLod(rock_ao_b, ruv, 0.0).r);
	}
	ao *= 1.0 - 0.38 * rao;
	ALBEDO = col * ao * uw_albedo_light(wpos.y);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	// ---- the dive boat's shadow: its footprint seen from here toward the sun, with a penumbra that widens
	// with depth (the water scatters the light around the hull)
	sun_v = 1.0;
	if (boat_size.x > 0.0 && depth < 40.0) {
		vec3 sd3 = normalize(sun_dir);
		vec2 q = wpos.xz - sd3.xz * (wpos.y / sd3.y) - boat.xy;
		vec2 bl = vec2(dot(q, boat.zw), dot(q, vec2(-boat.w, boat.z)));
		float e = (length(bl / boat_size) - 1.0) * boat_size.y;
		float pen = 0.4 + 0.12 * depth;
		sun_v = 1.0 - 0.62 * (1.0 - smoothstep(-pen, pen, e));
	}
	// ---- caustics: fade with depth (gone by ~90 m), with distance and when the network gets sub-pixel
	float caus = uw_caustics(wpos.xz * 1.8, uw_time);
	caus *= l * l * (1.0 - smoothstep(22.0, 60.0, depth)) * (1.0 - smoothstep(30.0, 85.0, dist));
	caus *= (1.0 - smoothstep(0.06, 0.22, mpp)) * (1.0 - slope * 0.6) * (1.0 - patch * 0.5) * (1.0 - rk * 0.5);
	caus_v = caus * caustic_gain * sun_v;
	vec3 vw = normalize(cam - wpos);
	EMISSION = uw_ambient_glow(nw, vw, wpos.y) * 0.5 * ao;
	FOG = uw_fog_eval(cam, wpos);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float r = ROUGHNESS;
	// diffuse_lambert_wrap (energy conserving wrap, as Godot's built-in)
	float wrap = max(0.0, (ndl + r) / ((1.0 + r) * (1.0 + r))) / PI;
	float sv = LIGHT_IS_DIRECTIONAL ? sun_v : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * wrap * ATTENUATION * sv;
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (caus_v * clamp(ndl * 1.4 + 0.25, 0.0, 1.0) / PI);
	}
	// a broad GGX sheen (specular 0.15, very rough)
	float cndl = clamp(ndl, 0.0, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float a = r * r;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float dist_ggx = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float vis = 0.25 / ((cndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	float f0 = 0.0036;
	float fr = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(LIGHT, h), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * dist_ggx * vis * fr * cndl * sv;
}
