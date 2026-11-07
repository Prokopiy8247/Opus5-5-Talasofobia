shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Boulders and rock chunks (scripts/gen/Rocks.gd, MultiMesh): the terrain's rock palette in 3D noise, darker
// cracks and pits, encrusting growth in the light, a thin film of silt or sand on the upward faces, and a base
// that sinks into the ground's own sediment colour (no dark rim: the rock grows out of the seabed), micro
// relief near the camera, and in the shallows the sun's caustics on the upward faces like the sand around them
// (added in light() for the directional light only; without them the rocks read as dark holes in the lit sand).
// Vertex COLOR.r = occlusion toward the base. INSTANCE_CUSTOM.r = tone variation 0..1. light() reproduces
// diffuse_lambert_wrap + a GGX lobe.
#include "res://shaders/inc/uw.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;
varying float vao;
varying float tone;
varying float caus_v;                   // fragment -> light: caustic intensity on this pixel

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vao = COLOR.r;
	tone = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 n0 = normalize(wnrm);
	float l = uw_light(wpos.y);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float mpp = max(length(fwidth(wpos)), 1e-4);
	float n3 = uw_fbm3(wpos * vec3(0.18, 0.4, 0.18) + tone * 13.0);
	float n4 = uw_vnoise3(wpos * 1.7);
	// each rock its own stone: tone picks a cold grey, a warmer brown-grey or a greenish dark
	vec3 base_a = mix(pal_steel * 1.3, pal_teal_far * 0.6, n3);
	vec3 base_b = mix(pal_rust * 0.45 + pal_steel * 0.6, pal_bone * 0.22, n3);
	vec3 rock = mix(base_a, base_b, smoothstep(0.35, 0.85, tone)) * (0.62 + 0.55 * n3);
	rock *= mix(0.72, 1.15, fract(tone * 7.31)) * (0.88 + 0.24 * n4) * mix(1.0, 1.3, smoothstep(0.45, 0.8, l));
	// dark cracks and pits (ridged noise), only where they stay wider than a pixel
	float cr = 1.0 - abs(uw_vnoise3(wpos * 2.3 + tone * 5.0) * 2.0 - 1.0);
	rock *= 1.0 - 0.35 * smoothstep(0.82, 0.97, cr) * (1.0 - smoothstep(0.03, 0.09, mpp));
	// pale encrusting crust and growth in the light, rusty stains
	float crust = smoothstep(0.6, 0.78, uw_vnoise3(wpos * 0.9 + 4.0));
	rock = mix(rock, mix(pal_bone * 0.3, pal_moss * 0.8, 0.5 + 0.5 * l), crust * 0.45);
	// a film of silt or sand on the upward faces, thinner in patches (a full even cap read as an egg)
	vec3 sand = mix(pal_bone * 0.26, pal_bone * 0.38, n4) * vec3(0.9, 1.0, 0.92);
	vec3 silt = mix(pal_moss * 0.55, pal_teal_far * 0.7, n4);
	vec3 dust = mix(silt, sand, smoothstep(0.15, 0.6, l));
	float top = smoothstep(0.5, 0.88, n0.y + (n3 - 0.5) * 0.6) * mix(0.5, 1.0, smoothstep(0.3, 0.6, uw_vnoise3(wpos * 0.6 + 2.0)));
	vec3 col = mix(rock, dust, top * 0.7);
	col = mix(col, pal_moss * (0.7 + 0.4 * n3), top * smoothstep(0.55, 0.75, n3) * 0.4);
	// the buried base takes the ground's sediment colour (scour and settled sand), not a dark outline
	float base = 1.0 - smoothstep(0.38, 0.62, vao + (n4 - 0.5) * 0.12);
	col = mix(col, dust * 0.85, base * 0.7);
	// micro relief from screen derivatives (uniform control flow)
	vec3 rp = vec3(wpos.x * 0.8253 + wpos.z * 0.5646, wpos.y, wpos.z * 0.8253 - wpos.x * 0.5646);
	float w1 = 1.0 - smoothstep(0.15, 0.4, 3.0 * mpp);
	float w2 = 1.0 - smoothstep(0.15, 0.4, 7.0 * mpp);
	float hm = (uw_vnoise3(rp * 3.0) * 0.5 * w1 + uw_vnoise3(rp.zxy * 7.0 + 3.3) * 0.2 * w2) * (1.0 - smoothstep(10.0, 45.0, dist)) * 0.12;
	vec3 dpdx = dFdx(wpos);
	vec3 dpdy = dFdy(wpos);
	vec3 r1 = cross(dpdy, n0);
	vec3 r2 = cross(n0, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(hm) * r1 + dFdy(hm) * r2);
	vec3 nw = abs(det) > 1e-9 ? normalize(abs(det) * n0 - grad) : n0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float ao = mix(1.0, vao, 0.45);
	ALBEDO = col * ao * uw_albedo_light(wpos.y);
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	EMISSION = uw_ambient_glow(nw, vw, wpos.y) * 0.6 * ao;
	FOG = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
	// caustics as on the terrain: fade with depth (gone by ~90 m), distance and when sub-pixel; up faces only
	float caus = uw_caustics(wpos.xz * 1.8, uw_time);
	caus *= l * l * (1.0 - smoothstep(22.0, 60.0, -wpos.y)) * (1.0 - smoothstep(30.0, 85.0, dist));
	caus_v = caus * 0.62 * (1.0 - smoothstep(0.06, 0.22, mpp)) * smoothstep(0.2, 0.8, nw.y);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float r = ROUGHNESS;
	float wrap = max(0.0, (ndl + r) / ((1.0 + r) * (1.0 + r))) / PI;
	DIFFUSE_LIGHT += LIGHT_COLOR * wrap * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (caus_v * clamp(ndl * 1.4 + 0.25, 0.0, 1.0) / PI);
	}
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
	float f0 = 0.0064;                    // 0.16 * SPECULAR^2, as the built-in
	float fr = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(LIGHT, h), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * dist_ggx * vis * fr * cndl;
}
