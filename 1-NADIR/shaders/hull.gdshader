// NADIR - colossal ship hull plating. UV = (x, v) in metres (v = profile length from the design top, increasing
// downward / toward +Z under the bottom).
// Colossal strakes (28 x 7 m plates, staggered butts) aligned so every porthole row sits inside one strake,
// plating dished between internal frames (ribs in grazing light), double rivet rows at the seams, rust streaks
// that run across seams, algae, barnacle colonies with bare steel between, antifouling below the boot-top,
// draft marks painted into the steel, black porthole interiors, the hawsehole cut-out and a torn top edge.
// Presence: writes its own FOG (the engine's exponential law + the water-light contract), so the hull condenses
// out of the water instead of popping in when the beat turns visible. Sub-pixel detail fades with the footprint.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 c_steel : source_color = vec3(0.231, 0.165, 0.133);
uniform vec3 c_barn : source_color = vec3(0.45, 0.42, 0.33);
uniform vec3 c_algae : source_color = vec3(0.11, 0.165, 0.133);
uniform vec3 c_rust : source_color = vec3(0.4, 0.2, 0.1);
uniform vec3 c_anti : source_color = vec3(0.26, 0.16, 0.14);
uniform float albedo_gain = 5.2;   // the torch is weak at 30-40 m: plating must be bright enough to read
uniform float barn_gain = 0.95;
uniform float bump_k = 1.0;
uniform float boot_v = 520.0;
uniform float bilge_v = 640.0;
uniform float port_rows[12];
uniform int port_count = 0;
uniform float port_dx = 11.0;
uniform float port_r = 1.72;
uniform float port_xmax = 166.0;
uniform vec4 hawse = vec4(-32.0, 420.0, 6.5, 5.0);
// draft marks: v of the bottom of each mark (draft 120, 118, ... 2 m above the keel), text starts at draft_x
uniform float mark_v[60];
uniform float draft_x = 5.0;
// presence and water light (ShipMesh.update_env, every frame)
uniform float fog_density = 0.0175;
uniform vec4 fog_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float presence = 1.0;
uniform float wl_on = 0.0;
global uniform float g_depth;
// path-length colour absorption (torch -> surface -> eye): water eats the red first
global uniform vec3 g_torch_pos;
global uniform float g_torch;

const float PW = 28.0;   // plate length (butt seams)
const float PH = 7.0;    // strake height (lapped seams)
const float FR = 3.5;    // internal frame spacing
const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

varying vec2 huv;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Legacy value noise (float hash): ONLY for tear_line(), which must match ShipProfile.tear() bit for bit.
float vnoise_legacy(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Exact integer lattice hash: the float hash amplifies last-bit differences the shader compiler may introduce
// between the two cells sharing a corner (reassociated i + 1), which cut value noise into straight-edged
// patches ("tiles") on the plating. Integer maths on the lattice index cannot disagree.
float hash_i(vec2 c) {
	uvec2 q = uvec2(ivec2(c) + ivec2(65536));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash_i(i);
	float b = hash_i(i + vec2(1.0, 0.0));
	float c = hash_i(i + vec2(0.0, 1.0));
	float d = hash_i(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// WATER LIGHT CONTRACT (shared pass, B1 surface, ship presence fog use exactly this)
float wl_grad(float depth) {
	return 1.0 - smoothstep(150.0, 330.0, depth);
}
vec3 wl_ratio(vec3 d, float depth) {
	float dn = smoothstep(0.0, 0.95, -d.y);
	dn = dn * dn * (3.0 - 2.0 * dn);
	vec3 r = mix(vec3(1.0), vec3(0.30, 0.36, 0.48), dn) * (1.0 + 0.35 * smoothstep(0.0, 0.66, d.y));
	return mix(vec3(1.0), r, wl_grad(depth));
}

// v of the torn top edge at x (ShipProfile.tear() is the same formula)
float tear_line(float x) {
	return 3.0 + 7.0 * vnoise_legacy(vec2(x * 0.04, 1.3)) + 4.0 * vnoise_legacy(vec2(x * 0.13, 2.9))
		+ 3.0 * abs(2.0 * vnoise_legacy(vec2(x * 0.37, 7.1)) - 1.0)
		+ 7.0 * smoothstep(0.78, 0.84, vnoise_legacy(vec2(x * 0.02, 4.0)));
}

// Plate grid: q = plating coords (strakes centred on the porthole rows), returns (row, xs)
vec2 plate_grid(vec2 p, out vec2 f) {
	vec2 q = vec2(p.x, p.y - port_rows[1] + PH * 0.5);
	float row = floor(q.y / PH);
	float xs = q.x + (mod(row, 2.0) * 0.5 + 0.1 * (hash12(vec2(row, 7.7)) - 0.5)) * PW;   // staggered butts
	f = vec2(fract(xs / PW), fract(q.y / PH));
	return vec2(row, xs);
}

// One layer of barnacles: sparse cells (density dens), power-law sizes, volcano shells with a dark opening.
// Returns (height 0..1, opening 0..1).
vec2 barn_layer(vec2 p, float sc, float dens, float seed) {
	vec2 q = ROT * p * sc;
	vec2 qi = floor(q);
	float h = 0.0;
	float o = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = qi + vec2(float(i), float(j));
			if (hash12(c + seed) > dens) {
				continue;
			}
			vec2 off = vec2(hash12(c + seed + 3.1), hash12(c + seed + 17.3));
			float r = mix(0.18, 0.75, pow(hash12(c + seed + 9.7), 3.0));
			float d = length(q - c - off) / r;
			float shell = sqrt(clamp(1.0 - d, 0.0, 1.0));
			float pit = smoothstep(0.36, 0.18, d);
			h = max(h, shell * (1.0 - 0.85 * pit));
			o = max(o, pit);
		}
	}
	return vec2(h, o);
}

// Colonies: big shells (fade below ~5 px with lb) and small ones between (ls).
vec2 barn(vec2 p, float dens, float lb, float ls) {
	vec2 b = vec2(0.0);
	if (lb > 0.001) {
		b = barn_layer(p, 1.6, dens * 0.85, 0.0) * lb;
	}
	if (ls > 0.001) {
		vec2 s = barn_layer(p, 4.3, dens, 41.0) * ls;
		b = max(b, vec2(0.7 * s.x, s.y));
	}
	return b;
}

// Plating relief height (m) along the outward normal.
float relief(vec2 p, float lod, float lb, float ls, float crust, float dens) {
	vec2 f;
	vec2 g = plate_grid(p, f);
	// plate dish and frame dish are C1 (zero slope at seams and frames): no normal crease cuts the torch's
	// specular lobe into seam-bounded tiles; the ribs still show in grazing light
	float h = -0.05 * (0.5 - 0.5 * cos(TAU * f.x)) * (0.5 - 0.5 * cos(TAU * f.y)) * (0.4 + hash12(vec2(floor(g.y / PW), g.x)));
	h += -0.035 * (1.0 - cos(TAU * fract(p.x / FR))) * pow(sin(PI * f.y), 2.0);   // dished between internal frames
	h += 0.04 * f.y;                                          // lapped strakes: lower edge stands proud
	float ex = min(f.x, 1.0 - f.x) * PW;
	h += 0.016 * (1.0 - smoothstep(0.0, 0.06, ex));           // butt weld bead
	if (lod > 0.001) {
		// double rivet rows (pitch 0.6 m, heads r 0.11 m) along both sides of every seam
		float ay = abs((f.y < 0.5 ? f.y : f.y - 1.0) * PH);
		float rx = (fract(p.x / 0.6) - 0.5) * 0.6;
		float rv = min(length(vec2(rx, ay - 0.3)), length(vec2(rx, ay - 0.75)));
		float ax = abs((f.x < 0.5 ? f.x : f.x - 1.0) * PW);
		float ry = (fract(p.y / 0.6) - 0.5) * 0.6;
		rv = min(rv, min(length(vec2(ax - 0.3, ry)), length(vec2(ax - 0.75, ry))));
		h += 0.045 * sqrt(max(1.0 - rv / 0.11, 0.0)) * lod;
	}
	h += 0.3 * (vnoise(p * 0.045) - 0.5);                     // large buckles break the specular
	if (crust > 0.001) {
		h += crust * (0.03 * vnoise(p * 0.9) + 0.1 * barn(p, dens, lb, ls).x);
	}
	return h;
}

float seg_d(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Distance to a circular arc (centre c, radius r) running counter-clockwise from angle a0 to a1 (a1 > a0).
float arc_d(vec2 u, vec2 c, float r, float a0, float a1) {
	vec2 q = u - c;
	if (mod(atan(q.y, q.x) - a0, TAU) <= a1 - a0) {
		return abs(length(q) - r);
	}
	return min(length(u - c - r * vec2(cos(a0), sin(a0))), length(u - c - r * vec2(cos(a1), sin(a1))));
}

// Distance to a painted digit in a rounded stroke font (bowls and arcs, not 7-segment bars);
// u = (right as seen, up), cell x in [-0.3, 0.3], y in [0, 1], glyphs span y 0.07..0.93.
float digit_d(vec2 u, int dg) {
	if (dg == 0) {   // a stadium: two semicircles joined by straight sides
		return abs(length(vec2(u.x, max(abs(u.y - 0.5) - 0.2, 0.0))) - 0.23);
	}
	if (dg == 1) {   // a single stroke with a flag
		return min(seg_d(u, vec2(0.04, 0.07), vec2(0.04, 0.93)), seg_d(u, vec2(-0.16, 0.78), vec2(0.04, 0.93)));
	}
	if (dg == 2) {   // an upper hook, a diagonal and a foot
		float d = arc_d(u, vec2(0.0, 0.715), 0.205, -0.62, 2.75);
		d = min(d, seg_d(u, vec2(0.167, 0.596), vec2(-0.24, 0.07)));
		return min(d, seg_d(u, vec2(-0.24, 0.07), vec2(0.25, 0.07)));
	}
	if (dg == 3) {   // two open bowls on the right
		float d = arc_d(u, vec2(0.0, 0.725), 0.205, -PI * 0.5, 2.6);
		return min(d, arc_d(u, vec2(0.0, 0.295), 0.225, -2.6, PI * 0.5));
	}
	if (dg == 4) {   // diagonal, upright and bar
		float d = seg_d(u, vec2(0.12, 0.93), vec2(-0.25, 0.32));
		d = min(d, seg_d(u, vec2(-0.25, 0.32), vec2(0.27, 0.32)));
		return min(d, seg_d(u, vec2(0.12, 0.93), vec2(0.12, 0.07)));
	}
	if (dg == 5) {   // flag, upright and a big lower bowl
		float d = seg_d(u, vec2(-0.2, 0.93), vec2(0.24, 0.93));
		d = min(d, seg_d(u, vec2(-0.2, 0.93), vec2(-0.17, 0.5)));
		return min(d, arc_d(u, vec2(0.0, 0.305), 0.235, -2.55, 2.25));
	}
	if (dg == 6) {   // a lower ring and a stem sweeping up to the right
		float d = abs(length(u - vec2(0.0, 0.3)) - 0.23);
		return min(d, seg_d(u, vec2(-0.225, 0.34), vec2(0.17, 0.93)));
	}
	if (dg == 7) {   // a bar and a diagonal
		return min(seg_d(u, vec2(-0.25, 0.93), vec2(0.25, 0.93)), seg_d(u, vec2(0.25, 0.93), vec2(-0.06, 0.07)));
	}
	if (dg == 8) {   // two stacked rings
		return min(abs(length(u - vec2(0.0, 0.3)) - 0.23), abs(length(u - vec2(0.0, 0.73)) - 0.2));
	}
	// 9: an upper ring and a stem sweeping down to the left
	float d = abs(length(u - vec2(0.0, 0.7)) - 0.23);
	return min(d, seg_d(u, vec2(0.225, 0.66), vec2(-0.17, 0.07)));
}

float m_glyph_d(vec2 u) {
	float d = min(seg_d(u, vec2(-0.27, 0.07), vec2(-0.27, 0.93)), seg_d(u, vec2(0.27, 0.07), vec2(0.27, 0.93)));
	d = min(d, seg_d(u, vec2(-0.27, 0.93), vec2(0.0, 0.42)));
	return min(d, seg_d(u, vec2(0.27, 0.93), vec2(0.0, 0.42)));
}

// Painted draft marks near x = draft_x: (paint coverage, rust tear below the glyphs, paint shade).
vec3 draft_paint(vec2 p, float fw) {
	vec3 res = vec3(0.0);
	float span = draft_x - p.x;            // text reads toward -x (left -> right seen from the line)
	if (span < -0.2 || span > 3.8 || p.y < mark_v[0] - 1.1 || p.y > mark_v[59] + 1.1) {
		return res;
	}
	int idx = -1;
	for (int i = 0; i < 60; i++) {
		float dv = p.y - mark_v[i];
		if (dv > -1.05 && dv < 1.0) {
			idx = i;
			break;
		}
	}
	if (idx < 0) {
		return res;
	}
	float fi = float(idx);
	if (hash12(vec2(fi, 3.7)) < 0.15) {
		return res;                        // the whole mark flaked off
	}
	int num = 120 - 2 * idx;
	int nd = num >= 100 ? 3 : (num >= 10 ? 2 : 1);
	float yl = mark_v[idx] - p.y;          // 0 at the glyph bottom, 1 at the top
	float ox = 0.06 * (hash12(vec2(fi, 5.1)) - 0.5);
	float kf = (span - ox) / 0.75;
	float k = floor(kf);
	float d = 9.0;
	if (k >= 0.0 && k < float(nd)) {
		int ki = int(k);
		int div = ki == nd - 1 ? 1 : (ki == nd - 2 ? 10 : 100);
		d = digit_d(vec2((kf - k - 0.5) * 0.75, yl), (num / div) % 10);   // every digit stays (the count reads)
	}
	if (num % 10 == 0) {
		float um = span - ox - (float(nd) * 0.75 + 0.45 + 0.4);
		if (abs(um) < 0.45) {
			d = min(d, m_glyph_d(vec2(um, yl)));
		}
	}
	float aa = max(fw * 0.8, 0.012);
	float cov = 1.0 - smoothstep(0.075 - aa, 0.075 + aa, d);
	// flaking: paint survives in patches, but a stroke never vanishes whole (an 8 must never read as a 6)
	float flake = smoothstep(0.3, 0.44, vnoise(p * 6.0) * 0.65 + vnoise(p * 1.9 + 3.0) * 0.35);
	cov *= max(flake, 0.35 * step(d, 0.05));
	// rust tears bleeding down from the bars into the gap below the mark
	float wid = (float(nd) + (num % 10 == 0 ? 1.6 : 0.0)) * 0.75;
	float below = -yl;
	float tr = step(0.0, below) * step(0.0, span) * step(span, wid)
		* (1.0 - smoothstep(0.0, 0.95, below)) * smoothstep(0.55, 0.8, vnoise(vec2(p.x * 9.0, 2.0 + fi)));
	return vec3(cov, tr, 0.75 + 0.25 * hash12(vec2(fi, 9.3)));
}

void vertex() {
	huv = UV;
}

void fragment() {
	vec2 p = huv;
	// torn top edge: ragged line 3-24 m below the design top, a rusty lip below it
	float tear = p.y < 62.0 ? tear_line(p.x) : -100.0;
	if (p.y < tear) {
		discard;
	}
	vec2 hq = (p - hawse.xy) / hawse.zw;
	if (dot(hq, hq) < 1.0) {
		discard;
	}
	float lip = 1.0 - smoothstep(tear, tear + 1.2, p.y);
	vec2 fw2 = fwidth(p);
	float fw = max(max(fw2.x, fw2.y), 0.001);
	float lod = 1.0 - smoothstep(0.035, 0.09, fw);   // rivets, welds
	float lb = 1.0 - smoothstep(0.02, 0.05, fw);     // large barnacles (gone before they read as bubble wrap)
	float ls = 1.0 - smoothstep(0.012, 0.035, fw);   // small barnacles (>= ~5 px)

	float below = smoothstep(bilge_v - 90.0, bilge_v + 20.0, p.y);
	vec2 pr = ROT * p;
	float dens = smoothstep(0.3, 0.75, vnoise(p * 0.32 + 5.0));   // colonies with bare steel between
	// calcareous crust: crisp, lumpy colony edges (0.5-1 m) instead of feathered smoky clouds
	// (colony = the crisp mask that colours the steel; crust = its barnacle density, for relief and openings)
	float cf = vnoise(pr * 0.06) * 0.55 + vnoise(pr * 0.23 + 3.7) * 0.33 + vnoise(pr * 1.1 + 9.0) * 0.12
		+ below * 0.12 + 0.08 * (vnoise(p * 0.7) - 0.5) + 0.05 * (vnoise(p * 2.6 + 1.7) - 0.5);   // lumpy outline
	float cw = max(0.006, 0.75 * fwidth(cf));   // as crisp as the pixel footprint allows
	float colony = smoothstep(0.685 - cw, 0.685 + cw, cf);
	// the crust thins out around the painted draft marks, so they keep counting down to the keel
	float dspan = draft_x - p.x;
	colony *= 1.0 - 0.75 * smoothstep(-1.6, -0.4, dspan) * (1.0 - smoothstep(4.0, 5.2, dspan))
		* smoothstep(mark_v[0] - 4.0, mark_v[0] - 1.0, p.y) * (1.0 - smoothstep(mark_v[59] + 1.0, mark_v[59] + 4.0, p.y));
	float crust = colony * mix(0.3, 1.0, dens);
	vec2 bv = crust > 0.001 ? barn(p, dens, lb, ls) : vec2(0.0);

	float e = max(0.025, fw * 0.75);
	float h0 = relief(p, lod, lb, ls, crust, dens);
	float hx = relief(p + vec2(e, 0.0), lod, lb, ls, crust, dens);
	float hy = relief(p + vec2(0.0, e), lod, lb, ls, crust, dens);
	vec2 g = vec2(hx - h0, hy - h0) / e * bump_k;

	vec2 f;
	vec2 grid = plate_grid(p, f);
	float plate = hash12(vec2(floor(grid.y / PW), grid.x));
	vec3 col = c_steel * (0.96 + 0.08 * plate) * (0.8 + 0.4 * vnoise(p * vec2(0.12, 0.2)));   // plates differ only subtly (no tiles)
	col *= 0.8 + 0.4 * vnoise(p * 0.02 + 11.0);              // big weathered paint fields

	// rust run-off: streaks bleed from a rivet row (the top of a band of three strakes), narrow at the source,
	// wider and fainter below, ending before the next band; they meander (wx) instead of running ruler-straight.
	// Sub-2-px octaves fade out with the footprint (hf): no crawling cells at grazing angles.
	float hf = 1.0 - smoothstep(0.035, 0.08, fw);
	float wx = p.x + 0.9 * (vnoise(vec2(p.x * 0.25, p.y * 0.06)) - 0.5) + 0.35 * (vnoise(vec2(p.x * 0.9, p.y * 0.21)) - 0.5);
	float qy = p.y - port_rows[1] + PH * 0.5;
	float fb = fract(qy / (PH * 3.0));
	float sband = floor(qy / (PH * 3.0));
	float st = smoothstep(0.80 - 0.2 * fb, 0.95, vnoise(vec2(wx * 0.9, sband * 5.3))) * exp(-2.0 * fb)
		* (1.0 - smoothstep(0.75, 1.0, fb)) * (0.55 + 0.45 * mix(0.5, vnoise(vec2(wx * 7.0, p.y * 0.5)), hf));
	// long streaks: a few, and they end (no endless curtain)
	float lng = smoothstep(0.7, 0.95, vnoise(vec2(wx * 0.42, p.y * 0.012 + 5.0)))
		* smoothstep(0.35, 0.7, vnoise(vec2(wx * 0.5, p.y * 0.05 + 9.0)))
		* (0.45 + 0.55 * vnoise(vec2(wx * 3.0, p.y * 0.06))) * (0.6 + 0.4 * mix(0.5, vnoise(vec2(wx * 9.0, p.y * 0.7)), hf))
		* smoothstep(0.15, 0.6, vnoise(vec2(wx * 1.3, p.y * 0.035 + 2.0)));

	// portholes: black interiors, grime rings, rust tears running down below them
	float hole = 0.0;
	float grime = 0.0;
	float pst = 0.0;
	float xc = round(p.x / port_dx) * port_dx;
	if (abs(xc) <= port_xmax) {
		for (int i = 0; i < 12; i++) {
			if (i >= port_count) {
				break;
			}
			float dv = p.y - port_rows[i];
			if (dv < -3.5 || dv > 24.0) {
				continue;
			}
			float r = length(vec2(p.x - xc, dv));
			hole = max(hole, 1.0 - smoothstep(port_r - 0.04, port_r + 0.04, r));
			grime = max(grime, 1.0 - smoothstep(port_r, port_r + 1.0, r));
			float w = 1.5 - dv * 0.035;
			pst = max(pst, step(0.0, dv) * (1.0 - smoothstep(w * 0.45, w, abs(p.x - xc)))
				* (1.0 - smoothstep(3.0, 23.0, dv)) * (0.45 + 0.55 * mix(0.5, vnoise(vec2(p.x * 6.0, p.y * 0.3)), hf)));
		}
	}
	vec2 hd = p - hawse.xy;
	// rust pours out of the hawse pipe over the lip and down the plating
	float hst = step(0.0, hd.y) * (1.0 - smoothstep(hawse.z * 0.8, hawse.z * 1.25, abs(hd.x - 0.6 * (wx - p.x))))
		* (1.0 - smoothstep(8.0, 70.0, hd.y)) * (0.35 + 0.65 * vnoise(vec2(wx * 3.0, p.y * 0.2)));
	vec3 mk = draft_paint(p, fw);
	float rust = clamp(st * 0.85 + lng * 0.45 + pst * 0.9 + hst + mk.y * 0.8 + lip, 0.0, 1.0);
	col = mix(col, c_rust * (0.45 + 0.5 * vnoise(p * 2.3)), rust);

	// dark biofilm stains (nothing photosynthesises at 330-720 m; no teal stripes competing with the cyan):
	// moderate, with firmer edges, so they read as a stained film and not as smoke over the plating
	float alg = smoothstep(0.6, 0.75, vnoise(vec2(wx * 0.15, p.y * 0.05)) * 0.7 + vnoise(p * 0.5) * 0.3);
	col = mix(col, c_algae, alg * 0.3 * (1.0 - below));

	float anti = smoothstep(boot_v - fw, boot_v + fw, p.y);   // antifouling below the boot-top
	col = mix(col, c_anti * (0.7 + 0.5 * plate), anti * 0.8);
	float band = 1.0 - smoothstep(0.0, fw * 1.5, abs(p.y - boot_v - 1.2) - 1.1);
	col *= 1.0 - 0.5 * band;

	float ey = min(f.y, 1.0 - f.y) * PH;
	float ex = min(f.x, 1.0 - f.x) * PW;
	float seam = (1.0 - smoothstep(0.03, 0.03 + fw * 1.5, ey)) + 0.35 * (1.0 - smoothstep(0.02, 0.02 + fw * 1.5, ex));
	col *= 1.0 - 0.25 * min(seam, 1.0) * (1.0 - smoothstep(0.12, 0.35, fw));
	col *= mix(1.0, 0.5, grime);
	col *= albedo_gain;
	// faded off-white paint (the brightest surface, warm, not cyan), eaten by rust and crust
	col = mix(col, vec3(0.95, 0.88, 0.74) * mk.z, mk.x * (1.0 - 0.7 * rust) * (1.0 - colony));
	// pale, rust-stained calcareous crust with crisp colony edges (no translucent smoky clouds); the beige
	// is pink enough that path absorption greys it at distance instead of turning it olive
	vec3 cb = c_barn * barn_gain * mix(1.0, 0.78, below) * (0.25 + 0.9 * mix(0.5, bv.x, lb))
		* (0.72 + 0.4 * mix(0.5, vnoise(p * 3.3), hf)) * mix(0.85 + 0.3 * vnoise(p * 1.7), 1.0, lb);
	col = mix(col, cb, colony * (0.55 + 0.35 * vnoise(p * 1.3 + 4.1)));   // thick and thin crust over the steel
	col *= 1.0 - 0.6 * ls * crust * bv.y;                    // dark barnacle openings
	col *= mix(1.0, 0.8, below);                            // the underside is darker (absorption does the rest)
	col *= 1.0 - 0.6 * lip;                                 // torn lip
	col = mix(col, vec3(0.0), hole);

	// a century-old, biofilmed hull is matte: no glossy sheen sliding from bay to bay
	float rough = 0.66 + 0.18 * vnoise(p * 0.11 + 2.0) - 0.12 * smoothstep(0.55, 0.85, vnoise(p * 0.035));
	rough = mix(rough, 0.85, rust * 0.7);
	rough = mix(rough, 0.75, mk.x);
	rough = mix(rough, 0.92, crust);
	rough = mix(rough, 0.3, hole);
	// rivet heads keep a small wet glint (the plating around them is matte): scale without tiles
	float ry0 = abs((f.y < 0.5 ? f.y : f.y - 1.0) * PH);
	float rxx = (fract(p.x / 0.6) - 0.5) * 0.6;
	float rvd = min(length(vec2(rxx, ry0 - 0.3)), length(vec2(rxx, ry0 - 0.75)));
	float rx0 = abs((f.x < 0.5 ? f.x : f.x - 1.0) * PW);
	float ryy = (fract(p.y / 0.6) - 0.5) * 0.6;
	rvd = min(rvd, min(length(vec2(rx0 - 0.3, ryy)), length(vec2(rx0 - 0.75, ryy))));
	float riv = (1.0 - smoothstep(0.05, 0.11, rvd)) * lod * (1.0 - colony) * (1.0 - 0.6 * rust);
	rough = mix(rough, 0.38, riv);

	// water eats the red: path-length absorption torch -> surface -> eye (52 m = the wall at 26 m stays as is);
	// FOG is untouched, so fully fogged steel still equals the backdrop
	vec3 wpa = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float path = length(VERTEX) + length(wpa - g_torch_pos);
	vec3 ab = clamp(exp(-vec3(0.020, 0.008, 0.005) * (path - 52.0)), vec3(0.0), vec3(1.25));
	// path absorption greys the paint instead of turning it cyan (no glowing LCD numerals at distance)
	ALBEDO = col * mix(vec3(1.0), mix(ab, vec3(min(ab.g, 1.0)), mk.x), clamp(g_torch, 0.0, 1.0));	ROUGHNESS = rough;
	SPECULAR = mix(mix(0.3, 0.5, riv), 0.05, hole);
	METALLIC = 0.0;
	NORMAL = normalize(NORMAL - (TANGENT * g.x + BINORMAL * g.y) * (1.0 - hole));

	// presence fog: the engine's exponential law, divided by the water-light pass's own factor so a fully
	// faded hull equals the backdrop in every direction; the upper 35 m melt into the water
	vec3 dw = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float fa = 1.0 - exp(-fog_density * length(VERTEX));
	vec3 wr = mix(vec3(1.0), wl_ratio(dw, g_depth), wl_on);
	float fog_a = max(fa, 1.0 - presence);
	fog_a = max(fog_a, 0.55 * (1.0 - smoothstep(tear, tear + 35.0, p.y)));
	FOG = vec4(fog_col.rgb * wr / mix(vec3(1.0), wr, fa), fog_a);
}
