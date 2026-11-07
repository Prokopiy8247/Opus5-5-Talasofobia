shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Props by the door lamp: solid.gdshader's look (world-noise colour, rust, moss on top faces, vertex AO) with
// a metallic parameter and a light() (lambert wrap + GGX like the built-ins) in which the lost sun has no
// specular at depth. local_light_gain scales omni/spot light (1 = like every other material; the door lamp
// carries its own depth compensation in its energy, see DoorLamp.gd). silt_amount lays pale silt on the
// upward faces (rubble: rock under a skin of silt, matching the seabed around it).
#include "res://shaders/inc/uw.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.19);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.3;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.3;
uniform float silt_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 silt_color = vec3(0.06, 0.075, 0.06);     // linear, like the deep silt by the wall foot
uniform float noise_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float local_light_gain = 1.0;   // gain for omni/spot lights

varying vec3 wpos;
varying vec3 wnrm;
varying float vao;
varying float lb_v;
varying float sk_v;
varying float f0_v;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vao = COLOR.r;
}

void fragment() {
	vec3 q = wpos / (3.0 * noise_scale);
	float n = uw_fbm3(q);
	vec3 col = base_color * (0.85 + 0.3 * n);
	float rust = smoothstep(0.75 - rust_amount * 0.4, 0.95, n + uw_vnoise3(q * 3.1) * 0.25) * rust_amount;
	col = mix(col, mix(pal_rust * 0.6, pal_rust, n), clamp(rust * 1.4, 0.0, 1.0));
	float up = smoothstep(0.2, 0.9, wnrm.y);
	float moss = up * smoothstep(0.4, 0.7, uw_fbm3(q * 1.7 + 4.0)) * moss_amount;
	col = mix(col, pal_moss * (0.8 + 0.4 * n), clamp(moss * 1.5, 0.0, 1.0));
	float silt = 0.0;
	if (silt_amount > 0.0) {
		// a soft skin on everything facing up, thinning down the flanks with a noisy edge
		silt = smoothstep(0.3, 0.8, wnrm.y + (uw_vnoise3(wpos * 2.3) - 0.5) * 0.5) * silt_amount;
		col = mix(col, silt_color * (0.85 + 0.3 * n), silt);
	}
	float ao = mix(1.0, vao, 0.85);
	float al = uw_albedo_light(wpos.y);
	ALBEDO = col * ao * al;
	ROUGHNESS = mix(roughness, 0.95, clamp(rust + moss + silt, 0.0, 1.0) * 0.6);
	METALLIC = metallic * (1.0 - rust) * (1.0 - silt);
	lb_v = local_light_gain;
	sk_v = clamp(uw_light(wpos.y) * 4.0, 0.0, 1.0);
	f0_v = 0.0144 * (1.0 - METALLIC) + 0.25 * METALLIC;
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	EMISSION = uw_ambient_glow(normalize(wnrm), vw, wpos.y) * ao;
	FOG = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float r = ROUGHNESS;
	float wrap = max(0.0, (ndl + r) / ((1.0 + r) * (1.0 + r))) / PI;
	DIFFUSE_LIGHT += LIGHT_COLOR * wrap * ATTENUATION * (LIGHT_IS_DIRECTIONAL ? 1.0 : lb_v);
	float cndl = clamp(ndl, 0.0, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float a = max(r * r, 0.002);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float dist_ggx = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float vis = 0.25 / ((cndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	float fr = f0_v + (1.0 - f0_v) * pow(1.0 - clamp(dot(LIGHT, h), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * dist_ggx * vis * fr * cndl
		* (LIGHT_IS_DIRECTIONAL ? sk_v : 1.0);
}
