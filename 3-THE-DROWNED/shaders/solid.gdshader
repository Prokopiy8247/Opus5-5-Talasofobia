shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Generic sunken object: base colour with world-noise variation, rust and moss, optional emission.
// Vertex COLOR.r = ambient occlusion (1 = open).
#include "res://shaders/inc/uw.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.19);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.3;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.3;
uniform float noise_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform bool use_vertex_ao = true;
uniform bool hide_until_reveal = false;   // hidden in the fog until uw_reveal.x, like the wall (0 -> 0.3)

varying vec3 wpos;
varying vec3 wnrm;
varying float vao;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vao = use_vertex_ao ? COLOR.r : 1.0;
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
	float ao = mix(1.0, vao, 0.85);
	ALBEDO = col * ao * uw_albedo_light(wpos.y);
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	EMISSION = emission_color * emission_energy + uw_ambient_glow(normalize(wnrm), vw, wpos.y) * ao;
	vec4 f = uw_fog_eval(CAMERA_POSITION_WORLD, wpos);
	if (hide_until_reveal) {
		f.a = max(f.a, (1.0 - smoothstep(0.0, 0.3, uw_reveal.x)) * smoothstep(110.0, 240.0, length(CAMERA_POSITION_WORLD - wpos)));
	}
	FOG = f;
}
