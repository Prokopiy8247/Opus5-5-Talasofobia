shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Verdigris stone of the beat 4 statue (assets/generated/statue.glb) at three scales:
//  large  - blotches, slow streaks, drip stains below the shoulders and the hands, a few long cracks;
//  medium - masonry courses (course_h) wrapped around the body, showing in patches, a pale silt mantle on
//           every upward face;
//  small  - grain, flat crusts of sponge and barnacle, grey-brown silt specks near the camera.
// Vertex COLOR: r = ambient occlusion (1 open), g = 1 for silt meshes (the skirt under the liner), b = cavity.
// uw_reveal.y (0..1) turns the head around neck_pivot (head_down_deg: + bows further, - lifts;
// head_turn_deg: + turns toward +X, the statue's left, where the diver passes). Patterns live in the
// statue's local frame (taken before the head turn), so the stone does not swim when the head moves.
// keel_a / keel_b / keel_r: a capsule (world) around the liner's keel that darkens the palm under it.
// Drowned stone, not a mannequin: the head is weathered in the vertex shader (broad lumps and a few chipped
// bites out of its outline, head_relief; the right hand's fingers, the ring-folded sleeves and their buckled
// hems too, never the left palm); every pixel gets a bump relief (pitting, flat crusts, soft worn ledges)
// through screen-space derivatives (no tangents needed), dark stains run down the back and sides of the
// head, and silt settles on the relief that looks up.
// FACELESS: the front of the bowed head (the face oval, the forehead and the front of the crown, which is
// what the diver sees) is a plain, smooth blank: no stains, crusts, specks, cracks or bites there, since
// any spots or streaks on it are read as eyes, a mouth or a fringe of hair.
// In the water: below murk_top the body sinks into dark water (more the further below the eye and the
// further away), and far away the stone takes a light veil and less albedo contrast (veil_amount, flatten).
#include "res://shaders/inc/uw.gdshaderinc"

uniform vec3 neck_pivot = vec3(0.0, 372.0, 72.0);
uniform vec3 neck_axis = vec3(0.0, 0.866, 0.5);
uniform vec2 neck_blend = vec2(-14.0, 12.0);   // along the neck axis: weight 0 -> 1
uniform vec2 neck_radius = vec2(48.0, 70.0);   // distance from the axis: weight 1 -> 0
uniform float head_down_deg = -11.0;
uniform float head_turn_deg = 15.0;
uniform float head_override = -1.0;            // >= 0 replaces uw_reveal.y (tests)
uniform vec3 face_center = vec3(0.0, 396.9, 123.2);
uniform vec3 face_dir = vec3(0.0, -0.766, 0.643);
uniform float face_radius = 30.0;
uniform float streak_scale = 1.0;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.88;
uniform float course_h = 7.5;                  // masonry course height (m)
uniform float block_w = 11.0;                  // block length (m)
uniform float silt_amount : hint_range(0.0, 1.0) = 0.7;
uniform float crack_amount : hint_range(0.0, 1.0) = 0.8;
uniform vec3 keel_a = vec3(0.0);
uniform vec3 keel_b = vec3(0.0);
uniform float keel_r = 0.0;                    // 0 = no contact shadow
uniform vec3 head_center = vec3(0.0, 421.0, 103.0);
uniform float head_relief = 1.0;               // weathering, chips (head, right hand), sleeve masses (vertex)
uniform float bump_amount = 1.0;               // pixel relief: pits, encrustation, chipped ledges
uniform float stain_amount : hint_range(0.0, 1.0) = 0.6;   // dark streaks down the back and sides of the head
uniform float murk_top = -640.0;               // world y: the height murk starts here ...
uniform float murk_bottom = -880.0;            // ... and is full here
uniform float murk_amount : hint_range(0.0, 1.0) = 0.7;
uniform float veil_amount : hint_range(0.0, 1.0) = 0.16;   // extra water veil far away (contrast, depth)
uniform float flatten : hint_range(0.0, 1.0) = 0.25;       // far away: albedo pulled toward its mean

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 opos;
varying vec3 onrm;
varying vec4 vcol;
varying float face;
varying float chip;
varying float hfront;   // the front of the bowed head (1), see head_front
varying float limb;     // hands and sleeves (1): carved as single pieces, no masonry joints

// a chipped bite (m deep at c): steep walls, a flat-ish floor, like a broken-off flake
float bite(vec3 p, vec3 c, float r, float depth) {
	vec3 d = p - c;
	return depth * sqrt(max(1.0 - dot(d, d) / (r * r), 0.0));
}

// the head's carved relief (m, + outward): broad weathering and bites out of its outline as the diver sees
// it from the front-left (crown, both temples, the back of the skull, the jaw edge)
float head_bites(vec3 p) {
	return bite(p, vec3(-2.0, 466.0, 112.0), 14.0, 5.5) + bite(p, vec3(-20.5, 437.1, 139.9), 10.0, 3.5)
		+ bite(p, vec3(35.2, 427.4, 104.9), 12.0, 5.0) + bite(p, vec3(-34.2, 414.7, 103.7), 9.0, 3.0)
		+ bite(p, vec3(22.8, 392.3, 92.4), 7.0, 2.0) + bite(p, vec3(18.0, 455.0, 90.0), 10.0, 3.0);
}

// the front of the bowed head as the diver sees it: the face oval, the forehead and the front of the crown
// (1), not the very top, the sides or the back (0); statue-local, before the head turn, so it turns with it
float head_front(vec3 p) {
	vec3 d = p - head_center;
	float l = length(d);
	vec3 hd = d / max(l, 1e-3);
	return (1.0 - smoothstep(52.0, 64.0, l)) * smoothstep(0.02, 0.4, hd.z) * (1.0 - smoothstep(0.8, 0.95, hd.y));
}

// broad lumps; on the front only faintly (bulges there read as a brow and cheeks), and no bites there (a
// round bite in the forehead read as an eye socket): the bites stay on the outline, where they show the turn
float head_carve(vec3 p) {
	float fr = head_front(p);
	return ((uw_vnoise3(p * 0.06 + vec3(11.0, 3.0, 7.0)) - 0.5) * 2.4
		+ (uw_vnoise3(p * 0.17 + vec3(4.0, 9.0, 1.0)) - 0.5) * 0.7) * (1.0 - 0.65 * fr) - head_bites(p) * (1.0 - fr);
}

// the right hand (palm down on the slope): its four fingers were cast alike, so time made them differ -
// one fingertip broken off, flakes off two knuckles, the little finger worn down, uneven girths
float hand_bites(vec3 p) {
	return bite(p, vec3(-82.8, 202.2, 292.0), 10.0, 6.0) + bite(p, vec3(-104.2, 195.3, 254.2), 7.5, 2.8)
		+ bite(p, vec3(-71.0, 193.2, 251.3), 7.0, 2.4) + bite(p, vec3(-122.5, 195.3, 285.1), 7.5, 3.6);
}

float hand_carve(vec3 p) {
	return (uw_vnoise3(p * 0.09 + vec3(5.0, 1.0, 8.0)) - 0.5) * 3.0
		+ (uw_vnoise3(p * 0.23 + vec3(2.0, 6.0, 4.0)) - 0.5) * 1.1 - hand_bites(p);
}

// freshly broken stone (0..1) at the floor of a bite (head, right hand): paler, less weathered than the
// old surface around it
float chip_of(vec3 p) {
	return clamp((head_bites(p) * (1.0 - head_front(p)) + hand_bites(p)) / 3.0, 0.0, 1.0);
}

const vec3 RHAND_C = vec3(-98.0, 182.0, 255.0);
const vec3 PALM_C = vec3(111.3, 199.4, 249.2);
// the sleeves (shoulder, elbow, cuff of each arm, from tools_py/statue_sdf.py)
const vec3 ARM_RS = vec3(-74.0, 336.0, 88.0);
const vec3 ARM_RE = vec3(-112.0, 236.0, 126.0);
const vec3 ARM_RC = vec3(-107.2, 180.5, 163.2);
const vec3 ARM_LS = vec3(74.0, 336.0, 88.0);
const vec3 ARM_LE = vec3(124.0, 254.0, 128.0);
const vec3 ARM_LC = vec3(118.3, 217.7, 175.6);

// a thin line (x: distance in m to its centre, half-width hw) that fades with its pixel coverage once it is
// thinner than a pixel (far off, a full-strength aa line broke into rows of dark dashes). fwidth(x) alone fails
// at the line's centre, where x is V-shaped and the quad's differences cancel (isolated dark pixels), so the
// width is never taken below pf, the pixel footprint in metres.
float thin_line(float x, float hw, float pf) {
	float fw = max(fwidth(x), pf);
	return (1.0 - smoothstep(hw - fw, hw + fw, abs(x))) * clamp(2.0 * hw / fw, 0.0, 1.0);
}

float seg_dist(vec3 p, vec3 a, vec3 b) {
	vec3 ba = b - a;
	float t = clamp(dot(p - a, ba) / dot(ba, ba), 0.0, 1.0);
	return length(p - a - ba * t);
}

// the ring folds of a sleeve as statue_sdf.py sculpted them (sleeve_folds): outward offset (m) at p
float sleeve_rings(vec3 p, vec3 s, vec3 e, vec3 c, float sg) {
	vec3 a1 = normalize(e - s);
	vec3 a2 = normalize(c - e);
	float l1 = length(e - s);
	float t1 = dot(p - s, a1);
	float w = clamp((t1 - l1 + 20.0) / 40.0, 0.0, 1.0);
	w = w * w * (3.0 - 2.0 * w);
	vec3 ax = normalize(a1 * (1.0 - w) + a2 * w);
	float along = t1 * (1.0 - w) + (l1 + dot(p - e, a2)) * w;
	vec3 p1 = cross(ax, vec3(0.0, 1.0, 0.0));
	p1 /= max(length(p1), 1e-6);
	vec3 p2 = cross(ax, p1);
	vec3 q = p - e;
	float ph = along * 0.2 + 1.7 * sin(dot(q, p1) * 0.06 + sg) + 1.2 * sin(dot(q, p2) * 0.045 + 0.7);
	float ridge = (sqrt(sin(ph) * sin(ph) + 0.2) - 0.75) * 1.6;
	float ke = (along - l1) / 30.0;
	return ridge * (1.2 + 2.0 * exp(-ke * ke));
}

// the sleeves were sculpted as even rings (an accordion, a ribbed hose): in patches the rings are worn
// flat or silted over, and the cloth sags in uneven masses
float sleeve_arm(vec3 p, vec3 s, vec3 e, vec3 c, float sg) {
	float d = min(seg_dist(p, mix(s, e, 0.35), e), seg_dist(p, e, c));
	float w = (1.0 - smoothstep(48.0, 60.0, d)) * (1.0 - smoothstep(-6.0, 4.0, dot(p - c, normalize(c - e))));
	if (w <= 0.0) {
		return 0.0;
	}
	float worn = smoothstep(0.3, 0.62, uw_vnoise3(p * 0.028 + vec3(6.0, 2.0, 9.0)));
	return w * (-sleeve_rings(p, s, e, c, sg) * 0.9 * worn
		+ (uw_vnoise3(p * 0.04 + vec3(3.0, 8.0, 2.0)) - 0.5) * 4.0
		+ (uw_vnoise3(p * 0.11 + vec3(7.0, 1.0, 5.0)) - 0.5) * 1.8);
}

// the open end of a sleeve was cut flat (a planar ring with straight edges: a box next to the hand): the heavy
// hem buckles into a few deep folds that run back up the cuff and sag at the bottom. Never the forearm inside
// (radius < ~20 m) and never the inner wall deep in the hollow.
float cuff_hem(vec3 p, vec3 e, vec3 c, float sg) {
	vec3 ax = normalize(c - e);
	vec3 q = p - c;
	float al = dot(q, ax);
	vec3 r = q - ax * al;
	float rl = length(r);
	float w = smoothstep(-60.0, -6.0, al) * (1.0 - smoothstep(4.0, 12.0, al))
		* smoothstep(23.0, 31.0, rl) * (1.0 - smoothstep(56.0, 66.0, rl));
	if (w <= 0.0) {
		return 0.0;
	}
	vec3 p1 = normalize(cross(ax, vec3(0.0, 1.0, 0.0)));
	vec3 p2 = cross(ax, p1);
	float ang = atan(dot(r, p2), dot(r, p1));
	float folds = sin(ang * 3.0 + sg) * 0.6 + sin(ang * 5.0 + 1.9 * sg) * 0.4;
	// the lower side (the cloth hangs) bulges and sags more than the top
	float low = 1.0 - smoothstep(-0.8, 0.2, dot(r / max(rl, 1e-3), vec3(0.0, 1.0, 0.0)));
	return w * (folds * (3.8 + 2.4 * low) + (uw_vnoise3(p * 0.08 + vec3(3.0, 1.0, 6.0)) - 0.5) * 4.0);
}

float sleeve_carve(vec3 p) {
	return (sleeve_arm(p, ARM_RS, ARM_RE, ARM_RC, -1.0) + sleeve_arm(p, ARM_LS, ARM_LE, ARM_LC, 1.0)
		+ cuff_hem(p, ARM_RE, ARM_RC, 0.7) + cuff_hem(p, ARM_LE, ARM_LC, 2.3))
		* smoothstep(60.0, 75.0, length(p - PALM_C));
}

// vertex relief (m along the normal): the head, the right hand and the sleeves; never within 60 m of the
// left palm (the liner's fit depends on that surface)
float carve(vec3 p, float face_w) {
	float hw = (1.0 - smoothstep(50.0, 62.0, length(p - head_center))) * (1.0 - face_w * 0.75);
	float rw = 1.0 - smoothstep(58.0, 72.0, length(p - RHAND_C));
	return (hw * head_carve(p) + rw * hand_carve(p) + sleeve_carve(p)) * head_relief;
}

bool carved(vec3 p) {
	return length(p - head_center) < 62.0 || length(p - RHAND_C) < 72.0
		|| (min(min(seg_dist(p, mix(ARM_RS, ARM_RE, 0.35), ARM_RE), seg_dist(p, ARM_RE, ARM_RC)),
			min(seg_dist(p, mix(ARM_LS, ARM_LE, 0.35), ARM_LE), seg_dist(p, ARM_LE, ARM_LC))) < 68.0
			&& length(p - PALM_C) > 60.0);
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	face = smoothstep(0.8, 0.95, dot(NORMAL, normalize(face_dir)))
		* (1.0 - smoothstep(face_radius * 0.75, face_radius, length(VERTEX - face_center)));
	hfront = head_front(VERTEX);
	// (from the shoulder: masonry joints ran across the round shoulders and biceps like tiles)
	float sd = min(min(seg_dist(VERTEX, ARM_RS, ARM_RE), seg_dist(VERTEX, ARM_RE, ARM_RC)),
		min(seg_dist(VERTEX, ARM_LS, ARM_LE), seg_dist(VERTEX, ARM_LE, ARM_LC)));
	limb = max(1.0 - smoothstep(50.0, 62.0, sd), max(1.0 - smoothstep(58.0, 72.0, length(VERTEX - RHAND_C)),
		1.0 - smoothstep(55.0, 70.0, length(VERTEX - PALM_C))));
	// weather the head, the right hand and the sleeves: displace along the normal (the blank face keeps its
	// calm plane)
	chip = 0.0;
	if (head_relief > 0.0 && carved(VERTEX)) {
		float e = 0.8;
		float d0 = carve(VERTEX, face);
		vec3 g = (vec3(carve(VERTEX + vec3(e, 0.0, 0.0), face), carve(VERTEX + vec3(0.0, e, 0.0), face),
			carve(VERTEX + vec3(0.0, 0.0, e), face)) - vec3(d0)) / e;
		vec3 gt = g - NORMAL * dot(g, NORMAL);
		VERTEX += NORMAL * d0;
		NORMAL = normalize(NORMAL - gt);
		chip = chip_of(opos) * (1.0 - face * 0.75) * min(head_relief, 1.0);
	}
	vec3 ax = normalize(neck_axis);
	vec3 v = VERTEX - neck_pivot;
	float along = dot(v, ax);
	float lat = length(v - ax * along);
	float w = smoothstep(neck_blend.x, neck_blend.y, along) * (1.0 - smoothstep(neck_radius.x, neck_radius.y, lat));
	float rv = head_override >= 0.0 ? head_override : uw_reveal.y;
	float k = clamp(rv, 0.0, 1.0) * w;
	float a = radians(head_down_deg) * k;
	float b = radians(head_turn_deg) * k;
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(a), sin(a)), vec3(0.0, -sin(a), cos(a)));
	mat3 ry = mat3(vec3(cos(b), 0.0, -sin(b)), vec3(0.0, 1.0, 0.0), vec3(sin(b), 0.0, cos(b)));
	mat3 r = ry * rx;
	VERTEX = neck_pivot + r * v;
	NORMAL = r * NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

// distance (m) to the nearest edge of a jittered 3D cell pattern (cracks), cell size cs
float crack_edge(vec3 p, float cs) {
	vec3 q = p / cs;
	vec3 iq = floor(q);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = iq + vec3(float(x), float(y), float(z));
				vec3 o = vec3(uw_hash13(c + 0.7), uw_hash13(c + 3.1), uw_hash13(c + 5.9));
				float d = length(c + o - q);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return (d2 - d1) * 0.5 * cs;
}

void fragment() {
	vec3 n0 = normalize(wnrm);
	vec3 on = normalize(onrm);
	float ao = vcol.r;
	float cav = vcol.b;
	float silt_mesh = vcol.g;
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float near_f = 1.0 - smoothstep(25.0, 140.0, dist);
	float face_k = clamp(face, 0.0, 1.0);
	// the plain blank: the face oval and the front of the bowed head carry no marks at all
	float plain = max(face_k, clamp(hfront, 0.0, 1.0));
	float lmb = clamp(limb, 0.0, 1.0);
	// ---- the liner's keel: a soft contact shadow, and the bed of silt it lies in (the banks along the hull
	// are silt meshes, so the palm around them must be silt too or their edges show)
	vec3 kab = keel_b - keel_a;
	float kt = clamp(dot(wpos - keel_a, kab) / max(dot(kab, kab), 1e-4), 0.0, 1.0);
	float kd = length(wpos - keel_a - kab * kt) - keel_r;
	float bed = keel_r > 0.0 ? 1.0 - smoothstep(keel_r + 4.0, keel_r * 2.0 + 16.0,
		kd + (uw_vnoise3(opos * 0.12 + vec3(2.0)) - 0.5) * 8.0) : 0.0;
	float stone_k = (1.0 - plain) * (1.0 - max(silt_mesh, bed));
	float dfade = 1.0 - smoothstep(170.0, 330.0, dist);
	float pfoot = 0.5 * length(fwidth(wpos));
	// ---- relief (m): pitting, flat crusts, soft worn ledges where an edge stands exposed; turned into a
	// normal with screen-space derivatives (no branches around it)
	float pit2 = uw_vnoise3(opos * 0.95 + vec3(2.0));
	float pits = uw_vnoise3(opos * 0.33 + vec3(5.0)) * 0.42 + pit2 * 0.14;
	// crusts (sponge sheets, barnacle mats) gather in loose clusters: noise-shaped, flat-topped, with wide
	// broken edges (round domes on a cell grid read as water droplets, and lined up into rows of stitches)
	float cluster = smoothstep(0.42, 0.7, uw_vnoise3(opos * 0.035 + vec3(8.0, 1.0, 3.0)));
	float cf = uw_vnoise3(opos * 0.17 + vec3(3.0, 5.0, 2.0)) * 0.6 + uw_vnoise3(opos * 0.53 + vec3(9.0, 4.0, 7.0)) * 0.4;
	float cth = mix(0.8, 0.6, cluster);
	float crust = smoothstep(cth, cth + 0.16, cf) * stone_k;
	float crust_h = crust * (0.18 + 0.16 * pit2);
	float exposed0 = smoothstep(0.55, 0.95, ao * (1.0 - cav));
	// worn ledges: rare, low and soft-edged (sharp noise thresholds drew contour lines with raised rims)
	float scar = smoothstep(0.68, 0.8, uw_vnoise3(opos * 0.09 + vec3(3.0, 7.0, 2.0)) + (cf - 0.5) * 0.1)
		* exposed0 * stone_k;
	float bfade = bump_amount * dfade;
	// (the blank keeps its fine pitting: smooth as an egg it read as plastic, not stone)
	float hgt = (pits * (1.0 - plain * 0.3) + crust_h - scar * 0.35) * bfade;
	vec3 dpx = dFdx(wpos);
	vec3 dpy = dFdy(wpos);
	vec3 r1 = cross(dpy, n0);
	vec3 r2 = cross(n0, dpx);
	float det = dot(dpx, r1);
	vec3 sgrad = sign(det) * (dFdx(hgt) * r1 + dFdy(hgt) * r2);
	vec3 n = normalize(max(abs(det), 1e-9) * n0 - sgrad);
	n = dot(n, n0) > 0.25 ? n : n0;
	// ---- large scale: blotches and slow streaks
	float blotch = uw_fbm3(opos * 0.012 + vec3(3.1, 0.0, 1.7));
	float streak = uw_fbm3(vec3(opos.x * 0.045, opos.y * 0.0045, opos.z * 0.045) / streak_scale);
	vec3 col = pal_verdigris * (0.78 + 0.45 * blotch);
	col = mix(col, pal_teal_far * 0.9, smoothstep(0.45, 0.75, streak) * 0.55 * (1.0 - plain * 0.7));
	// ---- masonry: courses of staggered blocks wrapped around the body (arc length around a vertical axis, so
	// round shoulders and thighs do not flip between x and z joints), sagging a little, showing only in
	// patches; none on the head, the hands and the sleeves (each carved from one block)
	vec3 an = abs(on);
	float hc = atan(opos.x, opos.z + 20.0) * 90.0;
	float cy = opos.y + (uw_vnoise3(opos * 0.025 + vec3(2.0, 9.0, 4.0)) - 0.5) * 4.0;
	float ci = floor(cy / course_h);
	float bw = block_w * mix(0.75, 1.5, uw_hash12(vec2(ci, 9.0)));
	float bu = hc / bw + 0.5 * mod(ci, 2.0) + uw_hash12(vec2(ci, 3.0)) * 0.37;
	float bi = floor(bu);
	float fy = fract(cy / course_h);
	float dj_h = min(fy, 1.0 - fy) * course_h;
	float dj_v = min(fract(bu), 1.0 - fract(bu)) * bw;
	float vis_h = mix(0.25, 1.0, uw_hash12(vec2(floor(cy / course_h + 0.5), 1.3)));
	float vis_v = step(0.35, uw_hash12(vec2(floor(bu + 0.5), ci + 0.5)));
	float side_f = 1.0 - smoothstep(0.55, 0.8, an.y);
	float jpatch = smoothstep(0.38, 0.62, uw_vnoise3(opos * 0.016 + vec3(5.0, 3.0, 8.0)));
	float joint = max(thin_line(dj_h, 0.2, pfoot) * vis_h, thin_line(dj_v, 0.16, pfoot) * vis_v * 0.8) * side_f * jpatch;
	float tone = (uw_hash12(vec2(bi, ci)) - 0.5) * side_f * jpatch;
	float head_k = 1.0 - smoothstep(52.0, 64.0, length(opos - head_center));
	float masonry = (1.0 - plain) * (1.0 - silt_mesh) * (1.0 - head_k) * (1.0 - lmb);
	col *= 1.0 + tone * 0.12 * masonry;
	// ---- folds and cavities: darker teal and moss
	float fold = clamp(cav * 1.1 + (1.0 - ao) * 0.35, 0.0, 1.0);
	col = mix(col, mix(pal_teal_far * 0.55, pal_moss * 0.7, blotch), fold * 0.8);
	// ---- drip stains running down below the shoulders and below both hands
	float src_sh = (1.0 - smoothstep(35.0, 70.0, length(vec2(abs(opos.x) - 78.0, opos.z - 92.0))))
		* step(opos.y, 345.0) * (1.0 - smoothstep(0.0, 170.0, 345.0 - opos.y));
	float src_hl = (1.0 - smoothstep(30.0, 60.0, length(opos.xz - vec2(108.0, 262.0))))
		* step(opos.y, 196.0) * (1.0 - smoothstep(0.0, 130.0, 196.0 - opos.y));
	float src_hr = (1.0 - smoothstep(30.0, 60.0, length(opos.xz - vec2(-98.0, 236.0))))
		* step(opos.y, 170.0) * (1.0 - smoothstep(0.0, 120.0, 170.0 - opos.y));
	float dn = uw_vnoise3(vec3(opos.x * 0.32, opos.y * 0.011, opos.z * 0.32)) * 0.7
		+ uw_vnoise3(vec3(opos.x * 0.9, opos.y * 0.03, opos.z * 0.9)) * 0.3;
	float drip = smoothstep(0.52, 0.8, dn) * max(src_sh, max(src_hl, src_hr)) * (1.0 - smoothstep(0.3, 0.75, n.y));
	col = mix(col, pal_deep * 1.4 + pal_moss * 0.08, drip * 0.6 * (1.0 - plain));
	// ---- long cracks (only where a slow mask allows), with a dark stained halo
	vec3 wq = opos * 0.05;
	vec3 cw = opos + (vec3(uw_vnoise3(wq), uw_vnoise3(wq + 7.0), uw_vnoise3(wq + 13.0)) * 0.7
		+ vec3(uw_vnoise3(wq * 2.7 + 3.0), uw_vnoise3(wq * 2.7 + 9.0), uw_vnoise3(wq * 2.7 + 17.0)) * 0.3) * 12.0;
	float ce = crack_edge(cw, 46.0);
	float cmask = smoothstep(0.55, 0.68, uw_fbm3(opos * 0.009 + vec3(11.0, 2.0, 5.0))) * crack_amount * (1.0 - plain) * (1.0 - silt_mesh);
	float crack = thin_line(ce, 0.3, pfoot) * cmask;
	float halo = (1.0 - smoothstep(0.3, 2.5, ce)) * cmask;
	col *= 1.0 - halo * 0.25;
	col = mix(col, pal_deep * 0.6, crack * 0.85);
	// ---- pale bone wear on exposed edges
	float up = smoothstep(0.45, 0.95, n.y);
	float exposed = smoothstep(0.55, 0.95, ao * (1.0 - cav));
	float wear_patch = smoothstep(0.35, 0.65, uw_fbm3(opos * 0.05 + vec3(7.0)) + up * 0.2);
	float wear = clamp(up * 0.8 + 0.25, 0.0, 1.0) * exposed * wear_patch;
	col = mix(col, mix(pal_verdigris, pal_bone, 0.6), wear * wear_amount * (1.0 - plain));
	// ---- the silt mantle on every face that looks up (and the skirt meshes); it fills the joints. On the
	// front of the head its edge is a smooth gradient (a noisy edge drew a hairline)
	float sn = uw_fbm3(opos * 0.07 + vec3(4.0, 1.0, 9.0));
	float drift = smoothstep(0.3, 0.62, uw_fbm3(opos * 0.022 + vec3(1.0, 6.0, 2.0)));
	float mantle = smoothstep(0.5, 0.9, n.y + (sn - 0.5) * mix(0.5, 0.1, plain)) * mix(mix(0.35, 1.0, drift), 0.5, plain)
		* (1.0 - face_k);
	col *= 1.0 - joint * 0.26 * masonry * (1.0 - crack) * (1.0 - mantle);
	mantle = max(mantle, max(silt_mesh, bed) * (0.75 + 0.25 * sn));
	vec3 silt_c = mix(pal_bone * 0.5, pal_bone * 0.36 + pal_moss * 0.12, smoothstep(0.35, 0.7, sn));
	col = mix(col, silt_c, clamp(mantle * silt_amount * 1.15, 0.0, 1.0));
	// ---- the blank face: smooth, a little darker than the skull, faintly polished
	col = mix(col, pal_verdigris * 0.66 * (0.96 + 0.08 * blotch), face_k * 0.85);
	// ---- dark stains running down the back and the sides of the head, the neck and the chest (never its
	// front: streaks over the forehead read as a fringe of hair)
	float sr = uw_vnoise3(vec3(opos.x * 0.21, opos.y * 0.009, opos.z * 0.21) + vec3(1.0, 0.0, 6.0)) * 0.75
		+ uw_vnoise3(vec3(opos.x * 0.6, opos.y * 0.02, opos.z * 0.6)) * 0.25;
	float stain_zone = (1.0 - smoothstep(55.0, 115.0, length(opos.xz - head_center.xz))) * smoothstep(250.0, 400.0, opos.y);
	float stain = smoothstep(0.5, 0.74, sr) * stain_zone * (1.0 - smoothstep(0.5, 0.9, n.y)) * (1.0 - plain);
	col = mix(col, pal_deep * 1.3 + pal_moss * 0.08, stain * stain_amount * (1.0 - silt_mesh));
	// ---- worn ledges and the bites out of the head: paler, less weathered stone
	float fresh = max(scar, clamp(chip * 1.6, 0.0, 1.0)) * (1.0 - plain);
	col = mix(col, mix(pal_verdigris, pal_bone, 0.3) * 0.92, fresh * 0.25);
	// ---- crust colour: grey bone and moss, varied in broad patches, faded at the broken edge
	vec3 crust_c = mix(pal_bone * 0.42, pal_moss * 0.5 + pal_bone * 0.08, smoothstep(0.3, 0.7, sn));
	col = mix(col, crust_c, crust * 0.34 * dfade);
	// ---- silt specks near the camera: sparse grey-brown flecks with soft edges (dark red-brown dots read
	// as blood spatter on the pale palm)
	float cs = 2.6;
	vec3 cell = floor(opos / cs);
	float pick = step(0.95, uw_hash13(cell * 1.07 + 5.3)) * (1.0 - plain);
	vec3 cen = (cell + 0.3 + 0.4 * vec3(uw_hash13(cell + 1.7), uw_hash13(cell + 7.1), uw_hash13(cell + 3.9))) * cs;
	float rad = cs * mix(0.12, 0.24, uw_hash13(cell + 9.2));
	float dotm = pick * (1.0 - smoothstep(rad * 0.4, rad, length(opos - cen))) * (1.0 - smoothstep(60.0, 170.0, dist));
	vec3 dot_c = mix(pal_bone * 0.3 + pal_rust * 0.05, pal_bone * 0.4 + pal_moss * 0.1, uw_hash13(cell + 2.2));
	col = mix(col, dot_c, dotm * 0.5);
	// ---- stone grain near the camera
	float grain = uw_vnoise3(opos * 1.3) * 0.6 + uw_vnoise3(opos * 3.7) * 0.4;
	col *= 1.0 + (grain - 0.5) * 0.22 * grain_amount * near_f * (1.0 - plain * 0.3);
	// ---- far away the stone sits in the water: less albedo contrast (around its mean tone)
	float far_k = smoothstep(60.0, 220.0, dist);
	col = mix(col, pal_verdigris * 0.8, flatten * far_k);
	// ---- contact shadow under the liner's keel: a dark seam right at the hull and a soft falloff (a wide
	// uniform one reads as a dark slab)
	float keel_occ = keel_r > 0.0 ? mix(0.4, 1.0, smoothstep(-1.0, keel_r * 0.8 + 3.0, kd))
		* mix(0.55, 1.0, smoothstep(-2.5, 1.5, kd)) : 1.0;
	float occl = mix(1.0, ao, 0.85) * keel_occ;
	ALBEDO = col * occl * uw_albedo_light(wpos.y);
	ROUGHNESS = clamp(roughness_base - wear * 0.1 + fold * 0.06 - face_k * 0.25 + mantle * 0.05, 0.0, 1.0);
	SPECULAR = mix(0.25, 0.4, face_k);
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	EMISSION = uw_ambient_glow(n, vw, wpos.y) * occl;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// ---- water: the normal fog; over it a height murk (the lower body sinks into the dark, the more the
	// further below the eye or the further away; the palm seen from beside it stays clear) and a light veil
	// far away. Both composite as a layer just in front of the stone: murk colour first, then the fog
	vec4 fog = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
	float layer = clamp((murk_top - wpos.y) / max(murk_top - murk_bottom, 1.0), 0.0, 1.0);
	float below = smoothstep(40.0, 200.0, CAMERA_POSITION_WORLD.y - wpos.y);
	float murk = layer * max(below, smoothstep(160.0, 380.0, dist)) * murk_amount;
	float veil = veil_amount * smoothstep(80.0, 300.0, dist);
	vec3 murk_c = mix(uw_water_col(wpos.y) * 0.35, fog.rgb, veil / max(murk + veil, 1e-4));
	float m = 1.0 - (1.0 - murk) * (1.0 - veil);
	float fa = 1.0 - (1.0 - fog.a) * (1.0 - m);
	FOG = vec4((murk_c * m * (1.0 - fog.a) + fog.rgb * fog.a) / max(fa, 1e-4), fa);
}
