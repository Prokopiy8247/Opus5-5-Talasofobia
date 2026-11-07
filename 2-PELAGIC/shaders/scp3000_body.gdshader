shader_type spatial;
// The endless procedural continuation of SCP-3000's body (shares the wave, staging and skin with the finished mesh).
// UV2 = (body parameter s (continues past 1), lateral wave scale), CUSTOM0 = (side.x, side.z, angle around body,
// d(wave scale)/d(arc) per model m). The wave scale (SCP3000._ext_wave_scale) eases the swim wave out on bends too
// tight for it (it would fold the inner side of the tube into a crease); 1 elsewhere.
render_mode cull_back, depth_draw_opaque, shadows_disabled;
#include "res://shaders/water_common.gdshaderinc"
#include "res://shaders/scp3000_common.gdshaderinc"

uniform sampler2D detail_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D relief_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 olive : source_color = vec4(0.357, 0.388, 0.314, 1.0);
uniform vec4 dark : source_color = vec4(0.149, 0.173, 0.149, 1.0);
uniform float skin_gain = 1.7;
uniform float ridge_amp = 0.12;
uniform float ext_s0 = 0.61;              // body parameter where the extension starts (at the mesh cut)
uniform float rise_model = 0.0;           // the prefab is lowered by this (model m) while the front rises (SCP3000.gd)
uniform vec2 rise_arc = vec2(6.0, 76.0);  // model m from the junction: the rise blends out here (the line lies still)

varying vec3 v_wpos;
varying float v_arc;
varying float v_ang;

void vertex() {
	float s = UV2.x;
	vec2 w = body_wave(s);
	// scaled lateral offset and its slope along the arc (product rule: the scale itself varies slowly along the body)
	w = vec2(w.x * UV2.y, w.y * UV2.y + w.x * CUSTOM0.w);
	vec3 side = vec3(CUSTOM0.x, 0.0, CUSTOM0.y);
	VERTEX += side * w.x;
	float ridge = smoothstep(0.75, 0.15, abs(CUSTOM0.z));
	VERTEX += NORMAL * ridge * ridge_amp * sin(6.2831853 * (s * 22.0 - motion_time / 9.0));
	// the junction rises with the finished mesh, the far body (the dark line) lies still
	VERTEX.y += rise_model * smoothstep(rise_arc.x, rise_arc.y, (s - ext_s0) * spine_len);
	mat3 R = rot_y(-atan(w.y));
	NORMAL = R * NORMAL; TANGENT = R * TANGENT; BINORMAL = R * BINORMAL;
	v_arc = s * spine_len;
	v_ang = CUSTOM0.z;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(v_wpos - water_cam_pos);
	vec3 dc = creature_dist(dist);            // near detail, far darkening, top light
	vec3 ns = creature_safe_n(NORMAL);        // smooth geometric normal (view space, before the relief map)
	float ndv = clamp(dot(ns, VIEW), 0.0, 1.0);
	float rimv = creature_rim(NORMAL, VIEW);
	vec3 nw = (INV_VIEW_MATRIX * vec4(ns, 0.0)).xyz;
	// slow large-scale life of the far body's darkness (patches ~40-100 m, drifting): the skin's mottling as it
	// survives 300 m of water, a living mass, not a cut-out. Periodic around the body (cos / sin of the angle: no
	// seam on the belly); none near the junction with the mesh.
	float ja = v_arc - ext_s0 * spine_len;   // model m from the junction
	vec2 lq = vec2(v_arc * 0.05 - motion_time * 0.004, 1.6 * cos(v_ang) + 0.9 * sin(v_ang) + 7.0);
	float ln = skin_noise(lq) * 0.5 + skin_noise(lq * 2.3 + vec2(3.1, 1.7)) * 0.5;
	float life = 1.0 + (0.6 * ln - 0.3) * smoothstep(150.0, 300.0, dist) * smoothstep(10.0, 40.0, ja);
	// soft limb: as on the finished mesh's trunk at the junction (no seam), from ~60 model m on it comes in from 90 m
	// and is complete by 220 m (the dark line and the far body lie 150-250 m from the path)
	vec2 lramp = mix(vec2(150.0, 330.0), vec2(90.0, 220.0), smoothstep(10.0, 60.0, ja));
	vec4 fogv = creature_fog(v_wpos, v_arc / spine_len, rimv, creature_limb(ndv, dist, VIEWPORT_SIZE.y, lramp), life);
	vec4 sk = skin_proc(v_arc, v_ang, olive.rgb, dark.rgb, smoothstep(60.0, 220.0, dist));
	float folds = skin_folds(v_arc, v_ang);
	float top = creature_top(nw.y, dc.z, v_wpos.y);
	vec3 alb = sk.rgb * PROC_SKIN * skin_gain * (0.9 + 0.1 * folds) * top * mix(1.0, 0.45, dc.y);
	alb = creature_water_hue(alb, fogv.rgb, dist, v_wpos.y);
	ALBEDO = alb * water_rel_light(v_wpos.y) * below_dark(v_wpos.y);
	float shimmer = skin_noise(vec2(v_arc * 0.23 - motion_time * 0.03, v_ang * 1.3 + 5.0));   // wet sheen, drifting
	vec2 g = proc_gloss(shimmer, sk.a, deep_gloss(v_wpos.y));
	float fg = smoothstep(50.0, 200.0, dist);
	ROUGHNESS = mix(g.x, 0.75, fg);
	SPECULAR = mix(g.y, 0.08, fg) * water_spec_dim(v_wpos.y);   // no clearcoat on the creature
	NORMAL_MAP = skin_relief(relief_tex, detail_tex, v_arc, v_ang);
	NORMAL_MAP_DEPTH = 1.4 * mix(0.3, 1.0, dc.x);
	EMISSION = creature_rim_glow(fogv.rgb, rimv, nw.y, v_arc / spine_len) + creature_top_scatter(fogv.rgb, ndv, nw.y, dist);
	FOG = fogv;
}
