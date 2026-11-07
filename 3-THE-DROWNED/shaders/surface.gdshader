shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
// The water surface seen from below. The view ray is refracted through a moving wave normal
// (water -> air, eta 1.33): inside Snell's window the sky and the sun's glare, outside it total
// internal reflection: a darker rippled mirror of the water and the seabed below, broken by short wind
// waves, with a pale web where the facets catch the light. The window edge is soft, anti-aliased and wobbles.
// A boat floating on it (boat / boat_size, set by Beat01_Shallows) shows its hull mirrored in the sheet, a
// bright meniscus line at its waterline and small rings around it, so the boat sits IN the surface.
#include "res://shaders/inc/uw.gdshaderinc"

uniform float sky_energy = 0.8;
uniform vec3 sun_dir = vec3(0.18, -1.0, -0.22);    // direction the sunlight travels
uniform vec4 boat = vec4(0.0, 0.0, 0.0, -1.0);      // xz of the waterline centre, xz unit bow direction
uniform vec4 boat_size = vec4(0.0);                 // half length, half beam, draft (m) at the waterline; 0 = none
uniform vec3 boat_color : source_color = vec3(0.05, 0.07, 0.07);

varying vec3 wpos;

float h_waves(vec2 p, float t) {
	float h = 0.0;
	h += 0.16 * sin(dot(p, vec2(0.21, 0.07)) + t * 0.9);
	h += 0.11 * sin(dot(p, vec2(-0.09, 0.26)) + t * 1.15 + 1.3);
	h += 0.07 * sin(dot(p, vec2(0.37, -0.31)) + t * 1.6 + 2.1);
	h += 0.05 * sin(dot(p, vec2(-0.52, -0.18)) + t * 2.1 + 4.0);
	h += 0.18 * (uw_vnoise2(p * 0.18 + vec2(t * 0.12, -t * 0.08)) - 0.5);
	h += 0.07 * (uw_vnoise2(p * 0.55 + vec2(-t * 0.25, t * 0.2)) - 0.5);
	return h;
}

// analytic slope of the short wind waves (wavelength 1-3 m), on a noise-warped domain so they never tile
vec2 ripple_grad(vec2 p, float t) {
	vec2 q = p + (vec2(uw_vnoise2(p * 0.21 + t * 0.05), uw_vnoise2(p * 0.19 - t * 0.04 + 7.0)) - 0.5) * 4.0;
	vec2 g = vec2(0.0);
	vec2 k1 = vec2(2.3, 1.1);
	vec2 k2 = vec2(-1.4, 2.7);
	vec2 k3 = vec2(3.9, -2.2);
	vec2 k4 = vec2(-2.6, -3.9);
	g += k1 * cos(dot(q, k1) + t * 2.6) * 0.024;
	g += k2 * cos(dot(q, k2) + t * 3.1 + 1.7) * 0.02;
	g += k3 * cos(dot(q, k3) + t * 4.0 + 0.6) * 0.011;
	g += k4 * cos(dot(q, k4) + t * 3.6 + 2.9) * 0.012;
	return g;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 v = normalize(wpos - cam);                       // going up toward the surface
	float dist = length(wpos - cam);
	float t = uw_time;
	vec2 p = wpos.xz;
	float e = 0.35;
	float h0 = h_waves(p, t);
	vec2 g = vec2(h_waves(p + vec2(e, 0.0), t) - h0, h_waves(p + vec2(0.0, e), t) - h0) / e;
	g *= 1.0 / (1.0 + dist * 0.012);                      // far ripples average out (no shimmer)
	// the boat: local waterline frame (u toward the bow, w across), signed distance to its footprint
	float bd = 1e3;
	vec2 bl = vec2(0.0);
	bool has_boat = boat_size.x > 0.0;
	if (has_boat) {
		vec2 dxz = p - boat.xy;
		bl = vec2(dot(dxz, boat.zw), dot(dxz, vec2(-boat.w, boat.z)));
		bd = (length(bl / boat_size.xy) - 1.0) * min(boat_size.x, boat_size.y);
	}
	// short wind waves (band-limited by the pixel footprint) and rings spreading from the hull
	float mpp = max(length(fwidth(wpos)), 1e-4);
	float rf = 1.0 - smoothstep(0.06, 0.3, mpp);
	vec2 gs = ripple_grad(p, t) * rf;
	if (has_boat && bd < 6.0 && bd > 0.0) {
		float ring = sin(bd * 7.0 - t * 2.2) * exp(-bd / 1.6) * 0.09 * rf;
		vec2 radial = normalize(bl / (boat_size.xy * boat_size.xy) + 1e-5);
		gs += vec2(radial.x * boat.z - radial.y * boat.w, radial.x * boat.w + radial.y * boat.z) * ring;
	}
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));             // surface normal, up (long waves only: steady window)
	// refraction water -> air
	float eta = 1.333;
	float cosi = clamp(dot(n, v), 0.0, 1.0);
	float k = 1.0 - eta * eta * (1.0 - cosi * cosi);
	float fw = fwidth(k) * 1.5 + 0.015;
	float window = smoothstep(-fw, fw, k);
	vec3 r = eta * v + (sqrt(max(k, 0.0)) - eta * cosi) * n;   // refracted (into the air), up
	r = normalize(r + vec3(0.0, 1e-4, 0.0));
	// Fresnel transmission: dims toward the window edge, where the horizon is squeezed into a bright ring
	float ct = sqrt(max(k, 0.0));
	float rs = (eta * cosi - ct) / max(eta * cosi + ct, 1e-4);
	float rp = (eta * ct - cosi) / max(eta * ct + cosi, 1e-4);
	float trans = clamp(1.0 - 0.5 * (rs * rs + rp * rp), 0.0, 1.0);
	vec3 to_sun = -normalize(sun_dir);
	float sd = max(dot(r, to_sun), 0.0);
	float sun = pow(sd, 600.0) * 6.0 + pow(sd, 40.0) * 0.6;
	vec3 zenith = vec3(0.36, 0.62, 0.72);
	vec3 horizon = mix(pal_shaft, pal_bone, 0.3) * 0.95;
	vec3 sky = mix(horizon, zenith, smoothstep(0.0, 0.7, r.y)) * sky_energy;
	sky += mix(pal_shaft, vec3(1.0), 0.5) * sun;
	float rip = 0.85 + 0.3 * uw_caustics(p * 0.5, t);
	vec3 inside = sky * trans * rip * mix(1.0, 0.3, smoothstep(-15.0, -60.0, cam.y));   // a dim glow from the deep
	// total internal reflection: a mirror of the water below. Near the window it reflects the seabed (steep
	// rays down, darker), toward the horizon the open water (grazing rays, lighter); the wind waves scramble
	// the two into a rippled sheet, with a pale web where the facets catch the light
	vec3 nr = normalize(vec3(-(g.x + gs.x), 1.0, -(g.y + gs.y)));
	vec3 rr = reflect(v, nr);                               // down into the water
	float dn = clamp(-rr.y, 0.0, 1.0);
	vec3 open_w = uw_water_col(cam.y) * 0.8;
	vec3 floor_w = uw_water_col(cam.y - 14.0) * 0.36;
	vec3 tir = mix(open_w, floor_w, smoothstep(0.12, 0.7, dn));
	float facet = clamp(0.5 + (gs.x * 1.7 - gs.y * 1.3) * 2.2, 0.0, 1.0);
	tir *= 0.72 + 0.56 * facet;
	tir += pal_shaft * uw_caustics(p * 0.8 + gs * 3.0, t * 1.2) * 0.16 * rf * uw_fog.w;
	// the boat's hull in the mirror: the reflected ray against a half-ellipsoid hull below the waterline. The
	// mirror takes the long waves and only a little of the wind waves: their full slope scattered the image
	// into hard-edged dark blobs all over the sheet
	if (has_boat && bd < 40.0) {
		vec3 rb = reflect(v, normalize(vec3(-(g.x + gs.x * 0.2), 1.0, -(g.y + gs.y * 0.2))));
		vec3 o = vec3(bl.x, 0.0, bl.y);
		vec3 rd = vec3(dot(rb.xz, boat.zw), rb.y, dot(rb.xz, vec2(-boat.w, boat.z)));
		vec3 sc = vec3(boat_size.x, boat_size.z, boat_size.y);
		vec3 os = o / sc;
		vec3 ds = rd / sc;
		float qa = dot(ds, ds);
		float qb = dot(os, ds);
		float qc = dot(os, os) - 1.0;
		float disc = qb * qb - qa * qc;
		// soft edge from how far the ray misses (normalised units): no aliased outline
		float miss = -disc / max(qa, 1e-6);
		float hit = (1.0 - smoothstep(-0.03, 0.09 + mpp * 0.05, miss)) * step(0.0, -qb);
		tir = mix(tir, boat_color * uw_fog.w, hit * 0.85);
	}
	float kq = k / 0.05;
	float rim = exp(-kq * kq) * window;
	vec3 col = mix(tir, inside, window) + pal_shaft * rim * 0.25;
	// the meniscus: a thin bright line where the hull cuts the surface, a darker band just outside it
	if (has_boat) {
		float ml = max(0.05, mpp * 1.5);
		float mq = bd / ml;                                   // (no pow() of a negative base: NaN under MSAA)
		float dq = (bd - 0.5) / 0.4;
		col += pal_shaft * exp(-mq * mq) * 0.55 * uw_fog.w;
		col *= 1.0 - 0.25 * exp(-dq * dq);
	}
	vec4 f = uw_fog_eval(cam, wpos);
	ALBEDO = mix(col, f.rgb, f.a);
}
