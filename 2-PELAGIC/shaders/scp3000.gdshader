shader_type spatial;
// SCP-3000 finished material + vertex-shader swimming (Part 10 / 10B).
// UV2 = (spine s, neck-turn weight); COLOR = (jaw, dorsal ridge, rigid head, eye).
// Note: the baked mask_tex only carries the teeth (alpha); its RGB was lost to a premultiplied-alpha resize in the
// bake, so roughness and the eye mask are rebuilt here (roughness from the albedo, eye from COLOR.a).
render_mode cull_back, depth_draw_opaque, shadows_disabled;
#include "res://shaders/water_common.gdshaderinc"
#include "res://shaders/scp3000_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;          // A teeth
uniform sampler2D detail_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D relief_tex : hint_normal, filter_linear_mipmap, repeat_enable;   // smooth FBM (coarse relief)
uniform sampler2D spine_tex : filter_linear, repeat_disable;              // rows: position, tangent, radius (model)

uniform vec3 jaw_hinge = vec3(14.5, 2.6, 25.5);
uniform float jaw_angle = 0.0;
uniform vec3 head_pivot = vec3(12.6, 2.8, 23.0);
uniform float head_yaw = 0.0;
uniform float head_pitch = 0.0;
uniform float s_neck = 0.19;
uniform float s_cut = 0.75;
uniform float ridge_amp = 0.12;
uniform float head_sway = 0.6;            // counter-sway of the head against the wave (fraction of the neck slope)
uniform float girth_hold = 6.6;           // model m: the trunk keeps this radius towards the cut (no tail taper)

uniform vec3 eye_c0 = vec3(17.78, 7.27, 31.26);
uniform vec3 eye_c1 = vec3(10.89, 7.36, 32.24);
uniform float eye_r0 = 1.27;
uniform float eye_r1 = 1.47;
uniform vec3 eye_g0 = vec3(0.8, 0.51, 0.32);   // rest gaze of each eyeball (the visible cap is around it)
uniform vec3 eye_g1 = vec3(-0.79, 0.37, 0.49);
uniform vec3 eye_look0 = vec3(0.8, 0.5, 0.3);
uniform vec3 eye_look1 = vec3(-0.8, 0.4, 0.5);
uniform vec4 eye_color : source_color = vec4(0.31, 0.94, 0.88, 1.0);
uniform float eye_glow = 9.0;
uniform float eye_pulse = 0.0;            // 0..1, driven by script (slow 6-8 s pulse + story)
uniform vec4 olive : source_color = vec4(0.357, 0.388, 0.314, 1.0);
uniform vec4 dark : source_color = vec4(0.149, 0.173, 0.149, 1.0);
uniform float skin_gain = 1.7;
// where the catchlight sits on each eyeball: the half vector between the camera and the light from above, in the
// rest head frame (SCP3000._update_eyes), so it is evaluated on the analytic sphere, not on the faceted mesh normal
uniform vec3 eye_catch0 = vec3(0.0, 0.7, 0.7);
uniform vec3 eye_catch1 = vec3(0.0, 0.7, 0.7);
// eyeshine gain of each eye from how squarely it looks at the camera (1 = ignores the diver, SCP3000.EYE_GAIN =
// locked on; SCP3000._update_eyes), and the lock itself (0..1: the pupils widen a little as the eyes hold the diver)
uniform vec2 eye_gain = vec2(1.0);
uniform float eye_lock = 0.0;

varying vec3 v_mpos;
varying vec3 v_wpos;
varying float v_s;
varying vec3 v_tube;                      // view-space radial direction from the spine (smooth tube normal)

vec3 spine_pos(float s) { return textureLod(spine_tex, vec2(clamp(s, 0.0, 1.0), 1.0 / 6.0), 0.0).xyz; }
vec3 spine_tan(float s) { return normalize(textureLod(spine_tex, vec2(clamp(s, 0.0, 1.0), 0.5), 0.0).xyz); }
float spine_rad(float s) { return textureLod(spine_tex, vec2(clamp(s, 0.0, 1.0), 5.0 / 6.0), 0.0).x; }

void vertex() {
	vec3 p = VERTEX;
	vec3 n = NORMAL; vec3 t = TANGENT; vec3 b = BINORMAL;
	float s = UV2.x;
	v_s = s;
	float turn_w = UV2.y;
	float jaw = COLOR.r; float ridge = COLOR.g; float rigid = COLOR.b;
	// 0. towards the cut (rest pose): the tail's fin blades and the frill flatten into a round trunk that holds its
	//    girth instead of thinning like a tail, and the last metres take exactly the cross-section the procedural
	//    body starts with (dorsal crest included), so the two meet without a step
	if (s > 0.44) {
		vec3 sp0 = spine_pos(s);
		vec3 tg0 = spine_tan(s);
		vec3 rd = p - sp0;
		float len = max(length(rd), 1e-4);
		vec3 dir = rd / len;
		float r_s = max(spine_rad(s), 0.5);
		float w_f = smoothstep(0.46, 0.56, s);
		float l2 = mix(len, min(len, r_s * (1.08 + 0.22 * ridge)), w_f);
		l2 *= mix(1.0, max(1.0, girth_hold / r_s), w_f);
		vec3 sd0 = normalize(vec3(-tg0.z, 0.0, tg0.x));
		vec3 up0 = normalize(cross(sd0, tg0));
		float ang = atan(-dot(dir, sd0), dot(dir, up0));
		float wm = smoothstep(s_cut - 0.06, s_cut - 0.012, s);
		l2 = mix(l2, girth_hold * ext_profile(0.0, ang), wm);
		p = sp0 + dir * l2;
		n = normalize(mix(n, dir, wm));
	}
	v_mpos = p;
	// smooth tube normal (radial from the spine): the far trunk's soft limb and top scatter follow the body's round
	// form, not the sculpted wrinkles of the mesh normal
	vec3 tn = p - spine_pos(s);
	tn *= inversesqrt(max(dot(tn, tn), 1e-10));
	// 1. jaw opens about its hinge (teeth stay rigid inside the jaw region)
	if (jaw > 0.002) {
		mat3 J = rot_axis(vec3(1.0, 0.0, 0.0), jaw_angle * jaw);
		p = J * (p - jaw_hinge) + jaw_hinge; n = J * n; t = J * t; b = J * b;
	}
	// 2. head turn about the neck pivot, plus a few degrees of counter-sway against the body wave
	vec2 wn = body_wave(s_neck);
	float sway = -atan(wn.y) * head_sway;
	float yaw = (head_yaw + sway) * turn_w;
	if (abs(yaw) + abs(head_pitch * turn_w) > 0.0001) {
		vec3 lat = normalize(cross(vec3(0.0, 1.0, 0.0), spine_tan(s_neck)));
		mat3 H = rot_y(yaw) * rot_axis(lat, head_pitch * turn_w);
		p = H * (p - head_pivot) + head_pivot; n = H * n; t = H * t; b = H * b; tn = H * tn;
	}
	// 3. serpentine travelling wave along the baked spine; the rigid head rides on the neck value
	float se = mix(s, s_neck, rigid);
	vec2 w = body_wave(se);
	vec3 tg = spine_tan(se);
	vec3 side = normalize(vec3(-tg.z, 0.0, tg.x) + vec3(0.0001));
	p += side * w.x;
	mat3 R = rot_y(-atan(w.y) * (1.0 - rigid));
	n = R * n; t = R * t; b = R * b; tn = R * tn;
	v_tube = (MODELVIEW_MATRIX * vec4(tn, 0.0)).xyz;
	// 4. dorsal ridge ripple (slow: a fin on a giant)
	p += n * ridge * ridge_amp * sin(6.2831853 * (s * 22.0 - motion_time / 9.0));
	// 5. the tail beyond the cut folds into the body; the procedural body continues from there
	if (s > s_cut) {
		vec2 wc = body_wave(s_cut);
		vec3 tc = spine_tan(s_cut);
		vec3 c = spine_pos(s_cut) + normalize(vec3(-tc.z, 0.0, tc.x)) * wc.x;
		p = mix(p, c, smoothstep(s_cut, s_cut + 0.012, s));
	}
	VERTEX = p; NORMAL = normalize(n); TANGENT = normalize(t); BINORMAL = normalize(b);
	v_wpos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

// The eyeball cap from geometry (the vertex mask misses the painted pupil): on the sphere, within ~60 deg of the
// rest gaze, with a soft edge into the lids (no hard ring of wet gloss against the skin).
float eye_cap(vec3 mp, vec3 c, float r, vec3 g) {
	vec3 d = mp - c;
	float l = length(d);
	return (1.0 - smoothstep(1.0, 1.1, l / r)) * smoothstep(0.38, 0.6, dot(d / max(l, 1e-4), normalize(g)));
}

vec3 triplanar_detail(vec3 mp, vec3 nrm) {
	vec3 bw = nrm * nrm; bw *= bw; bw /= max(bw.x + bw.y + bw.z, 1e-6);
	vec3 a = texture(detail_tex, mp.zy * 0.9).xyz;
	vec3 c = texture(detail_tex, mp.xz * 0.9).xyz;
	vec3 d = texture(detail_tex, mp.xy * 0.9).xyz;
	return a * bw.x + c * bw.y + d * bw.z;
}

void fragment() {
	float dist = length(v_wpos - water_cam_pos);
	vec3 dc = creature_dist(dist);            // near detail, far darkening, top light
	vec3 alb = texture(albedo_tex, UV).rgb;
	// facing term of the interpolated normal: wet gloss and catchlight only where the eye faces the camera (GGX on a
	// near-mirror surface at grazing angles throws single-pixel HDR fireflies along the eyeball rim)
	float facing = smoothstep(0.2, 0.5, dot(NORMAL, VIEW));
	vec3 srgb = sqrt(alb);                    // close enough to the baked sRGB values for the masks below
	float lum = (srgb.r + srgb.g + srgb.b) / 3.0;
	float teeth = texture(mask_tex, UV).a;
	float eye = smoothstep(0.35, 0.85, COLOR.a);
	if (v_s < 0.1) {
		eye = max(eye, max(eye_cap(v_mpos, eye_c0, eye_r0, eye_g0), eye_cap(v_mpos, eye_c1, eye_r1, eye_g1)));
	}
	eye *= 1.0 - teeth;
	float gum = smoothstep(0.02, 0.07, srgb.r - srgb.g) * (1.0 - teeth) * (1.0 - eye);
	vec3 nw = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// skin only: teeth and eyes keep their own colour
	float skin = 1.0 - clamp(eye + teeth, 0.0, 1.0);
	alb *= mix(1.0, skin_gain, skin);
	// blend into the procedural skin of the endless body before the cut (albedo, gloss and relief)
	float blend = smoothstep(s_cut - 0.12, s_cut - 0.005, v_s);
	float shimmer = skin_noise(vec2(v_s * spine_len * 0.23 - motion_time * 0.03, v_mpos.y * 0.7 + v_mpos.x * 0.3));
	float top = creature_top(nw.y, dc.z, v_wpos.y);
	float rimv = creature_rim(NORMAL, VIEW) * (1.0 - eye);
	// the trunk (not the head) far away: soft limb and top scatter on the smooth tube normal, as on the endless body
	vec3 tube = creature_safe_n(v_tube);
	float tube_ndv = clamp(dot(tube, VIEW), 0.0, 1.0);
	float trunk = smoothstep(0.15, 0.3, v_s);
	vec4 fogv = creature_fog(v_wpos, v_s, rimv, creature_limb(tube_ndv, dist, VIEWPORT_SIZE.y, vec2(150.0, 330.0)) * trunk, 1.0);
	vec2 pg = vec2(0.0);
	vec3 relief = vec3(0.5, 0.5, 1.0);
	if (blend > 0.0) {
		vec3 sp = spine_pos(v_s); vec3 tg = spine_tan(v_s);
		vec3 rad = v_mpos - sp;
		vec3 sd = normalize(vec3(-tg.z, 0.0, tg.x));
		vec3 up = normalize(cross(sd, tg));
		float ang = atan(-dot(rad, sd), dot(rad, up));   // 0 = top, as on the procedural body
		vec4 sk = skin_proc(v_s * spine_len, ang, olive.rgb, dark.rgb, smoothstep(60.0, 220.0, dist));
		float folds = skin_folds(v_s * spine_len, ang);
		alb = mix(alb, sk.rgb * PROC_SKIN * skin_gain * (0.9 + 0.1 * folds), blend);
		float shimmer_p = skin_noise(vec2(v_s * spine_len * 0.23 - motion_time * 0.03, ang * 1.3 + 5.0));
		pg = proc_gloss(shimmer_p, sk.a, deep_gloss(v_wpos.y));
		relief = skin_relief(relief_tex, detail_tex, v_s * spine_len, ang);
	}
	// the gums (lifted a little so the upper teeth do not hang from a black band); the light from above shades
	// the jaw, throat and flanks
	alb = mix(alb, alb * 1.5, gum * 0.5);
	alb *= mix(1.0, top, skin);
	// teeth: ivory, darker towards the roots in the gum
	vec3 ivory = vec3(0.36, 0.32, 0.22) * (0.75 + 0.5 * lum);
	alb = mix(alb, ivory * mix(0.45, 1.0, smoothstep(0.35, 0.95, teeth)), teeth);
	// far: lit detail fades first, the body goes to a dark mass (silhouette before skin) in the water's hue
	alb *= mix(1.0, 0.45, dc.y * skin);
	alb = mix(alb, creature_water_hue(alb, fogv.rgb, dist, v_wpos.y), skin);
	vec3 depth_tint = water_rel_light(v_wpos.y) * below_dark(v_wpos.y);
	ALBEDO = alb * depth_tint;
	// wet skin; in the deep only a broad soft sheen (the sun is no longer a sharp light source down there)
	float gl = deep_gloss(v_wpos.y);
	float rough = 0.36 + 0.18 * (1.0 - smoothstep(0.15, 0.45, lum));
	rough *= mix(1.0, 0.88, shimmer);
	rough = mix(rough, max(rough, 0.5), 1.0 - gl);
	ROUGHNESS = mix(rough, 0.5, teeth);
	SPECULAR = mix(mix(0.24, 0.4, gl), 0.3, teeth);
	if (blend > 0.0) {
		ROUGHNESS = mix(ROUGHNESS, pg.x, blend);
		SPECULAR = mix(SPECULAR, pg.y, blend);
	}
	// gloss falls off with distance: no sharp glints on a body seen through 100+ m of water
	float fg = smoothstep(50.0, 200.0, dist);
	ROUGHNESS = mix(ROUGHNESS, 0.75, fg * (1.0 - eye));
	SPECULAR = mix(SPECULAR, 0.08, fg * (1.0 - eye));
	vec3 det = triplanar_detail(v_mpos, creature_safe_n(v_mpos - spine_pos(v_s)));
	vec3 nm = texture(normal_tex, UV).xyz;
	nm = mix(nm, det, 0.3 * skin * dc.x);
	nm = mix(nm, relief, blend);
	// the eyeball is smooth: its normal is flat over a wider ring than the wet gloss below, so no half-blended skin
	// bump ever meets the lower roughness at the rim of the cap
	nm = mix(nm, vec3(0.5, 0.5, 1.0), smoothstep(0.0, 0.5, eye));
	NORMAL_MAP = creature_safe_n(nm * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.4 * mix(0.3, 1.0, dc.x);
	// the eyes: a wet, domed ball under a heavy lid; a large dark pupil that follows the gaze, ringed by a luminous
	// iris that is brightest at the pupil and falls off into a dark limbal ring; its eyeshine wakes as it locks on
	if (eye > 0.01) {
		bool first = distance(v_mpos, eye_c0) < distance(v_mpos, eye_c1);
		vec3 ec = first ? eye_c0 : eye_c1;
		vec3 look = creature_safe_n(first ? eye_look0 : eye_look1);
		vec3 rest = creature_safe_n(first ? eye_g0 : eye_g1);
		float gain = first ? eye_gain.x : eye_gain.y;
		vec3 rd = creature_safe_n(v_mpos - ec);
		float c = dot(rd, look);
		float ang = acos(clamp(c, -1.0, 1.0));
		vec3 sd = creature_safe_n(cross(look, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
		vec3 uv_ = creature_safe_n(cross(sd, look));
		float ex = dot(rd, sd);
		float ey = dot(rd, uv_);
		// pupil ~60 % of the iris, a little taller than wide (sin of the angle off the look axis); it widens as the
		// eye locks on. Front half only (the components shrink again behind the ball).
		float pe = mix(0.29, 0.325, eye_lock);
		float pr = sqrt(max(ex * ex + ey * ey * 0.78, 0.0));
		float pupil = (1.0 - smoothstep(pe - 0.025, pe + 0.015, pr)) * step(0.0, c);
		float ring = smoothstep(0.46, 0.6, ang);
		float az = atan(ey, ex + ((abs(ex) + abs(ey)) < 1e-6 ? 1e-6 : 0.0));   // atan(0, 0) is undefined
		float fib = 0.62 + 0.38 * (0.5 + 0.5 * sin(az * 41.0 + sin(az * 7.0) * 2.0)) * smoothstep(0.2, 0.3, ang);
		float iris = (1.0 - pupil) * (1.0 - ring) * fib;
		// brightest next to the pupil, falling off towards the limbus
		float tq = clamp((ang - pe) / 0.21, 0.0, 1.0);
		float glow_core = 0.1 + 0.9 * (1.0 - tq) * (1.0 - tq);
		// the lid's soft shadow over the upper part of the ball, and the ball darkening towards its rim (domed)
		vec3 up_e = creature_safe_n(vec3(0.0, 1.0, 0.0) - rest * rest.y);
		float lid = smoothstep(0.18, 0.62, dot(rd, up_e));
		float ball = smoothstep(0.35, 0.9, dot(rd, rest));
		vec3 eye_alb = (vec3(0.015, 0.03, 0.035) + eye_color.rgb * 0.06 * iris) * (1.0 - 0.6 * lid) * mix(0.55, 1.0, ball);
		ALBEDO = mix(ALBEDO, eye_alb, eye);
		// wet, but never a near-mirror (the sun is a dim broad source at this depth; the catchlight below is the
		// wet glint): the gloss eases in only on the flat inner cap where it faces the camera, and the specular
		// fades out towards the limb (grazing view, interpolated normals turning away)
		float wet = smoothstep(0.5, 1.0, eye) * facing;
		// the wet gloss belongs to the cornea over the iris; the dark ball around it only takes a broad dull sheen
		// (a sharp highlight of the light from above there sat as a detached glint above or beside the iris)
		float sclera = smoothstep(0.52, 0.68, ang) * eye;
		ROUGHNESS = mix(mix(ROUGHNESS, 0.26, wet), 0.62, sclera);
		SPECULAR = mix(SPECULAR, 0.45, wet) * mix(1.0, facing, eye) * (1.0 - 0.8 * sclera);
		float pulse = 0.82 + 0.18 * eye_pulse;
		// a soft wet catchlight of the faint light from above (the sun is a dim, broad source down here): a small soft
		// spot on the analytic eyeball sphere where it mirrors that light to the camera. A reflection lobe on the
		// mesh normal aliased into arcs of single white pixels along the faceted rim of the cap.
		vec3 hc = creature_safe_n(first ? eye_catch0 : eye_catch1);
		float cc = dot(rd, hc);
		float catch_l = (smoothstep(0.990, 0.9985, cc) * 1.6 + smoothstep(0.965, 0.99, cc) * 0.1) * water_light_scale * facing;
		// the catchlight: the blue-green light down here, plus a little of the iris glow on the wet cornea (a neutral
		// or blue-white highlight next to the cyan iris reads as a pink or lilac blob)
		EMISSION = (eye_color.rgb * eye_glow * gain * iris * glow_core * pulse * (1.0 - 0.5 * lid) + vec3(0.3, 0.82, 0.95) * catch_l) * eye;
	}
	SPECULAR *= water_spec_dim(v_wpos.y);
	vec3 tube_w = (INV_VIEW_MATRIX * vec4(tube, 0.0)).xyz;
	EMISSION += creature_rim_glow(fogv.rgb, rimv, nw.y, v_s) + creature_top_scatter(fogv.rgb, tube_ndv, tube_w.y, dist) * trunk;
	FOG = fogv;
}
