shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Soft sun shafts: light falling from the surface along the sun direction. Each shaft is one strip along its
// axis (VERTEX = point on the axis) that turns around the axis to face the camera, so it never shows
// edge-on planes or crossed ribbons. A shaft is a bundle of thin rays inside a soft envelope (no slab
// edges), it fades in below the surface (no visible top end, the far ones longest), then dies away with depth
// as it widens (a cone of light thinning out downward: one that kept its brightness to its end read as a
// glowing rod or a pole standing on the floor), breaks up along its length and flickers slowly.
// UV.x = side (0 / 1), UV.y = along (0 at the surface .. 1 at the end), UV2.x = random, UV2.y = half width,
// COLOR.r = brightness, COLOR.g = rays across the bundle / 8, COLOR.b = shaft length / 300 m.
// Fog and depth light are evaluated per vertex (smooth along a shaft): the fragment stays cheap.
// It fades out where it meets geometry (depth texture), when seen end-on and near the camera.
#include "res://shaders/inc/uw.gdshaderinc"

uniform float intensity = 0.35;
uniform vec3 shaft_dir = vec3(0.18, -1.0, -0.22);
uniform float soft_dist = 16.0;    // metres over which a shaft melts into the ground behind it
uniform float shaft_len = 100.0;      // unused fallback (older meshes without COLOR.b)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;
varying float rnd;
varying float endon;
varying float vis;                    // fog transmission x depth light x brightness (per vertex)
varying float rays;
varying float len_m;
varying float spread_k;               // far shafts are drawn wider and fainter (a thin far one read as a lit pole)

void vertex() {
	vec3 axis = normalize(shaft_dir);
	vec3 c = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view = c - CAMERA_POSITION_WORLD;
	vec3 side = cross(axis, view);
	float sl = length(side);
	float vl = max(length(view), 1e-3);
	endon = sl / vl;                                  // sin of the angle between the view ray and the axis
	side = sl > 1e-4 ? side / sl : normalize(cross(axis, vec3(1.0, 0.0, 0.0)));
	spread_k = 1.0 + 1.6 * smoothstep(35.0, 170.0, vl);
	float hw = UV2.y * spread_k;
	vec3 w = c + side * (UV.x * 2.0 - 1.0) * hw;
	wpos = w;
	rnd = UV2.x;
	rays = max(COLOR.g * 8.0, 1.0);
	len_m = COLOR.b > 0.0 ? COLOR.b * 300.0 : shaft_len;
	vec4 f = uw_fog_eval(CAMERA_POSITION_WORLD, w);
	vis = (1.0 - f.a) * uw_light(w.y) * COLOR.r;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	vec2 uv = clamp(UV, 0.0, 1.0);    // MSAA samples outside the triangle: keep every pow()/log() argument >= 0
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float x = uv.x * 2.0 - 1.0;
	// soft envelope with wide skirts (zero at the strip edge): never a slab with a hard side
	float env = exp(-x * x * 3.0) * (1.0 - x * x);
	// the bundle: thin rays across it, slowly drifting sideways and changing along the length
	float along_m = uv.y * len_m;
	float r1 = uw_vnoise2(vec2(x * rays + rnd * 31.0 + uw_time * 0.045, along_m * 0.018 + rnd * 7.0));
	float r2 = uw_vnoise2(vec2(x * rays * 2.3 + rnd * 11.0 - uw_time * 0.06, along_m * 0.03 - uw_time * 0.02));
	float bundle = 0.45 + 0.55 * smoothstep(0.3, 0.8, r1 * 0.65 + r2 * 0.35);    // a glow with brighter rays in it
	// fades in below the surface (longer for far shafts, whose tops would line up along the invisible far
	// surface), brightest in the upper water, then dying away with depth, a long soft tail at the far end
	float dm = max(-wpos.y, 0.0);
	float top_len = mix(3.0, 15.0, smoothstep(15.0, 110.0, dist)) * (0.75 + 0.5 * rnd);
	float decay = mix(16.0, 28.0, rnd);
	float a = env * bundle * smoothstep(0.0, top_len, dm) * (0.1 + 0.9 * exp(-dm / decay));
	a *= 1.0 - smoothstep(0.15, 1.0, uv.y);
	// broken along its length: brighter and dimmer stretches drifting slowly (not one even rod)
	a *= 0.5 + 0.5 * smoothstep(0.2, 0.8, uw_vnoise2(vec2(along_m * 0.03 + rnd * 13.0, rnd * 3.0 + uw_time * 0.02)));
	// forward scattering: shafts glow when looking up toward the sun, recede when looking across or down-sun
	vec3 vdir = normalize(wpos - CAMERA_POSITION_WORLD);
	float fw = max(dot(vdir, -normalize(shaft_dir)), 0.0);
	a *= 0.55 + 1.2 * fw * fw * fw;
	// slow pulses travelling down the shaft, as if the waves above were focusing the light
	float sh = uw_vnoise2(vec2(along_m * 0.04 - uw_time * 0.3 + rnd * 17.0, x * 1.5 + rnd * 5.0));
	float flick = 0.7 + 0.3 * sin(uw_time * (0.2 + rnd * 0.3) + rnd * 30.0);
	a *= flick * (0.55 + 0.8 * sh);
	a *= smoothstep(0.18, 0.55, endon);               // end-on: it would collapse to a bright dot
	a *= smoothstep(4.0, 20.0, dist);
	a *= 1.0 - 0.5 * smoothstep(60.0, 180.0, dist);   // far shafts melt into the haze, not a row of slabs
	// soft where it meets the seabed, a hull or anything else
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -vp.z / vp.w;
	a *= clamp((scene_z + VERTEX.z) / soft_dist, 0.0, 1.0);
	a *= vis * intensity * 2.4 / spread_k;
	ALBEDO = pal_shaft * max(a, 0.0);
}
