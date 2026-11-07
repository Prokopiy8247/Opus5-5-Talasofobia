// NADIR - intact porthole glass with a cabin behind it (interior mapping). The disc lies in its local XY plane,
// +Z outward (toward the water). A ray from the eye through the glass is traced into a 3.4 x 3.4 x 5 m room in
// object space: black walls, a silted floor, one dark fallen shape per porthole. The room is lit only by the
// torch, and only where the torch shines through the glass aperture, so it shows when the beam points in and
// stays black otherwise. The glass itself is black and glossy (it still glints). No eyeshine: that belongs to
// the creature. Writes the same presence FOG as the other ship shaders.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float room_gain = 9.0;
uniform float glass_r = 1.62;
// presence and water light (ShipMesh.update_env, every frame)
uniform float fog_density = 0.0175;
uniform vec4 fog_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float presence = 1.0;
uniform float wl_on = 0.0;
global uniform float g_depth;
global uniform vec3 g_torch_pos;
global uniform vec3 g_torch_dir;
global uniform float g_torch;

varying vec3 lpos;
varying vec3 lcam;
varying vec3 ltorch;
varying vec3 ltdir;     // torch direction in object space (MODEL_MATRIX in fragment() lacks the instance transform)
varying float seed;

const vec3 ROOM = vec3(1.7, 1.7, 5.0);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 1.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 1.0));
	float d = hash13(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// WATER LIGHT CONTRACT
float wl_grad(float depth) {
	return 1.0 - smoothstep(150.0, 330.0, depth);
}
vec3 wl_ratio(vec3 d, float depth) {
	float dn = smoothstep(0.0, 0.95, -d.y);
	dn = dn * dn * (3.0 - 2.0 * dn);
	vec3 r = mix(vec3(1.0), vec3(0.30, 0.36, 0.48), dn) * (1.0 + 0.35 * smoothstep(0.0, 0.66, d.y));
	return mix(vec3(1.0), r, wl_grad(depth));
}

// ray / axis-aligned box: (t near, t far)
vec2 box_hit(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax) {
	vec3 inv = 1.0 / rd;
	vec3 t0 = (bmin - ro) * inv;
	vec3 t1 = (bmax - ro) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	return vec2(max(max(tn.x, tn.y), tn.z), min(min(tf.x, tf.y), tf.z));
}

void vertex() {
	lpos = VERTEX;
	mat4 inv_m = inverse(MODEL_MATRIX);
	lcam = (inv_m * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	ltorch = (inv_m * vec4(g_torch_pos, 1.0)).xyz;
	ltdir = normalize((inv_m * vec4(g_torch_dir, 0.0)).xyz);
	seed = hash13(floor((MODEL_MATRIX[3].xyz - NODE_POSITION_WORLD) * 2.0) + 0.37);
}

void fragment() {
	vec3 ro = lpos;
	vec3 rd = normalize(lpos - lcam);
	rd += vec3(1e-5) * step(abs(rd), vec3(1e-5));
	// far side of the room box (x, y in [-1.7, 1.7], z in [-5, 0])
	vec3 tN = (vec3(sign(rd.xy) * ROOM.xy, -ROOM.z) - ro) / rd;
	float t = min(min(tN.x, tN.y), tN.z);
	vec3 h = ro + rd * max(t, 0.0);
	vec3 nrm = t == tN.z ? vec3(0.0, 0.0, 1.0) : (t == tN.x ? vec3(-sign(rd.x), 0.0, 0.0) : vec3(0.0, -sign(rd.y), 0.0));
	float alb = 0.03;   // black, rotted walls
	if (h.y < -ROOM.y + 0.05) {   // silted floor
		alb = 0.06 * (0.6 + 0.8 * vnoise2(h.xz * 2.3 + seed * 17.0));
	}
	// one dark fallen shape per cabin (a bunk, a locker): a box on the floor, its place hashed per porthole
	vec3 bc = vec3(mix(-0.9, 0.9, seed), -ROOM.y + 0.35 + 0.25 * fract(seed * 7.3), -mix(2.2, 3.8, fract(seed * 13.1)));
	vec3 bs = vec3(0.45 + 0.4 * fract(seed * 3.7), 0.35 + 0.25 * fract(seed * 7.3), 0.5);
	vec2 bh = box_hit(ro, rd, bc - bs, bc + bs);
	if (bh.x > 0.0 && bh.x < bh.y && bh.x < t) {
		h = ro + rd * bh.x;
		alb = 0.012;
		vec3 q = (h - bc) / bs;
		vec3 aq = abs(q);
		nrm = aq.x > aq.y && aq.x > aq.z ? vec3(sign(q.x), 0.0, 0.0) : (aq.y > aq.z ? vec3(0.0, sign(q.y), 0.0) : vec3(0.0, 0.0, sign(q.z)));
	}
	// torch light reaching h through the glass aperture
	vec3 lv = h - ltorch;
	float s = ltorch.z / max(ltorch.z - h.z, 1e-3);
	vec2 ap = mix(ltorch, h, clamp(s, 0.0, 1.0)).xy;
	float aperture = smoothstep(glass_r, glass_r - 0.25, length(ap)) * step(0.0, ltorch.z);
	float dl = length(lv);   // object space is orthonormal: metres as in the world
	float cone = smoothstep(0.82, 0.95, dot(lv / max(dl, 1e-3), ltdir));
	float ndl = clamp(dot(nrm, -normalize(lv)), 0.0, 1.0);
	float lit = cone * aperture * clamp(g_torch, 0.0, 1.0) * pow(max(dl, 0.4), -0.55) * exp(-fog_density * dl) * (0.25 + 0.75 * ndl);
	// water eats the red on the way in and out (same law as the hull)
	float path = length(VERTEX) + dl;
	vec3 ab = clamp(exp(-vec3(0.020, 0.008, 0.005) * (path - 52.0)), vec3(0.0), vec3(1.25));
	vec3 room = vec3(alb) * vec3(1.0, 0.93, 0.85);
	EMISSION = room * lit * room_gain * mix(vec3(1.0), ab, clamp(g_torch, 0.0, 1.0));
	// the glass: black, glossy, grimy at the rim
	float rim = smoothstep(glass_r - 0.35, glass_r, length(lpos.xy));
	ALBEDO = vec3(0.01, 0.012, 0.012) * rim;
	ROUGHNESS = mix(0.06, 0.5, rim);
	SPECULAR = 0.5;
	METALLIC = 0.0;

	vec3 dw = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float fa = 1.0 - exp(-fog_density * length(VERTEX));
	vec3 wr = mix(vec3(1.0), wl_ratio(dw, g_depth), wl_on);
	FOG = vec4(fog_col.rgb * wr / mix(vec3(1.0), wr, fa), max(fa, 1.0 - presence));
}
