shader_type spatial;
// Reef props (MultiMesh). INSTANCE_CUSTOM = (linear albedo rgb, variation). Vertex COLOR: r = AO, g = cavity,
// b = shape parameter. kind: 0 coral head / encrusting colony (meanders, knobs), 1 sponge (pores, dark cavity),
// 2 plate / table (growth rings, radial ridges, pale growing rim), 3 branching rods, whips and gorgonian trees
// (polyp fuzz, sway in the current, a little translucency against the light).
// Both sides are shaded correctly (normal flipped on back faces). Same water fill, caustics and fog as the rock,
// and world-scale mottling from the rock's own life noise so a far prop sits in the same tones as the reef around it.
render_mode cull_disabled;
#include "res://shaders/water_common.gdshaderinc"
#include "res://shaders/reef_common.gdshaderinc"

uniform int kind = 0;
// plates growing out of a wall: local +X points away from the rock, the -X side is attached (dark, buried)
uniform bool wall_plate = false;
// sponges hanging under the lip roof (ReefDress 'rtubes'): the same side light from the open water as the roof's
// undersides (reef.gdshader roof_*), so they are not the darkest things on a roof that now shows its relief
uniform float roof_open = 0.0;
uniform vec3 roof_centre = vec3(-68.0, -84.0, -384.0);
uniform float roof_radius = 82.0;   // ReefRoof.R0
uniform float roof_side = 4.0;      // (the roof's values in reef.gdshader)
uniform float roof_floor = 0.1;
uniform float roof_blue = 0.85;
uniform float roof_end = 0.12;
// a hanging sponge is a thin lit body, not a rock facet: the water's light wraps round it (scattered light, thin
// tissue: the side turned away keeps roof_wrap of the lit side's light) and its floor is higher, so it reads in the
// roof's mid tones instead of as a dark log against the roof
uniform float roof_wrap = 0.25;
uniform float roof_prop_floor = 5.0;

varying vec3 v_w;
varying vec3 v_n;
varying vec4 v_c;
varying vec3 v_l;
varying vec3 v_v;
varying vec3 v_caus;
varying float v_f0;
varying vec3 v_back;
varying float v_cov;     // thin stems: true width / drawn width (the rest is blended into the water)
varying vec3 v_out;      // wall plates: the rock's normal where the shelf grows

void vertex() {
	v_l = VERTEX;
	v_v = COLOR.rgb;
	// wall plates: the normal of the rock the shelf grows from (ReefDress._plate_xf: horizontal part along local +X,
	// height coded in the z / x scale ratio)
	float ry = clamp((length(MODEL_MATRIX[2].xyz) / max(length(MODEL_MATRIX[0].xyz), 1e-4) - 1.0) * 10.0, -0.95, 0.95);
	vec2 xh = MODEL_MATRIX[0].xz;
	xh /= max(length(xh), 1e-4);
	v_out = vec3(xh.x * sqrt(1.0 - ry * ry), ry, xh.y * sqrt(1.0 - ry * ry));
	if (kind == 3) {
		float w = max(VERTEX.y, 0.0);
		float ph = TIME * 0.55 + INSTANCE_CUSTOM.a * 20.0;
		VERTEX.x += sin(ph) * 0.07 * w * w;
		VERTEX.z += sin(ph * 0.8 + 1.3) * 0.05 * w * w;
	}
	v_cov = 1.0;
	if (kind == 3) {
		// keep stems at least ~1.4 px wide (no crawling dashes), fading the widened part into the water
		float sc = length(MODEL_MATRIX[0].xyz);
		float rw = COLOR.g * 0.06 * sc;
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		// NOTE: PROJECTION_MATRIX[1][1] is negative in this pipeline, so px < 0 and the widening below never runs. Kept
		// that way on purpose: the widened part is blended into the FOG colour, which is right against open water but
		// paints thin stems on rock (e.g. under the lip, where the fog colour is the bright water overhead) as pale
		// glowing scribbles. Fixing it needs a background-aware fade, not abs().
		float px = 2.0 * length(wp - water_cam_pos) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		float want = 0.7 * px;
		if (rw > 0.0 && want > rw) {
			VERTEX += NORMAL * (want - rw) / max(sc, 1e-3);
			v_cov = rw / want;
		}
	}
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = rf_safe_normal(MODEL_NORMAL_MATRIX * NORMAL, vec3(0.0, 1.0, 0.0));
	v_c = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 n = rf_safe_normal(v_n, vec3(0.0, 1.0, 0.0));     // (guarded: an interpolated normal can pass through zero)
	if (!FRONT_FACING) {
		n = -n;
	}
	float dist = length(v_w - water_cam_pos);
	float near = 1.0 - smoothstep(8.0, 45.0, dist);
	float seed = v_c.a;
	// world-scale mottling shared with the rock: tone and a touch of the encrusting-life palette
	float wm1 = rf_noise(v_w * 0.35 + 3.0);
	float wm2 = rf_noise(RF_ROT * v_w * 0.9 + 11.0);
	vec3 col = mix(v_c.rgb, rf_ramp(wm1 * 1.4 + seed * 0.5), 0.22) * (0.78 + 0.44 * wm2);
	float h = 0.0;
	float ao = clamp(v_v.r, 0.0, 1.0);   // sqrt(ao) below: a slightly negative baked AO would give NaN
	float top = 1.0;
	if (kind == 0) {
		// world-scale surface of a massive coral: meandering ridges (brain) or knobbly polyp mounds (star / boulder).
		// The fine pattern fades by pixel footprint (a polyp pit smaller than ~2 px is a single dark speck that
		// twinkles) into coarse mounds with the same mean, which hold at any distance; derivatives before the branch.
		float m = rf_noise(v_w * 1.7 + seed * 20.0) + 0.5 * rf_noise(v_w * 3.6 + seed * 7.0);
		float mfw = fwidth(m * 13.0);                       // ridge phase per pixel (rad)
		float cfw = length(fwidth(v_w * 5.0));              // polyp cells per pixel
		// coarse mounds (~0.3 m, with a finer octave that fades by footprint) and the dark gaps between them
		float lfw = length(fwidth(v_w * 7.0));
		float lump = smoothstep(0.3, 0.75, rf_noise(v_w * 3.2 + seed * 9.0) * 0.7
			+ mix(0.15, rf_noise(v_w * 7.0 + seed * 5.0) * 0.3, 1.0 - smoothstep(0.25, 0.6, lfw)));
		float ridge = mix(0.3 + 0.45 * lump, 0.5 + 0.5 * sin(m * 13.0), 1.0 - smoothstep(0.7, 1.6, mfw));
		if (fract(seed * 3.3) > 0.5) {
			float f1 = rf_cells(v_w * 5.0 + seed * 9.0).x;
			ridge = mix(0.6 + 0.55 * lump, smoothstep(0.08 - cfw, 0.4 + cfw, f1) * (0.8 + 0.4 * lump),
				1.0 - smoothstep(0.06, 0.16, cfw));
		}
		float far_mix = 1.0 - smoothstep(30.0, 90.0, dist);
		col *= mix(0.85, 0.55 + 0.6 * ridge, far_mix);
		h = ridge * 0.07 * far_mix;
	} else if (kind == 1) {
		// porous, lumpy sponge surface, dark open cavity
		vec3 cl = rf_cells(v_l * 11.0 + seed * 13.0);
		float pore = smoothstep(0.05, 0.32, cl.x);
		float lump = rf_noise(v_l * 5.0 + seed * 17.0);
		col *= mix(0.9, 0.6 + 0.45 * pore, near) * (0.85 + 0.3 * lump);
		h = pore * 0.02 + lump * 0.05;
		col *= mix(1.0, 0.18, v_v.g);
	} else if (kind == 2) {
		// plate / table coral: radial ridges and concentric growth rings on the top, a pale growing rim
		float r = v_v.b;
		float ang = atan(v_l.z, v_l.x + 1e-6);     // (never atan(0, 0))
		float ridges = 0.5 + 0.5 * sin(ang * 26.0 + rf_noise(v_l * 4.0 + seed * 9.0) * 4.0);
		float rfade = 1.0 - smoothstep(0.25, 0.9, fwidth(ang * 26.0));
		float rings = 0.5 + 0.5 * sin(r * 55.0 + rf_noise(v_l * 3.5 + seed * 9.0) * 5.0);
		top = smoothstep(-0.2, 0.4, n.y);
		// (a wall plate close up: stronger ridges and growth rings, the form of a shelf top now lit like the rock)
		// (within ~25 m a little more: a sunlit shallow shelf top shows its growth rings and bands)
		float wn = wall_plate ? 1.0 - smoothstep(20.0, 35.0, dist) : 0.0;
		float rk = wall_plate ? 1.7 : 1.0;
		float rg = wall_plate ? mix(2.6, 3.2, wn) : 1.0;
		col *= mix(1.0, 1.0 - rk * (0.2 - 0.3 * ridges), rfade * top) * mix(1.0, 1.0 - rg * (0.07 - 0.12 * rings), near * top);
		// broad structure that survives distance: an older, darker centre, wide growth bands, coarse radial ridges
		// and a few uneven growth sectors
		float bands = 0.5 + 0.5 * sin(r * 16.0 + rf_noise(v_l * 2.0 + seed * 5.0) * 2.5);
		float coarse = 0.5 + 0.5 * sin(ang * 9.0 + rf_noise(v_l * 1.5 + seed * 3.0) * 3.0);
		col *= mix(0.5, 1.0, smoothstep(0.1, 0.85, r)) * (0.8 + 0.4 * rf_noise(vec3(v_l.x * 1.2, r * 2.5, v_l.z * 1.2) + seed * 17.0));
		col *= mix(1.0, (0.8 + mix(0.36, 0.46, wn) * bands) * (0.9 + 0.2 * coarse), top);
		// the pale growing edge: the rolled bead of the margin (ReefProps.plate, r 0.9-1.0) on the upper side (gated by
		// 'top', so never a white sliver seen edge-on), and just inside it the shaded groove where the lip curls up: at
		// any distance the edge reads as a rolled lip with thickness, not a cut-out
		// (table corals on the reef top keep their thinner edge). On wall plates the pale edge grows unevenly along the
		// margin (some sectors pale, some like the plate) and calms where the bead is only a pixel or two wide on screen
		// (a uniform 1-px pale outline reads as a drawn stroke round a cut-out)
		float rfw = fwidth(r);
		float grow = 0.45 + 0.55 * smoothstep(0.3, 0.7, rf_noise(vec3(v_l.x, 0.0, v_l.z) * 1.8 + seed * 11.0));
		float rim_w = grow * mix(0.45, 1.0, 1.0 - smoothstep(0.03, 0.08, rfw));
		float rim = (wall_plate ? smoothstep(0.86, 0.97, r) * 0.8 * rim_w : smoothstep(0.92, 0.985, r) * 0.45) * top;
		float ring = (wall_plate ? smoothstep(0.76, 0.84, r) * (1.0 - smoothstep(0.88, 0.92, r))
			: smoothstep(0.7, 0.82, r) * (1.0 - smoothstep(0.86, 0.93, r))) * top;
		col *= 1.0 - 0.32 * ring;
		col = mix(col, min(col * (wall_plate ? 1.6 : 1.3) + vec3(wall_plate ? 0.012 : 0.008), vec3(0.6)), rim);
		// undersides: duller and darker (the lighting does most of it: they face the deep); the outer band of the
		// underside and the side of the lip are darkest (a shadow line under the shelf that never fades with distance)
		float ud = wall_plate ? 0.72 : 0.8;
		col *= mix(1.0, ud, 1.0 - top) * (1.0 - (wall_plate ? 0.6 : 0.45) * smoothstep(wall_plate ? 0.86 : 0.88, 0.97, r) * (1.0 - top));
		if (wall_plate) {
			// the part attached to (and buried in) the wall is in its shadow
			ao *= mix(0.45, 1.0, smoothstep(-0.55, 0.35, v_l.x));
			// a shelf top faces the light that the steep rock around it only grazes: keep it in the rock's tones where
			// that rock is dim, i.e. far away (the fog has taken the detail and only the shelf's brightness is left)
			// and deep (from ~30 m down the face carries no sunlit crust, and deep plates are dark brown: a sunlit pale
			// top there reads as a pale chip; the lighting normal leans too, below). Close up in the shallows the top is lit like the rock tops beside it (sun,
			// caustics), and its rings, ridges and rim show its form.
			float dim = min(mix(1.0, 0.6, smoothstep(25.0, 60.0, dist)), mix(1.0, 0.55, smoothstep(30.0, 65.0, -v_w.y)));
			col *= mix(1.0, dim, top);
		}
		// (wall plates: the broad growth bands and coarse ridges in stronger relief, so a sunlit top shows its form;
		// the fine terms stay low: their screen-space normal is constant per 2x2 pixel quad)
		float hb = wall_plate ? mix(2.0, 2.5, wn) : 1.0;
		h = (ridges * rfade * 0.01 + rings * 0.008 * near + (bands * 0.02 + coarse * 0.01) * hb) * top;
	} else {
		col *= 0.8 + 0.3 * mix(0.5, rf_noise(v_l * 30.0 + seed * 7.0), near);
	}
	col *= ao;
	vec3 nb = rf_bump(v_w, n, h, kind == 0 ? 1.0 : (kind == 2 ? 1.0 : near));
	if (kind == 2 && wall_plate) {
		// a far or deep wall plate is lit like the face it grows from: its lighting normal leans toward the rock's own
		// normal, so a shelf lit unlike the dim rock around it never reads as a pale chip or a dark slab. Not within
		// ~25 m in the shallows: there a shelf top catches the sun and the caustics like the sunlit rock tops beside it.
		float lean = max(0.7 * smoothstep(25.0, 60.0, dist), 0.65 * smoothstep(30.0, 65.0, -v_w.y));
		vec3 nl = mix(nb, v_out, lean * top);
		float nl2 = dot(nl, nl);
		nb = nl2 > 1e-8 ? nl * inversesqrt(nl2) : nb;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	col = rf_depth_mute(col, -v_w.y);
	vec3 rl = water_rel_light(v_w.y);
	ALBEDO = col * rl;
	EMISSION = col * sqrt(ao) * rl * rf_water_fill(nb, -water_cam_pos.y) * 0.25;
	if (roof_open > 0.0) {
		// under the lip: the roof's side light (reef.gdshader), from the smooth geometric normal. A prop carries no
		// baked openness: it follows the distance out from the roof's centre, fitted to the roof's own mean openness
		// (smoothstep(0.25, 0.75) of its baked AO on undersides, by distance out: QA/reef3_work/roofopen.gd).
		float und = roof_open * smoothstep(0.5, -0.2, n.y);
		vec2 rd = v_w.xz - roof_centre.xz;
		float rdl = length(rd);
		float rr = rdl / max(roof_radius, 1.0);
		float open = 0.76 * smoothstep(0.28, 0.72, rr) + 0.24 * smoothstep(0.8, 0.95, rr);
		rd = rdl > 1e-3 ? rd / rdl : vec2(1.0, 0.0);
		// 'out' turned towards the open blue, and the lip's ends dimmed, as on the roof (reef.gdshader)
		vec2 od = mix(rd, vec2(1.0, 0.0), roof_blue);
		float odl = length(od);
		od = odl > 1e-3 ? od / odl : vec2(1.0, 0.0);
		float reach = mix(roof_end, 1.0, smoothstep(0.58, 0.96, rd.x));
		float hzl = length(n.xz);
		float facing = hzl > 1e-3 ? dot(n.xz, od) / hzl : 0.0;
		vec3 hz = wb_backdrop(vec3(1.0, 0.0, 0.0), -water_cam_pos.y, 0.0);
		hz = mix(hz, dot(hz, WB_LUMA) * vec3(0.75, 0.95, 1.3), 0.5);
		float wrap = mix(roof_wrap, 1.0, smoothstep(-0.4, 0.9, facing));
		float side = hzl * wrap * mix(0.15, 1.0, open * open);
		// (col already carries the baked AO once: sqrt(ao) in all, like the roof's side light, which carries none of
		// the occlusion the side light itself stands for)
		EMISSION += col * inversesqrt(max(ao, 0.04)) * rl * hz * (roof_side * side + roof_floor * roof_prop_floor * open) * und * reach;
	}
	v_caus = rf_caustic(v_w, TIME);
	v_f0 = 0.16 * 0.0625 * water_spec_dim(v_w.y);
	v_back = kind == 3 ? vec3(0.3) : (kind == 2 ? vec3(wall_plate ? 0.05 : 0.12) : vec3(0.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.25 * water_spec_dim(v_w.y);
	vec4 fog = rf_fog(v_w);
	fog.a = 1.0 - (1.0 - fog.a) * v_cov;
	FOG = fog;
}

void light() {
	vec3 k = LIGHT_IS_DIRECTIONAL ? v_caus : vec3(1.0);
	DIFFUSE_LIGHT += rf_light_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, k);
	// thin tissue lets a little light through when lit from behind
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(-dot(NORMAL, LIGHT), 0.0) * v_back * (1.0 / PI);
	SPECULAR_LIGHT += rf_light_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, ROUGHNESS, v_f0) * k;
}
